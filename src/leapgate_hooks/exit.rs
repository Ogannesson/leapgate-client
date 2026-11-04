//! The controller's exit mapping (phase 4 contract 03 §3.6): a local SOCKS5 / HTTP CONNECT
//! proxy on 127.0.0.1 whose connections each become a channel of one multiplexed tunnel to the
//! exit. The handshake and the decisions live in `leapgate::exit`; this is the upstream glue.

#[cfg(not(any(target_os = "android", target_os = "ios")))]
use crate::{
    client::{Data, Interface},
    port_forward::{connect_and_login_mux, take_socket},
    port_forward_mux::{Claim, Tunnel, MAX_CHANNELS},
    ui_session_interface::{InvokeUiSession, Session},
};
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use hbb_common::{
    log, tcp, throttled_log,
    tokio::{self, net::TcpStream, sync::mpsc},
    tokio_util::codec::{BytesCodec, Framed},
};
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use leapgate::exit::{
    self, after_login,
    proxy::{self, Request},
    LoginEnd, Next,
};
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use std::time::{Duration, Instant};

#[cfg(not(any(target_os = "android", target_os = "ios")))]
const LOG_INTERVAL: Duration = Duration::from_secs(60);

/// Hook at the top of `main_get_common`.
#[cfg(feature = "flutter")]
pub(crate) fn get_common(key: &str) -> Option<String> {
    (key == leapgate::exit::directory::KEY).then(directory_json)
}

/// frb calls `main_get_common` on its own worker thread, outside any runtime.
#[cfg(feature = "flutter")]
#[hbb_common::tokio::main(flavor = "current_thread", crate = "hbb_common::tokio")]
async fn directory_json() -> String {
    leapgate::exit::directory::fetch(|k| crate::ui_interface::get_option(k)).await
}

/// Hook at the top of `start_one_port_forward`, for the mapping whose target is the sentinel.
/// The tunnel is set up lazily by the first local connection and kept while the window is open.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub(crate) async fn run<T: InvokeUiSession>(
    handler: Session<T>,
    port: i32,
    mut receiver: mpsc::UnboundedReceiver<Data>,
    key: &str,
    token: &str,
) {
    // M5: a session the new UI added for an exit card runs as that card.
    if let Some((gen, ctl)) = cards::take(&handler.get_id()) {
        return cards::run_card(handler, gen, port, receiver, ctl, key, token).await;
    }
    // A10: loopback only, no SO_REUSEADDR, no other port when this one is taken.
    let listener = match tcp::new_listener(format!("127.0.0.1:{}", port), false).await {
        Ok(listener) => listener,
        Err(err) => {
            handler.on_error(&format!("Failed to listen on {}: {}", port, err));
            return;
        }
    };
    log::info!("leapgate exit: listening on 127.0.0.1:{}", port);
    let tunnel = Tunnel::new();
    let (ready_tx, mut ready) = mpsc::channel::<(TcpStream, Request)>(MAX_CHANNELS);
    let mut cooldown = None;
    loop {
        tokio::select! {
            Ok((mut socket, _)) = listener.accept() => {
                // Off the loop, so a slow local program holds up no one else.
                let ready_tx = ready_tx.clone();
                tokio::spawn(async move {
                    match proxy::accept(&mut socket).await {
                        Ok(req) => {
                            // Fails only once the listener has closed, which drops the socket.
                            let _ = ready_tx.send((socket, req)).await;
                        }
                        Err(why) => throttled_log!(LOG_INTERVAL, info, "leapgate exit: local handshake refused ({:?})", why),
                    }
                });
            }
            Some((socket, req)) = ready.recv() => {
                if !serve(&handler, &tunnel, &mut cooldown, &mut receiver, &mut ready, socket, req, key, token).await {
                    break;
                }
            }
            d = receiver.recv() => match d {
                Some(Data::Close) | None => break,
                _ => {}
            },
        }
    }
}

