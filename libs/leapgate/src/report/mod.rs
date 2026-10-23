//! Reports to a Leapgate server over `/api/leapgate/v1/`: heartbeat with sysinfo, and the controlled
//! side's audits, each signed with the device key. Upstream calls in from two hooks, `tick` in
//! the hbbs sync loop and `audit` in `post_audit_async`; when they return `false` / `None`,
//! upstream's legacy reports run unchanged.
//!
//! Capability per API root: unknown, supported or unsupported (contract 01 §2.5). Only a 404 /
//! 405, or a 2xx that is not a Leapgate answer, on a root not yet confirmed sends the reports back
//! to the legacy path: that path is unsigned, may accept invalid certificates and applies
//! whatever options the heartbeat hands down, so nothing else may downgrade to it.

mod audit;
mod heartbeat;

use crate::{
    api::{self, Resp},
    brand, route, sign,
};
use base::config::keys;
use hbb_common::{
    config::{self, Config},
    serde_json::{self, Map, Value},
    sodiumoxide::crypto::sign::PublicKey,
    throttled_log, tokio, ResultType,
};
use std::{
    sync::Mutex,
    time::{Duration, Instant},
};

/// `<API root>\n<feature,feature,...>`, written by the service process only. A Config option
/// rather than LocalConfig so the UI process gets it through the option sync.
const CAPS_KEY: &str = "leapgate-api-caps";
const RECHECK: Duration = Duration::from_secs(600);
const LOG_INTERVAL: Duration = Duration::from_secs(60);
/// A 2xx's `time` moves the clock only when it is this far off (seconds).
const MAX_SKEW: i64 = 30;
/// The 401 `error` codes leapgate-server sends (contract 01 §2.6).
const AUTH_ERRORS: [&str; 5] = [
    "bad_auth",
    "stale_time",
    "replay",
    "unknown_device",
    "bad_signature",
];

#[derive(Clone, Copy, PartialEq, Debug)]
enum Cap {
    Unknown,
    Supported,
    Unsupported { recheck_at: Instant },
}

/// The API root the state belongs to, and the state.
type CapSlot = Mutex<(String, Cap)>;

/// Only meaningful in the service process, where the reports are sent.
static CAP: CapSlot = Mutex::new((String::new(), Cap::Unknown));

/// Hook in the hbbs sync loop, after upstream's empty-address and `stop-service` checks.
/// `true`: this round is handled (sent, or skipped while backing off), skip upstream's reports.
pub async fn tick(
    url: &str,
    sysinfo: fn() -> Value,
    alive_conns: fn() -> Vec<i32>,
    version: &str,
) -> bool {
    let Some(root) = heartbeat_root(url, &api_root()) else {
        return false;
    };
    heartbeat::tick(
        &Live { root },
        &CAP,
        &heartbeat::HB,
        root,
        alive_conns(),
        || heartbeat::payload(sysinfo, version),
    )
    .await
}

/// Hook at the top of `post_audit_async`. `None`: send it the legacy way.
pub async fn audit(url: &str, v: &Value) -> Option<ResultType<String>> {
    let (root, typ) = audit_target(url, &api_root())?;
    audit::send(&Live { root }, &CAP, root, typ, v).await
}

/// The current API root is a confirmed Leapgate server, or the address the build was configured
/// with. Reads the persisted record, so it holds in any process and right after start.
pub fn server_is_leapgate() -> bool {
    is_leapgate(&api_root(), &Config::get_option(CAPS_KEY), &default_root())
}

/// The current API root is a confirmed Leapgate server that announced `name`.
pub fn has_feature(name: &str) -> bool {
    feature_in(&api_root(), &Config::get_option(CAPS_KEY), name)
}

