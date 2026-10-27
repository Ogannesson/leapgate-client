//! Controlled side: which destination addresses an exit may reach (contract 02 §3.1). Pure
//! functions, without the network, Config or session objects.
//!
//! Hard refusals (loopback, link-local and cloud metadata, this device, reserved ranges, a
//! fake-ip literal) hold whatever the owner allows; soft ones (the LAN, a fake-ip answer) can
//! be opened by `leapgate-exit-allow-nets` (B3, B4). The reserved ranges follow the IANA IPv4
//! and IPv6 Special-Purpose Address Registries (both last updated 2025-10-09).

use crate::lan::Nic;
use cidr_utils::cidr::{Ipv4Cidr, Ipv6Cidr};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Reason {
    InvalidTarget,
    Reserved,
    Loopback,
    LinkLocal,
    Local,
    Lan,
    FakeIp,
    FakeIpLiteral,
    Nxdomain,
    ResolveFailed,
    NoRoute,
    Timeout,
    Refused,
    Unreachable,
}

/// The networks the owner opened for soft refusals.
#[derive(Debug, Default)]
pub struct AllowNets {
    v4: Vec<Ipv4Cidr>,
    v6: Vec<Ipv6Cidr>,
}

impl AllowNets {
    fn contains(&self, ip: IpAddr) -> bool {
        match ip {
            IpAddr::V4(ip) => self.v4.iter().any(|n| n.contains(ip)),
            IpAddr::V6(ip) => self.v6.iter().any(|n| n.contains(ip)),
        }
    }
}

/// What the policy knows of this device: every adapter's addresses and on-link networks,
/// virtual and offline adapters included, and the public IPv4 addresses (B11).
#[derive(Debug, Default)]
pub(crate) struct Snapshot {
    local: Vec<IpAddr>,
    v4_links: Vec<Ipv4Cidr>,
    /// The top 64 bits of every global IPv6 address: Windows reports a temporary address as a
    /// `/128`.
    v6_links: Vec<u64>,
}

impl Snapshot {
    pub(crate) fn new(nics: &[Nic], public_v4: &[Ipv4Addr]) -> Self {
        let mut s = Snapshot::default();
        for n in nics {
            s.local.extend(n.ipv4.iter().map(|&ip| IpAddr::V4(ip)));
            s.local.extend(n.all_ipv6.iter().map(|&ip| IpAddr::V6(ip)));
            // `from_prefix_and_bits` refuses a prefix length over 32.
            s.v4_links.extend(
                n.ipv4_prefixes
                    .iter()
                    .filter_map(|&(ip, bits)| Ipv4Cidr::from_prefix_and_bits(ip, bits).ok()),
            );
            s.v6_links.extend(
                n.all_ipv6
                    .iter()
                    .filter(|ip| in_2000_3(**ip))
                    .map(|&ip| top64(ip)),
            );
        }
        s.local.extend(public_v4.iter().map(|&ip| IpAddr::V4(ip)));
        s
    }
}

/// AWS IMDS over IPv6, GCP's on IPv6-only VMs, Alibaba Cloud ECS. They sit in ranges that only
/// refuse softly (`fc00::/7`, `100.64/10`), so they are checked before those.
const METADATA: [IpAddr; 3] = [
    IpAddr::V6(Ipv6Addr::new(0xfd00, 0xec2, 0, 0, 0, 0, 0, 0x254)),
    IpAddr::V6(Ipv6Addr::new(0xfd20, 0xce, 0, 0, 0, 0, 0, 0x254)),
    IpAddr::V4(Ipv4Addr::new(100, 100, 100, 200)),
];

/// 192.0.0.0/24 also covers the anycast 192.0.0.9 and 192.0.0.10 that IANA marks globally
/// reachable.
const RESERVED_V4: [(Ipv4Addr, u8); 8] = [
    (Ipv4Addr::new(0, 0, 0, 0), 8),
    (Ipv4Addr::new(192, 0, 0, 0), 24),
    (Ipv4Addr::new(192, 0, 2, 0), 24),
    (Ipv4Addr::new(192, 88, 99, 0), 24),
    (Ipv4Addr::new(198, 51, 100, 0), 24),
    (Ipv4Addr::new(203, 0, 113, 0), 24),
    (Ipv4Addr::new(224, 0, 0, 0), 4),
    (Ipv4Addr::new(240, 0, 0, 0), 4),
];

