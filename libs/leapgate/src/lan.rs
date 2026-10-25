//! LAN direct connection with candidate addresses.
//!
//! Upstream's LAN path uses the local address of the socket to the rendezvous server on both
//! ends: the controlled side reports it and listens on it, the controlling side binds its
//! connect to its own. Under a TUN proxy (mihomo, sing-box) that address belongs to the virtual
//! adapter (`198.18.0.1`), so the direct attempt always fails and falls back to relay. Here the
//! controlled side reports its physical adapters' addresses instead, and the controlling side
//! tries them all unbound; the LAN route is more specific than the TUN's default route, so the
//! system sends them out of the physical adapter.

use hbb_common::{
    bytes::Bytes,
    futures::future::select_ok,
    log,
    rendezvous_proto::PunchHoleResponse,
    socket_client::connect_tcp_local,
    tokio::{self, time::timeout},
    AddrMangle, ResultType, Stream,
};
use std::{
    future::Future,
    net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr},
    time::{Duration, Instant},
};

const MAX_CANDIDATES: usize = 8;
/// Upstream's connect timeout for an `is_local` punch (`MIN` in `Client::connect`).
const CONNECT_TIMEOUT_MS: u64 = 1000;
/// Upstream bounds the handshake only by `READ_TIMEOUT`. A candidate that the peer's listener
/// queued but never accepted (it takes one connection) would hold the race that long.
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(3);
/// For a connection whose local end is not a physical adapter (see `handshake_timeout`).
const VIRTUAL_HANDSHAKE_TIMEOUT: Duration = Duration::from_millis(800);

// Windows `IfType` values of virtual adapters: Wintun (mihomo, sing-box, WireGuard, Tailscale)
// and the newer TAP drivers report 53.
const IF_TYPE_PPP: u32 = 23;
const IF_TYPE_LOOPBACK: u32 = 24;
const IF_TYPE_PROP_VIRTUAL: u32 = 53;
const IF_TYPE_TUNNEL: u32 = 131;
pub(crate) const IF_TYPE_ETHERNET: u32 = 6;
pub(crate) const IF_TYPE_IEEE80211: u32 = 71;

