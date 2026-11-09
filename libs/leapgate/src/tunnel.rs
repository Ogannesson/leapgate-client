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
    /// Close the listener and wait for a retry; the `Stopped` state to report.
    Stop(State),
    /// Keep listening; the next local connection logs in again. The `Interrupted` state.
    Interrupt(State),
}

/// `error` is the row's last error: for `Failed` the login's error, otherwise the error message
/// box the login reported last (`(title, text)`), if any. Unlike an exit card's, a row does not
/// look at the peer's exit feature nor at an unsecured stream (the user chose to go on), and a
/// failure has no cooldown.
pub fn after_login(end: LoginEnd, error: Option<(&str, &str)>) -> Next {
    let stopped = |reason: Option<Reason>, text| State::Stopped { reason, text };
    match end {
        LoginEnd::Peer { mux: true } => Next::Use,
        LoginEnd::Peer { mux: false } => Next::Stop(stopped(
            Some(Reason::PeerTooOld {
                feature: Feature::PortForward,
            }),
            None,
        )),
        LoginEnd::Refused {
            insecure_declined: true,
        } => Next::Stop(stopped(Some(Reason::InsecureDeclined), None)),
        LoginEnd::Refused { .. } => match error.map(classified) {
            Some((reason, text)) => Next::Stop(stopped(Some(reason), text)),
            None => Next::Stop(stopped(None, None)),
        },
        LoginEnd::Failed => {
            let (reason, text) = error.map_or((Reason::Other, None), classified);
            Next::Interrupt(State::Interrupted {
                cause: Cause::LoginFailed,
                reason: Some(reason),
                text,
            })
        }
    }
}

