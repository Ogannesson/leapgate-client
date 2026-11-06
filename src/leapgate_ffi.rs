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

/// The CM page's events from the main window (C2, S7, M6), as JSON: `{"name":"show_cm"}`,
/// `{"name":"ui_mode","mode":…}`, `{"name":"lang","lang":…}`. A new subscription replaces the
/// previous one.
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

// ---- Exit cards (M5) ----
// E1~E3 (`LEAPGATE.md` §10.12), desktop only. Stopping or cancelling a card is the first block's
// `session_close`; its path and relay are `leapgate_session_connection`.

/// E3: a session with the exit mapping alone, registered as a card; then `session_start` as
/// usual. `{}`, or `{"error":"already"}` (the device has a port forward session),
/// `{"error":"invalid_port"}`, `{"error":"other","text":…}`.
pub fn leapgate_exit_session_add(
    session_id: SessionID,
    id: String,
    port: i32,
    password: String,
    is_shared_password: bool,
    conn_token: Option<String>,
    force_relay: bool,
) -> SyncReturn<String> {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    return SyncReturn(crate::leapgate_hooks::exit::cards::session_add(
        &session_id,
        &id,
        port,
        password,
        is_shared_password,
        conn_token,
        force_relay,
    ));
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        let _ = (session_id, id, port, password, is_shared_password, conn_token, force_relay);
        SyncReturn(r#"{"error":"other","text":"not supported"}"#.to_owned())
    }
}

/// E2: `{"id":…,"session_id":…,"port":…,"state":…}` per change, each card's current state
/// first. A new subscription replaces the previous one.
pub fn leapgate_exit_events(sink: StreamSink<String>) -> ResultType<()> {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    crate::leapgate_hooks::exit::cards::set_events(sink);
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let _ = sink;
    Ok(())
}

/// Logs in now, past the cooldown (M5-7); `false` without such a card.
pub fn leapgate_exit_retry(id: String) -> SyncReturn<bool> {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    return SyncReturn(crate::leapgate_hooks::exit::cards::retry(&id));
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        let _ = id;
        SyncReturn(false)
    }
}

/// Listens on `port` instead, keeping the tunnel (M5-5); `false` without such a card or for a
/// port outside 1~65535.
pub fn leapgate_exit_set_port(id: String, port: i32) -> SyncReturn<bool> {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    return SyncReturn(crate::leapgate_hooks::exit::cards::set_port(&id, port));
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        let _ = (id, port);
        SyncReturn(false)
    }
}

// ---- Settings (M6) ----
// `LEAPGATE.md` §10.13. Server addresses and capabilities are read from the UI's option cache,
// not from this process's `Config` (09 §4.1).

/// S9: `changes` is a JSON object `{key: value}`, an empty value removes the option.
/// `saved`, `saved_local` (no service runs; it takes them when it starts) or `failed`.
pub fn leapgate_set_options(changes: String) -> String {
    let saved = match serde_json::from_str(&changes) {
        Ok(changes) => crate::leapgate_hooks::settings::set_options(changes),
        Err(_) => leapgate::settings::Saved::Failed,
    };
    saved.as_str().to_owned()
}

/// S9 for the proxy; an empty `proxy` removes it. `true` when it was saved.
pub fn leapgate_set_socks(
    proxy: String,
    username: String,
    password: String,
) -> bool {
    crate::leapgate_hooks::settings::set_socks(proxy, username, password)
}

/// E5: `{"valid","count","lines":[{"line","state"}],"value"}` (`LEAPGATE.md` §10.13).
pub fn leapgate_exit_allow_nets_check(text: String) -> SyncReturn<String> {
    let check = leapgate::exit::check_allow_nets(&text);
    SyncReturn(serde_json::to_string(&check).unwrap_or_default())
}

/// S1: `{"id":{"value","source","default"},"api":{"value","source"},"key":{"source","builtin"},
/// "relay":{"value"}}`; `id.default` is the first built-in ID server, empty without one;
/// `key.builtin` whether the build has a key.
pub fn leapgate_server_summary() -> String {
    crate::leapgate_hooks::settings::server_summary()
}

/// S2: `{"kind":"leapgate"|"compat"|"checking","features":[…]}`.
pub fn leapgate_server_kind() -> SyncReturn<String> {
    SyncReturn(crate::leapgate_hooks::settings::server_kind())
}