/// ZeroTier, VMware, VirtualBox host-only and Wi-Fi Direct adapters report `IfType` 6 or 71, so
/// only their description gives them away. No `hyper-v` / `vethernet`: behind a Hyper-V external
/// switch the host's real uplink is a `vEthernet` adapter; internal ones have no default gateway.
const VIRTUAL_KEYWORDS: &[&str] = &[
    "meta tunnel",
    "wintun",
    "wireguard",
    "tailscale",
    "zerotier",
    "tap-windows",
    "openvpn",
    "vpn",
    "vmware virtual ethernet",
    "vmnet",
    "virtualbox host-only",
    "wi-fi direct",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Suffix {
    /// A privacy (temporary) address.
    Temporary,
    /// Assigned by DHCPv6; Windows reports it as a `/128`.
    Dhcp,
    Other,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct V6 {
    pub(crate) ip: Ipv6Addr,
    pub(crate) suffix: Suffix,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct Nic {
    pub(crate) name: String,
    pub(crate) description: String,
    pub(crate) if_type: u32,
    pub(crate) up: bool,
    pub(crate) ipv4: Vec<Ipv4Addr>,
    /// Preferred unicast addresses, without link-local ones.
    pub(crate) ipv6: Vec<V6>,
    pub(crate) has_gateway_v4: bool,
    pub(crate) has_gateway_v6: bool,
    /// Bits per second, 0 when unknown.
    pub(crate) speed: u64,
    /// The adapter's own DNS servers, in its order.
    pub(crate) dns: Vec<IpAddr>,
}

impl Nic {
    pub(crate) fn is_virtual(&self) -> bool {
        if matches!(
            self.if_type,
            IF_TYPE_PPP | IF_TYPE_LOOPBACK | IF_TYPE_PROP_VIRTUAL | IF_TYPE_TUNNEL
        ) {
            return true;
        }
        let name = self.name.to_lowercase();
        let description = self.description.to_lowercase();
        name.starts_with("tun")
            || name.starts_with("utun")
            || name.contains("mihomo")
            || name.contains("wintun")
            || VIRTUAL_KEYWORDS
                .iter()
                .any(|k| name.contains(k) || description.contains(k))
    }

    /// Whether ICE takes candidates from this adapter. The default gateway rules out Hyper-V
    /// internal switches, WSL's `vEthernet` and host-only adapters.
    pub(crate) fn can_gather(&self) -> bool {
        self.up && !self.is_virtual() && (self.has_gateway_v4 || self.has_gateway_v6)
    }
}

/// Network cost of a physical adapter's link (contract 05 §2.10).
pub(crate) fn net_cost(if_type: u32) -> u8 {
    match if_type {
        IF_TYPE_ETHERNET => 0,
        IF_TYPE_IEEE80211 => 10,
        _ => 50,
    }
}

/// One address per /64, the temporary one where the /64 has one, in first-seen order. Keyed on
/// the address's top 64 bits: Windows reports `OnLinkPrefixLength` 128 for temporary and DHCPv6
/// addresses.
pub(crate) fn one_per_prefix(addrs: &[V6]) -> Vec<Ipv6Addr> {
    let prefix = |ip: Ipv6Addr| u128::from(ip) >> 64;
    let mut out: Vec<V6> = Vec::new();
    for &a in addrs {
        match out.iter_mut().find(|o| prefix(o.ip) == prefix(a.ip)) {
            Some(o) if o.suffix != Suffix::Temporary && a.suffix == Suffix::Temporary => *o = a,
            Some(_) => {}
            None => out.push(a),
        }
    }
    out.into_iter().map(|a| a.ip).collect()
}

/// TUN adapters and fake-ip pools of mihomo / sing-box sit in `198.18.0.0/15`; Tailscale and
/// carrier-grade NAT use `100.64.0.0/10`. Neither is a LAN address.
pub(crate) fn excluded_ip(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    ip.is_loopback()
        || ip.is_link_local()
        || ip.is_unspecified()
        || (o[0] == 198 && (o[1] & 0xfe) == 18)
        || (o[0] == 100 && (o[1] & 0xc0) == 64)
}

/// Whether `ip` is an address of an up, physical adapter. A default gateway is not required:
/// this only decides whether the socket's own address can stay first, or whether a connection
/// left through a real adapter.
pub(crate) fn is_physical(nics: &[Nic], ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ip) => {
            !excluded_ip(ip)
                && nics
                    .iter()
                    .any(|n| n.up && !n.is_virtual() && n.ipv4.contains(&ip))
        }
        IpAddr::V6(ip) => nics
            .iter()
            .any(|n| n.up && !n.is_virtual() && n.ipv6.iter().any(|a| a.ip == ip)),
    }
}

fn select_candidates(nics: &[Nic], sock_local: SocketAddr) -> Vec<SocketAddr> {
    let SocketAddr::V4(sock_v4) = sock_local else {
        return Vec::new();
    };
    let port = sock_local.port();
    let mut out = Vec::new();
    if is_physical(nics, IpAddr::V4(*sock_v4.ip())) {
        out.push(sock_local);
    }
    // A default gateway also rules out WSL / Hyper-V vEthernet and host-only adapters.
    let mut usable: Vec<&Nic> = nics
        .iter()
        .filter(|n| n.up && n.has_gateway_v4 && !n.is_virtual())
        .collect();
    usable.sort_by_key(|n| (n.if_type != IF_TYPE_ETHERNET, std::cmp::Reverse(n.speed)));
    for ip in usable.iter().flat_map(|n| n.ipv4.iter()) {
        let addr = SocketAddr::new(IpAddr::V4(*ip), port);
        if out.len() >= MAX_CANDIDATES {
            break;
        }
        if !excluded_ip(*ip) && !out.contains(&addr) {
            out.push(addr);
        }
    }
    out
}

/// The controlled side's LAN candidates, best first, all on `sock_local`'s port. Empty when
/// there is no physical adapter, and the caller then behaves as upstream does.
pub fn local_candidates(sock_local: SocketAddr) -> Vec<SocketAddr> {
    select_candidates(&nics(), sock_local)
}

/// `local_candidates` off the async runtime: enumerating adapters is a blocking system call.
pub async fn local_candidates_async(sock_local: SocketAddr) -> Vec<SocketAddr> {
    tokio::task::spawn_blocking(move || local_candidates(sock_local))
        .await
        .unwrap_or_default()
}

pub fn encode(addrs: &[SocketAddr]) -> Vec<Bytes> {
    addrs
        .iter()
        .map(|a| Bytes::from(AddrMangle::encode(*a)))
        .collect()
}

/// Where the controlled side waits for the LAN connection, from the candidates it reported for
/// the socket at `sock_local`. A candidate on another address than the socket's needs the
/// wildcard; the port stays the one reported.
pub fn listen_addr(candidates: &[SocketAddr], sock_local: SocketAddr) -> SocketAddr {
    if candidates.iter().any(|c| c.ip() != sock_local.ip()) {
        SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), sock_local.port())
    } else {
        sock_local
    }
}

