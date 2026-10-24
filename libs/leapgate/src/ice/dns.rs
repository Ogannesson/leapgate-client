//! The rendezvous server's address for srflx (contract 05 §4.3). Under a TUN with fake-ip DNS
//! (mihomo, Clash) the system resolver answers with an address in `198.18/15`, and a Binding
//! request to it from a socket on a physical adapter never gets a reply. So a name is asked of
//! the adapters' own DNS servers, from the adapters' own addresses; the system resolver is only
//! the fallback.

use super::{
    gather::RECV_BUF,
    sig::{classify, Class},
    LocalAddr,
};
use hbb_common::{
    futures::future::{select, select_ok, Either},
    log, rand,
    tokio::{self, net::UdpSocket},
};
use std::{
    net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr},
    pin::pin,
    time::{Duration, Instant},
};

/// Leaves the rest of `GATHER_WAIT` to the Binding request: the first send and the resend at
/// 200 ms, with 200 ms for the answer to that.
pub(super) const RESOLVE_WAIT: Duration = Duration::from_millis(200);
const MAX_SERVERS: usize = 2;
const MAX_RECORDS: u16 = 32;
const TYPE_A: u16 = 1;
const TYPE_AAAA: u16 = 28;

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
            .map(|&(bind, server)| Box::pin(ask(bind, server, host, port)));
        match tokio::time::timeout_at(deadline.into(), select_ok(asks)).await {
            Ok(Ok((addrs, _))) => addrs,
            _ => Vec::new(),
        }
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

/// `server`'s A and AAAA answers for `host`, from a socket of its own on `bind`; `Err` when it
/// gives no address.
async fn ask(
    bind: IpAddr,
    server: SocketAddr,
    host: &str,
    port: u16,
) -> Result<Vec<SocketAddr>, ()> {
    let fail = |e: &dyn std::fmt::Display| {
        log::trace!("leapgate ice: DNS {} from {}: {}", host, server, e);
    };
    let sock = UdpSocket::bind(SocketAddr::new(bind, 0))
        .await
        .map_err(|e| fail(&e))?;
    let mut queries = Vec::new();
    for t in [TYPE_A, TYPE_AAAA] {
        let Some(q) = query(rand::random(), host, t) else {
            fail(&"not a DNS name");
            return Err(());
        };
        sock.send_to(&q, server).await.map_err(|e| fail(&e))?;
        queries.push(q);
    }
    let mut ips = Vec::new();
    let mut buf = [0u8; RECV_BUF];
    while !queries.is_empty() {
        let (n, from) = sock.recv_from(&mut buf).await.map_err(|e| fail(&e))?;
        if from != server {
            continue;
        }
        if let Some(i) = queries.iter().position(|q| reply_to(&buf[..n], q)) {
            ips.extend(answers(&buf[..n], &queries[i]).unwrap_or_default());
            queries.swap_remove(i);
        }
    }
    let got = reachable(ips.into_iter().map(|ip| SocketAddr::new(ip, port)));
    if got.is_empty() {
        fail(&"no address");
        return Err(());
    }
    Ok(got)
}

/// A recursive query for `name`, `None` when it is not a valid DNS name.
fn query(id: u16, name: &str, qtype: u16) -> Option<Vec<u8>> {
    let mut q = id.to_be_bytes().to_vec();
    q.extend_from_slice(&[0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]);
    for label in name.strip_suffix('.').unwrap_or(name).split('.') {
        if label.is_empty() || label.len() > 63 {
            return None;
        }
        q.push(label.len() as u8);
        q.extend_from_slice(label.as_bytes());
    }
    q.push(0);
    if q.len() - 12 > 255 {
        return None;
    }
    q.extend_from_slice(&qtype.to_be_bytes());
    q.extend_from_slice(&[0, 1]);
    Some(q)
}

/// Whether `resp` is a response to `query`: its id, QR set, and its one question.
fn reply_to(resp: &[u8], query: &[u8]) -> bool {
    resp.len() >= query.len()
        && resp[..2] == query[..2]
        && resp[2] & 0x80 != 0
        && resp[4..6] == [0, 1]
        && resp[12..query.len()].eq_ignore_ascii_case(&query[12..])
}

