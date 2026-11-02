//! The new UI's account, address book and team devices (M4, H1; `LEAPGATE.md` §10.11): the HTTP
//! requests, the token and `user_info`, and the `_ab` / `_group` caches, so that the token never
//! reaches Dart. Every request goes through the strict client in `api.rs`.
//!
//! The functions return JSON for the UI: the result, or `{"error":<kind>,"text":<text>}`.

mod ab;
mod group;

pub use ab::{
    ab_add_peer, ab_add_tag, ab_book, ab_books, ab_cache, ab_delete_peers, ab_delete_tags,
    ab_rename_tag, ab_set_tag_color, ab_update_peer,
};
pub use group::{group, group_cache};

use crate::{api, report};
use hbb_common::{
    config::{Ab, Group, LocalConfig},
    log,
    serde_json::{self, json, Value},
    throttled_log,
};
use reqwest::Method;
use std::{
    collections::HashMap,
    sync::{Mutex, MutexGuard, PoisonError},
    time::Duration,
};

/// The LocalConfig keys upstream uses; the rest of Rust reads them (session token, audits,
/// the exit directory, the display name sent at login).
const TOKEN: &str = "access_token";
const USER_INFO: &str = "user_info";
/// Upstream logs out with the same timeout.
const LOGOUT_TIMEOUT: Duration = Duration::from_secs(2);
/// Upstream's page size; servers answer at least this many per page.
const PAGE_SIZE: i64 = 100;
const TEXT_MAX: usize = 200;
const LOG_INTERVAL: Duration = Duration::from_secs(60);

/// Each export runs on its own frb thread: the caches are read, changed and written back, and
/// signing out removes them, each as one step under this lock. Never held across an `.await`.
static CACHE: Mutex<()> = Mutex::new(());

fn cache_lock() -> MutexGuard<'static, ()> {
    CACHE.lock().unwrap_or_else(PoisonError::into_inner)
}

/// Where the token, `user_info` and the two caches are kept. Tests keep them in memory instead of
/// the user's config.
pub(crate) trait Store {
    fn option(&self, key: &str) -> String;
    fn set_option(&self, key: &str, value: String);
    fn ab(&self) -> Ab;
    /// `None` removes the cache.
    fn set_ab(&self, ab: Option<&Ab>);
    fn group(&self) -> Group;
    fn set_group(&self, group: Option<&Group>);
}

/// The real store: LocalConfig and the `_ab` / `_group` files.
pub(crate) struct Local;

impl Store for Local {
    fn option(&self, key: &str) -> String {
        LocalConfig::get_option(key)
    }

    fn set_option(&self, key: &str, value: String) {
        LocalConfig::set_option(key.to_owned(), value);
    }

    fn ab(&self) -> Ab {
        Ab::load()
    }

    fn set_ab(&self, ab: Option<&Ab>) {
        match ab.map(serde_json::to_string) {
            Some(Ok(json)) => Ab::store(json),
            Some(Err(e)) => log::error!("leapgate account: address book cache not saved: {e}"),
            None => Ab::remove(),
        }
    }

    fn group(&self) -> Group {
        Group::load()
    }

    fn set_group(&self, group: Option<&Group>) {
        match group.map(serde_json::to_string) {
            Some(Ok(json)) => Group::store(json),
            Some(Err(e)) => log::error!("leapgate account: team devices cache not saved: {e}"),
            None => Group::remove(),
        }
    }
}

/// This device as the account requests name it.
pub struct Device {
    pub id: String,
    pub uuid: String,
}

/// The error kinds of `LEAPGATE.md` §10.11 "错误的形状".
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) enum Kind {
    Unauthorized,
    WrongCredentials,
    VerificationRequired,
    NotFound,
    Conflict,
    Unsupported,
    Network,
    Server,
}

impl Kind {
    fn as_str(self) -> &'static str {
        match self {
            Kind::Unauthorized => "unauthorized",
            Kind::WrongCredentials => "wrong_credentials",
            Kind::VerificationRequired => "verification_required",
            Kind::NotFound => "not_found",
            Kind::Conflict => "conflict",
            Kind::Unsupported => "unsupported",
            Kind::Network => "network",
            Kind::Server => "server",
        }
    }
}

#[derive(Debug)]
pub(crate) struct Error {
    kind: Kind,
    text: String,
}

impl Error {
    fn new(kind: Kind, text: &str) -> Self {
        Self {
            kind,
            text: text.chars().take(TEXT_MAX).collect(),
        }
    }

    /// A 2xx whose body is not what the endpoint answers.
    fn shape(status: u16) -> Self {
        Self::new(Kind::Server, &format!("HTTP {status}"))
    }
}

type Result<T> = std::result::Result<T, Error>;

fn render(r: Result<Value>) -> String {
    match r {
        Ok(v) => v.to_string(),
        Err(e) => json!({ "error": e.kind.as_str(), "text": e.text }).to_string(),
    }
}

/// `{"user":<user_info>}` when signed in, `{}` when not; asks nothing.
pub fn account_local() -> String {
    local(&Local)
}