/// Candidates a Leapgate peer listed in an `is_local` response; empty otherwise. Only private
/// IPv4 addresses are LAN candidates; anything else the peer or server put there (loopback,
/// multicast, public addresses) would have this side connect to it unbound.
pub fn peer_candidates(ph: &PunchHoleResponse) -> Vec<SocketAddr> {
    if !ph.is_local() {
        return Vec::new();
    }
    let mut out = Vec::new();
    for b in ph.leapgate_local_addrs.iter() {
        let addr = AddrMangle::decode(b);
        let private = matches!(addr.ip(), IpAddr::V4(ip) if ip.is_private());
        if private && addr.port() != 0 && !out.contains(&addr) {
            out.push(addr);
        }
        if out.len() >= MAX_CANDIDATES {
            break;
        }
    }
    out
}

/// Source address for upstream's own LAN attempt (a peer without candidates): binding to a TUN
/// address would send it into the tunnel, so leave the choice to the routing table. Without an
/// adapter list (other platforms, enumeration failed) the address stays as upstream binds it.
pub async fn controller_bind_addr(my_addr: SocketAddr, is_local: bool) -> SocketAddr {
    let SocketAddr::V4(v4) = my_addr else {
        return my_addr;
    };
    if !is_local {
        return my_addr;
    }
    let ip = *v4.ip();
    let physical = tokio::task::spawn_blocking(move || {
        let nics = nics();
        nics.is_empty() || is_physical(&nics, IpAddr::V4(ip))
    })
    .await
    .unwrap_or(true);
    if physical {
        my_addr
    } else {
        SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), 0)
    }
}

/// Connects to every candidate at once, unbound, and returns the first that also passes
/// `handshake`. `None` when all fail, so the caller can fall back to relay.
pub async fn connect_candidates<H, F, T>(candidates: &[SocketAddr], handshake: H) -> Option<T>
where
    H: Fn(Stream) -> F,
    F: Future<Output = ResultType<T>>,
{
    if candidates.is_empty() {
        return None;
    }
    let nics = tokio::task::spawn_blocking(nics).await.unwrap_or_default();
    let (nics, handshake) = (&nics, &handshake);
    race(candidates, |addr| async move {
        let conn = connect_tcp_local(addr, None, CONNECT_TIMEOUT_MS).await?;
        let limit = handshake_timeout(nics, conn.local_addr());
        timeout(limit, handshake(conn)).await?
    })
    .await
}

