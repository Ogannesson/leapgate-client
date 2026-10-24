//! Leapgate's own ICE (phase 3 contract 05): host and srflx candidates on physical adapters,
//! signaling relayed by leapgate-server, STUN connectivity checks, then upstream's KCP on the
//! selected pair. The protocol constants and wire formats are those of contract 05 §2.

mod check;
mod gather;
mod sig;
mod stun;

pub use sig::{open_forward, AnswerParams, Bad, Opened};

use crate::lan;
use check::{Base, Check, Kernel, Outcome, Packet, Remote, Reply, Transmit};
use gather::{Socks, GATHER_WAIT, RECV_BUF};
use hbb_common::{
    base64::{engine::general_purpose::STANDARD_NO_PAD, Engine as _},
    bytes::{Bytes, BytesMut},
    rand,
    rendezvous_proto::leapgate_ice_result,
    sodiumoxide::randombytes::{randombytes, randombytes_into},
    tokio::{self, net::UdpSocket},
};
use sig::{Candidate, SESSION_LEN};
use std::{
    net::{IpAddr, SocketAddr},
    sync::Arc,
    time::Instant,
};
use stun::{Creds, Role};

/// A local address ICE binds a socket on, with its adapter's network cost (§2.10).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LocalAddr {
    ip: IpAddr,
    net_cost: u8,
}

impl LocalAddr {
    pub fn new(addr: IpAddr, net_cost: u8) -> Self {
        LocalAddr { ip: addr, net_cost }
    }
}

/// The sockets, candidates and proofs of one gathering, for an `Offer` or an `Agent`.
pub struct Gathered {
    socks: Socks,
    /// Network cost of each socket's adapter.
    nets: Vec<u8>,
    bases: Vec<Base>,
    candidates: Vec<Candidate>,
    proofs: Vec<Bytes>,
    started: Instant,
}

/// The pair the controlling side selected. Hand over with `socket.connect(remote)`.
#[derive(Debug)]
pub struct Selected {
    pub socket: Arc<UdpSocket>,
    pub remote: SocketAddr,
    pub local_kind: leapgate_ice_result::Kind,
    pub remote_kind: leapgate_ice_result::Kind,
    /// 4 or 6.
    pub family: u32,
    pub net: leapgate_ice_result::Net,
}

/// The pair the controlled side's KCP SYN came up, and that SYN, for `KcpStream::accept`.
#[derive(Debug)]
pub struct Accepted {
    pub socket: Arc<UdpSocket>,
    pub remote: SocketAddr,
    pub init_packet: BytesMut,
}

/// No pair selected within `CHECK_TIMEOUT` of the ANSWER.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NoPair;

/// No KCP SYN within `AGENT_TTL` of the FORWARD.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TimedOut;

/// The physical adapters' addresses ICE gathers on (§4.3). Empty: no ICE on this side.
pub async fn local_addrs() -> Vec<LocalAddr> {
    tokio::task::spawn_blocking(|| gather::select(&lan::nics()))
        .await
        .unwrap_or_default()
}

/// A socket on each of `local` (§4.3), asking the rendezvous server `rendezvous` (`host:port`)
/// for srflx candidates, for at most `GATHER_WAIT` including the name lookup.
pub async fn gather(local: &[LocalAddr], rendezvous: &str) -> Gathered {
    let started = Instant::now();
    let deadline = started + GATHER_WAIT;
    let stun =
        match tokio::time::timeout_at(deadline.into(), tokio::net::lookup_host(rendezvous)).await {
            Ok(Ok(addrs)) => addrs.collect(),
            _ => Vec::new(),
        };
    gather::gather_until(local, &stun, started, deadline).await
}

/// `gather` with the STUN addresses given: an IPv4 socket asks the first IPv4 one, an IPv6
/// socket the first IPv6 one, and a family without one gets no srflx.
pub async fn gather_on(local: &[LocalAddr], stun: &[SocketAddr]) -> Gathered {
    let started = Instant::now();
    gather::gather_until(local, stun, started, started + GATHER_WAIT).await
}

