//! Routing level two (contract 02). The service process measures the TCP connect time to every
//! relay leapgate-server lists in the heartbeat's `routing` and reports the latest round in the
//! next heartbeat's `probes`; leapgate-server then picks relays by measurement instead of GeoIP.
//! Upstream calls in from two hooks: `relay_preference` in `get_relay_server`, so the relay
//! leapgate-server chose wins over the local `relay-server` option, and `self_id` in the punch hole
//! request, so leapgate-server knows whose measurements to use for the requesting side.

mod probe;

use crate::{report, sign};
use hbb_common::{
    config::Config,
    serde_json::{json, Map, Value},
};
use serde::Deserialize;
use std::{
    sync::{Condvar, Mutex},
    time::{Duration, Instant},
};

/// leapgate-server lists at most this many; any beyond are not probed.
const MAX_RELAYS: usize = 32;
/// leapgate-server drops a round older than this, so it is not sent.
const MAX_AGE: Duration = Duration::from_secs(900);
/// Probing pauses once no heartbeat has succeeded for this long.
const CONFIRM_TTL: Duration = Duration::from_secs(900);
const MIN_INTERVAL_SECS: u64 = 60;
const MAX_INTERVAL_SECS: u64 = 3600;

struct State {
    rev: i64,
    interval: Duration,
    relays: Vec<String>,
    /// Last successful Leapgate heartbeat.
    confirmed_at: Instant,
    result: Option<ProbeResult>,
}

#[derive(Debug, PartialEq)]
struct ProbeResult {
    rev: i64,
    /// When the round ended.
    at: Instant,
    /// Relays that answered, with the fastest of the tries in milliseconds.
    rtt: Vec<(String, u32)>,
    /// Relays that failed every try.
    down: Vec<String>,
}

#[derive(Deserialize)]
struct Routing {
    rev: i64,
    probe_interval_secs: u64,
    relays: Vec<String>,
}

type Slot = Mutex<Option<State>>;

/// Only has content in the service process, where the heartbeat runs.
static STATE: Slot = Mutex::new(None);
/// Tells the probe thread the state changed.
static WAKE: Condvar = Condvar::new();

/// Revision of the relay list in hand, sent in the heartbeat; 0 without one.
pub fn routing_rev() -> i64 {
    STATE.lock().unwrap().as_ref().map_or(0, |s| s.rev)
}

/// The latest round for the list in hand, as the heartbeat's `probes`.
pub fn probes() -> Option<Value> {
    probes_at(&STATE, Instant::now())
}

/// Called after every successful heartbeat with its `routing` field.
pub fn on_heartbeat_ok(routing: Option<&Value>) {
    // Without a key the heartbeat is not verified: a man in the middle could fill `relays` with
    // any host:port, turning this device into its port scanner, and read the results back from
    // the next heartbeat's `probes`.
    let keyed = matches!(sign::server_pk(), Ok(Some(_)));
    if apply(&STATE, keyed, routing, Instant::now()) {
        probe::start();
    }
    WAKE.notify_all();
}

/// Called when the API server changes or turns out not to be a Leapgate server.
pub fn reset() {
    *STATE.lock().unwrap() = None;
    WAKE.notify_all();
}

/// Hook in `get_relay_server`: with leapgate-server, the relay it chose (from the measurements, or
/// a relay pinned to this device) wins over the local `relay-server` option. Against an original
/// hbbs, whose choice is round robin, the local option keeps winning as upstream has it.
pub fn relay_preference(provided: &str) -> Option<String> {
    prefer(provided, report::server_is_leapgate)
}

/// This device's ID for the punch hole request. Not `Config::get_id()`, which generates and
/// saves a new ID when this process has none: the UI process would invent one that differs
/// from the service's.
pub fn self_id() -> String {
    Config::get_id_or(String::new())
}

fn prefer(provided: &str, is_leapgate: impl FnOnce() -> bool) -> Option<String> {
    (!provided.is_empty() && is_leapgate()).then(|| provided.to_owned())
}

/// Takes in a successful heartbeat. Returns whether there are relays to probe.
fn apply(slot: &Slot, keyed: bool, routing: Option<&Value>, now: Instant) -> bool {
    if !keyed {
        return false;
    }
    let routing = routing.and_then(|v| Routing::deserialize(v).ok());
    let mut g = slot.lock().unwrap();
    if let Some(mut r) = routing {
        if g.as_ref().map_or(true, |s| s.rev != r.rev) {
            r.relays.truncate(MAX_RELAYS);
            *g = Some(State {
                rev: r.rev,
                interval: Duration::from_secs(
                    r.probe_interval_secs
                        .clamp(MIN_INTERVAL_SECS, MAX_INTERVAL_SECS),
                ),
                relays: r.relays,
                confirmed_at: now,
                result: None,
            });
        }
    }
    let Some(s) = g.as_mut() else {
        return false;
    };
    s.confirmed_at = now;
    !s.relays.is_empty()
}

