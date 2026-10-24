//! Gathering (contract 05 §4.3): which local addresses ICE uses, one UDP socket bound on each,
//! and the srflx candidates the rendezvous server reports for them.

use super::{
    check::{candidate_priority, local_pref, Base, PENALTY_GLOBAL_V6, PENALTY_ULA, PENALTY_V4},
    sig::{classify, is_ula, Candidate, Class, Kind},
    stun::{binding_request, new_txid, read_binding_response, Mapped},
    Gathered, LocalAddr,
};
use crate::lan::{net_cost, one_per_prefix, Nic};
use hbb_common::{
    bytes::Bytes,
    log,
    tokio::{self, io::ReadBuf, net::UdpSocket},
};
use std::{
    cmp::Reverse,
    future::poll_fn,
    io,
    net::{IpAddr, SocketAddr},
    sync::Arc,
    task::{Context, Poll},
    time::{Duration, Instant},
};

pub(super) const GATHER_WAIT: Duration = Duration::from_millis(600);
/// Send times of a Binding request, from the first send.
const BINDING_SENDS: [Duration; 3] = [
    Duration::from_millis(0),
    Duration::from_millis(200),
    Duration::from_millis(400),
];
pub(super) const RECV_BUF: usize = 1500;
/// After a receive error, as `kcp_io` does: a lasting one (adapter gone) must not spin the driver.
const RECV_ERROR_PAUSE: Duration = Duration::from_millis(10);
const MAX_SOCKETS: usize = 8;
const MAX_HOST_V4: usize = 4;
const MAX_HOST_V6: usize = 4;
const MAX_SRFLX_V4: usize = 4;
const MAX_SRFLX_V6: usize = 2;

/// §2.10's address family penalty.
fn penalty(ip: IpAddr) -> u16 {
    match ip {
        IpAddr::V4(_) => PENALTY_V4,
        IpAddr::V6(ip) if is_ula(ip) => PENALTY_ULA,
        IpAddr::V6(_) => PENALTY_GLOBAL_V6,
    }
}

/// The host addresses, best first within each family: adapters that can give candidates, the
/// cheapest network first and then the fastest link.
pub(super) fn select(nics: &[Nic]) -> Vec<LocalAddr> {
    let mut usable: Vec<&Nic> = nics.iter().filter(|n| n.can_gather()).collect();
    usable.sort_by_key(|n| (net_cost(n.if_type), Reverse(n.speed)));
    let (mut v4, mut v6) = (Vec::new(), Vec::new());
    let add = |list: &mut Vec<LocalAddr>, ip: IpAddr, cost: u8, cap: usize| {
        if list.len() < cap && !list.iter().any(|a| a.ip == ip) {
            list.push(LocalAddr::new(ip, cost));
        }
    };
    for n in usable {
        let cost = net_cost(n.if_type);
        if n.has_gateway_v4 {
            for &ip in &n.ipv4 {
                if matches!(classify(ip.into()), Class::PrivateV4 | Class::PublicV4) {
                    add(&mut v4, ip.into(), cost, MAX_HOST_V4);
                }
            }
        }
        for ip in one_per_prefix(&n.ipv6) {
            if matches!(classify(ip.into()), Class::GlobalV6 | Class::Ula) {
                add(&mut v6, ip.into(), cost, MAX_HOST_V6);
            }
        }
    }
    v4.extend(v6);
    v4
}

/// A socket bound to `addr`, which on Windows no longer reports ICMP errors (§4.3).
pub(super) async fn bind(addr: SocketAddr) -> io::Result<(UdpSocket, SocketAddr)> {
    let s = UdpSocket::bind(addr).await?;
    #[cfg(windows)]
    no_connreset(&s)?;
    let local = s.local_addr()?;
    Ok((s, local))
}

