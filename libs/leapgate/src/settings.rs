//! The settings page's saving (S9) and its Telegram check (S10), `LEAPGATE.md` §10.13. The
//! IPC itself is in the main crate (`src/leapgate_hooks/settings.rs`).

use hbb_common::serde_json::Value;
use serde::Serialize;
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Saved {
    /// The service confirmed it; this process's config matches.
    Saved,
    /// Only this process's config: no service runs, it takes the options when it starts.
    SavedLocal,
    Failed,
}

impl Saved {
    pub fn as_str(self) -> &'static str {
        match self {
            Saved::Saved => "saved",
            Saved::SavedLocal => "saved_local",
            Saved::Failed => "failed",
        }
    }
}

/// `changes` into `options`; an empty value removes the option.
pub fn merge(options: &mut HashMap<String, String>, changes: &HashMap<String, String>) {
    for (k, v) in changes {
        if v.is_empty() {
            options.remove(k);
        } else {
            options.insert(k.clone(), v.clone());
        }
    }
}

/// When the service does not answer. An installed service that should be running would not
/// see a change written only here, so that fails; a stopped one, or a portable build, takes it.
pub fn offline(installed: bool, stop_service: &str) -> Saved {
    if installed && stop_service != "Y" {
        Saved::Failed
    } else {
        Saved::SavedLocal
    }
}

/// S10: a `bot_chat` result as `ok`, `invalid_token` (Telegram's 401 or 404), `no_chat` (no
/// message to the bot yet) or `network` (every other error).
pub fn bot_result<T>(result: &Result<Option<T>, String>) -> &'static str {
    match result {
        Ok(Some(_)) => "ok",
        Ok(None) => "no_chat",
        Err(e) => match telegram_error_code(e) {
            Some(401 | 404) => "invalid_token",
            _ => "network",
        },
    }
}

/// The code in upstream's `Telegram API error: {description} (error_code: {code})`.
fn telegram_error_code(e: &str) -> Option<i64> {
    let rest = e.strip_prefix("Telegram API error: ")?;
    rest.strip_suffix(')')?
        .rsplit_once("(error_code: ")?
        .1
        .parse()
        .ok()
}

/// The chat the bot's codes would go to, for the user to confirm before it is saved.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct BotChat {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: String,
    /// `@username` or `first_name last_name` for a private chat, the title otherwise.
    pub label: String,
}

