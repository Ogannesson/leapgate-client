use hbb_common::config::{PORTA_API_SERVER, RENDEZVOUS_PORT, RENDEZVOUS_SERVERS};

/// Privacy mode copies the system RuntimeBroker.exe under this name and installers kill it
/// by name, so it must differ from stock RustDesk's `RuntimeBroker_rustdesk.exe` or the two
/// would kill each other's process when installed side by side.
/// libs/portable/src/main.rs repeats this name (it does not depend on this crate).
pub const PRIVACY_BROKER_EXE: &str = "RuntimeBroker_porta.exe";

/// Replaces the `https://admin.rustdesk.com` fallback of `get_api_server_`, reached when
/// neither `api-server` nor a custom rendezvous server is configured.
/// Uses `PORTA_API_SERVER`; without it, derives the address from the built-in rendezvous
/// server the same way upstream derives it from a custom one. Empty when the build set
/// neither, which disables the API client.
pub fn default_api_server() -> String {
    if !PORTA_API_SERVER.is_empty() {
        return PORTA_API_SERVER.to_owned();
    }
    let s0 = RENDEZVOUS_SERVERS[0];
    if s0.is_empty() {
        return "".to_owned();
    }
    // Same rule as the custom-server branch of `get_api_server_` in src/common.rs.
    let s = hbb_common::socket_client::increase_port(s0, -2);
    if s == s0 {
        let s = if hbb_common::is_ipv6_str(&s) && !s.starts_with('[') {
            format!("[{s}]")
        } else {
            s
        };
        format!("http://{}:{}", s, RENDEZVOUS_PORT - 2)
    } else {
        format!("http://{}", s)
    }
}

/// Upstream treats "no custom rendezvous server" as using RustDesk's public server, which
/// shows a tip linking to rustdesk.com/pricing, caps custom image quality and turns on
/// register backoff. A Porta build never uses RustDesk's public server.
pub fn never_public_server() -> bool {
    true
}
