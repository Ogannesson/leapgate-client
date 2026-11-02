//! The address book: upstream `models/ab_model.dart`'s requests (the current one only, no legacy
//! `/api/ab`) and its `_ab` cache.

use super::{answer, bytes, pages, render, send, Error, Kind, Local, Result, Store, TOKEN};
use crate::{api, report};
use hbb_common::{
    config::{Ab, AbEntry, AbPeer},
    serde_json::{self, json, Map, Value},
};
use reqwest::Method;

/// The name `AbEntry::personal()` knows the personal book by; `src/client.rs` fills a saved
/// password from that entry (07 §4.2).
const PERSONAL_NAME: &str = "My address book";

/// The cache entries for the current token, `{"entries":[…]}`; asks nothing.
pub fn ab_cache() -> String {
    cache(&Local)
}

/// The personal book's guid, `max_peers` and the shared books.
pub async fn ab_books() -> String {
    render(books(&Local, &report::api_root()).await)
}

/// One book's devices and tags; caches it on success.
pub async fn ab_book(guid: &str, name: &str, personal: bool) -> String {
    render(book(&Local, &report::api_root(), guid, name, personal).await)
}

/// `peer` is the device's JSON as the UI built it.
pub async fn ab_add_peer(guid: &str, peer: String) -> String {
    write(
        Method::POST,
        &format!("/api/ab/peer/add/{guid}"),
        peer.into_bytes(),
    )
    .await
}

/// `peer` is `id` plus the fields to change.
pub async fn ab_update_peer(guid: &str, peer: String) -> String {
    write(
        Method::PUT,
        &format!("/api/ab/peer/update/{guid}"),
        peer.into_bytes(),
    )
    .await
}

pub async fn ab_delete_peers(guid: &str, ids: &[String]) -> String {
    write(
        Method::DELETE,
        &format!("/api/ab/peer/{guid}"),
        bytes(json!(ids)),
    )
    .await
}

/// `color` is ARGB, as upstream stores it.
pub async fn ab_add_tag(guid: &str, name: &str, color: i64) -> String {
    let body = json!({ "name": name, "color": color });
    write(
        Method::POST,
        &format!("/api/ab/tag/add/{guid}"),
        bytes(body),
    )
    .await
}

pub async fn ab_rename_tag(guid: &str, old_name: &str, new_name: &str) -> String {
    let body = json!({ "old": old_name, "new": new_name });
    write(
        Method::PUT,
        &format!("/api/ab/tag/rename/{guid}"),
        bytes(body),
    )
    .await
}

pub async fn ab_set_tag_color(guid: &str, name: &str, color: i64) -> String {
    let body = json!({ "name": name, "color": color });
    write(
        Method::PUT,
        &format!("/api/ab/tag/update/{guid}"),
        bytes(body),
    )
    .await
}

pub async fn ab_delete_tags(guid: &str, names: &[String]) -> String {
    write(
        Method::DELETE,
        &format!("/api/ab/tag/{guid}"),
        bytes(json!(names)),
    )
    .await
}

async fn write(method: Method, path: &str, body: Vec<u8>) -> String {
    render(write_to(&Local, &report::api_root(), method, path, body).await)
}

pub(super) fn cache(s: &impl Store) -> String {
    let token = s.option(TOKEN);
    let ab = s.ab();
    if token.is_empty() || ab.access_token != token {
        return json!({ "entries": [] }).to_string();
    }
    json!({ "entries": ab.ab_entries }).to_string()
}