/// CIDR or single addresses, separated by commas, white space or newlines. Stricter than
/// cidr-utils' own parser, which takes `10` as 10.0.0.0/8 and masks such as `/255.0.0.0`.
pub fn parse_allow_nets(text: &str) -> Result<AllowNets, String> {
    let mut nets = AllowNets::default();
    for item in text
        .split(|c: char| c == ',' || c.is_whitespace())
        .filter(|s| !s.is_empty())
    {
        let bad = || item.to_owned();
        let (addr, bits) = match item.split_once('/') {
            Some((a, b)) => (a, Some(b)),
            None => (item, None),
        };
        let addr: IpAddr = addr.parse().map_err(|_| bad())?;
        let max = if addr.is_ipv4() { 32 } else { 128 };
        let bits = match bits {
            None => max,
            Some(b) if !b.is_empty() && b.bytes().all(|c| c.is_ascii_digit()) => {
                b.parse::<u8>().ok().filter(|&b| b <= max).ok_or_else(bad)?
            }
            Some(_) => return Err(bad()),
        };
        // Host bits are cleared, as cidr-utils does.
        match addr {
            IpAddr::V4(ip) => nets
                .v4
                .push(Ipv4Cidr::from_prefix_and_bits(ip, bits).map_err(|_| bad())?),
            IpAddr::V6(ip) => nets
                .v6
                .push(Ipv6Cidr::from_prefix_and_bits(ip, bits).map_err(|_| bad())?),
        }
    }
    Ok(nets)
}

/// Whether an exit may connect to `ip`. `literal`: the controller sent it as an address, not a
/// name this side resolved. An IPv4-mapped or NAT64 (`64:ff9b::/96`) address is judged by the
/// IPv4 address in it.
pub(crate) fn classify(
    ip: IpAddr,
    literal: bool,
    local: &Snapshot,
    allow: &AllowNets,
) -> Result<(), Reason> {
    let embedded = match ip {
        IpAddr::V6(v6) => embedded_v4(v6),
        IpAddr::V4(_) => None,
    };
    for ip in [Some(ip), embedded.map(IpAddr::V4)].into_iter().flatten() {
        if local.local.contains(&ip) {
            return Err(Reason::Local);
        }
        if METADATA.contains(&ip) {
            return Err(Reason::LinkLocal);
        }
    }
    match (ip, embedded) {
        (_, Some(v4)) | (IpAddr::V4(v4), None) => classify_v4(v4, literal, local, allow),
        (IpAddr::V6(v6), None) => classify_v6(v6, local, allow),
    }
}

fn classify_v4(
    ip: Ipv4Addr,
    literal: bool,
    local: &Snapshot,
    allow: &AllowNets,
) -> Result<(), Reason> {
    let soft = |reason| {
        if allow.contains(IpAddr::V4(ip)) {
            Ok(())
        } else {
            Err(reason)
        }
    };
    if ip.is_loopback() {
        Err(Reason::Loopback)
    } else if ip.is_link_local() {
        Err(Reason::LinkLocal)
    } else if RESERVED_V4.iter().any(|&(net, bits)| in_v4(ip, net, bits)) {
        Err(Reason::Reserved)
    } else if ip.is_private() || in_v4(ip, Ipv4Addr::new(100, 64, 0, 0), 10) {
        soft(Reason::Lan)
    } else if in_v4(ip, Ipv4Addr::new(198, 18, 0, 0), 15) {
        if literal {
            Err(Reason::FakeIpLiteral)
        } else {
            soft(Reason::FakeIp)
        }
    } else if local.v4_links.iter().any(|n| n.contains(ip)) {
        soft(Reason::Lan)
    } else {
        Ok(())
    }
}