/// A candidate outside this side's own LAN segments is routed into the TUN, whose stack
/// completes the TCP handshake locally and then never answers; its local end is the virtual
/// adapter's address. So is a real path through a VPN adapter (WireGuard, Tailscale), where the
/// peer sends its `SignedId` as soon as it accepts and the handshake takes one round trip. Such
/// a connection gets the short limit, which keeps a TUN-caught candidate inside the peer's 3 s
/// IPv6 punch window. An empty adapter list proves nothing.
fn handshake_timeout(nics: &[Nic], local: SocketAddr) -> Duration {
    match local.ip() {
        IpAddr::V4(ip) if !nics.is_empty() && !is_physical(nics, IpAddr::V4(ip)) => {
            VIRTUAL_HANDSHAKE_TIMEOUT
        }
        _ => HANDSHAKE_TIMEOUT,
    }
}

async fn race<A, F, T>(candidates: &[SocketAddr], attempt: A) -> Option<T>
where
    A: Fn(SocketAddr) -> F,
    F: Future<Output = ResultType<T>>,
{
    if candidates.is_empty() {
        return None;
    }
    let start = Instant::now();
    let attempts = candidates.iter().map(|&addr| {
        let fut = attempt(addr);
        Box::pin(async move { fut.await.map(|v| (addr, v)) })
    });
    match select_ok(attempts).await {
        Ok(((addr, v), _)) => {
            log::info!("LAN candidate {} won in {:?}", addr, start.elapsed());
            Some(v)
        }
        Err(e) => {
            log::info!(
                "all {} LAN candidates failed in {:?}, last error: {}",
                candidates.len(),
                start.elapsed(),
                e
            );
            None
        }
    }
}

#[cfg(not(windows))]
pub(crate) fn nics() -> Vec<Nic> {
    Vec::new()
}