/// The addresses of `query`'s type in the answer section of `resp`, CNAME records skipped.
/// Empty for an error RCODE, so that server stops being waited for; `None` when `resp` is not
/// a reply to `query` or is malformed.
fn answers(resp: &[u8], query: &[u8]) -> Option<Vec<IpAddr>> {
    if !reply_to(resp, query) {
        return None;
    }
    if resp[3] & 0x0f != 0 {
        return Some(Vec::new());
    }
    let qtype = &query[query.len() - 4..query.len() - 2];
    let count = u16::from_be_bytes([resp[6], resp[7]]);
    let mut at = query.len();
    let mut out = Vec::new();
    for _ in 0..count.min(MAX_RECORDS) {
        at = skip_name(resp, at)?;
        let rr = resp.get(at..at + 10)?;
        let len = u16::from_be_bytes([rr[8], rr[9]]) as usize;
        let data = resp.get(at + 10..at + 10 + len)?;
        if &rr[..2] == qtype && rr[2..4] == [0, 1] {
            match (u16::from_be_bytes([rr[0], rr[1]]), data.len()) {
                (TYPE_A, 4) => out.push(Ipv4Addr::new(data[0], data[1], data[2], data[3]).into()),
                (TYPE_AAAA, 16) => {
                    out.push(Ipv6Addr::from(<[u8; 16]>::try_from(data).ok()?).into())
                }
                _ => return None,
            }
        }
        at += 10 + len;
    }
    Some(out)
}

