//! Controller: the server's exit node directory (contract 03).
//!
//! Only advice: whether an exit can be used is decided by the exit itself. Fetched once each
//! time the dialog opens, never polled (D2).

use crate::{api, report};
use hbb_common::{config::LocalConfig, serde_json, throttled_log};
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// The `main_get_common` key the dialog asks for.
pub const KEY: &str = "leapgate-exits";

const LOG_INTERVAL: Duration = Duration::from_secs(60);
const UNSUPPORTED: &str = r#"{"state":"unsupported"}"#;
const NOT_LOGGED_IN: &str = r#"{"state":"not_logged_in"}"#;
const ERROR: &str = r#"{"state":"error"}"#;

#[derive(Deserialize, Serialize)]
struct Exit {
    id: String,
    hostname: String,
    owner: String,
    own: bool,
}

#[derive(Deserialize)]
struct Exits {
    exits: Vec<Exit>,
}

/// The JSON the dialog shows: `{"state": "unsupported" | "not_logged_in" | "error"}`, or
/// `{"state": "ok", "exits": [...]}`.
pub async fn fetch() -> String {
    // F3: the announced feature decides; a 404 or 405 is not taken as "no directory".
    if !report::has_feature("exit") {
        return UNSUPPORTED.to_owned();
    }
    let token = LocalConfig::get_option("access_token");
    if token.is_empty() {
        return NOT_LOGGED_IN.to_owned();
    }
    let failure = match api::get_user(&report::api_root(), "exits", &token).await {
        Ok((status, body)) => {
            let out = render(status, &body);
            if out != ERROR {
                return out;
            }
            status.to_string()
        }
        Err(e) => e.to_string(),
    };
    throttled_log!(
        LOG_INTERVAL,
        info,
        "leapgate exit: directory request failed ({})",
        failure
    );
    ERROR.to_owned()
}

/// Only a 200 with an `exits` array is a list; 401 means not logged in, or no longer.
fn render(status: u16, body: &[u8]) -> String {
    match status {
        200 => match serde_json::from_slice::<Exits>(body) {
            Ok(list) => serde_json::json!({ "state": "ok", "exits": list.exits }).to_string(),
            Err(_) => ERROR.to_owned(),
        },
        401 => NOT_LOGGED_IN.to_owned(),
        _ => ERROR.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};

    fn state(status: u16, body: &str) -> Value {
        serde_json::from_str(&render(status, body.as_bytes())).unwrap()
    }

    #[test]
    fn only_a_200_list_is_shown() {
        let body = r#"{"exits":[{"id":"123","hostname":"","owner":"alice","own":false,"x":1}]}"#;
        assert_eq!(
            state(200, body),
            json!({"state": "ok", "exits": [{"id": "123", "hostname": "", "owner": "alice", "own": false}]})
        );
        assert_eq!(state(200, "{}"), json!({"state": "error"}));
        assert_eq!(state(401, body), json!({"state": "not_logged_in"}));
        assert_eq!(state(500, body), json!({"state": "error"}));
    }
}
