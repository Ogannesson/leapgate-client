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
    bail,
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
    net::{IpAddr, Ipv4Addr, SocketAddr},
    time::{Duration, Instant},
};

const MAX_CANDIDATES: usize = 8;
/// Upstream's connect timeout for an `is_local` punch (`MIN` in `Client::connect`).
const CONNECT_TIMEOUT_MS: u64 = 1000;
/// Upstream bounds the handshake only by `READ_TIMEOUT`. A candidate that the peer's listener
/// queued but never accepted (it takes one connection) would hold the race that long.
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(3);

// Windows `IfType` values of virtual adapters: Wintun (mihomo, sing-box, WireGuard, Tailscale)
// and the newer TAP drivers report 53.
const IF_TYPE_PPP: u32 = 23;
const IF_TYPE_LOOPBACK: u32 = 24;
const IF_TYPE_PROP_VIRTUAL: u32 = 53;
const IF_TYPE_TUNNEL: u32 = 131;
const IF_TYPE_ETHERNET: u32 = 6;

#[derive(Debug, Clone, Default)]
struct Nic {
    name: String,
    if_type: u32,
    up: bool,
    ipv4: Vec<Ipv4Addr>,
    has_gateway: bool,
    /// Bits per second, 0 when unknown.
    speed: u64,
}

impl Nic {
    fn is_virtual(&self) -> bool {
        if matches!(
            self.if_type,
            IF_TYPE_PPP | IF_TYPE_LOOPBACK | IF_TYPE_PROP_VIRTUAL | IF_TYPE_TUNNEL
        ) {
            return true;
        }
        let name = self.name.to_lowercase();
        name.starts_with("tun")
            || name.starts_with("utun")
            || name.contains("mihomo")
            || name.contains("wintun")
    }
}

/// TUN adapters and fake-ip pools of mihomo / sing-box sit in `198.18.0.0/15`; Tailscale and
/// carrier-grade NAT use `100.64.0.0/10`. Neither is a LAN address.
fn excluded_ip(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    ip.is_loopback()
        || ip.is_link_local()
        || ip.is_unspecified()
        || (o[0] == 198 && (o[1] & 0xfe) == 18)
        || (o[0] == 100 && (o[1] & 0xc0) == 64)
}

/// Whether `ip` is an address of an up, physical adapter. A default gateway is not required:
/// this only decides whether the socket's own address can stay first.
fn is_physical(nics: &[Nic], ip: Ipv4Addr) -> bool {
    !excluded_ip(ip)
        && nics
            .iter()
            .any(|n| n.up && !n.is_virtual() && n.ipv4.contains(&ip))
}

fn select_candidates(nics: &[Nic], sock_local: SocketAddr) -> Vec<SocketAddr> {
    let SocketAddr::V4(sock_v4) = sock_local else {
        return Vec::new();
    };
    let port = sock_local.port();
    let mut out = Vec::new();
    if is_physical(nics, *sock_v4.ip()) {
        out.push(sock_local);
    }
    // A default gateway also rules out WSL / Hyper-V vEthernet and host-only adapters.
    let mut usable: Vec<&Nic> = nics
        .iter()
        .filter(|n| n.up && n.has_gateway && !n.is_virtual())
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

/// Candidates a Porta peer listed in an `is_local` response; empty otherwise. Only private
/// IPv4 addresses are LAN candidates; anything else the peer or server put there (loopback,
/// multicast, public addresses) would have this side connect to it unbound.
pub fn peer_candidates(ph: &PunchHoleResponse) -> Vec<SocketAddr> {
    if !ph.is_local() {
        return Vec::new();
    }
    let mut out = Vec::new();
    for b in ph.porta_local_addrs.iter() {
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
        nics.is_empty() || is_physical(&nics, ip)
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
        if !left_through_lan(nics, conn.local_addr()) {
            bail!("routed into a local tunnel from {}", conn.local_addr());
        }
        timeout(HANDSHAKE_TIMEOUT, handshake(conn)).await?
    })
    .await
}

