//! Against a real server (07 §5.2, §5.3), ignored by default. Run with `--ignored --nocapture`
//! and these variables:
//! - `LEAPGATE_IT_API`: the API root, e.g. `http://192.0.2.1:21114`;
//! - `LEAPGATE_IT_SERVER`: `leapgate` or `rustdesk-api`;
//! - `LEAPGATE_IT_USER`, `LEAPGATE_IT_PASSWORD`: an account made for this test (never printed);
//! - `LEAPGATE_IT_BOOK_RO`, `LEAPGATE_IT_BOOK_RW`, `LEAPGATE_IT_BOOK_FULL`: shared books this account
//!   may read, read and write, fully control;
//! - `LEAPGATE_IT_TEAMMATE`: another user the account sees in the team devices.
//!
//! Entries it adds carry the `h1it` prefix and are removed again.

use super::{tests::Mem, *};
use hbb_common::tokio;

const PREFIX: &str = "h1it";

fn var(k: &str) -> String {
    std::env::var(k).unwrap_or_else(|_| panic!("{k} is not set"))
}

fn outcome(r: &Result<Value>) -> String {
    match r {
        Ok(_) => "ok".to_owned(),
        Err(e) => format!("{:?} ({})", e.kind, e.text),
    }
}

fn ids(book: &Value) -> Vec<String> {
    book["peers"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["id"].as_str().unwrap_or_default().to_owned())
        .collect()
}

async fn put(s: &Mem, base: &str, method: Method, path: String, body: Value) -> Result<Value> {
    ab::write_to(s, base, method, &path, bytes(body)).await
}