pub(super) async fn books(s: &impl Store, base: &str) -> Result<Value> {
    // Only `personal` tells an old server without the address book apart (07 §4.4); asked first
    // so that its 404 is not hidden behind another endpoint's.
    let personal = read(s, base, "/api/ab/personal", Kind::Unsupported).await?;
    let Some(personal) = personal
        .get("guid")
        .and_then(Value::as_str)
        .filter(|g| !g.is_empty())
    else {
        return Err(Error::shape(200));
    };
    let settings = read(s, base, "/api/ab/settings", Kind::Server).await?;
    let max_peers = settings
        .get("max_peer_one_ab")
        .and_then(Value::as_i64)
        .unwrap_or_default();
    let shared = pages(
        s,
        base,
        Method::POST,
        "/api/ab/shared/profiles",
        &[],
        "guid",
    )
    .await?;
    Ok(json!({ "max_peers": max_peers, "personal": personal, "shared": shared }))
}

pub(super) async fn book(
    s: &impl Store,
    base: &str,
    guid: &str,
    name: &str,
    personal: bool,
) -> Result<Value> {
    let token = s.option(TOKEN);
    let peers = pages(
        s,
        base,
        Method::POST,
        "/api/ab/peers",
        &[("ab", guid)],
        "id",
    )
    .await?;
    let tags = match read(s, base, &format!("/api/ab/tags/{guid}"), Kind::Server).await? {
        Value::Array(tags) => tags,
        // rustdesk-api encodes a book without tags as `null`.
        Value::Null => Vec::new(),
        _ => return Err(Error::shape(200)),
    };
    // A logout while this was in flight removed the cache; do not bring it back.
    if s.option(TOKEN) == token {
        save(s, &token, guid, name, personal, &peers, &tags);
    }
    Ok(json!({ "peers": peers, "tags": tags }))
}

/// A POST without a body that answers JSON.
async fn read(s: &impl Store, base: &str, path: &str, on_404: Kind) -> Result<Value> {
    let (status, body) = send(
        base,
        Method::POST,
        path,
        &[],
        &s.option(TOKEN),
        None,
        api::TIMEOUT,
    )
    .await?;
    answer(s, status, &body, on_404)
}

/// Upstream `_jsonDecodeActionResp`: a 2xx without `error` is done; a 404 means the device or the
/// tag is not in the book.
pub(super) async fn write_to(
    s: &impl Store,
    base: &str,
    method: Method,
    path: &str,
    body: Vec<u8>,
) -> Result<Value> {
    let (status, body) = send(
        base,
        method,
        path,
        &[],
        &s.option(TOKEN),
        Some(body),
        api::TIMEOUT,
    )
    .await?;
    answer(s, status, &body, Kind::NotFound)?;
    Ok(json!({}))
}

/// Upstream keeps the personal book and the current one (`_serializeCache`): the personal entry
/// or the shared entry is replaced, and a cache of another token is dropped first.
fn save(
    s: &impl Store,
    token: &str,
    guid: &str,
    name: &str,
    personal: bool,
    peers: &[Value],
    tags: &[Value],
) {
    let mut ab = s.ab();
    if ab.access_token != token {
        ab = Ab {
            access_token: token.to_owned(),
            ab_entries: Vec::new(),
        };
    }
    ab.ab_entries.retain(|e| e.personal() != personal);
    let mut colors = Map::new();
    let mut names = Vec::new();
    for tag in tags {
        if let Some(n) = tag.get("name").and_then(Value::as_str) {
            colors.insert(
                n.to_owned(),
                tag.get("color").cloned().unwrap_or(Value::Null),
            );
            names.push(n.to_owned());
        }
    }
    ab.ab_entries.push(AbEntry {
        guid: guid.to_owned(),
        name: if personal { PERSONAL_NAME } else { name }.to_owned(),
        // Upstream `toCustomJson(includingHash: personal)`.
        peers: peers
            .iter()
            .filter_map(|p| serde_json::from_value::<AbPeer>(p.clone()).ok())
            .map(|p| {
                if personal {
                    p
                } else {
                    AbPeer {
                        hash: String::new(),
                        ..p
                    }
                }
            })
            .collect(),
        tags: names,
        tag_colors: Value::Object(colors).to_string(),
    });
    s.set_ab(Some(&ab));
}
