//! Leapgate glue that needs upstream's crate-private items, so it cannot live in `libs/leapgate`.
//! Upstream files call in here through one-line hooks; the logic itself stays in `libs/leapgate`.

pub(crate) mod exit;

use crate::{
    client::{Client, Interface},
    kcp_stream::KcpStream,
    server::{ConnectionMeta, ServerPtr},
};
use base::config::keys;
use hbb_common::{
    allow_err, anyhow, bail,
    config::{self, Config, LocalConfig, CONNECT_TIMEOUT},
    futures::future::Either,
    log,
    protobuf::{Message as _, MessageField},
    rendezvous_proto::{
        leapgate_ice,
        leapgate_ice_reject::Reason,
        leapgate_ice_result::{Kind, Net, Outcome},
        rendezvous_message, LeapgateIce, LeapgateIceAnswer, LeapgateIceOffer, LeapgateIceParams,
        LeapgateIceReject, LeapgateIceResult, RendezvousMessage,
    },
    socket_client::connect_tcp,
    tokio::{self, time::timeout},
    ResultType, Stream,
};
use leapgate::ice::{Accepted, Agent, AnswerParams, Offer, Opened, Selected, ICE_VER};
use std::{
    future::Future,
    net::SocketAddr,
    sync::atomic::{AtomicUsize, Ordering},
    time::{Duration, Instant},
};

/// Races the LAN candidates a Leapgate peer listed in its `is_local` response, each secured with
/// upstream's handshake, and returns what `Client::connect` returns on success. `None` when
/// they all fail; when they are not tried at all (TCP punching off, relay forced, no peer key
/// that verifies under the server's key) it also empties them, so `lan_fallback` keeps
/// upstream's path.
///
/// A verified key is required because without it the handshake reads nothing from the peer,
/// so any connection that merely completed (one the peer's listener queued but never accepted)
/// would win. It is checked before the race: the peer's listener takes one connection, so a
/// race that failed on it would leave nothing for upstream's attempt. A candidate whose
/// handshake returns without securing the stream is a failure too.
pub(crate) async fn lan_connect(
    candidates: &mut Vec<SocketAddr>,
    allow_tcp_punch: bool,
    force_relay: bool,
    peer: &str,
    signed_id_pk: &[u8],
    key: &str,
) -> Option<(
    Stream,
    bool,
    Option<Vec<u8>>,
    Option<KcpStream>,
    &'static str,
)> {
    if !allow_tcp_punch || force_relay || !peer_key_verifies(peer, signed_id_pk, key) {
        candidates.clear();
    }
    if candidates.is_empty() {
        return None;
    }
    let secure = |mut conn: Stream| async move {
        let pk = Client::secure_connection(peer, signed_id_pk.to_vec(), key, &mut conn).await?;
        if !conn.is_secured() {
            bail!("LAN candidate answered without a verified identity");
        }
        Ok::<_, anyhow::Error>((conn, pk))
    };
    let (conn, pk) = leapgate::lan::connect_candidates(candidates, secure).await?;
    Some((conn, true, pk, None, "TCP"))
}

/// The check `Client::secure_connection` makes before reading the peer: the peer's key signed
/// by the server, under the configured key, for this peer id.
fn peer_key_verifies(peer: &str, signed_id_pk: &[u8], key: &str) -> bool {
    if signed_id_pk.is_empty() {
        return false;
    }
    let rs_pk = crate::common::get_rs_pk(if key.is_empty() {
        config::RS_PUB_KEY
    } else {
        key
    });
    rs_pk.is_some_and(|rs_pk| {
        crate::common::decode_id_pk(signed_id_pk, &rs_pk).is_ok_and(|(id, _)| id == peer)
    })
}

/// Upstream's `connect()` arguments when `lan_connect` did not connect: when the candidates it
/// tried (still in `candidates`) include `peer_addr`, upstream's own TCP attempt would only
/// retry it, so it is skipped and upstream relays; otherwise its LAN attempt only stops
/// binding to a TUN address.
pub(crate) async fn lan_fallback(
    candidates: &[SocketAddr],
    peer_addr: SocketAddr,
    is_local: bool,
    my_addr: SocketAddr,
    allow_tcp_punch: bool,
) -> (SocketAddr, bool) {
    let tcp = allow_tcp_punch && !candidates.contains(&peer_addr);
    if !tcp {
        return (my_addr, tcp);
    }
    (
        leapgate::lan::controller_bind_addr(my_addr, is_local).await,
        tcp,
    )
}

