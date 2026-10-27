//! One DNS server's A and AAAA answers for a name, asked from a socket of its own on a given
//! local address. ICE asks the adapters' own servers for the rendezvous server (contract 05
//! §4.3); the exit asks them for a destination (phase 4 contract 02 §3.2).

use hbb_common::{
    log, rand,
    tokio::{self, net::UdpSocket},
};
use std::{
    net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr},
    time::{Duration, Instant},
};

pub(crate) const TYPE_A: u16 = 1;
pub(crate) const TYPE_AAAA: u16 = 28;
const RECV_BUF: usize = 1500;
const RCODE_NXDOMAIN: u8 = 3;

/// What one server said about a name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Answer {
    Addresses(Vec<IpAddr>),
    /// A matching NXDOMAIN, or NOERROR without an address for both types.
    Negative,
    /// Nothing to go by: a timeout, a send or receive error, another error code, a truncated or
    /// malformed reply, or a name that is not a DNS name.
    NoAnswer,
}

/// One reply to one question.
#[derive(Debug, PartialEq, Eq)]
enum Reply {
    Records(Vec<IpAddr>),
    NxDomain,
    Failed,
}

/// `server`'s A and AAAA answers for `host` by `deadline`, from a socket of its own on `bind`.
/// Once one family has addresses, the other one is waited for at most `other_family_grace`.
pub(crate) async fn ask(
    bind: IpAddr,
    server: SocketAddr,
    host: &str,
    deadline: Instant,
    other_family_grace: Option<Duration>,
) -> Answer {
    let fail = |e: &dyn std::fmt::Display| {
        log::trace!("leapgate: DNS {} from {}: {}", host, server, e);
    };
    let sock = match UdpSocket::bind(SocketAddr::new(bind, 0)).await {
        Ok(s) => s,
        Err(e) => {
            fail(&e);
            return Answer::NoAnswer;
        }
    };
    let mut queries = Vec::new();
    for t in [TYPE_A, TYPE_AAAA] {
        let Some(q) = query(rand::random(), host, t) else {
            fail(&"not a DNS name");
            return Answer::NoAnswer;
        };
        if let Err(e) = sock.send_to(&q, server).await {
            fail(&e);
            return Answer::NoAnswer;
        }
        queries.push(q);
    }
    let (mut ips, mut nodata, mut nxdomain) = (Vec::new(), 0, false);
    let mut until = deadline;
    let mut buf = [0u8; RECV_BUF];
    while !queries.is_empty() {
        let Ok(got) = tokio::time::timeout_at(until.into(), sock.recv_from(&mut buf)).await else {
            break;
        };
        let (n, from) = match got {
            Ok(got) => got,
            Err(e) => {
                fail(&e);
                break;
            }
        };
        if from != server {
            continue;
        }
        let Some(i) = queries.iter().position(|q| reply_to(&buf[..n], q)) else {
            continue;
        };
        match answers(&buf[..n], &queries[i]) {
            Some(Reply::Records(v)) if v.is_empty() => nodata += 1,
            Some(Reply::Records(v)) => {
                if let (true, Some(grace)) = (ips.is_empty(), other_family_grace) {
                    until = deadline.min(Instant::now() + grace);
                }
                ips.extend(v);
            }
            Some(Reply::NxDomain) => nxdomain = true,
            Some(Reply::Failed) | None => {}
        }
        queries.swap_remove(i);
    }
    if !ips.is_empty() {
        Answer::Addresses(ips)
    } else if nxdomain || nodata == 2 {
        Answer::Negative
    } else {
        fail(&"no answer");
        Answer::NoAnswer
    }
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
/// A truncated reply or an error RCODE other than NXDOMAIN fails; `None` when `resp` is not a
/// reply to `query` or is malformed.
fn answers(resp: &[u8], query: &[u8]) -> Option<Reply> {
    if !reply_to(resp, query) {
        return None;
    }
    if resp[2] & 0x02 != 0 {
        return Some(Reply::Failed);
    }
    match resp[3] & 0x0f {
        0 => {}
        RCODE_NXDOMAIN => return Some(Reply::NxDomain),
        _ => return Some(Reply::Failed),
    }
    let qtype = &query[query.len() - 4..query.len() - 2];
    let count = u16::from_be_bytes([resp[6], resp[7]]);
    let mut at = query.len();
    let mut out = Vec::new();
    for _ in 0..count {
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
    Some(Reply::Records(out))
}

/// Past the name at `at`. A compression pointer ends it and is not followed.
fn skip_name(b: &[u8], mut at: usize) -> Option<usize> {
    loop {
        let len = *b.get(at)? as usize;
        match len & 0xc0 {
            0xc0 => return (at + 2 <= b.len()).then_some(at + 2),
            0 if len == 0 => return Some(at + 1),
            0 => at += 1 + len,
            _ => return None,
        }
    }
}

#[cfg(test)]
pub(crate) fn record(name: &[u8], rtype: u16, data: &[u8]) -> Vec<u8> {
    let mut r = name.to_vec();
    r.extend_from_slice(&rtype.to_be_bytes());
    r.extend_from_slice(&[0, 1, 0, 0, 0, 60]);
    r.extend_from_slice(&(data.len() as u16).to_be_bytes());
    r.extend_from_slice(data);
    r
}

#[cfg(test)]
pub(crate) fn reply(q: &[u8], rcode: u8, records: &[Vec<u8>]) -> Vec<u8> {
    let mut r = q.to_vec();
    r[2] = 0x81;
    r[3] = 0x80 | rcode;
    r[6..8].copy_from_slice(&(records.len() as u16).to_be_bytes());
    records.iter().for_each(|rec| r.extend_from_slice(rec));
    r
}

#[cfg(test)]
const PTR: [u8; 2] = [0xc0, 0x0c];

/// A server on loopback that sends each query what `respond` makes of it (`true` for an A
/// question), after a forged reply with an address from another port.
#[cfg(test)]
pub(crate) async fn serve(respond: fn(&[u8], bool) -> Option<Vec<u8>>) -> SocketAddr {
    let s = UdpSocket::bind("127.0.0.1:0").await.unwrap();
    let forger = UdpSocket::bind("127.0.0.1:0").await.unwrap();
    let at = s.local_addr().unwrap();
    tokio::spawn(async move {
        let mut buf = [0u8; 512];
        loop {
            let (n, from) = s.recv_from(&mut buf).await.unwrap();
            let q = &buf[..n];
            let is_a = q[n - 4..n - 2] == TYPE_A.to_be_bytes();
            let forged = if is_a {
                record(&PTR, TYPE_A, &[203, 0, 113, 66])
            } else {
                record(&PTR, TYPE_AAAA, &[0x20; 16])
            };
            forger.send_to(&reply(q, 0, &[forged]), from).await.unwrap();
            if let Some(r) = respond(q, is_a) {
                s.send_to(&r, from).await.unwrap();
            }
        }
    });
    at
}

/// `203.0.113.9` for an A question, nothing for the rest.
#[cfg(test)]
pub(crate) fn a_record(q: &[u8], is_a: bool) -> Option<Vec<u8>> {
    is_a.then(|| reply(q, 0, &[record(&PTR, TYPE_A, &[203, 0, 113, 9])]))
}

#[cfg(test)]
mod tests {
    use super::*;

    const TYPE_CNAME: u16 = 5;

    fn hex(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    fn labels(name: &str) -> Vec<u8> {
        let q = query(0, name, 0).unwrap();
        q[12..q.len() - 4].to_vec()
    }

    #[test]
    fn query_asks_one_recursive_question() {
        let q = query(0x1234, "rd.Example.com.", TYPE_A).unwrap();
        assert_eq!(
            q,
            hex("123401000001000000000000027264074578616d706c6503636f6d0000010001")
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
        assert_eq!(answers(&r, &q), Some(Reply::Records(want)));

        let q6 = query(8, "RD.example.com", TYPE_AAAA).unwrap();
        let mut r = reply(&q6, 0, &[record(&PTR, TYPE_AAAA, &[0x20; 16])]);
        // A server may echo the question in another case.
        r[13] = b'r';
        assert_eq!(
            answers(&r, &q6),
            Some(Reply::Records(vec![IpAddr::from([0x20u8; 16])]))
        );
    }

    #[test]
    fn only_a_successful_reply_to_the_same_question_gives_addresses() {
        let q = query(7, "rd.example.com", TYPE_A).unwrap();
        let a = [record(&PTR, TYPE_A, &[203, 0, 113, 9])];
        let good = reply(&q, 0, &a);
        assert!(matches!(answers(&good, &q), Some(Reply::Records(v)) if v.len() == 1));
        let mut other_id = good.clone();
        other_id[1] ^= 1;
        let mut not_a_reply = good.clone();
        not_a_reply[2] &= 0x7f;
        let other_question = reply(&query(7, "rd.example.org", TYPE_A).unwrap(), 0, &a);
        let other_type = reply(&query(7, "rd.example.com", TYPE_AAAA).unwrap(), 0, &a);
        for r in [other_id, not_a_reply, other_question, other_type] {
            assert_eq!(answers(&r, &q), None);
        }
        assert_eq!(answers(&reply(&q, 3, &a), &q), Some(Reply::NxDomain));
        assert_eq!(answers(&reply(&q, 2, &a), &q), Some(Reply::Failed));
        assert_eq!(answers(&reply(&q, 5, &a), &q), Some(Reply::Failed));
        let mut truncated = good.clone();
        truncated[2] |= 0x02;
        assert_eq!(answers(&truncated, &q), Some(Reply::Failed));
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

    async fn ask_of(respond: fn(&[u8], bool) -> Option<Vec<u8>>) -> Answer {
        let server = serve(respond).await;
        let deadline = Instant::now() + Duration::from_millis(300);
        let lo = IpAddr::from(Ipv4Addr::LOCALHOST);
        ask(
            lo,
            server,
            "rd.example.com",
            deadline,
            Some(Duration::from_millis(50)),
        )
        .await
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn a_server_answers_addresses_a_negative_or_nothing() {
        let a = IpAddr::from([203, 0, 113, 9]);
        let started = Instant::now();
        // AAAA never answered: the A answer is taken after the grace, not at the deadline.
        assert_eq!(ask_of(a_record).await, Answer::Addresses(vec![a]));
        assert!(started.elapsed() < Duration::from_millis(250));
        assert_eq!(
            ask_of(|q, is_a| a_record(q, is_a).or_else(|| Some(reply(q, 0, &[])))).await,
            Answer::Addresses(vec![a])
        );
        assert_eq!(
            ask_of(|q, _| Some(reply(q, 3, &[]))).await,
            Answer::Negative
        );
        assert_eq!(
            ask_of(|q, is_a| is_a.then(|| reply(q, 3, &[]))).await,
            Answer::Negative
        );
        assert_eq!(
            ask_of(|q, _| Some(reply(q, 0, &[]))).await,
            Answer::Negative
        );
        // NODATA for one family and nothing for the other proves nothing.
        assert_eq!(
            ask_of(|q, is_a| is_a.then(|| reply(q, 0, &[]))).await,
            Answer::NoAnswer
        );
        let no_answer: [fn(&[u8], bool) -> Option<Vec<u8>>; 6] = [
            |_, _| None,
            |q, _| Some(reply(q, 2, &[])),
            |q, _| Some(reply(q, 5, &[])),
            |q, is_a| {
                let mut r = a_record(q, true)?;
                r[2] |= 0x02;
                is_a.then_some(r)
            },
            |q, is_a| {
                let mut r = a_record(q, is_a)?;
                r[0] ^= 1;
                Some(r)
            },
            |q, is_a| {
                let mut r = a_record(q, is_a)?;
                r[13] ^= 0x20 | 1;
                Some(r)
            },
        ];
        for (i, respond) in no_answer.into_iter().enumerate() {
            assert_eq!(ask_of(respond).await, Answer::NoAnswer, "case {i}");
        }
        // Malformed: an A record of the wrong length.
        assert_eq!(
            ask_of(|q, is_a| is_a.then(|| reply(q, 0, &[record(&PTR, TYPE_A, &[1, 2, 3])]))).await,
            Answer::NoAnswer
        );
        let lo = IpAddr::from(Ipv4Addr::LOCALHOST);
        let server = serve(a_record).await;
        let deadline = Instant::now() + Duration::from_millis(300);
        assert_eq!(
            ask(lo, server, "rd..com", deadline, None).await,
            Answer::NoAnswer
        );
    }
}