/// Upstream `get_api_server(api-server, custom-rendezvous-server)` recomputed, since this crate
/// cannot call it; without the Windows license-in-exe-name branch. Keep the two in step.
pub(crate) fn api_root() -> String {
    if Config::no_register_device() {
        return String::new();
    }
    let prod = config::PROD_RENDEZVOUS_SERVER.read().unwrap().clone();
    root_from(
        &Config::get_option("api-server"),
        &Config::get_option("custom-rendezvous-server"),
        &prod,
        brand::default_api_server(),
        allow_https_21114(),
    )
}

fn allow_https_21114() -> bool {
    config::BUILTIN_SETTINGS
        .read()
        .unwrap()
        .get(keys::OPTION_ALLOW_HTTPS_21114)
        .map_or(false, |v| v == "Y")
}

fn root_from(api: &str, custom: &str, prod: &str, default: String, allow_21114: bool) -> String {
    let res = if !api.is_empty() {
        api.to_owned()
    } else {
        let s0 = if custom.is_empty() { prod } else { custom };
        if s0.is_empty() {
            default
        } else {
            brand::api_from_rendezvous(s0)
        }
    };
    normalize(res, allow_21114)
}

fn normalize(mut res: String, allow_21114: bool) -> String {
    if res.ends_with('/') {
        res.pop();
    }
    if res.starts_with("https") && res.ends_with(":21114") && !allow_21114 {
        return res.replace(":21114", "");
    }
    res
}

/// The API address decided at build time, which counts as supported without probing.
fn default_root() -> String {
    normalize(brand::default_api_server(), allow_https_21114())
}

/// The API root in upstream's heartbeat URL (`{root}/api/heartbeat`).
fn heartbeat_root<'a>(url: &'a str, api_root: &str) -> Option<&'a str> {
    checked_root(url.strip_suffix("/api/heartbeat")?, api_root)
}

/// The API root and record type in upstream's audit URL (`{root}/api/audit/{typ}`).
fn audit_target<'a>(url: &'a str, api_root: &str) -> Option<(&'a str, &'a str)> {
    let (root, typ) = url.rsplit_once("/api/audit/")?;
    Some((checked_root(root, api_root)?, typ))
}

/// `root`, provided it is the one `api_root` computes: the capability record is read against
/// `api_root`, so both sides must mean the same address.
fn checked_root<'a>(root: &'a str, api_root: &str) -> Option<&'a str> {
    if root != api_root {
        throttled_log!(
            LOG_INTERVAL,
            warn,
            "leapgate report: api root mismatch, using legacy reports"
        );
        return None;
    }
    Some(root)
}

fn parse_caps(v: &str) -> Option<(&str, Vec<&str>)> {
    let (root, features) = v.split_once('\n')?;
    Some((
        root,
        features.split(',').filter(|f| !f.is_empty()).collect(),
    ))
}

fn caps_value(root: &str, features: &[String]) -> String {
    format!("{root}\n{}", features.join(","))
}

fn is_leapgate(root: &str, caps: &str, default_root: &str) -> bool {
    !root.is_empty() && (root == default_root || parse_caps(caps).map_or(false, |(r, _)| r == root))
}

fn feature_in(root: &str, caps: &str, name: &str) -> bool {
    !root.is_empty() && parse_caps(caps).map_or(false, |(r, f)| r == root && f.contains(&name))
}

/// Everything the report logic reads or changes outside its own state, so the tests run
/// without a server and without touching the real config.
trait Env {
    async fn send(&self, endpoint: &str, body: Vec<u8>) -> ResultType<(Resp, [u8; 64])>;
    fn server_pk(&self) -> Result<Option<PublicKey>, ()>;
    fn caps(&self) -> String;
    fn set_caps(&self, v: String);
    fn default_root(&self) -> String;
    fn route_reset(&self);
    fn route_heartbeat_ok(&self, routing: Option<&Value>);
    fn apply_strategy(&self, rev: i64, options: &Map<String, Value>);
    fn clock_skew(&self, t: i64) -> i64;
    fn set_server_time(&self, t: i64);
    async fn sleep(&self, d: Duration);
}

