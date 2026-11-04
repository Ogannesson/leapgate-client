//! The UI process's end of the settings page's Rust items (`LEAPGATE.md` §10.13) that need
//! upstream's IPC, config or private functions: S1's inputs, S9, S10. The logic is in
//! `libs/leapgate` (`server_info`, `settings`).

#[cfg(not(any(target_os = "android", target_os = "ios")))]
use crate::ipc::{self, Data};
use base::config::keys;
use hbb_common::config::{self, Config};
#[cfg(not(any(target_os = "android", target_os = "ios")))]
use hbb_common::{log, tokio};
use leapgate::{
    server_info::{self, Servers},
    settings::{self, Saved},
};
use std::{collections::HashMap, sync::Mutex};

/// Held while this process writes the service's option table: each write reads the whole table
/// and sends it back, so two at once would drop one's change. frb runs exports concurrently.
static SAVING: Mutex<()> = Mutex::new(());

/// S9: merges `changes` into the service's options over one IPC connection (read the whole
/// table, merge, write it back, wait for the confirmation), then into this process's config.
/// Without the service, `settings::offline` decides. Upstream's side effects of writing these
/// options follow.
pub(crate) fn set_options(changes: HashMap<String, String>) -> Saved {
    let _saving = SAVING.lock().unwrap();
    let _nat = crate::CheckTestNatType::new();
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let saved = match save_to_service(&changes) {
        Some(options) => {
            Config::set_options(options);
            Saved::Saved
        }
        None => {
            let saved = offline();
            if saved == Saved::Failed {
                return saved;
            }
            save_here(&changes);
            saved
        }
    };
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let saved = {
        save_here(&changes);
        Saved::Saved
    };
    if changes.contains_key(keys::OPTION_ALLOW_INSECURE_TLS_FALLBACK) {
        hbb_common::tls::reset_tls_cache();
    }
    #[cfg(not(target_os = "ios"))]
    if changes.contains_key("audio-input") {
        crate::audio_service::restart();
    }
    crate::ui_interface::refresh_options();
    saved
}

fn save_here(changes: &HashMap<String, String>) {
    let mut options = Config::get_options();
    settings::merge(&mut options, changes);
    Config::set_options(options);
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn offline() -> Saved {
    settings::offline(
        crate::ui_interface::is_installed(),
        &crate::ui_interface::get_option("stop-service"),
    )
}

/// The options the service confirmed, `None` when it did not.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[tokio::main(flavor = "current_thread")]
async fn save_to_service(changes: &HashMap<String, String>) -> Option<HashMap<String, String>> {
    let Ok(mut c) = ipc::connect(1000, "").await else {
        log::info!("leapgate settings: options not saved, the service did not answer");
        return None;
    };
    c.send(&Data::Options(None)).await.ok()?;
    let Ok(Some(Data::Options(Some(mut options)))) = c.next_timeout(1000).await else {
        log::info!("leapgate settings: options not saved, reading the service's options failed");
        return None;
    };
    settings::merge(&mut options, changes);
    c.send(&Data::Options(Some(options.clone()))).await.ok()?;
    match c.next_timeout(1000).await {
        Ok(Some(Data::Options(None))) => Some(options),
        _ => {
            log::info!("leapgate settings: options sent, the service did not confirm them");
            None
        }
    }
}

/// S9 for the proxy: `true` when the service took it (it has no reply of its own, so the proxy
/// is asked back on the same connection), or when `settings::offline` lets it be saved here.
pub(crate) fn set_socks(proxy: String, username: String, password: String) -> bool {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        let socks = config::Socks5Server {
            proxy,
            username,
            password,
        };
        let socks = (!socks.proxy.is_empty()).then_some(socks);
        let _nat = crate::CheckTestNatType::new();
        if !socks_to_service(&socks) && offline() == Saved::Failed {
            return false;
        }
        Config::set_socks(socks);
        true
    }
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        crate::ui_interface::set_socks(proxy, username, password);
        true
    }
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[tokio::main(flavor = "current_thread")]
async fn socks_to_service(socks: &Option<config::Socks5Server>) -> bool {
    let Ok(mut c) = ipc::connect(1000, "").await else {
        log::info!("leapgate settings: proxy not saved, the service did not answer");
        return false;
    };
    // An empty proxy removes it, as upstream sends a removal.
    let sent = socks.clone().unwrap_or_default();
    if c.send(&Data::Socks(Some(sent))).await.is_err() || c.send(&Data::Socks(None)).await.is_err()
    {
        return false;
    }
    let confirmed = matches!(c.next_timeout(1000).await, Ok(Some(Data::Socks(v))) if v == *socks);
    if !confirmed {
        log::info!("leapgate settings: proxy sent, the service did not confirm it");
    }
    confirmed
}

