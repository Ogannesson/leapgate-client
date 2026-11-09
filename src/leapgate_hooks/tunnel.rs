//! The new UI's tunnel cards (M9c, `LEAPGATE.md` §10.18): a TCP tunnel card runs every saved port
//! forward of a device, an RDP card the one RDP forward. `leapgate_tunnel_session_add` registers a
//! card and adds a port forward (or RDP) session without arguments; upstream's `io_loop` hands
//! that session, and only that one, to `run` (the hook at the top of its port forward branch).
//! Each row logs in on its own connection as soon as it listens, and reports its state on one
//! event stream for all cards. The old UI never registers and keeps upstream's loop.

use super::exit::{
    cards::{accept, loopback_pair},
    listen_local,
};
use crate::{
    client::{Data, Interface, LoginConfigHandler},
    port_forward::{connect_and_login_mux, release_kcp, take_socket, LoginOutcome},
    port_forward_mux::{Claim, Tunnel},
    ui_session_interface::{InvokeUiSession, Session},
};
use base::message_proto::{Hash, PeerInfo, TestDelay, WindowsSession};
#[cfg(feature = "flutter")]
use flutter_rust_bridge::StreamSink;
use hbb_common::{
    log, throttled_log,
    tokio::{
        self,
        net::{TcpListener, TcpStream},
        sync::mpsc,
        task::JoinSet,
    },
    tokio_util::codec::{BytesCodec, Framed},
    ResultType, SessionID, Stream,
};
use leapgate::{
    exit::card::{Cause, Transport},
    tunnel::{self, after_login, Kind, LoginEnd, Next, State},
};
#[cfg(any(feature = "flutter", test))]
use std::sync::atomic::{AtomicU64, Ordering};
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    sync::{Arc, Mutex, RwLock},
    time::Duration,
};

const LOG_INTERVAL: Duration = Duration::from_secs(60);

/// Sent by the new UI's exports only.
#[cfg_attr(not(any(feature = "flutter", test)), allow(dead_code))]
pub(crate) enum Ctl {
    /// A row's local port, 0 for RDP.
    Retry(i32),
}

struct Card {
    /// Tells this card from a later one for the same device whose session was added while this
    /// one was still closing.
    gen: u64,
    /// The card's session, carried by every event and matched by `take`.
    session_id: SessionID,
    /// Each row's last state event, by local port, sent again to a new subscriber.
    rows: BTreeMap<i32, String>,
    #[cfg_attr(not(any(feature = "flutter", test)), allow(dead_code))]
    ctl: mpsc::UnboundedSender<Ctl>,
    /// Taken by the card's `run`.
    ctl_rx: Option<mpsc::UnboundedReceiver<Ctl>>,
}

/// Keyed on the device ID and the kind: a device's TCP and RDP cards are apart, and apart from
/// its exit card (`exit::cards`).
static CARDS: Mutex<BTreeMap<(String, Kind), Card>> = Mutex::new(BTreeMap::new());
#[cfg(any(feature = "flutter", test))]
static NEXT_GEN: AtomicU64 = AtomicU64::new(0);
#[cfg(feature = "flutter")]
static EVENTS: Mutex<Option<StreamSink<String>>> = Mutex::new(None);

/// What `run` takes from the registry.
pub(crate) struct Taken {
    kind: Kind,
    gen: u64,
    ctl: mpsc::UnboundedReceiver<Ctl>,
}

/// `leapgate_tunnel_session_add`: a port forward (or RDP) session without arguments, so
/// `io_loop` takes the no-argument branch and the hook hands it to `run`.
#[cfg(feature = "flutter")]
pub(crate) fn session_add(
    session_id: &crate::flutter_ffi::SessionID,
    id: &str,
    rdp: bool,
    password: String,
    is_shared_password: bool,
    conn_token: Option<String>,
    force_relay: bool,
) -> String {
    use hbb_common::rendezvous_proto::ConnType;
    let (kind, conn_type) = if rdp {
        (Kind::Rdp, ConnType::RDP)
    } else {
        (Kind::Tcp, ConnType::PORT_FORWARD)
    };
    super::exit::cards::add_session(
        session_id,
        id,
        conn_type,
        Vec::new(),
        password,
        is_shared_password,
        conn_token,
        force_relay,
        || register(id, kind, *session_id),
    )
}

/// Replaces a card left by a session that never started.
#[cfg(any(feature = "flutter", test))]
fn register(id: &str, kind: Kind, session_id: SessionID) {
    let (ctl, ctl_rx) = mpsc::unbounded_channel();
    let card = Card {
        gen: NEXT_GEN.fetch_add(1, Ordering::Relaxed),
        session_id,
        rows: BTreeMap::new(),
        ctl,
        ctl_rx: Some(ctl_rx),
    };
    CARDS.lock().unwrap().insert((id.to_owned(), kind), card);
}

/// The hook in `io_loop`: the card registered for this very session, or `None` for any other
/// port forward session (an exit card's, the old UI's, one added after the card's).
pub(crate) fn take<T: InvokeUiSession>(handler: &Session<T>) -> Option<Taken> {
    #[cfg(feature = "flutter")]
    {
        use crate::flutter::sessions;
        let kind = if handler.is_rdp() {
            Kind::Rdp
        } else {
            Kind::Tcp
        };
        // A session's `lc` is its own: the registered ID's session is this one when they share it.
        take_if(&handler.get_id(), kind, |session_id| {
            sessions::get_session_by_session_id(session_id)
                .is_some_and(|s| std::sync::Arc::ptr_eq(&s.lc, &handler.lc))
        })
    }
    #[cfg(not(feature = "flutter"))]
    {
        let _ = handler;
        None
    }
}

