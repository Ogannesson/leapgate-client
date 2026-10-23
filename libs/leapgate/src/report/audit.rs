//! `POST /api/leapgate/v1/audit/{conn,file,alarm}`: the controlled side's audit records.

use super::{
    exchange, is_supported, mark_supported, mark_unsupported, select, Cap, CapSlot, Env, Reply,
};
use hbb_common::{
    anyhow::anyhow,
    log,
    serde_json::{self, Value},
    ResultType,
};
use std::time::{Duration, Instant};

/// Upstream's retry table in `post_audit_async`: the server remembers a record's nonce for five
/// minutes, so retries stop by elapsed time, well inside that window.
const RETRY_DEADLINE: Duration = Duration::from_secs(120);
const RETRY_BACKOFF_SECS: [u64; 2] = [10, 30];

/// `None`: the server has no Leapgate API, send this record the legacy way.
pub(super) async fn send<E: Env>(
    env: &E,
    cap: &CapSlot,
    root: &str,
    typ: &str,
    v: &Value,
) -> Option<ResultType<String>> {
    select(env, cap, root);
    if matches!(cap.lock().unwrap().1, Cap::Unsupported { .. }) {
        return None;
    }
    // The device is identified by the signature header; the body carries no `id`.
    let mut v = v.clone();
    if let Some(o) = v.as_object_mut() {
        o.remove("id");
    }
    let body = serde_json::to_vec(&v).unwrap_or_default();
    let endpoint = format!("audit/{typ}");
    let started = Instant::now();
    let mut attempt = 0usize;
    loop {
        attempt += 1;
        // Every attempt is signed afresh by `exchange`; the nonce in the body stays the same.
        let (retryable, err) = match exchange(env, &endpoint, &body).await {
            Reply::Ok(_) => {
                if !is_supported(cap, root) {
                    mark_supported(env, cap, root, None);
                }
                return Some(Ok(String::new()));
            }
            Reply::NoApi(status) if !is_supported(cap, root) => {
                mark_unsupported(env, cap, root, status);
                return None;
            }
            // On a confirmed root a 2xx without `api` is a proxy's maintenance page: try again.
            Reply::NoApi(status) if (200..300).contains(&status) => {
                (true, format!("status {status} without api"))
            }
            Reply::NoApi(status) | Reply::Rejected(status) => (false, format!("status {status}")),
            Reply::Failed(e) => (true, e),
        };
        let elapsed = started.elapsed();
        if !retryable || attempt > RETRY_BACKOFF_SECS.len() || elapsed >= RETRY_DEADLINE {
            log::error!(
                "Leapgate audit post dropped (attempt {}, {:?} elapsed): {}",
                attempt,
                elapsed,
                err
            );
            return Some(Err(anyhow!(err)));
        }
        log::warn!("Leapgate audit post failed (attempt {}): {}", attempt, err);
        env.sleep(Duration::from_secs(RETRY_BACKOFF_SECS[attempt - 1]))
            .await;
        if started.elapsed() >= RETRY_DEADLINE {
            log::error!(
                "Leapgate audit post dropped (attempt {}, deadline passed during backoff): {}",
                attempt,
                err
            );
            return Some(Err(anyhow!(err)));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        super::tests::{signed, slot, unsigned, Fake, ROOT},
        *,
    };
    use hbb_common::serde_json::json;
    use std::sync::Mutex;

    fn record() -> Value {
        json!({"id": "123456789", "uuid": "dGVzdA==", "conn_id": 1, "nonce": "n1"})
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn unknown_then_404_hands_record_to_legacy() {
        let fake = Fake::default().script(vec![unsigned(404, "")]);
        let cap = slot("", Cap::Unknown);
        assert!(send(&fake, &cap, ROOT, "conn", &record()).await.is_none());
        assert!(matches!(cap.lock().unwrap().1, Cap::Unsupported { .. }));
        // Unsupported: not even tried.
        assert!(send(&fake, &cap, ROOT, "conn", &record()).await.is_none());
        assert_eq!(fake.sent.lock().unwrap().len(), 1);
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn success_confirms_root_and_strips_id() {
        let fake = Fake {
            caps: Mutex::new(format!("{ROOT}\nudp-punch")),
            ..Default::default()
        }
        .script(vec![signed(200, r#"{"api":1}"#)]);
        let cap = slot("", Cap::Unknown);
        // The record's root is persisted, so it starts supported and keeps its features.
        let res = send(&fake, &cap, ROOT, "file", &record()).await;
        assert_eq!(res.map(|r| r.ok()), Some(Some(String::new())));
        assert_eq!(fake.caps(), format!("{ROOT}\nudp-punch"));
        let (endpoint, body) = fake.sent.lock().unwrap()[0].clone();
        assert_eq!(endpoint, "audit/file");
        let body: Value = serde_json::from_slice(&body).unwrap();
        assert!(body.get("id").is_none());
        assert_eq!(body["nonce"], json!("n1"));

        // An unknown root confirmed by an audit is recorded with no features.
        let fake = Fake::default().script(vec![signed(200, r#"{"api":1}"#)]);
        let cap = slot("", Cap::Unknown);
        assert!(send(&fake, &cap, ROOT, "conn", &record()).await.is_some());
        assert_eq!(cap.lock().unwrap().1, Cap::Supported);
        assert_eq!(fake.caps(), format!("{ROOT}\n"));
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn confirmed_root_gives_up_on_404_and_400() {
        for status in [404, 400] {
            let fake = Fake {
                default_root: ROOT.to_owned(),
                ..Default::default()
            }
            .script(vec![unsigned(status, "")]);
            let cap = slot("", Cap::Unknown);
            let res = send(&fake, &cap, ROOT, "alarm", &record()).await;
            assert!(matches!(res, Some(Err(_))));
            assert_eq!(fake.sent.lock().unwrap().len(), 1);
        }
    }

    fn confirmed() -> Fake {
        Fake {
            default_root: ROOT.to_owned(),
            ..Default::default()
        }
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn confirmed_root_retries_maintenance_page() {
        let fake = confirmed().script(vec![
            unsigned(200, "<html>maintenance</html>"),
            signed(200, r#"{"api":1}"#),
        ]);
        let cap = slot("", Cap::Unknown);
        let res = send(&fake, &cap, ROOT, "conn", &record()).await;
        assert_eq!(res.map(|r| r.ok()), Some(Some(String::new())));
        assert_eq!(fake.sent.lock().unwrap().len(), 2);
        assert_eq!(cap.lock().unwrap().1, Cap::Supported);
    }

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn retries_follow_upstream_table() {
        let fake = confirmed().script(vec![
            unsigned(503, ""),
            unsigned(503, ""),
            unsigned(503, ""),
        ]);
        let cap = slot("", Cap::Unknown);
        let res = send(&fake, &cap, ROOT, "conn", &record()).await;
        assert!(matches!(res, Some(Err(_))));
        assert_eq!(fake.sent.lock().unwrap().len(), 3);
        assert_eq!(
            *fake.sleeps.lock().unwrap(),
            [Duration::from_secs(10), Duration::from_secs(30)]
        );

        let fake = confirmed().script(vec![unsigned(503, ""), signed(200, r#"{"api":1}"#)]);
        let cap = slot("", Cap::Unknown);
        let res = send(&fake, &cap, ROOT, "conn", &record()).await;
        assert_eq!(res.map(|r| r.ok()), Some(Some(String::new())));
        assert_eq!(*fake.sleeps.lock().unwrap(), [Duration::from_secs(10)]);
    }
}
