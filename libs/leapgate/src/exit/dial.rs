//! Controlled side: resolving, filtering and dialing an exit channel's destination (contract 02
//! §3.3). A name is asked of the physical adapters' own DNS servers, every address goes through
//! `policy::classify` before any connection, and each connection is bound to a physical
//! adapter's address, so exit traffic never takes this device's TUN, VPN or proxy (B2, B9).

use super::{
    policy::{self, AllowNets, Reason, Snapshot},
    OPTION_ALLOW_NETS,
};
use crate::{
    dns::{self, Answer},
    ice,
    lan::{self, Nic},
};
use hbb_common::{
    config::Config,
    futures::{
        future::{select, Either},
        stream::FuturesUnordered,
        StreamExt,
    },
    log, throttled_log,
    tokio::{
        self,
        net::{TcpSocket, TcpStream},
        sync::Mutex,
        time::error::Elapsed,
    },
};
use std::{
    cmp::Reverse,
    fmt,
    future::Future,
    io,
    net::{IpAddr, Ipv4Addr, SocketAddr},
    pin::pin,
    time::{Duration, Instant},
};

const DIAL_WAIT: Duration = Duration::from_secs(10);
const RESOLVE_WAIT: Duration = Duration::from_secs(2);
const CONNECT_WAIT: Duration = Duration::from_secs(8);
/// Between attempts, as Happy Eyeballs (RFC 8305) does.
const ATTEMPT_DELAY: Duration = Duration::from_millis(250);
/// RFC 8305 §3's Resolution Delay.
const OTHER_FAMILY_GRACE: Duration = Duration::from_millis(50);
const MAX_ADDRS: usize = 8;
const MAX_ATTEMPTS: usize = 4;
const MAX_DNS_SERVERS: usize = 2;
const PUBLIC_V4_TTL: Duration = Duration::from_secs(600);
const REFUSAL_LOG_INTERVAL: Duration = Duration::from_secs(60);

/// One exit channel's destination as the open frame had it, and the controller's self-reported
/// ID, which is only for the log.
pub struct Target {
    pub host: String,
    pub port: i32,
    pub controller_id: String,
}

pub type ConnectResult = Result<io::Result<TcpStream>, Elapsed>;

/// Why a dial failed, inside the `io::Error` `connect` returns.
#[derive(Debug)]
struct Failure(Reason);

impl fmt::Display for Failure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(policy::reason_code(self.0))
    }
}

impl std::error::Error for Failure {}

/// Within 10 s: 2 s for the name, 8 s for the connection attempts.
pub async fn connect(target: &Target) -> io::Result<TcpStream> {
    let result = tokio::time::timeout(DIAL_WAIT, dial(target))
        .await
        .unwrap_or(Err(Reason::Timeout));
    log::trace!(
        "leapgate exit: {} {}:{}: {}",
        target.controller_id.escape_debug(),
        target.host.escape_debug(),
        target.port,
        result
            .as_ref()
            .map_or_else(|r| policy::reason_code(*r), |_| "connected")
    );
    result.map_err(|reason| io::Error::other(Failure(reason)))
}

/// `None` for a connection; otherwise the opened failure text, empty for a failure the
/// controller does not show.
pub fn failure_message(result: &ConnectResult) -> Option<&'static str> {
    let reason = match result {
        Ok(Ok(_)) => return None,
        Ok(Err(e)) => e
            .get_ref()
            .and_then(|e| e.downcast_ref::<Failure>())
            .map_or(Reason::Unreachable, |f| f.0),
        Err(_) => Reason::Timeout,
    };
    Some(policy::opened_message(reason))
}

async fn dial(target: &Target) -> Result<TcpStream, Reason> {
    let port = u16::try_from(target.port)
        .ok()
        .filter(|&p| p != 0 && !target.host.is_empty())
        .ok_or(Reason::InvalidTarget)?;
    // A value written past the settings dialog allows nothing rather than more.
    let allow =
        policy::parse_allow_nets(&Config::get_option(OPTION_ALLOW_NETS)).unwrap_or_default();
    let nics = tokio::task::spawn_blocking(lan::nics)
        .await
        .unwrap_or_default();
    let sources = sources(&nics);
    let literal = target.host.parse::<IpAddr>().ok();
    let (public_v4, resolved) = tokio::join!(public_v4(&nics), async {
        match literal {
            Some(ip) => Ok(vec![ip]),
            None => resolve(&target.host, port, &dns_servers(&sources)).await,
        }
    });
    let local = Snapshot::new(&nics, &public_v4);
    let passed = filter(
        &resolved?,
        literal.is_some(),
        &local,
        &allow,
        |ip, reason| log_refused(&target.controller_id, SocketAddr::new(ip, port), reason),
    )?;
    tokio::time::timeout(CONNECT_WAIT, race(&attempt_order(&passed), port, &sources))
        .await
        .unwrap_or(Err(Reason::Timeout))
}