/// `is_session` is asked without `CARDS` held: it takes upstream's session locks.
#[cfg_attr(not(any(feature = "flutter", test)), allow(dead_code))]
fn take_if(id: &str, kind: Kind, is_session: impl FnOnce(&SessionID) -> bool) -> Option<Taken> {
    let key = (id.to_owned(), kind);
    let (gen, session_id) = {
        let cards = CARDS.lock().unwrap();
        let card = cards.get(&key)?;
        (card.gen, card.session_id)
    };
    if !is_session(&session_id) {
        return None;
    }
    let mut cards = CARDS.lock().unwrap();
    let card = cards.get_mut(&key).filter(|card| card.gen == gen)?;
    Some(Taken {
        kind,
        gen,
        ctl: card.ctl_rx.take()?,
    })
}

/// `leapgate_tunnel_retry`: `false` without such a card or row.
#[cfg_attr(not(any(feature = "flutter", test)), allow(dead_code))]
pub(crate) fn retry(session_id: &SessionID, port: i32) -> bool {
    CARDS
        .lock()
        .unwrap()
        .values()
        .find(|card| card.session_id == *session_id)
        .filter(|card| card.rows.contains_key(&port))
        .map_or(false, |card| card.ctl.send(Ctl::Retry(port)).is_ok())
}

/// Each row's last state first, then every change. A new subscription replaces the old one.
#[cfg(feature = "flutter")]
pub(crate) fn set_events(sink: StreamSink<String>) {
    let cards = CARDS.lock().unwrap();
    for event in cards.values().flat_map(|card| card.rows.values()) {
        sink.add(event.clone());
    }
    *EVENTS.lock().unwrap() = Some(sink);
}

/// A card's or a row's (`port`) event. A notice is not kept for a new subscriber.
fn push(id: &str, kind: Kind, gen: u64, port: Option<i32>, state: &State) {
    let key = (id.to_owned(), kind);
    let mut cards = CARDS.lock().unwrap();
    let Some(card) = cards.get_mut(&key).filter(|card| card.gen == gen) else {
        return;
    };
    let event = tunnel::event(id, &card.session_id.to_string(), kind, port, state);
    #[cfg(feature = "flutter")]
    if let Some(sink) = EVENTS.lock().unwrap().as_ref() {
        sink.add(event.clone());
    }
    match (state, port) {
        (State::Closed, _) => {
            cards.remove(&key);
        }
        (State::Removed, Some(port)) => {
            card.rows.remove(&port);
        }
        (State::Notice { .. }, _) | (_, None) => {}
        (_, Some(port)) => {
            card.rows.insert(port, event);
        }
    }
}

/// The card's loop, in the session's thread and runtime, in place of upstream's.
pub(crate) async fn run<T: InvokeUiSession>(
    handler: Session<T>,
    card: Taken,
    receiver: mpsc::UnboundedReceiver<Data>,
    key: &str,
    token: &str,
) {
    run_card(handler, card, receiver, key, token).await
}

/// What the card loop needs from its session: the app's `Session`, a fake in the tests.
#[async_trait::async_trait]
pub(crate) trait TunnelSession: Interface + Sync {
    /// `connect_and_login_mux` to the row's target, with `ui` as the interface, and whether the
    /// insecure-connection prompt was turned down.
    async fn login(
        &self,
        ui: RowUi<Self>,
        rx: &mut mpsc::UnboundedReceiver<Data>,
        forward: &mut Framed<TcpStream, BytesCodec>,
        key: &str,
        token: &str,
        target: &Target,
    ) -> (ResultType<Option<LoginOutcome>>, bool);
    /// Opens Remote Desktop Connection to the RDP row's local `port`.
    fn open_rdp(&self, port: u16);
}

#[async_trait::async_trait]
impl<T: InvokeUiSession> TunnelSession for Session<T> {
    fn open_rdp(&self, port: u16) {
        // The credentials this session read when it started, never the process environment:
        // upstream's RDP sessions share it, so two cards could pick up each other's.
        let (commands, name) = {
            let lc = self.lc.read().unwrap();
            let commands = rdp::commands(
                port,
                &lc.get_option("rdp_username"),
                &lc.get_option("rdp_password"),
            );
            (commands, rdp::display_name(&lc, &self.get_id()))
        };
        log::info!(
            "leapgate tunnel: opening Remote Desktop Connection to 127.0.0.1:{}",
            port
        );
        tokio::task::spawn_blocking(move || rdp::run(commands, name));
    }

    async fn login(
        &self,
        ui: RowUi<Self>,
        rx: &mut mpsc::UnboundedReceiver<Data>,
        forward: &mut Framed<TcpStream, BytesCodec>,
        key: &str,
        token: &str,
        target: &Target,
    ) -> (ResultType<Option<LoginOutcome>>, bool) {
        let mut insecure_declined = false;
        let res = connect_and_login_mux(
            &self.get_id(),
            &self.password,
            rx,
            ui,
            forward,
            key,
            token,
            target.rdp,
            &mut insecure_declined,
            &target.host,
            target.port,
        )
        .await;
        (res, insecure_declined)
    }
}

/// Upstream's `run_rdp` and `rdp_display_name` (`port_forward.rs`), with the credentials passed
/// in. Check them against upstream's on a merge.
mod rdp {
    use crate::client::LoginConfigHandler;
    use hbb_common::log;

    /// The programs to run and their arguments, in order: `cmdkey` drops the stored `localhost`
    /// credential and stores this one, if any; `mstsc` connects.
    pub(super) fn commands(
        port: u16,
        username: &str,
        password: &str,
    ) -> Vec<(&'static str, Vec<String>)> {
        let mut commands = vec![("cmdkey", vec!["/delete:localhost".to_owned()])];
        if !username.is_empty() || !password.is_empty() {
            let mut args = vec!["/generic:localhost".to_owned()];
            if !username.is_empty() {
                args.push(format!("/user:{}", username));
            }
            if !password.is_empty() {
                args.push(format!("/pass:{}", password));
            }
            commands.push(("cmdkey", args));
        }
        // As upstream, /v rather than a generated .rdp file: mstsc keeps the user's Default.rdp
        // settings and shows no unsigned-file warning.
        commands.push(("mstsc", vec![format!("/v:localhost:{}", port)]));
        commands
    }