/// What `Client::_start` returns.
type Connected = (
    (
        Stream,
        bool,
        Option<Vec<u8>>,
        Option<KcpStream>,
        &'static str,
    ),
    (i32, String),
    bool,
);

/// Contract 05 §2.11. The signaling connection gets one bound for connect and key exchange
/// together: a rendezvous server that does no key exchange would otherwise hold
/// `secure_tcp_required` for upstream's 18 s read timeout.
const SIGNAL_TIMEOUT: Duration = Duration::from_millis(3000);
const OFFER_RESEND: Duration = Duration::from_millis(1500);
const ANSWER_WAIT: Duration = Duration::from_millis(4000);
/// The selected pair has just been shown to work both ways, so upstream's 18 s are not needed.
const KCP_HANDOFF_TIMEOUT: Duration = Duration::from_millis(3000);
const MAX_AGENTS: usize = 8;
/// Upstream's `Client::RELAY_FALLBACK_DELAY_MS`, copied with `relay_fallback_delay_ms` below
/// rather than made visible.
const RELAY_FALLBACK_DELAY_MS: u64 = 2500;
const DROP_LOG_INTERVAL: Duration = Duration::from_secs(60);
/// Well past the controller's own 8 s (`KCP_PEER_SILENCE_LIMIT` in `src/client/io_loop.rs`): a
/// controller reconnecting after a link drop has to log in again before this connection closes,
/// or "lock after session end" locks a session that has resumed; and an idle mux or exit tunnel,
/// which its controller gives up on after an 18 s read timeout, is not closed any sooner here.
const ICE_PEER_SILENCE_CLOSE: Duration = Duration::from_secs(20);

/// Races Leapgate's ICE (contract 05 §4.8.1) against upstream's `_start` (`upstream`) and returns
/// the winner in `_start`'s shape. ICE never fails a connection: when it loses or fails, the
/// result and the error text are upstream's, which the UI matches whole (the offline retry).
pub(crate) async fn race_ice<I, F>(
    peer: &str,
    key: &str,
    interface: &I,
    upstream: F,
) -> ResultType<Connected>
where
    I: Interface,
    F: Future<Output = ResultType<Connected>>,
{
    if !ice_enabled(peer, key, interface) {
        return upstream.await;
    }
    let window_ms = relay_fallback_delay_ms();
    match race_legs(ice_leg(peer, key), upstream, window_ms, |r: &Connected| r.0 .1).await? {
        Either::Left(win) => Ok(win.commit().await),
        Either::Right(up) => Ok(up),
    }
}

/// Only the plain path: no `id@server?key=`, no direct IP, no forced relay (which covers `/r`, a
/// proxy and WebSocket), UDP allowed, UDP or IPv6 punching on, a trusted key, and a server that
/// announces `ice`.
fn ice_enabled(peer: &str, key: &str, interface: &impl Interface) -> bool {
    !config::is_incoming_only()
        && !hbb_common::is_ip_str(peer)
        && !hbb_common::is_domain_port_str(peer)
        && interface.get_lch().read().unwrap().other_server.is_none()
        && !interface.is_force_relay()
        && !crate::is_udp_disabled()
        && (crate::get_udp_punch_enabled() || crate::get_ipv6_punch_enabled())
        && crate::common::get_rs_pk(if key.is_empty() { config::RS_PUB_KEY } else { key })
            .is_some()
        && leapgate::report::has_feature("ice")
}

/// Upstream's `Client::relay_fallback_delay_ms`, so both races hold a relay for the same time.
fn relay_fallback_delay_ms() -> u64 {
    match LocalConfig::get_option(keys::OPTION_RELAY_FALLBACK_DELAY)
        .trim()
        .parse::<f64>()
    {
        Ok(secs) if secs.is_finite() && secs > 0.0 => (secs * 1000.0).round() as u64,
        _ => RELAY_FALLBACK_DELAY_MS,
    }
}

