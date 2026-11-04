//! The settings page's server summary (S1) and server kind (S2), `LEAPGATE.md` §10.13. Pure
//! functions over values the caller reads: in the UI process that is its option cache, not
//! `Config`, which can lag behind the service's (09 §4.1).

use crate::{brand, report};
use hbb_common::{
    config::{RENDEZVOUS_PORT, RENDEZVOUS_SERVERS, RS_PUB_KEY},
    serde_json::{json, Value},
};
use serde::Serialize;

/// Where each server setting can come from, in upstream's order of precedence.
#[derive(Default)]
pub struct Servers<'a> {
    /// From the program file name (Windows custom builds).
    pub exe_host: &'a str,
    pub exe_api: &'a str,
    pub exe_key: &'a str,
    /// The options `custom-rendezvous-server`, `api-server`, `key`, `relay-server`.
    pub custom: &'a str,
    pub api: &'a str,
    pub key: &'a str,
    pub relay: &'a str,
    /// `PROD_RENDEZVOUS_SERVER`, set by custom-client configuration (empty in Leapgate).
    pub prod: &'a str,
    /// The service's `Config::get_rendezvous_server()`: the cached server, else the first
    /// built-in one, with the default port added.
    pub current: &'a str,
    pub builtin: &'a [&'a str],
    pub default_api: &'a str,
    pub default_key: &'a str,
    pub allow_21114: bool,
    pub no_register_device: bool,
}

impl<'a> Servers<'a> {
    /// The build's own defaults; the caller fills in the rest.
    pub fn with_defaults(default_api: &'a str) -> Self {
        Servers {
            builtin: RENDEZVOUS_SERVERS,
            default_api,
            default_key: RS_PUB_KEY,
            allow_21114: report::allow_https_21114(),
            no_register_device: hbb_common::config::Config::no_register_device(),
            ..Default::default()
        }
    }
}

#[derive(Debug, PartialEq, Serialize)]
pub struct Item {
    pub value: String,
    pub source: &'static str,
}

impl Item {
    fn new(value: impl Into<String>, source: &'static str) -> Self {
        Item {
            value: value.into(),
            source,
        }
    }
}

/// `{"id":{"value","source"},"api":{"value","source"},"key":{"source"},"relay":{"value"}}`.
pub fn summary(s: &Servers) -> Value {
    json!({
        "id": id(s),
        "api": api(s),
        "key": {"source": key_source(s)},
        "relay": {"value": s.relay},
    })
}

/// `Config::get_rendezvous_server`'s order: `exe`, `user`, `custom`, then what the service
/// uses: the cache, or the built-in list's first entry (`default`). The cache itself is private
/// to the service's config, so its value is told by where it sits in the built-in list: the
/// first entry is `default`, another one `cache_default`, any other server `cache_last`.
fn id(s: &Servers) -> Item {
    if !s.exe_host.is_empty() {
        return Item::new(s.exe_host, "exe");
    }
    if !s.custom.is_empty() {
        return Item::new(s.custom, "user");
    }
    if !s.prod.is_empty() {
        return Item::new(s.prod, "custom");
    }
    let current = without_default_port(s.current);
    let first = s.builtin.first().copied().unwrap_or_default();
    if current.is_empty() || current == without_default_port(first) {
        return if first.is_empty() {
            Item::new("", "none")
        } else {
            Item::new(first, "default")
        };
    }
    if s.builtin.iter().any(|b| without_default_port(b) == current) {
        Item::new(current, "cache_default")
    } else {
        Item::new(current, "cache_last")
    }
}

fn without_default_port(server: &str) -> &str {
    server
        .strip_suffix(&format!(":{RENDEZVOUS_PORT}"))
        .unwrap_or(server)
}

/// Upstream `get_api_server` with its sources: `exe`, `user`, `derived` from the rendezvous
/// server (`exe_host`, `custom` or `prod`, as `get_custom_rendezvous_server` picks it),
/// `default` (`brand::default_api_server`), `none`. `report::api_root` uses it too.
pub fn api(s: &Servers) -> Item {
    if s.no_register_device {
        return Item::new("", "none");
    }
    let rendezvous = [s.exe_host, s.custom, s.prod]
        .into_iter()
        .find(|v| !v.is_empty());
    let (value, source) = if !s.exe_api.is_empty() {
        (s.exe_api.to_owned(), "exe")
    } else if !s.api.is_empty() {
        (s.api.to_owned(), "user")
    } else if let Some(r) = rendezvous {
        (brand::api_from_rendezvous(r), "derived")
    } else if !s.default_api.is_empty() {
        (s.default_api.to_owned(), "default")
    } else {
        return Item::new("", "none");
    };
    Item::new(report::normalize(value, s.allow_21114), source)
}

/// Upstream `get_key`'s order: `exe`, `user`, the built-in key (`default`), `none`.
fn key_source(s: &Servers) -> &'static str {
    if !s.exe_key.is_empty() {
        "exe"
    } else if !s.key.is_empty() {
        "user"
    } else if !s.default_key.is_empty() {
        "default"
    } else {
        "none"
    }
}

/// S2 over the given options (in the UI process, its option cache).
pub fn kind_with(option: &dyn Fn(&str) -> String) -> Value {
    kind(
        &report::api_root_with(option),
        &option(report::CAPS_KEY),
        &option(report::NOCAPS_KEY),
    )
}

