//! `POST /api/porta/v1/heartbeat`: the heartbeat with sysinfo folded in, strategy handed down.

use super::{
    exchange, is_supported, mark_supported, mark_unsupported, select, Cap, CapSlot, Env, Reply,
    LOG_INTERVAL,
};
use crate::route;
use base::config::keys;
use hbb_common::{
    base64::{engine::general_purpose::STANDARD, Engine as _},
    config::{self, Config, LocalConfig},
    get_uuid, get_version_number, log,
    serde_json::{self, json, Map, Value},
    sha2::{Digest, Sha256},
    throttled_log,
};
use serde::Serialize;
use std::{
    collections::HashMap,
    sync::Mutex,
    time::{Duration, Instant},
};

const INTERVAL_IDLE: Duration = Duration::from_secs(15);
const INTERVAL_CONNS: Duration = Duration::from_secs(3);
const BACKOFF_MAX: Duration = Duration::from_secs(60);
const STRATEGY_TIMESTAMP: &str = "strategy_timestamp";

#[derive(Default)]
pub(super) struct Hb {
    /// The API root the rest belongs to; another root starts from scratch.
    root: String,
    last_attempt: Option<Instant>,
    failures: u32,
    need_sysinfo: bool,
    /// Hash of the sysinfo the server last accepted.
    confirmed_hash: String,
}

pub(super) static HB: Mutex<Hb> = Mutex::new(Hb {
    root: String::new(),
    last_attempt: None,
    failures: 0,
    need_sysinfo: false,
    confirmed_hash: String::new(),
});

pub(super) struct Payload {
    pub uuid: String,
    pub ver: i64,
    pub strategy_rev: i64,
    /// Without `id` and `uuid`: the device is identified by the signature header.
    pub sysinfo: Value,
}

#[derive(Serialize)]
struct Req<'a> {
    uuid: &'a str,
    ver: i64,
    porta: &'static str,
    #[serde(skip_serializing_if = "<[i32]>::is_empty")]
    conns: &'a [i32],
    strategy_rev: i64,
    routing_rev: i64,
    sysinfo_hash: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    sysinfo: Option<&'a Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    probes: Option<Value>,
}

pub(super) async fn tick<E: Env>(
    env: &E,
    cap: &CapSlot,
    hb: &Mutex<Hb>,
    root: &str,
    conns: Vec<i32>,
    payload: impl FnOnce() -> Payload,
) -> bool {
    select(env, cap, root);
    {
        let mut slot = cap.lock().unwrap();
        if let Cap::Unsupported { recheck_at } = slot.1 {
            if Instant::now() < recheck_at {
                return false;
            }
            slot.1 = Cap::Unknown;
        }
    }
    {
        let mut h = hb.lock().unwrap();
        if h.root != root {
            *h = Hb {
                root: root.to_owned(),
                ..Default::default()
            };
        }
        let interval = interval(h.failures, !conns.is_empty());
        if h.last_attempt.map_or(false, |t| t.elapsed() < interval) {
            return true;
        }
        h.last_attempt = Some(Instant::now());
    }
    let p = payload();
    let sysinfo = serde_json::to_vec(&p.sysinfo).unwrap_or_default();
    let hash = STANDARD.encode(Sha256::digest(&sysinfo));
    let with_sysinfo = {
        let h = hb.lock().unwrap();
        h.need_sysinfo || h.confirmed_hash != hash
    };
    let body = body(&p, &conns, &hash, with_sysinfo.then_some(&p.sysinfo));
    match exchange(env, "heartbeat", &body).await {
        Reply::Ok(map) => {
            on_ok(env, cap, hb, root, &map, with_sysinfo.then_some(hash));
            true
        }
        Reply::NoApi(status) if !is_supported(cap, root) => {
            mark_unsupported(env, cap, root, status);
            false
        }
        Reply::NoApi(status) | Reply::Rejected(status) => fail(hb, &format!("status {status}")),
        Reply::Failed(e) => fail(hb, &e),
    }
}

/// 3, 6, 12, 24, 48, 60, 60... seconds after failures; otherwise upstream's pace.
fn interval(failures: u32, has_conns: bool) -> Duration {
    if failures > 0 {
        let backoff = Duration::from_secs(3 << (failures - 1).min(5));
        return backoff.min(BACKOFF_MAX);
    }
    if has_conns {
        INTERVAL_CONNS
    } else {
        INTERVAL_IDLE
    }
}

