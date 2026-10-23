//! Porta glue that needs upstream's crate-private items, so it cannot live in `libs/porta`.
//! Upstream files call in here through one-line hooks; the logic itself stays in `libs/porta`.

use crate::{client::Client, kcp_stream::KcpStream};
use hbb_common::{anyhow, Stream};
use std::net::SocketAddr;

/// Races the LAN candidates a Porta peer listed in its `is_local` response, each secured with
/// upstream's handshake, and returns what `Client::connect` returns on success. `None` when
/// there are none, TCP punching is off, or all fail.
pub(crate) async fn lan_connect(
    candidates: &[SocketAddr],
    allow_tcp_punch: bool,
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
    if !allow_tcp_punch || candidates.is_empty() {
        return None;
    }
    let secure = |mut conn: Stream| async move {
        let pk = Client::secure_connection(peer, signed_id_pk.to_vec(), key, &mut conn).await?;
        Ok::<_, anyhow::Error>((conn, pk))
    };
    let (conn, pk) = porta::lan::connect_candidates(candidates, secure).await?;
    Some((conn, true, pk, None, "TCP"))
}

/// Upstream's `connect()` arguments when `lan_connect` did not connect: after failed candidates
/// it skips its own TCP attempt, which would only retry the first of them, and relays; and its
/// LAN attempt never binds to a TUN address.
pub(crate) async fn lan_fallback(
    candidates: &[SocketAddr],
    is_local: bool,
    my_addr: SocketAddr,
    allow_tcp_punch: bool,
) -> (SocketAddr, bool) {
    let my_addr = porta::lan::controller_bind_addr(my_addr, is_local).await;
    (my_addr, allow_tcp_punch && candidates.is_empty())
}