/// The NAT self-test of `examples/ice_peer`: the mapping each of `servers` reports for one
/// socket bound on `local`, asked in turn.
pub async fn probe(local: SocketAddr, servers: &[SocketAddr]) -> Vec<Option<SocketAddr>> {
    let Ok(sock) = gather::bind(local).await else {
        return vec![None; servers.len()];
    };
    let mut socks = Socks::new(vec![sock]);
    let mut out = Vec::new();
    for s in servers {
        let mut got = socks.ask(&[Some(*s)], Instant::now() + GATHER_WAIT).await;
        out.push(got.pop().flatten().map(|m| m.addr));
    }
    out
}

impl From<sig::Kind> for check::Kind {
    fn from(k: sig::Kind) -> Self {
        match k {
            sig::Kind::Host => check::Kind::Host,
            sig::Kind::Srflx => check::Kind::Srflx,
        }
    }
}

fn result_kind(k: check::Kind) -> leapgate_ice_result::Kind {
    match k {
        check::Kind::Host => leapgate_ice_result::Kind::HOST,
        check::Kind::Srflx => leapgate_ice_result::Kind::SRFLX,
        check::Kind::Prflx => leapgate_ice_result::Kind::PRFLX,
    }
}

fn result_net(cost: u8) -> leapgate_ice_result::Net {
    if cost == lan::net_cost(lan::IF_TYPE_ETHERNET) {
        leapgate_ice_result::Net::ETHERNET
    } else if cost == lan::net_cost(lan::IF_TYPE_IEEE80211) {
        leapgate_ice_result::Net::WLAN
    } else {
        leapgate_ice_result::Net::OTHER
    }
}

/// §2.3 ①: 6 and 18 random bytes in base64 without padding are 8 and 24 ice-chars.
fn ice_string(random_bytes: usize) -> String {
    STANDARD_NO_PAD.encode(randombytes(random_bytes))
}

fn params(ufrag: &str, pwd: &str, g: &Gathered) -> (String, String, Vec<Bytes>, Vec<Bytes>) {
    (
        ufrag.to_owned(),
        pwd.to_owned(),
        g.candidates.iter().map(Candidate::encode).collect(),
        g.proofs.clone(),
    )
}

fn remotes(p: &AnswerParams) -> Vec<Remote> {
    p.candidates
        .iter()
        .map(|c| Remote {
            kind: c.kind.into(),
            pref: c.pref,
            addr: c.addr,
        })
        .collect()
}

/// The controlling side's ICE attempt.
pub struct Offer {
    session: [u8; SESSION_LEN],
    ufrag: String,
    pwd: String,
    g: Gathered,
}

impl Offer {
    pub fn new(g: Gathered) -> Offer {
        let mut session = [0u8; SESSION_LEN];
        randombytes_into(&mut session);
        Offer {
            session,
            ufrag: ice_string(6),
            pwd: ice_string(18),
            g,
        }
    }

    /// ufrag, pwd, candidates (§2.6) and proofs for the OFFER.
    pub fn params(&self) -> (String, String, Vec<Bytes>, Vec<Bytes>) {
        params(&self.ufrag, &self.pwd, &self.g)
    }

    pub fn session(&self) -> [u8; SESSION_LEN] {
        self.session
    }

    /// Call once the ANSWER is verified: only now are the ICE sockets read, so the peer's checks
    /// that came first are still buffered (§2.9.4).
    pub async fn run(self, remote: AnswerParams) -> Result<Selected, NoPair> {
        let g = self.g;
        let srflx = g
            .candidates
            .iter()
            .filter(|c| c.kind == sig::Kind::Srflx)
            .map(|c| c.addr)
            .collect();
        let kernel = Kernel::controlling(g.bases, srflx, &remotes(&remote), Instant::now());
        let creds = Creds {
            local_ufrag: self.ufrag,
            local_pwd: self.pwd,
            remote_ufrag: remote.ufrag,
            remote_pwd: remote.pwd,
            role: Role::Controlling,
            tie: rand::random(),
        };
        let mut d = Driver {
            socks: g.socks,
            creds,
            kernel,
        };
        match d.run().await {
            End::Outcome(Outcome::Selected(s)) => Ok(Selected {
                socket: d.socks.get(s.socket),
                remote: s.remote,
                local_kind: result_kind(s.local_kind),
                remote_kind: result_kind(s.remote_kind),
                family: if s.remote.is_ipv4() { 4 } else { 6 },
                net: result_net(g.nets[s.socket]),
            }),
            _ => Err(NoPair),
        }
    }
}