fn probes_at(slot: &Slot, now: Instant) -> Option<Value> {
    let g = slot.lock().unwrap();
    let s = g.as_ref()?;
    let r = s.result.as_ref().filter(|r| r.rev == s.rev)?;
    let age = now.saturating_duration_since(r.at);
    if age > MAX_AGE {
        return None;
    }
    let rtt: Map<String, Value> = r.rtt.iter().map(|(h, ms)| (h.clone(), json!(ms))).collect();
    Some(json!({
        "routing_rev": r.rev,
        "age_s": age.as_secs(),
        "rtt": rtt,
        "down": r.down,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn routing(rev: i64, interval: u64, relays: &[&str]) -> Value {
        json!({ "rev": rev, "probe_interval_secs": interval, "relays": relays })
    }

    fn result(rev: i64, at: Instant) -> ProbeResult {
        ProbeResult {
            rev,
            at,
            rtt: vec![("relay1.example.com:21117".to_owned(), 23)],
            down: vec!["relay2.example.com".to_owned()],
        }
    }

    fn with<T>(slot: &Slot, f: impl FnOnce(&mut State) -> T) -> T {
        f(slot.lock().unwrap().as_mut().unwrap())
    }

    #[test]
    fn new_rev_replaces_list_and_drops_result() {
        let slot = Slot::new(None);
        let now = Instant::now();
        assert!(apply(&slot, true, Some(&routing(7, 300, &["a", "b"])), now));
        assert_eq!(with(&slot, |s| s.rev), 7);
        with(&slot, |s| s.result = Some(result(7, now)));
        // Same rev, or no `routing` at all: the list and the result stay.
        assert!(apply(&slot, true, Some(&routing(7, 300, &["a", "b"])), now));
        assert!(apply(&slot, true, None, now));
        assert!(with(&slot, |s| s.result.is_some()));
        // A new rev swaps the list in and clears the old round.
        assert!(apply(&slot, true, Some(&routing(8, 300, &["c"])), now));
        with(&slot, |s| {
            assert_eq!((s.rev, s.relays.clone()), (8, vec!["c".to_owned()]));
            assert!(s.result.is_none());
        });
        // An empty list stops probing.
        assert!(!apply(&slot, true, Some(&routing(9, 300, &[])), now));
    }

    #[test]
    fn routing_values_are_bounded() {
        let slot = Slot::new(None);
        let now = Instant::now();
        apply(&slot, true, Some(&routing(1, 5, &[])), now);
        assert_eq!(with(&slot, |s| s.interval), Duration::from_secs(60));
        apply(&slot, true, Some(&routing(2, 99_999, &[])), now);
        assert_eq!(with(&slot, |s| s.interval), Duration::from_secs(3600));
        let many: Vec<String> = (0..40).map(|i| format!("relay{i}")).collect();
        let many: Vec<&str> = many.iter().map(String::as_str).collect();
        apply(&slot, true, Some(&routing(3, 300, &many)), now);
        with(&slot, |s| {
            assert_eq!(s.relays.len(), 32);
            assert_eq!(s.relays[31], "relay31");
        });
    }

    #[test]
    fn bad_or_unverified_routing_is_ignored() {
        let slot = Slot::new(None);
        let now = Instant::now();
        for bad in [
            json!("x"),
            json!({ "rev": 1, "relays": ["a"] }),
            json!({ "rev": 1, "probe_interval_secs": 300, "relays": [1, 2] }),
        ] {
            assert!(!apply(&slot, true, Some(&bad), now));
        }
        assert!(slot.lock().unwrap().is_none());
        // Without a key nothing is taken, and an adopted list is not refreshed either.
        assert!(!apply(&slot, false, Some(&routing(1, 300, &["a"])), now));
        assert!(slot.lock().unwrap().is_none());
        apply(&slot, true, Some(&routing(1, 300, &["a"])), now);
        let later = now + Duration::from_secs(60);
        assert!(!apply(&slot, false, None, later));
        assert_eq!(with(&slot, |s| s.confirmed_at), now);
    }

    #[test]
    fn probes_only_for_current_rev_and_recent() {
        let slot = Slot::new(None);
        let now = Instant::now();
        assert_eq!(probes_at(&slot, now), None);
        apply(&slot, true, Some(&routing(7, 300, &["a"])), now);
        assert_eq!(probes_at(&slot, now), None);

        with(&slot, |s| s.result = Some(result(7, now)));
        assert_eq!(
            probes_at(&slot, now + Duration::from_secs(42)),
            Some(json!({
                "routing_rev": 7,
                "age_s": 42,
                "rtt": { "relay1.example.com:21117": 23 },
                "down": ["relay2.example.com"],
            }))
        );
        assert!(probes_at(&slot, now + MAX_AGE).is_some());
        assert_eq!(
            probes_at(&slot, now + MAX_AGE + Duration::from_secs(1)),
            None
        );
        // A round measured against another list.
        with(&slot, |s| s.result = Some(result(6, now)));
        assert_eq!(probes_at(&slot, now), None);
    }

    #[test]
    fn leapgate_server_relay_wins_only_when_given() {
        let r = "relay1.example.com:21117";
        assert_eq!(prefer(r, || true), Some(r.to_owned()));
        assert_eq!(prefer(r, || false), None);
        assert_eq!(prefer("", || true), None);
    }
}