struct Live<'a> {
    root: &'a str,
}

impl Env for Live<'_> {
    async fn send(&self, endpoint: &str, body: Vec<u8>) -> ResultType<(Resp, [u8; 64])> {
        api::post(self.root, endpoint, body).await
    }

    fn server_pk(&self) -> Result<Option<PublicKey>, ()> {
        sign::server_pk()
    }

    fn caps(&self) -> String {
        Config::get_option(CAPS_KEY)
    }

    fn set_caps(&self, v: String) {
        Config::set_option(CAPS_KEY.to_owned(), v);
    }

    fn default_root(&self) -> String {
        default_root()
    }

    fn route_reset(&self) {
        route::reset();
    }

    fn route_heartbeat_ok(&self, routing: Option<&Value>) {
        route::on_heartbeat_ok(routing);
    }

    fn apply_strategy(&self, rev: i64, options: &Map<String, Value>) {
        heartbeat::apply_strategy(rev, options);
    }

    fn clock_skew(&self, t: i64) -> i64 {
        sign::clock_skew(t)
    }

    fn set_server_time(&self, t: i64) {
        sign::set_server_time(t);
    }

    async fn sleep(&self, d: Duration) {
        tokio::time::sleep(d).await;
    }
}

/// Points the state at `root`. A different root starts over: supported if it is the
/// persisted root or the build-time address, unknown otherwise.
fn select<E: Env>(env: &E, cap: &CapSlot, root: &str) {
    let mut slot = cap.lock().unwrap();
    if slot.0 == root {
        return;
    }
    let state = if is_leapgate(root, &env.caps(), &env.default_root()) {
        Cap::Supported
    } else {
        Cap::Unknown
    };
    *slot = (root.to_owned(), state);
    drop(slot);
    env.route_reset();
}

fn is_supported(cap: &CapSlot, root: &str) -> bool {
    let slot = cap.lock().unwrap();
    slot.0 == root && slot.1 == Cap::Supported
}

/// `features`: what the heartbeat announced; `None` keeps the persisted ones for this root.
fn mark_supported<E: Env>(env: &E, cap: &CapSlot, root: &str, features: Option<Vec<String>>) {
    let was = {
        let mut slot = cap.lock().unwrap();
        if slot.0 != root {
            return;
        }
        std::mem::replace(&mut slot.1, Cap::Supported)
    };
    let caps = env.caps();
    let features = features.unwrap_or_else(|| match parse_caps(&caps) {
        Some((r, f)) if r == root => f.into_iter().map(str::to_owned).collect(),
        _ => Vec::new(),
    });
    // Compare the whole value, not just the features: after the record was cleared, empty
    // features would otherwise look unchanged and never be written back.
    let v = caps_value(root, &features);
    if v != caps {
        env.set_caps(v);
    }
    if was != Cap::Supported {
        throttled_log!(
            LOG_INTERVAL,
            info,
            "leapgate report: {} supports Leapgate API, features [{}]",
            root,
            features.join(",")
        );
    }
}

fn mark_unsupported<E: Env>(env: &E, cap: &CapSlot, root: &str, status: u16) {
    {
        let mut slot = cap.lock().unwrap();
        if slot.0 != root {
            return;
        }
        slot.1 = Cap::Unsupported {
            recheck_at: Instant::now() + RECHECK,
        };
    }
    env.route_reset();
    throttled_log!(
        LOG_INTERVAL,
        info,
        "leapgate report: {} has no Leapgate API ({}), using legacy reports",
        root,
        status
    );
}

enum Reply {
    /// A 2xx JSON object with `api`, its signature verified when a key is configured.
    Ok(Map<String, Value>),
    /// 404 / 405, or a 2xx that is not a Leapgate answer (a proxy's page for unknown paths). Not
    /// signature-checked: it is as easy to forge as a 404. Means "no Leapgate API" only on a root
    /// not yet confirmed.
    NoApi(u16),
    /// 400 / 413: sending the same request again cannot help.
    Rejected(u16),
    /// Transport or TLS error, 3xx, 401, 429, 5xx, failed signature check.
    Failed(String),
}

