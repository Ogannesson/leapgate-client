//! Per-session state the new UI keeps in Rust: frame delivery keyed by the UI's session ID (V1),
//! and how each peer session connected (Q3).

use hbb_common::{config::RELAY_PORT, tokio, SessionID};
use serde::Serialize;
use std::{
    cell::RefCell,
    collections::{BTreeMap, BTreeSet},
    future::Future,
    net::IpAddr,
    sync::Mutex,
};

/// Session tabs the new UI has hidden (V1). Only hidden ones are stored, so showing a tab again
/// leaves nothing behind.
static HIDDEN: Mutex<BTreeSet<SessionID>> = Mutex::new(BTreeSet::new());

/// `alive` says whether a session still exists. Upstream's `session_close` has no hook, so
/// entries of tabs closed while hidden are dropped here. It runs without `HIDDEN` held:
/// `all_hidden` is called with the session handlers' lock held, and `alive` takes that lock.
pub fn set_visible(id: SessionID, visible: bool, alive: impl Fn(&SessionID) -> bool) {
    let hidden: Vec<SessionID> = HIDDEN.lock().unwrap().iter().copied().collect();
    let closed: Vec<SessionID> = hidden
        .into_iter()
        .filter(|h| *h != id && !alive(h))
        .collect();
    let mut hidden = HIDDEN.lock().unwrap();
    for h in &closed {
        hidden.remove(h);
    }
    if visible {
        hidden.remove(&id);
    } else {
        hidden.insert(id);
    }
}

/// True when every one of a peer session's UI sessions is hidden, so its frames go nowhere.
pub fn all_hidden<'a>(ids: impl IntoIterator<Item = &'a SessionID>) -> bool {
    let hidden = HIDDEN.lock().unwrap();
    if hidden.is_empty() {
        return false;
    }
    let mut any = false;
    for id in ids {
        if !hidden.contains(id) {
            return false;
        }
        any = true;
    }
    any
}

// ---- Connection path (Q3) ----

/// How a peer session's last connection was made, for the new UI's connection details
/// (`LEAPGATE.md` §10.4). Empty while connecting or when not known: the UI then shows only
/// whether the connection is direct.
#[derive(Debug, Default, Clone, PartialEq, Serialize)]
pub struct Connection {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub transport: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub relay: Option<String>,
    /// A refusal from the server, in its own words; the error text upstream shows is unchanged.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub refused: Option<String>,
}

/// What the hooks inside upstream's `Client::_start` saw during one attempt.
#[derive(Default)]
pub struct Attempt {
    /// The server answered `is_local`, or one of a Leapgate peer's LAN candidates won.
    lan: bool,
    relays: BTreeSet<String>,
    refused: Option<String>,
}

impl Attempt {
    pub fn refused(&self) -> Option<&str> {
        self.refused.as_deref()
    }
}

tokio::task_local! {
    static ATTEMPT: RefCell<Attempt>;
}

/// Runs one connection attempt with a recorder for the `note_*` hooks, which sit deep in
/// upstream's `_start` where no session is at hand. This holds only while that call tree is
/// polled inside `f`: a hook in a spawned task notes nothing.
pub async fn record<T>(f: impl Future<Output = T>) -> (T, Attempt) {
    ATTEMPT
        .scope(RefCell::default(), async move {
            let r = f.await;
            (r, ATTEMPT.with(|a| a.take()))
        })
        .await
}

fn note(f: impl FnOnce(&mut Attempt)) {
    // Outside `record` (tests, callers that do not report a path) there is nothing to note.
    let _ = ATTEMPT.try_with(|a| f(&mut a.borrow_mut()));
}

pub fn note_lan() {
    note(|a| a.lan = true);
}

/// A relay this attempt connects through, as the server named it, without the default port.
pub fn note_relay(server: &str) {
    let default_port = format!(":{RELAY_PORT}");
    let name = server
        .strip_suffix(&default_port)
        .unwrap_or(server)
        .to_owned();
    note(|a| {
        a.relays.insert(name);
    });
}

pub fn note_refusal(reason: &str) {
    note(|a| a.refused = Some(reason.to_owned()));
}

/// The connection that won, as `classify` needs it.
pub enum Won {
    /// Upstream's direct IP or `domain:port` access.
    DirectIp,
    /// Leapgate's ICE, with the selected pair's remote address.
    Ice(IpAddr),
    /// One of upstream's paths, by the label it returns.
    Upstream {
        typ: &'static str,
        direct: bool,
        websocket: bool,
        local: IpAddr,
        /// For WebRTC: whether the selected pair is IPv6.
        webrtc_ipv6: bool,
    },
}

