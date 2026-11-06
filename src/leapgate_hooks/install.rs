//! The UI process's end of the home page's "安装" and "升级" cards (M8, `LEAPGATE.md` §10.16):
//! upstream's installer called in this process, so a failure comes back to the card. The
//! options are in `libs/leapgate` (`install`).

use hbb_common::log;

/// Installs (`install`) or upgrades (`upgrade`) and exits on success; the failure otherwise, as
/// `leapgate::install::failure`.
///
/// Not `silent`: upstream starts the installed copy 2 s after the script (`run_after_run_cmds`),
/// and that copy hands itself over to a main window it finds, so this process exits first. The
/// script's `taskkill` leaves this process alone (`get_uninstall(false, …)`), so it is still
/// here to report a failure.
#[cfg(windows)]
pub(crate) fn install(kind: &str) -> String {
    let (options, path) = if kind == "upgrade" {
        (
            leapgate::install::upgrade_options(&crate::platform::get_install_options()),
            crate::ui_interface::install_path(),
        )
    } else {
        (leapgate::install::INSTALL_OPTIONS.to_owned(), String::new())
    };
    match crate::platform::install_me(&options, path, false, false) {
        Ok(()) => {
            log::info!("leapgate install: {kind} done, exiting");
            std::process::exit(0);
        }
        Err(e) => {
            log::warn!("leapgate install: {kind} failed: {e:#}");
            leapgate::install::failure(&format!("{e:#}"))
        }
    }
}

#[cfg(not(windows))]
pub(crate) fn install(kind: &str) -> String {
    leapgate::install::failure(&format!("{kind} is not supported on this platform"))
}