/// The one refusal line (B7): the address only, never the name, at most one a minute.
fn log_refused(controller_id: &str, addr: SocketAddr, reason: Reason) {
    throttled_log!(
        REFUSAL_LOG_INTERVAL,
        warn,
        "leapgate exit: {} refused {} ({})",
        controller_id.escape_debug(),
        addr,
        policy::reason_code(reason)
    );
}

/// The addresses that pass, deduplicated, in the order given, at most `MAX_ADDRS`; `refused`
/// hears of every other one. With none passing, the first refusal.
fn filter(
    addrs: &[IpAddr],
    literal: bool,
    local: &Snapshot,
    allow: &AllowNets,
    mut refused: impl FnMut(IpAddr, Reason),
) -> Result<Vec<IpAddr>, Reason> {
    let (mut passed, mut first) = (Vec::new(), None);
    let mut seen = Vec::new();
    for &ip in addrs {
        if passed.len() >= MAX_ADDRS {
            break;
        }
        if seen.contains(&ip) {
            continue;
        }
        seen.push(ip);
        match policy::classify(ip, literal, local, allow) {
            Ok(()) => passed.push(ip),
            Err(reason) => {
                refused(ip, reason);
                first.get_or_insert(reason);
            }
        }
    }
    if passed.is_empty() {
        return Err(first.unwrap_or(Reason::ResolveFailed));
    }
    Ok(passed)
}

/// IPv6 first, then the families alternate, each in its own order; at most `MAX_ATTEMPTS`.
fn attempt_order(addrs: &[IpAddr]) -> Vec<IpAddr> {
    let (v6, v4): (Vec<IpAddr>, Vec<IpAddr>) = addrs.iter().partition(|a| a.is_ipv6());
    let (mut v6, mut v4) = (v6.into_iter(), v4.into_iter());
    let mut out = Vec::new();
    while out.len() < MAX_ATTEMPTS {
        match (v6.next(), v4.next()) {
            (None, None) => break,
            (a, b) => out.extend(a.into_iter().chain(b)),
        }
    }
    out.truncate(MAX_ATTEMPTS);
    out
}

/// A physical adapter's address that connections and DNS queries leave from.
struct Source {
    ip: IpAddr,
    /// The IPv4 on-link prefix length; IPv6 uses the address's /64.
    bits: u8,
    /// Its adapter's DNS servers of its family.
    dns: Vec<IpAddr>,
}

impl Source {
    fn on_link(&self, ip: IpAddr) -> bool {
        match (self.ip, ip) {
            (IpAddr::V4(a), IpAddr::V4(b)) => {
                let mask = u32::MAX
                    .checked_shl(32u32.saturating_sub(u32::from(self.bits)))
                    .unwrap_or(0);
                self.bits <= 32 && (u32::from(a) ^ u32::from(b)) & mask == 0
            }
            (IpAddr::V6(a), IpAddr::V6(b)) => u128::from(a) >> 64 == u128::from(b) >> 64,
            _ => false,
        }
    }
}

/// Addresses of up, non-virtual adapters with a default gateway of the family, the cheapest
/// network and then the fastest link first; global IPv6 before the rest.
fn sources(nics: &[Nic]) -> Vec<Source> {
    let mut usable: Vec<&Nic> = nics.iter().filter(|n| n.up && !n.is_virtual()).collect();
    usable.sort_by_key(|n| (lan::net_cost(n.if_type), Reverse(n.speed)));
    let mut v4 = Vec::new();
    let mut v6 = Vec::new();
    for n in usable {
        let dns = |family_v4: bool| {
            n.dns
                .iter()
                .copied()
                .filter(|d| d.is_ipv4() == family_v4 && usable_dns(*d))
                .collect::<Vec<_>>()
        };
        if n.has_gateway_v4 {
            for &(ip, bits) in &n.ipv4_prefixes {
                if bindable_v4(ip) {
                    v4.push(Source {
                        ip: ip.into(),
                        bits,
                        dns: dns(true),
                    });
                }
            }
        }
        if n.has_gateway_v6 {
            for ip in lan::one_per_prefix(&n.ipv6) {
                v6.push(Source {
                    ip: ip.into(),
                    bits: 64,
                    dns: dns(false),
                });
            }
        }
    }
    v6.sort_by_key(|s| !matches!(s.ip, IpAddr::V6(ip) if ip.segments()[0] & 0xe000 == 0x2000));
    v4.extend(v6);
    v4
}

