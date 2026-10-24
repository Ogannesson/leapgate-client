//! Sans-IO connectivity-check kernel (contract 05 §4.5). It is fed checks and responses that
//! already passed §2.9.4 validation, plus the passage of time, and says what to send on which
//! socket, when to wake next and which pair was selected; the driver owns the sockets. Roles are
//! fixed (A controlling, B controlled), one component, no freezing, no trickle.

use super::stun::{new_txid, Role};
use std::{
    collections::VecDeque,
    net::SocketAddr,
    time::{Duration, Instant},
};

pub(crate) const TYPE_PREF_HOST: u32 = 126;
pub(crate) const TYPE_PREF_PRFLX: u32 = 110;
pub(crate) const TYPE_PREF_SRFLX: u32 = 100;
pub(crate) const PENALTY_V4: u16 = 0;
pub(crate) const PENALTY_GLOBAL_V6: u16 = 8;
pub(crate) const PENALTY_ULA: u16 = 16;

pub(crate) const MAX_PAIRS: usize = 32;
pub(crate) const MAX_PRFLX: usize = 4;
pub(crate) const CHECK_PACE: Duration = Duration::from_millis(20);
/// Send times of one check, counted from its first send.
pub(crate) const CHECK_RTO: [Duration; 5] = [
    Duration::from_millis(0),
    Duration::from_millis(100),
    Duration::from_millis(300),
    Duration::from_millis(700),
    Duration::from_millis(1500),
];
/// A check with no response this long after its first send has failed.
pub(crate) const CHECK_GIVE_UP: Duration = Duration::from_millis(2300);
pub(crate) const NOMINATE_WAIT_HOST: Duration = Duration::from_millis(100);
pub(crate) const NOMINATE_WAIT_OTHER: Duration = Duration::from_millis(300);
/// A: from receiving the ANSWER.
pub(crate) const CHECK_TIMEOUT: Duration = Duration::from_millis(3000);
/// B: from accepting the FORWARD.
pub(crate) const AGENT_TTL: Duration = Duration::from_secs(10);

/// §2.10: `65535 − 64 × network cost − address family penalty − index`.
pub(crate) fn local_pref(net_cost: u16, penalty: u16, index: u16) -> u16 {
    65535 - 64 * net_cost - penalty - index
}

/// §2.10; the type preference is always the receiver's, by kind.
pub(crate) fn candidate_priority(kind: Kind, local_pref: u16) -> u32 {
    let type_pref = match kind {
        Kind::Host => TYPE_PREF_HOST,
        Kind::Prflx => TYPE_PREF_PRFLX,
        Kind::Srflx => TYPE_PREF_SRFLX,
    };
    (type_pref << 24) | ((local_pref as u32) << 8) | 255
}

/// §2.10, RFC 8445 §6.1.2.3: `g` is the controlling side's candidate, `d` the controlled side's.
pub(crate) fn pair_priority(g: u32, d: u32) -> u64 {
    (1u64 << 32) * g.min(d) as u64 + 2 * g.max(d) as u64 + (g > d) as u64
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Kind {
    Host,
    Srflx,
    Prflx,
}

/// One local socket: the address it is bound to (the base of its host candidate and of any
/// srflx learned through it) and that host candidate's local preference.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Base {
    pub addr: SocketAddr,
    pub pref: u16,
}

/// A peer candidate from signaling, `Host` or `Srflx`.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Remote {
    pub kind: Kind,
    pub pref: u16,
    pub addr: SocketAddr,
}

/// A check request, received or to send.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Check {
    pub txid: [u8; 12],
    pub priority: u32,
    pub use_candidate: bool,
}