/// A direct result from either leg wins at once. A relay from upstream waits up to `window_ms`
/// for ICE. A failed ICE leg leaves upstream's own result, error included.
async fn race_legs<A, B>(
    ice: impl Future<Output = ResultType<A>>,
    upstream: impl Future<Output = ResultType<B>>,
    window_ms: u64,
    is_direct: impl Fn(&B) -> bool,
) -> ResultType<Either<A, B>> {
    let started = Instant::now();
    tokio::pin!(ice, upstream);
    tokio::select! {
        r = &mut ice => match r {
            Ok(a) => Ok(Either::Left(a)),
            Err(_) => upstream.await.map(Either::Right),
        },
        r = &mut upstream => match r {
            Ok(b) if is_direct(&b) => Ok(Either::Right(b)),
            Ok(b) => match timeout(Duration::from_millis(window_ms), ice).await {
                Ok(Ok(a)) => Ok(Either::Left(a)),
                Ok(Err(_)) => Ok(Either::Right(b)),
                // The ICE leg logs its own failures; only a leg still running here would leave
                // the controller's log silent.
                Err(_) => {
                    log::info!(
                        "leapgate ice: lost the relay window after {} ms",
                        started.elapsed().as_millis()
                    );
                    Ok(Either::Right(b))
                }
            },
            Err(e) => match ice.await {
                Ok(a) => Ok(Either::Left(a)),
                Err(_) => Err(e),
            },
        },
    }
}

/// The ICE leg's connection, kept until the race has picked it: RESULT `CONNECTED` goes out
/// only then, so a leg the race drops is `abandoned` on the server, not `connected`.
struct IceWin {
    sig: Signal,
    stream: Stream,
    pk: Option<Vec<u8>>,
    kcp: KcpStream,
    local_kind: Kind,
    remote_kind: Kind,
    family: u32,
    net: Net,
    elapsed_ms: u32,
    rendezvous_server: String,
}

impl IceWin {
    async fn commit(self) -> Connected {
        let result = LeapgateIceResult {
            outcome: Outcome::CONNECTED.into(),
            elapsed_ms: self.elapsed_ms,
            local_kind: self.local_kind.into(),
            remote_kind: self.remote_kind.into(),
            family: self.family,
            local_net: self.net.into(),
            ..Default::default()
        };
        self.sig.result(result).await;
        log::info!(
            "leapgate ice: selected {}/{}/{} <-> {}/{} in {} ms",
            kind_name(self.local_kind),
            family_name(self.family),
            net_name(self.net),
            kind_name(self.remote_kind),
            family_name(self.family),
            self.elapsed_ms
        );
        let typ = if self.family == 6 { "IPv6" } else { "UDP" };
        (
            (self.stream, true, self.pk, Some(self.kcp), typ),
            (0, self.rendezvous_server),
            false,
        )
    }
}

/// The controller's signaling connection once its OFFER is out.
struct Signal {
    conn: Stream,
    session: [u8; 16],
    started: Instant,
}

impl Signal {
    fn elapsed_ms(&self) -> u32 {
        self.started.elapsed().as_millis() as u32
    }

    /// RESULT is statistics only: a server that has already closed the connection loses it.
    async fn result(mut self, mut r: LeapgateIceResult) {
        r.session = self.session.to_vec().into();
        allow_err!(self.conn.send(&ice_msg(leapgate_ice::Union::Result(r))).await);
    }

    async fn fail(self, outcome: Outcome) -> anyhow::Error {
        let r = LeapgateIceResult {
            outcome: outcome.into(),
            elapsed_ms: self.elapsed_ms(),
            ..Default::default()
        };
        self.result(r).await;
        log::info!(
            "leapgate ice: no direct path ({}), falling back",
            outcome_name(outcome)
        );
        anyhow::anyhow!("ICE: {}", outcome_name(outcome))
    }
}

fn signaling_failed() -> anyhow::Error {
    log::info!("leapgate ice: signaling failed, falling back");
    anyhow::anyhow!("ICE signaling failed")
}