/// One request, re-signed and sent once more when a verified 401 brings the server's time.
async fn exchange<E: Env>(env: &E, endpoint: &str, body: &[u8]) -> Reply {
    let pk = env.server_pk();
    let mut resent = false;
    loop {
        let (resp, req_sig) = match env.send(endpoint, body.to_vec()).await {
            Ok(r) => r,
            Err(e) => return Reply::Failed(e.to_string()),
        };
        let verified = match &pk {
            Ok(None) => true,
            Ok(Some(pk)) => {
                sign::verify_server_sig(pk, &req_sig, &resp.body, resp.server_sig.as_deref())
            }
            Err(()) => false,
        };
        match resp.status {
            200..=299 => {
                let Ok(Value::Object(map)) = serde_json::from_slice(&resp.body) else {
                    return Reply::NoApi(resp.status);
                };
                if !map.contains_key("api") {
                    return Reply::NoApi(resp.status);
                }
                if !verified {
                    throttled_log!(
                        LOG_INTERVAL,
                        warn,
                        "leapgate report: server signature check failed"
                    );
                    return Reply::Failed("server signature check failed".to_owned());
                }
                // Only a real skew moves the clock. Following every response would let the
                // stamps drift back and forth by the request latency, and the server's replay
                // check accepts a device's stamps only down to 30 s below the newest it saw.
                if let Some(t) = map.get("time").and_then(Value::as_i64) {
                    if env.clock_skew(t).abs() > MAX_SKEW {
                        env.set_server_time(t);
                    }
                }
                return Reply::Ok(map);
            }
            401 => {
                let v = serde_json::from_slice::<Value>(&resp.body).ok();
                // Only a code from the fixed set reaches the log, signed or not.
                let code = v
                    .as_ref()
                    .and_then(|v| v.get("error")?.as_str())
                    .and_then(|c| AUTH_ERRORS.iter().find(|&&e| e == c))
                    .copied()
                    .unwrap_or("other");
                if !verified {
                    // `bad_auth` is never signed: the server could not parse the request's
                    // signature to bind its own to.
                    if code != "bad_auth" {
                        throttled_log!(
                            LOG_INTERVAL,
                            warn,
                            "leapgate report: server signature check failed"
                        );
                    }
                    return Reply::Failed(format!("status 401 {code}"));
                }
                if let Some(t) = v.as_ref().and_then(|v| v.get("time")?.as_i64()) {
                    env.set_server_time(t);
                    if !resent {
                        throttled_log!(
                            LOG_INTERVAL,
                            info,
                            "leapgate report: 401 {}, clock offset now {}s",
                            code,
                            sign::clock_offset()
                        );
                        resent = true;
                        continue;
                    }
                }
                return Reply::Failed(format!("status 401 {code}"));
            }
            404 | 405 => return Reply::NoApi(resp.status),
            400 | 413 => return Reply::Rejected(resp.status),
            status => return Reply::Failed(format!("status {status}")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sign::tests::{server_keys, server_sign};
    use hbb_common::anyhow::anyhow;
    use std::collections::VecDeque;

    pub(super) const ROOT: &str = "http://leapgate.test:21114";
    pub(super) const REQ_SIG: [u8; 64] = [5; 64];

    #[derive(Default)]
    pub(super) struct Fake {
        pub replies: Mutex<VecDeque<ResultType<(Resp, [u8; 64])>>>,
        pub sent: Mutex<Vec<(String, Vec<u8>)>>,
        pub keyless: bool,
        /// A key is configured but is not a valid public key.
        pub bad_key: bool,
        pub caps: Mutex<String>,
        pub default_root: String,
        pub resets: Mutex<usize>,
        pub heartbeat_ok: Mutex<Vec<Option<Value>>>,
        pub strategies: Mutex<Vec<(i64, Map<String, Value>)>>,
        /// The time requests are stamped with.
        pub clock: Mutex<i64>,
        pub times_set: Mutex<Vec<i64>>,
        pub sleeps: Mutex<Vec<Duration>>,
    }

    impl Fake {
        pub fn script(self, replies: Vec<ResultType<(Resp, [u8; 64])>>) -> Self {
            *self.replies.lock().unwrap() = replies.into();
            self
        }
        pub fn resets(&self) -> usize {
            *self.resets.lock().unwrap()
        }
    }

    impl Env for Fake {
        async fn send(&self, endpoint: &str, body: Vec<u8>) -> ResultType<(Resp, [u8; 64])> {
            self.sent.lock().unwrap().push((endpoint.to_owned(), body));
            self.replies
                .lock()
                .unwrap()
                .pop_front()
                .unwrap_or_else(|| Err(anyhow!("no reply scripted")))
        }
        fn server_pk(&self) -> Result<Option<PublicKey>, ()> {
            if self.bad_key {
                return Err(());
            }
            Ok((!self.keyless).then(|| server_keys().0))
        }
        fn caps(&self) -> String {
            self.caps.lock().unwrap().clone()
        }
        fn set_caps(&self, v: String) {
            *self.caps.lock().unwrap() = v;
        }
        fn default_root(&self) -> String {
            self.default_root.clone()
        }
        fn route_reset(&self) {
            *self.resets.lock().unwrap() += 1;
        }
        fn route_heartbeat_ok(&self, routing: Option<&Value>) {
            self.heartbeat_ok.lock().unwrap().push(routing.cloned());
        }
        fn apply_strategy(&self, rev: i64, options: &Map<String, Value>) {
            self.strategies.lock().unwrap().push((rev, options.clone()));
        }
        fn clock_skew(&self, t: i64) -> i64 {
            t - *self.clock.lock().unwrap()
        }
        fn set_server_time(&self, t: i64) {
            *self.clock.lock().unwrap() = t;
            self.times_set.lock().unwrap().push(t);
        }
        async fn sleep(&self, d: Duration) {
            self.sleeps.lock().unwrap().push(d);
        }
    }

    /// A 2xx with a valid server signature.
    pub(super) fn signed(status: u16, body: &str) -> ResultType<(Resp, [u8; 64])> {
        let server_sig = Some(server_sign(&REQ_SIG, body.as_bytes()));
        Ok((
            Resp {
                status,
                body: body.as_bytes().to_vec(),
                server_sig,
            },
            REQ_SIG,
        ))
    }

    pub(super) fn unsigned(status: u16, body: &str) -> ResultType<(Resp, [u8; 64])> {
        Ok((
            Resp {
                status,
                body: body.as_bytes().to_vec(),
                server_sig: None,
            },
            REQ_SIG,
        ))
    }

    pub(super) fn slot(root: &str, cap: Cap) -> CapSlot {
        Mutex::new((root.to_owned(), cap))
    }

    #[test]
    fn caps_format() {
        let v = caps_value(ROOT, &["udp-punch".to_owned(), "x".to_owned()]);
        assert_eq!(v, format!("{ROOT}\nudp-punch,x"));
        assert_eq!(parse_caps(&v), Some((ROOT, vec!["udp-punch", "x"])));
        assert_eq!(parse_caps(&format!("{ROOT}\n")), Some((ROOT, vec![])));
        assert_eq!(parse_caps(ROOT), None);
    }

    #[test]
    fn answers_from_persisted_record() {
        let caps = format!("{ROOT}\nudp-punch");
        assert!(is_leapgate(ROOT, &caps, ""));
        assert!(feature_in(ROOT, &caps, "udp-punch"));
        assert!(!feature_in(ROOT, &caps, "other"));
        // The record is for another root.
        assert!(!is_leapgate("http://other:21114", &caps, ""));
        assert!(!feature_in("http://other:21114", &caps, "udp-punch"));
        // Build-time address without a record yet: Leapgate, but no features known.
        assert!(is_leapgate(ROOT, "", ROOT));
        assert!(!feature_in(ROOT, "", "udp-punch"));
        assert!(!is_leapgate("", "", ""));
    }

    #[test]
    fn hook_urls_split_against_api_root() {
        let hb = "http://leapgate.test:21114/api/heartbeat";
        assert_eq!(heartbeat_root(hb, ROOT), Some(ROOT));
        assert_eq!(heartbeat_root(hb, "https://leapgate.test"), None);
        assert_eq!(
            heartbeat_root("http://leapgate.test:21114/api/sysinfo", ROOT),
            None
        );
        let au = "http://leapgate.test:21114/api/audit/conn";
        assert_eq!(audit_target(au, ROOT), Some((ROOT, "conn")));
        assert_eq!(
            audit_target(
                "https://leapgate.test/api/audit/alarm",
                "https://leapgate.test"
            ),
            Some(("https://leapgate.test", "alarm"))
        );
        assert_eq!(audit_target(au, "https://leapgate.test"), None);
        assert_eq!(
            audit_target("http://leapgate.test:21114/api/heartbeat", ROOT),
            None
        );
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn clock_follows_verified_times_only() {
        let stale = r#"{"error":"stale_time","message":"","time":1761200000}"#;
        let ok_at = |t: i64| format!(r#"{{"api":1,"features":[],"time":{t}}}"#);

        // A signed 401 sets the clock and the request goes again; the 2xx after it agrees.
        let fake =
            Fake::default().script(vec![signed(401, stale), signed(200, &ok_at(1761200000))]);
        assert!(matches!(
            exchange(&fake, "heartbeat", b"{}").await,
            Reply::Ok(_)
        ));
        assert_eq!(*fake.times_set.lock().unwrap(), [1761200000]);
        assert_eq!(fake.sent.lock().unwrap().len(), 2);

        // Unsigned 401, and an unsigned 2xx while a key is configured: ignored.
        for reply in [unsigned(401, stale), unsigned(200, &ok_at(1761200000))] {
            let fake = Fake::default().script(vec![reply]);
            exchange(&fake, "heartbeat", b"{}").await;
            assert!(fake.times_set.lock().unwrap().is_empty());
        }

        // A signed 2xx moves the clock only when more than 30 s off.
        let fake = Fake::default().script(vec![signed(200, &ok_at(30)), signed(200, &ok_at(-31))]);
        exchange(&fake, "heartbeat", b"{}").await;
        assert!(fake.times_set.lock().unwrap().is_empty());
        exchange(&fake, "heartbeat", b"{}").await;
        assert_eq!(*fake.times_set.lock().unwrap(), [-31]);
    }

    /// Expected values worked out by hand from upstream `get_api_server` / `get_api_server_`.
    #[test]
    fn api_root_matches_upstream() {
        let d = || "http://built.in:21114".to_owned();
        assert_eq!(
            root_from("https://api.example/", "rs.example", "", d(), false),
            "https://api.example"
        );
        assert_eq!(
            root_from("", "rs.example", "", d(), false),
            "http://rs.example:21114"
        );
        assert_eq!(
            root_from("", "rs.example:31116", "", d(), false),
            "http://rs.example:31114"
        );
        assert_eq!(
            root_from("", "1.2.3.4:21116", "", d(), false),
            "http://1.2.3.4:21114"
        );
        assert_eq!(
            root_from("", "2001:db8::1", "", d(), false),
            "http://[2001:db8::1]:21114"
        );
        assert_eq!(
            root_from("", "[2001:db8::1]:21116", "", d(), false),
            "http://[2001:db8::1]:21114"
        );
        assert_eq!(
            root_from("", "", "prod.example", d(), false),
            "http://prod.example:21114"
        );
        assert_eq!(root_from("", "", "", d(), false), "http://built.in:21114");
        assert_eq!(root_from("", "", "", String::new(), false), "");
        assert_eq!(
            root_from("https://api.example:21114", "", "", d(), false),
            "https://api.example"
        );
        assert_eq!(
            root_from("https://api.example:21114", "", "", d(), true),
            "https://api.example:21114"
        );
        assert_eq!(
            root_from("http://api.example:21114/", "", "", d(), false),
            "http://api.example:21114"
        );
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn exchange_classifies_replies() {
        let ok = r#"{"api":1,"features":[],"time":1}"#;
        let cases = [
            (signed(200, ok), "ok"),
            (unsigned(200, ok), "failed"),
            (signed(200, "<html>"), "noapi"),
            (unsigned(200, r#"{"x":1}"#), "noapi"),
            (unsigned(404, ""), "noapi"),
            (unsigned(405, ""), "noapi"),
            (unsigned(400, ""), "rejected"),
            (unsigned(413, ""), "rejected"),
            (unsigned(429, ""), "failed"),
            (unsigned(503, ""), "failed"),
            (unsigned(401, r#"{"error":"bad_auth"}"#), "failed"),
            (Err(anyhow!("tls")), "failed"),
        ];
        for (reply, want) in cases {
            let fake = Fake::default().script(vec![reply]);
            let got = match exchange(&fake, "heartbeat", b"{}").await {
                Reply::Ok(_) => "ok",
                Reply::NoApi(_) => "noapi",
                Reply::Rejected(_) => "rejected",
                Reply::Failed(_) => "failed",
            };
            assert_eq!(got, want);
        }
        // Without a key nothing is verified.
        let fake = Fake {
            keyless: true,
            ..Default::default()
        }
        .script(vec![unsigned(200, ok)]);
        assert!(matches!(
            exchange(&fake, "heartbeat", b"{}").await,
            Reply::Ok(_)
        ));
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn signed_401_resends_once() {
        let stale = r#"{"error":"stale_time","message":"","time":1761200000}"#;
        let fake = Fake::default().script(vec![
            signed(401, stale),
            signed(200, r#"{"api":1,"features":[],"time":1761200000}"#),
        ]);
        assert!(matches!(
            exchange(&fake, "heartbeat", b"{}").await,
            Reply::Ok(_)
        ));
        assert_eq!(fake.sent.lock().unwrap().len(), 2);

        let fake = Fake::default().script(vec![signed(401, stale), signed(401, stale)]);
        assert!(matches!(
            exchange(&fake, "heartbeat", b"{}").await,
            Reply::Failed(_)
        ));
        assert_eq!(fake.sent.lock().unwrap().len(), 2);

        // An unsigned 401 is not trusted for the time and not resent.
        let fake = Fake::default().script(vec![unsigned(401, stale)]);
        assert!(matches!(
            exchange(&fake, "heartbeat", b"{}").await,
            Reply::Failed(_)
        ));
        assert_eq!(fake.sent.lock().unwrap().len(), 1);
    }

    #[test]
    fn new_root_resets_state() {
        let cap = slot("", Cap::Unknown);
        let fake = Fake {
            default_root: "http://built.in:21114".to_owned(),
            ..Default::default()
        };
        select(&fake, &cap, ROOT);
        assert_eq!(cap.lock().unwrap().1, Cap::Unknown);
        assert_eq!(fake.resets(), 1);
        select(&fake, &cap, ROOT);
        assert_eq!(fake.resets(), 1);
        // The build-time address is supported without probing.
        select(&fake, &cap, "http://built.in:21114");
        assert_eq!(cap.lock().unwrap().1, Cap::Supported);
        assert_eq!(fake.resets(), 2);
        // So is the persisted root.
        fake.set_caps(format!("{ROOT}\n"));
        select(&fake, &cap, ROOT);
        assert_eq!(cap.lock().unwrap().1, Cap::Supported);
        assert_eq!(fake.resets(), 3);
    }
}
