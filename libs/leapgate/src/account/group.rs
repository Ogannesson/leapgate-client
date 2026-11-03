//! The team devices: upstream `models/group_model.dart`'s users and peers (not the device groups,
//! M4-6) and its `_group` cache.

use super::{cache_lock, pages, render, Local, Result, Store, TOKEN};
use crate::report;
use hbb_common::{
    config::{Group, GroupPeer, GroupUser},
    serde_json::{json, Value},
};
use reqwest::Method;

/// What upstream asks: only the users and devices the account may see, of enabled users.
const QUERY: [(&str, &str); 2] = [("accessible", ""), ("status", "1")];

/// `{"users":[…],"peers":[…]}` from the cache of the current token, `{}` without one; asks
/// nothing.
pub fn group_cache() -> String {
    cache(&Local)
}

/// The people and devices; rewrites the cache on success.
pub async fn group() -> String {
    render(pull(&Local, &report::api_root()).await)
}

pub(super) fn cache(s: &impl Store) -> String {
    let group = {
        let _cache = cache_lock();
        s.group()
    };
    let token = s.option(TOKEN);
    if token.is_empty() || group.access_token != token {
        return "{}".to_owned();
    }
    json!({ "users": group.users, "peers": group.peers }).to_string()
}

pub(super) async fn pull(s: &impl Store, base: &str) -> Result<Value> {
    let token = s.option(TOKEN);
    let users = pages(s, base, &token, Method::GET, "/api/users", &QUERY, "name").await?;
    let peers = pages(s, base, &token, Method::GET, "/api/peers", &QUERY, "id").await?;
    let group = to_cache(token, &users, &peers);
    {
        let _cache = cache_lock();
        // A logout while this was in flight removed the cache; do not bring it back.
        if s.option(TOKEN) == group.access_token {
            s.set_group(Some(&group));
        }
    }
    Ok(json!({ "users": users, "peers": peers }))
}

/// Upstream `_saveCache`: users as `toGroupCacheJson`, devices as `PeerPayload.toPeer` then
/// `toGroupCacheJson`.
fn to_cache(access_token: String, users: &[Value], peers: &[Value]) -> Group {
    let field = |v: &Value, k: &str| {
        v.get(k)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned()
    };
    Group {
        access_token,
        users: users
            .iter()
            .map(|u| GroupUser {
                name: field(u, "name"),
                display_name: field(u, "display_name"),
            })
            .collect(),
        peers: peers
            .iter()
            .map(|p| {
                let info = p.get("info").cloned().unwrap_or_default();
                GroupPeer {
                    id: field(p, "id"),
                    username: field(&info, "username"),
                    hostname: field(&info, "device_name"),
                    platform: platform(&field(&info, "os")).to_owned(),
                    login_name: field(p, "user_name"),
                }
            })
            .collect(),
        device_groups: Vec::new(),
    }
}

/// Upstream `_platform` in `common/hbbs/hbbs.dart`; "" where it gives null.
fn platform(os: &str) -> &'static str {
    let first = os.split(" / ").next().unwrap_or_default().to_lowercase();
    match first.as_str() {
        "windows" => "Windows",
        "linux" => "Linux",
        "macos" => "Mac OS",
        "android" => "Android",
        _ if os.to_lowercase().contains("linux") => "Linux",
        _ => "",
    }
}
