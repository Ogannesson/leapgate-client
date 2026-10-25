//! The probe thread: one per process, on blocking `std::net` sockets rather than tokio. The
//! heartbeat runs on the hbbs sync loop's single-threaded runtime, where each tick also makes
//! blocking calls; timing connects there would count those stalls.
//!
//! A probe takes the real relay connection's way: the system resolver and route, into a TUN
//! when there is one. A proxy on that way completes the handshake itself and only then connects
//! the relay, so the handshake times nothing. What is timed is the relay closing the connection
//! on an empty first frame, sent once the proxy has had `SETTLE` to connect: hbbr's `make_pair_`
//! returns on any first frame but `RequestRelay`, without a log line.

use super::{ProbeResult, CONFIRM_TTL, STATE, WAKE};
use crate::sign;
use hbb_common::{
    config::{self, Config, RELAY_PORT},
    log,
    rand::{self, Rng},
    socket_client::check_port,
    throttled_log,
};
use std::{
    io::{ErrorKind, Read, Write},
    net::{IpAddr, SocketAddr, TcpStream, ToSocketAddrs},
    sync::Once,
    thread,
    time::{Duration, Instant},
};

const TRIES: usize = 3;
const TRY_GAP: Duration = Duration::from_millis(200);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(3);
/// Long enough for a proxy that took the handshake to connect the relay over a remote node;
/// hbbr waits 30 s for the first frame.
const SETTLE: Duration = Duration::from_millis(1500);
/// A frame header for length 0: hbbr parses it as an empty `RendezvousMessage`.
const EMPTY_FRAME: [u8; 1] = [0];
/// No round trip to a public relay is this short, so whatever closed the connection was not the
/// relay: a proxy rule rejecting it, or security software cutting it on the first data.
const RELAY_MIN_RTT: Duration = Duration::from_millis(2);
const LOG_INTERVAL: Duration = Duration::from_secs(60);

pub(super) struct Attempt {
    /// From sending the empty frame to the relay's close.
    pub elapsed: Duration,
    pub remote: IpAddr,
}

pub(super) fn start() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        if let Err(e) = thread::Builder::new()
            .name("leapgate-route-probe".to_owned())
            .spawn(run)
        {
            log::error!("leapgate route: cannot start the probe thread: {}", e);
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
    let attempts = thread::scope(|s| {
        let handles: Vec<_> = relays
            .iter()
            .map(|h| {
                thread::Builder::new()
                    .spawn_scoped(s, move || probe(h))
                    .map_err(|e| {
                        throttled_log!(
                            LOG_INTERVAL,
                            warn,
                            "leapgate route: probe round dropped, cannot start a probe thread: {}",
                            e
                        )
                    })
                    .ok()
            })
            .collect();
        handles
            .into_iter()
            .zip(relays)
            .map(|(j, h)| Some((h.clone(), j?.join().ok()?)))
            .collect::<Vec<_>>()
    });
    let attempts = attempts.into_iter().collect::<Option<Vec<_>>>()?;
    summarize(rev, &attempts)
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
            try_relay(&addrs, SETTLE)
        })
        .collect()
}

/// On the first address that accepts, as upstream's `FramedStream::new` takes it. `None` unless
/// the connection stays open and silent through `settle` (hbbr neither sends nor closes before
/// the first frame; a proxy that cannot reach the relay closes it) and then closes cleanly on
/// the empty frame.
fn try_relay(addrs: &[SocketAddr], settle: Duration) -> Option<Attempt> {
    let (mut stream, remote) = addrs.iter().find_map(|addr| {
        let stream = TcpStream::connect_timeout(addr, CONNECT_TIMEOUT).ok()?;
        Some((stream, addr.ip()))
    })?;
    thread::sleep(settle);
    stream.set_nonblocking(true).ok()?;
    match stream.peek(&mut [0u8; 1]) {
        Err(e) if e.kind() == ErrorKind::WouldBlock => {}
        _ => return None,
    }
    stream.set_nonblocking(false).ok()?;
    stream.set_read_timeout(Some(CONNECT_TIMEOUT)).ok()?;
    let start = Instant::now();
    stream.write_all(&EMPTY_FRAME).ok()?;
    match stream.read(&mut [0u8; 1]) {
        Ok(0) => Some(Attempt {
            elapsed: start.elapsed(),
            remote,
        }),
        _ => None,
    }
}