/// One ICE attempt up to a secured stream (§4.8.1 steps 1~7). Any failure is an `Err` the race
/// ignores; the logs and RESULT for it are sent here.
async fn ice_leg(peer: &str, key: &str) -> ResultType<IceWin> {
    let started = Instant::now();
    let rendezvous_server = crate::get_rendezvous_server(1_000).await.0;
    let local = leapgate::ice::local_addrs().await;
    if local.is_empty() {
        bail!("no ICE candidates");
    }
    let (gathered, conn) = tokio::join!(
        leapgate::ice::gather(&local, &rendezvous_server),
        signaling(&rendezvous_server, key)
    );
    let Ok(mut conn) = conn else {
        return Err(signaling_failed());
    };
    let offer = Offer::new(gathered);
    let session = offer.session();
    let (ufrag, pwd, candidates, proofs) = offer.params();
    let msg = ice_msg(leapgate_ice::Union::Offer(LeapgateIceOffer {
        session: session.to_vec().into(),
        id: peer.to_owned(),
        licence_key: key.to_owned(),
        params: MessageField::some(LeapgateIceParams {
            ufrag,
            pwd,
            candidates,
            ..Default::default()
        }),
        proofs,
        ..Default::default()
    }));
    let reply = wait_answer(&mut conn, &msg).await;
    let sig = Signal {
        conn,
        session,
        started,
    };
    let answer = match reply {
        Reply::Answer(ICE_VER, a) => a,
        Reply::Answer(..) => return Err(sig.fail(Outcome::BAD_ANSWER).await),
        Reply::Reject(reason) => {
            log::info!(
                "leapgate ice: rejected ({}), falling back",
                reason_name(reason)
            );
            bail!("ICE rejected");
        }
        Reply::Closed => return Err(signaling_failed()),
        Reply::NoAnswer => return Err(sig.fail(Outcome::NO_ANSWER).await),
    };
    if answer.session[..] != session[..] || !peer_key_verifies(peer, &answer.pk, key) {
        return Err(sig.fail(Outcome::BAD_ANSWER).await);
    }
    let Ok(params) = AnswerParams::parse(&answer.params) else {
        return Err(sig.fail(Outcome::BAD_ANSWER).await);
    };
    let Ok(sel) = offer.run(params).await else {
        return Err(sig.fail(Outcome::NO_PAIR).await);
    };
    let Ok((kcp, mut stream)) = kcp_connect(&sel).await else {
        return Err(sig.fail(Outcome::KCP_FAILED).await);
    };
    let secured = timeout(
        KCP_HANDOFF_TIMEOUT,
        Client::secure_connection(peer, answer.pk.to_vec(), key, &mut stream),
    )
    .await;
    let pk = match secured {
        Ok(Ok(pk)) if stream.is_secured() => pk,
        _ => return Err(sig.fail(Outcome::SECURE_FAILED).await),
    };
    Ok(IceWin {
        elapsed_ms: sig.elapsed_ms(),
        sig,
        stream,
        pk,
        kcp,
        local_kind: sel.local_kind,
        remote_kind: sel.remote_kind,
        family: sel.family,
        net: sel.net,
        rendezvous_server,
    })
}

async fn kcp_connect(sel: &Selected) -> ResultType<(KcpStream, Stream)> {
    sel.socket.connect(sel.remote).await?;
    KcpStream::connect(sel.socket.clone(), KCP_HANDOFF_TIMEOUT).await
}

/// A new encrypted connection to the rendezvous server, as upstream's WebRTC answer opens one.
async fn signaling(host: &str, key: &str) -> ResultType<Stream> {
    timeout(SIGNAL_TIMEOUT, async {
        let mut conn = connect_tcp(host, CONNECT_TIMEOUT).await?;
        crate::secure_tcp_required(&mut conn, key).await?;
        Ok(conn)
    })
    .await?
}

fn ice_msg(union: leapgate_ice::Union) -> RendezvousMessage {
    let mut msg = RendezvousMessage::new();
    msg.set_leapgate_ice(LeapgateIce {
        ver: ICE_VER,
        union: Some(union),
        ..Default::default()
    });
    msg
}

enum Reply {
    /// With the message's `ver`.
    Answer(u32, LeapgateIceAnswer),
    Reject(Reason),
    /// Closed or broken: an older leapgate-server drops the connection on oneof 1000.
    Closed,
    NoAnswer,
}

/// Sends the OFFER, once more after `OFFER_RESEND`, and reads the reply for `ANSWER_WAIT`.
async fn wait_answer(conn: &mut Stream, offer: &RendezvousMessage) -> Reply {
    if conn.send(offer).await.is_err() {
        return Reply::Closed;
    }
    let sent = Instant::now();
    let mut resent = false;
    loop {
        let until = sent + if resent { ANSWER_WAIT } else { OFFER_RESEND };
        let bytes = match tokio::time::timeout_at(until.into(), conn.next()).await {
            Ok(Some(Ok(bytes))) => bytes,
            Ok(_) => return Reply::Closed,
            Err(_) if resent => return Reply::NoAnswer,
            Err(_) => {
                resent = true;
                if conn.send(offer).await.is_err() {
                    return Reply::Closed;
                }
                continue;
            }
        };
        let Ok(RendezvousMessage {
            union: Some(rendezvous_message::Union::LeapgateIce(ice)),
            ..
        }) = RendezvousMessage::parse_from_bytes(&bytes)
        else {
            continue;
        };
        match ice.union {
            Some(leapgate_ice::Union::Answer(a)) => return Reply::Answer(ice.ver, a),
            Some(leapgate_ice::Union::Reject(r)) => {
                return Reply::Reject(r.reason.enum_value_or_default())
            }
            _ => {}
        }
    }
}