fn classify_v6(ip: Ipv6Addr, local: &Snapshot, allow: &AllowNets) -> Result<(), Reason> {
    let s = ip.segments();
    let soft = |reason| {
        if allow.contains(IpAddr::V6(ip)) {
            Ok(())
        } else {
            Err(reason)
        }
    };
    if ip.is_loopback() {
        Err(Reason::Loopback)
    } else if ip.is_unicast_link_local() {
        Err(Reason::LinkLocal)
    } else if ip.is_unique_local() {
        soft(Reason::Lan)
    } else if !in_2000_3(ip)
        // 2001::/23 (Teredo, benchmarking, ORCHID and the anycast and protocol addresses IANA
        // marks globally reachable, refused with the rest), documentation 2001:db8::/32 and
        // 3fff::/20, 6to4 2002::/16.
        || (s[0] == 0x2001 && s[1] < 0x0200)
        || (s[0] == 0x2001 && s[1] == 0x0db8)
        || (s[0] == 0x3fff && s[1] < 0x1000)
        || s[0] == 0x2002
    {
        Err(Reason::Reserved)
    } else if local.v6_links.contains(&top64(ip)) {
        soft(Reason::Lan)
    } else {
        Ok(())
    }
}

/// Not `Ipv6Addr::to_ipv4`: it takes `::1` for 0.0.0.1, and deprecated `::a.b.c.d` too.
fn embedded_v4(ip: Ipv6Addr) -> Option<Ipv4Addr> {
    let bits = u128::from(ip);
    ip.to_ipv4_mapped().or_else(|| {
        (bits >> 32 == 0x0064_ff9b_0000_0000_0000_0000).then(|| Ipv4Addr::from(bits as u32))
    })
}

fn in_v4(ip: Ipv4Addr, net: Ipv4Addr, bits: u8) -> bool {
    let mask = u32::MAX.checked_shl(32 - u32::from(bits)).unwrap_or(0);
    u32::from(ip) & mask == u32::from(net) & mask
}

fn in_2000_3(ip: Ipv6Addr) -> bool {
    ip.segments()[0] & 0xe000 == 0x2000
}

fn top64(ip: Ipv6Addr) -> u64 {
    (u128::from(ip) >> 64) as u64
}

/// The opened failure text (README §2.4): fixed, without the destination, so the controller's
/// de-duplication works. Empty: the controller shows nothing.
pub fn opened_message(reason: Reason) -> &'static str {
    match reason {
        Reason::Reserved
        | Reason::Loopback
        | Reason::LinkLocal
        | Reason::Local
        | Reason::Lan
        | Reason::FakeIp => super::MSG_BLOCKED,
        Reason::FakeIpLiteral => super::MSG_FAKE_IP_LITERAL,
        Reason::InvalidTarget
        | Reason::Nxdomain
        | Reason::ResolveFailed
        | Reason::NoRoute
        | Reason::Timeout
        | Reason::Refused
        | Reason::Unreachable => "",
    }
}