/// S1's JSON. Options come from this process's cache, the current rendezvous server from the
/// service (09 §4.1).
pub(crate) fn server_summary() -> String {
    let option = |k: &str| crate::ui_interface::get_option(k);
    #[cfg(windows)]
    let (exe_host, exe_api, exe_key) = crate::platform::windows::get_license_from_exe_name()
        .map(|l| (l.host, l.api, l.key))
        .unwrap_or_default();
    #[cfg(not(windows))]
    let (exe_host, exe_api, exe_key) = (String::new(), String::new(), String::new());
    let (custom, api, key, relay) = (
        option("custom-rendezvous-server"),
        option("api-server"),
        option("key"),
        option("relay-server"),
    );
    let prod = config::PROD_RENDEZVOUS_SERVER.read().unwrap().clone();
    let current = current_rendezvous_server();
    let default_api = leapgate::brand::default_api_server();
    let servers = Servers {
        exe_host: &exe_host,
        exe_api: &exe_api,
        exe_key: &exe_key,
        custom: &custom,
        api: &api,
        key: &key,
        relay: &relay,
        prod: &prod,
        current: &current,
        ..Servers::with_defaults(&default_api)
    };
    server_info::summary(&servers).to_string()
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[tokio::main(flavor = "current_thread")]
async fn current_rendezvous_server() -> String {
    ipc::get_rendezvous_server(1000).await.0
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn current_rendezvous_server() -> String {
    Config::get_rendezvous_server()
}

/// S2's JSON, from this process's option cache.
pub(crate) fn server_kind() -> String {
    server_info::kind_with(&|k| crate::ui_interface::get_option(k)).to_string()
}

/// S10's first step: the chat the codes would go to, saving nothing. The error is `network`
/// when the request fails, otherwise a `settings::bot_result` kind, and the text without the
/// token.
pub(crate) fn bot_lookup(token: &str) -> Result<settings::BotChat, (&'static str, String)> {
    // A negative offset takes the last 100 updates; without it a backlog of over 100 would
    // hide the newest message.
    let url = format!(
        "https://api.telegram.org/bot{}/getUpdates?offset=-100",
        token
    );
    // As upstream's `get_chatid_telegram`: the caller may be in a tokio runtime.
    let resp = std::thread::spawn(move || crate::post_request_sync(url, "".to_owned(), ""))
        .join()
        .map_err(|_| "Thread panicked".to_owned())
        .and_then(|resp| resp.map_err(|e| e.to_string()));
    let (kind, result) = match resp {
        Ok(resp) => {
            let result = settings::bot_chat(&resp);
            (settings::bot_result(&result), result)
        }
        Err(text) => ("network", Err(text)),
    };
    match result {
        Ok(Some(chat)) => Ok(chat),
        Ok(None) => Err((kind, String::new())),
        Err(text) if token.is_empty() => Err((kind, text)),
        Err(text) => Err((kind, text.replace(token, "<token>"))),
    }
}

/// S10's second step: saves the bot as upstream's private `TelegramBot::save` does, then
/// confirms the service has it (upstream's save fails silently): `ok` or `other`.
pub(crate) fn bot_save(token: &str, chat_id: String) -> &'static str {
    let _saving = SAVING.lock().unwrap();
    let bot = crate::auth_2fa::TelegramBot {
        token: hbb_common::password_security::encrypt_vec_or_original(token.as_bytes(), "00", 1024),
        chat_id,
        ..Default::default()
    };
    let Ok(s) = serde_json::to_string(&bot) else {
        return "other";
    };
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    ipc::set_option("bot", &s);
    #[cfg(any(target_os = "android", target_os = "ios"))]
    Config::set_option("bot".to_owned(), s);
    if saved_in_service("bot") {
        "ok"
    } else {
        "other"
    }
}

/// `ok`, `wrong_code`, or `not_saved` when the code was right but the service does not have the
/// secret (upstream's save fails silently).
pub(crate) fn verify_2fa(code: String) -> &'static str {
    let _saving = SAVING.lock().unwrap();
    if !crate::ui_interface::verify2fa(code) {
        "wrong_code"
    } else if saved_in_service("2fa") {
        "ok"
    } else {
        "not_saved"
    }
}

/// Whether the service holds the value this process just wrote for `key`. Without the service,
/// upstream's save wrote it here only, which counts as `settings::offline` says (as in S9).
#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[tokio::main(flavor = "current_thread")]
async fn saved_in_service(key: &str) -> bool {
    let local = Config::get_option(key);
    if local.is_empty() {
        return false;
    }
    let Ok(mut c) = ipc::connect(1000, "").await else {
        return offline() != Saved::Failed;
    };
    if c.send(&Data::Options(None)).await.is_err() {
        return false;
    }
    matches!(c.next_timeout(1000).await, Ok(Some(Data::Options(Some(o)))) if o.get(key) == Some(&local))
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn saved_in_service(key: &str) -> bool {
    !Config::get_option(key).is_empty()
}
