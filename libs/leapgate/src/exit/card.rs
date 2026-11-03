//! The new UI's exit card (`LEAPGATE.md` §10.12): the states the controller's card loop reports
//! to the UI, one JSON event per change.

use super::NOT_SUPPORTED;
use crate::reason::Reason;
use hbb_common::serde_json;
use serde::Serialize;

#[derive(Debug, PartialEq, Serialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum State {
    /// The first login or a lazy reconnect. What the login asks for is on the session's events.
    Connecting,
    InUse {
        transport: Transport,
    },
    Interrupted {
        cause: Cause,
        /// The cooldown left after a failed login (C9).
        #[serde(skip_serializing_if = "Option::is_none")]
        retry_after_ms: Option<u64>,
    },
    /// The listener is closed; the card waits for a retry or to be closed.
    Stopped {
        #[serde(skip_serializing_if = "Option::is_none")]
        reason: Option<Reason>,
    },
    /// The event's `port` is taken by another program.
    PortInUse,
    Closed,
}

#[derive(Debug, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Transport {
    Direct,
    Relay,
}

#[derive(Debug, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Cause {
    TunnelEnded,
    LoginFailed,
}

/// `{"id":…,"session_id":…,"port":…,"state":…}` plus the state's fields. The session ID tells a
/// card from an earlier one for the same device that is still closing.
pub fn event(id: &str, session_id: &str, port: i32, state: &State) -> String {
    #[derive(Serialize)]
    struct Event<'a> {
        id: &'a str,
        session_id: &'a str,
        port: i32,
        #[serde(flatten)]
        state: &'a State,
    }
    serde_json::to_string(&Event {
        id,
        session_id,
        port,
        state,
    })
    .unwrap_or_default()
}

/// The stopped state after `Next::Stop(msg)`. A refusal by the peer carries no reason here: the
/// login error is on the session's events. `insecure_refused` is the card turning down the
/// insecure-connection prompt, which upstream ends as a refusal without a message.
pub fn stopped(msg: Option<&str>, insecure_refused: bool) -> State {
    let reason = match msg {
        Some(NOT_SUPPORTED) => Some(Reason::ExitNotSupported),
        Some(_) => None,
        None if insecure_refused => Some(Reason::ExitNeedEncryption),
        None => None,
    };
    State::Stopped { reason }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn events_read_as_documented() {
        let session = "6f1c0f5e-7d2a-4c1b-9e3f-2a5b8c9d0e1f";
        let head = format!(r#"{{"id":"123456789","session_id":"{}","port":21180,"#, session);
        let cases = [
            (State::Connecting, r#""state":"connecting"}"#),
            (
                State::InUse { transport: Transport::Direct },
                r#""state":"in_use","transport":"direct"}"#,
            ),
            (
                State::InUse { transport: Transport::Relay },
                r#""state":"in_use","transport":"relay"}"#,
            ),
            (
                State::Interrupted { cause: Cause::TunnelEnded, retry_after_ms: None },
                r#""state":"interrupted","cause":"tunnel_ended"}"#,
            ),
            (
                State::Interrupted { cause: Cause::LoginFailed, retry_after_ms: Some(10000) },
                r#""state":"interrupted","cause":"login_failed","retry_after_ms":10000}"#,
            ),
            (State::Stopped { reason: None }, r#""state":"stopped"}"#),
            (
                State::Stopped { reason: Some(Reason::ExitNotSupported) },
                r#""state":"stopped","reason":{"code":"exit_not_supported"}}"#,
            ),
            (State::PortInUse, r#""state":"port_in_use"}"#),
            (State::Closed, r#""state":"closed"}"#),
        ];
        for (state, tail) in cases {
            assert_eq!(event("123456789", session, 21180, &state), head.clone() + tail);
        }
    }

    #[test]
    fn stopped_carries_the_reasons_rust_knows() {
        assert_eq!(
            stopped(Some(NOT_SUPPORTED), false),
            State::Stopped { reason: Some(Reason::ExitNotSupported) }
        );
        assert_eq!(
            stopped(None, true),
            State::Stopped { reason: Some(Reason::ExitNeedEncryption) }
        );
        assert_eq!(stopped(None, false), State::Stopped { reason: None });
    }
}