#[tokio::test(crate = "hbb_common::tokio")]
#[ignore]
async fn live_account_flow() {
    let base = var("LEAPGATE_IT_API");
    let leapgate = match var("LEAPGATE_IT_SERVER").as_str() {
        "leapgate" => true,
        "rustdesk-api" => false,
        other => panic!("unknown server {other}"),
    };
    let user = var("LEAPGATE_IT_USER");
    let password = var("LEAPGATE_IT_PASSWORD");
    let s = Mem::default();
    let device = Device {
        id: format!("{PREFIX}-device"),
        uuid: "aDFpdC11dWlk".to_owned(),
    };
    let info = || json!({"os": "windows", "type": "client", "name": "h1it"});

    // Account.
    let r = login_options(&base).await;
    println!("login-options: {}", outcome(&r));
    assert!(r.is_ok());
    let r = login(&s, &base, &user, "not-the-password", &device, info()).await;
    println!("login, wrong password: {}", outcome(&r));
    let wrong = if leapgate {
        Kind::WrongCredentials
    } else {
        Kind::Server
    };
    assert_eq!(r.as_ref().err().map(|e| e.kind), Some(wrong));
    let r = login(&s, &base, &user, &password, &device, info()).await;
    println!("login: {}", outcome(&r));
    assert_eq!(
        r.as_ref().ok().map(|u| u["user"]["name"].clone()),
        Some(json!(user))
    );
    assert!(!s.option(TOKEN).is_empty());
    let user_info: Value = serde_json::from_str(&s.option(USER_INFO)).unwrap();
    assert_eq!(user_info["name"], json!(user));
    let r = current_user(&s, &base, &device).await;
    println!("currentUser: {}", outcome(&r));
    assert!(r.is_ok());

    // Books.
    let books = ab::books(&s, &base).await;
    println!("books: {}", outcome(&books));
    let books = books.ok().unwrap();
    let personal = books["personal"].as_str().unwrap().to_owned();
    println!(
        "  max_peers {}, shared {}",
        books["max_peers"], books["shared"]
    );
    let shared = |name: &str| {
        books["shared"]
            .as_array()
            .unwrap()
            .iter()
            .find(|b| b["name"] == name)
            .unwrap_or_else(|| panic!("shared book {name} not listed"))
            .clone()
    };

    // The personal book: clear leftovers of an earlier run, then every write.
    let book = ab::book(&s, &base, &personal, "", true).await.ok().unwrap();
    let left: Vec<String> = ids(&book)
        .into_iter()
        .filter(|i| i.starts_with(PREFIX))
        .collect();
    if !left.is_empty() {
        put(
            &s,
            &base,
            Method::DELETE,
            format!("/api/ab/peer/{personal}"),
            json!(left),
        )
        .await
        .ok()
        .unwrap();
    }
    let tags = |b: &Value| -> Vec<String> {
        b["tags"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| t["name"].as_str().unwrap().to_owned())
            .collect()
    };
    let old_tags: Vec<String> = tags(&book)
        .into_iter()
        .filter(|t| t.starts_with(PREFIX))
        .collect();
    if !old_tags.is_empty() {
        put(
            &s,
            &base,
            Method::DELETE,
            format!("/api/ab/tag/{personal}"),
            json!(old_tags),
        )
        .await
        .ok()
        .unwrap();
    }
    let p1 = format!("{PREFIX}-1");
    let (t1, t2, t3) = (
        format!("{PREFIX}-t1"),
        format!("{PREFIX}-t2"),
        format!("{PREFIX}-t3"),
    );
    let r = put(&s, &base, Method::POST, format!("/api/ab/peer/add/{personal}"),
        json!({"id": p1, "alias": "first", "tags": [], "hash": "aDFpdC1oYXNo", "username": "u", "hostname": "h", "platform": "Windows"})).await;
    println!("peer/add: {}", outcome(&r));
    assert!(r.is_ok());
    for (t, color) in [(&t1, 4278190335i64), (&t2, 4294901760)] {
        let r = put(
            &s,
            &base,
            Method::POST,
            format!("/api/ab/tag/add/{personal}"),
            json!({"name": t, "color": color}),
        )
        .await;
        println!("tag/add {t}: {}", outcome(&r));
        assert!(r.is_ok());
    }
    let r = put(
        &s,
        &base,
        Method::PUT,
        format!("/api/ab/peer/update/{personal}"),
        json!({"id": p1, "tags": [t1], "note": "h1it note"}),
    )
    .await;
    println!("peer/update: {}", outcome(&r));
    assert!(r.is_ok());
    let r = put(
        &s,
        &base,
        Method::PUT,
        format!("/api/ab/tag/update/{personal}"),
        json!({"name": t1, "color": 4278255360i64}),
    )
    .await;
    println!("tag/update: {}", outcome(&r));
    assert!(r.is_ok());
    let book = ab::book(&s, &base, &personal, "", true).await.ok().unwrap();
    let peer = book["peers"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == json!(p1))
        .unwrap()
        .clone();
    println!(
        "  peer as read back: alias {}, tags {}, note {}, hash present {}",
        peer["alias"],
        peer["tags"],
        peer["note"],
        peer.get("hash").is_some()
    );
    assert_eq!(
        (peer["alias"].clone(), peer["tags"].clone()),
        (json!("first"), json!([t1]))
    );
    let tag = book["tags"]
        .as_array()
        .unwrap()
        .iter()
        .find(|t| t["name"] == json!(t1))
        .unwrap()
        .clone();
    println!("  tag as read back: {tag}");
    assert_eq!(tag["color"], json!(4278255360i64));
    // The cache `src/client.rs` fills a saved password from.
    let entry = s
        .ab()
        .ab_entries
        .into_iter()
        .find(|e| e.personal())
        .unwrap();
    let cached = entry.peers.iter().find(|p| p.id == p1).unwrap();
    println!(
        "  cache: personal entry {}, hash kept {}",
        entry.name,
        !cached.hash.is_empty()
    );
    assert_eq!(
        (entry.guid.as_str(), cached.hash.as_str()),
        (personal.as_str(), "aDFpdC1oYXNo")
    );

    let r = put(
        &s,
        &base,
        Method::PUT,
        format!("/api/ab/tag/rename/{personal}"),
        json!({"old": t1, "new": t2}),
    )
    .await;
    println!("tag/rename onto an existing name: {}", outcome(&r));
    if leapgate {
        assert_eq!(r.as_ref().err().map(|e| e.kind), Some(Kind::Conflict));
    }
    let r = put(
        &s,
        &base,
        Method::PUT,
        format!("/api/ab/tag/rename/{personal}"),
        json!({"old": t1, "new": t3}),
    )
    .await;
    println!("tag/rename: {}", outcome(&r));
    assert!(r.is_ok());
    let book = ab::book(&s, &base, &personal, "", true).await.ok().unwrap();
    let peer = book["peers"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == json!(p1))
        .unwrap()
        .clone();
    println!(
        "  tags after rename: book {:?}, peer {}",
        tags(&book),
        peer["tags"]
    );
    let r = put(
        &s,
        &base,
        Method::PUT,
        format!("/api/ab/peer/update/{personal}"),
        json!({"id": format!("{PREFIX}-missing"), "alias": "x"}),
    )
    .await;
    println!("peer/update of a missing device: {}", outcome(&r));
    if leapgate {
        assert_eq!(r.as_ref().err().map(|e| e.kind), Some(Kind::NotFound));
    }
    let r = put(
        &s,
        &base,
        Method::PUT,
        format!("/api/ab/tag/update/{personal}"),
        json!({"name": format!("{PREFIX}-missing"), "color": 1}),
    )
    .await;
    println!("tag/update of a missing tag: {}", outcome(&r));

    // Paging: more devices than one page.
    for i in 0..120 {
        let r = put(
            &s,
            &base,
            Method::POST,
            format!("/api/ab/peer/add/{personal}"),
            json!({"id": format!("{PREFIX}-p{i:03}"), "tags": []}),
        )
        .await;
        assert!(r.is_ok(), "peer/add {i}: {}", outcome(&r));
    }
    let book = ab::book(&s, &base, &personal, "", true).await;
    println!("book with 121 devices: {}", outcome(&book));
    let all = ids(&book.ok().unwrap());
    let mine = all.iter().filter(|i| i.starts_with(PREFIX)).count();
    println!("  {} devices read, {} of them this test's", all.len(), mine);
    assert_eq!(mine, 121);

    // rustdesk-api refuses the whole request when a name is not there (t1 was renamed).
    let r = put(
        &s,
        &base,
        Method::DELETE,
        format!("/api/ab/tag/{personal}"),
        json!([t2, t3]),
    )
    .await;
    println!("DELETE tag: {}", outcome(&r));
    assert!(r.is_ok());
    let gone: Vec<String> = all.into_iter().filter(|i| i.starts_with(PREFIX)).collect();
    let r = put(
        &s,
        &base,
        Method::DELETE,
        format!("/api/ab/peer/{personal}"),
        json!(gone),
    )
    .await;
    println!("DELETE peer: {}", outcome(&r));
    assert!(r.is_ok());
    let book = ab::book(&s, &base, &personal, "", true).await.ok().unwrap();
    assert!(!ids(&book).iter().any(|i| i.starts_with(PREFIX)));
    assert!(!tags(&book).iter().any(|t| t.starts_with(PREFIX)));

    // Shared books, one per rule.
    for (var_name, rule, writable) in [
        ("LEAPGATE_IT_BOOK_RO", 1, false),
        ("LEAPGATE_IT_BOOK_RW", 2, true),
        ("LEAPGATE_IT_BOOK_FULL", 3, true),
    ] {
        let name = var(var_name);
        let profile = shared(&name);
        let guid = profile["guid"].as_str().unwrap().to_owned();
        println!(
            "shared {name}: rule {}, owner {}",
            profile["rule"], profile["owner"]
        );
        assert_eq!(profile["rule"], json!(rule));
        let r = ab::book(&s, &base, &guid, &name, false).await;
        println!("  book: {}", outcome(&r));
        assert!(r.is_ok());
        let id = format!("{PREFIX}-s{rule}");
        let r = put(
            &s,
            &base,
            Method::POST,
            format!("/api/ab/peer/add/{guid}"),
            json!({"id": id, "tags": [], "password": "h1it-shared"}),
        )
        .await;
        println!("  peer/add: {}", outcome(&r));
        assert_eq!(r.is_ok(), writable);
        if writable {
            let book = ab::book(&s, &base, &guid, &name, false).await.ok().unwrap();
            let peer = book["peers"]
                .as_array()
                .unwrap()
                .iter()
                .find(|p| p["id"] == json!(id))
                .unwrap()
                .clone();
            println!(
                "  shared password read back: {}",
                peer["password"] == json!("h1it-shared")
            );
            let entry = s
                .ab()
                .ab_entries
                .into_iter()
                .find(|e| !e.personal())
                .unwrap();
            assert_eq!(entry.name, name);
            assert!(entry.peers.iter().all(|p| p.hash.is_empty()));
            let r = put(
                &s,
                &base,
                Method::DELETE,
                format!("/api/ab/peer/{guid}"),
                json!([id]),
            )
            .await;
            println!("  DELETE peer: {}", outcome(&r));
            // rustdesk-api deletes with full control only.
            assert_eq!(r.is_ok(), leapgate || rule == 3);
        }
    }

    // Team devices.
    let g = group::pull(&s, &base).await;
    println!("group: {}", outcome(&g));
    let g = g.ok().unwrap();
    let names: Vec<&str> = g["users"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|u| u["name"].as_str())
        .collect();
    println!(
        "  users {:?}, {} devices",
        names,
        g["peers"].as_array().unwrap().len()
    );
    assert!(names.contains(&user.as_str()));
    assert!(names.contains(&var("LEAPGATE_IT_TEAMMATE").as_str()));
    assert_eq!(s.group().users.len(), names.len());

    // Logout ends the token on the server too.
    let token = s.option(TOKEN);
    logout(&s, &base, &device).await;
    assert!(s.option(TOKEN).is_empty() && s.ab().ab_entries.is_empty());
    s.set_option(TOKEN, token);
    let r = current_user(&s, &base, &device).await;
    println!("currentUser with the token after logout: {}", outcome(&r));
    assert_eq!(r.as_ref().err().map(|e| e.kind), Some(Kind::Unauthorized));
}
