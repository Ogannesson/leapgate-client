//! The rendezvous server's address for srflx (contract 05 §4.3). Under a TUN with fake-ip DNS
//! (mihomo, Clash) the system resolver answers with an address in `198.18/15`, and a Binding
//! request to it from a socket on a physical adapter never gets a reply. So a name is asked of
//! the adapters' own DNS servers, from the adapters' own addresses; the system resolver is only
//! the fallback.

use super::{
    sig::{classify, Class},
    LocalAddr,
};
use crate::dns::Answer;
use hbb_common::{
    futures::future::{select, select_ok, Either},
    log, tokio,
};
use std::{
    net::{IpAddr, SocketAddr},
    pin::pin,
    time::{Duration, Instant},
};

/// Leaves the rest of `GATHER_WAIT` to the Binding request: the first send and the resend at
/// 200 ms, with 200 ms for the answer to that.
pub(super) const RESOLVE_WAIT: Duration = Duration::from_millis(200);
const MAX_SERVERS: usize = 2;

/// `rendezvous` (`host:port`) as STUN addresses by `deadline`: a literal as it is, a name from
/// the DNS servers of `local`'s adapters or else from the system.
pub(super) async fn resolve(
    local: &[LocalAddr],
    rendezvous: &str,
    deadline: Instant,
) -> Vec<SocketAddr> {
    if let Ok(a) = rendezvous.parse::<SocketAddr>() {
        return vec![a];
    }
    let mut servers: Vec<(IpAddr, SocketAddr)> = Vec::new();
    for l in local {
        for &d in l.dns.iter().flatten() {
            if servers.len() < MAX_SERVERS && !servers.iter().any(|(_, s)| s.ip() == d) {
                servers.push((l.ip, SocketAddr::new(d, 53)));
            }
        }
    }
    resolve_via(&servers, rendezvous, deadline).await
}

/// `servers` are (address to bind, DNS server). Their answer wins even over a system one that
/// came first: under split DNS the system's may be an internal address, while the Binding
/// request leaves through the physical adapter.
async fn resolve_via(
    servers: &[(IpAddr, SocketAddr)],
    rendezvous: &str,
    deadline: Instant,
) -> Vec<SocketAddr> {
    let Some((host, port)) = rendezvous
        .rsplit_once(':')
        .and_then(|(h, p)| Some((h, p.parse::<u16>().ok()?)))
    else {
        return Vec::new();
    };
    let adapters = pin!(async {
        if servers.is_empty() {
            return Vec::new();
        }
        let asks = servers
            .iter()
            .map(|&(bind, server)| Box::pin(ask(bind, server, host, port, deadline)));
        select_ok(asks).await.map(|(addrs, _)| addrs).unwrap_or_default()
    });
    let system = pin!(async {
        match tokio::time::timeout_at(deadline.into(), tokio::net::lookup_host(rendezvous)).await {
            Ok(Ok(addrs)) => reachable(addrs),
            _ => Vec::new(),
        }
    });
    match select(adapters, system).await {
        Either::Left((a, system)) if a.is_empty() => system.await,
        Either::Left((a, _)) => a,
        Either::Right((s, adapters)) => {
            let a = adapters.await;
            if a.is_empty() {
                s
            } else {
                a
            }
        }
    }
}

/// Without what a socket on a physical adapter cannot reach: a fake-ip `198.18/15`, loopback.
fn reachable(addrs: impl IntoIterator<Item = SocketAddr>) -> Vec<SocketAddr> {
    addrs
        .into_iter()
        .filter(|a| classify(a.ip()) != Class::Drop)
        .collect()
}

/// `server`'s A and AAAA answers for `host` that came by `deadline`, from a socket of its own on
/// `bind`; `Err` when it gives no reachable address. One answer is enough: a server may never
/// answer AAAA.
async fn ask(
    bind: IpAddr,
    server: SocketAddr,
    host: &str,
    port: u16,
    deadline: Instant,
) -> Result<Vec<SocketAddr>, ()> {
    let Answer::Addresses(ips) = crate::dns::ask(bind, server, host, deadline, None).await else {
        return Err(());
    };
    let got = reachable(ips.into_iter().map(|ip| SocketAddr::new(ip, port)));
    if got.is_empty() {
        log::trace!("leapgate ice: DNS {} from {}: no address", host, server);
        return Err(());
    }
    Ok(got)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dns::{record, reply, TYPE_A};
    use hbb_common::tokio::net::UdpSocket;
    use std::net::Ipv4Addr;

    const PTR: [u8; 2] = [0xc0, 0x0c];

    fn sa(s: &str) -> SocketAddr {
        s.parse().unwrap()
    }

    /// Answers A questions with `a` and AAAA ones with no record (or not at all without `aaaa`),
    /// under `rcode`, each after a forged reply from another port that only the source check
    /// turns away.
    async fn fake_server(rcode: u8, a: [u8; 4], aaaa: bool) -> SocketAddr {
        let s = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let forger = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let at = s.local_addr().unwrap();
        tokio::spawn(async move {
            let mut buf = [0u8; 512];
            loop {
                let (n, from) = s.recv_from(&mut buf).await.unwrap();
                let q = &buf[..n];
                let is_a = q[n - 4..n - 2] == TYPE_A.to_be_bytes();
                if !is_a && !aaaa {
                    continue;
                }
                let rec = |ip: [u8; 4]| {
                    is_a.then(|| record(&PTR, TYPE_A, &ip))
                        .into_iter()
                        .collect::<Vec<_>>()
                };
                let forged = reply(q, 0, &rec([203, 0, 113, 66]));
                forger.send_to(&forged, from).await.unwrap();
                s.send_to(&reply(q, rcode, &rec(a)), from).await.unwrap();
            }
        });
        at
    }

    /// The name is an address literal so that the system resolver has an answer offline.
    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn the_adapters_answer_wins_and_the_system_one_is_kept_only_if_reachable() {
        let lo = IpAddr::from(Ipv4Addr::LOCALHOST);
        let deadline = || Instant::now() + RESOLVE_WAIT;
        let answering = fake_server(0, [203, 0, 113, 9], true).await;
        let no_aaaa = fake_server(0, [203, 0, 113, 9], false).await;
        let failing = fake_server(2, [203, 0, 113, 9], true).await;
        let fake_ip = fake_server(0, [198, 18, 0, 19], true).await;
        let name = "203.0.113.5:21116";
        let got = resolve_via(&[(lo, answering)], name, deadline()).await;
        assert_eq!(got, [sa("203.0.113.9:21116")]);
        let got = resolve_via(&[(lo, no_aaaa)], name, deadline()).await;
        assert_eq!(got, [sa("203.0.113.9:21116")]);
        let got = resolve_via(&[(lo, failing)], name, deadline()).await;
        assert_eq!(got, [sa("203.0.113.5:21116")]);
        let got = resolve_via(&[(lo, fake_ip)], name, deadline()).await;
        assert_eq!(got, [sa("203.0.113.5:21116")]);
        let got = resolve_via(&[(lo, failing)], "198.18.0.20:21116", deadline()).await;
        assert!(got.is_empty(), "{got:?}");
        let got = resolve_via(&[], name, deadline()).await;
        assert_eq!(got, [sa("203.0.113.5:21116")]);
    }
}
