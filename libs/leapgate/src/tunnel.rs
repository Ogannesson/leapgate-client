//! The new UI's tunnel cards (M9c, `LEAPGATE.md` §10.18): a TCP tunnel card with a row per port
//! forward, or an RDP card with one row. The controller's card loop (`src/leapgate_hooks/tunnel.rs`)
//! reports each row's state to the UI, one JSON event per change.

use crate::{
    exit::card::{Cause, Transport},
    reason::Reason,
};
use hbb_common::serde_json;
use serde::Serialize;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    Tcp,
    Rdp,
}

#[derive(Debug, PartialEq, Serialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum State {
    /// A row's first login, a retry or a lazy reconnect. What the login asks for is on the
    /// session's events.
    Connecting,
    /// The row's own connection: the rows of a card log in each on their own connection.
    InUse { transport: Transport },
    /// The listener stays open; the next local connection logs in again, with no cooldown.
    Interrupted {
        cause: Cause,
        #[serde(skip_serializing_if = "Option::is_none")]
        reason: Option<Reason>,
    },
    /// The listener is closed; the row waits for a retry or to be removed.
    Stopped {
        #[serde(skip_serializing_if = "Option::is_none")]
        reason: Option<Reason>,
    },
    /// The row's local port is taken by another program.
    PortInUse,
    /// The peer refused to open a channel; the row's state is unchanged. `text` is the peer's,
    /// clipped, for `Reason::Other` only.
    Notice {
        reason: Reason,
        #[serde(skip_serializing_if = "Option::is_none")]
        text: Option<String>,
    },
    /// The row is gone and its listener closed.
    Removed,
    /// The card's loop ended, all rows done. A card event: no `port`.
    Closed,
}

/// `{"id":…,"session_id":…,"kind":…,"port":…,"state":…}` plus the state's fields; `port` (the
/// local port, 0 for RDP) only for a row's event.
pub fn event(id: &str, session_id: &str, kind: Kind, port: Option<i32>, state: &State) -> String {
    #[derive(Serialize)]
    struct Event<'a> {
        id: &'a str,
        session_id: &'a str,
        kind: Kind,
        #[serde(skip_serializing_if = "Option::is_none")]
        port: Option<i32>,
        #[serde(flatten)]
        state: &'a State,
    }
    serde_json::to_string(&Event {
        id,
        session_id,
        kind,
        port,
        state,
    })
    .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::reason::Feature;

    #[test]
    fn events_read_as_documented() {
        let session = "6f1c0f5e-7d2a-4c1b-9e3f-2a5b8c9d0e1f";
        let row = |kind: &str, port: i32| {
            format!(
                r#"{{"id":"123456789","session_id":"{}","kind":"{}","port":{},"#,
                session, kind, port
            )
        };
        let cases = [
            (Kind::Tcp, Some(8080), State::Connecting, r#""state":"connecting"}"#),
            (
                Kind::Rdp,
                Some(0),
                State::InUse { transport: Transport::Relay },
                r#""state":"in_use","transport":"relay"}"#,
            ),
            (
                Kind::Tcp,
                Some(8080),
                State::Interrupted { cause: Cause::TunnelEnded, reason: None },
                r#""state":"interrupted","cause":"tunnel_ended"}"#,
            ),
            (
                Kind::Tcp,
                Some(8080),
                State::Interrupted { cause: Cause::LoginFailed, reason: Some(Reason::PeerOffline) },
                r#""state":"interrupted","cause":"login_failed","reason":{"code":"peer_offline"}}"#,
            ),
            (Kind::Tcp, Some(8080), State::Stopped { reason: None }, r#""state":"stopped"}"#),
            (
                Kind::Tcp,
                Some(8080),
                State::Stopped {
                    reason: Some(Reason::PeerTooOld { feature: Feature::PortForward }),
                },
                r#""state":"stopped","reason":{"code":"peer_too_old","feature":"port_forward"}}"#,
            ),
            (Kind::Tcp, Some(8080), State::PortInUse, r#""state":"port_in_use"}"#),
            (
                Kind::Tcp,
                Some(8080),
                State::Notice {
                    reason: Reason::NoPermission { feature: Feature::PortForward },
                    text: None,
                },
                r#""state":"notice","reason":{"code":"no_permission","feature":"port_forward"}}"#,
            ),
            (
                Kind::Tcp,
                Some(8080),
                State::Notice { reason: Reason::Other, text: Some("refused".to_owned()) },
                r#""state":"notice","reason":{"code":"other"},"text":"refused"}"#,
            ),
            (Kind::Tcp, Some(8080), State::Removed, r#""state":"removed"}"#),
        ];
        for (kind, port, state, tail) in cases {
            let kind_name = if kind == Kind::Tcp { "tcp" } else { "rdp" };
            assert_eq!(
                event("123456789", session, kind, port, &state),
                row(kind_name, port.unwrap()) + tail
            );
        }
        // A card event has no port.
        assert_eq!(
            event("123456789", session, Kind::Rdp, None, &State::Closed),
            format!(
                r#"{{"id":"123456789","session_id":"{}","kind":"rdp","state":"closed"}}"#,
                session
            )
        );
    }
}
