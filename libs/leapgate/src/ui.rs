//! Support for the new UI (`leapgate_ui/`; total repo `docs/新界面/03-实施方案.md`). The exports in
//! `src/leapgate_ffi.rs` forward here.

use hbb_common::{log, serde_json};

/// Version of the Leapgate extensions. The new UI shows it as the product version (R2-Q32) and the
/// build writes it into the Windows version resource (`--build-name`).
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Set by the new UI's runner before it calls into the core, so code shared with the upstream UI can
/// tell which UI's process it runs in (W1).
pub const UI_ENV: &str = "LEAPGATE_UI";
pub const UI_ENV_NEXT: &str = "next";

/// Window class of the new UI's main window; its runner registers it (`leapgate_ui/app/windows/runner`).
/// The connection manager's window has a class of its own, so looking up this one never finds it.
pub const MAIN_WINDOW_CLASS: &str = "LEAPGATE_UI_MAIN";

/// Whether this process runs the new UI.
pub fn is_next_ui() -> bool {
    std::env::var_os(UI_ENV).is_some_and(|v| v == UI_ENV_NEXT)
}

/// Writes a line from the UI into the log file. `level`: 1 error, 2 warn, 3 info, 4 debug, other values
/// trace. The UI collapses repeated identical errors before calling this, so it does not throttle.
pub fn log(level: i32, msg: &str) {
    let level = match level {
        1 => log::Level::Error,
        2 => log::Level::Warn,
        3 => log::Level::Info,
        4 => log::Level::Debug,
        _ => log::Level::Trace,
    };
    log::log!(target: "leapgate_ui", level, "{msg}");
}

/// The name the peer is shown for this device at login, computed as upstream's login does
/// (`src/client.rs`, `display_name` in `LoginConfigHandler`): the built-in option, else the
/// signed-in user's `display_name` or `name` from `user_info`, else the OS user name; every word
/// capitalized. Repeated here rather than split out of upstream's login code, so an upstream merge
/// that changes it has to be compared by hand (`LEAPGATE.md` §10.4).
pub fn display_name(builtin: &str, user_info: &str, username: impl FnOnce() -> String) -> String {
    let mut display_name = builtin.to_owned();
    if display_name.is_empty() {
        display_name = serde_json::from_str::<serde_json::Value>(user_info)
            .map(|x| {
                x.get("display_name")
                    .and_then(|x| x.as_str())
                    .map(|x| x.trim())
                    .filter(|x| !x.is_empty())
                    .or_else(|| x.get("name").and_then(|x| x.as_str()))
                    .map(|x| x.to_owned())
                    .unwrap_or_default()
            })
            .unwrap_or_default();
    }
    if display_name.is_empty() {
        display_name = username();
    }
    display_name
        .split_whitespace()
        .map(|word| {
            word.chars()
                .enumerate()
                .map(|(i, c)| {
                    if i == 0 {
                        c.to_uppercase().to_string()
                    } else {
                        c.to_string()
                    }
                })
                .collect::<String>()
        })
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    // Expected values follow upstream's algorithm by hand.
    #[test]
    fn display_name_as_upstream_computes_it() {
        let user = || "os  user".to_owned();
        let info = r#"{"display_name":"dee x","name":"dee"}"#;
        assert_eq!(
            display_name("help desk", info, user),
            "Help Desk",
            "built-in first"
        );
        assert_eq!(
            display_name("", r#"{"name":"alice smith"}"#, user),
            "Alice Smith"
        );
        assert_eq!(display_name("", info, user), "Dee X");
        assert_eq!(
            display_name("", r#"{"display_name":"  ","name":"bob"}"#, user),
            "Bob",
            "blank display_name"
        );
        assert_eq!(display_name("", "", user), "Os User", "signed out");
        assert_eq!(display_name("", r#"{"name":""}"#, user), "Os User");
    }
}