/// Unlike ICE's `excluded_ip`, keeps `100.64.0.0/10`: some ISPs hand it to the PC itself.
fn bindable_v4(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    !ip.is_loopback()
        && !ip.is_link_local()
        && !ip.is_unspecified()
        && !(o[0] == 198 && (o[1] & 0xfe) == 18)
}

/// Not loopback, link-local, `fec0::/10` (Windows fills `fec0:0:0:ffff::1~3` in on adapters
/// without IPv6 DNS) or fake-ip.
fn usable_dns(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ip) => {
            let o = ip.octets();
            !ip.is_loopback() && !ip.is_link_local() && !(o[0] == 198 && (o[1] & 0xfe) == 18)
        }
        IpAddr::V6(ip) => {
            !ip.is_loopback() && !ip.is_unicast_link_local() && ip.segments()[0] & 0xffc0 != 0xfec0
        }
    }
}

/// (source to bind, server) for the first two servers in the sources' order.
fn dns_servers(sources: &[Source]) -> Vec<(IpAddr, SocketAddr)> {
    let mut out: Vec<(IpAddr, SocketAddr)> = Vec::new();
    for s in sources {
        for &d in &s.dns {
            if out.len() < MAX_DNS_SERVERS && !out.iter().any(|(_, x)| x.ip() == d) {
                out.push((s.ip, SocketAddr::new(d, 53)));
            }
        }
    }
    out
}

/// A source of `ip`'s family, one on its link first. `None`: no route, and no unbound
/// connection instead.
fn source_for(ip: IpAddr, sources: &[Source]) -> Option<IpAddr> {
    let family = |s: &&Source| s.ip.is_ipv4() == ip.is_ipv4();
    sources
        .iter()
        .filter(family)
        .find(|s| s.on_link(ip))
        .or_else(|| sources.iter().find(family))
        .map(|s| s.ip)
}

/// `host` by the adapters' DNS servers, racing; the system resolver, started alongside, only
/// when they gave no answer at all.
async fn resolve(
    host: &str,
    port: u16,
    servers: &[(IpAddr, SocketAddr)],
) -> Result<Vec<IpAddr>, Reason> {
    let deadline = Instant::now() + RESOLVE_WAIT;
    let adapters = pin!(ask_adapters(servers, host, deadline));
    let system = pin!(async {
        match tokio::time::timeout_at(deadline.into(), tokio::net::lookup_host((host, port))).await
        {
            Ok(Ok(addrs)) => addrs.map(|a| a.ip()).collect(),
            _ => Vec::new(),
        }
    });
    match select(adapters, system).await {
        Either::Left((a, system)) => settle(a, system).await,
        Either::Right((s, adapters)) => settle(adapters.await, async { s }).await,
    }
}

async fn settle(
    adapters: Answer,
    system: impl Future<Output = Vec<IpAddr>>,
) -> Result<Vec<IpAddr>, Reason> {
    match adapters {
        Answer::Addresses(v) => Ok(v),
        Answer::Negative => Err(Reason::Nxdomain),
        Answer::NoAnswer => {
            let v = system.await;
            if v.is_empty() {
                Err(Reason::ResolveFailed)
            } else {
                Ok(v)
            }
        }
    }
}

/// The first server with addresses wins; a negative from either only counts when neither has
/// any.
async fn ask_adapters(servers: &[(IpAddr, SocketAddr)], host: &str, deadline: Instant) -> Answer {
    let mut asks: FuturesUnordered<_> = servers
        .iter()
        .map(|&(bind, server)| dns::ask(bind, server, host, deadline, Some(OTHER_FAMILY_GRACE)))
        .collect();
    let mut negative = false;
    while let Some(a) = asks.next().await {
        match a {
            Answer::Addresses(v) => return Answer::Addresses(v),
            Answer::Negative => negative = true,
            Answer::NoAnswer => {}
        }
    }
    if negative {
        Answer::Negative
    } else {
        Answer::NoAnswer
    }
}

