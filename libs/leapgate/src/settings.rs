//! The settings page's saving (S9) and its Telegram check (S10), `LEAPGATE.md` §10.13. The
//! IPC itself is in the main crate (`src/leapgate_hooks/settings.rs`).

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

/// S10: upstream's `get_chatid_telegram` result as `ok`, `invalid_token` (Telegram's 401 or
/// 404), `no_chat` (no message to the bot yet) or `network` (every other error).
pub fn bot_result(result: &Result<Option<String>, String>) -> &'static str {
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
        let err = |s: &str| Err(s.to_owned());
        assert_eq!(bot_result(&Ok(Some("123456789".to_owned()))), "ok");
        assert_eq!(bot_result(&Ok(None)), "no_chat");
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
}
