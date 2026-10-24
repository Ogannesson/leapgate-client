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

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::{
        protobuf::Message as _, rendezvous_proto::IdPk, sodiumoxide::crypto::sign, tokio,
    };

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
}