/// Whether the API server answers `GET /api/login-options` with a 2xx; the options are ignored
/// (M4-4).
pub async fn account_login_options() -> String {
    render(login_options(&report::api_root()).await)
}

pub async fn account_login(
    username: &str,
    password: &str,
    device: &Device,
    device_info: Value,
) -> String {
    let base = report::api_root();
    render(login(&Local, &base, username, password, device, device_info).await)
}

pub async fn account_current_user(device: &Device) -> String {
    render(current_user(&Local, &report::api_root(), device).await)
}

/// Always `{}`: signed out on this device whatever the server said (M4-9).
pub async fn account_logout(device: &Device) -> String {
    logout(&Local, &report::api_root(), device).await;
    "{}".to_owned()
}

fn local(s: &impl Store) -> String {
    if s.option(TOKEN).is_empty() {
        return "{}".to_owned();
    }
    let user = serde_json::from_str::<Value>(&s.option(USER_INFO))
        .ok()
        .filter(Value::is_object)
        .unwrap_or_else(|| json!({}));
    json!({ "user": user }).to_string()
}

async fn login_options(base: &str) -> Result<Value> {
    let (status, body) = send(
        base,
        Method::GET,
        "/api/login-options",
        &[],
        "",
        None,
        api::TIMEOUT,
    )
    .await?;
    if (200..300).contains(&status) {
        return Ok(json!({}));
    }
    Err(Error::new(Kind::Server, &error_text(status, &body)))
}

async fn login(
    s: &impl Store,
    base: &str,
    username: &str,
    password: &str,
    device: &Device,
    device_info: Value,
) -> Result<Value> {
    // Upstream `LoginRequest` (common/hbbs/hbbs.dart) without the verification fields.
    let body = json!({
        "username": username,
        "password": password,
        "id": device.id,
        "uuid": device.uuid,
        "autoLogin": true,
        "type": "account",
        "deviceInfo": device_info,
    });
    let (status, body) = send(
        base,
        Method::POST,
        "/api/login",
        &[],
        "",
        Some(bytes(body)),
        api::TIMEOUT,
    )
    .await?;
    // leapgate-server answers a wrong user name or password with 401 (07 §4.1); no token is
    // involved, so nothing is cleared.
    if status == 401 {
        return Err(Error::new(
            Kind::WrongCredentials,
            &error_text(status, &body),
        ));
    }
    let v = answer(s, "", status, &body, Kind::Server)?;
    if v.get("type").and_then(Value::as_str) != Some("access_token") {
        return Err(Error::new(Kind::VerificationRequired, ""));
    }
    let token = v.get(TOKEN).and_then(Value::as_str).unwrap_or_default();
    let Some(user) = v.get("user").filter(|u| u.is_object() && !token.is_empty()) else {
        return Err(Error::shape(status));
    };
    s.set_option(TOKEN, token.to_owned());
    s.set_option(USER_INFO, user_info(user));
    Ok(json!({ "user": user }))
}

async fn current_user(s: &impl Store, base: &str, device: &Device) -> Result<Value> {
    let body = json!({ "id": device.id, "uuid": device.uuid });
    let token = s.option(TOKEN);
    let (status, body) = send(
        base,
        Method::POST,
        "/api/currentUser",
        &[],
        &token,
        Some(bytes(body)),
        api::TIMEOUT,
    )
    .await?;
    // Upstream drops the token on a 400 too (models/user_model.dart).
    let status = if status == 400 { 401 } else { status };
    let user = answer(s, &token, status, &body, Kind::Server)?;
    if !user.is_object() {
        return Err(Error::shape(status));
    }
    {
        // `user_info` is read without the token (login display name), so a logout landing here
        // must not have it written back.
        let _cache = cache_lock();
        if s.option(TOKEN) == token {
            s.set_option(USER_INFO, user_info(&user));
        }
    }
    Ok(json!({ "user": user }))
}

async fn logout(s: &impl Store, base: &str, device: &Device) {
    let body = json!({ "id": device.id, "uuid": device.uuid });
    let token = s.option(TOKEN);
    let failure = match send(
        base,
        Method::POST,
        "/api/logout",
        &[],
        &token,
        Some(bytes(body)),
        LOGOUT_TIMEOUT,
    )
    .await
    {
        Ok((status, _)) if (200..300).contains(&status) => None,
        Ok((status, _)) => Some(format!("HTTP {status}")),
        Err(e) => Some(e.text),
    };
    if let Some(failure) = failure {
        throttled_log!(
            LOG_INTERVAL,
            info,
            "leapgate account: /api/logout failed ({}), signed out locally",
            failure
        );
    }
    clear(s);
}

/// Signed out: the token, `user_info` and both caches go.
fn clear(s: &impl Store) {
    let _cache = cache_lock();
    clear_locked(s);
}

/// A 401 for `used` signs out only while `used` is still the token: an answer to a request sent
/// before a logout and a new login must not end the new login.
fn clear_if(s: &impl Store, used: &str) {
    let _cache = cache_lock();
    if s.option(TOKEN) == used {
        clear_locked(s);
    }
}