fn kind_name(k: Kind) -> &'static str {
    match k {
        Kind::HOST => "host",
        Kind::SRFLX => "srflx",
        Kind::PRFLX => "prflx",
    }
}

fn family_name(family: u32) -> &'static str {
    if family == 6 {
        "v6"
    } else {
        "v4"
    }
}

fn net_name(n: Net) -> &'static str {
    match n {
        Net::ETHERNET => "ethernet",
        Net::WLAN => "wlan",
        Net::OTHER => "other",
    }
}

fn outcome_name(o: Outcome) -> &'static str {
    match o {
        Outcome::UNKNOWN => "unknown",
        Outcome::CONNECTED => "connected",
        Outcome::NO_ANSWER => "no_answer",
        Outcome::BAD_ANSWER => "bad_answer",
        Outcome::NO_PAIR => "no_pair",
        Outcome::KCP_FAILED => "kcp_failed",
        Outcome::SECURE_FAILED => "secure_failed",
    }
}

fn reason_name(r: Reason) -> &'static str {
    match r {
        Reason::BAD => "bad",
        Reason::OFFLINE => "offline",
        Reason::UNSUPPORTED => "unsupported",
        Reason::RELAY => "relay",
        Reason::BUSY => "busy",
    }
}

/// `handle_resp` got a `LeapgateIce` (§4.8.2). Spawned and infallible: an `Err` out of
/// `handle_resp` would take the whole mediator down and reconnect it.
pub(crate) fn on_ice_offer(ice: LeapgateIce, host: String, server: ServerPtr) {
    tokio::spawn(on_ice_offer_(ice, host, server));
}

/// The FORWARD is verified, deduplicated and decrypted before anything else, because only then
/// is there a session to answer a REJECT for.
async fn on_ice_offer_(ice: LeapgateIce, host: String, server: ServerPtr) {
    let (session, peer) = match leapgate::ice::open_forward(&ice) {
        Opened::Drop => return dropped_offer(),
        Opened::Bad { session } => (session, None),
        Opened::Ok { session, peer } => (session.to_vec().into(), Some(peer)),
    };
    // A full table goes unanswered: every REJECT costs a new TCP connection to the server, and a
    // full table usually means someone is flooding FORWARDs.
    let Some(slot) = AgentSlot::take() else {
        return dropped_offer();
    };
    let key = crate::get_key(true).await;
    let reject = |reason: Reason| {
        let r = LeapgateIceReject {
            session: session.clone(),
            reason: reason.into(),
            ..Default::default()
        };
        reply(&host, &key, leapgate_ice::Union::Reject(r))
    };
    let Some(peer) = peer else {
        return reject(Reason::BAD).await;
    };
    if ice_unsupported_here() {
        return reject(Reason::UNSUPPORTED).await;
    }
    let local = leapgate::ice::local_addrs().await;
    if local.is_empty() {
        return reject(Reason::UNSUPPORTED).await;
    }
    let (gathered, conn) = tokio::join!(
        leapgate::ice::gather(&local, &host),
        signaling(&host, &key)
    );
    let Ok(mut conn) = conn else {
        log::trace!("leapgate ice: no signaling connection for an answer");
        return;
    };
    let agent = Agent::new(gathered, peer);
    let (ufrag, pwd, candidates, proofs) = agent.params();
    let answer = ice_msg(leapgate_ice::Union::Answer(LeapgateIceAnswer {
        session: session.clone(),
        params: MessageField::some(LeapgateIceParams {
            ufrag,
            pwd,
            candidates,
            ..Default::default()
        }),
        proofs,
        ..Default::default()
    }));
    let send = async move {
        if let Err(e) = conn.send(&answer).await {
            log::trace!("leapgate ice: answer not sent: {}", e);
        }
    };
    let (_, accepted) = tokio::join!(send, agent.run());
    let Ok(Accepted {
        socket,
        remote,
        init_packet,
    }) = accepted
    else {
        log::trace!("leapgate ice: agent timed out");
        return;
    };
    let kcp = async {
        socket.connect(remote).await?;
        KcpStream::accept(socket, KCP_HANDOFF_TIMEOUT, Some(init_packet)).await
    };
    let (kcp, stream) = match kcp.await {
        Ok(k) => k,
        Err(e) => {
            log::trace!("leapgate ice: KCP handoff failed: {}", e);
            return;
        }
    };
    drop(slot);
    // The address ICE actually selected, as a LAN TCP accept would see it.
    allow_err!(
        serve_over_kcp(
            kcp,
            ICE_PEER_SILENCE_CLOSE,
            crate::server::create_tcp_connection(
                server,
                stream,
                remote,
                true,
                ConnectionMeta::default()
            )
        )
        .await
    );
}