/// The controlled side's agent for one FORWARD.
pub struct Agent {
    ufrag: String,
    pwd: String,
    peer: AnswerParams,
    g: Gathered,
}

impl Agent {
    pub fn new(g: Gathered, peer: AnswerParams) -> Agent {
        Agent {
            ufrag: ice_string(6),
            pwd: ice_string(18),
            peer,
            g,
        }
    }

    /// ufrag, pwd, candidates (§2.6) and proofs for the ANSWER.
    pub fn params(&self) -> (String, String, Vec<Bytes>, Vec<Bytes>) {
        params(&self.ufrag, &self.pwd, &self.g)
    }

    /// Answers and starts checks, never nominates, and returns at the first KCP SYN up a pair
    /// the controlling side nominated (§2.9.5). `AGENT_TTL` counts from the start of gathering,
    /// which follows the FORWARD's acceptance at once.
    pub async fn run(self) -> Result<Accepted, TimedOut> {
        let g = self.g;
        let kernel = Kernel::controlled(g.bases, &remotes(&self.peer), Instant::now(), g.started);
        let creds = Creds {
            local_ufrag: self.ufrag,
            local_pwd: self.pwd,
            remote_ufrag: self.peer.ufrag,
            remote_pwd: self.peer.pwd,
            role: Role::Controlled,
            tie: rand::random(),
        };
        let mut d = Driver {
            socks: g.socks,
            creds,
            kernel,
        };
        match d.run().await {
            End::Syn(socket, remote, init_packet) => Ok(Accepted {
                socket: d.socks.get(socket),
                remote,
                init_packet,
            }),
            End::Outcome(_) => Err(TimedOut),
        }
    }
}

enum End {
    Outcome(Outcome),
    Syn(usize, SocketAddr, BytesMut),
}

/// Feeds every socket's datagrams to the kernel and sends what it asks for, in one future: a
/// leg dropped by the race takes all of it along (§4.2).
struct Driver {
    socks: Socks,
    creds: Creds,
    kernel: Kernel,
}

impl Driver {
    async fn run(&mut self) -> End {
        let mut buf = [0u8; RECV_BUF];
        loop {
            while let Some(t) = self.kernel.poll_transmit() {
                self.send(t).await;
            }
            if let Some(o) = self.kernel.outcome() {
                return End::Outcome(o);
            }
            let at = self.kernel.poll_timeout().unwrap_or_else(Instant::now);
            if let Some((i, n, from)) = self.socks.recv(&mut buf, at).await {
                if let Some(syn) = self.feed(i, from, &buf[..n]) {
                    return End::Syn(i, from, syn);
                }
            }
            let now = Instant::now();
            if now >= at {
                self.kernel.handle_timeout(now);
            }
        }
    }

    /// §2.9.2's receive split; `Some` is the controlled side's handover SYN.
    fn feed(&mut self, i: usize, from: SocketAddr, buf: &[u8]) -> Option<BytesMut> {
        let now = Instant::now();
        if !stun::is_stun(buf) {
            let syn = self.creds.role == Role::Controlled
                && stun::is_kcp_syn(buf)
                && self.kernel.nominated(i, from);
            return syn.then(|| BytesMut::from(buf));
        }
        match [buf[0], buf[1]] {
            [0x00, 0x01] => {
                if let Some(r) = self.creds.read_request(buf) {
                    let role = match self.creds.role {
                        Role::Controlling => Role::Controlled,
                        Role::Controlled => Role::Controlling,
                    };
                    let check = Check {
                        txid: r.txid,
                        priority: r.priority,
                        use_candidate: r.nominate,
                        role,
                    };
                    self.kernel.on_request(now, i, from, &check);
                }
            }
            [0x01, 0x01] => {
                let kernel = &self.kernel;
                if let Some((txid, mapped)) = self
                    .creds
                    .read_response(buf, from, |t| kernel.sent_to(i, t))
                {
                    self.kernel
                        .on_response(now, i, from, &Reply { txid, mapped });
                }
            }
            _ => {}
        }
        None
    }

