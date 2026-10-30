//! Support for the new UI (`leapgate_ui/`; total repo `docs/新界面/03-实施方案.md`). The exports in
//! `src/leapgate_ffi.rs` forward here.

use hbb_common::log;

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
