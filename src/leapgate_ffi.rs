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

/// The reason behind one of the session's message boxes (C3), as JSON: `code`, `retry`, and the
/// reason's parameters if it has any (`feature`, `port`; `LEAPGATE.md` §10.4). `retry` is
/// upstream's `check_if_retry`, given the session's state the way `Session::msgbox` gives it.
pub fn leapgate_msgbox_reason(
    session_id: SessionID,
    msgtype: String,
    title: String,
    text: String,
) -> SyncReturn<String> {
    let retry_for_relay =
        crate::flutter::sessions::get_session_by_session_id(&session_id).map_or(false, |s| {
            let lc = s.lc.read().unwrap();
            lc.direct == Some(true) && !lc.received
        });
    let retry = crate::client::check_if_retry(&msgtype, &title, &text, retry_for_relay);
    let mut json = serde_json::to_value(leapgate::reason::classify(&msgtype, &title, &text))
        .unwrap_or_default();
    json["retry"] = retry.into();
    SyncReturn(json.to_string())
}