/// Runs `session` over the stream `kcp` guards. Without this a controller that crashed or lost
/// its network is only noticed by the session's own 30 s timeout, where a relay closes at once.
/// A peer silent for `limit` loses its guard: the endpoint stops, the stream's read fails, and
/// the session closes on that error as it would on a reset connection, cleanup included. A
/// session that ends first keeps the guard until its tail and FIN are out.
async fn serve_over_kcp<F: Future>(kcp: KcpStream, limit: Duration, session: F) -> F::Output {
    tokio::pin!(session);
    let mut kcp = Some(kcp);
    let mut tick = tokio::time::interval(Duration::from_secs(1));
    let out = loop {
        tokio::select! {
            out = &mut session => break out,
            _ = tick.tick(), if kcp.is_some() => {
                let silent = kcp.as_ref().and_then(|k| k.peer_silent_for());
                if let Some(s) = silent.filter(|s| *s >= limit) {
                    log::info!("leapgate ice: peer silent for {:?}, closing the session", s);
                    kcp = None;
                }
            }
        }
    };
    tokio::spawn(crate::port_forward::release_kcp(kcp));
    out
}

fn dropped_offer() {
    hbb_common::throttled_log!(
        DROP_LOG_INTERVAL,
        info,
        "leapgate ice: dropped a forwarded offer"
    );
}

/// A REJECT on a new encrypted connection, closed once sent.
async fn reply(host: &str, key: &str, union: leapgate_ice::Union) {
    if let Ok(mut conn) = signaling(host, key).await {
        if let Err(e) = conn.send(&ice_msg(union)).await {
            log::trace!("leapgate ice: reject not sent: {}", e);
        }
    }
}

/// A proxy, WebSocket or `disable-udp` normally moves the mediator to TCP, where the server
/// sees this device offline; this covers the seconds before it switches.
fn ice_unsupported_here() -> bool {
    Config::is_proxy()
        || config::use_ws()
        || crate::is_udp_disabled()
        || whitelist_restricts(&Config::get_option("whitelist"))
}

/// `check_whitelist`'s test for a list that limits anyone. The whitelist would judge the address
/// ICE selected, possibly a private or IPv6 one, and a winning ICE leg never falls back, so a
/// peer the relay could reach before might be refused; with a whitelist there is no ICE.
fn whitelist_restricts(whitelist: &str) -> bool {
    let items: Vec<&str> = whitelist.split(',').filter(|x| !x.is_empty()).collect();
    !items.is_empty() && !items.contains(&"0.0.0.0")
}

static ICE_AGENTS: AtomicUsize = AtomicUsize::new(0);

/// One of the process's `MAX_AGENTS` places for a FORWARD in flight, REJECTs included.
struct AgentSlot;

impl AgentSlot {
    fn take() -> Option<Self> {
        // Made before the increment so that a refused place, dropped by `then_some`, undoes it.
        let slot = AgentSlot;
        (ICE_AGENTS.fetch_add(1, Ordering::SeqCst) < MAX_AGENTS).then_some(slot)
    }
}

impl Drop for AgentSlot {
    fn drop(&mut self) {
        ICE_AGENTS.fetch_sub(1, Ordering::SeqCst);
    }
}

