//! Reason codes for the new UI (C3): upstream reports connection failures as message boxes
//! carrying English text, and the UI looks its wording up by code instead of translating that
//! text. Only the reason comes from here: whether to retry automatically is the msgbox event's
//! `hasRetry`, which `Session::msgbox` computed with upstream's `check_if_retry` at the time.
//!
//! Matching is on upstream's wording, so an upstream merge that rewords a message silently drops
//! it to `Other`; compare the msgbox texts between the tags and update this table and its tests
//! (new UI plan 03 §3.8, `LEAPGATE.md` §10).

use crate::exit;
use hbb_common::log;
use serde::Serialize;
use std::{collections::BTreeSet, sync::Mutex};

/// Codes are stable: the UI's connection state and wording are keyed on them.
#[derive(Debug, PartialEq, Serialize)]
#[serde(tag = "code", rename_all = "snake_case")]
pub enum Reason {
    IdNotExist,
    PeerOffline,
    KeyMismatch,
    KeyOveruse,
    PunchFailed,
    RendezvousFailed,
    SecureTcpFailed,
    /// The direct connection was reset (10054 / 104) or timed out; upstream offers the relay.
    DirectReset,
    /// No direct connection and no relay to fall back on.
    DirectFailed,
    RelayFailed,
    /// Login answered "Offline": the ID no longer belongs to that device.
    PeerIdChanged,
    LinuxLoginScreen,
    WrongPassword,
    #[serde(rename = "wrong_2fa")]
    Wrong2fa,
    TooManyAttempts,
    Blocked,
    NotAllowed,
    MainWindowNotOpen,
    InstalledOnly,
    NoPermission {
        feature: Feature,
    },
    PrivacyModeOccupied,
    PeerTooOld {
        feature: Feature,
    },
    ResetByPeer,
    Timeout,
    ClosedByPeer,
    Inactivity,
    NoDisplays,
    ExitNotEnabled,
    /// Also shown for `PeerTooOld { feature: PortForward }` on an exit card (01 §4.3).
    ExitNotSupported,
    ExitNeedEncryption,
    LocalPortInUse {
        port: u16,
    },
    ExitBlocked,
    ExitFakeIpLiteral,
    /// Not recognized: the UI shows the original text.
    Other,
}

#[derive(Debug, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Feature {
    FileTransfer,
    Camera,
    Terminal,
    /// TCP tunnel / port forwarding ("IP tunneling" upstream).
    PortForward,
}

/// Distinct unrecognized texts logged so far. Capped: some texts come from the peer.
static LOGGED: Mutex<BTreeSet<String>> = Mutex::new(BTreeSet::new());
const MAX_LOGGED: usize = 64;

/// Classifies an upstream message box. Unrecognized texts are logged once each.
pub fn classify(msgtype: &str, title: &str, text: &str) -> Reason {
    let reason = match_reason(msgtype, title, text);
    if reason == Reason::Other {
        let text = clip(text);
        let mut logged = LOGGED.lock().unwrap();
        if logged.len() < MAX_LOGGED && logged.insert(text.to_owned()) {
            log::info!(
                "leapgate reason: unrecognized msgbox type={:?} title={:?} text={:?}",
                msgtype,
                title,
                text
            );
        }
    }
    reason
}

/// At most this many characters of an unrecognized text are kept and logged.
const MAX_LOGGED_CHARS: usize = 200;

fn clip(text: &str) -> &str {
    match text.char_indices().nth(MAX_LOGGED_CHARS) {
        Some((end, _)) => &text[..end],
        None => text,
    }
}

