//! Leapgate glue that needs upstream's crate-private items, so it cannot live in `libs/leapgate`.
//! Upstream files call in here through one-line hooks; the logic itself stays in `libs/leapgate`.

use crate::{client::Client, kcp_stream::KcpStream};
use hbb_common::{anyhow, bail, config, Stream};
use std::net::SocketAddr;

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
