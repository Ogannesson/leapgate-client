use super::*;
use hbb_common::{
    config::{Ab, AbEntry, Group},
    tokio::{
        self,
        io::{AsyncReadExt, AsyncWriteExt},
        net::TcpListener,
    },
};
use std::sync::{Arc, Mutex};

#[derive(Default)]
pub(super) struct Mem {
    options: Mutex<HashMap<String, String>>,
    ab: Mutex<Option<Ab>>,
    group: Mutex<Option<Group>>,
}

impl Store for Mem {
    fn option(&self, key: &str) -> String {
        self.options
            .lock()
            .unwrap()
            .get(key)
            .cloned()
            .unwrap_or_default()
    }
    fn set_option(&self, key: &str, value: String) {
        self.options.lock().unwrap().insert(key.to_owned(), value);
    }
    fn ab(&self) -> Ab {
        self.ab.lock().unwrap().clone().unwrap_or_default()
    }
    fn set_ab(&self, ab: Option<&Ab>) {
        *self.ab.lock().unwrap() = ab.cloned();
    }
    fn group(&self) -> Group {
        self.group.lock().unwrap().clone().unwrap_or_default()
    }
    fn set_group(&self, group: Option<&Group>) {
        *self.group.lock().unwrap() = group.cloned();
    }
}

