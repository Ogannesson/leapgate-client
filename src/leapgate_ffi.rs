//! Leapgate's FFI functions for the UI. New exports go here instead of `flutter_ffi.rs`, so
//! merging upstream never conflicts on the bridge surface. Logic stays in `libs/leapgate`;
//! functions here only forward to it.
//!
//! This file is the second flutter_rust_bridge block (`LEAPGATE.md` §10.4). Signatures may use
//! primitives, `String`, `Vec`, `uuid::Uuid` (`SessionID`) and types declared for this block, but not
//! structs or enums the first block already exposes (e.g. `EventToUI`): both blocks would implement
//! `IntoDart` for them and the crate would not compile. Append new exports by area.
#![cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]

#[path = "leapgate_bridge/bridge_generated.rs"]
mod bridge_generated;

use crate::flutter_ffi::SessionID;
use flutter_rust_bridge::SyncReturn;

// ---- Log and version ----

/// Writes a line from the UI into the log file (L1). `level`: 1 error, 2 warn, 3 info, 4 debug,
/// other values trace.
pub fn leapgate_log(level: i32, msg: String) -> SyncReturn<()> {
    leapgate::ui::log(level, &msg);
    SyncReturn(())
}

/// Leapgate's version, shown as the product version (S12).
pub fn leapgate_version() -> SyncReturn<String> {
    SyncReturn(leapgate::ui::VERSION.to_owned())
}

// ---- Session ----

/// The reason behind a session's message box (C3), as JSON: `code` and the reason's parameters
/// if it has any (`feature`, `port`; `LEAPGATE.md` §10.4). Whether to retry is the event's
/// `hasRetry`.
pub fn leapgate_msgbox_reason(msgtype: String, title: String, text: String) -> SyncReturn<String> {
    let reason = leapgate::reason::classify(&msgtype, &title, &text);
    SyncReturn(serde_json::to_string(&reason).unwrap_or_default())
}

/// V1: a hidden session tab takes no frames (still received and decoded). Showing it again, the
/// UI calls `session_refresh` for a fresh frame.
pub fn leapgate_session_set_visible(session_id: SessionID, visible: bool) -> SyncReturn<()> {
    leapgate::session::set_visible(session_id, visible, |id| {
        crate::flutter::sessions::get_session_by_session_id(id).is_some()
    });
    SyncReturn(())
}
