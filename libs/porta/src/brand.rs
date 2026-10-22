/// Replaces the `https://admin.rustdesk.com` fallback of `get_api_server_`, reached when
/// neither `api-server` nor a custom rendezvous server is configured.
/// Empty when the build did not set `PORTA_API_SERVER`, which disables the API client.
pub fn default_api_server() -> String {
    hbb_common::config::PORTA_API_SERVER.to_owned()
}

/// Upstream treats "no custom rendezvous server" as using RustDesk's public server, which
/// shows a tip linking to rustdesk.com/pricing, caps custom image quality and turns on
/// register backoff. A Porta build never uses RustDesk's public server.
pub fn never_public_server() -> bool {
    true
}
