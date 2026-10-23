//! The probe thread: one per process, on blocking `std::net` sockets rather than tokio. The
//! heartbeat runs on the hbbs sync loop's single-threaded runtime, where each tick also makes
//! blocking calls; timing connects there would count those stalls.

use super::{ProbeResult, CONFIRM_TTL, STATE, WAKE};
use crate::{lan, sign};
use hbb_common::{
    config::{self, Config, RELAY_PORT},
    log,
    rand::{self, Rng},
    socket_client::check_port,
    throttled_log,
};
use std::{
    net::{IpAddr, SocketAddr, TcpStream, ToSocketAddrs},
    sync::Once,
    thread,
    time::{Duration, Instant},
};

const TRIES: usize = 3;
const TRY_GAP: Duration = Duration::from_millis(200);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(3);
/// A public relay this fast means a proxy on the way completed the handshake: a router's
/// transparent proxy answers the SYN itself, and the local address is still the physical one.
const PROXY_RTT: Duration = Duration::from_millis(2);
const LOG_INTERVAL: Duration = Duration::from_secs(60);

pub(super) struct Attempt {
    pub elapsed: Duration,
    pub local: IpAddr,
    pub remote: IpAddr,
}

pub(super) fn start() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        if let Err(e) = thread::Builder::new()
            .name("porta-route-probe".to_owned())
            .spawn(run)
        {
            log::error!("porta route: cannot start the probe thread: {}", e);
        }
    });
}

fn run() {
    let mut due = None;
    loop {
        let (rev, relays) = next_round(&mut due);
        let result = round(rev, &relays);
        // A round for a list replaced meanwhile is stored too; `probes` skips it by its rev.
        if let Some(s) = STATE.lock().unwrap().as_mut() {
            s.result = result;
        }
    }
}

/// Blocks until a round is due: there are relays, a heartbeat succeeded within `CONFIRM_TTL`,
/// and the wait for this list has passed (10~30 s after a new list, then the interval with
/// ±10% jitter). `due` holds the rev that wait was set for and its end.
fn next_round(due: &mut Option<(i64, Instant)>) -> (i64, Vec<String>) {
    let mut g = STATE.lock().unwrap();
    loop {
        let now = Instant::now();
        let wait = match g.as_ref() {
            Some(s)
                if !s.relays.is_empty()
                    && now.saturating_duration_since(s.confirmed_at) < CONFIRM_TTL =>
            {
                let at = match *due {
                    Some((rev, at)) if rev == s.rev => at,
                    _ => now + Duration::from_secs(rand::thread_rng().gen_range(10..=30)),
                };
                if at <= now {
                    let next = s.interval.mul_f64(rand::thread_rng().gen_range(0.9..=1.1));
                    *due = Some((s.rev, now + next));
                    return (s.rev, s.relays.clone());
                }
                *due = Some((s.rev, at));
                Some(at - now)
            }
            _ => None,
        };
        g = match wait {
            Some(d) => WAKE.wait_timeout(g, d).unwrap().0,
            None => WAKE.wait(g).unwrap(),
        };
    }
}

/// One round over `relays`. `None`: nothing worth reporting, and the last round is cleared.
fn round(rev: i64, relays: &[String]) -> Option<ProbeResult> {
    // Through a proxy or WebSocket the real relay connection takes another path entirely.
    if Config::is_proxy() || config::use_ws() || !matches!(sign::server_pk(), Ok(Some(_))) {
        return None;
    }
    let physical = lan::physical_snapshot();
    let attempts = thread::scope(|s| {
        let handles: Vec<_> = relays
            .iter()
            .map(|h| {
                thread::Builder::new()
                    .spawn_scoped(s, move || probe(h))
                    .ok()
            })
            .collect();
        handles
            .into_iter()
            .zip(relays)
            .map(|(j, h)| Some((h.clone(), j?.join().ok()?)))
            .collect::<Option<Vec<_>>>()
    })?;
    summarize(rev, &attempts, physical)
}

/// Resolved once per round, outside the timing; addresses tried in the order the resolver
/// gives them, as upstream's `FramedStream::new` does for the real relay connection.
fn probe(host: &str) -> Vec<Option<Attempt>> {
    let addrs: Vec<SocketAddr> = check_port(host, RELAY_PORT)
        .to_socket_addrs()
        .map(Iterator::collect)
        .unwrap_or_default();
    (0..TRIES)
        .map(|i| {
            if i > 0 {
                thread::sleep(TRY_GAP);
            }
            connect_first(&addrs)
        })
        .collect()
}

fn connect_first(addrs: &[SocketAddr]) -> Option<Attempt> {
    addrs.iter().find_map(|addr| {
        let start = Instant::now();
        let stream = TcpStream::connect_timeout(addr, CONNECT_TIMEOUT).ok()?;
        let elapsed = start.elapsed();
        Some(Attempt {
            elapsed,
            local: stream.local_addr().ok()?.ip(),
            remote: addr.ip(),
        })
    })
}