/// Past the name at `at`. A compression pointer ends it and is not followed.
fn skip_name(b: &[u8], mut at: usize) -> Option<usize> {
    // A name of at most 255 bytes has at most 127 labels.
    for _ in 0..128 {
        let len = *b.get(at)? as usize;
        match len & 0xc0 {
            0xc0 => return (at + 2 <= b.len()).then_some(at + 2),
            0 if len == 0 => return Some(at + 1),
            0 => at += 1 + len,
            _ => return None,
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    const PTR: [u8; 2] = [0xc0, 0x0c];
    const TYPE_CNAME: u16 = 5;

    fn sa(s: &str) -> SocketAddr {
        s.parse().unwrap()
    }

    fn labels(name: &str) -> Vec<u8> {
        let q = query(0, name, 0).unwrap();
        q[12..q.len() - 4].to_vec()
    }

    fn record(name: &[u8], rtype: u16, data: &[u8]) -> Vec<u8> {
        let mut r = name.to_vec();
        r.extend_from_slice(&rtype.to_be_bytes());
        r.extend_from_slice(&[0, 1, 0, 0, 0, 60]);
        r.extend_from_slice(&(data.len() as u16).to_be_bytes());
        r.extend_from_slice(data);
        r
    }

    fn reply(q: &[u8], rcode: u8, records: &[Vec<u8>]) -> Vec<u8> {
        let mut r = q.to_vec();
        r[2] = 0x81;
        r[3] = 0x80 | rcode;
        r[6..8].copy_from_slice(&(records.len() as u16).to_be_bytes());
        records.iter().for_each(|rec| r.extend_from_slice(rec));
        r
    }

    #[test]
    fn query_asks_one_recursive_question() {
        let q = query(0x1234, "rd.Example.com.", TYPE_A).unwrap();
        assert_eq!(
            q,
            crate::ice::hex("123401000001000000000000027264074578616d706c6503636f6d0000010001")
        );
        assert_eq!(query(1, "rd..com", TYPE_A), None);
        assert_eq!(query(1, &"a".repeat(64), TYPE_A), None);
        assert_eq!(query(1, &["a"; 128].join("."), TYPE_A), None);
    }

    #[test]
    fn a_and_aaaa_records_are_read_through_a_cname_chain() {
        let q = query(7, "rd.example.com", TYPE_A).unwrap();
        let edge = labels("edge.cdn.net");
        let r = reply(
            &q,
            0,
            &[
                record(&PTR, TYPE_CNAME, &edge),
                record(&edge, TYPE_A, &[203, 0, 113, 9]),
                record(&edge, TYPE_AAAA, &[0x20; 16]),
                record(&PTR, TYPE_A, &[203, 0, 113, 10]),
            ],
        );
        let want: Vec<IpAddr> = vec![[203, 0, 113, 9].into(), [203, 0, 113, 10].into()];
        assert_eq!(answers(&r, &q), Some(want));

        let q6 = query(8, "RD.example.com", TYPE_AAAA).unwrap();
        let mut r = reply(&q6, 0, &[record(&PTR, TYPE_AAAA, &[0x20; 16])]);
        // A server may echo the question in another case.
        r[13] = b'r';
        assert_eq!(answers(&r, &q6), Some(vec![IpAddr::from([0x20u8; 16])]));
    }

    #[test]
    fn only_a_successful_reply_to_the_same_question_gives_addresses() {
        let q = query(7, "rd.example.com", TYPE_A).unwrap();
        let a = [record(&PTR, TYPE_A, &[203, 0, 113, 9])];
        let good = reply(&q, 0, &a);
        assert!(answers(&good, &q).is_some_and(|v| v.len() == 1));
        let mut other_id = good.clone();
        other_id[1] ^= 1;
        let mut not_a_reply = good.clone();
        not_a_reply[2] &= 0x7f;
        let other_question = reply(&query(7, "rd.example.org", TYPE_A).unwrap(), 0, &a);
        let other_type = reply(&query(7, "rd.example.com", TYPE_AAAA).unwrap(), 0, &a);
        for r in [other_id, not_a_reply, other_question, other_type] {
            assert_eq!(answers(&r, &q), None);
        }
        assert_eq!(answers(&reply(&q, 3, &a), &q), Some(vec![]));
        // An A record of the wrong length.
        let bad = reply(&q, 0, &[record(&PTR, TYPE_A, &[1, 2, 3])]);
        assert_eq!(answers(&bad, &q), None);
    }

    #[test]
    fn no_bytes_from_the_network_panic() {
        let q = query(7, "rd.example.com", TYPE_A).unwrap();
        let edge = labels("edge.cdn.net");
        let good = reply(
            &q,
            0,
            &[
                record(&PTR, TYPE_CNAME, &edge),
                record(&edge, TYPE_A, &[203, 0, 113, 9]),
            ],
        );
        for n in 0..good.len() {
            answers(&good[..n], &q);
        }
        let mut seed = 0x2545_f491_4f6c_dd1du64;
        let mut next = || {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed
        };
        for _ in 0..20_000 {
            let mut r = good.clone();
            for _ in 0..1 + next() % 4 {
                let i = (next() as usize) % r.len();
                r[i] = next() as u8;
            }
            answers(&r, &q);
            let tail = (next() as usize) % 64;
            let mut junk = good[..q.len()].to_vec();
            junk.extend((0..tail).map(|_| next() as u8));
            answers(&junk, &q);
        }
    }

    /// Answers A questions with `a` and AAAA ones with no record, under `rcode`, each after a
    /// forged reply from another port that only the source check turns away.
    async fn fake_server(rcode: u8, a: [u8; 4]) -> SocketAddr {
        let s = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let forger = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let at = s.local_addr().unwrap();
        tokio::spawn(async move {
            let mut buf = [0u8; 512];
            loop {
                let (n, from) = s.recv_from(&mut buf).await.unwrap();
                let q = &buf[..n];
                let rec = |ip: [u8; 4]| {
                    let is_a = q[n - 4..n - 2] == TYPE_A.to_be_bytes();
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
        let answering = fake_server(0, [203, 0, 113, 9]).await;
        let failing = fake_server(2, [203, 0, 113, 9]).await;
        let fake_ip = fake_server(0, [198, 18, 0, 19]).await;
        let name = "203.0.113.5:21116";
        let got = resolve_via(&[(lo, answering)], name, deadline()).await;
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
