//! The new UI's tunnel cards (M9c, `LEAPGATE.md` §10.18): a TCP tunnel card with a row per port
//! forward, or an RDP card with one row. The controller's card loop (`src/leapgate_hooks/tunnel.rs`)
//! reports each row's state to the UI, one JSON event per change.

use crate::{
    exit::card::{Cause, Transport},
    reason::{self, Feature, Reason},
};
use hbb_common::serde_json;
use serde::Serialize;

/// How a row's `connect_and_login_mux` ended.
pub enum LoginEnd {
    Peer {
        mux: bool,
    },
    /// The login ended without a stream; `insecure_declined` when the row's insecure-connection
    /// prompt was answered "断开".
    Refused {
        insecure_declined: bool,
    },
    Failed,
}

pub enum Next {
    Use,
    /// Close the listener and wait for a retry.
    Stop(Option<Reason>),
    /// Keep listening; the next local connection logs in again.
    Interrupt(Reason),
}

/// `error` is the row's last error: for `Failed` the login's error, otherwise the error message
/// box the login reported last (`(title, text)`), if any. Unlike an exit card's, a row does not
/// look at the peer's exit feature nor at an unsecured stream (the user chose to go on), and a
/// failure has no cooldown.
pub fn after_login(end: LoginEnd, error: Option<(&str, &str)>) -> Next {
    let classify = |(title, text): (&str, &str)| reason::classify("error", title, text);
    match end {
        LoginEnd::Peer { mux: true } => Next::Use,
        LoginEnd::Peer { mux: false } => Next::Stop(Some(Reason::PeerTooOld {
            feature: Feature::PortForward,
        })),
        LoginEnd::Refused {
            insecure_declined: true,
        } => Next::Stop(Some(Reason::InsecureDeclined)),
        LoginEnd::Refused { .. } => Next::Stop(error.map(classify)),
        LoginEnd::Failed => Next::Interrupt(error.map_or(Reason::Other, classify)),
    }
}

/// A channel the peer refused while the tunnel is up, from the peer's text.
pub fn notice(text: &str) -> State {
    let reason = match text {
        "No permission of IP tunneling" => Reason::NoPermission {
            feature: Feature::PortForward,
        },
        "Too many port forward channels" => Reason::TunnelTooManyChannels,
        _ => match reason::unreachable_target(text) {
            Some(target) => Reason::TunnelUnreachable {
                target: target.to_owned(),
            },
            None => Reason::Other,
        },
    };
    let text = (reason == Reason::Other).then(|| reason::clip(text).to_owned());
    State::Notice { reason, text }
}

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

    #[test]
    fn a_login_ends_as_the_row_shows_it() {
        let reason = |next: Next| match next {
            Next::Use => panic!("in use"),
            Next::Stop(reason) => (true, reason),
            Next::Interrupt(reason) => (false, Some(reason)),
        };
        assert!(matches!(
            after_login(LoginEnd::Peer { mux: true }, None),
            Next::Use
        ));
        assert_eq!(
            reason(after_login(LoginEnd::Peer { mux: false }, None)),
            (
                true,
                Some(Reason::PeerTooOld {
                    feature: Feature::PortForward
                })
            )
        );
        assert_eq!(
            reason(after_login(
                LoginEnd::Refused {
                    insecure_declined: true
                },
                None
            )),
            (true, Some(Reason::InsecureDeclined))
        );
        // The peer refused the login: its error box, classified as C3 does.
        assert_eq!(
            reason(after_login(
                LoginEnd::Refused {
                    insecure_declined: false
                },
                Some(("Login Error", "No permission of IP tunneling"))
            )),
            (
                true,
                Some(Reason::NoPermission {
                    feature: Feature::PortForward
                })
            )
        );
        assert_eq!(
            reason(after_login(
                LoginEnd::Refused {
                    insecure_declined: false
                },
                None
            )),
            (true, None)
        );
        assert_eq!(
            reason(after_login(
                LoginEnd::Failed,
                Some(("Connection Error", "Remote desktop is offline"))
            )),
            (false, Some(Reason::PeerOffline))
        );
    }

    #[test]
    fn refused_channels_are_notices() {
        let notice_of = |text: &str| match notice(text) {
            State::Notice { reason, text } => (reason, text),
            other => panic!("{other:?}"),
        };
        assert_eq!(
            notice_of(
                "Failed to access remote 192.0.2.10:8080. Please make sure it is reachable/open."
            ),
            (
                Reason::TunnelUnreachable {
                    target: "192.0.2.10:8080".to_owned()
                },
                None
            )
        );
        assert_eq!(
            notice_of("Too many port forward channels"),
            (Reason::TunnelTooManyChannels, None)
        );
        assert_eq!(
            notice_of("No permission of IP tunneling"),
            (
                Reason::NoPermission {
                    feature: Feature::PortForward
                },
                None
            )
        );
        assert_eq!(
            notice_of("Port forward target not authorized"),
            (
                Reason::Other,
                Some("Port forward target not authorized".to_owned())
            )
        );
    }

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
            (
                Kind::Tcp,
                Some(8080),
                State::Connecting,
                r#""state":"connecting"}"#,
            ),
            (
                Kind::Rdp,
                Some(0),
                State::InUse {
                    transport: Transport::Relay,
                },
                r#""state":"in_use","transport":"relay"}"#,
            ),
            (
                Kind::Tcp,
                Some(8080),
                State::Interrupted {
                    cause: Cause::TunnelEnded,
                    reason: None,
                },
                r#""state":"interrupted","cause":"tunnel_ended"}"#,
            ),
            (
                Kind::Tcp,
                Some(8080),
                State::Interrupted {
                    cause: Cause::LoginFailed,
                    reason: Some(Reason::PeerOffline),
                },
                r#""state":"interrupted","cause":"login_failed","reason":{"code":"peer_offline"}}"#,
            ),
            (
                Kind::Tcp,
                Some(8080),
                State::Stopped { reason: None },
                r#""state":"stopped"}"#,
            ),
            (
                Kind::Tcp,
                Some(8080),
                State::Stopped {
                    reason: Some(Reason::PeerTooOld {
                        feature: Feature::PortForward,
                    }),
                },
                r#""state":"stopped","reason":{"code":"peer_too_old","feature":"port_forward"}}"#,
            ),
            (
                Kind::Tcp,
                Some(8080),
                State::PortInUse,
                r#""state":"port_in_use"}"#,
            ),
            (
                Kind::Tcp,
                Some(8080),
                State::Notice {
                    reason: Reason::NoPermission {
                        feature: Feature::PortForward,
                    },
                    text: None,
                },
                r#""state":"notice","reason":{"code":"no_permission","feature":"port_forward"}}"#,
            ),
            (
                Kind::Tcp,
                Some(8080),
                State::Notice {
                    reason: Reason::Other,
                    text: Some("refused".to_owned()),
                },
                r#""state":"notice","reason":{"code":"other"},"text":"refused"}"#,
            ),
            (
                Kind::Tcp,
                Some(8080),
                State::Removed,
                r#""state":"removed"}"#,
            ),
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