/// The C3 reason of an error box, and its text, clipped, when the reason is `Other`.
fn classified((title, text): (&str, &str)) -> (Reason, Option<String>) {
    let reason = reason::classify("error", title, text);
    let text = (reason == Reason::Other).then(|| reason::clip(text).to_owned());
    (reason, text)
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

/// Whether a program listens on `port` for all addresses, `0.0.0.0` or `[::]` (M9-3, 14 §4.1).
/// On Windows a listener on 127.0.0.1:`port` binds alongside it and would take its local
/// connections, so the tunnels and exits count the port as taken. Asked of the system's TCP
/// listener tables, not by binding: a bind of `0.0.0.0:port` also fails while an outgoing
/// connection happens to use `port` as its source port. `false` when the tables cannot be read.
#[cfg(windows)]
pub fn listened_on_all_addresses(port: u16) -> bool {
    use windows::Win32::{
        NetworkManagement::IpHelper::{
            MIB_TCP6ROW_OWNER_PID, MIB_TCPROW_OWNER_PID, MIB_TCP_STATE_LISTEN,
        },
        Networking::WinSock::{AF_INET, AF_INET6},
    };
    let listen = MIB_TCP_STATE_LISTEN.0 as u32;
    // The port is in network byte order, in the low 16 bits.
    let local_port = |dw: u32| u16::from_be(dw as u16);
    listeners::<MIB_TCPROW_OWNER_PID>(AF_INET.0.into())
        .iter()
        .any(|r| r.dwState == listen && r.dwLocalAddr == 0 && local_port(r.dwLocalPort) == port)
        || listeners::<MIB_TCP6ROW_OWNER_PID>(AF_INET6.0.into())
            .iter()
            .any(|r| {
                r.dwState == listen && r.ucLocalAddr == [0; 16] && local_port(r.dwLocalPort) == port
            })
}

/// The rows of `GetExtendedTcpTable`'s `TCP_TABLE_OWNER_PID_LISTENER` for `family`:
/// `MIB_TCPTABLE_OWNER_PID` or `MIB_TCP6TABLE_OWNER_PID`, a count and then the rows.
#[cfg(windows)]
fn listeners<Row: Copy>(family: u32) -> Vec<Row> {
    use hbb_common::log;
    use windows::Win32::{
        Foundation::{ERROR_INSUFFICIENT_BUFFER, NO_ERROR},
        NetworkManagement::IpHelper::{GetExtendedTcpTable, TCP_TABLE_OWNER_PID_LISTENER},
    };
    // u32s, for the count's and the rows' alignment; the rows follow the count directly.
    let mut table: Vec<u32> = Vec::new();
    let mut size = 0u32;
    // The table can grow between the call that sizes it and the one that fills it.
    for _ in 0..3 {
        let ptr = (!table.is_empty()).then(|| table.as_mut_ptr().cast());
        let ret = unsafe {
            GetExtendedTcpTable(
                ptr,
                &mut size,
                false,
                family,
                TCP_TABLE_OWNER_PID_LISTENER,
                0,
            )
        };
        if ret == ERROR_INSUFFICIENT_BUFFER.0 {
            table = vec![0; (size as usize).div_ceil(4)];
            continue;
        }
        if ret != NO_ERROR.0 {
            log::warn!("leapgate: no TCP listener table ({}): {}", family, ret);
            return Vec::new();
        }
        let Some(&count) = table.first() else {
            return Vec::new();
        };
        let bytes = table.len() * 4;
        let row = std::mem::size_of::<Row>();
        let count = (count as usize).min(bytes.saturating_sub(4) / row);
        let rows = unsafe { table.as_ptr().add(1).cast::<Row>() };
        return (0..count)
            .map(|i| unsafe { std::ptr::read_unaligned(rows.add(i)) })
            .collect();
    }
    Vec::new()
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
    /// `text` (here and in `Stopped`) is the error's, clipped, for `Reason::Other` only.
    Interrupted {
        cause: Cause,
        #[serde(skip_serializing_if = "Option::is_none")]
        reason: Option<Reason>,
        #[serde(skip_serializing_if = "Option::is_none")]
        text: Option<String>,
    },
    /// The listener is closed; the row waits for a retry or to be removed.
    Stopped {
        #[serde(skip_serializing_if = "Option::is_none")]
        reason: Option<Reason>,
        #[serde(skip_serializing_if = "Option::is_none")]
        text: Option<String>,
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
        let shown = |end: LoginEnd, error: Option<(&str, &str)>| match after_login(end, error) {
            Next::Use => "in_use".to_owned(),
            Next::Stop(state) | Next::Interrupt(state) => event("1", "s", Kind::Tcp, None, &state),
        };
        let head = r#"{"id":"1","session_id":"s","kind":"tcp","#;
        let refused = LoginEnd::Refused {
            insecure_declined: false,
        };
        assert_eq!(shown(LoginEnd::Peer { mux: true }, None), "in_use");
        let cases = [
            (
                shown(LoginEnd::Peer { mux: false }, None),
                r#""state":"stopped","reason":{"code":"peer_too_old","feature":"port_forward"}}"#,
            ),
            (
                shown(
                    LoginEnd::Refused {
                        insecure_declined: true,
                    },
                    None,
                ),
                r#""state":"stopped","reason":{"code":"insecure_declined"}}"#,
            ),
            // The peer refused the login: its error box, classified as C3 does.
            (
                shown(
                    LoginEnd::Refused {
                        insecure_declined: false,
                    },
                    Some(("Login Error", "No permission of IP tunneling")),
                ),
                r#""state":"stopped","reason":{"code":"no_permission","feature":"port_forward"}}"#,
            ),
            (shown(refused, None), r#""state":"stopped"}"#),
            // Not recognized: the text goes along.
            (
                shown(
                    LoginEnd::Refused {
                        insecure_declined: false,
                    },
                    Some(("Login Error", "Your account is not allowed here")),
                ),
                r#""state":"stopped","reason":{"code":"other"},"text":"Your account is not allowed here"}"#,
            ),
            (
                shown(
                    LoginEnd::Failed,
                    Some(("Connection Error", "Remote desktop is offline")),
                ),
                r#""state":"interrupted","cause":"login_failed","reason":{"code":"peer_offline"}}"#,
            ),
            (
                shown(
                    LoginEnd::Failed,
                    Some(("Connection Error", "deadline has elapsed")),
                ),
                r#""state":"interrupted","cause":"login_failed","reason":{"code":"other"},"text":"deadline has elapsed"}"#,
            ),
        ];
        for (shown, tail) in cases {
            assert_eq!(shown, head.to_owned() + tail);
        }
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
                    text: None,
                },
                r#""state":"interrupted","cause":"tunnel_ended"}"#,
            ),
            (
                Kind::Tcp,
                Some(8080),
                State::Interrupted {
                    cause: Cause::LoginFailed,
                    reason: Some(Reason::PeerOffline),
                    text: None,
                },
                r#""state":"interrupted","cause":"login_failed","reason":{"code":"peer_offline"}}"#,
            ),
            (
                Kind::Tcp,
                Some(8080),
                State::Stopped {
                    reason: None,
                    text: None,
                },
                r#""state":"stopped"}"#,
            ),
            (
                Kind::Tcp,
                Some(8080),
                State::Stopped {
                    reason: Some(Reason::Other),
                    text: Some("refused".to_owned()),
                },
                r#""state":"stopped","reason":{"code":"other"},"text":"refused"}"#,
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