fn body(p: &Payload, conns: &[i32], hash: &str, sysinfo: Option<&Value>) -> Vec<u8> {
    let req = Req {
        uuid: &p.uuid,
        ver: p.ver,
        porta: env!("CARGO_PKG_VERSION"),
        conns,
        strategy_rev: p.strategy_rev,
        routing_rev: route::routing_rev(),
        sysinfo_hash: hash,
        sysinfo,
        probes: route::probes(),
    };
    serde_json::to_vec(&req).unwrap_or_default()
}

fn on_ok<E: Env>(
    env: &E,
    cap: &CapSlot,
    hb: &Mutex<Hb>,
    root: &str,
    map: &Map<String, Value>,
    sent_hash: Option<String>,
) {
    let features = map
        .get("features")
        .and_then(Value::as_array)
        .map(|a| {
            a.iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default();
    mark_supported(env, cap, root, Some(features));
    {
        let mut h = hb.lock().unwrap();
        h.failures = 0;
        if let Some(hash) = sent_hash {
            h.confirmed_hash = hash;
        }
        h.need_sysinfo = map
            .get("need_sysinfo")
            .and_then(Value::as_bool)
            .unwrap_or(false);
    }
    if let Some(s) = map.get("strategy") {
        if let (Some(rev), Some(options)) = (
            s.get("rev").and_then(Value::as_i64),
            s.get("options").and_then(Value::as_object),
        ) {
            env.apply_strategy(rev, options);
        }
    }
    // Every time, `routing` or not: contract 02 keys its measurements off the last success.
    env.route_heartbeat_ok(map.get("routing"));
}

fn fail(hb: &Mutex<Hb>, err: &str) -> bool {
    hb.lock().unwrap().failures += 1;
    throttled_log!(LOG_INTERVAL, warn, "Porta heartbeat failed: {}", err);
    true
}

pub(super) fn payload(sysinfo: fn() -> Value, version: &str) -> Payload {
    Payload {
        uuid: STANDARD.encode(get_uuid()),
        ver: get_version_number(version),
        strategy_rev: LocalConfig::get_option(STRATEGY_TIMESTAMP)
            .parse()
            .unwrap_or(0),
        sysinfo: with_presets(sysinfo(), version),
    }
}

/// The preset keys upstream adds to its sysinfo (`start_hbbs_sync_async` in
/// src/hbbs_http/sync.rs), minus `id` and `uuid`.
fn with_presets(mut v: Value, version: &str) -> Value {
    v["version"] = json!(version);
    for key in [
        keys::OPTION_PRESET_ADDRESS_BOOK_NAME,
        keys::OPTION_PRESET_ADDRESS_BOOK_TAG,
        keys::OPTION_PRESET_ADDRESS_BOOK_ALIAS,
        keys::OPTION_PRESET_ADDRESS_BOOK_PASSWORD,
        keys::OPTION_PRESET_ADDRESS_BOOK_NOTE,
    ] {
        let s = Config::get_option(key);
        if !s.is_empty() {
            v[key] = json!(s);
        }
    }
    for key in [
        keys::OPTION_PRESET_USERNAME,
        keys::OPTION_PRESET_STRATEGY_NAME,
        keys::OPTION_PRESET_DEVICE_GROUP_NAME,
    ] {
        let s = config::BUILTIN_SETTINGS
            .read()
            .unwrap()
            .get(key)
            .cloned()
            .unwrap_or_default();
        if !s.is_empty() {
            v[key] = json!(s);
        }
    }
    let device_username = Config::get_option(keys::OPTION_PRESET_DEVICE_USERNAME);
    if !device_username.is_empty() {
        v["username"] = json!(device_username);
    }
    let device_name = Config::get_option(keys::OPTION_PRESET_DEVICE_NAME);
    if !device_name.is_empty() {
        v["hostname"] = json!(device_name);
    }
    let note = Config::get_option(keys::OPTION_PRESET_NOTE);
    if !note.is_empty() {
        v[keys::OPTION_PRESET_NOTE] = json!(note);
    }
    v
}

pub(super) fn apply_strategy(rev: i64, options: &Map<String, Value>) {
    let mut current = Config::get_options();
    {
        let defaults = config::DEFAULT_SETTINGS.read().unwrap();
        merge_strategy(&mut current, &defaults, options);
    }
    Config::set_options(current);
    LocalConfig::set_option(STRATEGY_TIMESTAMP.to_owned(), rev.to_string());
    log::info!("Porta strategy updated (rev {})", rev);
}

/// Upstream `handle_config_options` (src/hbbs_http/sync.rs), except that keys starting with
/// `porta-` are Porta's own state and never taken from the server.
fn merge_strategy(
    options: &mut HashMap<String, String>,
    defaults: &HashMap<String, String>,
    incoming: &Map<String, Value>,
) {
    for (k, v) in incoming {
        let Some(v) = v.as_str() else {
            continue;
        };
        if k.starts_with("porta-") {
            continue;
        }
        // Priority: user config > default advanced options. Only when the default is also
        // empty, remove the user option (fall back to the built-in default).
        if v.is_empty() && defaults.get(k).map_or("", |v| v).is_empty() {
            options.remove(k);
        } else {
            options.insert(k.to_owned(), v.to_owned());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        super::tests::{signed, slot, unsigned, Fake, ROOT},
        *,
    };
    use hbb_common::anyhow::anyhow;

    fn payload() -> Payload {
        Payload {
            uuid: "dGVzdA==".to_owned(),
            ver: 1005010,
            strategy_rev: 7,
            sysinfo: json!({"hostname": "pc", "os": "Windows", "version": "1.5.1"}),
        }
    }

    async fn run(fake: &Fake, cap: &CapSlot, hb: &Mutex<Hb>) -> bool {
        tick(fake, cap, hb, ROOT, vec![], payload).await
    }

    /// Lets the next `tick` go out at once instead of waiting for its interval.
    fn due(hb: &Mutex<Hb>) {
        hb.lock().unwrap().last_attempt = None;
    }

    fn sent_json(fake: &Fake, i: usize) -> Value {
        serde_json::from_slice(&fake.sent.lock().unwrap()[i].1).unwrap()
    }

    #[test]
    fn embedded_sysinfo_matches_its_hash() {
        let p = payload();
        let alone = serde_json::to_vec(&p.sysinfo).unwrap();
        let hash = STANDARD.encode(Sha256::digest(&alone));
        let whole = String::from_utf8(body(&p, &[3], &hash, Some(&p.sysinfo))).unwrap();
        let alone = String::from_utf8(alone).unwrap();
        assert!(whole.contains(&format!(r#""sysinfo":{alone}"#)), "{whole}");
        let v: Value = serde_json::from_str(&whole).unwrap();
        assert_eq!(v["sysinfo_hash"], json!(hash));
        assert_eq!(v["conns"], json!([3]));
        assert_eq!(v["porta"], json!(env!("CARGO_PKG_VERSION")));
        assert!(v.get("id").is_none() && v.get("probes").is_none());
        let without = body(&p, &[], &hash, None);
        let v: Value = serde_json::from_slice(&without).unwrap();
        assert!(v.get("sysinfo").is_none() && v.get("conns").is_none());
    }

    #[test]
    fn backoff_sequence() {
        let secs: Vec<u64> = (1..=7).map(|f| interval(f, false).as_secs()).collect();
        assert_eq!(secs, [3, 6, 12, 24, 48, 60, 60]);
        assert_eq!(interval(0, true).as_secs(), 3);
        assert_eq!(interval(0, false).as_secs(), 15);
        assert_eq!(interval(40, false).as_secs(), 60);
    }

    #[test]
    fn strategy_merge_follows_upstream() {
        let mut options = HashMap::from([
            ("a".to_owned(), "1".to_owned()),
            ("b".to_owned(), "1".to_owned()),
            ("porta-api-caps".to_owned(), "keep".to_owned()),
        ]);
        let defaults = HashMap::from([("b".to_owned(), "Y".to_owned())]);
        let incoming = json!({"a": "", "b": "", "c": "3", "porta-api-caps": "", "porta-x": "1"});
        merge_strategy(&mut options, &defaults, incoming.as_object().unwrap());
        assert_eq!(
            options,
            HashMap::from([
                // Empty with an empty default: removed. Empty over a default: kept as "".
                ("b".to_owned(), "".to_owned()),
                ("c".to_owned(), "3".to_owned()),
                ("porta-api-caps".to_owned(), "keep".to_owned()),
            ])
        );
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn unknown_then_404_goes_legacy_and_rechecks() {
        let fake = Fake::default().script(vec![unsigned(404, ""), unsigned(404, "")]);
        let (cap, hb) = (slot("", Cap::Unknown), Mutex::new(Hb::default()));
        let before = Instant::now();
        assert!(!run(&fake, &cap, &hb).await);
        let Cap::Unsupported { recheck_at } = cap.lock().unwrap().1 else {
            panic!("not unsupported");
        };
        assert!(recheck_at >= before + Duration::from_secs(599));
        // select + mark_unsupported
        assert_eq!(fake.resets(), 2);
        // Before the recheck time nothing is sent.
        due(&hb);
        assert!(!run(&fake, &cap, &hb).await);
        assert_eq!(fake.sent.lock().unwrap().len(), 1);
        // After it, probed again.
        cap.lock().unwrap().1 = Cap::Unsupported {
            recheck_at: Instant::now(),
        };
        assert!(!run(&fake, &cap, &hb).await);
        assert_eq!(fake.sent.lock().unwrap().len(), 2);
        assert_eq!(fake.caps(), "");
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn unknown_then_2xx_without_api_goes_legacy() {
        let fake = Fake::default().script(vec![unsigned(200, "<html>maintenance</html>")]);
        let (cap, hb) = (slot("", Cap::Unknown), Mutex::new(Hb::default()));
        assert!(!run(&fake, &cap, &hb).await);
        assert!(matches!(cap.lock().unwrap().1, Cap::Unsupported { .. }));
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn unknown_then_failure_skips_without_legacy() {
        let ok = r#"{"api":1,"features":[],"time":1}"#;
        for reply in [
            Err(anyhow!("tls handshake")),
            unsigned(401, r#"{"error":"bad_auth"}"#),
            unsigned(503, ""),
            unsigned(200, ok),
        ] {
            let fake = Fake::default().script(vec![reply]);
            let (cap, hb) = (slot("", Cap::Unknown), Mutex::new(Hb::default()));
            assert!(run(&fake, &cap, &hb).await);
            assert_eq!(cap.lock().unwrap().1, Cap::Unknown);
            assert_eq!(hb.lock().unwrap().failures, 1);
            assert_eq!(fake.caps(), "");
        }
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn confirmed_root_stays_supported_on_404() {
        let fake = Fake {
            caps: Mutex::new(format!("{ROOT}\n")),
            ..Default::default()
        }
        .script(vec![unsigned(404, "")]);
        let (cap, hb) = (slot("", Cap::Unknown), Mutex::new(Hb::default()));
        assert!(run(&fake, &cap, &hb).await);
        assert_eq!(cap.lock().unwrap().1, Cap::Supported);
        assert_eq!(hb.lock().unwrap().failures, 1);
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn build_time_root_is_supported_without_probe() {
        let fake = Fake {
            default_root: ROOT.to_owned(),
            ..Default::default()
        }
        .script(vec![unsigned(404, "")]);
        let (cap, hb) = (slot("", Cap::Unknown), Mutex::new(Hb::default()));
        assert!(run(&fake, &cap, &hb).await);
        assert_eq!(cap.lock().unwrap().1, Cap::Supported);
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn success_applies_response() {
        let first = r#"{"api":1,"features":["udp-punch"],"time":1,"need_sysinfo":true,
            "strategy":{"rev":9,"options":{"relay-server":""}},"routing":{"rev":2}}"#;
        let second = r#"{"api":1,"features":[],"time":1}"#;
        let fake = Fake::default().script(vec![
            signed(200, first),
            signed(200, second),
            signed(200, second),
        ]);
        let (cap, hb) = (slot("", Cap::Unknown), Mutex::new(Hb::default()));

        assert!(run(&fake, &cap, &hb).await);
        assert_eq!(cap.lock().unwrap().1, Cap::Supported);
        assert_eq!(fake.caps(), format!("{ROOT}\nudp-punch"));
        assert!(sent_json(&fake, 0).get("sysinfo").is_some());
        let strategies = fake.strategies.lock().unwrap().clone();
        assert_eq!(strategies.len(), 1);
        assert_eq!(strategies[0].0, 9);

        // need_sysinfo was set: sent again even though the hash was accepted.
        due(&hb);
        assert!(run(&fake, &cap, &hb).await);
        assert!(sent_json(&fake, 1).get("sysinfo").is_some());
        // Features dropped by the server are dropped from the record.
        assert_eq!(fake.caps(), format!("{ROOT}\n"));

        // Accepted and not requested: only the hash goes.
        due(&hb);
        assert!(run(&fake, &cap, &hb).await);
        assert!(sent_json(&fake, 2).get("sysinfo").is_none());

        assert_eq!(
            *fake.heartbeat_ok.lock().unwrap(),
            vec![Some(json!({"rev": 2})), None, None]
        );
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn waits_for_interval_and_backs_off() {
        let fake = Fake::default().script(vec![unsigned(503, "")]);
        let (cap, hb) = (slot("", Cap::Unknown), Mutex::new(Hb::default()));
        assert!(run(&fake, &cap, &hb).await);
        // Not due yet: handled (no legacy reports), nothing sent.
        assert!(run(&fake, &cap, &hb).await);
        assert_eq!(fake.sent.lock().unwrap().len(), 1);
    }

    fn last_attempt_ago(hb: &Mutex<Hb>, secs: u64) {
        hb.lock().unwrap().last_attempt = Some(Instant::now() - Duration::from_secs(secs));
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn backoff_is_wired_into_tick() {
        let ok = r#"{"api":1,"features":[],"time":1}"#;
        let fake = Fake::default().script(vec![unsigned(503, ""), signed(200, ok)]);
        let (cap, hb) = (slot("", Cap::Unknown), Mutex::new(Hb::default()));
        assert!(run(&fake, &cap, &hb).await);
        assert!(fake.heartbeat_ok.lock().unwrap().is_empty());
        // One failure: the next try is 3 s later, not the idle 15 s.
        last_attempt_ago(&hb, 2);
        assert!(run(&fake, &cap, &hb).await);
        assert_eq!(fake.sent.lock().unwrap().len(), 1);
        last_attempt_ago(&hb, 4);
        assert!(run(&fake, &cap, &hb).await);
        assert_eq!(fake.sent.lock().unwrap().len(), 2);
        assert_eq!(hb.lock().unwrap().failures, 0);
        assert_eq!(fake.heartbeat_ok.lock().unwrap().len(), 1);
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn new_root_clears_heartbeat_state() {
        let ok = r#"{"api":1,"features":[],"time":1}"#;
        let fake =
            Fake::default().script(vec![signed(200, ok), unsigned(503, ""), signed(200, ok)]);
        let (cap, hb) = (slot("", Cap::Unknown), Mutex::new(Hb::default()));
        assert!(run(&fake, &cap, &hb).await);
        due(&hb);
        assert!(run(&fake, &cap, &hb).await);
        assert_eq!(hb.lock().unwrap().failures, 1);
        assert!(!hb.lock().unwrap().confirmed_hash.is_empty());
        // Another root goes out at once, with sysinfo, and without the old failure count.
        let other = "http://other.test:21114";
        assert!(tick(&fake, &cap, &hb, other, vec![], payload).await);
        assert_eq!(fake.sent.lock().unwrap().len(), 3);
        assert!(sent_json(&fake, 2).get("sysinfo").is_some());
        assert_eq!(hb.lock().unwrap().failures, 0);
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn invalid_key_fails_closed() {
        let ok = r#"{"api":1,"features":["udp-punch"],"time":1,
            "strategy":{"rev":9,"options":{"relay-server":""}},"routing":{"rev":2}}"#;
        let fake = Fake {
            bad_key: true,
            ..Default::default()
        }
        .script(vec![signed(200, ok)]);
        let (cap, hb) = (slot("", Cap::Unknown), Mutex::new(Hb::default()));
        assert!(run(&fake, &cap, &hb).await);
        assert_eq!(cap.lock().unwrap().1, Cap::Unknown);
        assert_eq!(hb.lock().unwrap().failures, 1);
        assert_eq!(fake.caps(), "");
        assert!(fake.strategies.lock().unwrap().is_empty());
        assert!(fake.heartbeat_ok.lock().unwrap().is_empty());
        assert!(fake.times_set.lock().unwrap().is_empty());
    }
}