/// The fastest try per relay, or `down` when every try failed. The whole round is dropped when
/// a public relay closed faster than `RELAY_MIN_RTT`.
fn summarize(rev: i64, attempts: &[(String, Vec<Option<Attempt>>)]) -> Option<ProbeResult> {
    let (mut rtt, mut down) = (Vec::new(), Vec::new());
    for (host, tries) in attempts {
        let mut best: Option<Duration> = None;
        for a in tries.iter().flatten() {
            if is_public(a.remote) && a.elapsed < RELAY_MIN_RTT {
                throttled_log!(
                    LOG_INTERVAL,
                    info,
                    "leapgate route: probe round dropped, {} closed in {}us (not the relay?)",
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

/// Fake-ip addresses count as public: `198.18.0.0/15` already does, and mihomo's IPv6 range
/// `fdfe:dcba:9876::/48` would otherwise pass as a ULA.
fn is_public(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ip) => {
            let o = ip.octets();
            !(ip.is_private()
                || ip.is_loopback()
                || ip.is_link_local()
                || (o[0] == 100 && (o[1] & 0xc0) == 64))
        }
        IpAddr::V6(ip) => {
            ip.segments()[..3] == [0xfdfe, 0xdcba, 0x9876]
                || !(ip.is_loopback() || ip.is_unique_local() || ip.is_unicast_link_local())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    fn ok(us: u64, remote: &str) -> Option<Attempt> {
        Some(Attempt {
            elapsed: Duration::from_micros(us),
            remote: ip(remote),
        })
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
        let r = summarize(7, &attempts).unwrap();
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
    fn public_relay_under_2ms_drops_round() {
        for remote in ["8.8.8.8", "198.18.0.5", "2408:8256::1", "fdfe:dcba:9876::5"] {
            let attempts = [
                host("a", vec![ok(23_000, "1.1.1.1")]),
                host("b", vec![ok(40_000, remote), ok(1_500, remote)]),
            ];
            assert_eq!(summarize(7, &attempts), None, "{remote}");
        }
        // Private, carrier-grade NAT and ULA relays may well be that close.
        for remote in ["10.0.0.2", "100.64.1.2", "fd00::2"] {
            let attempts = [host("b", vec![ok(1_000, remote)])];
            let r = summarize(7, &attempts).unwrap();
            assert_eq!(r.rtt, vec![("b".to_owned(), 1)], "{remote}");
        }
        // A public relay at 2 ms is believed.
        let attempts = [host("b", vec![ok(2_000, "8.8.8.8")])];
        assert!(summarize(7, &attempts).is_some());
    }

    #[test]
    fn fake_ip_relay_through_a_tun_is_measured() {
        let attempts = [host("b", vec![ok(5_000, "198.18.0.5")])];
        let r = summarize(7, &attempts).unwrap();
        assert_eq!(r.rtt, vec![("b".to_owned(), 5)]);
    }

    /// A loopback listener handing its one connection to `serve`.
    fn server(serve: fn(TcpStream)) -> SocketAddr {
        let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let at = l.local_addr().unwrap();
        thread::spawn(move || serve(l.accept().unwrap().0));
        at
    }

    #[test]
    fn only_a_silent_connection_closed_on_the_frame_counts() {
        let settle = Duration::from_millis(300);
        // hbbr: reads the first frame, not a RequestRelay, and returns.
        let hbbr = server(|mut s| s.read_exact(&mut [0u8; 1]).unwrap());
        assert_eq!(try_relay(&[hbbr], settle).unwrap().remote, ip("127.0.0.1"));
        // A proxy that cannot reach the relay closes before the frame.
        assert!(try_relay(&[server(drop)], settle).is_none());
        // Whatever speaks first is not hbbr.
        let chatty = server(|mut s| {
            s.write_all(b"x").unwrap();
            let _ = s.read(&mut [0u8; 1]);
        });
        assert!(try_relay(&[chatty], settle).is_none());
    }
}