    async fn send(&self, t: Transmit) {
        let bytes = match t.packet {
            Packet::Check(c) => self.creds.request(&c.txid, c.priority, c.use_candidate),
            Packet::Reply(r) => self.creds.response(&r.txid, r.mapped),
        };
        if let Some(b) = bytes {
            self.socks.send(t.socket, &b, t.to).await;
        }
    }
}

#[cfg(test)]
fn hex(s: &str) -> Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{Ipv4Addr, Ipv6Addr};

    /// Upstream's first KCP packet: conv, both session ids 0, SYN.
    const SYN: [u8; 14] = [0x2a, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01, 0x00];

    /// The other side's parameters as the signaling would carry them, without §2.7's filter
    /// (loopback is in its drop class).
    fn answer(
        (ufrag, pwd, candidates, _): (String, String, Vec<Bytes>, Vec<Bytes>),
    ) -> AnswerParams {
        AnswerParams {
            ufrag,
            pwd,
            candidates: candidates
                .iter()
                .map(|b| Candidate::decode(b).unwrap())
                .collect(),
        }
    }

    fn loopback(net_cost: u8) -> [LocalAddr; 2] {
        [
            LocalAddr::new(Ipv4Addr::LOCALHOST.into(), net_cost),
            LocalAddr::new(Ipv6Addr::LOCALHOST.into(), net_cost),
        ]
    }

    /// Runs A and B to the handover, A sending a SYN on the selected pair, then one datagram
    /// each way on the connected sockets.
    async fn hand_over(offer: Offer, agent: Agent, b: AnswerParams) -> Selected {
        let a = async {
            let s = offer.run(b).await.unwrap();
            s.socket.connect(s.remote).await.unwrap();
            s.socket.send(&SYN).await.unwrap();
            s
        };
        let (s, acc) = tokio::join!(a, agent.run());
        let acc = acc.unwrap();
        assert_eq!(&acc.init_packet[..], &SYN);
        assert_eq!(acc.remote, s.socket.local_addr().unwrap());
        assert_eq!(s.remote, acc.socket.local_addr().unwrap());
        acc.socket.connect(acc.remote).await.unwrap();
        let mut buf = [0u8; 16];
        s.socket.send(b"to b").await.unwrap();
        assert_eq!(acc.socket.recv(&mut buf).await.unwrap(), 4);
        assert_eq!(&buf[..4], b"to b");
        acc.socket.send(b"to a").await.unwrap();
        assert_eq!(s.socket.recv(&mut buf).await.unwrap(), 4);
        assert_eq!(&buf[..4], b"to a");
        s
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn loopback_agents_select_and_hand_over() {
        let offer = Offer::new(gather_on(&loopback(0), &[]).await);
        let agent = Agent::new(gather_on(&loopback(0), &[]).await, answer(offer.params()));
        let b = answer(agent.params());
        let s = hand_over(offer, agent, b).await;
        // §2.10: IPv4 ranks above IPv6 on the same adapter.
        assert_eq!(s.family, 4);
        assert_eq!(s.local_kind, leapgate_ice_result::Kind::HOST);
        assert_eq!(s.remote_kind, leapgate_ice_result::Kind::HOST);
        assert_eq!(s.net, leapgate_ice_result::Net::ETHERNET);
    }

    /// B's best-ranked candidate is a closed port, so A's first check draws an ICMP port
    /// unreachable onto its socket.
    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn icmp_from_a_dead_candidate_does_not_stop_selection() {
        let closed = std::net::UdpSocket::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap();
        let offer = Offer::new(gather_on(&loopback(0), &[]).await);
        let agent = Agent::new(gather_on(&loopback(50), &[]).await, answer(offer.params()));
        let mut b = answer(agent.params());
        let real = b.candidates[0].addr;
        b.candidates.insert(
            0,
            Candidate {
                kind: sig::Kind::Host,
                pref: 0xFFFF,
                addr: closed,
            },
        );
        let s = hand_over(offer, agent, b).await;
        assert_eq!(s.remote, real);
    }

    #[allow(dead_code)]
    fn runs_are_send(offer: Offer, agent: Agent, p: AnswerParams) {
        fn send<T: Send>(_: T) {}
        send(offer.run(p));
        send(agent.run());
    }
}