fn match_reason(msgtype: &str, title: &str, text: &str) -> Reason {
    use Feature::*;
    use Reason::*;
    // By type: these carry the raw error or the login error as their text or title.
    match msgtype {
        "relay-hint" | "relay-hint2" => return DirectReset,
        "re-input-password" => return WrongPassword,
        "input-2fa" if title == "Wrong 2FA Code" => return Wrong2fa,
        _ => {}
    }
    // `Client::start` appends ": Please try later" to errors starting with "Failed", and some
    // carry the underlying error after a colon.
    for (prefix, reason) in [
        ("Failed to connect via rendezvous server", RendezvousFailed),
        ("Failed to secure tcp", SecureTcpFailed),
        (
            "Failed to make direct connection to remote desktop",
            DirectFailed,
        ),
        ("Failed to connect via relay server", RelayFailed),
        ("Too many wrong attempts", TooManyAttempts),
    ] {
        if text.starts_with(prefix) {
            return reason;
        }
    }
    if let Some(port) = text
        .strip_prefix("Failed to listen on ")
        .and_then(|rest| rest.split(':').next())
        .and_then(|port| port.parse().ok())
    {
        return LocalPortInUse { port };
    }
    match text {
        "ID does not exist" => IdNotExist,
        "Remote desktop is offline" => PeerOffline,
        "Key mismatch" => KeyMismatch,
        "Key overuse" => KeyOveruse,
        "other punch hole failure" => PunchFailed,
        "Offline" => PeerIdChanged,
        "Login screen using Wayland is not supported" => LinuxLoginScreen,
        "Please try 1 minute later" => TooManyAttempts,
        "Your ip is blocked by the peer" | "Your ID is blocked by the peer" => Blocked,
        "Connection not allowed" => NotAllowed,
        "The main window is not open" => MainWindowNotOpen,
        "Supported only in the installed version." => InstalledOnly,
        "No permission of file transfer" => NoPermission {
            feature: FileTransfer,
        },
        "No permission of viewing camera" => NoPermission { feature: Camera },
        "No permission of terminal" => NoPermission { feature: Terminal },
        "No permission of IP tunneling" => NoPermission {
            feature: PortForward,
        },
        "Someone turns on privacy mode, exit" => PrivacyModeOccupied,
        "upgrade_remote_rustdesk_client_to_{1.3.9}_tip" => PeerTooOld { feature: Camera },
        "Remote terminal is not supported by the remote side. Please upgrade to version 1.4.1 or higher." => {
            PeerTooOld { feature: Terminal }
        }
        exit::PEER_TOO_OLD => PeerTooOld {
            feature: PortForward,
        },
        "Reset by the peer" => ResetByPeer,
        "Timeout" => Timeout,
        "Closed manually by the peer" => ClosedByPeer,
        "Connection failed due to inactivity" => Inactivity,
        "No displays" => NoDisplays,
        exit::MSG_NOT_ENABLED => ExitNotEnabled,
        exit::NOT_SUPPORTED => ExitNotSupported,
        exit::MSG_NEED_ENCRYPTION => ExitNeedEncryption,
        exit::MSG_BLOCKED => ExitBlocked,
        exit::MSG_FAKE_IP_LITERAL => ExitFakeIpLiteral,
        _ => Other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use Feature::*;
    use Reason::*;

    /// (type, title, text) as upstream builds them, with where. Line numbers are as of
    /// leapgate-client `5f0b5bd3f`.
    #[test]
    fn upstream_message_boxes() {
        let cases = [
            // client.rs:1015/1018/1021/1024/1026 `_start_inner`, shown by
            // client.rs:4990 `on_establish_connection_error`
            (("error", "Connection Error", "ID does not exist"), IdNotExist),
            (("error", "Connection Error", "Remote desktop is offline"), PeerOffline),
            (("error", "Connection Error", "Key mismatch"), KeyMismatch),
            (("error", "Connection Error", "Key overuse"), KeyOveruse),
            (("error", "Connection Error", "other punch hole failure"), PunchFailed),
            // client.rs:1361 `_start_inner`; client.rs:397 `start` appends the suffix
            (
                (
                    "error",
                    "Connection Error",
                    "Failed to connect via rendezvous server: Please try later",
                ),
                RendezvousFailed,
            ),
            // client.rs:894 `_start_inner`
            (
                (
                    "error",
                    "Connection Error",
                    "Failed to secure tcp: deadline has elapsed: Please try later",
                ),
                SecureTcpFailed,
            ),
            // client.rs:4988 `on_establish_connection_error` (both relay hint types)
            (
                (
                    "relay-hint",
                    "Connection Error",
                    "An existing connection was forcibly closed by the remote host. (os error 10054)",
                ),
                DirectReset,
            ),
            (
                ("relay-hint2", "Connection Error", "deadline has elapsed"),
                DirectReset,
            ),
            // client.rs:1591 `connect`
            (
                (
                    "error",
                    "Connection Error",
                    "Failed to make direct connection to remote desktop: Please try later",
                ),
                DirectFailed,
            ),
            // client.rs:1586 `connect`
            (
                (
                    "error",
                    "Connection Error",
                    "Failed to connect via relay server: Timeout: Please try later",
                ),
                RelayFailed,
            ),
            // connection.rs:3022 `on_message` (LOGIN_MSG_OFFLINE), client.rs:4562 `handle_login_error`
            (("error", "Login Error", "Offline"), PeerIdChanged),
            // client.rs:4504 LOGIN_ERROR_MAP, client.rs:4547 `handle_login_error`
            (
                (
                    "error",
                    "Login Error",
                    "Login screen using Wayland is not supported",
                ),
                LinuxLoginScreen,
            ),
            // client.rs:4534 `handle_login_error`
            (
                ("re-input-password", "Wrong Password", "Do you want to enter again?"),
                WrongPassword,
            ),
            // client.rs:4543 `handle_login_error`
            (("input-2fa", "Wrong 2FA Code", ""), Wrong2fa),
            // connection.rs:4581/4592 `check_failure_with_scope`, 4310
            // `prepare_terminal_login_for_authorization`, 4495 `check_failure_ipv6_prefix`
            (("error", "Login Error", "Too many wrong attempts"), TooManyAttempts),
            (("error", "Login Error", "Please try 1 minute later"), TooManyAttempts),
            (
                (
                    "error",
                    "Login Error",
                    "Too many wrong attempts for IPv6 prefix /64",
                ),
                TooManyAttempts,
            ),
            // connection.rs:1441 `check_whitelist`, 1473 `check_id_whitelist`
            (("error", "Login Error", "Your ip is blocked by the peer"), Blocked),
            (("error", "Login Error", "Your ID is blocked by the peer"), Blocked),
            // connection.rs:2842 `check_login_scope`, 3193 `on_message`; as a close reason
            // connection.rs:5860 `handle_authorized_scope_violation`, shown by io_loop.rs:2153
            // `handle_msg_from_peer`
            (("error", "Login Error", "Connection not allowed"), NotAllowed),
            (("error", "Connection Error", "Connection not allowed"), NotAllowed),
            // connection.rs:1518 `on_open`
            (("error", "Login Error", "The main window is not open"), MainWindowNotOpen),
            // connection.rs:2965 `on_message`
            (
                ("error", "Login Error", "Supported only in the installed version."),
                InstalledOnly,
            ),
            // connection.rs:2941/2950/2959/2989 `on_message`
            (
                ("error", "Login Error", "No permission of file transfer"),
                NoPermission {
                    feature: FileTransfer,
                },
            ),
            (
                ("error", "Login Error", "No permission of viewing camera"),
                NoPermission { feature: Camera },
            ),
            (
                ("error", "Login Error", "No permission of terminal"),
                NoPermission { feature: Terminal },
            ),
            (
                ("error", "Login Error", "No permission of IP tunneling"),
                NoPermission {
                    feature: PortForward,
                },
            ),
            // server/port_forward_mux.rs:119 `on_open`, shown by port_forward_mux.rs:725
            // `tunnel_loop` through client.rs:4906 `on_error`
            (
                ("error", "Error", "No permission of IP tunneling"),
                NoPermission {
                    feature: PortForward,
                },
            ),
            // connection.rs:1415 `check_privacy_mode_on`; io_loop.rs:2523
            // `handle_back_msg_privacy_mode`
            (
                ("error", "Login Error", "Someone turns on privacy mode, exit"),
                PrivacyModeOccupied,
            ),
            (
                ("error", "Connecting...", "Someone turns on privacy mode, exit"),
                PrivacyModeOccupied,
            ),
            // io_loop.rs:1506 `check_view_camera_support`
            (
                (
                    "error",
                    "Download new version",
                    "upgrade_remote_rustdesk_client_to_{1.3.9}_tip",
                ),
                PeerTooOld { feature: Camera },
            ),
            // io_loop.rs:1523 `check_terminal_support`
            (
                (
                    "error",
                    "Remote terminal not supported",
                    "Remote terminal is not supported by the remote side. Please upgrade to version 1.4.1 or higher.",
                ),
                PeerTooOld { feature: Terminal },
            ),
            // port_forward.rs:384 `establish_tunnel`
            (
                ("error", "Error", exit::PEER_TOO_OLD),
                PeerTooOld {
                    feature: PortForward,
                },
            ),
            // io_loop.rs:300 `io_loop`; client.rs:1800 `secure_connection`
            (("error", "Connection Error", "Reset by the peer"), ResetByPeer),
            // io_loop.rs:318/366 `io_loop`; client.rs:1866 `request_relay`
            (("error", "Connection Error", "Timeout"), Timeout),
            // connection.rs:5360 `send_close_reason_no_retry`, shown by io_loop.rs:2153
            (
                ("error", "Connection Error", "Closed manually by the peer"),
                ClosedByPeer,
            ),
            // connection.rs:1173 `start`, shown by io_loop.rs:2153
            (
                ("error", "Connection Error", "Connection failed due to inactivity"),
                Inactivity,
            ),
            // ui_session_interface.rs:1847 `handle_peer_info`
            (("error", "Error", "No displays"), NoDisplays),
            // connection.rs:2982 `on_message` (exit::login_refusal)
            (("error", "Login Error", exit::MSG_NOT_ENABLED), ExitNotEnabled),
            (
                ("error", "Login Error", exit::MSG_NEED_ENCRYPTION),
                ExitNeedEncryption,
            ),
            // server/port_forward_mux.rs:114 `on_open`, shown by port_forward_mux.rs:725
            (("error", "Error", exit::MSG_NOT_ENABLED), ExitNotEnabled),
            // leapgate_hooks/exit.rs:172 `serve`
            (("error", "Error", exit::NOT_SUPPORTED), ExitNotSupported),
            // server/port_forward_mux.rs:250 (exit::dial::failure_message), shown by
            // port_forward_mux.rs:725
            (("error", "Error", exit::MSG_BLOCKED), ExitBlocked),
            (("error", "Error", exit::MSG_FAKE_IP_LITERAL), ExitFakeIpLiteral),
            // leapgate_hooks/exit.rs:57 `run`; ui_session_interface.rs:2106 `start_one_port_forward`
            (
                (
                    "error",
                    "Error",
                    "Failed to listen on 1080: Only one usage of each socket address (protocol/network address/port) is normally permitted. (os error 10048)",
                ),
                LocalPortInUse { port: 1080 },
            ),
        ];
        for ((msgtype, title, text), expected) in cases {
            assert_eq!(classify(msgtype, title, text), expected, "{text}");
        }
    }

    #[test]
    fn unrecognized_text_is_other() {
        for (msgtype, title, text) in [
            // client.rs:1011 `_start_inner`: the server's own refusal text
            (
                "error",
                "Connection Error",
                "Your account is not allowed here",
            ),
            // io_loop.rs:1513 `check_view_camera_support`
            ("error", "Error", "view_camera_unsupported_tip"),
            // ui_session_interface.rs:1847 `handle_peer_info`
            ("error", "Error", "No cameras"),
            // a port that does not parse
            ("error", "Error", "Failed to listen on 70000: invalid port"),
            // MSG_NEED_MUX never reaches a Leapgate controller (01 §4.3)
            ("error", "Login Error", exit::MSG_NEED_MUX),
        ] {
            assert_eq!(classify(msgtype, title, text), Other, "{text}");
        }
    }

    #[test]
    fn unrecognized_text_is_clipped_on_a_char_boundary() {
        // Some texts come from the peer: keep and log at most MAX_LOGGED_CHARS of them.
        let long = "错".repeat(MAX_LOGGED_CHARS + 5);
        assert_eq!(clip(&long), "错".repeat(MAX_LOGGED_CHARS));
        assert_eq!(clip("short"), "short");
    }

    #[test]
    fn input_2fa_asked_for_the_first_time_is_no_error() {
        // client.rs:4543 `handle_login_error` with REQUIRE_2FA
        assert_eq!(classify("input-2fa", "2FA Required", ""), Other);
    }

    #[test]
    fn json_shape() {
        let json = |r: &Reason| hbb_common::serde_json::to_string(r).unwrap();
        assert_eq!(json(&Timeout), r#"{"code":"timeout"}"#);
        assert_eq!(json(&Wrong2fa), r#"{"code":"wrong_2fa"}"#);
        assert_eq!(
            json(&NoPermission {
                feature: FileTransfer
            }),
            r#"{"code":"no_permission","feature":"file_transfer"}"#
        );
        assert_eq!(
            json(&LocalPortInUse { port: 1080 }),
            r#"{"code":"local_port_in_use","port":1080}"#
        );
    }
}