/// Signed in with token `t1`, both caches present.
fn signed_in() -> Mem {
    let s = Mem::default();
    s.set_option(TOKEN, "t1".to_owned());
    s.set_option(USER_INFO, r#"{"name":"alice"}"#.to_owned());
    s.set_ab(Some(&Ab {
        access_token: "t1".to_owned(),
        ab_entries: vec![AbEntry {
            name: "My address book".to_owned(),
            ..Default::default()
        }],
    }));
    s.set_group(Some(&Group {
        access_token: "t1".to_owned(),
        ..Default::default()
    }));
    s
}

fn signed_out(s: &Mem) -> bool {
    s.option(TOKEN).is_empty()
        && s.option(USER_INFO).is_empty()
        && s.ab.lock().unwrap().is_none()
        && s.group.lock().unwrap().is_none()
}

#[derive(Clone, Debug)]
struct Req {
    method: String,
    /// Path and query.
    target: String,
    auth: Option<String>,
    body: String,
}

impl Req {
    fn query(&self, k: &str) -> Option<String> {
        let q = self.target.split_once('?')?.1;
        q.split('&')
            .filter_map(|p| p.split_once('='))
            .find(|(a, _)| *a == k)
            .map(|(_, v)| v.to_owned())
    }
    fn json(&self) -> Value {
        serde_json::from_str(&self.body).unwrap()
    }
}

type Handler = Arc<dyn Fn(&Req) -> (u16, String) + Send + Sync>;

/// A minimal HTTP/1.1 server answering every request with `handler`; returns its base URL and
/// the requests it got.
async fn serve(
    handler: impl Fn(&Req) -> (u16, String) + Send + Sync + 'static,
) -> (String, Arc<Mutex<Vec<Req>>>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let seen = Arc::new(Mutex::new(Vec::new()));
    let handler: Handler = Arc::new(handler);
    let log = seen.clone();
    tokio::spawn(async move {
        while let Ok((mut s, _)) = listener.accept().await {
            let mut buf = Vec::new();
            let mut chunk = [0u8; 4096];
            let head_end = loop {
                let n = s.read(&mut chunk).await.unwrap();
                if n == 0 {
                    break None;
                }
                buf.extend_from_slice(&chunk[..n]);
                if let Some(i) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
                    break Some(i + 4);
                }
            };
            let Some(head_end) = head_end else { continue };
            let head = String::from_utf8_lossy(&buf[..head_end]).to_string();
            let mut lines = head.lines();
            let mut first = lines.next().unwrap().split(' ');
            let method = first.next().unwrap().to_owned();
            let target = first.next().unwrap().to_owned();
            let mut len = 0;
            let mut auth = None;
            for l in lines {
                if let Some((k, v)) = l.split_once(':') {
                    match k.to_ascii_lowercase().as_str() {
                        "content-length" => len = v.trim().parse().unwrap(),
                        "authorization" => auth = Some(v.trim().to_owned()),
                        _ => {}
                    }
                }
            }
            while buf.len() < head_end + len {
                let n = s.read(&mut chunk).await.unwrap();
                buf.extend_from_slice(&chunk[..n]);
            }
            let req = Req {
                method,
                target,
                auth,
                body: String::from_utf8_lossy(&buf[head_end..head_end + len]).to_string(),
            };
            let (status, body) = handler(&req);
            log.lock().unwrap().push(req);
            let resp = format!(
                "HTTP/1.1 {status} X\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            s.write_all(resp.as_bytes()).await.unwrap();
        }
    });
    (format!("http://{addr}"), seen)
}

fn device() -> Device {
    Device {
        id: "123456789".to_owned(),
        uuid: "dXVpZA==".to_owned(),
    }
}

fn kind(r: &Result<Value>) -> Option<Kind> {
    r.as_ref().err().map(|e| e.kind)
}

#[tokio::test(crate = "hbb_common::tokio")]
async fn login_writes_the_token_and_upstream_user_info() {
    let (base, seen) = serve(|_| {
        (200, r#"{"type":"access_token","access_token":"t2","user":{"name":"bob","display_name":"Bob","avatar":"","email":"b@example.com","status":-1,"is_admin":false}}"#.to_owned())
    })
    .await;
    let s = Mem::default();
    let info = json!({"os": "windows", "type": "client", "name": "pc"});
    let r = login(&s, &base, "bob", "pw", &device(), info.clone())
        .await
        .unwrap();
    assert_eq!(r["user"]["email"], "b@example.com");
    assert_eq!(s.option(TOKEN), "t2");
    let user_info: Value = serde_json::from_str(&s.option(USER_INFO)).unwrap();
    assert_eq!(
        user_info,
        json!({"name": "bob", "display_name": "Bob", "avatar": "", "status": -1})
    );
    let req = seen.lock().unwrap()[0].clone();
    assert_eq!(
        (
            req.method.as_str(),
            req.target.as_str(),
            req.auth.as_deref()
        ),
        ("POST", "/api/login", None)
    );
    assert_eq!(
        req.json(),
        json!({"username": "bob", "password": "pw", "id": "123456789", "uuid": "dXVpZA==",
               "autoLogin": true, "type": "account", "deviceInfo": info})
    );
}

#[tokio::test(crate = "hbb_common::tokio")]
async fn login_failures() {
    // leapgate-server: 401 for a wrong password, which keeps the stored login.
    let (base, _) = serve(|_| (401, r#"{"error":"Wrong credentials"}"#.to_owned())).await;
    let s = signed_in();
    let r = login(&s, &base, "a", "b", &device(), Value::Null).await;
    assert_eq!(kind(&r), Some(Kind::WrongCredentials));
    assert_eq!(r.unwrap_err().text, "Wrong credentials");
    assert_eq!(s.option(TOKEN), "t1");
    // rustdesk-api: 400.
    let (base, _) = serve(|_| (400, r#"{"error":"bad password"}"#.to_owned())).await;
    let r = login(&s, &base, "a", "b", &device(), Value::Null).await;
    assert_eq!(kind(&r), Some(Kind::Server));
    // A verification code is wanted (M4-1).
    let (base, _) = serve(|_| {
        (
            200,
            r#"{"type":"email_check","tfa_type":"email","secret":"x"}"#.to_owned(),
        )
    })
    .await;
    let s = Mem::default();
    let r = login(&s, &base, "a", "b", &device(), Value::Null).await;
    assert_eq!(kind(&r), Some(Kind::VerificationRequired));
    assert!(s.option(TOKEN).is_empty());
    // A 2xx with `error`, and a token without a user.
    for body in [
        r#"{"error":"x"}"#,
        r#"{"type":"access_token","access_token":"t"}"#,
    ] {
        let (base, _) = serve(move |_| (200, body.to_owned())).await;
        let r = login(&s, &base, "a", "b", &device(), Value::Null).await;
        assert_eq!(kind(&r), Some(Kind::Server));
        assert!(s.option(TOKEN).is_empty());
    }
}

#[tokio::test(crate = "hbb_common::tokio")]
async fn current_user_401_and_400_sign_out() {
    for status in [401, 400] {
        let (base, seen) = serve(move |_| (status, r#"{"error":"Unauthorized"}"#.to_owned())).await;
        let s = signed_in();
        let r = current_user(&s, &base, &device()).await;
        assert_eq!(kind(&r), Some(Kind::Unauthorized));
        assert!(signed_out(&s));
        let req = seen.lock().unwrap()[0].clone();
        assert_eq!(req.auth.as_deref(), Some("Bearer t1"));
        assert_eq!(req.json(), json!({"id": "123456789", "uuid": "dXVpZA=="}));
    }
}

#[tokio::test(crate = "hbb_common::tokio")]
async fn current_user_keeps_the_login_on_other_failures() {
    let (base, _) = serve(|_| (200, r#"{"error":"Server error"}"#.to_owned())).await;
    let s = signed_in();
    let r = current_user(&s, &base, &device()).await;
    assert_eq!(kind(&r), Some(Kind::Server));
    assert_eq!(r.unwrap_err().text, "Server error");
    assert_eq!(s.option(TOKEN), "t1");
    let r = current_user(&s, "http://127.0.0.1:1", &device()).await;
    assert_eq!(kind(&r), Some(Kind::Network));
    assert_eq!(s.option(TOKEN), "t1");
    let (base, _) = serve(|_| {
        (
            200,
            r#"{"name":"alice","display_name":"A","status":1}"#.to_owned(),
        )
    })
    .await;
    let r = current_user(&s, &base, &device()).await.unwrap();
    assert_eq!(r["user"]["display_name"], "A");
    assert_eq!(
        serde_json::from_str::<Value>(&s.option(USER_INFO)).unwrap()["display_name"],
        "A"
    );
}

#[tokio::test(crate = "hbb_common::tokio")]
async fn logout_signs_out_even_when_the_server_is_unreachable() {
    let (base, seen) = serve(|_| (200, String::new())).await;
    let s = signed_in();
    logout(&s, &base, &device()).await;
    assert!(signed_out(&s));
    let req = seen.lock().unwrap()[0].clone();
    assert_eq!(
        (req.target.as_str(), req.auth.as_deref()),
        ("/api/logout", Some("Bearer t1"))
    );
    let s = signed_in();
    logout(&s, "http://127.0.0.1:1", &device()).await;
    assert!(signed_out(&s));
}

#[tokio::test(crate = "hbb_common::tokio")]
async fn login_options_only_needs_an_answer() {
    let (base, _) = serve(|_| (200, r#"["common-oidc/null"]"#.to_owned())).await;
    assert_eq!(login_options(&base).await.unwrap(), json!({}));
    let (base, _) = serve(|_| (502, String::new())).await;
    let r = login_options(&base).await;
    assert_eq!(kind(&r), Some(Kind::Server));
    assert_eq!(r.unwrap_err().text, "HTTP 502");
}

#[test]
fn local_and_error_text() {
    let s = Mem::default();
    assert_eq!(local(&s), "{}");
    let s = signed_in();
    assert_eq!(local(&s), r#"{"user":{"name":"alice"}}"#);
    let e = Error::new(Kind::Server, &"x".repeat(500));
    assert_eq!(e.text.len(), 200);
    assert_eq!(
        render(Err(Error::new(Kind::Conflict, "Tag exists"))),
        r#"{"error":"conflict","text":"Tag exists"}"#
    );
}

#[tokio::test(crate = "hbb_common::tokio")]
async fn books_404_only_on_personal_is_unsupported() {
    let (base, _) = serve(|_| (404, String::new())).await;
    assert_eq!(
        kind(&ab::books(&signed_in(), &base).await),
        Some(Kind::Unsupported)
    );
    let (base, _) = serve(|r| {
        if r.target.starts_with("/api/ab/personal") {
            (200, r#"{"guid":"p1"}"#.to_owned())
        } else {
            (404, String::new())
        }
    })
    .await;
    assert_eq!(
        kind(&ab::books(&signed_in(), &base).await),
        Some(Kind::Server)
    );
}

#[tokio::test(crate = "hbb_common::tokio")]
async fn books_pages_the_shared_profiles() {
    let (base, seen) = serve(|r| match r.target.split('?').next().unwrap() {
        "/api/ab/personal" => (200, r#"{"guid":"p1"}"#.to_owned()),
        "/api/ab/settings" => (200, r#"{"max_peer_one_ab":5000}"#.to_owned()),
        _ => {
            let page: usize = r.query("current").unwrap().parse().unwrap();
            let data: Vec<Value> = (0..100)
                .map(|i| json!({"guid": format!("g{}", (page - 1) * 100 + i), "name": "n", "owner": "o", "note": "", "rule": 1}))
                .take(if page == 2 { 50 } else { 100 })
                .collect();
            (200, json!({"total": 150, "data": data}).to_string())
        }
    })
    .await;
    let r = ab::books(&signed_in(), &base).await.unwrap();
    assert_eq!(r["max_peers"], 5000);
    assert_eq!(r["personal"], "p1");
    assert_eq!(r["shared"].as_array().unwrap().len(), 150);
    let seen = seen.lock().unwrap();
    assert_eq!(seen.len(), 4);
    assert!(seen
        .iter()
        .all(|r| r.method == "POST" && r.auth.as_deref() == Some("Bearer t1")));
}

/// rustdesk-api answers every page with the same entries; `total` is far above them here, so
/// only the page without new ids ends paging.
#[tokio::test(crate = "hbb_common::tokio")]
async fn book_paging_stops_at_a_page_without_new_ids_and_caches() {
    let (base, seen) = serve(|r| {
        if r.target.starts_with("/api/ab/tags/") {
            return (200, r#"[{"name":"work","color":4294198070}]"#.to_owned());
        }
        let data: Vec<Value> = (0..150)
            .map(|i| json!({"id": format!("{i}"), "hash": "aGFzaA==", "password": "pw", "alias": "x", "note": "n", "tags": ["work"]}))
            .collect();
        (200, json!({"total": 1000, "data": data}).to_string())
    })
    .await;
    let s = signed_in();
    let r = ab::book(&s, &base, "p1", "ignored", true).await.unwrap();
    assert_eq!(r["peers"].as_array().unwrap().len(), 150);
    assert_eq!(r["peers"][0]["note"], "n");
    assert_eq!(r["tags"], json!([{"name": "work", "color": 4294198070u64}]));
    let reqs = seen.lock().unwrap().clone();
    assert_eq!(reqs.len(), 3);
    let first = &reqs[0];
    assert_eq!(first.method, "POST");
    for (k, v) in [
        ("current", "1"),
        ("page", "1"),
        ("pageSize", "100"),
        ("ab", "p1"),
    ] {
        assert_eq!(first.query(k).as_deref(), Some(v));
    }
    assert_eq!(reqs[1].query("current").as_deref(), Some("2"));
    assert_eq!(reqs[2].target, "/api/ab/tags/p1");

    // The personal entry keeps `hash` and the name `src/client.rs` looks for.
    let cached: Value = serde_json::from_str(&ab::cache(&s)).unwrap();
    let entries = cached["entries"].as_array().unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0]["name"], "My address book");
    assert_eq!(entries[0]["guid"], "p1");
    assert_eq!(
        entries[0]["peers"][0],
        json!({"id": "0", "hash": "aGFzaA==", "alias": "x", "tags": ["work"]})
    );
    assert_eq!(entries[0]["tags"], json!(["work"]));
    assert_eq!(entries[0]["tag_colors"], r#"{"work":4294198070}"#);
    assert!(s.ab().ab_entries[0].personal());

    // A shared book goes beside it without `hash`; a second shared book replaces the first.
    ab::book(&s, &base, "s1", "Team", false).await.unwrap();
    ab::book(&s, &base, "s2", "Ops", false).await.unwrap();
    let ab = s.ab();
    assert_eq!(ab.ab_entries.len(), 2);
    let shared = ab.ab_entries.iter().find(|e| !e.personal()).unwrap();
    assert_eq!((shared.guid.as_str(), shared.name.as_str()), ("s2", "Ops"));
    assert!(shared.peers.iter().all(|p| p.hash.is_empty()));

    // Another token's cache is not shown and is replaced on the next pull.
    s.set_option(TOKEN, "t2".to_owned());
    assert_eq!(ab::cache(&s), r#"{"entries":[]}"#);
    ab::book(&s, &base, "s1", "Team", false).await.unwrap();
    let ab = s.ab();
    assert_eq!((ab.access_token.as_str(), ab.ab_entries.len()), ("t2", 1));
}

#[tokio::test(crate = "hbb_common::tokio")]
async fn book_pages_by_total() {
    let (base, seen) = serve(|r| {
        if r.target.starts_with("/api/ab/tags/") {
            // rustdesk-api, a book without tags.
            return (200, "null".to_owned());
        }
        let page: usize = r.query("current").unwrap().parse().unwrap();
        let data: Vec<Value> = (0..100)
            .map(|i| json!({"id": format!("{}", (page - 1) * 100 + i)}))
            .collect();
        (200, json!({"total": 250, "data": data}).to_string())
    })
    .await;
    let r = ab::book(&signed_in(), &base, "s1", "Team", false)
        .await
        .unwrap();
    assert_eq!(r["peers"].as_array().unwrap().len(), 300);
    assert_eq!(r["tags"], json!([]));
    assert_eq!(seen.lock().unwrap().len(), 4);
}

#[tokio::test(crate = "hbb_common::tokio")]
async fn book_401_signs_out() {
    let (base, _) = serve(|_| (401, r#"{"error":"Unauthorized"}"#.to_owned())).await;
    let s = signed_in();
    assert_eq!(
        kind(&ab::book(&s, &base, "p1", "", true).await),
        Some(Kind::Unauthorized)
    );
    assert!(signed_out(&s));
}

/// Signed out and in again while a request with the old token was out: its 401 keeps the new
/// login.
#[tokio::test(crate = "hbb_common::tokio")]
async fn a_401_for_an_old_token_keeps_the_new_login() {
    let s = Arc::new(signed_in());
    let s2 = s.clone();
    let (base, seen) = serve(move |_| {
        s2.set_option(TOKEN, "t2".to_owned());
        (401, String::new())
    })
    .await;
    assert_eq!(
        kind(&ab::book(&*s, &base, "p1", "", true).await),
        Some(Kind::Unauthorized)
    );
    assert_eq!(s.option(TOKEN), "t2");
    assert!(s.ab.lock().unwrap().is_some());
    assert_eq!(seen.lock().unwrap()[0].auth.as_deref(), Some("Bearer t1"));
}

/// A logout lands while the devices are fetched: the removed caches stay removed.
#[tokio::test(crate = "hbb_common::tokio")]
async fn a_logout_during_a_pull_is_not_undone() {
    let s = Arc::new(signed_in());
    let s2 = s.clone();
    let (base, _) = serve(move |r| {
        if r.target.starts_with("/api/ab/tags/") {
            return (200, "[]".to_owned());
        }
        if r.target.starts_with("/api/ab/peers") || r.target.starts_with("/api/peers") {
            clear(&*s2);
        }
        (
            200,
            json!({"total": 1, "data": [{"id": "1", "name": "a", "hash": "aGFzaA=="}]}).to_string(),
        )
    })
    .await;
    ab::book(&*s, &base, "p1", "", true).await.unwrap();
    assert!(s.ab.lock().unwrap().is_none());
    s.set_option(TOKEN, "t1".to_owned());
    group::pull(&*s, &base).await.unwrap();
    assert!(s.group.lock().unwrap().is_none());
}

/// Reading a real `_ab` file takes a while.
struct SlowAb(Mem);

impl Store for SlowAb {
    fn option(&self, key: &str) -> String {
        self.0.option(key)
    }
    fn set_option(&self, key: &str, value: String) {
        self.0.set_option(key, value)
    }
    fn ab(&self) -> Ab {
        let ab = self.0.ab();
        std::thread::sleep(std::time::Duration::from_millis(300));
        ab
    }
    fn set_ab(&self, ab: Option<&Ab>) {
        self.0.set_ab(ab)
    }
    fn group(&self) -> Group {
        self.0.group()
    }
    fn set_group(&self, group: Option<&Group>) {
        self.0.set_group(group)
    }
}

/// The personal book and a shared one saved at once (each export runs on its own thread): both
/// entries stay.
#[tokio::test(
    flavor = "multi_thread",
    worker_threads = 2,
    crate = "hbb_common::tokio"
)]
async fn concurrent_saves_keep_both_entries() {
    let (base, _) = serve(|r| {
        if r.target.starts_with("/api/ab/tags/") {
            return (200, "[]".to_owned());
        }
        (
            200,
            json!({"total": 1, "data": [{"id": "1", "hash": "aGFzaA=="}]}).to_string(),
        )
    })
    .await;
    let s = Arc::new(SlowAb(signed_in()));
    s.set_option(TOKEN, "t2".to_owned());
    let (a, b) = (s.clone(), s.clone());
    let (base_a, base_b) = (base.clone(), base.clone());
    let ha = tokio::spawn(async move { ab::book(&*a, &base_a, "p1", "", true).await.is_ok() });
    let hb = tokio::spawn(async move { ab::book(&*b, &base_b, "s1", "Team", false).await.is_ok() });
    assert!(ha.await.unwrap() && hb.await.unwrap());
    let ab = s.0.ab();
    assert_eq!(ab.ab_entries.len(), 2);
    let personal = ab.ab_entries.iter().find(|e| e.personal()).unwrap();
    assert_eq!(personal.peers[0].hash, "aGFzaA==");
}

#[tokio::test(crate = "hbb_common::tokio")]
async fn writes() {
    let (base, seen) = serve(|r| match r.target.as_str() {
        "/api/ab/peer/update/missing" | "/api/ab/tag/update/missing" => {
            (404, r#"{"error":"Peer not found"}"#.to_owned())
        }
        "/api/ab/tag/rename/g" => (409, r#"{"error":"Tag exists"}"#.to_owned()),
        "/api/ab/peer/add/full" => (400, r#"{"error":"Address book is full"}"#.to_owned()),
        "/api/ab/peer/add/oops" => (200, r#"{"error":"Failed"}"#.to_owned()),
        "/api/ab/peer/add/proxy" => (200, "<html>blocked</html>".to_owned()),
        "/api/ab/peer/add/gone" => (401, String::new()),
        _ => (200, String::new()),
    })
    .await;
    let s = signed_in();
    macro_rules! w {
        ($method:expr, $path:expr) => {
            ab::write_to(&s, &base, $method, $path, bytes(json!({"id": "1"}))).await
        };
    }
    assert_eq!(w!(Method::POST, "/api/ab/peer/add/g").unwrap(), json!({}));
    assert_eq!(
        kind(&w!(Method::PUT, "/api/ab/peer/update/missing")),
        Some(Kind::NotFound)
    );
    assert_eq!(
        kind(&w!(Method::PUT, "/api/ab/tag/update/missing")),
        Some(Kind::NotFound)
    );
    assert_eq!(
        kind(&w!(Method::PUT, "/api/ab/tag/rename/g")),
        Some(Kind::Conflict)
    );
    let full = w!(Method::POST, "/api/ab/peer/add/full");
    assert_eq!(kind(&full), Some(Kind::Server));
    assert_eq!(full.unwrap_err().text, "Address book is full");
    assert_eq!(
        kind(&w!(Method::POST, "/api/ab/peer/add/oops")),
        Some(Kind::Server)
    );
    assert_eq!(
        kind(&w!(Method::POST, "/api/ab/peer/add/proxy")),
        Some(Kind::Server)
    );
    assert!(!signed_out(&s));
    assert_eq!(
        kind(&w!(Method::POST, "/api/ab/peer/add/gone")),
        Some(Kind::Unauthorized)
    );
    assert!(signed_out(&s));
    let first = seen.lock().unwrap()[0].clone();
    assert_eq!(
        (first.method.as_str(), first.auth.as_deref()),
        ("POST", Some("Bearer t1"))
    );
    assert_eq!(first.json(), json!({"id": "1"}));
}

/// DELETE carries its body too.
#[tokio::test(crate = "hbb_common::tokio")]
async fn write_requests() {
    let (base, seen) = serve(|_| (200, String::new())).await;
    let s = signed_in();
    let ids = vec!["1".to_owned(), "2".to_owned()];
    let cases: Vec<(Method, String, Value)> = vec![
        (Method::DELETE, "/api/ab/peer/g".to_owned(), json!(ids)),
        (
            Method::POST,
            "/api/ab/tag/add/g".to_owned(),
            json!({"name": "a", "color": 4278190080u64}),
        ),
        (
            Method::PUT,
            "/api/ab/tag/rename/g".to_owned(),
            json!({"old": "a", "new": "b"}),
        ),
        (Method::DELETE, "/api/ab/tag/g".to_owned(), json!(["a"])),
    ];
    for (method, path, body) in &cases {
        ab::write_to(&s, &base, method.clone(), path, bytes(body.clone()))
            .await
            .unwrap();
    }
    let seen = seen.lock().unwrap();
    for (req, (method, path, body)) in seen.iter().zip(&cases) {
        assert_eq!(
            (req.method.as_str(), req.target.as_str()),
            (method.as_str(), path.as_str())
        );
        assert_eq!(&req.json(), body);
    }
}

#[tokio::test(crate = "hbb_common::tokio")]
async fn group_pulls_users_and_peers_and_caches() {
    let (base, seen) = serve(|r| {
        if r.target.starts_with("/api/users") {
            (200, r#"{"total":2,"data":[{"name":"alice","display_name":"Alice","status":1},{"name":"bob","status":1}]}"#.to_owned())
        } else {
            (200, r#"{"total":1,"data":[{"id":"9","user_name":"bob","note":"n","info":{"username":"b","device_name":"pc","os":"windows / Windows 11"}}]}"#.to_owned())
        }
    })
    .await;
    let s = signed_in();
    let r = group::pull(&s, &base).await.unwrap();
    assert_eq!(r["users"].as_array().unwrap().len(), 2);
    assert_eq!(r["peers"][0]["note"], "n");
    let reqs = seen.lock().unwrap().clone();
    assert_eq!(reqs.len(), 2);
    for (req, path) in reqs.iter().zip(["/api/users", "/api/peers"]) {
        assert_eq!(req.method, "GET");
        assert!(req.target.starts_with(path));
        for (k, v) in [
            ("current", "1"),
            ("page", "1"),
            ("pageSize", "100"),
            ("accessible", ""),
            ("status", "1"),
        ] {
            assert_eq!(req.query(k).as_deref(), Some(v));
        }
    }
    let cached: Value = serde_json::from_str(&group::cache(&s)).unwrap();
    assert_eq!(
        cached["users"][0],
        json!({"name": "alice", "display_name": "Alice"})
    );
    assert_eq!(
        cached["peers"][0],
        json!({"id": "9", "username": "b", "hostname": "pc", "platform": "Windows", "login_name": "bob"})
    );
    s.set_option(TOKEN, "t2".to_owned());
    assert_eq!(group::cache(&s), "{}");
}