/// Attempts `ATTEMPT_DELAY` apart; the first connection wins and the rest are dropped. All
/// failed: the reason of the last one to finish.
async fn race(order: &[IpAddr], port: u16, sources: &[Source]) -> Result<TcpStream, Reason> {
    let mut attempts: FuturesUnordered<_> = order
        .iter()
        .enumerate()
        .map(|(i, &ip)| async move {
            tokio::time::sleep(ATTEMPT_DELAY * i as u32).await;
            attempt(ip, port, sources).await
        })
        .collect();
    let mut last = Reason::Unreachable;
    while let Some(r) = attempts.next().await {
        match r {
            Ok(s) => return Ok(s),
            Err(reason) => last = reason,
        }
    }
    Err(last)
}

async fn attempt(ip: IpAddr, port: u16, sources: &[Source]) -> Result<TcpStream, Reason> {
    let src = source_for(ip, sources).ok_or(Reason::NoRoute)?;
    let socket = match ip {
        IpAddr::V4(_) => TcpSocket::new_v4(),
        IpAddr::V6(_) => TcpSocket::new_v6(),
    }
    .map_err(|e| io_reason(&e))?;
    // The address went away since the adapters were listed.
    socket
        .bind(SocketAddr::new(src, 0))
        .map_err(|_| Reason::NoRoute)?;
    socket
        .connect(SocketAddr::new(ip, port))
        .await
        .map_err(|e| io_reason(&e))
}

fn io_reason(e: &io::Error) -> Reason {
    match e.kind() {
        io::ErrorKind::ConnectionRefused => Reason::Refused,
        io::ErrorKind::TimedOut => Reason::Timeout,
        io::ErrorKind::NetworkUnreachable | io::ErrorKind::AddrNotAvailable => Reason::NoRoute,
        _ => Reason::Unreachable,
    }
}