/// W1: in the new UI's process, hands a link (`--connect` and the like) only to the new UI's main
/// window, found by its class alone: its title follows the current tab. Returns `None` in the upstream
/// UI's process, which then looks up its window by class and title as upstream does; the two never
/// fall back to each other's window. `Some(false)` when no main window of the new UI is running.
#[cfg(all(windows, feature = "flutter"))]
pub(crate) fn send_to_new_ui_main_window(dw_data: usize, data: &str) -> Option<bool> {
    use winapi::um::winuser::{FindWindowW, SendMessageW, COPYDATASTRUCT, WM_COPYDATA};
    if !leapgate::ui::is_next_ui() {
        return None;
    }
    let class = crate::platform::windows::wide_string(leapgate::ui::MAIN_WINDOW_CLASS);
    let window = unsafe { FindWindowW(class.as_ptr(), std::ptr::null()) };
    if window.is_null() {
        log::info!("leapgate ui: no main window to hand the link to");
        return Some(false);
    }
    let mut bytes: Vec<u8> = data.bytes().chain(Some(0)).collect();
    let data_struct = COPYDATASTRUCT {
        dwData: dw_data,
        cbData: bytes.len() as _,
        lpData: bytes.as_mut_ptr() as _,
    };
    unsafe {
        SendMessageW(window, WM_COPYDATA, 0, &data_struct as *const COPYDATASTRUCT as _);
    }
    Some(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::{rendezvous_proto::IdPk, sodiumoxide::crypto::sign, tokio};

    const PEER: &str = "123456789";

    /// A server key and `PEER`'s key signed under it, as the server hands them out.
    fn server_signed_peer() -> (String, Vec<u8>) {
        let (rs_pk, rs_sk) = sign::gen_keypair();
        let (peer_pk, _) = sign::gen_keypair();
        let id_pk = IdPk {
            id: PEER.to_owned(),
            pk: peer_pk.0.to_vec().into(),
            ..Default::default()
        }
        .write_to_bytes()
        .unwrap();
        (crate::common::encode64(rs_pk.0), sign::sign(&id_pk, &rs_sk))
    }

    #[test]
    fn peer_key_verifies_only_for_the_signed_id() {
        let (key, signed) = server_signed_peer();
        assert!(peer_key_verifies(PEER, &signed, &key));
        assert!(!peer_key_verifies("987654321", &signed, &key));
    }

    #[tokio::test]
    async fn unverified_peer_key_keeps_upstream_tcp() {
        let (_, signed) = server_signed_peer();
        let (other_key, _) = server_signed_peer();
        let peer_addr: SocketAddr = "192.168.1.2:21118".parse().unwrap();
        let mut candidates = vec![peer_addr];
        let res = lan_connect(&mut candidates, true, false, PEER, &signed, &other_key).await;
        assert!(res.is_none());
        assert!(candidates.is_empty());
        let my_addr = "192.168.1.3:0".parse().unwrap();
        let (_, tcp) = lan_fallback(&candidates, peer_addr, true, my_addr, true).await;
        assert!(tcp);
    }

    #[tokio::test]
    async fn lan_fallback_skips_upstream_tcp_only_after_trying_peer_addr() {
        let peer_addr: SocketAddr = "192.168.1.2:21118".parse().unwrap();
        let other: SocketAddr = "10.0.0.2:21118".parse().unwrap();
        let my_addr: SocketAddr = "192.168.1.3:0".parse().unwrap();
        assert_eq!(
            lan_fallback(&[other, peer_addr], peer_addr, true, my_addr, true).await,
            (my_addr, false)
        );
        let (_, tcp) = lan_fallback(&[other], peer_addr, true, my_addr, true).await;
        assert!(tcp);
    }

    /// Upstream's result: a tag and whether it is direct.
    type Up = (&'static str, bool);
    const DIRECT: Up = ("direct", true);
    const RELAY: Up = ("relay", false);

    async fn ok_after<T>(ms: u64, v: T) -> ResultType<T> {
        tokio::time::sleep(Duration::from_millis(ms)).await;
        Ok(v)
    }

    async fn err_after<T>(ms: u64, what: &'static str) -> ResultType<T> {
        tokio::time::sleep(Duration::from_millis(ms)).await;
        Err(anyhow::anyhow!(what))
    }

    async fn race(
        ice: impl Future<Output = ResultType<&'static str>>,
        upstream: impl Future<Output = ResultType<Up>>,
        window_ms: u64,
    ) -> ResultType<&'static str> {
        Ok(match race_legs(ice, upstream, window_ms, |u: &Up| u.1).await? {
            Either::Left(ice) => ice,
            Either::Right(up) => up.0,
        })
    }

    #[tokio::test]
    async fn ice_wins_as_soon_as_it_connects() {
        let got = race(ok_after(10, "ice"), ok_after(200, DIRECT), 60_000).await;
        assert_eq!(got.unwrap(), "ice");
    }

    #[tokio::test]
    async fn upstream_direct_wins_at_once() {
        let start = Instant::now();
        let got = race(ok_after(60_000, "ice"), ok_after(10, DIRECT), 60_000).await;
        assert_eq!(got.unwrap(), "direct");
        assert!(start.elapsed() < Duration::from_secs(5));
    }

    #[tokio::test]
    async fn upstream_relay_waits_one_window_for_ice() {
        let got = race(ok_after(100, "ice"), ok_after(10, RELAY), 60_000).await;
        assert_eq!(got.unwrap(), "ice");
        let start = Instant::now();
        let got = race(ok_after(60_000, "ice"), ok_after(10, RELAY), 100).await;
        assert_eq!(got.unwrap(), "relay");
        assert!(start.elapsed() < Duration::from_secs(5));
        let got = race(err_after(50, "ICE: no_pair"), ok_after(10, RELAY), 60_000).await;
        assert_eq!(got.unwrap(), "relay");
    }

    #[tokio::test]
    async fn ice_still_connects_after_upstream_fails() {
        let got = race(ok_after(100, "ice"), err_after(10, "relay failed"), 60_000).await;
        assert_eq!(got.unwrap(), "ice");
    }

    #[tokio::test]
    async fn a_failed_ice_leg_reports_upstreams_error() {
        const OFFLINE: &str = "Remote desktop is offline";
        let got = race(err_after(50, "ICE: no_pair"), err_after(10, OFFLINE), 60_000).await;
        assert_eq!(got.unwrap_err().to_string(), OFFLINE);
        let got = race(err_after(10, "ICE: no_pair"), err_after(50, OFFLINE), 60_000).await;
        assert_eq!(got.unwrap_err().to_string(), OFFLINE);
    }

    #[test]
    fn only_a_limiting_whitelist_stops_ice() {
        assert!(!whitelist_restricts(""));
        assert!(!whitelist_restricts(","));
        assert!(!whitelist_restricts("0.0.0.0"));
        assert!(!whitelist_restricts("192.168.1.0/24,0.0.0.0"));
        assert!(whitelist_restricts("192.168.1.0/24"));
        assert!(whitelist_restricts("10.0.0.1,"));
    }

    #[tokio::test]
    async fn a_session_over_kcp_ends_soon_after_its_peer_goes_silent() {
        use std::sync::Arc;
        use tokio::net::UdpSocket;
        let a = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let b = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        a.connect(b.local_addr().unwrap()).await.unwrap();
        b.connect(a.local_addr().unwrap()).await.unwrap();
        let (ours, theirs) = tokio::join!(
            KcpStream::accept(Arc::new(b), Duration::from_secs(5), None),
            KcpStream::connect(Arc::new(a), Duration::from_secs(5)),
        );
        let (guard, mut stream) = ours.unwrap();
        let (peer_guard, _peer_stream) = theirs.unwrap();
        // A crashed peer: its endpoint stops with no FIN, and nothing more reaches us.
        drop(peer_guard);
        let session = async move { while let Some(Ok(_)) = stream.next().await {} };
        let start = Instant::now();
        // The 2 s limit, one 1 s tick and margin: a slower check fails here.
        timeout(
            Duration::from_secs(5),
            serve_over_kcp(guard, Duration::from_secs(2), session),
        )
        .await
        .expect("the session outlived its silent peer");
        assert!(start.elapsed() >= Duration::from_secs(2));
    }

    #[tokio::test]
    async fn a_session_over_kcp_that_ends_delivers_its_tail() {
        use hbb_common::bytes::Bytes;
        use std::sync::Arc;
        use tokio::net::UdpSocket;
        let a = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let b = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        a.connect(b.local_addr().unwrap()).await.unwrap();
        b.connect(a.local_addr().unwrap()).await.unwrap();
        let (ours, theirs) = tokio::join!(
            KcpStream::accept(Arc::new(b), Duration::from_secs(5), None),
            KcpStream::connect(Arc::new(a), Duration::from_secs(5)),
        );
        let (guard, mut stream) = ours.unwrap();
        let (_peer_guard, mut peer_stream) = theirs.unwrap();
        const N: usize = 50;
        let payload = vec![7u8; 32 * 1024];
        let sent = payload.clone();
        let session = async move {
            for _ in 0..N {
                stream.send_bytes(Bytes::from(sent.clone())).await.unwrap();
            }
            drop(stream);
        };
        serve_over_kcp(guard, ICE_PEER_SILENCE_CLOSE, session).await;
        let mut got = 0;
        while let Some(Ok(data)) = timeout(Duration::from_secs(5), peer_stream.next())
            .await
            .expect("the stream never ended")
        {
            assert_eq!(&data[..], &payload[..]);
            got += 1;
        }
        assert_eq!(got, N);
    }
}
