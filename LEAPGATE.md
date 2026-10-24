# Leapgate 客户端实施契约

`leapgate-client` 是 `rustdesk/rustdesk` 的 fork。本文是 Leapgate 在上游之上做的改动的约定，写代码的人先读本文，再读总仓库的 `AGENTS.md` 和 `docs/architecture.md` §3.3。仓库里的 `AGENTS.md`、`CLAUDE.md` 是上游自带的，不改（合并上游时会冲突）。服务端的对应契约在总仓库 `server/LEAPGATE.md`。

## 1. 改动纪律

- Leapgate 的逻辑放在 `libs/leapgate`（crate 名 `leapgate`），上游文件里只加挂钩：一两行调用 `leapgate::…`，前面一行注释写 `// leapgate: <一句话>`，方便合并上游时一眼认出。
- 挂钩不改上游语句的结构，不挪动上游代码；能在调用点之前或之后插入的，不改调用点本身。
- 热点文件（`src/client.rs`、`src/client/io_loop.rs`、`src/server/connection.rs`、`src/server/port_forward_mux.rs`、`src/rendezvous_mediator.rs`、`src/common.rs`）每处挂钩不超过几行。
- 共用库 `libs/hbb_common` 是 `leapgate-cardo`（hbb_common 的 fork），客户端用它的 `leapgate/client` 分支；proto 新字段的字段号从 1000 起，避开上游以后可能用到的号段。proto 改动做成只含 proto 的提交，服务端那条线（`leapgate/server`）和客户端那条线各放一份，内容一致。
- 构建：Windows 用总仓库 `scripts/windows/`（`env.ps1`、`setup-toolchain.ps1`、`build-client.ps1`），工具链在 `C:\leapgate-build\`。子模块工作区用 LF（`core.eol=lf`、`core.autocrlf=false`）。

## 2. 已有的挂钩（第二期）

`libs/leapgate/src/`：`brand.rs`（名字、默认服务器构建时注入、`default_api_server()`）、`options.rs`（自建服务器时 IPv6 打洞默认开等默认值）、`rendezvous.rs`（没配会合服务器时等用户填好再连）、`update.rs`（关掉官方更新检查）、`lan.rs`（第三期：局域网多候选地址，§3）、`api.rs`、`sign.rs`、`report/`（第三期：上报与认证，§4）、`route/`（第三期：路由第二级，`relay_preference`、`self_id`、测速线程，§5）。具体挂钩位置用 `git grep -n "leapgate::\|leapgate_hooks"` 查。

主 crate 的 `src/leapgate_hooks.rs` 放需要调用上游私有函数的胶水代码（例如传进 `libs/leapgate` 的握手闭包）：`libs/leapgate` 调不到主 crate 的私有函数，又不想把闭包组装写在热点文件的调用处。上游文件里的挂钩只调用 `leapgate::…` 或 `crate::leapgate_hooks::…`。不要建 `src/leapgate.rs`，会和外部 crate `leapgate` 撞名。

## 3. 局域网直连：多候选地址（第三期第一项）

依据：总仓库 `docs/research/第三期/04-TUN下的局域网直连.md`（读码结论、mihomo/sing-tun 的路由行为、选网卡规则都在里面，动手前先读）。维护者 2026-10-23 定：先单独做这一项；一步到位做多候选地址（改 proto 和服务端转发）。

### 3.1 问题

局域网路径（服务端发现两端公网出口相同 → `FetchLocalAddr` → 被控端回 `LocalAddr` → 服务端转成 `PunchHoleResponse{is_local}` 给控制端）里，被控端报的 `local_addr` 是它连 hbbs 那条 socket 的本地地址，控制端连的时候也把源地址绑在自己连 hbbs 那条 socket 的本地地址上。开 TUN 代理（Clash Verge / mihomo 等）的机器上，这两个地址都是虚拟网卡的（例如 `198.18.0.1`），直连必然失败、1 秒后退回中继。

### 3.2 协议（已改，leapgate-cardo `375e2a3` / `a3d96d4`）

- `LocalAddr.leapgate_local_addrs = 1000`（`repeated bytes`）：被控端的局域网候选地址，`AddrMangle::encode` 编码（和 `local_addr` 同一种编码），最好的在前，端口都等于 `local_addr` 的端口。
- `PunchHoleResponse.leapgate_local_addrs = 1000`：服务端在 `is_local` 的响应里原样带给控制端。
- 原版 hbbs、原版客户端遇到这两个字段直接忽略。

### 3.3 被控端（`handle_intranet`）

- 新增 `libs/leapgate/src/lan.rs`，提供 `local_candidates(sock_local: SocketAddr) -> Vec<SocketAddr>`：
  - 只取 IPv4。候选来自物理网卡：排除虚拟/隧道网卡（Windows `IfType` 53/131/23/24，Wintun 是 53；接口名 `utun*`、`tun*`、`Mihomo`、`wintun` 一类）、`198.18.0.0/15`、`100.64.0.0/10`、回环、`169.254.0.0/16`；要求网卡有默认网关（顺带排除 WSL/Hyper-V 的 vEthernet）。
  - 排序：有线在前，再按链路速度；去重；最多 8 个。端口都用 `sock_local` 的端口。
  - `sock_local` 本身不是虚拟地址时，它排第一（和上游行为一致），后面再跟其他物理网卡地址。
  - 网卡枚举用 `GetAdaptersAddresses`（`windows` crate，和主 crate 同版本）。实测（2026-10-23，维护者台式机）：`default-net 0.14.1` 的 `get_interfaces()` 每次 4.2~5.3 秒，原因是它对一块断开但配了静态网关的网卡发 `SendARP` 等到超时，而且整个跳过 IfType 53 的网卡；`GetAdaptersAddresses` 每次 5~10 ms，还能读到在线状态、借此排除断开的网卡。不能用 `default_net::get_default_interface()`：开 TUN 时它选中的正是 TUN。
- 挂钩：组 `LocalAddr` 时，`local_addr` 改成候选的第一个（`sock_local` 是物理地址时就是它自己，不变），`leapgate_local_addrs` 填全部候选。
- 监听：被控端随后在 `local_addr` 的 IP:端口上开 18 秒、只收一条的监听（上游 `src/server.rs` `accept_connection_`）。候选里有和 `sock_local` 不同的 IP 时，改为监听 `0.0.0.0:同一端口`，否则照上游（Windows 上实测能在同一端口上绑 `0.0.0.0`）。监听地址由纯函数 `leapgate::lan::listen_addr(candidates, sock_local)` 算出，候选列表在 `handle_intranet_` 里算一次，作为新参数经 `accept_connection` 传到 `accept_connection_`（维护者 2026-10-23 同意这处签名改动：`pub(crate)`、只有一个调用方）。不在发出 `LocalAddr` 之后再枚举网卡：那会把"发出地址到开始监听"的空档从微秒拉长到 5~10 ms。
- 没有任何物理候选时，一切照上游。

### 3.4 控制端（收到 `is_local` 的 `PunchHoleResponse`）

- `leapgate_local_addrs` 非空时：对全部候选并发发起 TCP 连接，不绑定源地址（局域网网段的路由比 TUN 的更具体，自然从物理网卡出去；依据见笔记 04），TCP 连接的等待和上游局域网的 1 秒一致；第一个完成 TCP 连接**并且**完成安全握手的胜出，其余丢弃。握手另有 3 秒上限（维护者 2026-10-23 同意）：被控端的监听只收一条连接，其余连上的候选会排在队列里永远等不到握手回应，没有上限就要等上游的 `READ_TIMEOUT` 才回落中继。
- 全部失败（包括 TCP 连上了但握手失败）时，必须和上游超时一样回落中继，不能直接报错。笔记 04 指出上游"连上了但握手失败"会直接报错、不回落：在 Leapgate 路径里要兜住。
- 以下情况不试候选，完全照上游走：强制中继（`interface.is_force_relay()`：始终走中继、`ID/r`、配了代理）、没有可信的服务端签名（`signed_id_pk` 为空，或者按上游 `secure_connection` 的方式验签、核对 id 失败：这时握手不验证对端，没被接受的候选也会"握手成功"）、关了 TCP 打洞。
- 上游那次直连尝试只在它要连的 `peer_addr` 已经在候选里试过时才跳过；`peer_addr` 被过滤掉了（例如是公网地址），就照上游放行。
- 候选只留私网 IPv4（10/8、172.16/12、192.168/16）且端口非零，去重，最多 8 个；回环、链路本地、组播、公网地址一律丢掉（防恶意对端或服务端让控制端去连任意地址）。
- TCP 连上后本地 IP 不是物理网卡地址时（竞速前枚举一次网卡，用同一套 `is_physical` 判断），握手上限缩短到约 800 ms：这种连接可能是进了本机 TUN、被代理在本地"假握手"接住（等不到 SignedId），也可能是经 WireGuard/Tailscale 这类虚拟网卡走的真实路径（一个往返就能完成握手）。不当场判失败，否则经 VPN 回家的控制端会比上游还差。
- 判失败的额外情况：握手返回了但流没加密（有服务端签名却没加密，说明对端身份没验过，回落中继，由上游中继路径弹"未加密"确认）。
- 已知限制：两端不开 TUN、实际又不在同一局域网（服务端误判同一出口）时，候选竞速串在上游 `connect()` 前面，IPv6 打洞和中继回落比上游晚约 1 秒（TCP 连接超时）。开 TUN 时连接被本机 TUN 接住，最多多等约 800 ms 的短握手上限。
- `leapgate_local_addrs` 为空（被控端是原版，或服务端是原版 hbbs）时：照上游，只是自己连 hbbs 的 socket 本地地址是虚拟地址时不绑定源地址。
- 改动放 `libs/leapgate/src/lan.rs`，`src/client.rs` 里只留挂钩。

### 3.5 兼容

| 控制端 | 被控端 | 结果 |
|---|---|---|
| Leapgate | Leapgate | 修好：被控端报物理地址并监听 `0.0.0.0`，控制端不绑源地址、并发试候选 |
| Leapgate | 原版 | 被控端没开 TUN 时照常；开了 TUN 修不了（原版监听绑在虚拟地址上），用户只能在 TUN 里排除服务端地址 |
| 原版 | Leapgate | `local_addr` 已是物理地址；控制端没开 TUN 时能连上 |
| 任意 | 任意，服务端是原版 hbbs | 新字段被丢掉；`local_addr` 仍是物理地址，行为不比上游差 |

### 3.6 测试

- `libs/leapgate` 单元测试：候选选择（用可注入的网卡列表模拟：TUN 加有线、TUN 加无线、有线加无线、只有虚拟网卡、WSL vEthernet）、编码往返。
- 控制端并发连候选、握手失败回落中继的逻辑要能在不起真实 Leapgate 的情况下单测（把"连接 + 握手"抽成可注入的函数）。
- Windows 构建通过（`scripts/windows/build-client.ps1`）。
- 端到端由维护者测：两台 Windows（都开 Clash Verge TUN、都装 Leapgate），连同一个 leapgate-server；期望服务端 `conn_attempt.outcome = direct_lan`，控制端日志里连的是物理网卡地址。

### 3.7 不做

- IPv6 候选（IPv6 直连另有打洞路径）、UDP。
- 把连 hbbs 的 socket 绑到物理网卡（会绕过代理；服务端用域名而代理开 fake-ip 时必然失败）。
- macOS 客户端（第一阶段只做 Windows）。

## 4. 上报与认证（第三期 01）

依据：总仓库 `docs/第三期实施契约/01-上报与认证.md`（协议、服务端行为、取舍都在里面）。连的是 Leapgate 服务端时，心跳、sysinfo、被控端审计改走 `/api/leapgate/v1/`，每个请求用设备的 Ed25519 私钥（注册时上报的那把）签名；连原版服务端时照上游走旧接口。下面和契约原文有出入的地方以本文（即代码）为准。

### 4.1 挂钩

- `src/hbbs_http/sync.rs` `start_hbbs_sync_async`：`stop-service` 检查之后调 `leapgate::report::tick(...)`，返回 `true` 就 `continue`，本轮不发上游的心跳和 sysinfo（发过了，或在退避中）。
- `src/server/connection.rs` `post_audit_async` 第一行调 `leapgate::report::audit(&url, &v)`，返回 `Some` 就直接用它的结果，`None` 走上游。
- 两处都从上游传进来的 URL 拆出 API 根地址，和 `report::api_root()` 不同时走上游（打 `api root mismatch`）。
- 合并上游后：`git grep -n get_audit_server` 确认没有绕过 `post_audit_async` 的新审计出口；`common.rs` 的 `get_api_server` 有改动时同步 `report::api_root()`，`get_key` 有改动时同步 `sign::server_pk()`（都是重算，不含 Windows 按 exe 文件名取授权那一支）。

### 4.2 能力缓存

- 持久键：Config 选项 `leapgate-api-caps`，值 `<API 根地址>\n<feature,feature,...>`。只由服务进程写（第一次确认支持时、之后每次成功心跳，整个值变了才写）；界面进程经上游的选项同步读到，`server_is_leapgate()`、`has_feature()` 每次按 `api_root()` 现算、和持久值比，不依赖心跳跑过。心跳下发的策略合并时跳过 `leapgate-` 开头的键。
- 进程内状态按根地址记：未知 / 支持 / 不支持（10 分钟后重探）。持久值里的根地址和构建时注入的默认地址直接算支持。
- 只有未确认的根地址回 404/405，或回 2xx 但不是 Leapgate 应答（没有 `api`），才判不支持、退回上游；已确认的根地址遇到这些按失败处理，不降级（旧接口不签名、可能接受无效证书）。

### 4.3 传输和验签

- 每次请求新建 reqwest 客户端：不用系统代理，按 `Config::get_socks()` 配代理（照上游 `configure_http_client!`）；rustls，同时信系统证书库和 reqwest 内置的 webpki 根证书（Windows 缺的根证书要等系统自己的验证用到时才从微软下载，rustls 只读本地已有的，新装系统可能缺 API 证书的根；系统证书库留着认用户导入的私有 CA）；没有不安全回退，`allow-insecure-tls-fallback` 不起作用；不跟随重定向，3xx 算失败；每次尝试 12 秒。
- 配了 Key 时响应必须验签通过（`Leapgate-Server-Sig`），Key 无效则全部失败。
- 时钟：验过签的 401 带 `time` 时采信、重签后立即重试一次；2xx 的 `time` 只在和当前偏差超过 30 秒时采信（每次都跟会让时间戳随延迟来回抖，撞上服务端的防重放下限）。
- 401 的 `error` 只取固定集合（`bad_auth`、`stale_time`、`replay`、`unknown_device`、`bad_signature`），其余记成 `other`；未签名的 401 不采信时间、不重试，除 `bad_auth`（服务端本来就不签）外都按验签失败记日志。
- 心跳失败退避 3、6、12、24、48、60 秒；审计照上游重试表（间隔 10、30 秒，总时限 120 秒），400/413 不重试。

### 4.4 固定日志

每种每分钟最多一条（`throttled_log!`），文字固定，端到端测试按此查找：

- `leapgate report: {root} supports Leapgate API, features [{features}]`
- `leapgate report: {root} has no Leapgate API ({status}), using legacy reports`
- `leapgate report: 401 {error}, clock offset now {offset}s`
- `leapgate report: server signature check failed`
- `leapgate report: api root mismatch, using legacy reports`

## 5. 路由第二级（第三期 02）

依据：总仓库 `docs/第三期实施契约/02-路由第二级.md`（协议、服务端整端替换的选路规则、取舍都在里面）。Leapgate 客户端在服务进程里测到每台候选中继的 TCP 建连耗时，随 Leapgate 心跳上报；leapgate-server 选中继时用实测代替 GeoIP 估计。被控端连 leapgate-server 时照用服务端选的中继，本地 `relay-server` 不再生效。下面和契约原文有出入的地方以本文（即代码）为准。

### 5.1 挂钩（上游文件 2 处、6 行）

- `src/rendezvous_mediator.rs` `get_relay_server` 开头：`leapgate::route::relay_preference(&provided)` 返回 `Some` 就直接用它。条件是服务端给了中继并且 `report::server_is_leapgate()` 为真（按持久化的能力记录现算，进程重启后、心跳被限速时都成立）；连原版 hbbs 时它给的是轮询结果，本地 `relay-server` 照上游优先。`get_relay_server` 只有 `handle_intranet`、`handle_punch_hole` 两个调用点，被控端主动发起中继也用它们的结果。
- `src/client.rs` `_start_inner` 的 `PunchHoleRequest` 字面量：`leapgate_from_id: leapgate::route::self_id()`。`self_id()` 用 `Config::get_id_or(String::new())`，不用 `Config::get_id()`（本进程没有 id 时它会就地生成并落盘，界面进程会造出和服务进程不一致的 id）；拿不到就发空串，服务端按估计值算。`PunchHoleRequest` 全仓库只在这里构造。
- proto：`PunchHoleRequest.leapgate_from_id = 1000`（string，leapgate-cardo 客户端线 `9c6e152`），`rendezvous.proto` 文件头注明 Leapgate 字段占 1000~1999。

### 5.2 心跳里的字段

- 请求：`routing_rev`（手里那份候选列表的 rev，没有为 0）；`probes`（最近一轮有效测量，没有就省略）：`{ routing_rev, age_s, rtt: { 原串: 毫秒 }, down: [原串] }`。只有这一轮的 rev 等于当前列表、并且结束不超过 900 秒才发。
- 响应：`routing`（`{ rev, probe_interval_secs, relays }`，服务端只在请求的 `routing_rev` 和它的不同时下发）。`on_heartbeat_ok` 每次成功的心跳都调：没配 Key（`sign::server_pk()` 不是 `Ok(Some(_))`）时什么都不做，不采用 `routing`、不刷新确认时间，防明文 HTTP 上的中间人往 `relays` 里塞任意地址、把设备当端口扫描器；配了 Key 时刷新确认时间，`routing` 解析失败整个忽略，`probe_interval_secs` 限在 60~3600，`relays` 截到 32 台；rev 变了就换列表、清掉旧结果，第一次拿到非空列表时起测速线程。
- `reset()`（API 根地址变了、能力判为不支持时由 `report` 调）清空状态。

### 5.3 测速线程（`route/probe.rs`）

- 进程内一个专用 `std::thread`（`Once`），阻塞的 `std::net`，不用 tokio：心跳跑在 `sync.rs` 的单线程运行时上，那里每个 tick 还会同步调阻塞函数，计时会被拉长。
- 测的条件：有非空列表、15 分钟内有成功的心跳。新列表（rev 变了）先等 10~30 秒随机时间再测第一轮，之后每轮间隔 `interval × (0.9~1.1)`；状态变了用 `Condvar` 唤醒重算。
- 每轮开头：开了代理（`Config::is_proxy()`）、开了 WebSocket（`use_ws()`）或没配 Key 时不测，并清掉旧结果；然后取一次网卡快照 `lan::physical_snapshot()`。
- 各中继并发（每台一个线程，测完即退）：`check_port(host, 21117)` 后系统解析一次（不计时），按返回顺序逐个试、取第一个连上的；每台测 3 次、间隔 200 毫秒，`connect_timeout` 3 秒，连上立刻关。成功的取最小值，毫秒向上取整、至少 1；3 次都失败进 `down`。
- 三条作废规则（纯函数 `summarize`），任一命中整轮作废、不上报、清掉旧结果：
  - 本地地址不在物理网卡上（挡本机 TUN：TUN 在本机完成握手，本地地址是 TUN 的）。
  - 对端地址在 `198.18.0.0/15`，不看耗时（RFC 2544 基准测试段，不分配给互联网主机；中继解析到这里说明是代理的 fake-ip，答话的一定是代理。路由器 fake-ip 加 Wi-Fi 时代答常在 2 毫秒以上，第三条拦不住）。
  - 对端是公网地址的中继任一次快于 2 毫秒（挡路由器透明代理当场回 SYN-ACK）。"公网"指不是私网、回环、链路本地、`100.64.0.0/10`、IPv6 ULA。
- 起不了测速子线程时这一轮作废，打一条 warn（`leapgate route: probe round dropped, cannot start a probe thread: …`）。
- 一轮测完时列表已经换了：结果照写，`probes()` 按 rev 不发它。

### 5.4 `lan.rs` 的双地址族（为测速做，03 块其余部分没做）

- 网卡枚举改成 `AF_UNSPEC`，`Nic` 多一个 `ipv6`（只收 `DadState` 为 Preferred 的单播地址，丢掉链路本地）。网关判断只看 IPv4，和以前一样。
- `is_physical` 参数改成 `IpAddr`：IPv6 地址在某块在线、非虚拟网卡的 `ipv6` 里就算物理。
- 局域网候选（§3）的行为不变：被控端候选、控制端收候选、`handshake_timeout`、`controller_bind_addr` 都还只看 IPv4。契约 03 的 IPv6 候选、网卡描述关键字、`has_gateway` 拆分、`listen_dual` 没做。
- 非 Windows 上枚举为空，测量全部作废（第一阶段只做 Windows）。

### 5.5 固定日志

每种每分钟最多一条，文字固定，端到端测试按此查找：

- `leapgate route: probe round dropped, local address {ip} not on a physical adapter`
- `leapgate route: probe round dropped, {host} answered in {us}us (proxy?)`（fake-ip 和 2 毫秒两条规则共用）
- `leapgate route: probe round dropped, cannot start a probe thread: {error}`（warn）

### 5.6 不配也能用：自动降级与可选优化

Leapgate 不要求用户配置任何代理规则。测量被本机 TUN 或路由器透明代理接住时会被自动识别（本地地址不在物理网卡上、公网中继快于 2 毫秒），整轮作废，服务端按估计值选路。可选优化：本机开 TUN 代理时把中继的地址排除在 TUN 之外、中继域名放进 fake-ip 过滤名单；路由器透明代理只代理 TCP 时把到中继的 TCP 设成直连。配了的机器才有第二级实测。

### 5.7 兼容

| 情况 | 结果 |
|---|---|
| Leapgate ↔ Leapgate，服务端 leapgate-server | 两端都有实测时服务端按实测选；被控端照用服务端选的中继 |
| Leapgate 控制端 → 原版被控端 | 控制端一段实测；被控端仍按上游优先用本地 `relay-server` |
| 原版控制端 → Leapgate 被控端 | 没有 `leapgate_from_id`，控制端一段估计；被控端一段实测、照用服务端选的中继 |
| 服务端是原版 hbbs | Leapgate 心跳 404 → 不测速，`relay_preference` 返回 `None`，和上游一样；`leapgate_from_id` 被忽略 |
| leapgate-server 只有 01、没有 02 | 响应不带 `routing`，不测速；`relay_preference` 照常生效 |
| 没配 Key | 不采用 `routing`、不测速；`relay_preference` 照常生效 |
| 开了代理或 WebSocket | 不测、不报；`relay_preference` 照常生效 |

### 5.8 已知限制

- 测的是 SYSTEM 服务进程的网络路径，用户会话走分用户 VPN、按应用分流的代理时可能和实际连接不同。
- 经全隧道 VPN（WireGuard 全局、Tailscale 出口节点）上网的设备测量其实是真的，也被作废（Wintun 网卡不算物理）。
- 系统 DNS 解析没有超时，某台中继解析卡住时这一轮推迟（只在测速线程里）。
- IPv4 字面量中继在只有 IPv6 的网络里会进 `down`（真实连接走 `nip.io` NAT64，测速不做这一步）。
- 路由器代答落在 2 毫秒以上时拦不住；验收时如果一律看到 2~3 毫秒，把阈值提到 5 毫秒。
- `relay_preference` 只看 API 根地址是不是 leapgate-server，不看被控端实际连的会合服务器；两者指向不同服务器的配置下可能选错中继。
