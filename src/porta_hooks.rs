//! Porta glue that needs upstream's crate-private items, so it cannot live in `libs/porta`.
//! Upstream files call in here through one-line hooks; the logic itself stays in `libs/porta`.

use crate::{client::Client, kcp_stream::KcpStream};
use hbb_common::{anyhow, bail, Stream};
use std::net::SocketAddr;

/// Races the LAN candidates a Porta peer listed in its `is_local` response, each secured with
/// upstream's handshake, and returns what `Client::connect` returns on success. `None` when
/// they all fail; when they are not tried at all (TCP punching off, relay forced, no
/// server-signed peer key) it also empties them, so `lan_fallback` keeps upstream's path.
///
/// The signed key is required because without it the handshake reads nothing from the peer,
/// so any connection that merely completed (one the peer's listener queued but never accepted)
/// would win. A candidate whose handshake returns without securing the stream is a failure too.
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
    if !allow_tcp_punch || force_relay || signed_id_pk.is_empty() {
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
    let (conn, pk) = porta::lan::connect_candidates(candidates, secure).await?;
    Some((conn, true, pk, None, "TCP"))
}

/// Upstream's `connect()` arguments when `lan_connect` did not connect: after candidates that
/// failed (still in `candidates`) it skips its own TCP attempt, which would only retry the
/// first of them, and relays; otherwise its LAN attempt only stops binding to a TUN address.
pub(crate) async fn lan_fallback(
    candidates: &[SocketAddr],
    is_local: bool,
    my_addr: SocketAddr,
    allow_tcp_punch: bool,
) -> (SocketAddr, bool) {
    let tcp = allow_tcp_punch && candidates.is_empty();
    if !tcp {
        return (my_addr, tcp);
    }
    (
        porta::lan::controller_bind_addr(my_addr, is_local).await,
        tcp,
    )
}