/// One handshaken local connection. Establishing the tunnel is awaited right here, as upstream's
/// `establish_tunnel` is: meanwhile new connections wait in the accept backlog and handshaken
/// ones in `ready` (A6, C9). `false` closes the listener.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
async fn serve<T: InvokeUiSession>(
    handler: &Session<T>,
    tunnel: &Tunnel,
    cooldown: &mut Option<Instant>,
    receiver: &mut mpsc::UnboundedReceiver<Data>,
    ready: &mut mpsc::Receiver<(TcpStream, Request)>,
    socket: TcpStream,
    req: Request,
    key: &str,
    token: &str,
) -> bool {
    log::trace!("leapgate exit: channel {}:{}", req.host, req.port);
    let (handle, mut socket, prebuf) = match tunnel.claim() {
        Claim::Muxed(handle) => (handle, socket, req.leftover),
        _ => {
            let mut socket = socket;
            if cooldown.map_or(false, |until| Instant::now() < until) {
                let _ = proxy::reply(&mut socket, req.kind, false).await;
                throttled_log!(
                    LOG_INTERVAL,
                    info,
                    "leapgate exit: local connection refused, retrying after cooldown"
                );
                return true;
            }
            let mut forward = Framed::new(socket, BytesCodec::new());
            let mut cancelled = false;
            let res = connect_and_login_mux(
                &handler.get_id(),
                &handler.password,
                receiver,
                handler.clone(),
                &mut forward,
                key,
                token,
                false,
                &mut cancelled,
                exit::SENTINEL_HOST,
                exit::SENTINEL_PORT,
            )
            .await;
            let end = match &res {
                Ok(Some(o)) => LoginEnd::Peer {
                    mux: o.mux,
                    exit: peer_has_exit(handler),
                    secured: o.stream.is_secured(),
                },
                Ok(None) => LoginEnd::Refused,
                Err(_) => LoginEnd::Failed,
            };
            match after_login(end) {
                Next::Use => {
                    let Ok(Some(o)) = res else { return true };
                    let direct = handler.lc.read().unwrap().direct == Some(true);
                    // F4: the row shows direct or relayed. The stream type label is gone by now.
                    handler.set_connection_type(true, direct, "");
                    log::info!(
                        "leapgate exit: tunnel up ({})",
                        if direct { "direct" } else { "relayed" }
                    );
                    let handle = tunnel.set_muxed(o.stream, handler.clone(), o.kcp);
                    if o.local_eof {
                        return true;
                    }
                    let (socket, prebuf) = take_socket(forward, [req.leftover, o.prebuf].concat());
                    (handle, socket, prebuf)
                }
                Next::Stop(msg) => {
                    // As K0: the KCP guard outlives the refused session so its close reaches the peer.
                    if let Ok(Some(o)) = res {
                        drop(o.stream);
                        tokio::spawn(crate::port_forward::release_kcp(o.kcp));
                    }
                    refuse(forward.get_mut(), req.kind, ready).await;
                    if let Some(msg) = msg {
                        handler.on_error(msg);
                    }
                    log::info!("leapgate exit: tunnel refused, listener closed");
                    return false;
                }
                Next::Cooldown => {
                    refuse(forward.get_mut(), req.kind, ready).await;
                    *cooldown = Some(Instant::now() + exit::RETRY_COOLDOWN);
                    let err = res.err().map(|e| e.to_string()).unwrap_or_default();
                    throttled_log!(
                        LOG_INTERVAL,
                        info,
                        "leapgate exit: tunnel failed, retrying after cooldown: {}",
                        err
                    );
                    handler.on_establish_connection_error(err);
                    return true;
                }
            }
        }
    };
    // C5 (A): the local program hears success first; a refusal by the exit closes the channel.
    if proxy::reply(&mut socket, req.kind, true).await.is_ok()
        && handle
            .open(&req.host, i32::from(req.port), socket, prebuf)
            .is_err()
    {
        throttled_log!(
            LOG_INTERVAL,
            info,
            "leapgate exit: local connection dropped, tunnel unavailable"
        );
    }
    true
}

/// Fails this connection and every handshaken one waiting behind it.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
async fn refuse(
    socket: &mut TcpStream,
    kind: proxy::Kind,
    ready: &mut mpsc::Receiver<(TcpStream, Request)>,
) {
    let _ = proxy::reply(socket, kind, false).await;
    while let Ok((mut socket, req)) = ready.try_recv() {
        let _ = proxy::reply(&mut socket, req.kind, false).await;
    }
}

/// Upstream stored the peer's `PeerInfo` when the login ended.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn peer_has_exit<T: InvokeUiSession>(handler: &Session<T>) -> bool {
    handler
        .lc
        .read()
        .unwrap()
        .peer_info
        .as_ref()
        .and_then(|pi| pi.features.as_ref())
        .map_or(false, |f| f.leapgate_exit)
}

