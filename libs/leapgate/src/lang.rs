//! Chinese for Leapgate's own strings, looked up after upstream's tables (hook in `src/lang.rs`
//! `translate_locale`), so it never overrides an upstream translation. The key is the English
//! text, with `{}` where the UI writes `{value}`, as upstream's tables do.
//!
//! `CONTROLLER` holds the controller's strings and `CONTROLLED` the controlled side's; the two
//! are kept apart so the two sides add rows without touching each other's lines.

use crate::exit;

static CONTROLLER: &[(&str, &str)] = &[
    (exit::MSG_NOT_ENABLED, "对方设备没有开启出口"),
    (
        exit::MSG_NEED_MUX,
        "对方设备只接受多路复用的端口转发。请升级客户端，并在设置里打开\"端口转发复用同一条连接\"",
    ),
    (exit::MSG_NEED_ENCRYPTION, "出口只接受加密的连接"),
    (
        exit::MSG_BLOCKED,
        "出口拒绝了这个目标：它在对方的局域网里或就是对方设备本机，或者对方网络的 DNS 返回了 fake-ip 地址",
    ),
    (
        exit::MSG_FAKE_IP_LITERAL,
        "目标是本机代理软件分配的 fake-ip 地址，请在程序的代理设置里改用远程 DNS（socks5h）",
    ),
    (exit::PEER_TOO_OLD, "对方版本过旧，无法做端口转发"),
];

pub fn get(lang: &str, key: &str) -> Option<&'static str> {
    if lang != "zh-cn" {
        return None;
    }
    CONTROLLER
        .iter()
        .chain(CONTROLLED)
        .find(|(k, _)| *k == key)
        .map(|(_, v)| *v)
}

static CONTROLLED: &[(&str, &str)] = &[];

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn tables_have_unique_keys_and_complete_translations() {
        let mut keys = HashSet::new();
        for (key, zh) in CONTROLLER.iter().chain(CONTROLLED) {
            assert!(keys.insert(*key), "duplicate key: {key}");
            assert!(!zh.is_empty(), "empty translation: {key}");
            assert_eq!(
                key.matches("{}").count(),
                zh.matches("{}").count(),
                "placeholders differ: {key}"
            );
        }
    }
}