fn clear_locked(s: &impl Store) {
    s.set_option(TOKEN, String::new());
    s.set_option(USER_INFO, String::new());
    s.set_ab(None);
    s.set_group(None);
}

/// Upstream `UserPayload.toJson`, which Rust reads elsewhere.
fn user_info(user: &Value) -> String {
    let field = |k: &str| user.get(k).and_then(Value::as_str).unwrap_or_default();
    let status = match user.get("status").and_then(Value::as_i64) {
        Some(0) => 0,
        Some(-1) => -1,
        _ => 1,
    };
    json!({
        "name": field("name"),
        "display_name": field("display_name"),
        "avatar": field("avatar"),
        "status": status,
    })
    .to_string()
}

/// One request. Only the path and the failure are logged: never the token, a password or a body.
async fn send(
    base: &str,
    method: Method,
    path: &str,
    query: &[(&str, &str)],
    token: &str,
    body: Option<Vec<u8>>,
    timeout: Duration,
) -> Result<(u16, Vec<u8>)> {
    match api::bearer(method, base, path, query, token, body, timeout).await {
        Ok((status, body)) => {
            if !(200..300).contains(&status) {
                throttled_log!(
                    LOG_INTERVAL,
                    info,
                    "leapgate account: {} answered {}",
                    path,
                    status
                );
            }
            Ok((status, body))
        }
        Err(e) => {
            throttled_log!(
                LOG_INTERVAL,
                info,
                "leapgate account: {} failed ({})",
                path,
                e
            );
            Err(Error::new(Kind::Network, &e.to_string()))
        }
    }
}

fn bytes(v: Value) -> Vec<u8> {
    v.to_string().into_bytes()
}

/// The JSON of an answer (`Value::Null` when the body is empty or not JSON), or the error it
/// means for every endpoint but login: a 401 to a request with the token `used` signs out on
/// this device.
fn answer(s: &impl Store, used: &str, status: u16, body: &[u8], on_404: Kind) -> Result<Value> {
    let json = serde_json::from_slice::<Value>(body).unwrap_or(Value::Null);
    let server_error = json.get("error").filter(|e| !e.is_null());
    let kind = match status {
        200..=299 if server_error.is_none() => return Ok(json),
        200..=299 => Kind::Server,
        401 => {
            clear_if(s, used);
            Kind::Unauthorized
        }
        404 => on_404,
        409 => Kind::Conflict,
        _ => Kind::Server,
    };
    Err(Error::new(kind, &error_text(status, body)))
}

/// The server's `error`, or `HTTP <status>`.
fn error_text(status: u16, body: &[u8]) -> String {
    match serde_json::from_slice::<Value>(body)
        .ok()
        .and_then(|v| v.get("error").cloned())
    {
        Some(Value::String(e)) => e,
        Some(e) if !e.is_null() => e.to_string(),
        _ => format!("HTTP {status}"),
    }
}

/// Every page of a list endpoint (`{"total":n,"data":[…]}`), the entries keyed by `key`, a later
/// one replacing an earlier one with the same key. Both `current` and `page` are sent:
/// rustdesk-api reads `page` for users and peers. Paging stops after the last page by `total`,
/// or at a page that brings no new key: rustdesk-api answers every `ab/peers` page with the same
/// first 1000 (07 §4.3).
async fn pages(
    s: &impl Store,
    base: &str,
    token: &str,
    method: Method,
    path: &str,
    extra: &[(&str, &str)],
    key: &str,
) -> Result<Vec<Value>> {
    let page_size = PAGE_SIZE.to_string();
    let mut items: Vec<Value> = Vec::new();
    let mut index: HashMap<String, usize> = HashMap::new();
    let mut current: i64 = 1;
    loop {
        let n = current.to_string();
        let mut query = vec![
            ("current", n.as_str()),
            ("page", n.as_str()),
            ("pageSize", page_size.as_str()),
        ];
        query.extend_from_slice(extra);
        let (status, body) = send(
            base,
            method.clone(),
            path,
            &query,
            token,
            None,
            api::TIMEOUT,
        )
        .await?;
        let Value::Object(mut page) = answer(s, token, status, &body, Kind::Server)? else {
            return Err(Error::shape(status));
        };
        let total = page
            .get("total")
            .and_then(Value::as_i64)
            .unwrap_or_default();
        let data = match page.remove("data") {
            Some(Value::Array(data)) => data,
            Some(Value::Null) | None => Vec::new(),
            Some(_) => return Err(Error::shape(status)),
        };
        let mut new = false;
        for item in data {
            let k = item
                .get(key)
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned();
            match index.get(&k) {
                Some(&i) => items[i] = item,
                None => {
                    index.insert(k, items.len());
                    items.push(item);
                    new = true;
                }
            }
        }
        if !new || current * PAGE_SIZE >= total {
            return Ok(items);
        }
        current += 1;
    }
}

#[cfg(test)]
mod live_tests;
#[cfg(test)]
mod tests;
