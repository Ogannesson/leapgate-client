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
    leapgate::exit::directory::fetch().await
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