/// Otherwise a port unreachable for an earlier send fails the next `recv_from` with 10054, and
/// the peer's candidates that draw ICMP (a TUN address, a closed port) would cost us the socket
/// (note 06 §9.1). Set before the first send, so there is no window.
#[cfg(windows)]
fn no_connreset(s: &UdpSocket) -> io::Result<()> {
    use std::os::windows::io::AsRawSocket;
    use windows::Win32::Networking::WinSock::{WSAIoctl, SIO_UDP_CONNRESET, SOCKET};
    let enable: u32 = 0;
    let mut ret: u32 = 0;
    // SAFETY: a socket this process owns, a 4-byte input that outlives the synchronous call, and
    // no output buffer or overlapped structure.
    let r = unsafe {
        WSAIoctl(
            SOCKET(s.as_raw_socket() as usize),
            SIO_UDP_CONNRESET,
            Some(&enable as *const u32 as _),
            4,
            None,
            0,
            &mut ret,
            None,
            None,
        )
    };
    if r != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

/// The ICE sockets, read from one task. A receive error on one pauses that socket briefly and
/// never ends the loop (§4.3).
pub(super) struct Socks {
    socks: Vec<Arc<UdpSocket>>,
    local: Vec<SocketAddr>,
    paused: Vec<Option<Instant>>,
    next: usize,
}

impl Socks {
    pub(super) fn new(socks: Vec<(UdpSocket, SocketAddr)>) -> Self {
        let (socks, local): (Vec<_>, Vec<_>) =
            socks.into_iter().map(|(s, a)| (Arc::new(s), a)).unzip();
        Socks {
            paused: vec![None; socks.len()],
            socks,
            local,
            next: 0,
        }
    }

    pub(super) fn get(&self, i: usize) -> Arc<UdpSocket> {
        self.socks[i].clone()
    }

    pub(super) async fn send(&self, i: usize, buf: &[u8], to: SocketAddr) {
        if let Err(e) = self.socks[i].send_to(buf, to).await {
            log::trace!("leapgate ice: send on socket {}: {}", i, e);
        }
    }

    /// The next datagram as (socket, length, source), or `None` once `deadline` has passed.
    pub(super) async fn recv(
        &mut self,
        buf: &mut [u8],
        deadline: Instant,
    ) -> Option<(usize, usize, SocketAddr)> {
        loop {
            let now = Instant::now();
            let wake = self
                .paused
                .iter()
                .flatten()
                .filter(|&&t| t > now)
                .fold(deadline, |a, &t| a.min(t));
            let got = tokio::select! {
                biased;
                r = poll_fn(|cx| self.poll_recv(cx, buf, now)) => Some(r),
                _ = tokio::time::sleep_until(wake.into()) => None,
            };
            match got {
                Some(Ok(d)) => return Some(d),
                Some(Err(i)) => self.paused[i] = Some(now + RECV_ERROR_PAUSE),
                None if Instant::now() >= deadline => return None,
                None => {}
            }
        }
    }

    fn poll_recv(
        &mut self,
        cx: &mut Context<'_>,
        buf: &mut [u8],
        now: Instant,
    ) -> Poll<Result<(usize, usize, SocketAddr), usize>> {
        let n = self.socks.len();
        for k in 0..n {
            let i = (self.next + k) % n;
            if self.paused[i].is_some_and(|t| t > now) {
                continue;
            }
            let mut rb = ReadBuf::new(buf);
            match self.socks[i].poll_recv_from(cx, &mut rb) {
                Poll::Ready(Ok(from)) => {
                    self.next = (i + 1) % n;
                    return Poll::Ready(Ok((i, rb.filled().len(), from)));
                }
                Poll::Ready(Err(e)) => {
                    log::trace!("leapgate ice: recv on socket {}: {}", i, e);
                    return Poll::Ready(Err(i));
                }
                Poll::Pending => {}
            }
        }
        Poll::Pending
    }

    /// Asks `targets[i]` for socket `i`'s mapped address (§2.9.3), resending at 200 and 400 ms,
    /// until every target answered or `deadline`.
    pub(super) async fn ask(
        &mut self,
        targets: &[Option<SocketAddr>],
        deadline: Instant,
    ) -> Vec<Option<Mapped>> {
        let txids: Vec<_> = targets.iter().map(|_| new_txid()).collect();
        let mut got: Vec<Option<Mapped>> = vec![None; targets.len()];
        let mut buf = [0u8; RECV_BUF];
        let start = Instant::now();
        let mut sends = 0;
        loop {
            let now = Instant::now();
            while sends < BINDING_SENDS.len() && now >= start + BINDING_SENDS[sends] {
                for (i, t) in targets.iter().enumerate() {
                    if let (Some(to), None) = (t, &got[i]) {
                        self.send(i, &binding_request(&txids[i]), *to).await;
                    }
                }
                sends += 1;
            }
            if targets
                .iter()
                .zip(&got)
                .all(|(t, g)| t.is_none() || g.is_some())
            {
                return got;
            }
            let next = BINDING_SENDS
                .get(sends)
                .map_or(deadline, |&d| deadline.min(start + d));
            match self.recv(&mut buf, next).await {
                Some((i, n, _)) if got[i].is_none() => {
                    got[i] = read_binding_response(&buf[..n], &txids[i], self.local[i]);
                }
                None if Instant::now() >= deadline => return got,
                _ => {}
            }
        }
    }
}

/// The candidates, best first, and each socket's host local preference. `bound[i]` is the
/// address socket `i` was asked for and the one it got; `mapped[i]` is what S saw of it.
fn assemble(
    bound: &[(LocalAddr, SocketAddr)],
    mapped: &[Option<SocketAddr>],
) -> (Vec<Candidate>, Vec<u16>) {
    let index = |list: &[Candidate], kind: Kind, p: u16| {
        list.iter()
            .filter(|c| c.kind == kind && penalty(c.addr.ip()) == p)
            .count() as u16
    };
    let mut out: Vec<Candidate> = Vec::new();
    let mut prefs = Vec::new();
    for (local, addr) in bound {
        let p = penalty(addr.ip());
        let pref = local_pref(local.net_cost as u16, p, index(&out, Kind::Host, p));
        prefs.push(pref);
        out.push(Candidate {
            kind: Kind::Host,
            pref,
            addr: *addr,
        });
    }
    for ((local, _), m) in bound.iter().zip(mapped) {
        let Some(m) = *m else { continue };
        let cap = if m.is_ipv4() {
            MAX_SRFLX_V4
        } else {
            MAX_SRFLX_V6
        };
        let same_family = out
            .iter()
            .filter(|c| c.kind == Kind::Srflx && c.addr.is_ipv4() == m.is_ipv4())
            .count();
        if same_family >= cap || out.iter().any(|c| c.addr == m) {
            continue;
        }
        let p = penalty(m.ip());
        let pref = local_pref(local.net_cost as u16, p, index(&out, Kind::Srflx, p));
        out.push(Candidate {
            kind: Kind::Srflx,
            pref,
            addr: m,
        });
    }
    out.sort_by_key(|c| Reverse(candidate_priority(c.kind.into(), c.pref)));
    (out, prefs)
}

/// One socket per local address, each asking S's address of its family (`stun`) for its
/// mapping until `deadline`.
pub(super) async fn gather_until(
    local: &[LocalAddr],
    stun: &[SocketAddr],
    started: Instant,
    deadline: Instant,
) -> Gathered {
    let mut socks = Vec::new();
    let mut bound = Vec::new();
    for l in local.iter().take(MAX_SOCKETS) {
        match bind(SocketAddr::new(l.ip, 0)).await {
            Ok((s, addr)) => {
                socks.push((s, addr));
                bound.push((*l, addr));
            }
            Err(e) => log::trace!("leapgate ice: bind {}: {}", l.ip, e),
        }
    }
    let mut socks = Socks::new(socks);
    let targets: Vec<_> = bound
        .iter()
        .map(|(_, a)| stun.iter().find(|s| s.is_ipv4() == a.is_ipv4()).copied())
        .collect();
    let answers = socks.ask(&targets, deadline).await;
    let mapped: Vec<_> = answers.iter().map(|m| m.as_ref().map(|m| m.addr)).collect();
    let (candidates, prefs) = assemble(&bound, &mapped);
    Gathered {
        socks,
        nets: bound.iter().map(|(l, _)| l.net_cost).collect(),
        bases: bound
            .iter()
            .zip(prefs)
            .map(|((_, addr), pref)| Base { addr: *addr, pref })
            .collect(),
        candidates,
        proofs: answers
            .into_iter()
            .flatten()
            .filter_map(|m| m.proof.map(Bytes::from))
            .collect(),
        started,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lan::{Suffix, IF_TYPE_ETHERNET, IF_TYPE_IEEE80211, V6};

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    fn sa(s: &str) -> SocketAddr {
        s.parse().unwrap()
    }

    fn nic(if_type: u32, v4: &[&str], gw_v4: bool, v6: &[(&str, Suffix)], gw_v6: bool) -> Nic {
        Nic {
            name: "Ethernet".to_owned(),
            if_type,
            up: true,
            ipv4: v4.iter().map(|a| a.parse().unwrap()).collect(),
            ipv6: v6
                .iter()
                .map(|&(a, suffix)| V6 {
                    ip: a.parse().unwrap(),
                    suffix,
                })
                .collect(),
            has_gateway_v4: gw_v4,
            has_gateway_v6: gw_v6,
            ..Default::default()
        }
    }

    #[test]
    fn host_addresses_come_from_adapters_with_a_gateway() {
        let wlan = nic(IF_TYPE_IEEE80211, &["192.168.1.20"], true, &[], false);
        let eth = nic(
            IF_TYPE_ETHERNET,
            &[
                "192.168.1.10",
                "169.254.3.4",
                "10.0.0.1",
                "10.0.0.2",
                "10.0.0.3",
            ],
            true,
            &[
                ("2408:8256::10", Suffix::Other),
                ("2408:8256::abcd", Suffix::Temporary),
                ("fd00::1", Suffix::Other),
                ("fdfe:dcba:9876::1", Suffix::Other),
            ],
            true,
        );
        // IPv6 gateway only: its IPv4 address gives no candidate.
        let v6_only = nic(
            0,
            &["172.16.0.5"],
            false,
            &[("2001:db8:1::5", Suffix::Dhcp)],
            true,
        );
        // A Hyper-V internal switch: no gateway at all.
        let internal = nic(IF_TYPE_ETHERNET, &["172.20.0.1"], false, &[], false);
        let mut vmware = nic(IF_TYPE_ETHERNET, &["192.168.50.1"], true, &[], false);
        vmware.description = "VMware Virtual Ethernet Adapter for VMnet8".to_owned();
        // Its second /64 would be a fifth IPv6 address.
        let more_v6 = nic(
            0,
            &[],
            false,
            &[
                ("2001:db8:2::1", Suffix::Other),
                ("2001:db8:3::1", Suffix::Other),
            ],
            true,
        );
        let got = select(&[wlan, v6_only, internal, vmware, eth, more_v6]);
        let want = [
            ("192.168.1.10", 0),
            ("10.0.0.1", 0),
            ("10.0.0.2", 0),
            ("10.0.0.3", 0),
            ("2408:8256::abcd", 0),
            ("fd00::1", 0),
            ("2001:db8:1::5", 50),
            ("2001:db8:2::1", 50),
        ]
        .map(|(a, cost)| LocalAddr::new(ip(a), cost));
        assert_eq!(got, want);
        assert_eq!(select(&[]), vec![]);
    }

    #[test]
    fn candidates_rank_by_network_family_and_order() {
        let bound = [
            ("192.168.1.10", 0),
            ("192.168.1.20", 10),
            ("2408:8256::abcd", 0),
            ("fd00::1", 0),
        ]
        .map(|(a, cost)| (LocalAddr::new(ip(a), cost), SocketAddr::new(ip(a), 5000)));
        let public = sa("203.0.113.7:40000");
        // Both IPv4 sockets map to the same address; the IPv6 one maps to itself (no NAT66).
        let mapped = [Some(public), Some(public), Some(bound[2].1), None];
        let (got, prefs) = assemble(&bound, &mapped);
        assert_eq!(prefs, [65535, 65535 - 640 - 1, 65535 - 8, 65535 - 16]);
        let want = [
            (Kind::Host, 65535, bound[0].1),
            (Kind::Host, 65527, bound[2].1),
            (Kind::Host, 65519, bound[3].1),
            (Kind::Host, 64894, bound[1].1),
            (Kind::Srflx, 65535, public),
        ]
        .map(|(kind, pref, addr)| Candidate { kind, pref, addr });
        assert_eq!(got, want);

        // Five sockets, each mapped to an address of its own.
        let srflx = |host: &dyn Fn(i32) -> String, map: &dyn Fn(i32) -> String| {
            let bound: Vec<_> = (1..=5)
                .map(|i| {
                    let a = SocketAddr::new(ip(&host(i)), 5000);
                    (LocalAddr::new(a.ip(), 0), a)
                })
                .collect();
            let mapped: Vec<_> = (1..=5)
                .map(|i| Some(SocketAddr::new(ip(&map(i)), 7000)))
                .collect();
            let (got, _) = assemble(&bound, &mapped);
            got.iter().filter(|c| c.kind == Kind::Srflx).count()
        };
        let v4 = srflx(&|i| format!("192.168.{i}.1"), &|i| format!("203.0.113.{i}"));
        let v6 = srflx(&|i| format!("2408:8256:{i}::1"), &|i| format!("2001:db8::{i}"));
        assert_eq!((v4, v6), (4, 2));
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn at_most_eight_sockets() {
        let local = [LocalAddr::new(ip("127.0.0.1"), 0); 9];
        let g = super::super::gather_on(&local, &[]).await;
        assert_eq!(g.bases.len(), 8);
    }

    /// S drops the first Binding request and answers the resend.
    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn binding_is_resent_and_its_proof_kept() {
        use super::super::stun::{Attribute, LeapgateProof};
        use bytecodec::EncodeExt;
        use stun_codec::{
            rfc5389::{
                attributes::{Fingerprint, XorMappedAddress},
                methods::BINDING,
            },
            Message, MessageClass, MessageEncoder, TransactionId,
        };
        let server = UdpSocket::bind("127.0.0.1:0").await.unwrap();
        let to = server.local_addr().unwrap();
        let (public, proof) = (sa("203.0.113.7:40000"), vec![1u8; 28]);
        let answer = {
            let proof = proof.clone();
            async move {
                let mut buf = [0u8; 200];
                let mut seen = 0;
                loop {
                    let (n, from) = server.recv_from(&mut buf).await.unwrap();
                    assert_eq!(n, 100);
                    seen += 1;
                    if seen == 1 {
                        continue;
                    }
                    let id = TransactionId::new(buf[8..20].try_into().unwrap());
                    let mut m =
                        Message::<Attribute>::new(MessageClass::SuccessResponse, BINDING, id);
                    m.add_attribute(XorMappedAddress::new(public));
                    m.add_attribute(LeapgateProof(proof.clone()));
                    let fp = Fingerprint::new(&m).unwrap();
                    m.add_attribute(fp);
                    let bytes = MessageEncoder::new().encode_into_bytes(m).unwrap();
                    server.send_to(&bytes, from).await.unwrap();
                    return seen;
                }
            }
        };
        let local = [LocalAddr::new(ip("127.0.0.1"), 0)];
        let t0 = Instant::now();
        let stun = [to];
        let (g, seen) = tokio::join!(
            super::super::gather_on(&local, &stun),
            tokio::time::timeout(GATHER_WAIT * 2, answer)
        );
        assert_eq!(seen.expect("the Binding request was not resent"), 2);
        assert!(t0.elapsed() < GATHER_WAIT);
        assert!(g
            .candidates
            .iter()
            .any(|c| c.kind == Kind::Srflx && c.addr == public));
        assert_eq!(g.proofs, vec![Bytes::from(proof)]);
    }

    /// Fails if `bind` stops turning off SIO_UDP_CONNRESET.
    #[cfg(windows)]
    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn icmp_port_unreachable_does_not_fail_recv() {
        let closed = std::net::UdpSocket::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap();
        let (s, _) = bind(sa("127.0.0.1:0")).await.unwrap();
        s.send_to(b"x", closed).await.unwrap();
        let mut buf = [0u8; 16];
        let r = tokio::time::timeout(Duration::from_millis(200), s.recv_from(&mut buf)).await;
        assert!(r.is_err(), "recv_from returned {:?}", r);
    }

    /// WSAEMSGSIZE for a datagram longer than `RECV_BUF`, then a good one on the same socket.
    #[cfg(windows)]
    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn a_receive_error_does_not_stop_the_socket() {
        let (s, at) = bind(sa("127.0.0.1:0")).await.unwrap();
        let mut socks = Socks::new(vec![(s, at)]);
        let peer = std::net::UdpSocket::bind("127.0.0.1:0").unwrap();
        peer.send_to(&[0u8; RECV_BUF + 100], at).unwrap();
        peer.send_to(b"ok", at).unwrap();
        let mut buf = [0u8; RECV_BUF];
        let deadline = Instant::now() + Duration::from_millis(500);
        let got = socks.recv(&mut buf, deadline).await;
        assert_eq!(got.map(|(i, n, _)| (i, n)), Some((0, 2)));
    }
}