/// S2: `{"kind":"leapgate"|"compat"|"checking","features":[…]}` for the API root `root`, from the
/// service's records `caps` (`leapgate-api-caps`) and `nocaps` (`leapgate-api-nocaps`). Only a
/// record for this root counts; without one the service has not answered yet.
pub fn kind(root: &str, caps: &str, nocaps: &str) -> Value {
    if !root.is_empty() {
        if let Some((r, features)) = report::parse_caps(caps) {
            if r == root {
                return json!({"kind": "leapgate", "features": features});
            }
        }
        if nocaps == root {
            return json!({"kind": "compat", "features": []});
        }
    }
    json!({"kind": "checking", "features": []})
}

#[cfg(test)]
mod tests {
    use super::*;

    const BUILTIN: &[&str] = &["rs.example.net", "rs2.example.net"];

    fn base() -> Servers<'static> {
        Servers {
            builtin: BUILTIN,
            default_api: "https://api.example.net",
            default_key: "built-in key",
            ..Default::default()
        }
    }

    fn summary_of(s: &Servers) -> (Item, Item, &'static str) {
        (id(s), api(s), key_source(s))
    }

    #[test]
    fn sources_in_upstream_order() {
        let i = Item::new;
        let rows: Vec<(Servers, Item, Item, &str)> = vec![
            // Nothing set: the build's defaults, whether or not the service answered.
            (
                Servers {
                    current: "rs.example.net:21116",
                    ..base()
                },
                i("rs.example.net", "default"),
                i("https://api.example.net", "default"),
                "default",
            ),
            (
                base(),
                i("rs.example.net", "default"),
                i("https://api.example.net", "default"),
                "default",
            ),
            // The service cached another server: one from the list, or the last custom one.
            (
                Servers {
                    current: "rs2.example.net:21116",
                    ..base()
                },
                i("rs2.example.net", "cache_default"),
                i("https://api.example.net", "default"),
                "default",
            ),
            (
                Servers {
                    current: "old.example.org:21116",
                    ..base()
                },
                i("old.example.org", "cache_last"),
                i("https://api.example.net", "default"),
                "default",
            ),
            // A custom ID server derives the API (port minus 2), the key stays built in.
            (
                Servers {
                    custom: "home.example.org:31116",
                    current: "home.example.org:31116",
                    ..base()
                },
                i("home.example.org:31116", "user"),
                i("http://home.example.org:31114", "derived"),
                "default",
            ),
            (
                Servers {
                    custom: "home.example.org",
                    api: "https://api.example.org/",
                    key: "user key",
                    ..base()
                },
                i("home.example.org", "user"),
                i("https://api.example.org", "user"),
                "user",
            ),
            (
                Servers {
                    prod: "prod.example.org",
                    ..base()
                },
                i("prod.example.org", "custom"),
                i("http://prod.example.org:21114", "derived"),
                "default",
            ),
            // The program file name wins over everything.
            (
                Servers {
                    exe_host: "exe.example.org",
                    exe_api: "https://exe.example.org:21114",
                    exe_key: "exe key",
                    custom: "home.example.org",
                    api: "https://api.example.org",
                    key: "user key",
                    ..base()
                },
                i("exe.example.org", "exe"),
                i("https://exe.example.org", "exe"),
                "exe",
            ),
            (
                Servers {
                    exe_host: "exe.example.org",
                    ..base()
                },
                i("exe.example.org", "exe"),
                i("http://exe.example.org:21114", "derived"),
                "default",
            ),
            // A build without defaults.
            (
                Servers {
                    current: ":21116",
                    builtin: &[""],
                    ..Default::default()
                },
                i("", "none"),
                i("", "none"),
                "none",
            ),
        ];
        for (s, want_id, want_api, want_key) in rows {
            let (got_id, got_api, got_key) = summary_of(&s);
            assert_eq!((got_id, got_api, got_key), (want_id, want_api, want_key));
        }
        let off = Servers {
            no_register_device: true,
            ..base()
        };
        assert_eq!(api(&off), i("", "none"));
    }

    #[test]
    fn summary_json_shape() {
        let s = Servers {
            relay: "relay.example.org",
            ..base()
        };
        assert_eq!(
            summary(&s),
            json!({
                "id": {"value": "rs.example.net", "source": "default"},
                "api": {"value": "https://api.example.net", "source": "default"},
                "key": {"source": "default"},
                "relay": {"value": "relay.example.org"},
            })
        );
    }

    #[test]
    fn server_kind_from_the_records() {
        let root = "https://api.example.net";
        let caps = format!("{root}\nexit,ice");
        assert_eq!(
            kind(root, &caps, ""),
            json!({"kind": "leapgate", "features": ["exit", "ice"]})
        );
        assert_eq!(
            kind(root, "", root),
            json!({"kind": "compat", "features": []})
        );
        // Records for another root (the server was changed) do not count.
        let other = "http://home.example.org:21114";
        assert_eq!(
            kind(other, &caps, root),
            json!({"kind": "checking", "features": []})
        );
        assert_eq!(
            kind(root, "", ""),
            json!({"kind": "checking", "features": []})
        );
        assert_eq!(
            kind("", "", ""),
            json!({"kind": "checking", "features": []})
        );
    }
}