/// The path of a connection that was made; the first matching row of `LEAPGATE.md` §10.4 Q3
/// wins.
pub fn classify(won: Won, attempt: &Attempt) -> Connection {
    let punch = |v6: bool| if v6 { "punch_v6" } else { "punch_v4" };
    let (path, transport, relay) = match won {
        Won::DirectIp => ("direct_ip", "tcp", None),
        Won::Ice(remote) => {
            let lan = match remote {
                IpAddr::V4(ip) => ip.is_private(),
                IpAddr::V6(ip) => ip.is_unique_local(),
            };
            let path = if lan { "lan" } else { punch(remote.is_ipv6()) };
            (path, "udp", None)
        }
        Won::Upstream {
            typ,
            direct,
            websocket,
            local,
            webrtc_ipv6,
        } => {
            let transport = match typ {
                "UDP" | "IPv6" | "WebRTC" => "udp",
                _ => "tcp",
            };
            if !direct {
                // Two different relays in one attempt are not told apart; a TURN relay has no name.
                let relay = match (typ, attempt.relays.len()) {
                    ("WebRTC", _) => None,
                    (_, 1) => attempt.relays.first().cloned(),
                    _ => None,
                };
                let path = if websocket { "relay_ws" } else { "relay" };
                (path, transport, relay)
            } else {
                let path = match typ {
                    "TCP" if attempt.lan => "lan",
                    "TCP" => punch(local.to_canonical().is_ipv6()),
                    "UDP" => punch(false),
                    "IPv6" => punch(true),
                    "WebRTC" => punch(webrtc_ipv6),
                    _ => return Connection::default(),
                };
                (path, transport, None)
            }
        }
    };
    Connection {
        path: Some(path),
        transport: Some(transport),
        relay,
        refused: None,
    }
}

/// Each peer session's last connection, keyed as upstream's `flutter::sessions` keys peer
/// sessions: the peer ID and the connection type.
static CONNECTIONS: Mutex<BTreeMap<(String, i32), Connection>> = Mutex::new(BTreeMap::new());

pub fn set_connection(id: &str, conn_type: i32, connection: Option<Connection>) {
    let mut connections = CONNECTIONS.lock().unwrap();
    let key = (id.to_owned(), conn_type);
    match connection {
        Some(c) => connections.insert(key, c),
        None => connections.remove(&key),
    };
}