/// `GetAdaptersAddresses` directly rather than `default-net`, which calls `SendARP` for every
/// adapter with a gateway and took over 4 s on a machine with a disconnected one.
#[cfg(windows)]
pub(crate) fn nics() -> Vec<Nic> {
    use windows::Win32::{
        Foundation::{ERROR_BUFFER_OVERFLOW, NO_ERROR},
        NetworkManagement::{
            IpHelper::{
                GetAdaptersAddresses, GAA_FLAG_INCLUDE_GATEWAYS, GAA_FLAG_SKIP_ANYCAST,
                GAA_FLAG_SKIP_MULTICAST, IP_ADAPTER_ADDRESSES_LH,
            },
            Ndis::IfOperStatusUp,
        },
        Networking::WinSock::{
            IpDadStatePreferred, IpSuffixOriginDhcp, IpSuffixOriginRandom, AF_INET, AF_INET6,
            AF_UNSPEC, SOCKADDR_IN, SOCKADDR_IN6, SOCKET_ADDRESS,
        },
    };

    fn ipv4_of(sa: &SOCKET_ADDRESS) -> Option<Ipv4Addr> {
        // SAFETY: the pointer comes from GetAdaptersAddresses and lives in its buffer; the
        // family is checked before reading it as SOCKADDR_IN.
        unsafe {
            let p = sa.lpSockaddr.as_ref()?;
            if p.sa_family != AF_INET {
                return None;
            }
            let sin = &*(sa.lpSockaddr as *const SOCKADDR_IN);
            Some(Ipv4Addr::from(sin.sin_addr.S_un.S_addr.to_ne_bytes()))
        }
    }

    fn ipv6_of(sa: &SOCKET_ADDRESS) -> Option<Ipv6Addr> {
        // SAFETY: as in ipv4_of, read as SOCKADDR_IN6 only after the family check.
        unsafe {
            let p = sa.lpSockaddr.as_ref()?;
            if p.sa_family != AF_INET6 {
                return None;
            }
            let sin6 = &*(sa.lpSockaddr as *const SOCKADDR_IN6);
            Some(Ipv6Addr::from(sin6.sin6_addr.u.Byte))
        }
    }

    let flags = GAA_FLAG_INCLUDE_GATEWAYS | GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST;
    let mut size: u32 = 16 * 1024;
    // u64 elements keep the buffer aligned for IP_ADAPTER_ADDRESSES_LH.
    let mut buf: Vec<u64>;
    let mut tries = 0;
    loop {
        buf = vec![0u64; (size as usize).div_ceil(8)];
        // SAFETY: buf holds `size` bytes, as passed.
        let ret = unsafe {
            GetAdaptersAddresses(
                AF_UNSPEC.0 as u32,
                flags,
                None,
                Some(buf.as_mut_ptr() as *mut IP_ADAPTER_ADDRESSES_LH),
                &mut size,
            )
        };
        if ret == NO_ERROR.0 {
            break;
        }
        tries += 1;
        if ret != ERROR_BUFFER_OVERFLOW.0 || tries >= 3 {
            log::warn!("GetAdaptersAddresses failed: {}", ret);
            return Vec::new();
        }
    }

    let mut out = Vec::new();
    let mut cur = buf.as_ptr() as *const IP_ADAPTER_ADDRESSES_LH;
    // SAFETY: a linked list inside buf, built by GetAdaptersAddresses.
    while let Some(a) = unsafe { cur.as_ref() } {
        let mut ipv4 = Vec::new();
        let mut ipv6 = Vec::new();
        let mut u = a.FirstUnicastAddress;
        while let Some(ua) = unsafe { u.as_ref() } {
            ipv4.extend(ipv4_of(&ua.Address));
            if ua.DadState == IpDadStatePreferred {
                let suffix = if ua.SuffixOrigin == IpSuffixOriginRandom {
                    Suffix::Temporary
                } else if ua.SuffixOrigin == IpSuffixOriginDhcp {
                    Suffix::Dhcp
                } else {
                    Suffix::Other
                };
                ipv6.extend(
                    ipv6_of(&ua.Address)
                        .filter(|ip| !ip.is_unicast_link_local())
                        .map(|ip| V6 { ip, suffix }),
                );
            }
            u = ua.Next;
        }
        let (mut has_gateway_v4, mut has_gateway_v6) = (false, false);
        let mut g = a.FirstGatewayAddress;
        while let Some(ga) = unsafe { g.as_ref() } {
            has_gateway_v4 |= ipv4_of(&ga.Address).is_some_and(|ip| !ip.is_unspecified());
            has_gateway_v6 |= ipv6_of(&ga.Address).is_some_and(|ip| !ip.is_unspecified());
            g = ga.Next;
        }
        let mut dns = Vec::new();
        let mut d = a.FirstDnsServerAddress;
        while let Some(da) = unsafe { d.as_ref() } {
            dns.extend(
                ipv4_of(&da.Address)
                    .map(IpAddr::V4)
                    .or_else(|| ipv6_of(&da.Address).map(IpAddr::V6)),
            );
            d = da.Next;
        }
        out.push(Nic {
            name: unsafe { a.FriendlyName.to_string() }.unwrap_or_default(),
            description: unsafe { a.Description.to_string() }.unwrap_or_default(),
            if_type: a.IfType,
            up: a.OperStatus == IfOperStatusUp,
            ipv4,
            ipv6,
            has_gateway_v4,
            has_gateway_v6,
            speed: if a.TransmitLinkSpeed == u64::MAX {
                0
            } else {
                a.TransmitLinkSpeed
            },
            dns,
        });
        cur = a.Next;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::anyhow::anyhow;

    const IF_TYPE_WIFI: u32 = 71;

    fn nic(name: &str, if_type: u32, ip: &str, gateway: bool, speed: u64) -> Nic {
        Nic {
            name: name.to_owned(),
            if_type,
            up: true,
            ipv4: vec![ip.parse().unwrap()],
            has_gateway_v4: gateway,
            speed,
            ..Default::default()
        }
    }

    fn v6(ip: &str, suffix: Suffix) -> V6 {
        V6 {
            ip: ip.parse().unwrap(),
            suffix,
        }
    }

    fn tun() -> Nic {
        nic("Mihomo", IF_TYPE_PROP_VIRTUAL, "198.18.0.1", true, 0)
    }

    fn addr(s: &str) -> SocketAddr {
        s.parse().unwrap()
    }

    const TUN_SOCK: &str = "198.18.0.1:54996";

    #[test]
    fn tun_and_wired() {
        let nics = [
            tun(),
            nic(
                "Ethernet",
                IF_TYPE_ETHERNET,
                "192.168.1.145",
                true,
                1_000_000_000,
            ),
        ];
        assert_eq!(
            select_candidates(&nics, addr(TUN_SOCK)),
            vec![addr("192.168.1.145:54996")]
        );
    }

    #[test]
    fn tun_and_wireless() {
        let nics = [
            tun(),
            nic("WLAN", IF_TYPE_WIFI, "192.168.1.157", true, 866_000_000),
        ];
        assert_eq!(
            select_candidates(&nics, addr(TUN_SOCK)),
            vec![addr("192.168.1.157:54996")]
        );
    }

    #[test]
    fn wired_before_faster_wireless() {
        let nics = [
            nic("WLAN", IF_TYPE_WIFI, "192.168.1.157", true, 2_400_000_000),
            nic(
                "Ethernet",
                IF_TYPE_ETHERNET,
                "192.168.1.145",
                true,
                1_000_000_000,
            ),
        ];
        assert_eq!(
            select_candidates(&nics, addr(TUN_SOCK)),
            vec![addr("192.168.1.145:54996"), addr("192.168.1.157:54996")]
        );
    }

    #[test]
    fn physical_socket_address_stays_first() {
        let nics = [
            nic(
                "Ethernet",
                IF_TYPE_ETHERNET,
                "192.168.1.145",
                true,
                1_000_000_000,
            ),
            nic("WLAN", IF_TYPE_WIFI, "192.168.1.157", true, 866_000_000),
        ];
        assert_eq!(
            select_candidates(&nics, addr("192.168.1.157:40000")),
            vec![addr("192.168.1.157:40000"), addr("192.168.1.145:40000")]
        );
    }

    #[test]
    fn only_virtual_adapters_gives_nothing() {
        let nics = [
            tun(),
            nic(
                "Tailscale",
                IF_TYPE_PROP_VIRTUAL,
                "100.101.102.103",
                false,
                0,
            ),
            nic(
                "Loopback Pseudo-Interface 1",
                IF_TYPE_LOOPBACK,
                "127.0.0.1",
                false,
                0,
            ),
        ];
        assert!(select_candidates(&nics, addr(TUN_SOCK)).is_empty());
    }

    #[test]
    fn wsl_vethernet_and_down_adapters_skipped() {
        let mut down = nic("Ethernet 3", IF_TYPE_ETHERNET, "192.168.100.128", true, 0);
        down.up = false;
        let nics = [
            tun(),
            nic(
                "vEthernet (WSL)",
                IF_TYPE_ETHERNET,
                "172.20.80.1",
                false,
                10_000_000_000,
            ),
            down,
            nic("WLAN", IF_TYPE_WIFI, "192.168.1.157", true, 866_000_000),
        ];
        assert_eq!(
            select_candidates(&nics, addr(TUN_SOCK)),
            vec![addr("192.168.1.157:54996")]
        );
    }

    #[test]
    fn candidates_round_trip_through_punch_response() {
        let candidates = vec![addr("192.168.1.145:54996"), addr("10.0.0.7:54996")];
        let mut ph = PunchHoleResponse {
            leapgate_local_addrs: encode(&candidates),
            ..Default::default()
        };
        ph.set_is_local(true);
        assert_eq!(peer_candidates(&ph), candidates);
        let not_local = PunchHoleResponse {
            leapgate_local_addrs: encode(&candidates),
            ..Default::default()
        };
        assert!(peer_candidates(&not_local).is_empty());
    }

    #[test]
    fn peer_candidates_keep_only_private_ipv4() {
        let lan = addr("192.168.1.145:54996");
        let junk = [
            "127.0.0.1:21118",
            "224.0.0.1:80",
            "255.255.255.255:80",
            "0.0.0.1:80",
            "8.8.8.8:53",
            "169.254.1.1:80",
            "198.18.0.1:80",
            "192.168.1.146:0",
        ];
        let mut sent: Vec<SocketAddr> = junk.iter().map(|s| addr(s)).collect();
        sent.push(lan);
        let mut ph = PunchHoleResponse {
            leapgate_local_addrs: encode(&sent),
            ..Default::default()
        };
        ph.set_is_local(true);
        assert_eq!(peer_candidates(&ph), vec![lan]);
    }

    #[test]
    fn listen_on_wildcard_only_beyond_the_socket_address() {
        let any = addr("0.0.0.0:54996");
        let tun_sock = addr(TUN_SOCK);
        let lan_sock = addr("192.168.1.145:54996");
        assert_eq!(listen_addr(&[lan_sock], tun_sock), any);
        assert_eq!(listen_addr(&[lan_sock], lan_sock), lan_sock);
        assert_eq!(listen_addr(&[], tun_sock), tun_sock);
    }

    #[test]
    fn connection_off_physical_adapters_gets_short_handshake() {
        let nics = [
            tun(),
            nic("Ethernet", IF_TYPE_ETHERNET, "192.168.1.145", true, 0),
        ];
        let tun_end = addr("198.18.0.1:13355");
        assert_eq!(handshake_timeout(&nics, tun_end), VIRTUAL_HANDSHAKE_TIMEOUT);
        let lan_end = addr("192.168.1.145:13355");
        assert_eq!(handshake_timeout(&nics, lan_end), HANDSHAKE_TIMEOUT);
        assert_eq!(handshake_timeout(&[], tun_end), HANDSHAKE_TIMEOUT);
    }

    #[test]
    fn physical_test_covers_both_families() {
        let mut wired = nic("Ethernet", IF_TYPE_ETHERNET, "192.168.1.145", true, 0);
        wired.ipv6 = vec![v6("2408:8256::10", Suffix::Other)];
        let mut tun = tun();
        tun.ipv6 = vec![v6("fdfe:dcba:9876::1", Suffix::Other)];
        let nics = [tun, wired];
        let ip = |s: &str| s.parse::<IpAddr>().unwrap();
        assert!(is_physical(&nics, ip("192.168.1.145")));
        assert!(is_physical(&nics, ip("2408:8256::10")));
        assert!(!is_physical(&nics, ip("198.18.0.1")));
        assert!(!is_physical(&nics, ip("fdfe:dcba:9876::1")));
        assert!(!is_physical(&nics, ip("2408:8256::11")));
        // No enumeration: nothing counts as physical.
        assert!(!is_physical(&[], ip("192.168.1.145")));
        assert!(!is_physical(&[], ip("2408:8256::10")));
    }

    // Contract 05 §4.7: the keyword rule also tightens the merged LAN candidates and the relay
    // probes' physical test, on purpose.
    #[test]
    fn keyword_adapters_are_virtual_for_every_user() {
        let described = |name: &str, description: &str, if_type: u32, ip: &str| {
            let mut n = nic(name, if_type, ip, true, 1_000_000_000);
            n.description = description.to_owned();
            n
        };
        let virtuals = [
            described(
                "ZeroTier One [8056c2e21c000001]",
                "ZeroTier Virtual Port",
                IF_TYPE_ETHERNET,
                "10.147.17.5",
            ),
            described(
                "VMware Network Adapter VMnet8",
                "VMware Virtual Ethernet Adapter for VMnet8",
                IF_TYPE_ETHERNET,
                "192.168.80.1",
            ),
            described(
                "Local Area Connection* 2",
                "Microsoft Wi-Fi Direct Virtual Adapter #2",
                IF_TYPE_IEEE80211,
                "192.168.137.1",
            ),
        ];
        let uplink = described(
            "vEthernet (External)",
            "Hyper-V Virtual Ethernet Adapter",
            IF_TYPE_ETHERNET,
            "192.168.1.145",
        );
        let mut nics = virtuals.to_vec();
        nics.push(uplink.clone());
        assert_eq!(
            select_candidates(&nics, addr(TUN_SOCK)),
            vec![addr("192.168.1.145:54996")]
        );
        for n in &virtuals {
            assert!(!is_physical(&nics, IpAddr::V4(n.ipv4[0])), "{}", n.name);
            assert!(!n.can_gather(), "{}", n.name);
        }
        assert!(is_physical(&nics, IpAddr::V4(uplink.ipv4[0])));
        assert!(uplink.can_gather());
    }

    #[test]
    fn every_ipv6_address_stays_physical_and_ice_keeps_one_per_prefix() {
        let temporary = v6("2408:8256:1:2:a5b0:1c2d:3e4f:5061", Suffix::Temporary);
        let stable = v6("2408:8256:1:2::10", Suffix::Other);
        let dhcp = v6("2408:8256:1:2::abcd", Suffix::Dhcp);
        let ula = v6("fd00:1:2:3::10", Suffix::Other);
        let mut wired = nic("Ethernet", IF_TYPE_ETHERNET, "192.168.1.145", true, 0);
        wired.ipv6 = vec![stable, dhcp, temporary, ula];
        let nics = [wired];
        for a in &nics[0].ipv6 {
            assert!(is_physical(&nics, IpAddr::V6(a.ip)));
        }
        assert_eq!(one_per_prefix(&nics[0].ipv6), vec![temporary.ip, ula.ip]);
        assert_eq!(one_per_prefix(&[dhcp, stable]), vec![dhcp.ip]);
    }

    #[test]
    fn a_gateway_of_either_family_lets_an_adapter_gather() {
        let mut v6_only = nic("Ethernet", IF_TYPE_ETHERNET, "192.168.1.145", false, 0);
        v6_only.has_gateway_v6 = true;
        assert!(v6_only.can_gather());
        let none = nic("Ethernet 2", IF_TYPE_ETHERNET, "172.20.80.1", false, 0);
        assert!(!none.can_gather());
        let mut down = v6_only.clone();
        down.up = false;
        assert!(!down.can_gather());
        assert!(!tun().can_gather());
    }

    #[test]
    fn net_cost_tiers() {
        assert_eq!(net_cost(IF_TYPE_ETHERNET), 0);
        assert_eq!(net_cost(IF_TYPE_IEEE80211), 10);
        assert_eq!(net_cost(IF_TYPE_PPP), 50);
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn first_secured_candidate_wins() {
        let bad = addr("192.168.1.145:54996");
        let good = addr("192.168.1.157:54996");
        let got = race(&[bad, good], |a| async move {
            if a == bad {
                Err(anyhow!("handshake failed"))
            } else {
                Ok(a)
            }
        })
        .await;
        assert_eq!(got, Some(good));
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn all_failing_candidates_leave_relay_to_caller() {
        let got: Option<()> = race(&[addr("192.168.1.145:54996")], |_| async {
            Err(anyhow!("connected but handshake failed"))
        })
        .await;
        assert_eq!(got, None);
        let none: Option<()> = race(&[], |_| async { Ok(()) }).await;
        assert_eq!(none, None);
    }
}