/// A candidate outside this side's own LAN segments is routed into the TUN, whose stack
/// completes the TCP handshake locally and then never answers. Its local end is then the
/// virtual adapter's address, so it fails here at once instead of holding the handshake
/// timeout, and the handshake bytes never reach the proxy. An empty adapter list proves nothing.
fn left_through_lan(nics: &[Nic], local: SocketAddr) -> bool {
    match local.ip() {
        IpAddr::V4(ip) => nics.is_empty() || is_physical(nics, ip),
        IpAddr::V6(_) => true,
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
fn nics() -> Vec<Nic> {
    Vec::new()
}

/// `GetAdaptersAddresses` directly rather than `default-net`, which calls `SendARP` for every
/// adapter with a gateway and took over 4 s on a machine with a disconnected one.
#[cfg(windows)]
fn nics() -> Vec<Nic> {
    use windows::Win32::{
        Foundation::{ERROR_BUFFER_OVERFLOW, NO_ERROR},
        NetworkManagement::{
            IpHelper::{
                GetAdaptersAddresses, GAA_FLAG_INCLUDE_GATEWAYS, GAA_FLAG_SKIP_ANYCAST,
                GAA_FLAG_SKIP_DNS_SERVER, GAA_FLAG_SKIP_MULTICAST, IP_ADAPTER_ADDRESSES_LH,
            },
            Ndis::IfOperStatusUp,
        },
        Networking::WinSock::{AF_INET, SOCKADDR_IN, SOCKET_ADDRESS},
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

    let flags = GAA_FLAG_INCLUDE_GATEWAYS
        | GAA_FLAG_SKIP_ANYCAST
        | GAA_FLAG_SKIP_MULTICAST
        | GAA_FLAG_SKIP_DNS_SERVER;
    let mut size: u32 = 16 * 1024;
    // u64 elements keep the buffer aligned for IP_ADAPTER_ADDRESSES_LH.
    let mut buf: Vec<u64>;
    let mut tries = 0;
    loop {
        buf = vec![0u64; (size as usize).div_ceil(8)];
        // SAFETY: buf holds `size` bytes, as passed.
        let ret = unsafe {
            GetAdaptersAddresses(
                AF_INET.0 as u32,
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
        let mut u = a.FirstUnicastAddress;
        while let Some(ua) = unsafe { u.as_ref() } {
            ipv4.extend(ipv4_of(&ua.Address));
            u = ua.Next;
        }
        let mut has_gateway = false;
        let mut g = a.FirstGatewayAddress;
        while let Some(ga) = unsafe { g.as_ref() } {
            has_gateway |= ipv4_of(&ga.Address).is_some_and(|ip| !ip.is_unspecified());
            g = ga.Next;
        }
        out.push(Nic {
            name: unsafe { a.FriendlyName.to_string() }.unwrap_or_default(),
            if_type: a.IfType,
            up: a.OperStatus == IfOperStatusUp,
            ipv4,
            has_gateway,
            speed: if a.TransmitLinkSpeed == u64::MAX {
                0
            } else {
                a.TransmitLinkSpeed
            },
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
            has_gateway: gateway,
            speed,
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
            porta_local_addrs: encode(&candidates),
            ..Default::default()
        };
        ph.set_is_local(true);
        assert_eq!(peer_candidates(&ph), candidates);
        let not_local = PunchHoleResponse {
            porta_local_addrs: encode(&candidates),
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
            porta_local_addrs: encode(&sent),
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
    fn connection_caught_by_local_tun_is_not_lan() {
        let nics = [
            tun(),
            nic("Ethernet", IF_TYPE_ETHERNET, "192.168.1.145", true, 0),
        ];
        assert!(!left_through_lan(&nics, addr("198.18.0.1:13355")));
        assert!(left_through_lan(&nics, addr("192.168.1.145:13355")));
        assert!(left_through_lan(&[], addr("198.18.0.1:13355")));
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
