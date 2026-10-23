/// Upstream's updater queries api.rustdesk.com and runs the downloaded stock RustDesk
/// installer with `--update` from the privileged service. Leapgate does not use custom.txt,
/// so that path can only install or update stock RustDesk; Leapgate has its own update plan.
pub fn official_update_disabled() -> bool {
    true
}