/// The new UI's exit cards (M5, `LEAPGATE.md` §10.12). `leapgate_exit_session_add` registers a
/// card and adds a session with the exit mapping alone; that session's `run` becomes `run_card`,
/// which logs in as soon as it listens, reports its state on one event stream for all cards, and
/// takes retries and port changes. The lazy `run` above stays the old UI's.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub(crate) mod cards {
    use super::*;
    use crate::port_forward::{release_kcp, LoginOutcome};
    #[cfg(feature = "flutter")]
    use flutter_rust_bridge::StreamSink;
    use hbb_common::{tokio::net::TcpListener, ResultType};
    use leapgate::exit::card::{self, Cause, State, Transport};
    #[cfg(any(feature = "flutter", test))]
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::{collections::BTreeMap, sync::Mutex};

    // Sent only by the new UI's exports.
    #[cfg_attr(not(any(feature = "flutter", test)), allow(dead_code))]
    pub(crate) enum Ctl {
        Retry,
        SetPort(i32),
    }

    struct Card {
        /// Tells this card from a later one for the same device whose session was added while
        /// this one was still closing.
        gen: u64,
        /// The exit session's ID, carried by every event so the UI can tell the cards apart too.
        session_id: String,
        /// The last event, sent again to a new subscriber.
        last: Option<String>,
        #[cfg(any(feature = "flutter", test))]
        ctl: mpsc::UnboundedSender<Ctl>,
        /// Taken by the card's `run`.
        ctl_rx: Option<mpsc::UnboundedReceiver<Ctl>>,
    }

    static CARDS: Mutex<BTreeMap<String, Card>> = Mutex::new(BTreeMap::new());
    #[cfg(any(feature = "flutter", test))]
    static NEXT_GEN: AtomicU64 = AtomicU64::new(0);
    #[cfg(feature = "flutter")]
    static EVENTS: Mutex<Option<StreamSink<String>>> = Mutex::new(None);

    /// E3: a port forward session with the exit mapping alone. As upstream's `session_add`, with
    /// the mapping in `args` so `io_loop` starts only it and leaves the device's saved mappings
    /// alone, and without `LocalConfig::set_remote_id`: the connect box keeps its last ID.
    #[cfg(feature = "flutter")]
    pub(crate) fn session_add(
        session_id: &crate::flutter_ffi::SessionID,
        id: &str,
        port: i32,
        password: String,
        is_shared_password: bool,
        conn_token: Option<String>,
        force_relay: bool,
    ) -> String {
        use crate::flutter::{get_adapter_luid, sessions, FlutterHandler};
        use hbb_common::{rendezvous_proto::ConnType, serde_json::json};
        use std::sync::{atomic::AtomicUsize, Arc, RwLock};
        if !(1..=65535).contains(&port) {
            return json!({ "error": "invalid_port" }).to_string();
        }
        if sessions::get_session_by_peer_id(id.to_owned(), ConnType::PORT_FORWARD).is_some() {
            return json!({ "error": "already" }).to_string();
        }
        if sessions::get_session_by_session_id(session_id).is_some() {
            return json!({ "error": "other", "text": "same session id is found" }).to_string();
        }
        let (preset_password, shared_password) = if is_shared_password {
            (String::new(), Some(password))
        } else {
            (password, None)
        };
        let session: Session<FlutterHandler> = Session {
            password: preset_password,
            args: vec![
                port.to_string(),
                exit::SENTINEL_HOST.to_owned(),
                exit::SENTINEL_PORT.to_string(),
            ],
            server_keyboard_enabled: Arc::new(RwLock::new(true)),
            server_file_transfer_enabled: Arc::new(RwLock::new(true)),
            server_clipboard_enabled: Arc::new(RwLock::new(true)),
            reconnect_count: Arc::new(AtomicUsize::new(0)),
            ..Default::default()
        };
        session.lc.write().unwrap().initialize(
            id.to_owned(),
            ConnType::PORT_FORWARD,
            None,
            force_relay,
            get_adapter_luid(),
            shared_password,
            conn_token,
        );
        // The card is keyed on the ID the UI passed and found again by the session's ID, which
        // `initialize` rewrites for `ID@server?key=…` and a trailing `/r`.
        if session.get_id() != id {
            return json!({ "error": "invalid_id" }).to_string();
        }
        register(id, session_id.to_string());
        sessions::insert_session(*session_id, ConnType::PORT_FORWARD, Arc::new(session));
        "{}".to_owned()
    }

    /// Replaces a card left by a session that never started.
    #[cfg(any(feature = "flutter", test))]
    pub(crate) fn register(id: &str, session_id: String) {
        let (ctl, ctl_rx) = mpsc::unbounded_channel();
        let card = Card {
            gen: NEXT_GEN.fetch_add(1, Ordering::Relaxed),
            session_id,
            last: None,
            ctl,
            ctl_rx: Some(ctl_rx),
        };
        CARDS.lock().unwrap().insert(id.to_owned(), card);
    }

    pub(crate) fn take(id: &str) -> Option<(u64, mpsc::UnboundedReceiver<Ctl>)> {
        let mut cards = CARDS.lock().unwrap();
        let card = cards.get_mut(id)?;
        Some((card.gen, card.ctl_rx.take()?))
    }

    /// `false` when there is no such card.
    #[cfg(any(feature = "flutter", test))]
    pub(crate) fn retry(id: &str) -> bool {
        send(id, Ctl::Retry)
    }

    #[cfg(any(feature = "flutter", test))]
    pub(crate) fn set_port(id: &str, port: i32) -> bool {
        (1..=65535).contains(&port) && send(id, Ctl::SetPort(port))
    }

    #[cfg(any(feature = "flutter", test))]
    fn send(id: &str, ctl: Ctl) -> bool {
        CARDS
            .lock()
            .unwrap()
            .get(id)
            .map_or(false, |card| card.ctl.send(ctl).is_ok())
    }

    /// Each card's current state first, then every change.
    #[cfg(feature = "flutter")]
    pub(crate) fn set_events(sink: StreamSink<String>) {
        let cards = CARDS.lock().unwrap();
        for event in cards.values().filter_map(|card| card.last.as_ref()) {
            sink.add(event.clone());
        }
        *EVENTS.lock().unwrap() = Some(sink);
    }

    fn push(id: &str, gen: u64, port: i32, state: &State) {
        let mut cards = CARDS.lock().unwrap();
        let Some(card) = cards.get_mut(id).filter(|card| card.gen == gen) else {
            return;
        };
        let event = card::event(id, &card.session_id, port, state);
        #[cfg(feature = "flutter")]
        if let Some(sink) = EVENTS.lock().unwrap().as_ref() {
            sink.add(event.clone());
        }
        if *state == State::Closed {
            cards.remove(id);
        } else {
            card.last = Some(event);
        }
    }

    /// What the card loop needs from its session: the app's `Session`, a fake in the tests.
    #[async_trait::async_trait]
    pub(crate) trait CardSession: Interface {
        /// `connect_and_login_mux` to the exit, and whether the insecure-connection prompt was
        /// turned down.
        async fn login(
            &self,
            ui: &mut mpsc::UnboundedReceiver<Data>,
            forward: &mut Framed<TcpStream, BytesCodec>,
            key: &str,
            token: &str,
        ) -> (ResultType<Option<LoginOutcome>>, bool);
        /// F4: the session's connection-ready event, after which the UI reads the path.
        fn tunnel_up(&self, direct: bool);
    }

    #[async_trait::async_trait]
    impl<T: InvokeUiSession> CardSession for Session<T> {
        async fn login(
            &self,
            ui: &mut mpsc::UnboundedReceiver<Data>,
            forward: &mut Framed<TcpStream, BytesCodec>,
            key: &str,
            token: &str,
        ) -> (ResultType<Option<LoginOutcome>>, bool) {
            let mut insecure_refused = false;
            let res = connect_and_login_mux(
                &self.get_id(),
                &self.password,
                ui,
                self.clone(),
                forward,
                key,
                token,
                false,
                &mut insecure_refused,
                exit::SENTINEL_HOST,
                exit::SENTINEL_PORT,
            )
            .await;
            (res, insecure_refused)
        }

        fn tunnel_up(&self, direct: bool) {
            self.set_connection_type(true, direct, "");
        }
    }

    pub(crate) async fn run_card<S: CardSession>(
        session: S,
        gen: u64,
        mut port: i32,
        mut receiver: mpsc::UnboundedReceiver<Data>,
        mut ctl: mpsc::UnboundedReceiver<Ctl>,
        key: &str,
        token: &str,
    ) {
        let id = session.get_id();
        let report = |port: i32, state: State| push(&id, gen, port, &state);
        let tunnel = Tunnel::new();
        let (ready_tx, mut ready) = mpsc::channel::<(TcpStream, Request)>(MAX_CHANNELS);
        let mut cooldown: Option<Instant> = None;
        // `Some(direct)` while the tunnel is up.
        let mut up: Option<bool> = None;
        let mut listener = listen(port).await;
        // E1: log in as soon as the listener is up; a taken port waits for another.
        let mut login_now = listener.is_some();
        if !login_now {
            report(port, State::PortInUse);
        }
        loop {
            // The local connection a lazy login is for (C9); none when the card logs in itself.
            let mut waiting = None;
            if !login_now {
                tokio::select! {
                    Ok(socket) = accept(&listener) => {
                        handshake(socket, ready_tx.clone());
                        continue;
                    }
                    Some((mut socket, req)) = ready.recv() => match tunnel.claim() {
                        Claim::Muxed(handle) => {
                            // C5 (A), as `serve`.
                            if proxy::reply(&mut socket, req.kind, true).await.is_ok()
                                && handle.open(&req.host, i32::from(req.port), socket, req.leftover).is_err()
                            {
                                throttled_log!(LOG_INTERVAL, info, "leapgate exit: local connection dropped, tunnel unavailable");
                            }
                            continue;
                        }
                        _ if listener.is_none() || cooldown.map_or(false, |until| Instant::now() < until) => {
                            let _ = proxy::reply(&mut socket, req.kind, false).await;
                            continue;
                        }
                        _ => waiting = Some((socket, req)),
                    },
                    _ = tunnel.ended(), if up.is_some() => {
                        up = None;
                        // No listener: a port change failed while the tunnel was up.
                        if listener.is_none() {
                            report(port, State::PortInUse);
                        } else {
                            report(port, State::Interrupted { cause: Cause::TunnelEnded, retry_after_ms: None });
                        }
                        continue;
                    }
                    Some(c) = ctl.recv() => {
                        if let Ctl::SetPort(new_port) = c {
                            // M5-5: the old listener goes first, so the same port can be set again;
                            // the tunnel stays.
                            listener = None;
                            port = new_port;
                        }
                        if listener.is_none() {
                            listener = listen(port).await;
                            if listener.is_none() {
                                report(port, State::PortInUse);
                                continue;
                            }
                        }
                        if let Some(direct) = up {
                            report(port, in_use(direct));
                            continue;
                        }
                        // M5-7: retry, or a listener without a tunnel, logs in now.
                    }
                    d = receiver.recv() => match d {
                        Some(Data::Close) | None => break,
                        _ => continue,
                    },
                }
            }
            login_now = false;
            // A lazy login can start before `ended` has been seen for the last tunnel.
            up = None;
            cooldown = None;
            report(port, State::Connecting);
            // M5-4: the login pre-reads from a local socket and the card's own login has none. It
            // gets one end of a loopback pair of its own, not a connection to the card's port: a
            // program already pointed at the port could be accepted in its place, and the
            // placeholder must not go through the proxy handshake or get a channel. Both ends are
            // dropped once the login returns.
            let (mut forward, req, placeholder) = match waiting {
                Some((socket, req)) => (Framed::new(socket, BytesCodec::new()), Some(req), None),
                None => match loopback_pair().await {
                    Ok((ours, theirs)) => (Framed::new(theirs, BytesCodec::new()), None, Some(ours)),
                    Err(err) => {
                        log::warn!("leapgate exit: no loopback socket for the login: {}", err);
                        cooldown = Some(Instant::now() + exit::RETRY_COOLDOWN);
                        report(port, login_failed());
                        continue;
                    }
                },
            };
            let Some((res, insecure_refused)) =
                login_or_close(&session, &mut receiver, &mut listener, &mut forward, key, token).await
            else {
                break;
            };
            drop(placeholder);
            let end = match &res {
                Ok(Some(o)) => LoginEnd::Peer {
                    mux: o.mux,
                    exit: has_exit(&session),
                    secured: o.stream.is_secured(),
                },
                Ok(None) => LoginEnd::Refused,
                Err(_) => LoginEnd::Failed,
            };
            match after_login(end) {
                Next::Use => {
                    let Ok(Some(o)) = res else { continue };
                    let direct = session.get_lch().read().unwrap().direct == Some(true);
                    session.tunnel_up(direct);
                    log::info!(
                        "leapgate exit: card tunnel up ({})",
                        if direct { "direct" } else { "relayed" }
                    );
                    let handle = tunnel.set_muxed(o.stream, session.clone(), o.kcp);
                    up = Some(direct);
                    report(port, in_use(direct));
                    if let Some(req) = req.filter(|_| !o.local_eof) {
                        let (mut socket, prebuf) =
                            take_socket(forward, [req.leftover, o.prebuf].concat());
                        if proxy::reply(&mut socket, req.kind, true).await.is_ok()
                            && handle
                                .open(&req.host, i32::from(req.port), socket, prebuf)
                                .is_err()
                        {
                            throttled_log!(
                                LOG_INTERVAL,
                                info,
                                "leapgate exit: local connection dropped, tunnel unavailable"
                            );
                        }
                    }
                }
                Next::Stop(msg) => {
                    // As K0 and `serve`.
                    if let Ok(Some(o)) = res {
                        drop(o.stream);
                        tokio::spawn(release_kcp(o.kcp));
                    }
                    refuse_all(forward.get_mut(), req.as_ref(), &mut ready).await;
                    listener = None;
                    if let Some(msg) = msg {
                        session.on_error(msg);
                    }
                    log::info!("leapgate exit: card tunnel refused, listener closed");
                    report(port, card::stopped(msg, insecure_refused));
                }
                Next::Cooldown => {
                    refuse_all(forward.get_mut(), req.as_ref(), &mut ready).await;
                    cooldown = Some(Instant::now() + exit::RETRY_COOLDOWN);
                    let err = res.err().map(|e| e.to_string()).unwrap_or_default();
                    throttled_log!(
                        LOG_INTERVAL,
                        info,
                        "leapgate exit: card tunnel failed, retrying after cooldown: {}",
                        err
                    );
                    session.on_establish_connection_error(err);
                    report(port, login_failed());
                }
            }
        }
        drop(listener);
        drop(tunnel);
        log::info!("leapgate exit: card closed");
        report(port, State::Closed);
    }

    /// The login, raced against the session's close: upstream's login loop drops `Close`. `None`
    /// when closed: the listener goes at once and the login is told by its receiver closing, so
    /// it closes the connection itself. Dropping the login would drop a KCP guard with it, and
    /// the peer, its prompt up, would hear nothing until its own timeouts.
    async fn login_or_close<S: CardSession>(
        session: &S,
        receiver: &mut mpsc::UnboundedReceiver<Data>,
        listener: &mut Option<TcpListener>,
        forward: &mut Framed<TcpStream, BytesCodec>,
        key: &str,
        token: &str,
    ) -> Option<(ResultType<Option<LoginOutcome>>, bool)> {
        let (tx, mut rx) = mpsc::unbounded_channel();
        let login = session.login(&mut rx, forward, key, token);
        tokio::pin!(login);
        loop {
            tokio::select! {
                res = &mut login => return Some(res),
                d = receiver.recv() => match d {
                    Some(Data::Close) | None => break,
                    Some(d) => {
                        let _ = tx.send(d);
                    }
                },
            }
        }
        *listener = None;
        drop(tx);
        // A login that finished as the close came still holds its KCP guard: as K0.
        if let (Ok(Some(o)), _) = login.await {
            drop(o.stream);
            release_kcp(o.kcp).await;
        }
        None
    }

    /// A10, as `run`.
    async fn listen(port: i32) -> Option<TcpListener> {
        match tcp::new_listener(format!("127.0.0.1:{}", port), false).await {
            Ok(listener) => {
                log::info!("leapgate exit: card listening on 127.0.0.1:{}", port);
                Some(listener)
            }
            Err(err) => {
                log::info!("leapgate exit: card cannot listen on {}: {}", port, err);
                None
            }
        }
    }

    async fn accept(listener: &Option<TcpListener>) -> std::io::Result<TcpStream> {
        match listener {
            Some(listener) => listener.accept().await.map(|(socket, _)| socket),
            None => std::future::pending().await,
        }
    }

    /// As `run`: off the loop, so a slow local program holds up no one else.
    fn handshake(mut socket: TcpStream, ready: mpsc::Sender<(TcpStream, Request)>) {
        tokio::spawn(async move {
            match proxy::accept(&mut socket).await {
                Ok(req) => {
                    let _ = ready.send((socket, req)).await;
                }
                Err(why) => throttled_log!(
                    LOG_INTERVAL,
                    info,
                    "leapgate exit: local handshake refused ({:?})",
                    why
                ),
            }
        });
    }

    async fn loopback_pair() -> std::io::Result<(TcpStream, TcpStream)> {
        let listener = TcpListener::bind("127.0.0.1:0").await?;
        let ours = TcpStream::connect(listener.local_addr()?).await?;
        let (theirs, _) = listener.accept().await?;
        Ok((ours, theirs))
    }

    /// Fails the connection a lazy login was for, if any, and every handshaken one waiting.
    async fn refuse_all(
        socket: &mut TcpStream,
        req: Option<&Request>,
        ready: &mut mpsc::Receiver<(TcpStream, Request)>,
    ) {
        if let Some(req) = req {
            let _ = proxy::reply(socket, req.kind, false).await;
        }
        while let Ok((mut socket, req)) = ready.try_recv() {
            let _ = proxy::reply(&mut socket, req.kind, false).await;
        }
    }

    fn in_use(direct: bool) -> State {
        let transport = if direct {
            Transport::Direct
        } else {
            Transport::Relay
        };
        State::InUse { transport }
    }

    fn login_failed() -> State {
        State::Interrupted {
            cause: Cause::LoginFailed,
            retry_after_ms: Some(exit::RETRY_COOLDOWN.as_millis() as u64),
        }
    }

    fn has_exit(session: &impl Interface) -> bool {
        session
            .get_lch()
            .read()
            .unwrap()
            .peer_info
            .as_ref()
            .and_then(|pi| pi.features.as_ref())
            .map_or(false, |f| f.leapgate_exit)
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        use crate::{client::LoginConfigHandler, kcp_stream::KcpStream};
        use base::message_proto::*;
        use hbb_common::{
            anyhow::anyhow,
            protobuf::{Message as _, MessageField},
            sodiumoxide::crypto::secretbox,
            tcp::FramedStream,
            timeout,
            tokio::{
                io::{AsyncReadExt, AsyncWriteExt},
                net::UdpSocket,
            },
            Stream,
        };
        use std::{
            collections::VecDeque,
            sync::{Arc, RwLock},
        };

        /// What the next login answers.
        enum Login {
            Use(Stream, bool),
            /// A peer without the exit feature, over this stream and KCP guard.
            NotExit(Stream, Option<KcpStream>),
            Refused { insecure: bool },
            Fail,
            /// Logging in until the session closes, then closing this connection as
            /// `connect_and_login_mux` does, its KCP guard kept for the FIN.
            Hang(Option<(KcpStream, Stream)>),
        }

        #[derive(Clone)]
        struct Fake {
            id: String,
            lc: Arc<RwLock<LoginConfigHandler>>,
            logins: Arc<Mutex<VecDeque<Login>>>,
        }

        #[async_trait::async_trait]
        impl Interface for Fake {
            fn send(&self, _data: Data) {}
            fn msgbox(&self, _msgtype: &str, _title: &str, _text: &str, _link: &str) {}
            fn handle_login_error(&self, _err: &str) -> bool {
                false
            }
            fn handle_peer_info(&self, _pi: PeerInfo) {}
            fn set_multiple_windows_session(&self, _sessions: Vec<WindowsSession>) {}
            async fn handle_hash(&self, _pass: &str, _hash: Hash, _peer: &mut Stream) -> bool {
                false
            }
            async fn handle_login_from_ui(
                &self,
                _os_username: String,
                _os_password: String,
                _password: String,
                _remember: bool,
                _peer: &mut Stream,
            ) {
            }
            async fn handle_test_delay(&self, _t: TestDelay, _peer: &mut Stream) {}
            fn get_lch(&self) -> Arc<RwLock<LoginConfigHandler>> {
                self.lc.clone()
            }
            fn get_id(&self) -> String {
                self.id.clone()
            }
        }

        #[async_trait::async_trait]
        impl CardSession for Fake {
            async fn login(
                &self,
                ui: &mut mpsc::UnboundedReceiver<Data>,
                _forward: &mut Framed<TcpStream, BytesCodec>,
                _key: &str,
                _token: &str,
            ) -> (ResultType<Option<LoginOutcome>>, bool) {
                let next = self.logins.lock().unwrap().pop_front();
                let outcome = |stream, kcp| LoginOutcome {
                    stream,
                    mux: true,
                    prebuf: Vec::new(),
                    local_eof: false,
                    kcp,
                };
                match next {
                    Some(Login::Use(stream, direct)) => {
                        let mut lc = self.lc.write().unwrap();
                        lc.direct = Some(direct);
                        lc.peer_info = Some(PeerInfo {
                            features: MessageField::some(Features {
                                leapgate_exit: true,
                                ..Default::default()
                            }),
                            ..Default::default()
                        });
                        drop(lc);
                        (Ok(Some(outcome(stream, None))), false)
                    }
                    Some(Login::NotExit(stream, kcp)) => {
                        self.lc.write().unwrap().peer_info = Some(PeerInfo::default());
                        (Ok(Some(outcome(stream, kcp))), false)
                    }
                    Some(Login::Refused { insecure }) => (Ok(None), insecure),
                    Some(Login::Fail) => (Err(anyhow!("Timeout")), false),
                    Some(Login::Hang(conn)) => {
                        while ui.recv().await.is_some() {}
                        if let Some((guard, stream)) = conn {
                            drop(stream);
                            release_kcp(Some(guard)).await;
                        }
                        (Ok(None), false)
                    }
                    None => std::future::pending().await,
                }
            }

            fn tunnel_up(&self, _direct: bool) {}
        }

        fn start(id: &str, port: i32, logins: Vec<Login>) -> mpsc::UnboundedSender<Data> {
            register(id, format!("session-{}", id));
            let (gen, ctl) = take(id).unwrap();
            let fake = Fake {
                id: id.to_owned(),
                lc: Default::default(),
                logins: Arc::new(Mutex::new(logins.into())),
            };
            let (tx, rx) = mpsc::unbounded_channel();
            tokio::spawn(run_card(fake, gen, port, rx, ctl, "", ""));
            tx
        }

        fn last(id: &str) -> Option<String> {
            CARDS.lock().unwrap().get(id).and_then(|card| card.last.clone())
        }

        async fn wait_for(id: &str, want: &str) {
            let deadline = Instant::now() + Duration::from_secs(5);
            while !last(id).is_some_and(|event| event.contains(want)) {
                assert!(Instant::now() < deadline, "no {} for {}: {:?}", want, id, last(id));
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        }

        async fn wait_closed(id: &str) {
            let deadline = Instant::now() + Duration::from_secs(1);
            while CARDS.lock().unwrap().contains_key(id) {
                assert!(Instant::now() < deadline, "{} still open: {:?}", id, last(id));
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        }

        fn free_port() -> i32 {
            let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
            listener.local_addr().unwrap().port() as i32
        }

        /// Asked by connecting: a bind would also fail while a channel still holds a connection
        /// accepted on the port. A closed port times out (Windows retries the SYN on loopback).
        async fn listening(port: i32) -> bool {
            let connect = TcpStream::connect(("127.0.0.1", port as u16));
            matches!(timeout(500, connect).await, Ok(Ok(_)))
        }

        /// On Windows a dropped listener has gone on accepting for up to about a second under the
        /// load of the whole test run.
        async fn wait_not_listening(port: i32) {
            let deadline = Instant::now() + Duration::from_secs(3);
            while listening(port).await {
                assert!(Instant::now() < deadline, "port {} still listening", port);
            }
        }

        /// An encrypted pair, as a login over a secured connection leaves it.
        async fn secured_pair() -> (Stream, Stream) {
            let (a, b) = loopback_pair().await.unwrap();
            let addr = a.peer_addr().unwrap();
            let key = secretbox::gen_key();
            let mut ours = Stream::Tcp(FramedStream::from(a, addr));
            let mut theirs = Stream::Tcp(FramedStream::from(b, addr));
            ours.set_key(key.clone());
            theirs.set_key(key);
            (ours, theirs)
        }

        async fn kcp_pair() -> ((KcpStream, Stream), (KcpStream, Stream)) {
            let a = UdpSocket::bind("127.0.0.1:0").await.unwrap();
            let b = UdpSocket::bind("127.0.0.1:0").await.unwrap();
            a.connect(b.local_addr().unwrap()).await.unwrap();
            b.connect(a.local_addr().unwrap()).await.unwrap();
            let (ours, theirs) = tokio::join!(
                KcpStream::connect(Arc::new(a), Duration::from_secs(5)),
                KcpStream::accept(Arc::new(b), Duration::from_secs(5), None),
            );
            (ours.unwrap(), theirs.unwrap())
        }

        /// A SOCKS5 CONNECT to example.com:443 through the card's port.
        async fn socks5(port: i32) -> TcpStream {
            let mut s = TcpStream::connect(("127.0.0.1", port as u16)).await.unwrap();
            s.write_all(&[5, 1, 0]).await.unwrap();
            let mut method = [0u8; 2];
            s.read_exact(&mut method).await.unwrap();
            let mut req = vec![5, 1, 0, 3, 11];
            req.extend_from_slice(b"example.com");
            req.extend_from_slice(&443u16.to_be_bytes());
            s.write_all(&req).await.unwrap();
            s
        }

        /// The host of the next frame, which must be a channel open.
        async fn next_open(peer: &mut Stream) -> String {
            let bytes = timeout(5000, peer.next()).await.unwrap().unwrap().unwrap();
            match Message::parse_from_bytes(&bytes).unwrap().union {
                Some(message::Union::PortForwardChannel(PortForwardChannel {
                    union: Some(port_forward_channel::Union::Open(open)),
                    ..
                })) => open.host,
                other => panic!("expected a channel open, got {:?}", other),
            }
        }

        #[tokio::test]
        async fn a_card_logs_in_as_it_listens_and_shows_its_tunnel_end() {
            let (id, port) = ("card-use", free_port());
            let (ours, mut peer) = secured_pair().await;
            let close = start(id, port, vec![Login::Use(ours, true)]);
            wait_for(id, r#""state":"in_use","transport":"direct""#).await;
            assert!(last(id).unwrap().contains(r#""session_id":"session-card-use""#));
            // The placeholder got no channel: the first open is the local program's.
            let _app = socks5(port).await;
            assert_eq!(next_open(&mut peer).await, "example.com");
            drop(peer);
            wait_for(id, r#""state":"interrupted","cause":"tunnel_ended""#).await;
            assert!(listening(port).await);
            close.send(Data::Close).unwrap();
            wait_closed(id).await;
            wait_not_listening(port).await;
        }

        #[tokio::test]
        async fn a_refused_login_stops_hands_back_the_kcp_guard_and_retry_logs_in_again() {
            let (id, port) = ("card-refused", free_port());
            let ((guard, ours), (_peer_guard, mut peer)) = kcp_pair().await;
            let (secured, _secured_peer) = secured_pair().await;
            let _close = start(
                id,
                port,
                vec![
                    Login::NotExit(ours, Some(guard)),
                    Login::Refused { insecure: true },
                    Login::Use(secured, false),
                ],
            );
            wait_for(id, r#""state":"stopped","reason":{"code":"exit_not_supported"}"#).await;
            wait_not_listening(port).await;
            // K0: the guard outlives the stream, so the peer hears the close.
            let end = timeout(5000, peer.next()).await;
            assert!(matches!(end, Ok(None) | Ok(Some(Err(_)))), "peer not closed: {:?}", end);
            assert!(retry(id));
            wait_for(id, r#""state":"stopped","reason":{"code":"exit_need_encryption"}"#).await;
            assert!(retry(id));
            wait_for(id, r#""state":"in_use","transport":"relay""#).await;
            assert!(listening(port).await);
        }

        #[tokio::test]
        async fn a_failed_login_keeps_listening_until_retry() {
            let (id, port) = ("card-failed", free_port());
            let (secured, _peer) = secured_pair().await;
            let _close = start(id, port, vec![Login::Fail, Login::Use(secured, true)]);
            wait_for(
                id,
                r#""state":"interrupted","cause":"login_failed","retry_after_ms":10000"#,
            )
            .await;
            assert!(listening(port).await);
            assert!(retry(id));
            wait_for(id, r#""state":"in_use""#).await;
        }

        #[tokio::test]
        async fn closing_mid_login_closes_the_listener_at_once() {
            let (id, port) = ("card-cancel", free_port());
            let close = start(id, port, vec![Login::Hang(None)]);
            wait_for(id, r#""state":"connecting""#).await;
            assert!(listening(port).await);
            close.send(Data::Close).unwrap();
            wait_closed(id).await;
            wait_not_listening(port).await;
            // Another program can take the port.
            assert!(std::net::TcpListener::bind(("127.0.0.1", port as u16)).is_ok());
        }

        #[tokio::test]
        async fn closing_mid_login_closes_the_peer_connection_at_once() {
            let (id, port) = ("card-cancel-peer", free_port());
            let ((guard, ours), (_peer_guard, mut peer)) = kcp_pair().await;
            let close = start(id, port, vec![Login::Hang(Some((guard, ours)))]);
            wait_for(id, r#""state":"connecting""#).await;
            close.send(Data::Close).unwrap();
            // The peer hears the close, so its accept prompt goes with it (09 §5.3 item 9).
            let end = timeout(3000, peer.next()).await;
            assert!(matches!(end, Ok(None) | Ok(Some(Err(_)))), "peer not closed: {:?}", end);
            // While the guard sees the FIN out, the port is free for the card added next.
            wait_not_listening(port).await;
        }

        #[tokio::test]
        async fn a_new_port_keeps_the_tunnel() {
            let (id, old, new) = ("card-port", free_port(), free_port());
            let (ours, mut peer) = secured_pair().await;
            let _close = start(id, old, vec![Login::Use(ours, true)]);
            wait_for(id, r#""state":"in_use""#).await;
            assert!(set_port(id, new));
            wait_for(id, &format!(r#""port":{},"state":"in_use""#, new)).await;
            wait_not_listening(old).await;
            // No second login (there is none left to answer): the same tunnel opens the channel.
            let _app = socks5(new).await;
            assert_eq!(next_open(&mut peer).await, "example.com");
        }

        #[tokio::test]
        async fn a_taken_port_waits_for_another_before_logging_in() {
            let (id, taken, free) = ("card-taken", free_port(), free_port());
            let _other = std::net::TcpListener::bind(("127.0.0.1", taken as u16)).unwrap();
            let (secured, _peer) = secured_pair().await;
            let _close = start(id, taken, vec![Login::Use(secured, true)]);
            wait_for(id, &format!(r#""port":{},"state":"port_in_use""#, taken)).await;
            assert!(set_port(id, free));
            wait_for(id, &format!(r#""port":{},"state":"in_use""#, free)).await;
        }

        #[test]
        fn controls_reach_registered_cards_only() {
            assert!(!retry("card-none"));
            register("card-ctl", String::new());
            assert!(retry("card-ctl"));
            assert!(set_port("card-ctl", 21180));
            assert!(!set_port("card-ctl", 0));
            assert!(!set_port("card-ctl", 65536));
            CARDS.lock().unwrap().remove("card-ctl");
        }
    }
}