/// S3: `empty`, `valid` or `invalid`.
pub fn leapgate_key_check(
    key: String,
) -> SyncReturn<String> {
    SyncReturn(leapgate::sign::key_check(&key).to_owned())
}

/// S4: `[{"name","ipv4":[…],"ipv6":[…]}]` for the physical adapters, without temporary IPv6
/// addresses.
pub fn leapgate_local_addresses() -> String {
    serde_json::to_string(&leapgate::lan::local_addresses()).unwrap_or_else(|_| "[]".to_owned())
}

/// S5: the service's direct IP access listener, `{"state":"listening","port":N}`,
/// `{"state":"failed","port":N,"error":"in_use"|"denied"|"other"}`, or `{}` without a result.
pub fn leapgate_direct_listen() -> String {
    crate::leapgate_hooks::ipc::query_direct_listen()
        .and_then(|listen| serde_json::to_string(&listen).ok())
        .unwrap_or_else(|| "{}".to_owned())
}

/// S10's first step, saving nothing: `{"result":"ok","chat":{"id","type","label"}}` with the chat
/// of the bot's latest message, or `{"result":"network"|"invalid_token"|"no_chat"|"other",
/// "text":…}`; `text` is the error text, without the token.
pub fn leapgate_bot_lookup(token: String) -> String {
    match crate::leapgate_hooks::settings::bot_lookup(&token) {
        Ok(chat) => serde_json::json!({ "result": "ok", "chat": chat }),
        Err((result, text)) => serde_json::json!({ "result": result, "text": text }),
    }
    .to_string()
}

/// S10's second step, after the user confirmed the chat: `ok`, or `other` when the service does
/// not have it.
pub fn leapgate_bot_save(token: String, chat_id: String) -> String {
    crate::leapgate_hooks::settings::bot_save(&token, chat_id).to_owned()
}

/// `ok`, `wrong_code`, or `not_saved` (the code was right but the service does not have it).
pub fn leapgate_verify_2fa(code: String) -> String {
    crate::leapgate_hooks::settings::verify_2fa(code).to_owned()
}

/// Tells the CM the UI language changed, the resolved one (`zh-cn` or `en`). Instead of
/// upstream's `main_change_language`, whose message has the CM store its whole, older
/// LocalConfig.
pub fn leapgate_lang_changed(lang: String) {
    #[cfg(not(target_os = "ios"))]
    crate::ui_interface::send_to_cm(&crate::ipc::Data::Leapgate(leapgate::ipc::Msg::Lang {
        lang,
    }));
}

// ---- File transfer (M7a) ----
// `LEAPGATE.md` §10.15.

/// FT2: `{"reason":…,"args":[…],"text":…}` for a `job_error`'s `err`. `peer_platform` is the
/// peer info's `platform`; `side` is `local`, `remote` or `unknown` (a transfer).
pub fn leapgate_ft_reason(text: String, peer_platform: String, side: String) -> SyncReturn<String> {
    let reason = leapgate::ft_reason::classify(&text, &peer_platform, &side);
    SyncReturn(serde_json::to_string(&reason).unwrap_or_default())
}

/// M7a-4: as upstream's `session_read_local_dir_sync`, but a failure is
/// `{"error":…,"reason":…}` instead of an empty string.
pub fn leapgate_ft_read_local_dir(path: String, show_hidden: bool) -> SyncReturn<String> {
    SyncReturn(crate::leapgate_hooks::file_transfer::read_local_dir(
        path,
        show_hidden,
    ))
}

/// M7a-3: removes a link itself, not what it points to. The result comes as the session's
/// `job_done` / `job_error` with `id` = `act_id` and `file_num` 0.
pub fn leapgate_ft_remove_link(
    session_id: SessionID,
    act_id: i32,
    path: String,
    is_remote: bool,
    is_dir_link: bool,
) {
    crate::leapgate_hooks::file_transfer::remove_link(
        session_id,
        act_id,
        path,
        is_remote,
        is_dir_link,
    );
}

// ---- Install (M8) ----
// `LEAPGATE.md` §10.16.

/// The home page's cards: `kind` is `install` (the default path and options) or `upgrade` (the
/// installed path and options). Does not return on success: this process exits and the
/// installed copy starts. A failure is `{"result":"uac_denied"|"failed","text":…}`.
pub fn leapgate_install(kind: String) -> String {
    crate::leapgate_hooks::install::install(&kind)
}
