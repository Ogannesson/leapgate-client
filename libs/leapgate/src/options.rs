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
