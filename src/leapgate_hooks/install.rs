//! The UI process's end of the home page's "安装" and "升级" cards (M8, `LEAPGATE.md` §10.16):
//! upstream's installer, run so that a failure comes back to the card. The options are in
//! `libs/leapgate` (`install`).
//!
//! The installer runs in a child of this process (`--leapgate-install <kind>`), not in it: this
//! process holds the main IPC, and the `--server` that the installed service starts while the
//! script still runs finds it taken and kills the process holding it
//! (`server.rs` `stop_main_window_process`), before upstream's `run_after_run_cmds` would start
//! the installed copy and its tray. The child has no IPC and more than one argument, so that
//! kill passes it by, as it passes upstream's install page (`--install`) by.

use hbb_common::log;

/// The child's argument, followed by the kind.
#[cfg(windows)]
const CHILD_ARG: &str = "--leapgate-install";

/// Installs (`install`) or upgrades (`upgrade`) in a child and exits on success; the failure
/// otherwise, as `leapgate::install::failure`.
///
/// On success the child has started the installed copy and its tray; this process is usually gone
/// by then, killed by the script's `taskkill`.
#[cfg(windows)]
#[cfg_attr(not(feature = "flutter"), allow(dead_code))]
pub(crate) fn install(kind: &str) -> String {
    use std::io::Read;
    let child = std::env::current_exe().and_then(|exe| {
        std::process::Command::new(exe)
            .args([CHILD_ARG, kind])
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::piped())
            .spawn()
    });
    let mut child = match child {
        Ok(child) => child,
        Err(e) => return leapgate::install::failure(&format!("{e}")),
    };
    // The child writes its one line only on failure, and exits right after.
    let status = child.wait();
    if matches!(&status, Ok(s) if s.success()) {
        log::info!("leapgate install: {kind} done, exiting");
        std::process::exit(0);
    }
    let mut out = String::new();
    if let Some(mut stdout) = child.stdout.take() {
        stdout.read_to_string(&mut out).ok();
    }
    if out.trim().is_empty() {
        let text = match status {
            Ok(s) => format!("installer exited with {s}"),
            Err(e) => format!("{e}"),
        };
        log::warn!("leapgate install: {kind} failed: {text}");
        return leapgate::install::failure(&text);
    }
    out.trim().to_owned()
}

#[cfg(not(windows))]
pub(crate) fn install(kind: &str) -> String {
    leapgate::install::failure(&format!("{kind} is not supported on this platform"))
}

/// `core_main`'s hook: returns unless the arguments are the child's; the child installs, writes
/// the failure to the UI process's pipe and exits 1, or exits 0.
///
/// Not `silent`: upstream starts the installed copy and its tray (`run_after_run_cmds`). The
/// script's `taskkill` leaves the child alone (`get_uninstall(false, …)`).
#[cfg(windows)]
pub(crate) fn child(args: &[String]) {
    use std::{ffi::c_void, io::Write, os::windows::io::FromRawHandle};
    extern "system" {
        fn GetStdHandle(std_handle: u32) -> *mut c_void;
        fn SetStdHandle(std_handle: u32, handle: *mut c_void) -> i32;
        fn SetHandleInformation(handle: *mut c_void, mask: u32, flags: u32) -> i32;
    }
    const STD_OUTPUT_HANDLE: u32 = -11i32 as u32;
    const HANDLE_FLAG_INHERIT: u32 = 1;

    if args.first().map(String::as_str) != Some(CHILD_ARG) {
        return;
    }
    // The pipe leaves the standard handles before anything is started: the installed copy and its
    // tray would inherit it as their stdout, and once the UI process is gone a `println!` there
    // (e.g. the clipboard's on the last session's end) fails and aborts them.
    let pipe = unsafe {
        let pipe = GetStdHandle(STD_OUTPUT_HANDLE);
        SetHandleInformation(pipe, HANDLE_FLAG_INHERIT, 0);
        SetStdHandle(STD_OUTPUT_HANDLE, std::ptr::null_mut());
        pipe
    };
    let kind = args.get(1).map(String::as_str).unwrap_or_default();
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
            log::info!("leapgate install: {kind} done");
            std::process::exit(0);
        }
        Err(e) => {
            log::warn!("leapgate install: {kind} failed: {e:#}");
            let mut pipe = unsafe { std::fs::File::from_raw_handle(pipe) };
            writeln!(pipe, "{}", leapgate::install::failure(&format!("{e:#}"))).ok();
            std::process::exit(1);
        }
    }
}
