//! Application exit (phase 4): the controlled side dials TCP destinations for a controller's
//! local SOCKS5 / HTTP CONNECT proxy, over a multiplexed port forward tunnel. The shared
//! interface is phase 4 contract README §2.

pub mod dial;
pub mod directory;
mod policy;
pub mod proxy;

use hbb_common::config::Config;
use std::time::Duration;

/// The login target of an exit tunnel. Port 65536 cannot be typed into the ordinary add row,
/// and a pre-1.5.0 peer that takes it as a raw pipe fails parsing the port before any DNS query.
pub const SENTINEL_HOST: &str = "leapgate-exit.invalid";
pub const SENTINEL_PORT: i32 = 65536;

/// Config, not LocalConfig: the service process does not see the UI process's LocalConfig.
pub const OPTION_ALLOW_EXIT: &str = "leapgate-allow-exit";
pub const OPTION_ALLOW_NETS: &str = "leapgate-exit-allow-nets";

pub const MSG_NOT_ENABLED: &str = "Exit node is not enabled on the remote device";
pub const MSG_NEED_MUX: &str = "The remote device only accepts multiplexed port forwarding. Update your client and turn on \"Reuse one connection for port forwarding\" in its settings";
pub const MSG_NEED_ENCRYPTION: &str = "The exit node only accepts encrypted connections";
pub const MSG_BLOCKED: &str = "The exit node blocked this destination: it is on the remote device's local network or is the device itself, or the remote network's DNS returned a fake-ip address";
pub const MSG_FAKE_IP_LITERAL: &str = "The destination is a fake-ip address from this computer's proxy software. Set the program to resolve names through the proxy (socks5h)";

/// C11. A constant rather than a bare `return true` so upstream's lines after the hook stay
/// reachable to the compiler (no unreachable_code warning, nothing modified).
pub const CONTROLLER_MUX_ONLY: bool = true;
pub const PEER_TOO_OLD: &str = "The remote device is too old for port forwarding";
/// C9: after a temporary failure, local connections are refused for this long.
pub const RETRY_COOLDOWN: Duration = Duration::from_secs(10);
pub const NOT_SUPPORTED: &str = "The remote device does not support acting as an exit node";

/// How `connect_and_login_mux` ended, as the hook maps it.
pub enum LoginEnd {
    Peer {
        mux: bool,
        exit: bool,
        secured: bool,
    },
    /// Refused, or the user closed the insecure-connection prompt; upstream has said so.
    Refused,
    /// Offline, timed out, relay failed, dropped mid-login.
    Failed,
}

/// What the exit listener does after a tunnel login (C3, C9, C10).
#[derive(Debug, PartialEq)]
pub enum Next {
    Use,
    /// Close the listener, showing the message if there is one.
    Stop(Option<&'static str>),
    /// Fail local connections for `RETRY_COOLDOWN`, then try again.
    Cooldown,
}

pub fn after_login(end: LoginEnd) -> Next {
    match end {
        LoginEnd::Peer {
            mux: true,
            exit: true,
            secured: true,
        } => Next::Use,
        LoginEnd::Peer { .. } => Next::Stop(Some(NOT_SUPPORTED)),
        LoginEnd::Refused => Next::Stop(None),
        LoginEnd::Failed => Next::Cooldown,
    }
}

/// Exact match only: another case, a trailing dot or another port is an ordinary port forward.
pub fn is_exit_target(host: &str, port: i32) -> bool {
    host == SENTINEL_HOST && port == SENTINEL_PORT
}

/// Off outside Windows: the exit needs `lan::nics()`, which only Windows implements.
pub fn allowed() -> bool {
    cfg!(windows) && Config::get_option(OPTION_ALLOW_EXIT) == "Y"
}

/// The login error for an exit login, checked before the password and approval.
pub fn login_refusal(multiplex: bool, secured: bool) -> Option<&'static str> {
    refusal(allowed(), multiplex, secured)
}

fn refusal(enabled: bool, multiplex: bool, secured: bool) -> Option<&'static str> {
    if !enabled {
        Some(MSG_NOT_ENABLED)
    } else if !multiplex {
        Some(MSG_NEED_MUX)
    } else if !secured {
        Some(MSG_NEED_ENCRYPTION)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{io::ErrorKind, net::ToSocketAddrs};

    #[test]
    fn only_the_exact_sentinel_is_an_exit_target() {
        assert!(is_exit_target("leapgate-exit.invalid", 65536));
        assert!(!is_exit_target("leapgate-exit.invalid", 1));
        assert!(!is_exit_target("Leapgate-Exit.invalid", 65536));
        assert!(!is_exit_target("leapgate-exit.invalid.", 65536));
    }

    #[test]
    fn std_rejects_the_sentinel_port_before_resolving() {
        let err = "leapgate-exit.invalid:65536".to_socket_addrs().unwrap_err();
        assert_eq!(err.kind(), ErrorKind::InvalidInput);
    }

    #[test]
    fn refusal_checks_switch_then_multiplex_then_encryption() {
        let cases = [
            (false, false, false, Some(MSG_NOT_ENABLED)),
            (false, false, true, Some(MSG_NOT_ENABLED)),
            (false, true, false, Some(MSG_NOT_ENABLED)),
            (false, true, true, Some(MSG_NOT_ENABLED)),
            (true, false, false, Some(MSG_NEED_MUX)),
            (true, false, true, Some(MSG_NEED_MUX)),
            (true, true, false, Some(MSG_NEED_ENCRYPTION)),
            (true, true, true, None),
        ];
        for (enabled, multiplex, secured, expected) in cases {
            assert_eq!(refusal(enabled, multiplex, secured), expected);
        }
    }

    #[test]
    fn a_tunnel_is_used_only_from_a_secured_multiplexed_exit() {
        let peer = |mux, exit, secured| after_login(LoginEnd::Peer { mux, exit, secured });
        assert_eq!(peer(true, true, true), Next::Use);
        for (mux, exit, secured) in [
            (false, true, true),
            (true, false, true),
            (true, true, false),
        ] {
            assert_eq!(peer(mux, exit, secured), Next::Stop(Some(NOT_SUPPORTED)));
        }
        assert_eq!(after_login(LoginEnd::Refused), Next::Stop(None));
        assert_eq!(after_login(LoginEnd::Failed), Next::Cooldown);
    }
}