/// `alive` says whether a peer session still exists. Upstream's session close has no hook, so
/// entries of closed sessions are dropped here, as `set_visible` does; it runs without
/// `CONNECTIONS` held, since it takes upstream's session lock.
pub fn connection(id: &str, conn_type: i32, alive: impl Fn(&str, i32) -> bool) -> Connection {
    let keys: Vec<(String, i32)> = CONNECTIONS.lock().unwrap().keys().cloned().collect();
    let closed: Vec<(String, i32)> = keys
        .into_iter()
        .filter(|(i, t)| !(i == id && *t == conn_type) && !alive(i, *t))
        .collect();
    let mut connections = CONNECTIONS.lock().unwrap();
    for k in &closed {
        connections.remove(k);
    }
    connections
        .get(&(id.to_owned(), conn_type))
        .cloned()
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    // One test: HIDDEN is shared by the whole test binary.
    #[test]
    fn hidden_tabs_get_no_frames() {
        let (a, b, gone) = (
            SessionID::new_v4(),
            SessionID::new_v4(),
            SessionID::new_v4(),
        );
        let alive = |id: &SessionID| *id != gone;
        assert!(!all_hidden([&a]), "visible by default");
        assert!(!all_hidden([]), "no UI session at all");
        set_visible(a, false, alive);
        assert!(all_hidden([&a]));
        assert!(!all_hidden([&a, &b]), "another window still shows it");
        set_visible(b, false, alive);
        assert!(all_hidden([&a, &b]));
        set_visible(a, true, alive);
        assert!(!all_hidden([&a]));
        set_visible(gone, false, |_| true);
        set_visible(b, true, alive);
        assert!(HIDDEN.lock().unwrap().is_empty(), "closed tab dropped");
    }

    fn json(c: &Connection) -> String {
        hbb_common::serde_json::to_string(c).unwrap()
    }

    fn upstream(typ: &'static str, direct: bool, websocket: bool, local: &str) -> Won {
        Won::Upstream {
            typ,
            direct,
            websocket,
            local: local.parse().unwrap(),
            webrtc_ipv6: false,
        }
    }

    // One row per line of the table in `LEAPGATE.md` §10.4 Q3.
    #[test]
    fn connection_paths() {
        let plain = Attempt::default();
        let lan = Attempt {
            lan: true,
            ..Default::default()
        };
        let one_relay = Attempt {
            relays: ["relay-1.example.com".to_owned()].into(),
            ..Default::default()
        };
        let two_relays = Attempt {
            relays: [
                "relay-1.example.com".to_owned(),
                "relay-2.example.com".to_owned(),
            ]
            .into(),
            ..Default::default()
        };
        let ice = |ip: &str| Won::Ice(ip.parse().unwrap());
        let v4 = "192.0.2.10";
        let rows = [
            (
                Won::DirectIp,
                &lan,
                r#"{"path":"direct_ip","transport":"tcp"}"#,
            ),
            (
                ice("10.0.0.5"),
                &plain,
                r#"{"path":"lan","transport":"udp"}"#,
            ),
            (
                ice("fd00::5"),
                &plain,
                r#"{"path":"lan","transport":"udp"}"#,
            ),
            (
                ice("203.0.113.5"),
                &lan,
                r#"{"path":"punch_v4","transport":"udp"}"#,
            ),
            (
                ice("2001:db8::5"),
                &plain,
                r#"{"path":"punch_v6","transport":"udp"}"#,
            ),
            (
                upstream("Relay", false, false, v4),
                &one_relay,
                r#"{"path":"relay","transport":"tcp","relay":"relay-1.example.com"}"#,
            ),
            (
                upstream("Relay", false, true, v4),
                &one_relay,
                r#"{"path":"relay_ws","transport":"tcp","relay":"relay-1.example.com"}"#,
            ),
            (
                upstream("WebRTC", false, false, v4),
                &one_relay,
                r#"{"path":"relay","transport":"udp"}"#,
            ),
            (
                upstream("Relay", false, false, v4),
                &two_relays,
                r#"{"path":"relay","transport":"tcp"}"#,
            ),
            (
                upstream("TCP", true, false, v4),
                &lan,
                r#"{"path":"lan","transport":"tcp"}"#,
            ),
            (
                upstream("TCP", true, false, v4),
                &plain,
                r#"{"path":"punch_v4","transport":"tcp"}"#,
            ),
            (
                upstream("TCP", true, false, "::ffff:192.0.2.10"),
                &plain,
                r#"{"path":"punch_v4","transport":"tcp"}"#,
            ),
            (
                upstream("TCP", true, false, "2001:db8::10"),
                &plain,
                r#"{"path":"punch_v6","transport":"tcp"}"#,
            ),
            (
                upstream("UDP", true, false, v4),
                &lan,
                r#"{"path":"punch_v4","transport":"udp"}"#,
            ),
            (
                upstream("IPv6", true, false, v4),
                &lan,
                r#"{"path":"punch_v6","transport":"udp"}"#,
            ),
            (
                Won::Upstream {
                    typ: "WebRTC",
                    direct: true,
                    websocket: false,
                    local: v4.parse().unwrap(),
                    webrtc_ipv6: true,
                },
                &plain,
                r#"{"path":"punch_v6","transport":"udp"}"#,
            ),
            (upstream("", true, false, v4), &plain, "{}"),
        ];
        for (i, (won, attempt, want)) in rows.into_iter().enumerate() {
            assert_eq!(json(&classify(won, attempt)), want, "row {i}");
        }
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn an_attempt_keeps_what_its_hooks_noted() {
        note_refusal("noted outside an attempt");
        let relay = |attempt: &Attempt| {
            classify(upstream("Relay", false, false, "192.0.2.10"), attempt).relay
        };
        let ((), attempt) = record(async {
            note_relay("relay-1.example.com:21117");
            note_relay("relay-1.example.com");
            note_refusal("Not allowed by this server");
        })
        .await;
        assert_eq!(relay(&attempt).as_deref(), Some("relay-1.example.com"));
        assert_eq!(attempt.refused(), Some("Not allowed by this server"));
        let ((), attempt) = record(async { note_relay("relay-2.example.com:21127") }).await;
        assert_eq!(
            relay(&attempt).as_deref(),
            Some("relay-2.example.com:21127")
        );
        assert_eq!(attempt.refused(), None);
    }

    // One test: CONNECTIONS is shared by the whole test binary.
    #[test]
    fn a_connection_is_kept_until_its_session_closes() {
        let relay = Connection {
            path: Some("relay"),
            ..Default::default()
        };
        let alive = |id: &str, _: i32| id != "gone";
        assert_eq!(connection("a", 0, alive), Connection::default());
        set_connection("a", 0, Some(relay.clone()));
        set_connection("gone", 0, Some(relay.clone()));
        assert_eq!(connection("a", 0, alive), relay);
        assert_eq!(
            connection("a", 1, alive),
            Connection::default(),
            "another type"
        );
        assert_eq!(
            connection("gone", 0, |_, _| true),
            Connection::default(),
            "closed session dropped"
        );
        set_connection("a", 0, None);
        assert_eq!(
            connection("a", 0, alive),
            Connection::default(),
            "reconnecting"
        );
    }
}