/// S10: the chat of the latest update with a message in Telegram's getUpdates response.
/// Upstream's `get_chatid_telegram` takes the earliest, but anyone can find a bot and message
/// it first. Telegram's errors keep upstream's text, which `bot_result` reads.
pub fn bot_chat(resp: &str) -> Result<Option<BotChat>, String> {
    let value: Value = hbb_common::serde_json::from_str(resp).map_err(|e| e.to_string())?;
    if let Some(code) = value.get("error_code").and_then(Value::as_i64) {
        let description = value["description"]
            .as_str()
            .unwrap_or("Unknown error occurred");
        return Err(format!(
            "Telegram API error: {description} (error_code: {code})"
        ));
    }
    let Some(updates) = value["result"].as_array() else {
        return Ok(None);
    };
    Ok(updates.iter().rev().find_map(|u| {
        let chat = u.get("message")?.get("chat")?;
        let id = match &chat["id"] {
            Value::Number(n) => n.to_string(),
            Value::String(s) => s.clone(),
            _ => return None,
        };
        let text = |k: &str| chat[k].as_str().unwrap_or_default();
        let kind = text("type");
        let label = if kind == "private" {
            match (text("username"), text("last_name")) {
                ("", "") => text("first_name").to_owned(),
                ("", last) => format!("{} {last}", text("first_name")),
                (username, _) => format!("@{username}"),
            }
        } else {
            text("title").to_owned()
        };
        Some(BotChat {
            id,
            kind: kind.to_owned(),
            label,
        })
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn map(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn changes_merge_into_the_service_options() {
        let mut options = map(&[("a", "1"), ("b", "2"), ("c", "3")]);
        merge(
            &mut options,
            &map(&[("a", "9"), ("b", ""), ("d", "4"), ("e", "")]),
        );
        assert_eq!(options, map(&[("a", "9"), ("c", "3"), ("d", "4")]));
    }

    #[test]
    fn without_the_service() {
        assert_eq!(offline(true, ""), Saved::Failed);
        assert_eq!(offline(true, "N"), Saved::Failed);
        assert_eq!(offline(true, "Y"), Saved::SavedLocal);
        assert_eq!(offline(false, ""), Saved::SavedLocal);
        assert_eq!(
            [Saved::Saved, Saved::SavedLocal, Saved::Failed].map(Saved::as_str),
            ["saved", "saved_local", "failed"]
        );
    }

    /// Error texts as upstream's `get_chatid_telegram` formats them, with Telegram's own
    /// descriptions.
    #[test]
    fn telegram_results_by_upstream_text() {
        let err = |s: &str| Err::<Option<String>, _>(s.to_owned());
        assert_eq!(bot_result(&Ok(Some("123456789".to_owned()))), "ok");
        assert_eq!(bot_result::<String>(&Ok(None)), "no_chat");
        assert_eq!(
            bot_result(&err("Telegram API error: Unauthorized (error_code: 401)")),
            "invalid_token"
        );
        assert_eq!(
            bot_result(&err("Telegram API error: Not Found (error_code: 404)")),
            "invalid_token"
        );
        assert_eq!(
            bot_result(&err(
                "Telegram API error: Conflict: can't use getUpdates method while webhook is active; use deleteWebhook to delete the webhook first (error_code: 409)"
            )),
            "network"
        );
        assert_eq!(
            bot_result(&err(
                "error sending request for url (https://api.telegram.org/bot<token>/getUpdates)"
            )),
            "network"
        );
        assert_eq!(
            bot_result(&err("expected value at line 1 column 1")),
            "network"
        );
    }

    fn updates(chats: &[&str]) -> String {
        let updates: Vec<String> = chats
            .iter()
            .enumerate()
            .map(|(i, chat)| {
                format!(
                    r#"{{"update_id":{i},"message":{{"message_id":1,"chat":{chat},"text":"hi"}}}}"#
                )
            })
            .collect();
        format!(r#"{{"ok":true,"result":[{}]}}"#, updates.join(","))
    }

    fn chat(id: &str, kind: &str, label: &str) -> Option<BotChat> {
        Some(BotChat {
            id: id.to_owned(),
            kind: kind.to_owned(),
            label: label.to_owned(),
        })
    }

    #[test]
    fn telegram_chat_labels() {
        let one = |c: &str| bot_chat(&updates(&[c])).unwrap();
        assert_eq!(
            one(
                r#"{"id":123456789,"first_name":"Example","last_name":"User","username":"example_user","type":"private"}"#
            ),
            chat("123456789", "private", "@example_user")
        );
        assert_eq!(
            one(r#"{"id":123456789,"first_name":"Example","last_name":"User","type":"private"}"#),
            chat("123456789", "private", "Example User")
        );
        assert_eq!(
            one(r#"{"id":123456789,"first_name":"Example","type":"private"}"#),
            chat("123456789", "private", "Example")
        );
        assert_eq!(
            one(r#"{"id":-1001234567890,"title":"Example group","type":"supergroup"}"#),
            chat("-1001234567890", "supergroup", "Example group")
        );
        assert_eq!(
            one(r#"{"id":"@example_channel","title":"Example channel","type":"channel"}"#),
            chat("@example_channel", "channel", "Example channel")
        );
    }

    /// Updates come oldest first; one without a message (an edit, a member change) is skipped.
    #[test]
    fn telegram_chat_is_the_latest_message() {
        let mut resp = updates(&[
            r#"{"id":111111111,"first_name":"First","type":"private"}"#,
            r#"{"id":222222222,"first_name":"Latest","type":"private"}"#,
        ]);
        resp.insert_str(
            resp.len() - 2,
            r#",{"update_id":9,"edited_message":{"chat":{"id":333333333,"type":"private"}}}"#,
        );
        assert_eq!(bot_chat(&resp), Ok(chat("222222222", "private", "Latest")));
        let empty = bot_chat(r#"{"ok":true,"result":[]}"#);
        assert_eq!(empty, Ok(None));
        assert_eq!(bot_result(&empty), "no_chat");
    }

    #[test]
    fn telegram_errors_keep_telegram_text() {
        let unauthorized =
            bot_chat(r#"{"ok":false,"error_code":401,"description":"Unauthorized"}"#);
        assert_eq!(
            unauthorized,
            Err("Telegram API error: Unauthorized (error_code: 401)".to_owned())
        );
        assert_eq!(bot_result(&unauthorized), "invalid_token");
        let conflict = bot_chat(
            r#"{"ok":false,"error_code":409,"description":"Conflict: can't use getUpdates method while webhook is active; use deleteWebhook to delete the webhook first"}"#,
        );
        assert_eq!(bot_result(&conflict), "network");
        assert_eq!(bot_result(&bot_chat("<html>Bad Gateway</html>")), "network");
    }
}