    /// Blocking: `cmdkey` is waited for. Never run from the tests.
    pub(super) fn run(commands: Vec<(&'static str, Vec<String>)>, name: String) {
        for (program, args) in commands {
            let mut command = std::process::Command::new(program);
            command.args(&args);
            if program != "mstsc" {
                command.output().ok();
                continue;
            }
            match command.spawn() {
                Ok(child) => {
                    #[cfg(windows)]
                    crate::platform::set_rdp_window_title(child, name.clone());
                    #[cfg(not(windows))]
                    let _ = child;
                }
                Err(err) => log::warn!("leapgate tunnel: failed to launch mstsc: {}", err),
            }
        }
    }

    /// The peer's alias or ID, with its hostname.
    pub(super) fn display_name(lc: &LoginConfigHandler, id: &str) -> String {
        let alias = lc
            .options
            .get("alias")
            .map(|s| s.trim())
            .unwrap_or_default();
        let hostname = lc.info.hostname.trim();
        let identity = if !alias.is_empty() { alias } else { id };
        if hostname.is_empty() || hostname == identity {
            identity.to_owned()
        } else {
            format!("{} ({})", identity, hostname)
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        fn spelled(commands: &[(&str, Vec<String>)]) -> Vec<String> {
            commands
                .iter()
                .map(|(program, args)| format!("{} {}", program, args.join(" ")))
                .collect()
        }

        #[test]
        fn mstsc_gets_the_sessions_credentials_through_cmdkey() {
            assert_eq!(
                spelled(&commands(50123, "alice", "secret")),
                [
                    "cmdkey /delete:localhost",
                    "cmdkey /generic:localhost /user:alice /pass:secret",
                    "mstsc /v:localhost:50123",
                ]
            );
            assert_eq!(
                spelled(&commands(50123, "", "")),
                ["cmdkey /delete:localhost", "mstsc /v:localhost:50123"]
            );
        }
    }
}

/// A row's target on the peer's side. RDP's host is empty, as upstream's.
pub(crate) struct Target {
    host: String,
    port: i32,
    rdp: bool,
}

/// A row as the events name it.
#[derive(Clone)]
struct Row {
    id: String,
    kind: Kind,
    gen: u64,
    port: i32,
}

impl Row {
    fn report(&self, state: State) {
        push(&self.id, self.kind, self.gen, Some(self.port), &state);
    }
}

/// What the card loop sends a row.
enum RowCtl {
    Ui(Data),
    Retry,
}

/// The saved forwards a TCP card starts, as upstream's no-argument branch does, without the old
/// UI's exit mapping (`leapgate::exit::is_exit_target`), which upstream's exit hook would run.
fn forwarded(port: i32, host: &str, remote_port: i32) -> bool {
    port > 0 && remote_port > 0 && !leapgate::exit::is_exit_target(host, remote_port)
}

async fn run_card<S: TunnelSession>(
    session: S,
    card: Taken,
    mut receiver: mpsc::UnboundedReceiver<Data>,
    key: &str,
    token: &str,
) {
    let Taken { kind, gen, mut ctl } = card;
    let id = session.get_id();
    let mut rows = HashMap::<i32, mpsc::UnboundedSender<RowCtl>>::new();
    // Rows told to close for `RemovePortForward`, reported `removed` when done. Their ports take
    // no new row until then.
    let mut removing = HashSet::<i32>::new();
    let mut tasks = JoinSet::new();
    let start = |rows: &mut HashMap<i32, mpsc::UnboundedSender<RowCtl>>,
                 tasks: &mut JoinSet<i32>,
                 port: i32,
                 target: Target| {
        let (tx, rx) = mpsc::unbounded_channel();
        rows.insert(port, tx);
        let row = Row {
            id: id.clone(),
            kind,
            gen,
            port,
        };
        let (session, key, token) = (session.clone(), key.to_owned(), token.to_owned());
        tasks.spawn(async move {
            run_row(session, row, target, rx, key, token).await;
            port
        });
    };
    let tcp = |host: String, port: i32| Target {
        host,
        port,
        rdp: false,
    };
    log::info!("leapgate tunnel: {:?} card started", kind);
    match kind {
        Kind::Tcp => {
            let forwards = session.get_lch().read().unwrap().port_forwards.clone();
            for (port, host, remote_port) in forwards {
                if forwarded(port, &host, remote_port) && !rows.contains_key(&port) {
                    start(&mut rows, &mut tasks, port, tcp(host, remote_port));
                }
            }
        }
        Kind::Rdp => {
            // As upstream's RDP branch, without putting the credentials in the environment.
            let port = session
                .get_lch()
                .read()
                .unwrap()
                .get_option("rdp_port")
                .parse::<i32>()
                .unwrap_or(3389);
            let target = Target {
                host: String::new(),
                port,
                rdp: true,
            };
            start(&mut rows, &mut tasks, 0, target);
        }
    }
    loop {
        tokio::select! {
            d = receiver.recv() => match d {
                Some(Data::AddPortForward((port, host, remote_port))) => {
                    if kind == Kind::Tcp
                        && forwarded(port, &host, remote_port)
                        && !rows.contains_key(&port)
                        && !removing.contains(&port)
                    {
                        start(&mut rows, &mut tasks, port, tcp(host, remote_port));
                    }
                }
                Some(Data::RemovePortForward(port)) => {
                    if let Some(row) = rows.remove(&port) {
                        let _ = row.send(RowCtl::Ui(Data::Close));
                        removing.insert(port);
                    }
                }
                Some(Data::Close) | None => break,
                Some(d) => {
                    for row in rows.values() {
                        let _ = row.send(RowCtl::Ui(d.clone()));
                    }
                }
            },
            Some(Ctl::Retry(port)) = ctl.recv() => {
                if let Some(row) = rows.get(&port) {
                    let _ = row.send(RowCtl::Retry);
                }
            }
            Some(done) = tasks.join_next() => {
                if let Ok(port) = done {
                    if removing.remove(&port) {
                        push(&id, kind, gen, Some(port), &State::Removed);
                    }
                }
            }
        }
    }
    // Each row closes its listener and lets a login in progress close its connection itself.
    for row in rows.values() {
        let _ = row.send(RowCtl::Ui(Data::Close));
    }
    while tasks.join_next().await.is_some() {}
    log::info!("leapgate tunnel: {:?} card closed", kind);
    push(&id, kind, gen, None, &State::Closed);
}

/// One forward: listens, logs in at once on its own connection, and after a tunnel ends logs in
/// again for the next local connection (as an exit card, `exit::cards::run_card`, without the
/// proxy handshake, the cooldown or a port change).
async fn run_row<S: TunnelSession>(
    session: S,
    row: Row,
    target: Target,
    mut ctl: mpsc::UnboundedReceiver<RowCtl>,
    key: String,
    token: String,
) {
    let tunnel = Tunnel::new();
    // `Some(direct)` while the tunnel is up.
    let mut up: Option<bool> = None;
    let mut listener = listen(row.port, &target).await;
    let mut login_now = listener.is_some();
    if !login_now {
        row.report(State::PortInUse);
    }
    // RDP: no tunnel yet since the listener opened. The first one opens Remote Desktop
    // Connection unless a local connection (one the user opened) brought it.
    let mut fresh = true;
    loop {
        // The local connection a lazy login is for; none when the row logs in itself.
        let mut waiting = None;
        if !login_now {
            tokio::select! {
                Ok(socket) = accept(&listener) => match tunnel.claim() {
                    Claim::Muxed(handle) => {
                        if handle.open(&target.host, target.port, socket, Vec::new()).is_err() {
                            throttled_log!(LOG_INTERVAL, info, "leapgate tunnel: local connection dropped, tunnel unavailable");
                        }
                        continue;
                    }
                    _ => waiting = Some(socket),
                },
                _ = tunnel.ended(), if up.is_some() => {
                    up = None;
                    row.report(State::Interrupted { cause: Cause::TunnelEnded, reason: None });
                    continue;
                }
                c = ctl.recv() => match c {
                    Some(RowCtl::Retry) => {
                        if listener.is_none() {
                            listener = listen(row.port, &target).await;
                            if listener.is_none() {
                                row.report(State::PortInUse);
                                continue;
                            }
                            fresh = true;
                        } else if up.is_some() {
                            continue;
                        }
                        // Reopened, or interrupted: log in now.
                    }
                    Some(RowCtl::Ui(Data::NewRDP)) => {
                        if let Some(port) = local_port(&listener).filter(|_| target.rdp) {
                            session.open_rdp(port);
                        }
                        continue;
                    }
                    Some(RowCtl::Ui(Data::Close)) | None => break,
                    Some(RowCtl::Ui(_)) => continue,
                },
            }
        }
        login_now = false;
        // A lazy login can start before `ended` has been seen for the last tunnel.
        up = None;
        row.report(State::Connecting);
        // M5-4, as an exit card: a login of the row's own pre-reads from one end of a loopback pair
        // of its own, dropped once the login returns.
        let lazy = waiting.is_some();
        let (mut forward, placeholder) = match waiting {
            Some(socket) => (Framed::new(socket, BytesCodec::new()), None),
            None => match loopback_pair().await {
                Ok((ours, theirs)) => (Framed::new(theirs, BytesCodec::new()), Some(ours)),
                Err(err) => {
                    log::warn!("leapgate tunnel: no loopback socket for the login: {}", err);
                    row.report(login_failed(&err.to_string()));
                    continue;
                }
            },
        };
        let ui = RowUi::new(session.clone(), row.clone());
        let Some((res, insecure_declined)) = login_or_close(
            &session,
            ui.clone(),
            &mut ctl,
            &mut listener,
            &mut forward,
            &key,
            &token,
            &target,
        )
        .await
        else {
            break;
        };
        drop(placeholder);
        let end = match &res {
            Ok(Some(o)) => LoginEnd::Peer { mux: o.mux },
            Ok(None) => LoginEnd::Refused { insecure_declined },
            Err(_) => LoginEnd::Failed,
        };
        let error = match &res {
            Err(err) => Some(("Connection Error".to_owned(), err.to_string())),
            _ => ui.error(),
        };
        match after_login(end, error.as_ref().map(|(t, s)| (t.as_str(), s.as_str()))) {
            Next::Use => {
                let Ok(Some(o)) = res else { continue };
                let direct = ui.direct() == Some(true);
                log::info!(
                    "leapgate tunnel: row {} up ({})",
                    row.port,
                    if direct { "direct" } else { "relayed" }
                );
                let handle = tunnel.set_muxed(o.stream, ui.in_tunnel(), o.kcp);
                up = Some(direct);
                let transport = if direct {
                    Transport::Direct
                } else {
                    Transport::Relay
                };
                row.report(State::InUse { transport });
                if target.rdp && fresh && !lazy {
                    if let Some(port) = local_port(&listener) {
                        session.open_rdp(port);
                    }
                }
                fresh = false;
                if lazy && !o.local_eof {
                    let (socket, prebuf) = take_socket(forward, o.prebuf);
                    if handle
                        .open(&target.host, target.port, socket, prebuf)
                        .is_err()
                    {
                        throttled_log!(
                            LOG_INTERVAL,
                            info,
                            "leapgate tunnel: local connection dropped, tunnel unavailable"
                        );
                    }
                }
            }
            Next::Stop(reason) => {
                // As K0: the KCP guard outlives the refused session so its close reaches the peer.
                if let Ok(Some(o)) = res {
                    drop(o.stream);
                    tokio::spawn(release_kcp(o.kcp));
                }
                listener = None;
                log::info!("leapgate tunnel: row {} stopped, listener closed", row.port);
                row.report(State::Stopped { reason });
            }
            Next::Interrupt(reason) => {
                throttled_log!(
                    LOG_INTERVAL,
                    info,
                    "leapgate tunnel: row login failed: {:?}",
                    error.map(|(_, text)| text)
                );
                row.report(State::Interrupted {
                    cause: Cause::LoginFailed,
                    reason: Some(reason),
                });
            }
        }
    }
    drop(listener);
    drop(tunnel);
}

fn login_failed(err: &str) -> State {
    match after_login(LoginEnd::Failed, Some(("Connection Error", err))) {
        Next::Interrupt(reason) => State::Interrupted {
            cause: Cause::LoginFailed,
            reason: Some(reason),
        },
        _ => State::Interrupted {
            cause: Cause::LoginFailed,
            reason: None,
        },
    }
}

/// The login, raced against the card's close (as `exit::cards::login_or_close`): `None` when
/// closed, the listener gone at once and the login told by its receiver closing, so it closes the
/// connection itself and the peer drops its prompt.
async fn login_or_close<S: TunnelSession>(
    session: &S,
    ui: RowUi<S>,
    ctl: &mut mpsc::UnboundedReceiver<RowCtl>,
    listener: &mut Option<TcpListener>,
    forward: &mut Framed<TcpStream, BytesCodec>,
    key: &str,
    token: &str,
    target: &Target,
) -> Option<(ResultType<Option<LoginOutcome>>, bool)> {
    let (tx, mut rx) = mpsc::unbounded_channel();
    let login = session.login(ui, &mut rx, forward, key, token, target);
    tokio::pin!(login);
    loop {
        tokio::select! {
            res = &mut login => return Some(res),
            c = ctl.recv() => match c {
                Some(RowCtl::Ui(Data::Close)) | None => break,
                Some(RowCtl::Ui(d)) => {
                    let _ = tx.send(d);
                }
                // Connecting: nothing to retry.
                Some(RowCtl::Retry) => {}
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

/// The row's listener (`exit::listen_local`, as an exit's); RDP's on a port the system picks.
async fn listen(port: i32, target: &Target) -> Option<TcpListener> {
    match listen_local(port).await {
        Ok(listener) => {
            if target.rdp {
                let port = listener.local_addr().map(|a| a.port()).unwrap_or_default();
                log::info!("leapgate tunnel: RDP listening on 127.0.0.1:{}", port);
            } else {
                log::info!("leapgate tunnel: listening on 127.0.0.1:{}", port);
            }
            Some(listener)
        }
        Err(err) => {
            log::info!("leapgate tunnel: cannot listen on {}: {}", port, err);
            None
        }
    }
}

/// The port the listener got: the row's, or for RDP the one the system picked.
fn local_port(listener: &Option<TcpListener>) -> Option<u16> {
    listener.as_ref()?.local_addr().ok().map(|a| a.port())
}

/// What a row's logins and tunnel saw, apart from the other rows of the card.
#[derive(Default)]
struct Seen {
    /// The row's own connection: every row's login writes the session's shared `lc.direct`.
    direct: Option<bool>,
    /// The last error message box, `(title, text)`.
    error: Option<(String, String)>,
}

/// The session as one row's login and tunnel see it. Prompts go on to the session, whose events
/// the UI draws the questions from; errors stop here and become the row's state, so the session's
/// stream carries no error box and a card with several rows shows each row's own.
#[derive(Clone)]
pub(crate) struct RowUi<S> {
    session: S,
    row: Row,
    /// Set for the tunnel's `Interface`: a channel the peer refuses is the row's notice.
    tunnel: bool,
    seen: Arc<Mutex<Seen>>,
}

impl<S: Interface> RowUi<S> {
    fn new(session: S, row: Row) -> Self {
        Self {
            session,
            row,
            tunnel: false,
            seen: Default::default(),
        }
    }

    fn in_tunnel(&self) -> Self {
        Self {
            tunnel: true,
            ..self.clone()
        }
    }

    fn direct(&self) -> Option<bool> {
        self.seen.lock().unwrap().direct
    }

    fn error(&self) -> Option<(String, String)> {
        self.seen.lock().unwrap().error.clone()
    }

    fn keep_error(&self, title: &str, text: &str) {
        self.seen.lock().unwrap().error = Some((title.to_owned(), text.to_owned()));
    }
}

#[async_trait::async_trait]
impl<S: Interface + Sync> Interface for RowUi<S> {
    fn send(&self, data: Data) {
        self.session.send(data);
    }

    fn msgbox(&self, msgtype: &str, title: &str, text: &str, link: &str) {
        if msgtype == "error" {
            self.keep_error(title, text);
        } else {
            self.session.msgbox(msgtype, title, text, link);
        }
    }

    fn handle_login_error(&self, err: &str) -> bool {
        // Upstream's, with its message boxes through this row.
        crate::client::handle_login_error(self.get_lch(), err, self)
    }

    fn handle_peer_info(&self, pi: PeerInfo) {
        self.session.handle_peer_info(pi);
    }

    fn set_multiple_windows_session(&self, sessions: Vec<WindowsSession>) {
        self.session.set_multiple_windows_session(sessions);
    }

    fn on_error(&self, err: &str) {
        if self.tunnel {
            // The peer refused a channel; upstream has already held back a repeat for 10 seconds.
            self.row.report(tunnel::notice(err));
        } else {
            self.keep_error("Error", err);
        }
    }

    async fn handle_hash(&self, pass: &str, hash: Hash, peer: &mut Stream) -> bool {
        self.session.handle_hash(pass, hash, peer).await
    }

    async fn handle_login_from_ui(
        &self,
        os_username: String,
        os_password: String,
        password: String,
        remember: bool,
        peer: &mut Stream,
    ) {
        self.session
            .handle_login_from_ui(os_username, os_password, password, remember, peer)
            .await
    }

    async fn handle_test_delay(&self, t: TestDelay, peer: &mut Stream) {
        self.session.handle_test_delay(t, peer).await
    }

    fn get_lch(&self) -> Arc<RwLock<LoginConfigHandler>> {
        self.session.get_lch()
    }

    fn get_id(&self) -> String {
        self.session.get_id()
    }

    fn update_direct(&self, direct: Option<bool>) {
        self.seen.lock().unwrap().direct = direct;
        self.session.update_direct(direct);
    }

    fn on_establish_connection_error(&self, err: String) {
        self.keep_error("Connection Error", &err);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kcp_stream::KcpStream;
    use base::message_proto::*;
    use hbb_common::{
        anyhow::anyhow,
        protobuf::Message as _,
        sodiumoxide::crypto::secretbox,
        tcp::FramedStream,
        timeout,
        tokio::{io::AsyncWriteExt, net::UdpSocket},
    };
    use std::{collections::VecDeque, time::Instant};

    /// What a row's next login answers.
    enum Login {
        /// Multiplexed, over this stream, direct or relayed.
        Use(Stream, bool),
        /// A peer without multiplexing, over this stream and KCP guard.
        Old(Stream, Option<KcpStream>),
        /// The login error box the peer's refusal shows.
        Refused(&'static str),
        Fail,
        /// Logging in until the card closes, then closing this connection as
        /// `connect_and_login_mux` does, its KCP guard kept for the FIN.
        Hang(Option<(KcpStream, Stream)>),
    }

    /// Logins by the row's remote port; the session's message boxes and the ports Remote Desktop
    /// Connection was opened to, as they came.
    #[derive(Clone, Default)]
    struct Fake {
        id: String,
        lc: Arc<RwLock<LoginConfigHandler>>,
        logins: Arc<Mutex<HashMap<i32, VecDeque<Login>>>>,
        boxes: Arc<Mutex<Vec<String>>>,
        rdp_opened: Arc<Mutex<Vec<u16>>>,
    }

    #[async_trait::async_trait]
    impl Interface for Fake {
        fn send(&self, _data: Data) {}
        fn msgbox(&self, msgtype: &str, _title: &str, text: &str, _link: &str) {
            self.boxes
                .lock()
                .unwrap()
                .push(format!("{msgtype}: {text}"));
        }
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
    impl TunnelSession for Fake {
        async fn login(
            &self,
            ui: RowUi<Self>,
            rx: &mut mpsc::UnboundedReceiver<Data>,
            _forward: &mut Framed<TcpStream, BytesCodec>,
            _key: &str,
            _token: &str,
            target: &Target,
        ) -> (ResultType<Option<LoginOutcome>>, bool) {
            let next = self
                .logins
                .lock()
                .unwrap()
                .get_mut(&target.port)
                .and_then(VecDeque::pop_front);
            let outcome = |stream, mux, kcp| LoginOutcome {
                stream,
                mux,
                prebuf: Vec::new(),
                local_eof: false,
                kcp,
            };
            match next {
                Some(Login::Use(stream, direct)) => {
                    ui.update_direct(Some(direct));
                    (Ok(Some(outcome(stream, true, None))), false)
                }
                Some(Login::Old(stream, kcp)) => (Ok(Some(outcome(stream, false, kcp))), false),
                Some(Login::Refused(err)) => {
                    // As upstream's login loop: the error box, then the end of the login.
                    crate::client::handle_login_error(ui.get_lch(), err, &ui);
                    (Ok(None), false)
                }
                Some(Login::Fail) => (Err(anyhow!("Remote desktop is offline")), false),
                Some(Login::Hang(conn)) => {
                    while rx.recv().await.is_some() {}
                    if let Some((guard, stream)) = conn {
                        drop(stream);
                        release_kcp(Some(guard)).await;
                    }
                    (Ok(None), false)
                }
                None => std::future::pending().await,
            }
        }

        fn open_rdp(&self, port: u16) {
            self.rdp_opened.lock().unwrap().push(port);
        }
    }

    struct Card {
        id: &'static str,
        kind: Kind,
        session_id: SessionID,
        tx: mpsc::UnboundedSender<Data>,
        fake: Fake,
    }

    impl Card {
        fn send(&self, data: Data) {
            self.tx.send(data).unwrap();
        }

        fn last(&self, port: i32) -> Option<String> {
            CARDS
                .lock()
                .unwrap()
                .get(&(self.id.to_owned(), self.kind))
                .and_then(|card| card.rows.get(&port).cloned())
        }

        async fn wait_for(&self, port: i32, want: &str) {
            let deadline = Instant::now() + Duration::from_secs(5);
            while !self.last(port).is_some_and(|event| event.contains(want)) {
                assert!(
                    Instant::now() < deadline,
                    "no {} for row {}: {:?}",
                    want,
                    port,
                    self.last(port)
                );
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        }

        async fn wait_removed(&self, port: i32) {
            let deadline = Instant::now() + Duration::from_secs(3);
            while self.last(port).is_some() {
                assert!(Instant::now() < deadline, "row {} still there", port);
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        }

        async fn wait_closed(&self) {
            let deadline = Instant::now() + Duration::from_secs(3);
            let key = (self.id.to_owned(), self.kind);
            while CARDS.lock().unwrap().contains_key(&key) {
                assert!(Instant::now() < deadline, "{} still open", self.id);
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        }
    }

    /// A TCP card with no saved forwards: rows come with `AddPortForward`, as the UI adds them.
    fn start(id: &'static str, logins: Vec<(i32, Login)>) -> Card {
        start_kind(id, Kind::Tcp, logins)
    }

    /// An RDP card's one row (local port 0) logs in to 3389: the session has no `rdp_port`.
    fn start_kind(id: &'static str, kind: Kind, logins: Vec<(i32, Login)>) -> Card {
        let session_id = SessionID::new_v4();
        register(id, kind, session_id);
        let card = take_if(id, kind, |s| *s == session_id).unwrap();
        let mut by_port = HashMap::<i32, VecDeque<Login>>::new();
        for (port, login) in logins {
            by_port.entry(port).or_default().push_back(login);
        }
        let fake = Fake {
            id: id.to_owned(),
            logins: Arc::new(Mutex::new(by_port)),
            ..Default::default()
        };
        let (tx, rx) = mpsc::unbounded_channel();
        tokio::spawn(run_card(fake.clone(), card, rx, "", ""));
        Card {
            id,
            kind,
            session_id,
            tx,
            fake,
        }
    }

    fn add(port: i32, remote_port: i32) -> Data {
        Data::AddPortForward((port, "192.0.2.10".to_owned(), remote_port))
    }

    fn free_port() -> i32 {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        listener.local_addr().unwrap().port() as i32
    }

    /// Asked by connecting, as the exit card's tests do.
    async fn listening(port: i32) -> bool {
        let connect = TcpStream::connect(("127.0.0.1", port as u16));
        matches!(timeout(500, connect).await, Ok(Ok(_)))
    }

    async fn wait_not_listening(port: i32) {
        let deadline = Instant::now() + Duration::from_secs(3);
        while listening(port).await {
            assert!(Instant::now() < deadline, "port {} still listening", port);
        }
    }

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

    /// The target of the next frame, which must be a channel open.
    async fn next_open(peer: &mut Stream) -> (String, i32) {
        let bytes = timeout(5000, peer.next()).await.unwrap().unwrap().unwrap();
        match Message::parse_from_bytes(&bytes).unwrap().union {
            Some(message::Union::PortForwardChannel(PortForwardChannel {
                union: Some(port_forward_channel::Union::Open(open)),
                ..
            })) => (open.host, open.port),
            other => panic!("expected a channel open, got {:?}", other),
        }
    }

    async fn peer_closed(peer: &mut Stream) {
        let end = timeout(5000, peer.next()).await;
        assert!(
            matches!(end, Ok(None) | Ok(Some(Err(_)))),
            "peer not closed: {:?}",
            end
        );
    }

    #[tokio::test]
    async fn rows_log_in_at_once_each_on_its_own_connection() {
        let (a, b) = (free_port(), free_port());
        let ((ours_a, mut peer_a), (ours_b, _peer_b)) =
            (secured_pair().await, secured_pair().await);
        let card = start(
            "tunnel-two-rows",
            vec![
                (80, Login::Use(ours_a, true)),
                (443, Login::Use(ours_b, false)),
            ],
        );
        card.send(add(a, 80));
        card.send(add(b, 443));
        // Each row keeps its own transport though both logins wrote the session's `direct`.
        card.wait_for(a, r#""kind":"tcp","port":"#).await;
        card.wait_for(a, r#""state":"in_use","transport":"direct""#)
            .await;
        card.wait_for(b, r#""state":"in_use","transport":"relay""#)
            .await;
        assert!(card.last(a).unwrap().contains(&card.session_id.to_string()));
        // The placeholder got no channel: the first open is the local program's, to the row's
        // target.
        let mut app = TcpStream::connect(("127.0.0.1", a as u16)).await.unwrap();
        app.write_all(b"GET").await.unwrap();
        assert_eq!(next_open(&mut peer_a).await, ("192.0.2.10".to_owned(), 80));
        // Removing one row leaves the other.
        card.send(Data::RemovePortForward(a));
        card.wait_removed(a).await;
        wait_not_listening(a).await;
        assert!(listening(b).await);
        card.send(Data::Close);
        card.wait_closed().await;
        wait_not_listening(b).await;
    }

    #[tokio::test]
    async fn a_failed_login_keeps_listening_and_the_next_connection_logs_in_at_once() {
        let port = free_port();
        let (ours, mut peer) = secured_pair().await;
        let card = start(
            "tunnel-lazy",
            vec![(22, Login::Fail), (22, Login::Use(ours, true))],
        );
        card.send(add(port, 22));
        card.wait_for(
            port,
            r#""state":"interrupted","cause":"login_failed","reason":{"code":"peer_offline"}"#,
        )
        .await;
        // No cooldown: a local connection logs in again and gets its channel.
        let _app = TcpStream::connect(("127.0.0.1", port as u16))
            .await
            .unwrap();
        card.wait_for(port, r#""state":"in_use""#).await;
        assert_eq!(next_open(&mut peer).await, ("192.0.2.10".to_owned(), 22));
        drop(peer);
        card.wait_for(port, r#""state":"interrupted","cause":"tunnel_ended""#)
            .await;
        assert!(listening(port).await);
        // No error box reached the session's stream.
        assert!(card
            .fake
            .boxes
            .lock()
            .unwrap()
            .iter()
            .all(|b| !b.starts_with("error")));
    }

    #[tokio::test]
    async fn a_refused_row_stops_with_its_reason_and_retry_reopens_it() {
        let port = free_port();
        let ((guard, ours), (_peer_guard, mut peer)) = kcp_pair().await;
        let (secured, _secured_peer) = secured_pair().await;
        let card = start(
            "tunnel-refused",
            vec![
                (8080, Login::Old(ours, Some(guard))),
                (8080, Login::Refused("No permission of IP tunneling")),
                (8080, Login::Use(secured, true)),
            ],
        );
        card.send(add(port, 8080));
        card.wait_for(
            port,
            r#""state":"stopped","reason":{"code":"peer_too_old","feature":"port_forward"}"#,
        )
        .await;
        wait_not_listening(port).await;
        // K0: the guard outlives the stream, so the peer hears the close.
        peer_closed(&mut peer).await;
        assert!(retry(&card.session_id, port));
        card.wait_for(
            port,
            r#""state":"stopped","reason":{"code":"no_permission","feature":"port_forward"}"#,
        )
        .await;
        assert!(
            card.fake.boxes.lock().unwrap().is_empty(),
            "{:?}",
            card.fake.boxes
        );
        assert!(retry(&card.session_id, port));
        card.wait_for(port, r#""state":"in_use""#).await;
        assert!(listening(port).await);
    }

    #[tokio::test]
    async fn closing_mid_login_closes_each_row_and_its_peer_connection() {
        let (a, b) = (free_port(), free_port());
        let ((guard, ours), (_peer_guard, mut peer)) = kcp_pair().await;
        let card = start(
            "tunnel-cancel",
            vec![
                (80, Login::Hang(Some((guard, ours)))),
                (443, Login::Hang(None)),
            ],
        );
        card.send(add(a, 80));
        card.send(add(b, 443));
        card.wait_for(a, r#""state":"connecting""#).await;
        card.wait_for(b, r#""state":"connecting""#).await;
        card.send(Data::Close);
        // The peer hears the close, so its prompt goes with it. The card itself closes once the
        // KCP guard has seen the FIN out, seconds later, as an exit card's.
        peer_closed(&mut peer).await;
        wait_not_listening(a).await;
        wait_not_listening(b).await;
    }

    #[tokio::test]
    async fn the_old_uis_exit_mapping_and_bad_ports_get_no_row() {
        let (port, taken) = (free_port(), free_port());
        let card = start("tunnel-skip", vec![]);
        card.send(Data::AddPortForward((
            port,
            leapgate::exit::SENTINEL_HOST.to_owned(),
            leapgate::exit::SENTINEL_PORT,
        )));
        card.send(add(0, 80));
        card.send(add(taken, 0));
        // A row added after those shows they were passed over, not still on their way.
        let _other = std::net::TcpListener::bind(("127.0.0.1", taken as u16)).unwrap();
        card.send(add(taken, 80));
        card.wait_for(taken, r#""state":"port_in_use""#).await;
        assert!(card.last(port).is_none());
        assert!(card.last(0).is_none());
        assert!(!listening(port).await);
    }

    /// M9-3 (14 §4.1): on Windows the 127.0.0.1 bind alone succeeds here and would take the other
    /// program's local connections.
    #[cfg(windows)]
    #[tokio::test]
    async fn a_port_another_program_listens_on_for_all_addresses_is_taken() {
        let port = free_port();
        let other = std::net::TcpListener::bind(("0.0.0.0", port as u16)).unwrap();
        let (secured, _peer) = secured_pair().await;
        let card = start("tunnel-wildcard", vec![(80, Login::Use(secured, true))]);
        card.send(add(port, 80));
        card.wait_for(port, r#""state":"port_in_use""#).await;
        // Once the port is free, a retry logs in.
        drop(other);
        assert!(retry(&card.session_id, port));
        card.wait_for(port, r#""state":"in_use""#).await;
    }

    #[tokio::test]
    async fn rdp_opens_on_its_first_tunnel_and_when_asked_not_on_a_lazy_one() {
        let (first, mut peer) = secured_pair().await;
        let (again, _peer_again) = secured_pair().await;
        let card = start_kind(
            "tunnel-rdp",
            Kind::Rdp,
            vec![
                (3389, Login::Use(first, true)),
                (3389, Login::Use(again, true)),
            ],
        );
        card.wait_for(0, r#""kind":"rdp","port":0,"state":"in_use""#)
            .await;
        let opened = card.fake.rdp_opened.clone();
        let port = opened.lock().unwrap()[0];
        // Remote Desktop Connection's connection goes to the peer's RDP port.
        let _mstsc = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
        assert_eq!(next_open(&mut peer).await, (String::new(), 3389));
        drop(peer);
        card.wait_for(0, r#""state":"interrupted","cause":"tunnel_ended""#)
            .await;
        // Remote Desktop Connection, already open, connects again: no second window.
        let _again = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
        card.wait_for(0, r#""state":"in_use""#).await;
        assert_eq!(*opened.lock().unwrap(), [port]);
        card.send(Data::NewRDP);
        let deadline = Instant::now() + Duration::from_secs(3);
        while opened.lock().unwrap().len() < 2 {
            assert!(Instant::now() < deadline, "NewRDP opened nothing");
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        assert_eq!(*opened.lock().unwrap(), [port, port]);
    }

    #[test]
    fn a_row_keeps_its_errors_and_passes_its_prompts_on() {
        let fake = Fake {
            id: "tunnel-ui".to_owned(),
            ..Default::default()
        };
        let boxes = fake.boxes.clone();
        let row = Row {
            id: "tunnel-ui".to_owned(),
            kind: Kind::Tcp,
            gen: 0,
            port: 8080,
        };
        let ui = RowUi::new(fake, row);
        assert!(ui.handle_login_error(crate::client::LOGIN_MSG_PASSWORD_WRONG));
        assert!(!ui.handle_login_error("Connection not allowed"));
        ui.on_establish_connection_error("Timeout".to_owned());
        assert_eq!(
            *boxes.lock().unwrap(),
            ["re-input-password: Do you want to enter again?"]
        );
        assert_eq!(
            ui.error(),
            Some(("Connection Error".to_owned(), "Timeout".to_owned()))
        );
    }

    #[test]
    fn take_claims_only_the_registered_session_once() {
        let (id, sid, other) = ("tunnel-take", SessionID::new_v4(), SessionID::new_v4());
        register(id, Kind::Tcp, sid);
        // Another session of the device (an exit card's, one added later) is not the card's.
        assert!(take_if(id, Kind::Tcp, |s| *s == other).is_none());
        assert!(take_if(id, Kind::Rdp, |s| *s == sid).is_none());
        assert!(take_if(id, Kind::Tcp, |s| *s == sid).is_some());
        assert!(
            take_if(id, Kind::Tcp, |s| *s == sid).is_none(),
            "taken twice"
        );
        CARDS.lock().unwrap().remove(&(id.to_owned(), Kind::Tcp));
    }

    #[test]
    fn retry_reaches_a_row_of_the_card_only() {
        let (id, sid) = ("tunnel-retry", SessionID::new_v4());
        register(id, Kind::Tcp, sid);
        let gen = CARDS.lock().unwrap()[&(id.to_owned(), Kind::Tcp)].gen;
        assert!(!retry(&sid, 8080), "no such row yet");
        push(id, Kind::Tcp, gen, Some(8080), &State::PortInUse);
        assert!(retry(&sid, 8080));
        assert!(!retry(&sid, 8081));
        assert!(!retry(&SessionID::new_v4(), 8080));
        push(id, Kind::Tcp, gen, Some(8080), &State::Removed);
        assert!(!retry(&sid, 8080), "removed");
        push(id, Kind::Tcp, gen, None, &State::Closed);
        assert!(!CARDS
            .lock()
            .unwrap()
            .contains_key(&(id.to_owned(), Kind::Tcp)));
    }
}
