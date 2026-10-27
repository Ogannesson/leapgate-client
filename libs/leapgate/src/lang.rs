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
    (exit::NOT_SUPPORTED, "对方设备不支持作为出口"),
    ("Add exit node", "添加出口"),
    ("Exit node", "出口"),
    ("Exit nodes", "出口节点"),
    ("Local proxy port", "本地代理端口"),
    ("Connects on first use", "首次使用时连接"),
    ("Copy SOCKS5 address", "复制 SOCKS5 地址"),
    ("Copy HTTP address", "复制 HTTP 地址"),
    (
        "Only TCP. Only programs set to use this proxy go through the exit node. Firefox: Settings, Network Settings, Manual proxy configuration, SOCKS Host 127.0.0.1 and the port of this row, SOCKS v5, and tick \"Proxy DNS when using SOCKS v5\". Chrome and Edge: use a proxy extension such as SwitchyOmega, or start them with the parameter below. Sites you visit see the remote network's address; the remote device logs only refused destinations.",
        "只支持 TCP，只有设置了这个代理的程序才走出口。Firefox：设置 → 网络设置 → 手动配置代理，SOCKS 主机填 127.0.0.1、端口填本行的端口，选 SOCKS v5，并勾选\"使用 SOCKS v5 时代理 DNS 查询\"。Chrome 和 Edge：用 SwitchyOmega 这类代理扩展，或者带下面的参数启动。你访问的网站看到的是对方网络的地址；对方设备只记录被拒绝的目标地址。",
    ),
    ("Log in to see the exit nodes you can use", "登录后才能看到你能用的出口"),
    (
        "The current server does not provide an exit node directory",
        "当前服务器不提供出口目录",
    ),
    ("No exit node is available right now", "目前没有可用的出口"),
    ("Failed to load the exit node list", "无法获取出口列表"),
    (
        "You can also enter a device ID, open TCP tunneling and add an exit node",
        "也可以输入设备 ID，打开 TCP 隧道后添加出口",
    ),
    ("Use", "使用"),
    ("Mine", "我的"),
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

static CONTROLLED: &[(&str, &str)] = &[
    ("Exit node settings", "出口节点"),
    ("Allow this device to act as an exit node", "允许作为出口"),
    ("Acting as an exit node", "作为出口"),
    ("Allowed destination networks", "放行网段"),
    (
        "Enter IP addresses or CIDR networks, separated by commas, spaces or newlines. Hard-blocked addresses cannot be allowed.",
        "输入 IP 或 CIDR 网段，用逗号、空白或换行分隔。硬拒地址无法放行。",
    ),
    ("Invalid IP address or CIDR network", "IP 地址或 CIDR 网段无效"),
    (
        "Exit traffic leaves through this device's physical network adapter, bypassing its proxy and VPN.",
        "出口流量从本机网卡直接出去，不经过本机的代理或 VPN。",
    ),
    (
        "For an unattended exit, set a permanent password and choose \"Accept sessions via password\".",
        "无人值守的出口请设固定密码，审批方式选“只允许密码访问”。",
    ),
    (
        "To keep exit users off the local network, also turn off \"Enable TCP tunneling\".",
        "要让出口用户碰不到局域网，请同时关掉“允许建立 TCP 隧道”。",
    ),
    (
        "Only refused destination IP addresses are logged, at most one entry per minute; successful destinations and domain names are not logged.",
        "只记录被拒绝的目标 IP，每分钟最多一条；不记录成功访问的目标和域名。",
    ),
    (
        "This switch is independent of the access mode, including Screen Share.",
        "此开关独立于访问模式，选择“仅共享屏幕”也不会关闭出口。",
    ),
];

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
