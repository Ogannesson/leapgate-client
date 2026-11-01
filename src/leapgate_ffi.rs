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

use crate::{client::Interface as _, flutter_ffi::SessionID};
use base::config::keys;
use flutter_rust_bridge::{StreamSink, SyncReturn};
use hbb_common::{
    config::LocalConfig, protobuf::Enum as _, rendezvous_proto::ConnType, ResultType,
};

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

/// How the session's current connection was made (Q3), as JSON: `path`, `transport` and for a
/// relay `relay`; `refused` after a server refused the attempt; `{}` while connecting or when not
/// known (`LEAPGATE.md` §10.4). Read it again after each connection-ready event.
pub fn leapgate_session_connection(session_id: SessionID) -> SyncReturn<String> {
    use crate::flutter::sessions;
    let connection = sessions::get_session_by_session_id(&session_id)
        .map(|s| {
            let conn_type = s.lc.read().unwrap().conn_type;
            leapgate::session::connection(&s.get_id(), conn_type as i32, |id, t| {
                ConnType::from_i32(t)
                    .is_some_and(|t| sessions::get_session_by_peer_id(id.to_owned(), t).is_some())
            })
        })
        .unwrap_or_default();
    SyncReturn(serde_json::to_string(&connection).unwrap_or_default())
}

// ---- Device ----

/// The name the peer is shown for this device at login, for the panel shown while waiting for
/// the peer to accept.
pub fn leapgate_local_display_name() -> SyncReturn<String> {
    SyncReturn(leapgate::ui::display_name(
        &crate::common::get_builtin_option(keys::OPTION_DISPLAY_NAME),
        &LocalConfig::get_option("user_info"),
        crate::username,
    ))
}

// ---- Connection manager (M3) ----

/// Authorized incoming connections by type (C1), asked of the service once, as JSON: `remote`,
/// `file_transfer`, `port_forward`, `exit`, `camera`, `terminal`; `{}` when the service does
/// not answer. Exits are not counted in `port_forward`.
pub fn leapgate_incoming_counts() -> String {
    crate::leapgate_hooks::ipc::query_incoming_counts()
        .and_then(|counts| serde_json::to_string(&counts).ok())
        .unwrap_or_else(|| "{}".to_owned())
}

/// Brings the CM window to the front (C2); nothing happens when the CM is not running.
pub fn leapgate_show_cm() {
    #[cfg(not(target_os = "ios"))]
    crate::ui_interface::send_to_cm(&crate::ipc::Data::Leapgate(leapgate::ipc::Msg::ShowCm));
}

/// Tells the CM the UI mode changed (S7).
pub fn leapgate_ui_mode_changed(mode: String) {
    #[cfg(not(target_os = "ios"))]
    crate::ui_interface::send_to_cm(&crate::ipc::Data::Leapgate(leapgate::ipc::Msg::UiMode {
        mode,
    }));
}

/// The CM page's events from the main window (C2, S7), as JSON: `{"name":"show_cm"}`,
/// `{"name":"ui_mode","mode":…}`. A new subscription replaces the previous one.
pub fn leapgate_cm_events(sink: StreamSink<String>) -> ResultType<()> {
    crate::leapgate_hooks::ipc::set_cm_events(sink);
    Ok(())
}