/// B11's addresses, probed at most every `PUBLIC_V4_TTL` and shared by every channel: one that
/// comes during a probe waits for it.
async fn public_v4(nics: &[Nic]) -> Vec<Ipv4Addr> {
    static CACHE: Mutex<Option<(Instant, Vec<Ipv4Addr>)>> = Mutex::const_new(None);
    let mut cache = CACHE.lock().await;
    if let Some((at, v)) = cache.as_ref() {
        if at.elapsed() < PUBLIC_V4_TTL {
            return v.clone();
        }
    }
    let v = ice::public_v4(nics, &Config::get_rendezvous_server()).await;
    if v.is_empty() {
        log::warn!("leapgate exit: public IPv4 unavailable");
    }
    *cache = Some((Instant::now(), v.clone()));
    v
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dns::{a_record, reply, serve};
    use hbb_common::tokio::net::TcpListener;

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    fn ips(list: &[&str]) -> Vec<IpAddr> {
        list.iter().map(|s| ip(s)).collect()
    }

    fn refusals(
        addrs: &[IpAddr],
        literal: bool,
        local: &Snapshot,
    ) -> (Result<Vec<IpAddr>, Reason>, Vec<(IpAddr, Reason)>) {
        let mut seen = Vec::new();
        let got = filter(addrs, literal, local, &AllowNets::default(), |ip, r| {
            seen.push((ip, r))
        });
        (got, seen)
    }

    #[test]
    fn only_passing_addresses_are_dialed() {
        let local = Snapshot::default();
        let mixed = ips(&[
            "10.0.0.1",
            "8.8.8.8",
            "8.8.8.8",
            "::1",
            "2606:4700::1",
            "1.1.1.1",
        ]);
        let (got, refused) = refusals(&mixed, false, &local);
        assert_eq!(got, Ok(ips(&["8.8.8.8", "2606:4700::1", "1.1.1.1"])));
        assert_eq!(
            refused,
            vec![(ip("10.0.0.1"), Reason::Lan), (ip("::1"), Reason::Loopback)]
        );
        let many: Vec<IpAddr> = (1..=12).map(|i| IpAddr::from([8, 8, 4, i])).collect();
        assert_eq!(refusals(&many, false, &local).0, Ok(many[..8].to_vec()));
        let blocked = ips(&["192.168.1.1", "127.0.0.1"]);
        assert_eq!(refusals(&blocked, false, &local).0, Err(Reason::Lan));
        assert_eq!(
            refusals(&ips(&["198.18.0.1"]), true, &local).0,
            Err(Reason::FakeIpLiteral)
        );
        assert_eq!(
            refusals(&ips(&["198.18.0.1"]), false, &local).0,
            Err(Reason::FakeIp)
        );
    }

    /// What the system resolver gives for names that std's strict parsing refuses goes through
    /// the same filter as everything else.
    #[test]
    fn system_resolver_spellings_are_filtered_like_the_rest() {
        assert!("127.1".parse::<IpAddr>().is_err());
        assert!("fe80::1%2".parse::<IpAddr>().is_err());
        let from_system = ips(&["127.0.0.1", "fe80::1"]);
        let (got, refused) = refusals(&from_system, false, &Snapshot::default());
        assert_eq!(got, Err(Reason::Loopback));
        assert_eq!(
            refused,
            vec![
                (ip("127.0.0.1"), Reason::Loopback),
                (ip("fe80::1"), Reason::LinkLocal)
            ]
        );
    }

    /// The unbracketed `host:port` the old raw pipe would have built: std splits at the last
    /// colon, so `::1:80` becomes `::1` port 80, and as a whole it is an IPv6 literal.
    #[test]
    fn std_splits_an_unbracketed_ipv6_host_port_at_the_last_colon() {
        use std::net::ToSocketAddrs;
        let addrs: Vec<SocketAddr> = "::1:80".to_socket_addrs().unwrap().collect();
        assert_eq!(addrs, vec![SocketAddr::new(ip("::1"), 80)]);
        assert_eq!("::1:80".parse::<IpAddr>(), Ok(ip("::0.1.0.128")));
    }

    #[test]
    fn attempts_start_with_ipv6_and_alternate() {
        assert_eq!(
            attempt_order(&ips(&[
                "1.1.1.1", "1.0.0.1", "2606::1", "2606::2", "2606::3"
            ])),
            ips(&["2606::1", "1.1.1.1", "2606::2", "1.0.0.1"])
        );
        let v4 = ips(&["1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4", "9.9.9.9"]);
        assert_eq!(attempt_order(&v4), v4[..4].to_vec());
        assert_eq!(
            attempt_order(&ips(&["2606::2", "2606::1"])),
            ips(&["2606::2", "2606::1"])
        );
        assert_eq!(attempt_order(&ips(&["2606::1"])), ips(&["2606::1"]));
    }

    #[test]
    fn sources_are_physical_and_of_the_target_family() {
        let wired = Nic {
            name: "Ethernet".to_owned(),
            if_type: lan::IF_TYPE_ETHERNET,
            up: true,
            ipv4: vec![Ipv4Addr::new(192, 168, 1, 145)],
            ipv4_prefixes: vec![(Ipv4Addr::new(192, 168, 1, 145), 24)],
            has_gateway_v4: true,
            dns: ips(&["192.168.1.1", "fec0:0:0:ffff::1", "198.18.0.2", "223.5.5.5"]),
            ..Default::default()
        };
        let tun = Nic {
            name: "Mihomo".to_owned(),
            if_type: 53,
            up: true,
            ipv4: vec![Ipv4Addr::new(198, 18, 0, 1)],
            ipv4_prefixes: vec![(Ipv4Addr::new(198, 18, 0, 1), 30)],
            has_gateway_v4: true,
            dns: ips(&["198.18.0.2"]),
            ..Default::default()
        };
        let wifi = Nic {
            name: "WLAN".to_owned(),
            if_type: lan::IF_TYPE_IEEE80211,
            up: true,
            ipv4: vec![Ipv4Addr::new(10, 0, 0, 7)],
            ipv4_prefixes: vec![(Ipv4Addr::new(10, 0, 0, 7), 24)],
            has_gateway_v4: true,
            dns: ips(&["10.0.0.1"]),
            ..Default::default()
        };
        let vpn = Nic {
            name: "WireGuard".to_owned(),
            if_type: 53,
            up: true,
            ipv4: vec![Ipv4Addr::new(10, 8, 0, 2)],
            ipv4_prefixes: vec![(Ipv4Addr::new(10, 8, 0, 2), 24)],
            has_gateway_v4: true,
            ..Default::default()
        };
        let no_gateway = Nic {
            name: "Ethernet 2".to_owned(),
            if_type: lan::IF_TYPE_ETHERNET,
            up: true,
            ipv4: vec![Ipv4Addr::new(172, 17, 0, 1)],
            ipv4_prefixes: vec![(Ipv4Addr::new(172, 17, 0, 1), 20)],
            ipv6: vec![lan::V6 {
                ip: "2408:8256:1:2::99".parse().unwrap(),
                suffix: lan::Suffix::Other,
            }],
            ..Default::default()
        };
        let cellular = Nic {
            name: "Cellular".to_owned(),
            if_type: lan::IF_TYPE_ETHERNET,
            up: true,
            ipv4: vec![Ipv4Addr::new(100, 64, 5, 6)],
            ipv4_prefixes: vec![(Ipv4Addr::new(100, 64, 5, 6), 10)],
            has_gateway_v4: true,
            ..Default::default()
        };
        assert_eq!(
            source_for(ip("8.8.8.8"), &sources(&[cellular])),
            Some(ip("100.64.5.6"))
        );
        let sources = sources(&[tun, wifi, wired, vpn, no_gateway]);
        assert_eq!(
            source_for(ip("8.8.8.8"), &sources),
            Some(ip("192.168.1.145"))
        );
        assert_eq!(source_for(ip("10.0.0.20"), &sources), Some(ip("10.0.0.7")));
        assert_eq!(
            source_for(ip("10.8.0.5"), &sources),
            Some(ip("192.168.1.145"))
        );
        assert_eq!(
            source_for(ip("172.17.0.5"), &sources),
            Some(ip("192.168.1.145"))
        );
        assert_eq!(source_for(ip("2606:4700::1"), &sources), None);
        assert_eq!(
            dns_servers(&sources),
            vec![
                (ip("192.168.1.145"), SocketAddr::new(ip("192.168.1.1"), 53)),
                (ip("192.168.1.145"), SocketAddr::new(ip("223.5.5.5"), 53)),
            ]
        );
        assert!(!usable_dns(ip("fec0:0:0:ffff::1")));
        assert!(!usable_dns(ip("fe80::1")));
        assert!(usable_dns(ip("2001:4860:4860::8888")));
        assert_eq!(source_for(ip("8.8.8.8"), &[]), None);
    }

    /// `localhost` has a system answer offline; the adapters' addresses or negative answer win
    /// over it, and only no answer at all falls back to it.
    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn the_system_answer_is_taken_only_when_the_adapters_say_nothing() {
        let lo = ip("127.0.0.1");
        let answering = serve(|q, is_a| a_record(q, is_a).or_else(|| Some(reply(q, 0, &[])))).await;
        let got = resolve("localhost", 80, &[(lo, answering)]).await;
        assert_eq!(got, Ok(ips(&["203.0.113.9"])));
        let nxdomain = serve(|q, _| Some(reply(q, 3, &[]))).await;
        assert_eq!(
            resolve("localhost", 80, &[(lo, nxdomain)]).await,
            Err(Reason::Nxdomain)
        );
        // One server's addresses win over the other's negative.
        let got = resolve("localhost", 80, &[(lo, nxdomain), (lo, answering)]).await;
        assert_eq!(got, Ok(ips(&["203.0.113.9"])));
        let failing = serve(|q, _| Some(reply(q, 2, &[]))).await;
        for servers in [vec![(lo, failing)], vec![]] {
            let got = resolve("localhost", 80, &servers).await.unwrap();
            assert!(
                got.iter().all(|a| a.is_loopback()) && !got.is_empty(),
                "{got:?}"
            );
        }
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn failures_map_to_fixed_messages_only() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let stream = TcpStream::connect(listener.local_addr().unwrap())
            .await
            .unwrap();
        assert_eq!(failure_message(&Ok(Ok(stream))), None);
        let failed = |reason| -> ConnectResult { Ok(Err(io::Error::other(Failure(reason)))) };
        assert_eq!(
            failure_message(&failed(Reason::Lan)),
            Some(super::super::MSG_BLOCKED)
        );
        assert_eq!(
            failure_message(&failed(Reason::FakeIpLiteral)),
            Some(super::super::MSG_FAKE_IP_LITERAL)
        );
        assert_eq!(failure_message(&failed(Reason::Refused)), Some(""));
        // A plain system error never reaches the controller's text.
        let other: ConnectResult = Ok(Err(io::Error::other("connect 10.0.0.1:80: refused")));
        assert_eq!(failure_message(&other), Some(""));
        let elapsed = tokio::time::timeout(Duration::ZERO, std::future::pending::<()>())
            .await
            .unwrap_err();
        assert_eq!(failure_message(&Err(elapsed)), Some(""));
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn bad_targets_are_refused_before_anything_else() {
        for (host, port) in [
            ("", 80),
            ("example.com", 0),
            ("example.com", -1),
            ("example.com", 65536),
        ] {
            let target = Target {
                host: host.to_owned(),
                port,
                controller_id: "123456789".to_owned(),
            };
            assert_eq!(
                dial(&target).await.unwrap_err(),
                Reason::InvalidTarget,
                "{host}:{port}"
            );
        }
    }
}
