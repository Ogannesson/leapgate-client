use base::config::keys;

/// Default for a punch option the user never set, on a non-public rendezvous server, where
/// upstream defaults all of them to "N". `None` keeps upstream's "N".
///
/// IPv6 punch defaults to on: Leapgate's server relays the IPv6 address in punch signalling.
/// UDP punch stays off because the current server drops `PunchHoleSent` sent over UDP,
/// which would lose the IPv6 address as well.
pub fn self_hosted_punch_default(key: &str) -> Option<String> {
    if key == keys::OPTION_ENABLE_IPV6_PUNCH {
        return Some("Y".to_owned());
    }
    None
}

/// Keys starting with `leapgate-` are this device's own state; no server strategy writes them.
pub fn is_leapgate_local_option(key: &str) -> bool {
    key.starts_with("leapgate-")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_leapgate_prefixed_keys_are_local() {
        for key in ["leapgate-allow-exit", "leapgate-exit-allow-nets", "leapgate-api-caps"] {
            assert!(is_leapgate_local_option(key), "{key}");
        }
        for key in ["allow-exit", "enable-tunnel", "Leapgate-allow-exit", "x-leapgate-"] {
            assert!(!is_leapgate_local_option(key), "{key}");
        }
    }
}