/// The fastest try per relay, or `down` when every try failed. The whole round is dropped when
/// any try was answered by a proxy rather than the relay: a local address off the physical
/// adapters (a TUN completed the handshake on this machine), or a public relay faster than
/// `PROXY_RTT` (a router did).
fn summarize(
    rev: i64,
    attempts: &[(String, Vec<Option<Attempt>>)],
    is_physical: impl Fn(IpAddr) -> bool,
) -> Option<ProbeResult> {
    let (mut rtt, mut down) = (Vec::new(), Vec::new());
    for (host, tries) in attempts {
        let mut best: Option<Duration> = None;
        for a in tries.iter().flatten() {
            if !is_physical(a.local) {
                throttled_log!(
                    LOG_INTERVAL,
                    info,
                    "porta route: probe round dropped, local address {} not on a physical adapter",
                    a.local
                );
                return None;
            }
            if is_public(a.remote) && a.elapsed < PROXY_RTT {
                throttled_log!(
                    LOG_INTERVAL,
                    info,
                    "porta route: probe round dropped, {} answered in {}us (proxy?)",
                    host,
                    a.elapsed.as_micros()
                );
                return None;
            }
            best = Some(best.map_or(a.elapsed, |b| b.min(a.elapsed)));
        }
        match best {
            Some(d) => rtt.push((host.clone(), d.as_micros().div_ceil(1000).max(1) as u32)),
            None => down.push(host.clone()),
        }
    }
    Some(ProbeResult {
        rev,
        at: Instant::now(),
        rtt,
        down,
    })
}

/// `198.18.0.0/15` counts as public: a router's fake-ip DNS resolves the relay into it.
fn is_public(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ip) => {
            let o = ip.octets();
            !(ip.is_private()
                || ip.is_loopback()
                || ip.is_link_local()
                || (o[0] == 100 && (o[1] & 0xc0) == 64))
        }
        IpAddr::V6(ip) => !(ip.is_loopback() || ip.is_unique_local() || ip.is_unicast_link_local()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const LAN: &str = "192.168.1.145";

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    fn ok(us: u64, remote: &str) -> Option<Attempt> {
        Some(Attempt {
            elapsed: Duration::from_micros(us),
            local: ip(LAN),
            remote: ip(remote),
        })
    }

    fn on_lan(a: IpAddr) -> bool {
        a == ip(LAN)
    }

    fn host(name: &str, tries: Vec<Option<Attempt>>) -> (String, Vec<Option<Attempt>>) {
        (name.to_owned(), tries)
    }

    #[test]
    fn fastest_try_rounded_up_and_failures_down() {
        let attempts = [
            host(
                "a",
                vec![ok(30_400, "1.1.1.1"), ok(22_100, "1.1.1.1"), None],
            ),
            host(
                "d",
                vec![ok(41_000, "1.1.1.1"), ok(48_000, "1.1.1.1"), None],
            ),
            host("b", vec![None, None, None]),
            // Private relay on the LAN: under 1 ms is real, and still reports 1.
            host(
                "c",
                vec![ok(300, "192.168.1.2"), ok(900, "192.168.1.2"), None],
            ),
        ];
        let r = summarize(7, &attempts, on_lan).unwrap();
        assert_eq!(r.rev, 7);
        assert_eq!(
            r.rtt,
            vec![
                ("a".to_owned(), 23),
                ("d".to_owned(), 41),
                ("c".to_owned(), 1)
            ]
        );
        assert_eq!(r.down, vec!["b".to_owned()]);
    }

    #[test]
    fn local_address_off_physical_adapters_drops_round() {
        let mut tun = ok(900, "1.1.1.1");
        tun.as_mut().unwrap().local = ip("198.18.0.1");
        let attempts = [
            host("a", vec![ok(23_000, "1.1.1.1")]),
            host("b", vec![ok(40_000, "2.2.2.2"), tun]),
        ];
        assert_eq!(summarize(7, &attempts, on_lan), None);
        // No adapter list trusts nothing.
        let attempts = [host("a", vec![ok(23_000, "1.1.1.1")])];
        assert_eq!(summarize(7, &attempts, |_| false), None);
    }

    #[test]
    fn public_relay_under_2ms_drops_round() {
        for remote in ["8.8.8.8", "198.18.0.5", "2408:8256::1"] {
            let attempts = [
                host("a", vec![ok(23_000, "1.1.1.1")]),
                host("b", vec![ok(40_000, remote), ok(1_500, remote)]),
            ];
            assert_eq!(summarize(7, &attempts, on_lan), None, "{remote}");
        }
        // Private, carrier-grade NAT and ULA relays may well be that close.
        for remote in ["10.0.0.2", "100.64.1.2", "fd00::2"] {
            let attempts = [host("b", vec![ok(1_000, remote)])];
            let r = summarize(7, &attempts, on_lan).unwrap();
            assert_eq!(r.rtt, vec![("b".to_owned(), 1)], "{remote}");
        }
        // A public relay at 2 ms is believed.
        let attempts = [host("b", vec![ok(2_000, "8.8.8.8")])];
        assert!(summarize(7, &attempts, on_lan).is_some());
    }
}