/// B12's codes, as the controlled side's log writes them.
pub fn reason_code(reason: Reason) -> &'static str {
    match reason {
        Reason::InvalidTarget => "invalid_target",
        Reason::Reserved => "reserved",
        Reason::Loopback => "loopback",
        Reason::LinkLocal => "link_local",
        Reason::Local => "local",
        Reason::Lan => "lan",
        Reason::FakeIp => "fake_ip",
        Reason::FakeIpLiteral => "fake_ip_literal",
        Reason::Nxdomain => "nxdomain",
        Reason::ResolveFailed => "resolve_failed",
        Reason::NoRoute => "no_route",
        Reason::Timeout => "timeout",
        Reason::Refused => "refused",
        Reason::Unreachable => "unreachable",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lan::{Suffix, IF_TYPE_ETHERNET, V6};

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    fn nothing() -> Snapshot {
        Snapshot::default()
    }

    fn check(s: &str, literal: bool, local: &Snapshot, allow: &AllowNets) -> Result<(), Reason> {
        classify(ip(s), literal, local, allow)
    }

    fn all(cases: &[(&str, Result<(), Reason>)], local: &Snapshot, allow: &AllowNets) {
        for &(s, want) in cases {
            assert_eq!(check(s, false, local, allow), want, "{s}");
        }
    }

    use Reason::*;

    #[test]
    fn every_ipv4_class_at_its_edges() {
        let cases = [
            ("126.255.255.255", Ok(())),
            ("127.0.0.0", Err(Loopback)),
            ("127.255.255.255", Err(Loopback)),
            ("128.0.0.0", Ok(())),
            ("169.253.255.255", Ok(())),
            ("169.254.0.0", Err(LinkLocal)),
            ("169.254.169.254", Err(LinkLocal)),
            ("169.254.255.255", Err(LinkLocal)),
            ("169.255.0.0", Ok(())),
            ("0.0.0.0", Err(Reserved)),
            ("0.255.255.255", Err(Reserved)),
            ("1.0.0.0", Ok(())),
            ("191.255.255.255", Ok(())),
            ("192.0.0.0", Err(Reserved)),
            ("192.0.0.9", Err(Reserved)),
            ("192.0.0.10", Err(Reserved)),
            ("192.0.0.255", Err(Reserved)),
            ("192.0.1.0", Ok(())),
            ("192.0.2.0", Err(Reserved)),
            ("192.0.2.255", Err(Reserved)),
            ("192.0.3.0", Ok(())),
            ("192.31.196.1", Ok(())),
            ("192.52.193.1", Ok(())),
            ("192.88.98.255", Ok(())),
            ("192.88.99.0", Err(Reserved)),
            ("192.88.99.255", Err(Reserved)),
            ("192.88.100.0", Ok(())),
            ("192.175.48.1", Ok(())),
            ("198.51.99.255", Ok(())),
            ("198.51.100.0", Err(Reserved)),
            ("198.51.100.255", Err(Reserved)),
            ("198.51.101.0", Ok(())),
            ("203.0.112.255", Ok(())),
            ("203.0.113.0", Err(Reserved)),
            ("203.0.113.255", Err(Reserved)),
            ("203.0.114.0", Ok(())),
            ("223.255.255.255", Ok(())),
            ("224.0.0.0", Err(Reserved)),
            ("239.255.255.255", Err(Reserved)),
            ("240.0.0.0", Err(Reserved)),
            ("255.255.255.255", Err(Reserved)),
            ("9.255.255.255", Ok(())),
            ("10.0.0.0", Err(Lan)),
            ("10.255.255.255", Err(Lan)),
            ("11.0.0.0", Ok(())),
            ("172.15.255.255", Ok(())),
            ("172.16.0.0", Err(Lan)),
            ("172.31.255.255", Err(Lan)),
            ("172.32.0.0", Ok(())),
            ("192.167.255.255", Ok(())),
            ("192.168.0.0", Err(Lan)),
            ("192.168.255.255", Err(Lan)),
            ("192.169.0.0", Ok(())),
            ("100.63.255.255", Ok(())),
            ("100.64.0.0", Err(Lan)),
            ("100.127.255.255", Err(Lan)),
            ("100.128.0.0", Ok(())),
            ("100.100.100.200", Err(LinkLocal)),
            ("198.17.255.255", Ok(())),
            ("198.18.0.0", Err(FakeIp)),
            ("198.19.255.255", Err(FakeIp)),
            ("198.20.0.0", Ok(())),
        ];
        all(&cases, &nothing(), &AllowNets::default());
        assert_eq!(
            check("198.18.0.1", true, &nothing(), &AllowNets::default()),
            Err(FakeIpLiteral)
        );
        assert_eq!(
            check("198.18.0.1", false, &nothing(), &AllowNets::default()),
            Err(FakeIp)
        );
    }

    #[test]
    fn every_ipv6_class_at_its_edges() {
        let cases = [
            ("::1", Err(Loopback)),
            ("::", Err(Reserved)),
            ("::2", Err(Reserved)),
            ("fe7f:ffff:ffff:ffff:ffff:ffff:ffff:ffff", Err(Reserved)),
            ("fe80::", Err(LinkLocal)),
            ("febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff", Err(LinkLocal)),
            ("fec0::1", Err(Reserved)),
            ("fec0:0:0:ffff::1", Err(Reserved)),
            ("fbff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", Err(Reserved)),
            ("fc00::", Err(Lan)),
            ("fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", Err(Lan)),
            ("fe00::", Err(Reserved)),
            ("fd00:ec2::254", Err(LinkLocal)),
            ("fd20:ce::254", Err(LinkLocal)),
            ("fd00:ec2::253", Err(Lan)),
            ("ff02::1", Err(Reserved)),
            ("ff00::", Err(Reserved)),
            ("100::1", Err(Reserved)),
            ("100:0:0:1::1", Err(Reserved)),
            ("64:ff9b:1::1", Err(Reserved)),
            ("5f00::1", Err(Reserved)),
            ("1fff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", Err(Reserved)),
            ("2000::", Ok(())),
            ("2001::", Err(Reserved)),
            ("2001::1", Err(Reserved)),
            ("2001:1::1", Err(Reserved)),
            ("2001:2::1", Err(Reserved)),
            ("2001:3::1", Err(Reserved)),
            ("2001:4:112::1", Err(Reserved)),
            ("2001:20::1", Err(Reserved)),
            ("2001:30::1", Err(Reserved)),
            ("2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff", Err(Reserved)),
            ("2001:200::", Ok(())),
            ("2001:db7:ffff:ffff:ffff:ffff:ffff:ffff", Ok(())),
            ("2001:db8::", Err(Reserved)),
            ("2001:db8:ffff:ffff:ffff:ffff:ffff:ffff", Err(Reserved)),
            ("2001:db9::", Ok(())),
            ("2001:4860:4860::8888", Ok(())),
            ("2001:ffff:ffff:ffff:ffff:ffff:ffff:ffff", Ok(())),
            ("2002::", Err(Reserved)),
            ("2002:c000:204::1", Err(Reserved)),
            ("2002:ffff:ffff:ffff:ffff:ffff:ffff:ffff", Err(Reserved)),
            ("2003::", Ok(())),
            ("2620:4f:8000::1", Ok(())),
            ("3ffe:ffff:ffff:ffff:ffff:ffff:ffff:ffff", Ok(())),
            ("3fff::", Err(Reserved)),
            ("3fff:fff:ffff:ffff:ffff:ffff:ffff:ffff", Err(Reserved)),
            ("3fff:1000::", Ok(())),
            ("3fff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", Ok(())),
            ("4000::", Err(Reserved)),
        ];
        all(&cases, &nothing(), &AllowNets::default());
    }

    #[test]
    fn embedded_ipv4_is_judged_as_ipv4() {
        let local = Snapshot::new(
            &[Nic {
                ipv4: vec![Ipv4Addr::new(192, 168, 1, 145)],
                ..Default::default()
            }],
            &[],
        );
        let cases = [
            ("::ffff:127.0.0.1", Err(Loopback)),
            ("::ffff:10.0.0.1", Err(Lan)),
            ("::ffff:192.168.1.145", Err(Local)),
            ("::ffff:169.254.169.254", Err(LinkLocal)),
            ("::ffff:100.100.100.200", Err(LinkLocal)),
            ("::ffff:198.18.0.1", Err(FakeIp)),
            ("::ffff:0.0.0.0", Err(Reserved)),
            ("::ffff:8.8.8.8", Ok(())),
            ("64:ff9b::127.0.0.1", Err(Loopback)),
            ("64:ff9b::10.0.0.1", Err(Lan)),
            ("64:ff9b::192.168.1.145", Err(Local)),
            ("64:ff9b::169.254.169.254", Err(LinkLocal)),
            ("64:ff9b::100.100.100.200", Err(LinkLocal)),
            ("64:ff9b::198.18.0.1", Err(FakeIp)),
            ("64:ff9b::8.8.8.8", Ok(())),
            // Just outside the /96, with 8.8.8.8 in the low 32 bits.
            ("64:ff9b::1:808:808", Err(Reserved)),
            ("64:ff9b:0:0:1::808:808", Err(Reserved)),
            // Deprecated IPv4-compatible addresses are not taken apart.
            ("::127.0.0.1", Err(Reserved)),
        ];
        all(&cases, &local, &AllowNets::default());
        let allow = parse_allow_nets("10.0.0.0/8 198.18.0.0/15").unwrap();
        assert_eq!(check("64:ff9b::10.0.0.1", false, &local, &allow), Ok(()));
        assert_eq!(check("::ffff:198.18.0.1", false, &local, &allow), Ok(()));
        assert_eq!(
            check("::ffff:198.18.0.1", true, &local, &allow),
            Err(FakeIpLiteral)
        );
        assert_eq!(
            check("64:ff9b::198.18.0.1", true, &local, &allow),
            Err(FakeIpLiteral)
        );
        // A wide IPv6 rule does not open the IPv4 inside.
        let v6_only = parse_allow_nets("::/0").unwrap();
        assert_eq!(check("::ffff:10.0.0.1", false, &local, &v6_only), Err(Lan));
        assert_eq!(
            check("64:ff9b::10.0.0.1", false, &local, &v6_only),
            Err(Lan)
        );
    }

    #[test]
    fn every_address_of_this_device_is_local() {
        let deprecated: Ipv6Addr = "2408:8256:1:2:dead:beef:1:2".parse().unwrap();
        let wired = Nic {
            name: "Ethernet".to_owned(),
            if_type: IF_TYPE_ETHERNET,
            up: true,
            ipv4: vec![Ipv4Addr::new(192, 168, 1, 145)],
            ipv4_prefixes: vec![(Ipv4Addr::new(192, 168, 1, 145), 24)],
            ipv6: vec![V6 {
                ip: "2408:8256:1:2::10".parse().unwrap(),
                suffix: Suffix::Other,
            }],
            all_ipv6: vec!["2408:8256:1:2::10".parse().unwrap(), deprecated],
            ..Default::default()
        };
        let offline_vpn = Nic {
            name: "WireGuard".to_owned(),
            if_type: 53,
            ipv4: vec![Ipv4Addr::new(203, 0, 114, 7)],
            all_ipv6: vec!["2606:4700::1234".parse().unwrap()],
            ..Default::default()
        };
        let public = Ipv4Addr::new(93, 184, 215, 2);
        let local = Snapshot::new(&[wired, offline_vpn], &[public]);
        let wide = parse_allow_nets("0.0.0.0/0, ::/0 2408:8256:1:2::/64").unwrap();
        for allow in [AllowNets::default(), wide] {
            for s in [
                "192.168.1.145",
                "2408:8256:1:2::10",
                "2408:8256:1:2:dead:beef:1:2",
                "203.0.114.7",
                "2606:4700::1234",
                "93.184.215.2",
                "::ffff:93.184.215.2",
                "64:ff9b::5db8:d702",
            ] {
                assert_eq!(check(s, false, &local, &allow), Err(Local), "{s}");
                assert_eq!(check(s, true, &local, &allow), Err(Local), "{s}");
            }
        }
        // Neighbours on the same links are LAN, softly.
        assert_eq!(
            check("192.168.1.1", false, &local, &AllowNets::default()),
            Err(Lan)
        );
        assert_eq!(
            check("2408:8256:1:2::1", false, &local, &AllowNets::default()),
            Err(Lan)
        );
        assert_eq!(
            check("2408:8256:1:3::1", false, &local, &AllowNets::default()),
            Ok(())
        );
    }

    #[test]
    fn on_link_ipv4_networks_take_the_reported_prefix_only() {
        let nic = |ip: Ipv4Addr, bits: u8| Nic {
            ipv4: vec![ip],
            ipv4_prefixes: vec![(ip, bits)],
            ..Default::default()
        };
        let local = Snapshot::new(
            &[
                nic(Ipv4Addr::new(93, 184, 216, 2), 29),
                nic(Ipv4Addr::new(45, 1, 1, 1), 33),
            ],
            &[],
        );
        let none = AllowNets::default();
        assert_eq!(check("93.184.216.1", false, &local, &none), Err(Lan));
        assert_eq!(check("93.184.216.7", false, &local, &none), Err(Lan));
        assert_eq!(check("93.184.216.8", false, &local, &none), Ok(()));
        // A length over 32 is no network; nothing is guessed.
        assert_eq!(check("45.1.1.2", false, &local, &none), Ok(()));
    }

    #[test]
    fn allowed_networks_open_soft_refusals_only() {
        let allow = parse_allow_nets(
            "10.0.0.0/8,172.16.0.5\n192.168.0.0/16\t100.64.0.0/10  fd00::/8 fc00::/7 \
             198.18.0.0/15, 0.0.0.0/0, ::/0",
        )
        .unwrap();
        let none = nothing();
        for s in [
            "10.1.2.3",
            "172.16.0.5",
            "192.168.1.1",
            "100.64.0.1",
            "fd12::1",
            "fc00::1",
            "198.18.0.1",
            "8.8.8.8",
        ] {
            assert_eq!(check(s, false, &none, &allow), Ok(()), "{s}");
        }
        for (s, want) in [
            ("127.0.0.1", Loopback),
            ("::1", Loopback),
            ("169.254.169.254", LinkLocal),
            ("fe80::1", LinkLocal),
            ("fd00:ec2::254", LinkLocal),
            ("fd20:ce::254", LinkLocal),
            ("100.100.100.200", LinkLocal),
            ("0.0.0.0", Reserved),
            ("224.0.0.1", Reserved),
            ("255.255.255.255", Reserved),
            ("::", Reserved),
            ("ff02::1", Reserved),
            ("2001::1", Reserved),
            ("2002::1", Reserved),
            ("2001:db8::1", Reserved),
        ] {
            assert_eq!(check(s, false, &none, &allow), Err(want), "{s}");
        }
        assert_eq!(check("198.18.0.1", true, &none, &allow), Err(FakeIpLiteral));
        // A single address is a /32.
        let one = parse_allow_nets("172.16.0.5").unwrap();
        assert_eq!(check("172.16.0.6", false, &none, &one), Err(Lan));
        // Host bits are cleared.
        let host_bits = parse_allow_nets("192.168.1.5/24").unwrap();
        assert_eq!(check("192.168.1.200", false, &none, &host_bits), Ok(()));
        assert_eq!(check("192.168.2.1", false, &none, &host_bits), Err(Lan));
        let v6 = parse_allow_nets("fd00:1:2:3::/64").unwrap();
        assert_eq!(check("fd00:1:2:3::99", false, &none, &v6), Ok(()));
        assert_eq!(check("fd00:1:2:4::99", false, &none, &v6), Err(Lan));
    }

    #[test]
    fn allowed_networks_syntax() {
        assert!(parse_allow_nets("").is_ok());
        assert!(parse_allow_nets(" ,\n ").is_ok());
        assert!(parse_allow_nets("0.0.0.0/0 ::/0 10.0.0.0/32 fd00::/128").is_ok());
        for bad in [
            "10",
            "192.168",
            "010.0.0.1",
            "10.0.0.0/255.0.0.0",
            "10.0.0.0/33",
            "fd00::/129",
            "10.0.0.0/",
            "10.0.0.0/-1",
            "10.0.0.0/+8",
            "10.0.0.0/8/8",
            "example.com",
            "10.0.0.1:80",
            "[fd00::1]:80",
            "fe80::1%2",
            "10.0.0.0/8, nope",
        ] {
            assert!(parse_allow_nets(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn reasons_have_fixed_codes_and_messages() {
        use super::super::{MSG_BLOCKED, MSG_FAKE_IP_LITERAL};
        let table = [
            (InvalidTarget, "invalid_target", ""),
            (Reserved, "reserved", MSG_BLOCKED),
            (Loopback, "loopback", MSG_BLOCKED),
            (LinkLocal, "link_local", MSG_BLOCKED),
            (Local, "local", MSG_BLOCKED),
            (Lan, "lan", MSG_BLOCKED),
            (FakeIp, "fake_ip", MSG_BLOCKED),
            (FakeIpLiteral, "fake_ip_literal", MSG_FAKE_IP_LITERAL),
            (Nxdomain, "nxdomain", ""),
            (ResolveFailed, "resolve_failed", ""),
            (NoRoute, "no_route", ""),
            (Timeout, "timeout", ""),
            (Refused, "refused", ""),
            (Unreachable, "unreachable", ""),
        ];
        for (reason, code, message) in table {
            assert_eq!(reason_code(reason), code);
            assert_eq!(opened_message(reason), message, "{code}");
        }
    }
}
