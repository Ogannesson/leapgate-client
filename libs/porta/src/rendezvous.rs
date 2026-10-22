use hbb_common::{config::Config, log, tokio};
use std::time::Duration;

// Settings changes reach the service process's `Config` over IPC, so polling it picks up a
// newly entered server without a restart.
const POLL_INTERVAL: Duration = Duration::from_secs(1);

/// A Porta build may ship without a default server (`PORTA_RENDEZVOUS_SERVER` unset), and
/// then the server list is `[""]`. Upstream never has an empty list, so it would keep
/// connecting to `:21116` on its own address and log an error every few seconds.
fn server_configured() -> bool {
    Config::get_rendezvous_servers()
        .iter()
        .any(|s| !s.trim().is_empty())
}

/// Hook at the top of the rendezvous mediator loop: returns at once when a server is
/// configured, otherwise waits quietly until the user sets one.
pub async fn wait_for_server() {
    if server_configured() {
        return;
    }
    log::info!("No rendezvous server configured, waiting for one to be set");
    while !server_configured() {
        tokio::time::sleep(POLL_INTERVAL).await;
    }
    log::info!("Rendezvous server configured");
}

/// Same as `wait_for_server`, for the NAT test thread.
pub fn wait_for_server_blocking() {
    if server_configured() {
        return;
    }
    log::info!("No rendezvous server configured, NAT test waits for one to be set");
    while !server_configured() {
        std::thread::sleep(POLL_INTERVAL);
    }
}
