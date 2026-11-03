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

// ---- Account (M4) ----
// H1 (`LEAPGATE.md` §10.11): JSON results, or `{"error":…,"text":…}`. The token stays in Rust.

/// The signed-in user as stored, `{"user":…}`, or `{}`; asks nothing.
pub fn leapgate_account_local() -> SyncReturn<String> {
    SyncReturn(leapgate::account::account_local())
}

pub fn leapgate_account_login_options() -> String {
    account_run(leapgate::account::account_login_options())
}

pub fn leapgate_account_login(username: String, password: String) -> String {
    let device = account_device();
    let info = hbb_common::serde_json::to_value(crate::ui_interface::get_login_device_info())
        .unwrap_or_default();
    account_run(leapgate::account::account_login(
        &username, &password, &device, info,
    ))
}

pub fn leapgate_account_current_user() -> String {
    let device = account_device();
    account_run(leapgate::account::account_current_user(&device))
}

pub fn leapgate_account_logout() -> String {
    let device = account_device();
    account_run(leapgate::account::account_logout(&device))
}

pub fn leapgate_ab_cache() -> String {
    leapgate::account::ab_cache()
}

pub fn leapgate_group_cache() -> String {
    leapgate::account::group_cache()
}

pub fn leapgate_ab_books() -> String {
    account_run(leapgate::account::ab_books())
}

pub fn leapgate_ab_book(guid: String, name: String, personal: bool) -> String {
    account_run(leapgate::account::ab_book(&guid, &name, personal))
}

pub fn leapgate_ab_add_peer(guid: String, peer: String) -> String {
    account_run(leapgate::account::ab_add_peer(&guid, peer))
}

pub fn leapgate_ab_update_peer(guid: String, peer: String) -> String {
    account_run(leapgate::account::ab_update_peer(&guid, peer))
}

pub fn leapgate_ab_delete_peers(guid: String, ids: Vec<String>) -> String {
    account_run(leapgate::account::ab_delete_peers(&guid, &ids))
}

pub fn leapgate_ab_add_tag(guid: String, name: String, color: i64) -> String {
    account_run(leapgate::account::ab_add_tag(&guid, &name, color))
}

pub fn leapgate_ab_rename_tag(guid: String, old_name: String, new_name: String) -> String {
    account_run(leapgate::account::ab_rename_tag(&guid, &old_name, &new_name))
}

pub fn leapgate_ab_set_tag_color(guid: String, name: String, color: i64) -> String {
    account_run(leapgate::account::ab_set_tag_color(&guid, &name, color))
}

pub fn leapgate_ab_delete_tags(guid: String, names: Vec<String>) -> String {
    account_run(leapgate::account::ab_delete_tags(&guid, &names))
}

pub fn leapgate_group() -> String {
    account_run(leapgate::account::group())
}

/// Read before the runtime starts: `get_id` asks the service over IPC in a runtime of its own.
fn account_device() -> leapgate::account::Device {
    leapgate::account::Device {
        id: crate::ui_interface::get_id(),
        uuid: crate::ui_interface::get_uuid(),
    }
}

/// frb calls the exports on its own worker thread, outside any runtime.
#[hbb_common::tokio::main(flavor = "current_thread", crate = "hbb_common::tokio")]
async fn account_run(request: impl std::future::Future<Output = String>) -> String {
    request.await
}