/// A check success response, received or to send.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Reply {
    pub txid: [u8; 12],
    pub mapped: SocketAddr,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Packet {
    Check(Check),
    Reply(Reply),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Transmit {
    pub socket: usize,
    pub to: SocketAddr,
    pub packet: Packet,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Selection {
    pub socket: usize,
    pub remote: SocketAddr,
    pub local_kind: Kind,
    pub remote_kind: Kind,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Outcome {
    /// A only.
    Selected(Selection),
    /// A: nothing selected within `CHECK_TIMEOUT`. B: `AGENT_TTL` is up.
    Failed,
}

struct Tx {
    txid: [u8; 12],
    first: Instant,
    sent: usize,
}

enum Step {
    Wait,
    Send,
    GiveUp,
}

impl Tx {
    fn new(now: Instant) -> Self {
        Tx {
            txid: new_txid(),
            first: now,
            sent: 1,
        }
    }

    fn step(&mut self, now: Instant) -> Step {
        let elapsed = now.saturating_duration_since(self.first);
        if elapsed >= CHECK_GIVE_UP {
            return Step::GiveUp;
        }
        let due = CHECK_RTO.iter().filter(|&&at| elapsed >= at).count();
        if due > self.sent {
            self.sent = due;
            Step::Send
        } else {
            Step::Wait
        }
    }

    fn next(&self) -> Instant {
        self.first + CHECK_RTO.get(self.sent).copied().unwrap_or(CHECK_GIVE_UP)
    }
}

enum State {
    Waiting,
    InProgress(Tx),
    Succeeded { mapped: SocketAddr },
    Failed,
}

struct Pair {
    socket: usize,
    remote: SocketAddr,
    remote_kind: Kind,
    priority: u64,
    state: State,
    nominated: bool,
}

impl Pair {
    fn pending(&self) -> bool {
        matches!(self.state, State::Waiting | State::InProgress(_))
    }
}

pub(crate) struct Kernel {
    role: Role,
    bases: Vec<Base>,
    srflx: Vec<SocketAddr>,
    /// Remote addresses from signaling plus the prflx learned so far.
    known: Vec<SocketAddr>,
    pairs: Vec<Pair>,
    prflx: usize,
    triggered: VecDeque<usize>,
    next_check: Instant,
    first_valid: Option<Instant>,
    nominating: Option<(usize, Tx)>,
    /// B: (socket, remote) of every pair a valid USE-CANDIDATE request came in on.
    nominated: Vec<(usize, SocketAddr)>,
    deadline: Instant,
    outcome: Option<Outcome>,
    out: VecDeque<Transmit>,
}

impl Kernel {
    /// A, on receiving the ANSWER. `bases` are indexed by socket; `srflx` are the mapped
    /// addresses gathered from S, used only to tell the selected pair's local kind.
    pub(crate) fn controlling(
        bases: Vec<Base>,
        srflx: Vec<SocketAddr>,
        remote: &[Remote],
        now: Instant,
    ) -> Self {
        Self::new(
            Role::Controlling,
            bases,
            srflx,
            remote,
            now,
            now + CHECK_TIMEOUT,
        )
    }

    /// B, once gathered; `accepted` is when the FORWARD was accepted.
    pub(crate) fn controlled(
        bases: Vec<Base>,
        remote: &[Remote],
        now: Instant,
        accepted: Instant,
    ) -> Self {
        Self::new(
            Role::Controlled,
            bases,
            Vec::new(),
            remote,
            now,
            accepted + AGENT_TTL,
        )
    }

    fn new(
        role: Role,
        bases: Vec<Base>,
        srflx: Vec<SocketAddr>,
        remote: &[Remote],
        now: Instant,
        deadline: Instant,
    ) -> Self {
        // A local srflx pairs through its base, which already pairs as a host candidate with a
        // higher priority, so every srflx pair is a duplicate (RFC 8445 §6.1.2.4); none is built.
        let mut pairs = Vec::new();
        for (socket, b) in bases.iter().enumerate() {
            for r in remote
                .iter()
                .filter(|r| r.addr.is_ipv4() == b.addr.is_ipv4())
            {
                let local = candidate_priority(Kind::Host, b.pref);
                let priority = Self::priority(role, local, candidate_priority(r.kind, r.pref));
                pairs.push(Pair {
                    socket,
                    remote: r.addr,
                    remote_kind: r.kind,
                    priority,
                    state: State::Waiting,
                    nominated: false,
                });
            }
        }
        pairs.sort_by(|a, b| b.priority.cmp(&a.priority));
        let mut seen = Vec::new();
        pairs.retain(|p| {
            let key = (p.socket, p.remote);
            !seen.contains(&key) && {
                seen.push(key);
                true
            }
        });
        pairs.truncate(MAX_PAIRS);
        Kernel {
            role,
            bases,
            srflx,
            known: remote.iter().map(|r| r.addr).collect(),
            pairs,
            prflx: 0,
            triggered: VecDeque::new(),
            next_check: now,
            first_valid: None,
            nominating: None,
            nominated: Vec::new(),
            deadline,
            outcome: None,
            out: VecDeque::new(),
        }
    }

    fn priority(role: Role, local: u32, remote: u32) -> u64 {
        match role {
            Role::Controlling => pair_priority(local, remote),
            Role::Controlled => pair_priority(remote, local),
        }
    }

    pub(crate) fn outcome(&self) -> Option<Outcome> {
        self.outcome
    }

    /// B: whether a KCP SYN on `socket` from `from` comes up a nominated pair (§2.9.5).
    pub(crate) fn nominated(&self, socket: usize, from: SocketAddr) -> bool {
        self.nominated.contains(&(socket, from))
    }

    pub(crate) fn poll_transmit(&mut self) -> Option<Transmit> {
        self.out.pop_front()
    }

    /// When to call `handle_timeout` next; `None` once there is an outcome.
    pub(crate) fn poll_timeout(&self) -> Option<Instant> {
        if self.outcome.is_some() {
            return None;
        }
        let mut at = self.deadline;
        if self.checking() {
            for p in &self.pairs {
                if let State::InProgress(tx) = &p.state {
                    at = at.min(tx.next());
                }
            }
            if let Some((_, tx)) = &self.nominating {
                at = at.min(tx.next());
            }
            if self.pairs.iter().any(|p| matches!(p.state, State::Waiting)) {
                at = at.min(self.next_check);
            }
            if let Some((_, t)) = self.nominee() {
                at = at.min(t);
            }
        }
        Some(at)
    }

    pub(crate) fn handle_timeout(&mut self, now: Instant) {
        self.drive(now);
    }

    /// A request that passed §2.9.4 steps 1~5 on `socket` from `from`.
    pub(crate) fn on_request(
        &mut self,
        now: Instant,
        socket: usize,
        from: SocketAddr,
        check: &Check,
    ) {
        if self.outcome.is_some() {
            return;
        }
        self.out.push_back(Transmit {
            socket,
            to: from,
            packet: Packet::Reply(Reply {
                txid: check.txid,
                mapped: from,
            }),
        });
        if self.role == Role::Controlled
            && check.use_candidate
            && !self.nominated(socket, from)
            && self.nominated.len() < MAX_PAIRS
        {
            self.nominated.push((socket, from));
        }
        match self
            .pairs
            .iter()
            .position(|p| p.socket == socket && p.remote == from)
        {
            // Only a pair never checked moves up: a failed one is not restarted, so each pair
            // is checked at most once and the packets an agent sends stay bounded (§2.9.4 step 6).
            Some(i) => {
                if matches!(self.pairs[i].state, State::Waiting) && !self.triggered.contains(&i) {
                    self.triggered.push_front(i);
                }
            }
            None if !self.known.contains(&from) && self.prflx < MAX_PRFLX => {
                self.prflx += 1;
                self.known.push(from);
                // Only the low 24 bits are the peer's: the type preference stays ours (§2.10).
                let remote = (TYPE_PREF_PRFLX << 24) | (check.priority & 0x00FF_FFFF);
                let local = candidate_priority(Kind::Host, self.bases[socket].pref);
                self.pairs.push(Pair {
                    socket,
                    remote: from,
                    remote_kind: Kind::Prflx,
                    priority: Self::priority(self.role, local, remote),
                    state: State::Waiting,
                    nominated: false,
                });
                self.triggered.push_front(self.pairs.len() - 1);
            }
            None => {}
        }
        self.drive(now);
    }

    /// A success response that passed §2.9.4's response checks (format, MESSAGE-INTEGRITY with
    /// the peer's pwd) on `socket` from `from`.
    pub(crate) fn on_response(
        &mut self,
        now: Instant,
        socket: usize,
        from: SocketAddr,
        reply: &Reply,
    ) {
        if self.outcome.is_some() {
            return;
        }
        if let Some((i, tx)) = &self.nominating {
            let p = &self.pairs[*i];
            if p.socket == socket && tx.txid == reply.txid {
                if from == p.remote {
                    self.outcome = Some(Outcome::Selected(Selection {
                        socket,
                        remote: from,
                        local_kind: self.local_kind(socket, reply.mapped),
                        remote_kind: p.remote_kind,
                    }));
                }
                return;
            }
        }
        let hit = self.pairs.iter_mut().find(|p| {
            p.socket == socket && matches!(&p.state, State::InProgress(tx) if tx.txid == reply.txid)
        });
        // RFC 8445 §7.2.5.2.1: a response from anywhere but where the check went is not one.
        if let Some(p) = hit.filter(|p| p.remote == from) {
            p.state = State::Succeeded {
                mapped: reply.mapped,
            };
            self.first_valid.get_or_insert(now);
        }
        self.drive(now);
    }

    /// RFC 8445 §7.2.5.3.1: the pair's local side is always the base, so the kind comes from
    /// the address the peer saw.
    fn local_kind(&self, socket: usize, mapped: SocketAddr) -> Kind {
        if mapped == self.bases[socket].addr {
            Kind::Host
        } else if self.srflx.contains(&mapped) {
            Kind::Srflx
        } else {
            Kind::Prflx
        }
    }

    /// B stops starting and resending checks once nominated, to cut late packets (§2.9.5).
    fn checking(&self) -> bool {
        self.role == Role::Controlling || self.nominated.is_empty()
    }

    /// A: the best valid pair not yet nominated and when to nominate it (§4.5).
    fn nominee(&self) -> Option<(usize, Instant)> {
        if self.role != Role::Controlling || self.nominating.is_some() {
            return None;
        }
        let (i, best) = self
            .pairs
            .iter()
            .enumerate()
            .filter(|(_, p)| !p.nominated && matches!(p.state, State::Succeeded { .. }))
            .max_by_key(|(_, p)| p.priority)?;
        let first_valid = self.first_valid?;
        if !self
            .pairs
            .iter()
            .any(|p| p.priority > best.priority && p.pending())
        {
            return Some((i, first_valid));
        }
        let host = matches!(best.state, State::Succeeded { mapped } if mapped == self.bases[best.socket].addr)
            && best.remote_kind == Kind::Host;
        let wait = if host {
            NOMINATE_WAIT_HOST
        } else {
            NOMINATE_WAIT_OTHER
        };
        Some((i, first_valid + wait))
    }

    fn check(&mut self, i: usize, txid: [u8; 12], use_candidate: bool) {
        let p = &self.pairs[i];
        self.out.push_back(Transmit {
            socket: p.socket,
            to: p.remote,
            packet: Packet::Check(Check {
                txid,
                // §2.9.4: the base host candidate's priority as if it were prflx.
                priority: candidate_priority(Kind::Prflx, self.bases[p.socket].pref),
                use_candidate,
            }),
        });
    }

    fn next_waiting(&mut self) -> Option<usize> {
        while let Some(i) = self.triggered.pop_front() {
            if matches!(self.pairs[i].state, State::Waiting) {
                return Some(i);
            }
        }
        self.pairs
            .iter()
            .enumerate()
            .filter(|(_, p)| matches!(p.state, State::Waiting))
            .max_by_key(|(_, p)| p.priority)
            .map(|(i, _)| i)
    }

    fn drive(&mut self, now: Instant) {
        if self.outcome.is_some() {
            return;
        }
        if now >= self.deadline {
            self.outcome = Some(Outcome::Failed);
            return;
        }
        if !self.checking() {
            return;
        }
        for i in 0..self.pairs.len() {
            if let State::InProgress(tx) = &mut self.pairs[i].state {
                match tx.step(now) {
                    Step::Wait => {}
                    Step::Send => {
                        let txid = tx.txid;
                        self.check(i, txid, false);
                    }
                    Step::GiveUp => self.pairs[i].state = State::Failed,
                }
            }
        }
        if let Some((i, tx)) = &mut self.nominating {
            let i = *i;
            match tx.step(now) {
                Step::Wait => {}
                Step::Send => {
                    let txid = tx.txid;
                    self.check(i, txid, true);
                }
                Step::GiveUp => self.nominating = None,
            }
        }
        if now >= self.next_check {
            if let Some(i) = self.next_waiting() {
                let tx = Tx::new(now);
                self.check(i, tx.txid, false);
                self.pairs[i].state = State::InProgress(tx);
                self.next_check = now + CHECK_PACE;
            }
        }
        if let Some((i, at)) = self.nominee() {
            if now >= at {
                let tx = Tx::new(now);
                self.check(i, tx.txid, true);
                self.pairs[i].nominated = true;
                self.nominating = Some((i, tx));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::IpAddr;

    const HOP: Duration = Duration::from_millis(5);
    const SERVER: &str = "203.0.113.1:21116";

    fn sa(s: &str) -> SocketAddr {
        s.parse().unwrap()
    }

    #[derive(Clone, Copy, PartialEq)]
    enum Nat {
        Open,
        FullCone,
        Symmetric,
    }

    struct Map {
        inner: SocketAddr,
        dst: Option<SocketAddr>,
        port: u16,
    }

    struct Site {
        nat: Nat,
        public: IpAddr,
        maps: Vec<Map>,
    }

    impl Site {
        fn map(&mut self, inner: SocketAddr, dst: SocketAddr) -> SocketAddr {
            let sym = self.nat == Nat::Symmetric;
            let i = match self
                .maps
                .iter()
                .position(|m| m.inner == inner && (!sym || m.dst == Some(dst)))
            {
                Some(i) => i,
                None => {
                    let port = 40000 + self.maps.len() as u16;
                    self.maps.push(Map {
                        inner,
                        dst: sym.then_some(dst),
                        port,
                    });
                    self.maps.len() - 1
                }
            };
            SocketAddr::new(self.public, self.maps[i].port)
        }

        fn admit(&self, dst: SocketAddr, src: SocketAddr) -> Option<SocketAddr> {
            let m = self.maps.iter().find(|m| m.port == dst.port())?;
            let ok = match self.nat {
                Nat::FullCone => true,
                Nat::Symmetric => m.dst == Some(src),
                Nat::Open => false,
            };
            ok.then_some(m.inner)
        }
    }

    struct Peer {
        site: usize,
        bases: Vec<SocketAddr>,
        pwd: &'static str,
        peer_pwd: &'static str,
        kernel: Option<Kernel>,
        inbox: Vec<(usize, SocketAddr, Packet)>,
    }

    struct Flight {
        at: Instant,
        site: usize,
        dst: SocketAddr,
        src: SocketAddr,
        packet: Packet,
        key: &'static str,
    }

    type DropRule = Box<dyn FnMut(usize, SocketAddr, &Transmit) -> bool>;

    /// Peers 0 (A) and 1 (B), and impostors that answer any check without knowing the pwd.
    /// MESSAGE-INTEGRITY is modelled by the pwd each packet is keyed with.
    struct Sim {
        t0: Instant,
        now: Instant,
        sites: Vec<Site>,
        peers: Vec<Peer>,
        impostors: Vec<(usize, SocketAddr)>,
        flight: Vec<Flight>,
        sent: Vec<(Instant, usize, Transmit)>,
        drop: Option<DropRule>,
    }

    impl Sim {
        fn new(sites: &[(Nat, &str)]) -> Self {
            let t0 = Instant::now();
            Sim {
                t0,
                now: t0,
                sites: sites
                    .iter()
                    .map(|&(nat, ip)| Site {
                        nat,
                        public: ip.parse().unwrap(),
                        maps: Vec::new(),
                    })
                    .collect(),
                peers: Vec::new(),
                impostors: Vec::new(),
                flight: Vec::new(),
                sent: Vec::new(),
                drop: None,
            }
        }

        fn peer(&mut self, site: usize, bases: &[&str], pwd: &'static str, peer_pwd: &'static str) {
            self.peers.push(Peer {
                site,
                bases: bases.iter().map(|b| sa(b)).collect(),
                pwd,
                peer_pwd,
                kernel: None,
                inbox: Vec::new(),
            });
        }

        /// The srflx S would report for `peer`'s socket `i`.
        fn srflx(&mut self, peer: usize, i: usize) -> SocketAddr {
            let (site, base) = (self.peers[peer].site, self.peers[peer].bases[i]);
            self.sites[site].map(base, sa(SERVER))
        }

        fn bases(&self, peer: usize, prefs: &[u16]) -> Vec<Base> {
            self.peers[peer]
                .bases
                .iter()
                .zip(prefs)
                .map(|(&addr, &pref)| Base { addr, pref })
                .collect()
        }

        fn at(&self, ms: u64) -> Instant {
            self.t0 + Duration::from_millis(ms)
        }

        fn holds(&self, site: usize, addr: SocketAddr) -> bool {
            self.peers
                .iter()
                .any(|p| p.site == site && p.bases.contains(&addr))
                || self.impostors.contains(&(site, addr))
        }

        fn send(
            &mut self,
            site: usize,
            src: SocketAddr,
            to: SocketAddr,
            packet: Packet,
            key: &'static str,
        ) {
            let (dst_site, dst, src) = if self.holds(site, to) {
                (site, to, src)
            } else {
                let src = match self.sites[site].nat {
                    Nat::Open => src,
                    _ => self.sites[site].map(src, to),
                };
                let found = (0..self.sites.len()).find_map(|s| match self.sites[s].nat {
                    Nat::Open if self.holds(s, to) => Some((s, to)),
                    Nat::Open => None,
                    _ if self.sites[s].public == to.ip() => {
                        self.sites[s].admit(to, src).map(|inner| (s, inner))
                    }
                    _ => None,
                });
                match found {
                    Some((s, inner)) => (s, inner, src),
                    None => return,
                }
            };
            self.flight.push(Flight {
                at: self.now + HOP,
                site: dst_site,
                dst,
                src,
                packet,
                key,
            });
        }

        fn deliver(&mut self, f: Flight) {
            if self.impostors.contains(&(f.site, f.dst)) {
                if let Packet::Check(c) = f.packet {
                    let reply = Packet::Reply(Reply {
                        txid: c.txid,
                        mapped: f.src,
                    });
                    self.send(f.site, f.dst, f.src, reply, "impostor");
                }
                return;
            }
            let now = self.now;
            let Some(p) = self
                .peers
                .iter_mut()
                .find(|p| p.site == f.site && p.bases.contains(&f.dst))
            else {
                return;
            };
            let socket = p.bases.iter().position(|&b| b == f.dst).unwrap();
            let key_ok = match f.packet {
                Packet::Check(_) => f.key == p.pwd,
                Packet::Reply(_) => f.key == p.peer_pwd,
            };
            if !key_ok {
                return;
            }
            match (&mut p.kernel, f.packet) {
                (None, packet) => p.inbox.push((socket, f.src, packet)),
                (Some(k), Packet::Check(c)) => k.on_request(now, socket, f.src, &c),
                (Some(k), Packet::Reply(r)) => k.on_response(now, socket, f.src, &r),
            }
        }

        /// Starts `peer`'s kernel now, feeding it what arrived before.
        fn start(&mut self, peer: usize, mut k: Kernel) {
            let now = self.now;
            for (socket, from, packet) in std::mem::take(&mut self.peers[peer].inbox) {
                match packet {
                    Packet::Check(c) => k.on_request(now, socket, from, &c),
                    Packet::Reply(r) => k.on_response(now, socket, from, &r),
                }
            }
            k.handle_timeout(now);
            self.peers[peer].kernel = Some(k);
            self.flush();
        }

        fn flush(&mut self) {
            for i in 0..self.peers.len() {
                while let Some(t) = self.peers[i]
                    .kernel
                    .as_mut()
                    .and_then(|k| k.poll_transmit())
                {
                    let p = &self.peers[i];
                    let (site, src) = (p.site, p.bases[t.socket]);
                    let key = match t.packet {
                        Packet::Check(_) => p.peer_pwd,
                        Packet::Reply(_) => p.pwd,
                    };
                    self.sent.push((self.now, i, t));
                    if self.drop.as_mut().is_some_and(|d| d(i, src, &t)) {
                        continue;
                    }
                    self.send(site, src, t.to, t.packet, key);
                }
            }
        }

        fn run(&mut self, until_ms: u64) {
            let end = self.at(until_ms);
            loop {
                self.flush();
                let next = self
                    .peers
                    .iter()
                    .filter_map(|p| p.kernel.as_ref()?.poll_timeout())
                    .chain(self.flight.iter().map(|f| f.at))
                    .min();
                let Some(next) = next.filter(|&t| t <= end) else {
                    self.now = end;
                    return;
                };
                self.now = self.now.max(next);
                let now = self.now;
                let mut due: Vec<Flight> = Vec::new();
                let mut i = 0;
                while i < self.flight.len() {
                    if self.flight[i].at <= now {
                        due.push(self.flight.remove(i));
                    } else {
                        i += 1;
                    }
                }
                for f in due {
                    self.deliver(f);
                }
                for p in &mut self.peers {
                    if let Some(k) = p.kernel.as_mut() {
                        if k.poll_timeout().is_some_and(|t| t <= now) {
                            k.handle_timeout(now);
                        }
                    }
                }
            }
        }

        fn outcome(&self, peer: usize) -> Option<Outcome> {
            self.peers[peer].kernel.as_ref()?.outcome()
        }

        fn selected(&self) -> Selection {
            match self.outcome(0) {
                Some(Outcome::Selected(s)) => s,
                o => panic!("A did not select a pair: {:?}", o),
            }
        }

        fn checks(&self, peer: usize) -> impl Iterator<Item = &(Instant, usize, Transmit)> {
            self.sent
                .iter()
                .filter(move |(_, i, t)| *i == peer && matches!(t.packet, Packet::Check(_)))
        }
    }

    fn host(addr: SocketAddr, pref: u16) -> Remote {
        Remote {
            kind: Kind::Host,
            pref,
            addr,
        }
    }

    fn srflx(addr: SocketAddr, pref: u16) -> Remote {
        Remote {
            kind: Kind::Srflx,
            pref,
            addr,
        }
    }

    #[test]
    fn same_private_address_in_another_lan_is_not_mistaken_for_the_peer() {
        let mut sim = Sim::new(&[
            (Nat::FullCone, "198.51.100.1"),
            (Nat::FullCone, "198.51.100.2"),
        ]);
        sim.peer(0, &["192.168.1.10:5000"], "a", "b");
        sim.peer(1, &["192.168.1.20:6000"], "b", "a");
        sim.impostors.push((0, sa("192.168.1.20:6000")));
        let (a_srflx, b_srflx) = (sim.srflx(0, 0), sim.srflx(1, 0));
        let b_cands = [
            host(sa("192.168.1.20:6000"), 0xFFFF),
            srflx(b_srflx, 0xFFFF),
        ];
        let a_cands = [
            host(sa("192.168.1.10:5000"), 0xFFFF),
            srflx(a_srflx, 0xFFFF),
        ];
        let b = Kernel::controlled(sim.bases(1, &[0xFFFF]), &a_cands, sim.now, sim.now);
        sim.start(1, b);
        let a = Kernel::controlling(sim.bases(0, &[0xFFFF]), vec![a_srflx], &b_cands, sim.now);
        sim.start(0, a);
        sim.run(3000);
        let s = sim.selected();
        assert_eq!((s.remote, s.remote_kind), (b_srflx, Kind::Srflx));
        assert_eq!(s.local_kind, Kind::Srflx);
    }

    #[test]
    fn checks_that_arrive_before_the_answer_are_answered_and_learned_as_prflx() {
        let mut sim = Sim::new(&[(Nat::Open, "0.0.0.0"), (Nat::FullCone, "198.51.100.2")]);
        sim.peer(0, &["203.0.113.10:5000"], "a", "b");
        sim.peer(1, &["192.168.2.10:6000"], "b", "a");
        let a_cands = [host(sa("203.0.113.10:5000"), 0xFFFF)];
        // B's Binding went unanswered: its ANSWER carries only the host candidate.
        let b_cands = [host(sa("192.168.2.10:6000"), 0xFFFF)];
        let b = Kernel::controlled(sim.bases(1, &[0xFFFF]), &a_cands, sim.now, sim.now);
        sim.start(1, b);
        sim.run(200);
        let a = Kernel::controlling(sim.bases(0, &[0xFFFF]), vec![], &b_cands, sim.now);
        sim.start(0, a);
        sim.run(3000);
        let b_mapped = sim.srflx(1, 0);
        assert!(sim.sent.iter().any(|(t, i, x)| *t == sim.at(200)
            && *i == 0
            && x.to == b_mapped
            && matches!(x.packet, Packet::Reply(_))));
        let s = sim.selected();
        assert_eq!((s.remote, s.remote_kind), (b_mapped, Kind::Prflx));
    }

    #[test]
    fn symmetric_nat_reaches_full_cone_through_prflx() {
        let mut sim = Sim::new(&[
            (Nat::Symmetric, "198.51.100.1"),
            (Nat::FullCone, "198.51.100.2"),
        ]);
        sim.peer(0, &["192.168.1.10:5000"], "a", "b");
        sim.peer(1, &["192.168.2.10:6000"], "b", "a");
        let (a_srflx, b_srflx) = (sim.srflx(0, 0), sim.srflx(1, 0));
        let a_cands = [
            host(sa("192.168.1.10:5000"), 0xFFFF),
            srflx(a_srflx, 0xFFFF),
        ];
        let b_cands = [
            host(sa("192.168.2.10:6000"), 0xFFFF),
            srflx(b_srflx, 0xFFFF),
        ];
        let b = Kernel::controlled(sim.bases(1, &[0xFFFF]), &a_cands, sim.now, sim.now);
        sim.start(1, b);
        let a = Kernel::controlling(sim.bases(0, &[0xFFFF]), vec![a_srflx], &b_cands, sim.now);
        sim.start(0, a);
        sim.run(3000);
        let s = sim.selected();
        assert_eq!((s.remote, s.local_kind), (b_srflx, Kind::Prflx));
        let known = [a_cands[0].addr, a_srflx];
        assert!(sim.checks(1).any(|(_, _, t)| !known.contains(&t.to)));
    }

    #[test]
    fn both_ends_rank_a_pair_alike() {
        let eth_v4 = candidate_priority(Kind::Host, local_pref(0, PENALTY_V4, 0));
        assert_eq!(eth_v4, 0x7EFF_FFFF);
        assert_eq!(
            candidate_priority(Kind::Host, local_pref(0, PENALTY_GLOBAL_V6, 0)),
            0x7EFF_F7FF
        );
        assert_eq!(
            candidate_priority(Kind::Host, local_pref(0, PENALTY_ULA, 0)),
            0x7EFF_EFFF
        );
        assert_eq!(candidate_priority(Kind::Prflx, 0xFFFF), 0x6EFF_FFFF);
        let (a, b) = (
            candidate_priority(Kind::Srflx, local_pref(10, PENALTY_V4, 1)),
            candidate_priority(Kind::Host, local_pref(0, PENALTY_GLOBAL_V6, 0)),
        );
        assert_eq!(
            Kernel::priority(Role::Controlling, a, b),
            Kernel::priority(Role::Controlled, b, a)
        );
        assert_ne!(pair_priority(a, b), pair_priority(b, a));
    }

    #[test]
    fn nomination_waits_while_a_better_pair_is_pending() {
        for (kind, wait) in [
            (Kind::Host, NOMINATE_WAIT_HOST),
            (Kind::Srflx, NOMINATE_WAIT_OTHER),
        ] {
            let mut sim = Sim::new(&[(Nat::Open, "0.0.0.0")]);
            sim.peer(0, &["203.0.113.10:5000"], "a", "b");
            sim.peer(0, &["203.0.113.20:6000"], "b", "a");
            let a_cands = [host(sa("203.0.113.10:5000"), 0xFFFF)];
            let unreachable = host(sa("203.0.113.99:1"), 0xFFFF);
            let reachable = Remote {
                kind,
                pref: 0xFFF0,
                addr: sa("203.0.113.20:6000"),
            };
            let b = Kernel::controlled(sim.bases(1, &[0xFFFF]), &a_cands, sim.now, sim.now);
            sim.start(1, b);
            let a = Kernel::controlling(
                sim.bases(0, &[0xFFFF]),
                vec![],
                &[unreachable, reachable],
                sim.now,
            );
            sim.start(0, a);
            sim.run(1000);
            let first_valid = sim
                .sent
                .iter()
                .find(|(_, i, t)| *i == 1 && matches!(t.packet, Packet::Reply(_)))
                .map(|(at, _, _)| *at + HOP)
                .unwrap();
            let nominated = sim
                .checks(0)
                .find(|(_, _, t)| matches!(t.packet, Packet::Check(c) if c.use_candidate))
                .map(|(at, _, _)| *at)
                .unwrap();
            assert_eq!(nominated - first_valid, wait);
            assert_eq!(sim.selected().remote, reachable.addr);
        }
    }

    #[test]
    fn b_accepts_the_second_pair_after_a_renominates() {
        let mut sim = Sim::new(&[(Nat::Open, "0.0.0.0")]);
        sim.peer(0, &["203.0.113.10:5000"], "a", "b");
        sim.peer(0, &["203.0.113.20:6000", "203.0.113.21:6001"], "b", "a");
        let a_addr = sa("203.0.113.10:5000");
        let (b0, b1) = (sa("203.0.113.20:6000"), sa("203.0.113.21:6001"));
        let mut first: Option<(SocketAddr, SocketAddr)> = None;
        sim.drop = Some(Box::new(
            move |peer: usize, src: SocketAddr, t: &Transmit| match t.packet {
                Packet::Check(c) if peer == 0 && c.use_candidate => {
                    first.get_or_insert((src, t.to));
                    false
                }
                Packet::Reply(_) => peer == 1 && first == Some((t.to, src)),
                _ => false,
            },
        ));
        let b = Kernel::controlled(
            sim.bases(1, &[0xFFFF, 0xFFFE]),
            &[host(a_addr, 0xFFFF)],
            sim.now,
            sim.now,
        );
        sim.start(1, b);
        let a = Kernel::controlling(
            sim.bases(0, &[0xFFFF]),
            vec![],
            &[host(b0, 0xFFFF), host(b1, 0xFFFE)],
            sim.now,
        );
        sim.start(0, a);
        sim.run(3000);
        assert_eq!(sim.selected().remote, b1);
        let k = sim.peers[1].kernel.as_ref().unwrap();
        assert!(k.nominated(0, a_addr) && k.nominated(1, a_addr));
    }

    /// Runs `k` alone on its own timers until `until`, collecting what it sends.
    fn idle(k: &mut Kernel, sent: &mut Vec<Transmit>, until: Instant) {
        while let Some(t) = k.poll_timeout().filter(|&t| t <= until) {
            k.handle_timeout(t);
            sent.extend(std::iter::from_fn(|| k.poll_transmit()));
        }
    }

    #[test]
    fn no_pair_at_check_timeout() {
        let t0 = Instant::now();
        let base = Base {
            addr: sa("192.168.1.10:5000"),
            pref: 0xFFFF,
        };
        let mut k =
            Kernel::controlling(vec![base], vec![], &[host(sa("192.168.9.9:1"), 0xFFFF)], t0);
        let mut sent = Vec::new();
        idle(
            &mut k,
            &mut sent,
            t0 + CHECK_TIMEOUT - Duration::from_millis(1),
        );
        assert_eq!(k.outcome(), None);
        idle(&mut k, &mut sent, t0 + CHECK_TIMEOUT);
        assert_eq!(k.outcome(), Some(Outcome::Failed));
        assert_eq!(sent.len(), CHECK_RTO.len());
    }

    #[test]
    fn checks_sent_stay_bounded_and_failed_pairs_do_not_restart() {
        let t0 = Instant::now();
        let base = Base {
            addr: sa("192.168.1.10:5000"),
            pref: 0xFFFF,
        };
        let remote: Vec<Remote> = (0..40)
            .map(|i| host(SocketAddr::new([10, 0, 0, i].into(), 1), 0xFFFF - i as u16))
            .collect();
        let mut k = Kernel::controlled(vec![base], &remote, t0, t0);
        let check = |n: u8| Check {
            txid: [n; 12],
            priority: 0x6EFF_FFFF,
            use_candidate: false,
        };
        let mut sent = Vec::new();
        for n in 0..50u8 {
            k.on_request(
                t0,
                0,
                SocketAddr::new([198, 51, 100, n].into(), 7000),
                &check(n),
            );
        }
        sent.extend(std::iter::from_fn(|| k.poll_transmit()));
        idle(&mut k, &mut sent, t0 + Duration::from_secs(5));
        let checks = |s: &[Transmit]| {
            s.iter()
                .filter(|t| matches!(t.packet, Packet::Check(_)))
                .count()
        };
        let before = checks(&sent);
        assert!(before <= (MAX_PAIRS + MAX_PRFLX) * CHECK_RTO.len());
        let learned: Vec<_> = sent
            .iter()
            .filter(|t| {
                matches!(t.packet, Packet::Check(_)) && t.to.ip().to_string().starts_with("198.")
            })
            .map(|t| t.to)
            .fold(Vec::new(), |mut v, a| {
                if !v.contains(&a) {
                    v.push(a);
                }
                v
            });
        assert_eq!(learned.len(), MAX_PRFLX);

        let t1 = t0 + Duration::from_secs(5);
        for n in 0..20u8 {
            k.on_request(t1, 0, remote[0].addr, &check(n));
            k.on_request(t1, 0, learned[0], &check(n));
        }
        let mut after = Vec::new();
        after.extend(std::iter::from_fn(|| k.poll_transmit()));
        idle(&mut k, &mut after, t0 + Duration::from_secs(9));
        assert_eq!(checks(&after), 0);
        assert_eq!(after.len(), 40);
    }

    #[test]
    fn selected_local_kind_follows_the_mapped_address() {
        let base = sa("192.168.1.10:5000");
        let mapped_srflx = sa("198.51.100.1:40000");
        let peer = sa("198.51.100.2:40000");
        for (mapped, kind) in [
            (base, Kind::Host),
            (mapped_srflx, Kind::Srflx),
            (sa("198.51.100.1:40001"), Kind::Prflx),
        ] {
            let t0 = Instant::now();
            let mut k = Kernel::controlling(
                vec![Base {
                    addr: base,
                    pref: 0xFFFF,
                }],
                vec![mapped_srflx],
                &[srflx(peer, 0xFFFF)],
                t0,
            );
            for _ in 0..2 {
                k.handle_timeout(t0);
                let Some(Transmit {
                    packet: Packet::Check(c),
                    ..
                }) = k.poll_transmit()
                else {
                    panic!("no check sent");
                };
                k.on_response(
                    t0,
                    0,
                    peer,
                    &Reply {
                        txid: c.txid,
                        mapped,
                    },
                );
            }
            assert_eq!(
                k.outcome(),
                Some(Outcome::Selected(Selection {
                    socket: 0,
                    remote: peer,
                    local_kind: kind,
                    remote_kind: Kind::Srflx,
                }))
            );
        }
    }

    /// RFC 8445 §7.2.5.2.1, for a check and for the nomination.
    #[test]
    fn a_response_from_elsewhere_than_the_check_went_is_ignored() {
        let t0 = Instant::now();
        let base = sa("192.168.1.10:5000");
        let peer = sa("198.51.100.2:40000");
        let elsewhere = sa("198.51.100.2:40001");
        let mut k = Kernel::controlling(
            vec![Base {
                addr: base,
                pref: 0xFFFF,
            }],
            Vec::new(),
            &[srflx(peer, 0xFFFF)],
            t0,
        );
        k.handle_timeout(t0);
        for nominate in [false, true] {
            let Some(Transmit {
                packet: Packet::Check(c),
                ..
            }) = k.poll_transmit()
            else {
                panic!("no check sent");
            };
            assert_eq!(c.use_candidate, nominate);
            let reply = Reply {
                txid: c.txid,
                mapped: base,
            };
            k.on_response(t0, 0, elsewhere, &reply);
            assert_eq!((k.poll_transmit(), k.outcome()), (None, None));
            k.on_response(t0, 0, peer, &reply);
        }
        assert!(matches!(k.outcome(), Some(Outcome::Selected(_))));
    }
}
