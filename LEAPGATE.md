# Leapgate 客户端实施契约

`leapgate-client` 是 `rustdesk/rustdesk` 的 fork。本文是 Leapgate 在上游之上做的改动的约定，写代码的人先读本文，再读总仓库的 `AGENTS.md` 和 `docs/architecture.md` §3.3。仓库里的 `AGENTS.md`、`CLAUDE.md` 是上游自带的，不改（合并上游时会冲突）。服务端的对应契约在总仓库 `server/LEAPGATE.md`。

## 1. 改动纪律

- Leapgate 的逻辑放在 `libs/leapgate`（crate 名 `leapgate`），上游文件里只加挂钩：一两行调用 `leapgate::…`，前面一行注释写 `// leapgate: <一句话>`，方便合并上游时一眼认出。
- 挂钩不改上游语句的结构，不挪动上游代码；能在调用点之前或之后插入的，不改调用点本身。
- 热点文件（`src/client.rs`、`src/client/io_loop.rs`、`src/server/connection.rs`、`src/server/port_forward_mux.rs`、`src/rendezvous_mediator.rs`、`src/common.rs`）每处挂钩不超过几行。
- 共用库 `libs/hbb_common` 是 `leapgate-cardo`（hbb_common 的 fork），客户端用它的 `leapgate/client` 分支；proto 新字段的字段号从 1000 起，避开上游以后可能用到的号段。proto 改动做成只含 proto 的提交，服务端那条线（`leapgate/server`）和客户端那条线各放一份，内容一致。
- 构建：Windows 用总仓库 `scripts/windows/`（`env.ps1`、`setup-toolchain.ps1`、`build-client.ps1`），工具链在 `C:\leapgate-build\`。子模块工作区用 LF（`core.eol=lf`、`core.autocrlf=false`）。

## 2. 已有的挂钩（第二期）

`libs/leapgate/src/`：`brand.rs`（名字、默认服务器构建时注入、`default_api_server()`）、`options.rs`（自建服务器时 IPv6 打洞默认开等默认值）、`rendezvous.rs`（没配会合服务器时等用户填好再连）、`update.rs`（关掉官方更新检查）、`lan.rs`（第三期：局域网多候选地址，§3；05 加了网卡描述、`has_gateway_v6`、IPv6 地址属性、地址分类、网络代价，§7）、`api.rs`、`sign.rs`、`report/`（第三期：上报与认证，§4）、`route/`（第三期：路由第二级，`relay_preference`、`self_id`、测速线程，§5）、`ice/`（第三期 05：自研 ICE，`mod`、`gather`、`check`、`stun`、`sig`、`dns`，§7）、`dns.rs`（第四期：向一台 DNS 服务器问 A、AAAA 的报文和单服务器查询 `ask`，ICE 解析会合服务器、出口解析目标共用；ICE 怎么挑服务器、怎么回落系统解析仍在 `ice/dns.rs`）、`exit/`（第四期：应用出口，§9；`mod` 放哨兵、两个选项名、固定文案、被控端的登录关口和控制端登录后的判断，`policy` 是被控端的地址策略，`dial` 是被控端的解析、过滤和连接，`proxy` 是控制端本地 SOCKS5/HTTP CONNECT 握手，`directory` 是控制端取出口目录）、`lang.rs`（第四期：Leapgate 自己界面文案的中文，`CONTROLLER`、`CONTROLLED` 两张表，上游查表之后才查，不会盖掉上游已有的译文）。具体挂钩位置用 `git grep -n "leapgate::\|leapgate_hooks"` 查。

主 crate 的 `src/leapgate_hooks.rs` 放需要调用上游私有函数的胶水代码（例如传进 `libs/leapgate` 的握手闭包）：`libs/leapgate` 调不到主 crate 的私有函数，又不想把闭包组装写在热点文件的调用处。上游文件里的挂钩只调用 `leapgate::…` 或 `crate::leapgate_hooks::…`。不要建 `src/leapgate.rs`，会和外部 crate `leapgate` 撞名。05 在这里加了 `race_ice`（控制端：启用条件、到会合服务器的信令 TCP、验 S 签过的被控端 IdPk、检查、KCP connect、`secure_connection`、和上游路径竞速）和 `on_ice_offer`（被控端：spawn、验签解密去重、名额、回 ANSWER、KCP accept、`create_tcp_connection` 用 ICE 选中的远端地址、会话期间看 KCP 静默），见 §7。第四期加了子模块 `src/leapgate_hooks/exit.rs`：控制端的出口监听循环 `run`（本地代理握手、第一个本地连接到来时建隧道、登录后按 `exit::after_login` 决定用、停还是冷却）和出口目录的 `get_common`，见 §9。

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

- 局域网多候选只做 IPv4 TCP；IPv6 和 UDP 的局域网直连由自研 ICE 做（§7）。
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

- 持久键：Config 选项 `leapgate-api-caps`，值 `<API 根地址>\n<feature,feature,...>`。只由服务进程写（第一次确认支持时、之后每次成功心跳，整个值变了才写）；界面进程经上游的选项同步读到，`server_is_leapgate()`、`has_feature()` 每次按 `api_root()` 现算、和持久值比，不依赖心跳跑过。心跳下发的策略合并时跳过 `leapgate-` 开头的键。界面进程用 `has_feature("ice")` 决定启不启动 ICE（§7）。
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
- 每轮开头：开了代理（`Config::is_proxy()`）、开了 WebSocket（`use_ws()`）或没配 Key 时不测，并清掉旧结果。
- 测速和真实中继连接走同一条路（2026-10-25 改，契约 02a）：不绑本地地址，系统解析、系统路由，开着 TUN 就进 TUN、由代理按它的规则转发。代理会在本地或路由器上先完成握手、之后才去连中继，所以不计握手时间，计的是中继关连接：hbbr 的 `make_pair_` 收到不是 `RequestRelay` 的首帧就直接返回，不打日志。
- 各中继并发（每台一个线程，测完即退）：`check_port(host, 21117)` 后系统解析一次（不计时，fake-ip 下得到 `198.18.x` 照用），按返回顺序取第一个连上的（`connect_timeout` 3 秒）。连上后等 `SETTLE`（1.5 秒），让代理把上游连好；等完非阻塞地 `peek` 一次，连接已关、出错或已收到数据就判这次失败（hbbr 收到首帧前既不发数据也不关；代理连不上中继、规则拒绝时会在这段时间里关掉）。然后发 1 字节 `0x00`（长度为 0 的帧）开始计时，读到干净的 EOF 停表；3 秒内没读到、读到数据或出错都判失败。每台测 3 次、间隔 200 毫秒，成功的取最小值，毫秒向上取整、至少 1；3 次都失败进 `down`。
- 作废规则只有一条（纯函数 `summarize`）：对端是公网地址的中继任一次在 2 毫秒内关，整轮作废、不上报、清掉旧结果。真实路径至少一个往返，比这还快说明关连接的不是中继（代理规则拒绝、安全软件见数据就断）。"公网"指不是私网、回环、链路本地、`100.64.0.0/10`、IPv6 ULA；fake-ip 段 `198.18.0.0/15` 和 `fdfe:dcba:9876::/48`（mihomo 的 IPv6 TUN 和 fake-ip 段）算公网。
- 起不了测速子线程时这一轮作废，打一条 warn（`leapgate route: probe round dropped, cannot start a probe thread: …`）。
- 一轮测完时列表已经换了：结果照写，`probes()` 按 rev 不发它。

### 5.4 `lan.rs` 的双地址族（原为测速做，03 块其余部分没做）

- 网卡枚举改成 `AF_UNSPEC`，`Nic` 多一个 `ipv6`（只收 `DadState` 为 Preferred 的单播地址，丢掉链路本地）。
- `is_physical` 参数改成 `IpAddr`：IPv6 地址在某块在线、非虚拟网卡的 `ipv6` 里就算物理。
- 局域网候选（§3）的行为不变：被控端候选、控制端收候选、`handshake_timeout`、`controller_bind_addr` 都还只看 IPv4。
- 网卡描述关键字、`has_gateway_v4/v6`、IPv6 地址属性、地址分类、网络代价由 05 做（§7.2）；契约 03 的 IPv6 局域网候选、`listen_dual` 不做（03 收缩）。
- 05 让 `is_virtual` 变严（加了描述和名字的关键字，§7.2）：它也作用于 `is_physical`，所以原来只靠"有没有 IPv4 网关"漏进来的 ZeroTier、VMware 之类，现在在局域网多候选里也判成虚拟，提前去掉一个连不通的候选。是有意的，`lan.rs` 有回归测试钉住。`Nic.ipv6` 换成带属性的结构，`is_physical` 对每个地址照旧都认。
- 测速从 2026-10-25 起不再看网卡（§5.3），原来给它用的 `physical_snapshot` 已删。`is_physical` 的 IPv6 分支因此暂时只有测试在用，留着不动。

### 5.5 固定日志

每种每分钟最多一条，文字固定，端到端测试按此查找：

- `leapgate route: probe round dropped, {host} closed in {us}us (not the relay?)`（2 毫秒下限）
- `leapgate route: probe round dropped, cannot start a probe thread: {error}`（warn）

### 5.6 不配也能用

挪到 §8。

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
- 依赖原版 hbbr 对非 `RequestRelay` 首帧静默关闭。哪天改成等到 30 秒超时，测量全判 `down`，服务端按"全 `down` 时忽略"退回估计；改成打日志就是噪音。
- 代理连上游超过 1.5 秒时，超出的部分算进往返（偏大）；代理等收到数据才让节点去连中继时，多算一次节点到中继的握手（推测）。
- 经代理时中继主机在而 hbbr 没起：代理多半在等待期间就关连接、判失败；晚于 1.5 秒才关的会被当成 hbbr 关连接，量出偏小的数。服务端健康检查会先把这台判不可达。
- 代理收到上游的关连接后不及时关本地连接时，3 秒内没 EOF，判失败；全部这样时服务端退回估计。mihomo 是及时的（实测），其他代理软件推测。
- 代理在多个节点间负载均衡、每条连接选不同节点时，3 次取最小，数字偏向最快的节点。
- 同机房中继和 fake-ip 下用域名配的局域网中继会被 2 毫秒下限误杀，整轮退回估计。
- 中继解析到回环地址（和设备同机）时，hbbr 把连接当控制台命令处理，1 秒没收到命令就关，测速在等待期间判失败，这台一直是 `down`（真实中继连接在这种情况下同样用不了）。
- 系统 DNS 解析没有超时，某台中继解析卡住时这一轮推迟（只在测速线程里）。
- IPv4 字面量中继在只有 IPv6 的网络里会进 `down`（真实连接走 `nip.io` NAT64，测速不做这一步）。
- `relay_preference` 只看 API 根地址是不是 leapgate-server，不看被控端实际连的会合服务器；两者指向不同服务器的配置下可能选错中继。

## 6. 默认 ID 加盐（第三期 03）

依据：总仓库 `docs/第三期实施契约/03-局域网判定与候选.md` §4.4。

- 问题：上游第一次生成 ID 时取第一块有 MAC 的网卡，把 MAC 后 4 字节截成 29 位当 ID（`Config::get_auto_id`）。同一台机器上的原版 RustDesk 和 Leapgate 算出的是同一个数，指向同一台服务器时两边互抢这个 ID，从别处连它时时而连到原版、时而连到 Leapgate。
- 位置：leapgate-cardo 客户端线（`leapgate/client`，`8a5cf22`）。新文件 `src/leapgate_id.rs` 的 `salt`：`sha256("leapgate-auto-id\0" ‖ 上游 ID 的 4 字节小端)` 取前 4 字节按小端转 `u32`，再 `(h & 0x0FFF_FFFF) | 0x1000_0000`，结果固定 9 位（268435456~536870911）。`src/config.rs` 的 `get_auto_id` 在 `id &= 0x1FFFFFFF;` 后加 2 行挂钩；`src/lib.rs` 加模块声明，安卓和 iOS 不编（那里上游本来就用随机 ID）。不放 `libs/leapgate`，因为 `get_auto_id` 在 hbb_common 里，而 `libs/leapgate` 依赖 hbb_common。服务端不生成 ID，服务端线不放。
- 影响：只有第一次生成 ID 的设备（配置里 `id` 为空）拿到加盐后的 ID，已有 ID 的设备不变。`allow-hostname-as-id` 打开时用主机名，上游收到 `UUID_MISMATCH` 时换的随机 10 位 ID，都不经过这里。日志 `Generated id` 打的是加盐后的值。
- 已装 Leapgate、又要和原版指向同一服务器的机器：停掉 Leapgate，删掉配置文件 `Leapgate.toml`（安装版是服务进程那份）里的 `id` 和 `enc_id` 两项，再启动，Leapgate 按加盐后的规则重新生成 ID。界面上的"修改 ID"在 leapgate-server 上不可用（回 `NOT_SUPPORT`）。
- 测试：`leapgate_id::tests` 一条，三组固定输入的输出和另一种实现（Python）算出的值逐字一致，都是 9 位、和输入不同。端到端（契约 03 §6 第 4 项）留到统一验收。

## 7. 自研 ICE（第三期 05）

依据：总仓库 `docs/第三期实施契约/05-自研ICE.md`（线上格式、常数、测试向量、取舍和读码依据都在里面，§2 是两端共用的协议）。Leapgate 控制端连 Leapgate 被控端时，在上游路径之外再跑一条自己的 ICE：两端在每个物理网卡地址上各绑一个 UDP socket，收集 host 候选和向会合服务器问到的 srflx 候选，经 leapgate-server 转发的信令交换，用 STUN 检查逐对实测，选中一对后在它上面跑上游原样的 KCP 和 `secure_connection`。ICE 和上游路径竞速，ICE 失败从不对外报错。下面和契约原文有出入的地方以本文（即代码）为准。

### 7.1 挂钩（上游文件 2 处）和合并上游时的核对点

- H-1 `src/client.rs` `Client::start`：`Self::_start(...)` 先存成 `upstream`，再 `match crate::leapgate_hooks::race_ice(peer, key, &interface, upstream).await`。不启用 ICE 时 `race_ice` 直接 `upstream.await`，和上游逐字节相同。端口转发、RDP 也经 `Client::start`，同样走这里。
- H-3 `src/rendezvous_mediator.rs` `handle_resp`：兜底 `_ => {}` 之前加 `LeapgateIce` 分支，调 `crate::leapgate_hooks::on_ice_offer(ice, self.host.clone(), server.clone())`。它内部 `tokio::spawn`、吞掉所有错误（`handle_resp` 返回 `Err` 会让 mediator 退出重连）。UDP、TCP 两种 mediator 都走 `handle_resp`。
- 合并上游后核对：`Client::_start` 的返回三元组和前置分支（`is_incoming_only`、直连 IP、`other_server`）；`relay_fallback_delay_ms()` 的选项名、解析规则和默认值 2500（`leapgate_hooks` 照抄了一份）；上游竞速规则（`race_transports_prefer_webrtc` 的"直连立即赢、中继压窗口"，`race_legs` 照它写）；端口转发里 `Client::start` 仍被 `tokio::spawn`（`race_ice` 的 future 因此必须是 `Send`）；`handle_resp` 的结构；`KcpStream::connect/accept` 的签名和 SYN 包头（`endpoint.connect(timeout, 0, 0, …)`）；`create_tcp_connection` 的签名；`secure_connection`、`secure_tcp_required`、`get_rs_pk` 的签名；`get_udp_punch_enabled`、`get_ipv6_punch_enabled` 仍是这两个选项的读法。

### 7.2 候选

- 能出候选的网卡：在线、不是虚拟网卡、有默认网关（IPv4 或 IPv6 任一）。虚拟网卡按 IfType（23/24/53/131）、名字（`tun`/`utun` 开头，含 `mihomo`/`wintun`）和描述或名字里的关键字判：`meta tunnel`、`wintun`、`wireguard`、`tailscale`、`zerotier`、`tap-windows`、`openvpn`、`vpn`、`vmware virtual ethernet`、`vmnet`、`virtualbox host-only`、`wi-fi direct`。不排 `hyper-v`/`vethernet`：外部虚拟交换机下宿主机上网的口就是它（有网关）；内部交换机和 WSL 的没有网关，靠网关那条排掉。
- host IPv4：有 IPv4 默认网关的网卡上的私网 IPv4，和网卡上直接配的公网 IPv4（要拿到反射地址证明才过得了服务端），最多 4 个。host IPv6：全局地址和 ULA（mihomo 的 `fdfe:dcba:9876::/48` 除外），每个 /64（按地址高 64 位分组）只留一个、有临时地址时只留临时地址，DHCPv6 地址当稳定地址，最多 4 个。上限内代价低的网卡在前，同代价按链路速度从高到低。
- 每个 host 地址绑一个 socket（不建 `0.0.0.0` socket：开 TUN 时它的出口进隧道）。Windows 上绑好后、第一次发包前关掉 `SIO_UDP_CONNRESET`，接收出错一律继续收（该 socket 停 10 毫秒），否则对端某个会引来 ICMP 的候选（对端的 TUN 地址、已关的端口）会让 socket 静默失效。
- srflx：每个 host socket 向会合服务器同地址族的地址（每次 ICE 解析一次 `host:port`，见下一条）发 100 字节的 Binding 请求，第 0、200、400 毫秒各发一次（重发沿用第一次的事务号），600 毫秒（`GATHER_WAIT`，含解析）为止；回包只按事务号认，不看来源。映射地址不等于底座时成为 srflx，同一映射只留一份，IPv4 最多 4 个、IPv6 最多 2 个；`LEAPGATE-PROOF` 原样转发、不解析。
- 会合服务器地址的解析（`ice/dns.rs`）：IP 字面量（含 `[v6]:port`）直接用。域名不只问系统：mihomo/Clash 的 TUN 开着 fake-ip 时，系统解析给的是 `198.18/15` 的假地址，从物理网卡 socket 发过去永远没有回包，两端都没有 srflx。所以先问**物理网卡自己的 DNS 服务器**（`GetAdaptersAddresses` 里每块网卡的 DNS 服务器列表；每个 host 地址带上本网卡同地址族、不属于契约 §2.7 丢弃类的前两个，所以链路本地、Windows 的 `fec0:0:0:ffff::` 占位、`198.18/15` 都不问），按 host 地址的顺序取前 2 个服务器，各用一个单独的临时 UDP socket（绑在这块网卡同地址族的地址上，不用 ICE 的 socket）同时发 A 和 AAAA 查询（随机事务号，RD=1）。只认来自该服务器 53 端口、事务号相同、QR=1、问题段一致（大小写不论）的响应，RCODE 不为 0 当这个服务器没有答案；从回答段取与问题同类型的记录（CNAME 链里的照收，不跟压缩指针）。到截止时间只回了 A、AAAA 中的一个时用已收到的那个。系统解析同时起，只当回退：物理网卡 DNS 有地址就用它（哪怕系统的先到：企业分离 DNS 下系统给的可能是内网地址，而 Binding 走物理网卡），没有地址（网卡没有 DNS 服务器、超时、出错、答案全被丢弃）才用系统的结果，两边的答案都去掉 §2.7 丢弃类的地址（`198.18/15`、回环等）。解析最多 200 毫秒（`RESOLVE_WAIT`），剩下的至少 400 毫秒留给 Binding（第 0、200 毫秒两次发送，最后一次还有 200 毫秒等回包）。
- 收到对端的候选一律按契约 §2.7 过滤（回环、链路本地、`100.64/10`、`198.18/15`、组播、`fdfe:dcba:9876::/48` 等去掉）。

### 7.3 优先级（两端必须一致，改参数时两端一起改）

- 候选：`2^24 × 类型偏好 + 2^8 × 本地偏好 + 255`，类型偏好由收方按类型定（host 126、prflx 110、srflx 100）。
- 本地偏好 = `65535 − 64 × 网络代价 − 地址族罚分 − 序号`：网络代价以太网 0、WLAN 10、其他 50；罚分 IPv4 0、全局 IPv6 8、ULA 16；序号是同类型、同罚分档里的位置（0~3）。
- 候选对：`2^32 × min(G, D) + 2 × max(G, D) + (G > D ? 1 : 0)`，G 是控制端那一侧。效果是同一网卡上私网 IPv4 先于 IPv6，跨公网时全局 IPv6 host 先于 srflx IPv4。

### 7.4 控制端（`race_ice`）

- 启用条件，全部满足才出 ICE：不是只允许入站；对端不是直连 IP 或 `域名:端口`；不是 `id@server?key=`（`other_server` 为空）；不强制中继（含 `/r`、代理、WebSocket）；没开 `disable-udp`；`enable-udp-punch` 和 `enable-ipv6-punch` 至少开一个（上游 `get_udp_punch_enabled`、`get_ipv6_punch_enabled`，控制端本地选项；两个都关说明用户不要 UDP 直连，维护者 2026-10-25 定）；有可信 Key（`get_rs_pk` 能解出）；能力缓存含 `ice`。连接类型不特判。
- ICE 腿是一条 future，不 spawn：取会合服务器、枚举网卡（为空就静默结束，竞速只等上游）；并行收集和建信令连接（`connect_tcp` 加 `secure_tcp_required`，整段 3 秒）；发 OFFER，1.5 秒没回应原样重发一次，从第一次起最多等 4 秒；收到 ANSWER 先比 session、验 S 签过的被控端 IdPk（`peer_key_verifies`）、检查参数，过了才开始读 ICE socket 跑检查（之前到的对端检查留在接收缓冲里）；选中后 `socket.connect(远端)`，`KcpStream::connect` 和 `secure_connection` 各限 3 秒，流必须已加密。
- 竞速（`race_legs`）：ICE 先成功立即胜出；上游先给直连立即胜出；上游先给中继时最多再等 `relay-fallback-delay`（和上游 WebRTC 竞速同一个选项，默认 2.5 秒），等到 ICE 成功就用 ICE，否则用中继（窗口到时 ICE 还在跑就打 `lost the relay window` 那一行）；窗口从上游交回中继时算起，这时上游已经在中继上做完 `secure_connection`、收到了被控端经 hbbr 发来的身份消息，中继是真正可用的，本机 fake-ip TUN 提前完成的只是 TCP 握手；上游先失败就等 ICE，ICE 也失败时返回上游的错误原文。
- ICE 胜出时返回 `((KCP 流, true, pk, Some(kcp), "UDP" 或 "IPv6"), (0, 会合服务器), false)`：连接类型沿用上游 UDP/IPv6 打洞的标签；第三项 `false`，ICE 的成败不改 `direct_failures`。
- RESULT（只作统计）：`CONNECTED` 在竞速选定 ICE 之后才发；各种失败（`no_answer`、`bad_answer`、`no_pair`、`kcp_failed`、`secure_failed`）在 ICE 腿里发；收到 REJECT、信令连接建不起来或中途断开时不发。发完关掉信令连接。ICE 腿被竞速丢掉时信令连接随之关闭，服务端记 `abandoned`。

### 7.5 被控端（`on_ice_offer`）

- 顺序：`leapgate::ice::open_forward` 验签、时间窗（±40 秒）、去重（1024 条）、解密，不过就静默丢弃；再占进程内 8 个名额之一（满了静默丢弃，不回 `BUSY`）；内层格式不对回 `REJECT{BAD}`；开了代理、WebSocket、`disable-udp`，配了 IP 白名单（非空、不含 `0.0.0.0`），或没有物理网卡候选时回 `REJECT{UNSUPPORTED}`。
- 配了白名单不做 ICE：白名单按交给 `create_tcp_connection` 的地址判，ICE 选中的可能是私网地址、IPv6 或另一个 UDP 映射，以前经中继能连上的会被拒，而 ICE 胜出后不再回落。
- 能做时并行收集和建回 ANSWER 用的加密 TCP（整段 3 秒，建不起来就收摊），然后同时发 ANSWER（发完断开）和跑检查；收到提名过的对上来的 KCP SYN 后 `socket.connect`、`KcpStream::accept`（3 秒），还名额，再 `create_tcp_connection(server, 流, ICE 选中的远端地址, true, ConnectionMeta::default())`。`AGENT_TTL` 10 秒从开始收集算（紧接着接受 FORWARD）。
- 会话期间（`serve_over_kcp`）每秒看一次 `peer_silent_for()`，控制端静默满 20 秒（`ICE_PEER_SILENCE_CLOSE`，比控制端 `io_loop` 的 `KCP_PEER_SILENCE_LIMIT` 8 秒长，理由见 §7.10）就丢掉 KCP 守卫：端点停掉，Connection 读流当场报错，按上游断线的正常流程关会话（`on_close`、停服务、通知 CM、还会话名额），日志 `leapgate ice: peer silent for …, closing the session`。最后收到的包一般在断开前 1 秒内（被控端每秒发 TestDelay，KCP 两个方向约 2 秒一次 ping），所以控制端崩溃或断网后，被控端约 20 秒关会话，不再等 Connection 的 30 秒超时（以前远程桌面实测 30~50 秒：读码能解释的是 30~31 秒，正好卡在一次视频发送上时再晚最多 12 秒，40 多秒以上的那几次读码解释不了，没对过日志；端口转发和出口的发送超时是 120 秒，卡住时要等 kcp-sys 约 60~70 秒的回收）。会话正常结束时守卫交给 `release_kcp`（spawn，最多 10 秒），收尾数据和 FIN 照常发出，控制端当场看到断开，不再靠它的 8 秒静默检测。
- REJECT 和 ANSWER 都新开一条到会合服务器的加密 TCP，发完断开；回 REJECT 也占名额，所以被控端为 ICE 开出的 TCP 同时最多 8 条。

### 7.6 事务号和 KCP 交接

- Leapgate 生成的每个 STUN 请求事务号取 12 个随机字节、把第 5 个字节（整个包的偏移 12）置 0：交给 KCP 以后迟到的检查包标志字节为 0，KCP 不建状态、不回弹，只回一个 14 字节的 RST，对端忽略它。
- 被控端按 SYN 的位模式认 KCP 的第一个包（`len >= 14`、`buf[12] & 0x3F == 0x01`、`buf[4..12]` 全 0），而且要落在提名过的对的 socket 上、来自那一对的远端地址；控制端换了提名时两对都认。这个包原样当 `init_packet`。

### 7.7 版本号

`libs/leapgate` 的版本随心跳上报，服务端按它判被控端支不支持 ICE（不低于 0.3.1）。改动 ICE 协议、需要服务端区分新旧被控端时，先前移这里的版本号。

### 7.8 固定日志

前缀 `leapgate ice:`，文字固定、不打具体 IP，端到端测试按此查找。控制端每次连接最多一行，用 `info`、不限频（频率由用户发起连接决定）：

- `leapgate ice: selected <本端类型>/<地址族>/<网卡> <-> <对端类型>/<地址族> in <N> ms`（例 `selected host/v4/ethernet <-> host/v4 in 85 ms`；只在竞速选定 ICE 之后打；N 是从 ICE 腿开始到身份握手完成）
- `leapgate ice: no direct path (<outcome>), falling back`
- `leapgate ice: rejected (<reason>), falling back`
- `leapgate ice: signaling failed, falling back`
- `leapgate ice: lost the relay window after <N> ms`（上游先给中继、等满窗口 ICE 还没选中；N 从竞速开始算；服务端这一次记 `abandoned`）

上游直连先赢、ICE 被取消，以及没有物理网卡候选时不打。被控端丢弃 FORWARD（任一步校验不过、名额满）打 `leapgate ice: dropped a forwarded offer`，每分钟最多一条；ICE 会话期间控制端在 KCP 上静默满 20 秒时打 `leapgate ice: peer silent for <时长>, closing the session`（`info`，每次 ICE 会话最多一条；时长是 Rust `Duration` 的 Debug 写法，例如 `20.734512345s`，按每秒检查一次落在 20 秒到 21 秒多）；检查收发、STUN 校验失败、agent 超时、KCP 交接失败只用 `trace`。名字：类型 `host`/`srflx`/`prflx`，地址族 `v4`/`v6`，网卡 `ethernet`/`wlan`/`other`，结果 `no_answer`/`bad_answer`/`no_pair`/`kcp_failed`/`secure_failed`，原因 `bad`/`offline`/`unsupported`/`relay`/`busy`。

### 7.9 兼容

| 情况 | 结果 |
|---|---|
| Leapgate ↔ Leapgate（都含 05），服务端含 05 | ICE 和上游路径竞速 |
| 被控端是原版、Leapgate 0.3.0，或公钥没被锁定、心跳 180 秒内没成功过 | 服务端回 `UNSUPPORTED`，ICE 当场失败，上游照常 |
| 被控端没配 Key 或 Key 配错、设备密钥刚换过 | 被控端静默丢弃，控制端 4 秒后按 `no_answer` 收摊 |
| 被控端走 TCP mediator（开了代理、WebSocket 或 `disable-udp`） | 服务端回 `OFFLINE`；刚改设置的几秒里被控端自己回 `UNSUPPORTED` |
| 被控端配了 IP 白名单 | 被控端回 `UNSUPPORTED`，只走上游 |
| 控制端是原版或 0.3.0 | 不发 ICE 信令，和以前一样 |
| 服务端只有 01、02，第一期 leapgate-server，或原版 hbbs | 能力缓存里没有 `ice`，不启动 ICE |
| 控制端走普通路径以外的连接（见 §7.4 启用条件） | 不启动 ICE，行为和上游逐字节相同 |
| 控制端第一次心跳成功之前 | `has_feature` 为假，这一次不出 ICE |

### 7.10 已知限制

- 默认 Windows 防火墙下没实测：安装版有按程序路径放行的规则，预期不受影响；便携版第一次收包可能弹提示，不点允许时入站检查会被挡。
- 纯中继场景最多晚一个窗口：上游先给中继、ICE 有候选但都不通时，要等满 `relay-fallback-delay`。
- 被控端没配 Key 或 Key 配错时服务端看不出来，照样转发，控制端白等 4 秒。
- 能力缓存按 API 根地址记，信令走会合服务器：两者不是同一台时，会合服务器是原版 hbbs 就在 3 秒后失败、是不含 05 的 leapgate-server 就当场断开，反过来就不启动 ICE。继承 01 的两条：第一次心跳成功前、界面进程把缓存写回旧值的那几秒，这一次不出 ICE。
- 会合服务器域名向物理网卡 DNS 的查询不经过代理，DNS 服务器能看到查的是哪个名字；网卡 DNS 被设成 `198.18/15` 这类 fake-ip 地址时不问它、直接回退系统解析。
- 网卡 DNS 的 A、AAAA 查询各只发一次、不重发：两个都丢了，或服务器 200 毫秒内没答上时，这块网卡的 DNS 没有答案，开 fake-ip 时这一次没有 srflx。
- 解析整体只有 200 毫秒：不开 TUN 时系统冷解析超过 200 毫秒，这一次没有 srflx；网卡上配的 DNS 连不通而系统先答出来时，要等到 200 毫秒才用系统的答案，Binding 少一次发送。
- 网卡 DNS 不读 hosts 文件：hosts 里把会合服务器域名指到别的地址时，信令连接用 hosts 的地址，srflx 的 Binding 发往网卡 DNS 给的地址，可能没有 srflx 或证明对不上。
- 路由器自己做 fake-ip（例如 OpenClash 的 fake-ip 模式）时，物理网卡 DNS 的答案也是假地址：两边都被丢弃，没有 srflx，只剩 host 和 prflx，干净回落到上游路径和中继。
- 会合服务器 21116/UDP 的回包源地址必须是客户端发往的那个；多地址主机上发往次地址的 Binding 请求从主地址回包，端口受限和对称 NAT 后面的客户端拿不到 srflx 和证明。
- 选中后不换路径：选中的地址失效（ULA、临时地址过期、换网）时，远程桌面这类走 `io_loop` 的会话在 KCP 静默 8 秒后整次重连；端口转发和出口隧道不自动重连，隧道断开后等下一个本地连接进来才重新登录。
- 被控端的静默判断是 20 秒、没有 consent 保活（维护者 2026-10-28 定，最初合入的是和控制端相同的 8 秒）：控制端还在、但链路断了约 20 秒以上（换 Wi-Fi、睡眠唤醒）时，被控端照样关会话，上游给控制端的关闭原因发不出去。不用 8 秒，是因为下面两条（数值是读码估算，假设控制端本机网络正常、被控端地址没变、用密码登录，没有实测；点击确认的会话重连时要被控端再点一次确认，效果等于锁屏）：
  - 远程桌面这类走 `io_loop` 的会话：控制端静默满 8 秒就自动重连，重连那一轮的打洞请求在 3 秒、9 秒各重发一次，18 秒放弃（报不能自动重试的错误）。对方要求了"会话结束后锁屏"时，上游靠"旧连接关闭时，同一会话的新连接已经登录"来避免误锁（#16124 的 `session_reconnected`）。被控端 8 秒就关的话，重连还没登录，断链只要长到触发重连就几乎都会锁屏。20 秒时，会合服务器在近处，断链约 17 秒以内基本不锁；在远处（往返约 200 毫秒，像 2026-10-25 跨网验收那样），约 11 秒以内不锁、11~19 秒有时会锁（看 9 秒那次重发送到后，上游路径多快接上），约 19 秒以上会锁。以前的 30 秒档也只扛到 9 秒那次重发（重连那一轮最后一次发送）的时刻：远处约 18~19 秒，近处约 17 秒，所以近处和 20 秒时一样；再长，重连那一轮在约 27 秒失败、会话结束。要在远处服务器下也完全追平以前，阈值要约 23 秒。断的是控制端本机网络时，重连常当场报不能自动重试的错误，阈值多少都一样。被控端关旧连接时如果正好卡在发送上（走发送失败那条路，上游不锁），就不锁，所以准确说是"通常会锁"。挂钩读不到 `lock_after_session_end`，不改上游文件没法只对开了锁屏的会话放宽。
  - 端口转发（mux）和出口隧道：控制端不看 KCP 静默，空闲时靠 `tunnel_loop` 的 18 秒读超时发现断链，实际能扛约 11~18 秒的断链（受 KCP 重传退避影响）。被控端 20 秒才关，不比这个早，所以和以前一样；8 秒时约 5~9 秒的断链就会断，而且被控端先关、控制端要到 17~18 秒才发现。断链期间一直有本地流量时，以前能扛约 20~29 秒，20 秒时约 18~21 秒，略短。断链超过这个时长后，控制端要到"最后一次本地事件 + 18 秒"和 kcp-sys 约 60~70 秒的回收里较早的那个才发现，期间本地连接挂着，这一点以前也一样。
  - 非复用的端口转发（旧式映射、旧版 RDP）走不到这里：ICE 只在两端都是 Leapgate 时出现，Leapgate 被控端对非复用的端口转发回 `MSG_NEED_MUX`（§9.1）。
- UDP 被封的网络，以及两端都是对称 NAT、端口受限对对称 NAT 又没有 IPv6 时打不通，走上游路径和中继。
- 被控端的 ICE 可以被人占满：知道它的 ID 和服务端 Key 的人能让服务端不断转发 FORWARD，占满 8 个名额或去重表，这段时间 ICE 不可用、走上游路径。
- 隐私面：任何知道被控端 ID、服务端 Key、被控端又在线的人，都能拿到它物理网卡上的私网 IPv4、ULA、每个 /64 一个临时全局 IPv6 和 srflx（跨网时也给）；链路上看不到，只有服务端看得到。ICE 有意不经系统的 VPN/TUN，开着全隧道 VPN 时，两端物理网卡的公网出口（srflx 或全局 IPv6）和局域网地址照样交给服务端和对端；上游走 VPN 时对端只看得到 VPN 的出口。
- 网卡过滤靠 IfType 和关键字：描述不在表里、IfType 又报 6 或 71 的新虚拟网卡会被当成物理网卡，最坏只是一对检查失败。
- 被控端系统时钟往回跳、心跳还没改回偏移时，链路上截获过的旧 FORWARD 可能被重放一次，后果只是起一个空 agent、占一个名额到 `AGENT_TTL`。
- 上游先报错而 ICE 还在跑时要等 ICE，最长约 16 秒（信令 3 秒和收集并行、等 ANSWER 4 秒、检查 3 秒、KCP 和身份握手各 3 秒）；对端离线、Key 不对这类常见错误 ICE 一两个往返就失败。
- 非 Windows 平台枚举不到物理网卡，不出 ICE（第一阶段只做 Windows）。
- 会合服务器离两端很远时 ICE 可能输给中继窗口：ICE 比上游中继多几个经过会合服务器的往返（两端各建一条信令连接并做密钥交换、OFFER/FORWARD/ANSWER）。2026-10-25 跨网验收里会合服务器在美国、到两端往返约 200 毫秒，ICE 选中要 2.2~3.7 秒，上游中继约 1.3 秒给出、再等 2.5 秒，200 次里 6 次（3%）输给窗口，走中继、控制端打 `lost the relay window`。会合服务器离得近时快得多。
- 被控端会话期间句柄缓慢增长，和 ICE 无关：2026-10-25 跨网验收里被控端主进程在会话开着时每秒约多 0.5 个内核句柄（Mutant、Section 成对），关掉会话、空闲后不回落，线程数和专用字节平稳；每次约 25 秒的连接净增约 9 个，控制端开、关 ICE 各 200 次斜率相同（都是每次 9.0 个）。来源没查明，本仓库的代码里搜不到按事件创建互斥量或共享内存的地方，没和原版 RustDesk 对照测过。

## 8. 不配也能用：自动降级与可选优化

Leapgate 不要求用户配置任何代理规则。

- 路由第二级（§5）：测速和真实中继连接走同一条路，量到中继关连接为止，本机 TUN、路由器透明代理、全隧道 VPN 下量到的都是真实中继路径的往返，不需要任何配置（2026-10-25 起，此前要把中继排除在代理之外才有实测）。
- 自研 ICE（§7）：不配任何代理规则时，ICE 靠两端对物理网卡候选逐对实测直连，在"路由器只代理 TCP""本机开 TUN""两端 UDP 出口不同"的网络里也能连上。
- 条件不满足时（没有物理网卡候选、UDP 不通、服务端或对端不支持）自动回落上游路径和中继，不要求用户配规则。
- 应用出口（§9）：被控端开着 TUN 代理或全隧道 VPN 时，出口的连接和向物理网卡 DNS 的查询绑物理网卡地址、从物理网卡出去，不经本机代理和 VPN，不用配规则（契约 B9）；同时发起的系统解析仍会经过本机，见 §9.4。

## 9. 应用出口（第四期）

依据：总仓库 `docs/第四期实施契约/`（README 是总述、两端共用的接口和兼容矩阵；02 是被控端，03 是控制端，01 是服务端目录；B、C 开头的编号指契约清单里的条目）。被控端在设置里打开"允许作为出口"后，Leapgate 控制端可以在它的 TCP 隧道窗口里加一条"出口"映射：本机 `127.0.0.1:<端口>` 上开一个 SOCKS5/HTTP CONNECT 代理，每个本地连接成为同一条多路复用隧道里的一个通道，目标由被控端在自己的物理网卡上解析、过滤、连接。出口映射的登录目标是哨兵 `leapgate-exit.invalid:65536`（`exit::is_exit_target` 只认这一个写法；65536 在普通添加行里填不进去）。两个选项 `leapgate-allow-exit`、`leapgate-exit-allow-nets` 存 Config（服务进程看不到界面进程的 LocalConfig），服务端策略写不进。`libs/leapgate` 版本 0.4.0。下面和契约原文有出入的地方以本文（即代码）为准。

### 9.1 上游挂钩

每处前一行 `// leapgate: …`。除了 K0、`server/port_forward_mux.rs` 的 M-1~M-5、V-1~V-3 的可见性和 `server_page.dart` 那一处判断，其余都是纯插入。

控制端（Rust）：

| 文件 | 位置 | 作用 | 编号 |
|---|---|---|---|
| `src/port_forward.rs` | `listen` 里 `connect_and_login` 的成功分支；`connect_and_login` 的返回类型、`Client::start` 的解构和返回值 | 不再丢掉 `Client::start` 给的 KCP 守卫，转发任务结束后交给 `release_kcp` | K0 |
| `src/port_forward.rs` | `connect_and_login_mux` 的解构和返回值、`LoginOutcome.kcp`、`establish_tunnel` 调 `set_muxed`、`run_legacy` | 同上；多路复用隧道把守卫交给隧道循环，裸管道交给转发任务 | K0（含 03 H-6） |
| `src/port_forward.rs` | 新函数 `release_kcp` | 流结束后，KCP 端点还记着这条连接（`peer_silent_for()` 返回 `Some`）就继续等，最多 10 秒，让没发完的数据和 FIN 发出去；对端常不回 FIN，通常等满 10 秒（直接丢守卫会当场停掉 KCP 端点） | K0 |
| `src/port_forward_mux.rs` | `Tunnel::set_muxed` 加 `kcp` 参数，`tunnel_loop` 包一层 spawn，结束后调 `release_kcp`；模块测试里的调用补 `None` | 隧道活多久，KCP 端点就活多久 | K0 |
| `src/port_forward.rs` | `mux_enabled` 开头 | `exit::CONTROLLER_MUX_ONLY` 恒为真，Leapgate 控制端总是请求多路复用（设置页的复用开关不再起作用） | C11 H-4 |
| `src/port_forward.rs` | `establish_tunnel` 里对端不支持多路复用的分支开头 | 不退回裸管道：`set_failed`、弹 `PEER_TOO_OLD`、返回 `true` 停掉这条映射的监听；`listen` 的 `Claim::Legacy` 分支从此走不到，代码不动 | C11 H-5 |
| `src/port_forward.rs` | `connect_and_login_mux`、`LoginOutcome` 和它的字段、`take_socket` | 改成 `pub(crate)`，给出口监听用 | 03 V-1~V-3 |
| `src/ui_session_interface.rs` | `start_one_port_forward` 参数表之后 | 哨兵映射转 `leapgate_hooks::exit::run`，不进 `port_forward::listen`；RDP 传的是 `""` 和 RDP 端口，不会命中 | 03 H-1 |
| `src/flutter_ffi.rs` | `main_get_common` 开头 | `leapgate-exits` 键由 `leapgate_hooks::exit::get_common` 回答（出口目录的 JSON） | 03 H-2 |
| `src/lang.rs` | `translate_locale`，查完上游当前语言表之后 | 查 `leapgate::lang::get` | S0 H-3 |
| `src/leapgate_hooks.rs` | 文件头 | `pub(crate) mod exit;` | 03 |

被控端（Rust）：

| 文件 | 位置 | 作用 | 编号 |
|---|---|---|---|
| `src/server/connection.rs` | `on_message` 登录分支，上游 `PortForward` 分支之前 | 登录守卫：哨兵登录先规范化，再过 `exit::login_refusal`（开关、多路复用、加密，依次检查），不过就回固定登录错误；过了照常走后面的密码、点击接受、2FA（IP、ID 白名单在这之前已查），不提前授权，也不看 `enable-tunnel` | K-1 |
| `src/server/connection.rs` | 上游 `PortForward` 分支，`enable-tunnel` 检查之后、规范化之前 | 不是多路复用的端口转发（含旧版 RDP）在审批之前回 `MSG_NEED_MUX` | K-2（B5） |
| `src/server/connection.rs` | `connect_port_forward_if_needed` 建好 mux 之后、`return` 之前 | 原始登录目标是哨兵时，把控制端自报的 ID 写进 `mux.leapgate_exit` | M-1 |
| `src/server/connection.rs` | `send_logon_response_and_keep_alive` 端口转发那份 `Features` | `leapgate_exit: true`，和开关无关，表示这个版本认得出口登录；远控那份不填 | K-3 |
| `src/server/connection.rs` | `start` 主循环 `test_delay_timer`（每秒）分支开头 | 出口会话中途关掉开关时 `on_close("Exit node disabled")` 并退出，沿用上游清理链 | K-4（B8） |
| `src/server/port_forward_mux.rs` | `struct PortForwardMux` 和 `new()` | 加字段 `leapgate_exit: Option<String>`（出口隧道时是控制端 ID），`new` 的签名不变 | M-1 |
| `src/server/port_forward_mux.rs` | `on_open`，`retain` 之后 | 出口隧道且开关已关时回 `MSG_NOT_ENABLED`；出口隧道不看 `enable-tunnel`（`permitted` 或上出口） | M-2 |
| `src/server/port_forward_mux.rs` | `on_open` 的规范化和登录目标比较 | 出口隧道不规范化、不和登录目标比；spawn 前用 open 帧里的原始主机、端口和控制端 ID 组成 `exit::dial::Target` | M-3 |
| `src/server/port_forward_mux.rs` | `run_controlled_channel` 签名加 `exit_target`；连接 future | 出口通道改调 `exit::dial::connect`（自带期限：整体 10 秒，解析 2 秒，连接 8 秒），普通转发的 3 秒不变 | M-4 |
| `src/server/port_forward_mux.rs` | 连接完成那个 select 臂里、`match res` 之前 | 出口通道失败时 `exit::dial::failure_message` 给出固定文案（`MSG_BLOCKED`、`MSG_FAKE_IP_LITERAL` 或空串），经 `sink.send_ordered` 回 opened 后返回，不走上游的 debug 行和 `unreachable_message` | M-5 |
| `src/hbbs_http/sync.rs` | `handle_config_options` 开头 | 上游回落路径的服务端策略同样写不进 `leapgate-` 开头的键（Leapgate 心跳的 `merge_strategy` 用同一个 `options::is_leapgate_local_option`） | A7 |
| `libs/base/protos/message.proto`（上游文件，两端共用） | `message Features` 末尾 | `bool leapgate_exit = 1000`，前一行是号段注释 `// Leapgate fields use 1000-1999.`（proto 里沿用这种写法，不用 `// leapgate:`） | S0 |

Leapgate 自己的文件里和挂钩配套的：`report/heartbeat.rs` 在开关打开时带 `"exit": true`（关着不带键，放行网段不上报）；`lan.rs` 的 `Nic` 多两个字段 `ipv4_prefixes`（每个 IPv4 的在链前缀长度）、`all_ipv6`（全部 IPv6 单播地址，含已弃用的临时地址），供地址策略认本机地址和链路网段，原有的 `ipv6` 和 ICE 的候选选择不变；`ice/mod.rs` 加 `public_v4`（B11：用 ICE 的 Binding 探测问会合服务器本机的公网 IPv4，不建 ICE 会话）；proto 只改 `libs/base` 的 `message.proto`（见上表），cardo 不动。

上游 Dart（F7 写死的例外，超出要维护者同意；新 Dart 文件都在 `flutter/lib/leapgate/`：`exit_tunnel.dart` 放哨兵常量和出口行控件，`exit_nodes.dart` 是目录对话框，`exit_settings.dart` 是设置页的 part 文件）：

| 文件 | 改动 | 归属 |
|---|---|---|
| `flutter/lib/desktop/pages/port_forward_page.dart` | 1 行 import；`initState`、`dispose` 里 `leapgateExitAttach`/`leapgateExitDetach`（出口行显示连接类型）；Add 按钮后加"添加出口"按钮；`buildTunnelDataRow` 开头把出口映射换成出口行 | 03 |
| `flutter/lib/desktop/pages/connection_page.dart` | 1 行 import；连接菜单 TCP tunneling 后加"出口节点"一项（只在桌面端） | 03 |
| `flutter/lib/desktop/pages/desktop_setting_page.dart` | import 之后 `part '../../leapgate/exit_settings.dart';`；安全设置页权限卡片之后插"出口节点"卡片（只在 Windows，`enabled` 跟解锁状态） | 02 |
| `flutter/lib/desktop/pages/server_page.dart` | 1 行 import；CM 卡片上哨兵目标显示"作为出口"，其余照旧 "Port Forward: …" | 02 |

### 9.2 固定日志

前缀 `leapgate exit:`，文字固定，端到端测试按前缀查找：用 `throttled_log!` 打的行累计多于一次时末尾会带 ` (xN)`。日志文件里不出现成功访问的目标和域名。

被控端：

- `leapgate exit: <控制端 ID> refused <ip>:<port> (<原因>)`（warn，全进程一个调用点，每分钟最多一条，附累计次数）：出口策略拒了一个地址（B7）。只记 IP，不记域名；IPv6 带方括号，例 `leapgate exit: <ID> refused [2001:db8::1]:443 (reserved)`。混合答案里被丢掉的地址也算。原因是 `loopback`、`link_local`、`local`、`reserved`、`lan`、`fake_ip`、`fake_ip_literal` 之一。控制端 ID 是对方自报的，换行等控制字符转义后输出。
- `leapgate exit: public IPv4 unavailable`（warn）：B11 没问到本机公网 IPv4，NAT 回环那条硬拒这 10 分钟缺着；结果（空的也算）缓存 10 分钟，所以 10 分钟最多一条。
- 上游的 `#<连接号> Connection closed: Exit node disabled`（info）：出口会话中途关了开关，由 K-4 断开。
- 只在 `trace`：`leapgate exit: <控制端 ID> <host>:<port>: <connected 或原因码>`，每个出口通道一行；原因码多出解析和连接失败的 `invalid_target`、`nxdomain`、`resolve_failed`、`no_route`、`timeout`、`refused`、`unreachable`。

控制端（C13；只有隧道级事件和不带地址的限频计数）：

- `leapgate exit: listening on 127.0.0.1:<端口>`（info）
- `leapgate exit: tunnel up (direct)` 或 `(relayed)`（info）：隧道建好。
- `leapgate exit: tunnel refused, listener closed`（info）：登录被拒、对端不支持出口、没多路复用或没加密，这条映射的监听关掉。
- `leapgate exit: tunnel failed, retrying after cooldown: <错误>`（info，每分钟最多一条）：离线、超时这类临时失败，10 秒内本地连接一律立即失败。
- `leapgate exit: local handshake refused (<原因>)`（info，每分钟最多一条）：本地程序的握手不合规，原因是 `Socks4`、`NoMethod`、`Command`、`AddressType`、`BadTarget`、`NotConnect`、`BadRequest`、`Timeout`、`Io` 之一。
- `leapgate exit: local connection refused, retrying after cooldown`、`leapgate exit: local connection dropped, tunnel unavailable`（info，各自每分钟最多一条）
- `leapgate exit: directory request failed (<HTTP 状态码或错误>)`（info，每分钟最多一条）
- 只在 `trace`：`leapgate exit: channel <host>:<port>`。隧道断开由上游的 `port forward tunnel ended: …` 记；上游逐通道的 debug 行只带通道号和固定文案，照旧进文件。

### 9.3 兼容

| 组合 | 结果 |
|---|---|
| 两端第四期，出口开着 | 正常 |
| 被控端第四期，出口关着，或登录不是多路复用、流没加密 | 密码和审批之前回固定登录错误；控制端弹 "Login Error"，这条出口监听关闭 |
| 被控端是原版 1.5.0 以上，或第三期及以前的 Leapgate | 照常过认证（点击确认模式下对方会看到一张目标是哨兵的端口转发卡片）；控制端拿到 PeerInfo 发现没有出口位立即断开，弹"对方设备不支持作为出口"，监听关闭 |
| 被控端是 1.5.0 以前的原版 | 它走裸管道，端口 65536 解析失败、不查 DNS，回登录错误 "Failed to access remote leapgate-exit.invalid:65536…"（1.4.6~1.4.9 在认证之后，1.4.5 及以前在密码校验之前），监听关闭。Leapgate 控制端对它的普通映射和 RDP 弹"对方版本过旧"（C11） |
| 原版或旧版控制端连第四期被控端 | 发不出出口请求；多路复用的普通端口转发照旧；不是多路复用的回 `MSG_NEED_MUX`，被控端不弹审批 |
| 服务端是原版 hbbs 或第四期以前的 leapgate-server | 出口照常能用（手填 ID），没有目录：`has_feature("exit")` 为假，目录对话框显示"当前服务器不提供出口目录"、不发请求 |
| 两端第四期，流没加密（没配 Key、直接 IP 访问） | 被控端拒；不是直接 IP 访问时，控制端先弹一次上游的"不安全连接"确认框 |
| 控制端用"ID@其他服务器" | 出口照常能用，目录不涉及 |
| 任何服务端下发策略 | 写不进两个出口选项（Leapgate 心跳、上游回落路径都挡） |
| 非 Windows 被控端 | `exit::allowed()` 恒假，出口登录一律回 `MSG_NOT_ENABLED` |

### 9.4 已知限制

正文在契约 README §7、02 §7、03 §7，这里只列标题：

- 目录不是关口，撤销授权不断已有会话；做不到只给出口不给远控；控制端身份是自报的，出口日志落不到账号。
- 访问模式设成"仅共享屏幕"不关出口。
- 局域网保护只约束出口模式，普通端口转发和远控照样碰得到局域网。
- 按全局 IPv6 /64 写的放行会随家宽前缀变化失效；IPv6 只认本机地址所在的 /64。
- 路由器 fake-ip 网络里默认用不了域名，非默认 fake-ip 网段判不出；本机 strict-route 可能挡住物理网卡的 DNS。
- 查不到本机公网 IPv4 时少一条硬拒（含换网络后最长 10 分钟）。
- 出口从物理网卡出去：进不了主人公司的内网，被控端网络打不开的网站经出口也打不开。
- 系统解析和物理网卡 DNS 同时发起，目标域名会经系统解析器发给本机的代理、VPN 或公司 DNS（物理网卡 DNS 给出地址或明确否定时不采用系统答案，只在没有答复、或没有可用的物理网卡 DNS 时回落）；物理网卡 DNS 不读 hosts。
- 单会话缓存上限、主循环发送阻塞时关开关后的断开会推迟；所有通道共用发送队列和一条有序隧道（队头阻塞、KCP 不做拥塞控制、隧道不换路径）。
- 控制端：本地端口不认证；乐观应答；不安全确认框；连接状态不随断开更新；10 秒冷却；空闲不拆、经中继时一直占一对 hbbr 连接；重建照上游认证；Chrome、Edge 要扩展或启动参数；建隧道期间删除映射要等登录结束才停。
- C11 之后 Leapgate 控制端对 1.5.0 以前的原版做不了端口转发和 RDP。
- 拒绝日志每分钟只留第一条加累计次数，还原不了完整的拒绝历史。

### 9.5 合并上游时要核对

- `src/port_forward.rs`：`connect_and_login`、`connect_and_login_mux` 仍从 `Client::start` 拿到 KCP 守卫且没有新的丢弃点；`LoginOutcome` 的字段；`establish_tunnel` 的分支结构（H-5 插在不支持多路复用的那支）；`mux_enabled` 的选项读法；`listen` 的 `Claim::Legacy` 分支。
- `src/port_forward_mux.rs`：`set_muxed` 和 `tunnel_loop` 的签名、spawn 方式；`CHANNEL_WINDOW`、`UPDATE_THRESHOLD`（以后调窗口时 `UPDATE_THRESHOLD` 要钉成字面量 128 KiB，契约 03 §3.11）。
- `src/server/port_forward_mux.rs`：M-1~M-5 五处就是冲突面；核对 `on_open` 里 `retain`、权限检查、规范化和登录目标比较的顺序，`run_controlled_channel` 的签名和连接臂里 `match res` 按值绑定的写法，通道仍由 `tokio::spawn` 跑（`exit::dial::connect` 的 future 必须是 `Send`）。
- `src/server/connection.rs`：`on_message` 登录分支里 `PortForward` 那支（`enable-tunnel` 检查、`normalize_port_forward_target`、`self.lr` 在 `match lr.union` 之前赋值）；`connect_port_forward_if_needed` 读的仍是原始登录目标；端口转发的 `Features` 字面量；`test_delay_timer` 的周期和 `on_close` 的清理链（`port_forward_mux.take()` 后 `close_all`）。
- `src/ui_session_interface.rs` 的 `start_one_port_forward` 签名，`src/flutter_ffi.rs` 的 `main_get_common`，`src/hbbs_http/sync.rs` 的 `handle_config_options`，`src/lang.rs` 的 `translate_locale`（H-3）。
- `libs/base/protos/message.proto` 的 `message Features`：上游新增字段不能占 1000~1999 号段。
- 四个上游 Dart 文件的挂钩位置（§9.1），尤其 `desktop_setting_page.dart` 的 import 块（`part` 必须在全部 import 之后）和 `_SafetyState.build()` 的卡片列表。

## 10. 新界面

依据：总仓库 `docs/新界面/03-实施方案.md`（下称"03"），界面行为以 `01-内容与逻辑说明.md`、`02-第二轮内容与逻辑说明.md` 为准，令牌和图标以 `docs/新界面/样稿/A-基础.html` 为准。新界面放在 `leapgate_ui/`（`core` 包沿用上游包名 `flutter_hbb`，放桥、models、会话和状态；`app` 包 `leapgate_ui` 放页面、组件、令牌、Windows 启动代码），和上游 `flutter/` 互不引用。维护者 2026-10-30 定（03 §12 IQ13）：除分段延迟（Q13）单独写契约外，03 §6.1 的表加本节就是新界面各 Rust 项的实施契约；每项动手前把挂钩位置写进本节，合入时补上取值。

### 10.1 规则

- **上游 `flutter/` 一行不改**（architecture §3.3）。评审规则：新界面的分支合入 main 之前，`git diff main -- flutter/` 必须为空（切换之后那次还原除外，03 §7.3）。构建会打补丁、改写 `flutter/` 下被跟踪的文件，所以在构建过的 worktree 里只 `git add <具体路径>`，不用 `git add -A`、`git commit -a`。编旧界面还会在 `flutter/` 下留下块 2 的三个未跟踪文件（`flutter/lib/generated_bridge_leapgate.dart`、`flutter/macos/Runner/bridge_generated_leapgate.h`、`flutter/ios/Runner/bridge_generated_leapgate.h`），构建 worktree 把它们加进 `.git/info/exclude`（不改上游的 `.gitignore`）。
- **复制件头上写来源**：从上游复制的每个文件第一行写来源，例如 `// 上游：flutter/lib/models/input_model.dart@bd9262397（只删界面调用，不格式化）`。分三档：原样复制、只删界面调用、改写（03 §3.2）。合并上游 tag 之后，总仓库的 `scripts/windows/sync-ui-upstream.ps1`（还没写，最晚在有复制件以后的第一次合并上游之前写好）对前两档做三方合并（base = 头上记的提交里的上游原件，ours = 副本，theirs = 新 tag 的上游原件，`git merge-file`），冲突留给人，成功后改头上的提交号；改写档列出 `git log <旧>..<新> -- <上游文件>` 逐个人工判断。来源只记在文件头上，不另建对照表。来源行通常是第一行；有格式要求的文件放在允许的第一个位置（`Runner.rc` 在 `#pragma code_page(65001)` 之后，`runner.exe.manifest` 在 XML 声明之后），同步脚本按内容（`上游：` 开头的注释）找来源行，不按行号。
- **一个上游文件混了两档时**（`models/model.dart`：`ImageModel`、`CanvasModel`、`CursorModel`、`QualityMonitorModel`、`RecordingModel`、`PeerInfo` 等属于只删界面调用，`FfiModel`、`FFI` 属于改写）：整份复制到 `core/lib/models/model.dart`，保留的类按只删界面调用处理，改写的两个类整段删掉（`FFI` 前面的 `ConnType` 跟着 `FFI` 走），改写版放进 `lib/leapgate/` 下的新文件，沿用原类名和复制件用到的成员名。来源行写"只删界面调用；`FfiModel`、`FFI` 改写到 `lib/leapgate/<文件名>`"（`FFI` 在 `lib/leapgate/session.dart`）。同步脚本照常对它做三方合并；上游改了那两个类，会以冲突的形式冒出来，由人工移植到改写文件。
- **复制件和上游原件的差异保持最小**：`core` 原样使用上游的 `flutter/analysis_options.yaml`；"原样复制""只删界面调用"两档不跑 `dart format`、`dart fix`，不顺手修 lint；`flutter analyze` 的"新告警"以上游原件为基准算。评审时看 `git diff --no-index <上游原件> <副本>`，"只删界面调用"那一档的差异应该只有界面调用和导入。
- **废弃 API**（03 §8.8）：新写的代码和"改写"档的文件不用最新 stable 已标记废弃的 API，最新 stable 检查报出的这类提示当场处理。"原样复制""只删界面调用"两档按上一条不改：上游原件在同一版 SDK 下也报的提示在验收记录里单列，等上游改了随三方合并带过来，到升 Flutter（M10）还没改的在升级时处理；某个 API 在最新 stable 里已经删掉、复制件编不过时，照最小差异改，并在文件头的来源行后注明。
- 新的 FFI 函数只放 `src/leapgate_ffi.rs`（frb 的第二个块），逻辑在 `libs/leapgate`，按领域分段追加；Leapgate 自己的事件用块 2 的 `StreamSink`，不往上游的 `InvokeUiSession` 加方法。上游文件里的挂钩照 §1 的纪律写。
- 公开仓库里不写真实 IP、域名、设备 ID（测试夹具和文档用文档地址段）。

### 10.2 验收记录的写法

每个里程碑验收完在 10.5 加一小节：日期、验收的提交、03 §5.2 该里程碑的每一条验收结果（通过、不通过、未验证，后两种写原因），以及 03 §8.8 的最新 stable 检查（SDK 版本，四步各自的结果，发现的问题；不适用的步骤写"不适用"和原因）。只写结论和问题，不写机器名、IP、设备 ID；机器相关的细节记在维护者的私有运行手册里。

### 10.3 frb 第二个块（F0）

- 块 1 是 `src/flutter_ffi.rs`（上游，类名 `Rustdesk`），块 2 是 `src/leapgate_ffi.rs`（类名 `Leapgate`）。块 2 的 Rust 输出在 `src/leapgate_bridge/`（目录自带 `.gitignore`），由 `leapgate_ffi.rs` 用 `#[path]` 声明，不改 `src/lib.rs`。生成参数见总仓库 `scripts/windows/build-client.ps1` 的 bridge 步。Rust 侧两个界面共用，所以编哪个界面都生成两块：旧界面的 Dart 和 C 头落在 `flutter/`（块 2 的 Dart 旧界面不用，也不提交），新界面的落在 `leapgate_ui/core/`。
- 2026-10-30 试验（基线 `c0858dd2d`）：
  1. 块 1 生成的 `bridge_generated.rs`、`bridge_generated.io.rs`、`generated_bridge.dart`、`generated_bridge.freezed.dart` 和单块时逐字节一致；C 头只有末尾的 dummy 函数一段不同（多块时按块分名，并 `#include` 块 2 的头）。上游界面用两块生成的桥照常编出产物，锁文件没有漂移。
  2. 符号：`wire_<函数名>` 两块不能重名（codegen 生成前就检查）；按类型生成的 `new_*` 带块号后缀（`new_uint_8_list_0`、`new_uint_8_list_1`）；`free_WireSyncReturn`、`store_dart_post_cobject` 等公共符号只在块 1 里生成一份。dll 导出没有冲突。
  3. 共用类型：块 2 的签名里可以用基本类型、`String`、`Vec`、`uuid::Uuid`（`SessionID` 直接从 `flutter_ffi.rs` 引用）和块 2 自己声明的类型；块 1 已经暴露的自定义结构体和枚举（例如 `EventToUI`）不能再出现，两个生成模块会各实现一次 `IntoDart`，编译报 E0119。Dart 侧两份生成文件各自声明同名的类和常量（`EventToUI`、`wire_uint_8_list` 等），一个文件里用到同名的类型才报 `ambiguous_import`，所以块 2 的 Dart 一律带前缀导入（例如 `as lg`）。
  4. 块 2 的 `SyncReturn`（String 参数、uuid 参数）和 `StreamSink<String>`（推三条后关闭）在纯 Dart 程序里加载 dll 实测可用。
- 生成时的坑（构建脚本已处理）：`--c-output` 的文件要事先存在，而且不收多值、每块写一次；生成块 1 时 cbindgen 会顺着 `#[path]` 去读块 2 的 Rust 输出，所以它也要先有（空文件即可）；多块时要显式给 `--class-name`。

### 10.4 挂钩和导出

| 编号 | 位置 | 作用 |
|---|---|---|
| W1 | `src/core_main.rs` 的 `core_main_invoke_new_connection`，Windows 分支开头 | 新界面的进程里（runner 只在调 `rustdesk_core_main_args` 期间设着 `LEAPGATE_UI=next`，返回后马上清掉，免得从新界面起的浏览器、资源管理器等后代进程继承它、再起旧界面时误判；W1 只在 core_main 里读它），链接、`--connect` 等只交给类名为 `LEAPGATE_UI_MAIN` 的主窗口（`leapgate_hooks::send_to_new_ui_main_window`，只按类名找，不看标题）；旧界面的进程里它返回 `None`，照上游按"旧类名 + 标题"找。两边不交叉回退 |
| L1 | `src/leapgate_ffi.rs` 的 `leapgate_log(level, msg)` | 界面的日志写进日志文件，target `leapgate_ui`；1 error、2 warn、3 info、4 debug、其他 trace。不限流，重复的同一条错误由界面合并后再写 |
| S12 | `src/leapgate_ffi.rs` 的 `leapgate_version()` | `libs/leapgate` 的版本（`libs/leapgate/src/ui.rs` 的 `VERSION`），界面当产品版本显示；构建时由 `--build-name` 写进 Windows 版本资源 |
| C3 | `src/leapgate_ffi.rs` 的 `leapgate_msgbox_reason(msgtype, title, text)`，同步 | 会话的 `msgbox` 事件按（类型、标题、正文）归成原因码，返回 JSON 字符串：`{"code": "..."}`，带参数的原因多一个键（`feature` 或 `port`，见下表）。归类在 `libs/leapgate/src/reason.rs`（纯函数）。能否重试取 msgbox 事件的 `hasRetry`（即 `Session::msgbox` 当时调上游 `check_if_retry` 算出的结果，`src/flutter.rs` 的 `msgbox`），C3 只给原因码。没认出的归 `other`，界面显示原文；同一段正文只在日志里写一次（最多记 64 段，有的正文来自对端）。上游 Dart 的"连上过的会话报不在线时 30 秒内照样重试"（`model.dart` 的 `shouldAutoRetryOnOffline`）不在 Rust 里，归 `core` 的连接状态。返回 JSON 而不是块 2 的结构体：参数随原因变，`SyncReturn<String>` 是 F0 实测过的形态 |
| V1 | `src/leapgate_ffi.rs` 的 `leapgate_session_set_visible(session_id, visible)`，同步；`src/flutter.rs` 的 `on_rgba`（桌面那一份）、`on_texture` 开头各一处挂钩 | 不可见的会话标签不往界面推帧：照常收流、解码、计帧率，只是不交给 Flutter（03 §3.3 第 1 条）。界面用法：标签切走时设 `false`；切回时设 `true`，再调上游的 `session_refresh(session_id, display)` 要一帧（软件上屏、纹理上屏都一样）。状态在 `libs/leapgate/src/session.rs`，默认可见，只记被隐藏的会话；挂钩在这个对端会话的所有界面会话（`session_handlers`）都被隐藏时才跳过，同一台设备在另一个窗口里还显示着就照推。会话关闭不加挂钩：设回可见时删掉条目，每次调 `leapgate_session_set_visible` 时顺手删掉已经不在的会话（隐藏着被关掉的标签），查会话时不拿着这把锁（挂钩是拿着 `session_handlers` 读锁再拿它，反过来会有锁序问题）。不会卡住：软件上屏的"界面还没取走上一帧就不推下一帧"（`display_rgbas` 的 `valid`）只在已经发出的 `Rgba` 事件被界面处理后复位，隐藏前发出的那一条照常会被 `core` 处理（取帧、`session_next_rgba` 不依赖页面是否显示）；纹理上屏的"第一帧通知"（`notify_render_type`）隐藏期间不动，切回后的第一帧照常通知。界面要注意：上游 Dart 连上后 1.5 秒还没画面会给对方发空的系统登录密码（`model.dart` 的 `waitForImageTimer`），标签在第一帧到之前被隐藏时这个判断会误触发，`core` 要在隐藏期间不按"没画面"处理 |
| Q3 | `src/leapgate_ffi.rs` 的 `leapgate_session_connection(session_id)`，同步；`src/client.rs` 三处挂钩（`create_relay`、`_start_inner` 和 `request_relay` 里服务器拒绝的 `bail!` 前），已有的 H-1（`race_ice`）调用不改 | 这个会话当前连接是怎么连上的（01 §4.2 第二级的"路径""中继服务器""传输"），返回 JSON 字符串：`{"path":"relay","transport":"tcp","relay":"relay-1.example.com"}`、`{"path":"lan","transport":"tcp"}`；服务器拒绝了这次连接时 `{"refused":"<原文>"}`；还没连上、正在重连、会话已不在、判不出时 `{}`。界面在每次连接就绪事件后重新取。路径码、判法、中继名和拒绝原因的取法见下面"Q3 连接路径和中继名" |
| 本机名 | `src/leapgate_ffi.rs` 的 `leapgate_local_display_name()`，同步 | 登录时显示给对方的本机名称（"等对方接受"面板的"显示给对方的名称"），返回字符串。算法照上游 `src/client.rs` 登录时的 `display_name` 抄了一份在 `libs/leapgate/src/ui.rs` 的 `display_name`（不改上游那段去抽函数）：先读内置选项 `display-name`，再读 LocalConfig `user_info` 的 `display_name`（trim 后非空）或 `name`，再退到系统用户名，最后按空白分词、每词首字母大写、用一个空格连接。读的是调用时的值，和上一次登录时实际发出去的可能不同（中间改过登录状态时） |
| C1 | `src/leapgate_ffi.rs` 的 `leapgate_incoming_counts()`，异步；`src/ipc.rs` 的 `Data` 末尾一个变体 `Leapgate(leapgate::ipc::Msg)`、`handle` 一处分发；`src/server/connection.rs` 已有的出口挂钩（`connect_port_forward_if_needed` 里设 `leapgate_exit` 那一行）多调一次 `leapgate_hooks::ipc::note_exit_conn` | 分类型的传入连接数。导出自己连服务进程的主进程间通道问一次（`Msg::IncomingCounts`；连接 1 秒、等回复 1 秒，最坏约 2 秒），返回 `{"remote":n,"file_transfer":n,"port_forward":n,"exit":n,"camera":n,"terminal":n}`，服务进程不在或不回时 `{}`；只数已授权的连接（上游 `AUTHED_CONNS`），端口转发里登录为出口的只算进 `exit`。出口连接的编号记在 `libs/leapgate/src/ipc.rs` 的表里，每次记新编号和每次查询时都删掉连接已经不在的编号，没人查询时表也不会一直变长（按上游 `Connection::alive_conns()`，不按 `AUTHED_CONNS`：出口编号在授权前一点记下，按 `AUTHED_CONNS` 删会和刚登录的出口撞上）。上游的连接表和 `AuthedConn` 不加字段，`ui_interface.rs` 的状态轮询不改 |
| C2 | `src/leapgate_ffi.rs` 的 `leapgate_show_cm()`、`leapgate_cm_events(sink)`；`src/ui_cm_interface.rs` CM 消息循环一处分发 | 主窗口经上游 `send_to_cm`（连 `_cm`，和推主题、语言同一条路）发 `Msg::ShowCm`，CM 进程不在时什么也不做。CM 一侧收到后推给 `leapgate_cm_events` 订阅的 `StreamSink<String>`：`{"name":"show_cm"}`，界面自己把窗口提到前面；还没订阅时丢掉。再订阅一次替换上一个。不往上游的 `InvokeUiCM` 加方法 |
| S7 | `src/leapgate_ffi.rs` 的 `leapgate_ui_mode_changed(mode)` | 同 C2 的路发 `Msg::UiMode`，CM 推 `{"name":"ui_mode","mode":"…"}`；`mode` 原样转发，取值由界面定。只推给 CM，不像主题、语言那样再广播给主进程的其他窗口 |

- 新界面 runner 的窗口类：主窗口 `LEAPGATE_UI_MAIN`，CM（`--cm`）`LEAPGATE_UI_CM`，安装页（`--install`）`LEAPGATE_UI_INSTALL`。三者分开，按主窗口类名找时不会找到另外两个。主窗口的类名（`leapgate_ui/app/windows/runner/main.cpp` 的 `kMainWindowClass`）和 `libs/leapgate/src/ui.rs` 的 `MAIN_WINDOW_CLASS` 要一致；另外两个 Rust 不找，只在 runner 里。
- 合并上游时核对：`core_main_invoke_new_connection` 的 Windows 分支仍按 `send_message_to_hnwd` 加 `WM_USER + 2` 把链接交给已有窗口（`uni_links_desktop` 认这个消息号）；上游有没有新增按 `FLUTTER_RUNNER_WIN32_WINDOW_CLASS` 或窗口标题找窗口的地方（`git grep -n "FLUTTER_RUNNER_WIN32_WINDOW\|FindWindow"`）。
- 已知限制：新界面还没有安装页（第三轮）。exe 名以 `install.exe` 结尾时，core_main 会注入 `--install`、不起服务，runner 按安装页处理，新界面目前写一行日志后退出。M0 只出名叫 `leapgate.exe` 的便携目录，碰不到；做便携打包（03 §1.7 第 5 步）或安装页时处理。
- `Msg`（`libs/leapgate/src/ipc.rs`）按 `name` 字段区分，`snake_case`；CM 的事件就是 `Msg` 本身的 JSON，所以改名等于同时改进程间消息和界面事件。以后 Leapgate 的进程间消息都追加在 `Msg` 里，不改已有变体的顺序和含义。
- C1、C2、S7 的已知限制：新旧版本的进程短暂同时在跑时，旧进程收到 `Data::Leapgate` 解码失败（上游 `next()` 返回 `Ok(None)`，两头都静默忽略），C1 返回 `{}`、C2 和 S7 没有效果。新界面便携版和旧界面不同时运行（03 §7.1），日常碰不到。`ShowCm` 在 CM 页面订阅之前到达时丢掉，不补发。
- C1、C2、S7 合并上游时核对：`Data` 枚举末尾有没有新变体（`Leapgate` 要留在最后，冲突固定在这一处）；`ipc.rs` 的 `handle`、`ui_cm_interface.rs` 的 `IpcTaskRunner::run` 两处消息循环仍以兜底的 `_ => {}` 结尾、分发仍在里面；`AUTHED_CONNS`、`AuthConnType`（新增类型要在 `src/leapgate_hooks/ipc.rs` 的映射和 `Counts` 里加）、`Connection::alive_conns()`、`send_to_cm` 有没有变；`connect_port_forward_if_needed` 的复用分支是否仍是出口登录唯一建 mux 的地方。

#### C3 原因码

原因码是稳定的，界面的连接状态和文案按它查表；改名等于改接口。"对应"一列是 `docs/新界面/01-内容与逻辑说明.md` §4.3 表里的那一行（按"现在的原文"列）。"能否重试"给界面核对用，导出不返回它：界面用 msgbox 事件的 `hasRetry`，它来自上游 `check_if_retry`，这里写的是按它算出的结果，和 01 §4.3"自动重试"一列一致：标题是 `Connection Error`、正文不含 offline、not exist、failed、resolve、mismatch、manually、restricted、incoming only、not allowed 时才是"是"。匹配按正文，下表"上游原文"写匹配方式；单测里每条都注明了源码位置（`reason.rs` 的 `upstream_message_boxes`）。

| 原因码 | 参数 | 对应 01 §4.3 | 上游原文（匹配方式） | 能否重试 |
|---|---|---|---|---|
| `id_not_exist` | | ID does not exist | 正文等于 | 否 |
| `peer_offline` | | Remote desktop is offline | 正文等于 | 否（30 秒规则在 Dart） |
| `key_mismatch` | | Key mismatch | 正文等于 | 否 |
| `key_overuse` | | Key overuse | 正文等于 | 是 |
| `punch_failed` | | other punch hole failure | 正文等于 | 是 |
| `rendezvous_failed` | | Failed to connect via rendezvous server | 正文开头（`Client::start` 会给 Failed 开头的错误补 `: Please try later`） | 否 |
| `secure_tcp_failed` | | Failed to secure tcp: … | 正文开头 | 否 |
| `direct_reset` | | 直连被重置（10054 / 104）或超时（relay-hint） | 类型 `relay-hint`、`relay-hint2` | 否 |
| `direct_failed` | | Failed to make direct connection to remote desktop | 正文开头 | 否 |
| `relay_failed` | | Failed to connect via relay server | 正文开头 | 否 |
| `peer_id_changed` | | Offline（登录阶段） | 正文等于 `Offline` | 否 |
| `linux_login_screen` | | Login screen using Wayland is not supported 等 | 正文等于 `Login screen using Wayland is not supported` | 否 |
| `wrong_password` | | Wrong Password | 类型 `re-input-password` | 否 |
| `wrong_2fa` | | Wrong 2FA Code | 类型 `input-2fa` 且标题 `Wrong 2FA Code`（标题 `2FA Required` 是第一次要，归 `other`，界面按类型处理） | 否 |
| `too_many_attempts` | | Too many wrong attempts / Please try 1 minute later | 正文以 `Too many wrong attempts` 开头（含 IPv6 前缀那条），或等于 `Please try 1 minute later` | 否 |
| `blocked` | | Your ip / ID is blocked by the peer | 正文等于两者之一 | 否 |
| `not_allowed` | | Connection not allowed | 正文等于（登录错误和对端的关闭原因两条路） | 否 |
| `main_window_not_open` | | The main window is not open | 正文等于 | 否 |
| `installed_only` | | Supported only in the installed version. | 正文等于 | 否 |
| `no_permission` | `feature` | No permission of file transfer / viewing camera / terminal / IP tunneling | 正文等于四者之一 | 否 |
| `privacy_mode_occupied` | | Someone turns on privacy mode, exit | 正文等于 | 否 |
| `peer_too_old` | `feature` | 对端版本太旧（摄像头、终端、端口转发） | 正文等于 `upgrade_remote_rustdesk_client_to_{1.3.9}_tip`（camera）、`Remote terminal is not supported by the remote side. Please upgrade to version 1.4.1 or higher.`（terminal）、`exit::PEER_TOO_OLD`（port_forward） | 否 |
| `reset_by_peer` | | Reset by the peer | 正文等于 | 是 |
| `timeout` | | Timeout | 正文等于 | 是 |
| `closed_by_peer` | | Closed manually by the peer | 正文等于 | 否 |
| `inactivity` | | Connection failed due to inactivity | 正文等于 | 否 |
| `no_displays` | | No Displays | 正文等于 `No displays` | 否 |
| `exit_not_enabled` | | 出口：对方没开出口 | 正文等于 `exit::MSG_NOT_ENABLED`（登录被拒，或会话中关了开关后通道被拒） | 否 |
| `exit_not_supported` | | 出口：对方不支持 / 版本太旧 | 正文等于 `exit::NOT_SUPPORTED`；出口卡片上的 `peer_too_old`（port_forward）也按这一行显示 | 否 |
| `exit_need_encryption` | | 出口：只接受加密连接 | 正文等于 `exit::MSG_NEED_ENCRYPTION` | 否 |
| `local_port_in_use` | `port` | 出口：本地端口被占用 | 正文是 `Failed to listen on <端口>: …`，端口取冒号前的数字（普通端口转发也是这句） | 否 |
| `exit_blocked` | | 出口：单个目标被拦（MSG_BLOCKED） | 正文等于 `exit::MSG_BLOCKED` | 否 |
| `exit_fake_ip_literal` | | 出口：MSG_FAKE_IP_LITERAL | 正文等于 `exit::MSG_FAKE_IP_LITERAL` | 否 |
| `other` | | 其余，含"服务器自定义的拒绝原因" | 以上都不是 | 按 `hasRetry` |

- `feature` 取 `file_transfer`、`camera`、`terminal`、`port_forward`；`port` 是数字。
- 01 §4.3 里写"不会出现"的两行（Incoming only mode、MSG_NEED_MUX）不给码，真出现时归 `other`。
- 已知限制：服务器自定义的拒绝原因（`PunchHoleResponse.other_failure`、`RelayResponse.refuse_reason`）在 msgbox 里只是任意正文，和系统错误原文分不开，C3 归 `other`、显示原文。01 §4.3 要的"服务器拒绝了此连接："前缀由 Q3 的导出给：界面收到连接阶段的 msgbox 后调 `leapgate_session_connection`，有 `refused` 就显示"服务器拒绝了此连接：<原文>"（见下面 Q3 第 4 节）。
- 不在 01 §4.3 里的错误不给码，归 `other`：摄像头、终端的（`No cameras`、`view_camera_unsupported_tip`、`Remote terminal is not supported by the remote side`）第三轮随说明一起补；`No active console user logged on…` 01 没有文案。
- Linux 对端的另几种登录错误（`x11 expected`、`ubuntu-21-04-required`、portal 不可用）归 `other`、显示原文；01 §4.3 只给了 Wayland 登录界面那一条。
- `Failed to listen on` 一律归 `local_port_in_use`。Windows 上端口落在系统保留段时报的是 10013（访问被拒），文案"被占用"不准，但"改用其他端口"的建议仍然对。
- 没认出的正文入表和写日志前截到 200 个字符（按字符边界），因为有的正文来自对端。
- 合并上游时：`git diff <旧> <新> -- src | grep msgbox` 看 msgbox 文本有没有变，变了就改 `reason.rs` 的表和单测（03 §3.8 第 3 条）；`check_if_retry` 的签名或语义变了，核对 `leapgate_msgbox_reason`。

#### Q3 连接路径和中继名

2026-10-30 读码定的方案（基线 `7bc0abd92`，下文行号以它为准），2026-10-31 维护者把末尾三条全部按推荐定了（见"维护者的决定"），同日实现。按 03 §6.1 Q3、§12 IQ14。界面要什么见 01 §4.2（第二级的"路径""中继服务器""传输"三项）。

**思路**：`race_ice`（§7.1 的 H-1，`src/client.rs:393`）包着整个 `Client::_start`，上游的结果、上游的错误、ICE 的结果都从它这里出去，所以路径在它里面判、在它里面写表。`_start` 里面有四样东西 `race_ice` 看不到：服务端回没回 `is_local`、局域网多候选赢没赢、连的是哪台中继、服务器有没有拒绝。这几处的挂钩拿不到会话，用 tokio 的 task-local 记录器传：`race_ice` 用 `leapgate::session::record` 把整场竞速包在记录器的 `scope` 里（ICE 那条腿不写记录器）；已有的 `lan_connect`、`lan_fallback` 在函数里调 `note_lan`，`src/client.rs` 新加的三处调 `note_relay`、`note_refusal`，不在 scope 里（单测、别的调用方）时什么也不做。已有挂钩的调用行和参数都没改。能这样做是因为 `_start` 的整棵调用树（两轮 `_start_inner` 的 `select_ok`、`connect`、`request_relay`、中继和 IPv6、WebRTC 的竞速）都在同一个 future 里被 poll；被 `tokio::spawn` 的只有 UDP NAT 测试和 WebRTC 的候选桥，Q3 用不到它们。

##### 1. 六种路径怎么判

纯函数 `leapgate::session::classify`，`race_ice` 拿到成功结果后调用，按下表顺序取第一条命中：

| 顺序 | 01 §4.2 的叫法 | 路径码 | 条件 | 数据从哪来 |
|---|---|---|---|---|
| 1 | 直接 IP 访问 | `direct_ip` | `is_direct_ip_access(peer)`（`src/common.rs:3039`） | `race_ice` 的 `peer` 参数。上游 `_start` 对 IP 和 `域名:端口` 直接 `connect_tcp_local`，返回 `"TCP"`（`src/client.rs:440`、`:455`） |
| 2 | ICE 胜出时 | `lan` / `punch_v4` / `punch_v6` | `race_legs` 返回 `Either::Left`。选中对的对端地址是私网 IPv4（10/8、172.16/12、192.168/16）或 ULA（fc00::/7）时 `lan`；否则按地址族 `punch_v4` / `punch_v6` | `IceWin` 里多存的 `remote`（`sel.remote` 的 IP），在 `leapgate_hooks.rs` 里，不碰上游 |
| 3 | 经中继 / 经中继（WebSocket） | `relay` / `relay_ws` | 结果的 `direct` 为假（`"Relay"`、`"WebSocket"`，以及走 TURN 的 `"WebRTC"`）。流是 `Stream::WebSocket` 时 `relay_ws`，否则 `relay` | 结果元组。按流的变体判、不按标签：`connect()` 的中继回退在 WebSocket 下也写 `"Relay"`（`src/client.rs:1588`、`:1627`） |
| 4 | 局域网直连 | `lan` | `"TCP"`、直连，并且这次尝试里服务端回过 `is_local`（局域网多候选胜出，或上游按 `is_local` 连了本地地址） | 记录器：`lan_connect` 成功时、`lan_fallback` 收到 `is_local = true` 时各记一笔（已有挂钩 `src/leapgate_hooks.rs` 的 `lan_connect`、`lan_fallback` 里各加一行 `note_lan`） |
| 5 | 打洞直连（IPv4）/（IPv6） | `punch_v4` / `punch_v6` | `"TCP"` 直连但不是局域网（TCP 打洞）：按流本地地址的地址族（IPv4 映射地址算 IPv4）；`"UDP"` 是 `punch_v4`；`"IPv6"` 是 `punch_v6`；直连的 `"WebRTC"` 按 `webrtc_remote_ipv6()`（拿不到时算 IPv4，和 `io_loop` 给连接类型标签的做法一致） | 结果元组、`Stream::local_addr` |
| 6 | 都不是 | 不给（`{}`） | 读码看不会出现；界面只显示第一级 | |

- 传输（01 §4.2"传输：TCP / UDP"）顺带给：ICE 和标签是 `"UDP"`、`"IPv6"`（这两种带 KCP）、`"WebRTC"` 时 `udp`，其余 `tcp`。
- 01 §4.2 要求不区分 ICE 和上游打洞，这里只按"实际走的是不是局域网地址"分 `lan` 和打洞（维护者 2026-10-31 定）。全局 IPv6 即使两端在同一 /64 也算打洞直连（IPv6），和上游 IPv6 打洞一致。srflx 的对端地址都是公网地址，归打洞。
- 上游 UDP 打洞不会出现在 `is_local` 那一轮：服务端的局域网响应不带 `is_udp`（leapgate-server `rendezvous_server.rs` 的 `handle_local_addr`），`_start_inner` 不会把 NAT socket 连上去。`is_local` 那一轮 IPv6 打洞赢了算打洞直连（IPv6）。
- WebRTC：自建服务器时默认关（`get_local_option` 给 "N"），用户打开时按上表第 3、5 行处理，走 TURN 时不给中继名。

##### 2. 中继名

- 01 §4.2 和 §7 的示例显示的是服务器下发的中继地址（`relay-1.example.com`），没有另起的名字。取服务端下发的原串，去掉默认端口 `:21117`（`RELAY_PORT`），非默认端口保留。
- 挂钩放在 `create_relay` 里，不放 03 写的 `request_relay`。中继连接有三个来源：`_start_inner` 收到被控端要求中继的 `RelayResponse` 时直接 `create_relay(rr.relay_server)`（`src/client.rs:1135`）；`connect()` 直连失败后、两处 WebRTC 握手失败后经 `request_relay` 再 `create_relay`（`:1868`）。放在 `request_relay` 只看得到后两种，第一种会漏（被控端是对称 NAT、任一端强制中继时都走它）；三条路最后都经过 `create_relay`。
- `create_relay` 在 `RelayResponse` 分支里和 IPv6、WebRTC 同时起跑，没赢也会被记下，所以只在第 1 节判成中继时才给名字；`"WebRTC"`（TURN）不给；一次尝试里记到两台不同的中继时不给（两轮 `_start_inner` 同时问服务端，读码看服务端给的是同一台，实际碰不到）。
- 不按连接对上：`create_relay` 把 `relay_server` 按值交给 `ipv4_to_ipv6` 再去连，连好以后原串已经没了；要对上得在连接前后各加一处挂钩，不值。

##### 3. 挂钩清单

| 编号 | 文件 | 位置 | 加几行 | 调用 | 为什么不能少 |
|---|---|---|---|---|---|
| Q3-1 | `src/client.rs` | `create_relay`（`:1872`）开头，上游注释 `The proxy's address family…` 和 `let relay_server = check_port(relay_server, RELAY_PORT);`（`:1881`）之前 | 2（注释 + 调用） | `leapgate::session::note_relay(&relay_server);` | 中继地址只在 `_start_inner` 和 `create_relay` 的局部变量里，`race_ice` 拿到的结果里没有 |
| C3-1 | `src/client.rs` | `_start_inner`，`bail!(ph.other_failure);`（`:1011`）之前 | 2 | `leapgate::session::note_refusal(&ph.other_failure);` | 服务器自定义的拒绝原因是任意正文，到界面时和系统错误分不开（C3 的已知限制） |
| C3-2 | `src/client.rs` | `request_relay`，`bail!(rs.refuse_reason);`（`:1858`）之前 | 2 | `leapgate::session::note_refusal(&rs.refuse_reason);` | 同上；这条在 `connect()` 里还会被包成 `Failed to connect via relay server: <原因>`，按正文认不出来 |
| 已有 H-1 | `src/client.rs:393` | `race_ice` | 0 | 调用不改 | 建记录器、判路径、写表都在函数里 |
| 已有 | `src/client.rs:1379`、`:1385` | `lan_connect`、`lan_fallback` | 0 | 调用不改 | 在函数里记局域网胜出和 `is_local` |

- `src/client.rs` 新增 3 处（Q3-1、C3-1、C3-2），其他上游文件 0 处，在 03 §6.1 定的"不超过 3 处"以内。合并不了：两处拒绝都在各自的 `bail!` 前面，和 `create_relay` 不在同一个函数里；把 Q3 挂到 `request_relay` 里能和 C3-2 挨着，但会漏掉上面说的 `RelayResponse` 那条中继。
- 三处直接调 `libs/leapgate`（和上游文件里已有的 `leapgate::route::self_id()`、`leapgate::lan::peer_candidates` 一样），不经 `leapgate_hooks.rs` 转一手：它们不用上游的私有项。
- `src/client/io_loop.rs`、`src/flutter.rs` 不加：`race_ice` 返回在 `io_loop` 调 `set_connection_type`（发连接就绪事件，`src/client/io_loop.rs:218`）之前，界面收到事件时表已经写好；导出用上游已有的 `sessions::get_session_by_session_id` 找会话。

##### 4. 交给界面

- 状态放 `libs/leapgate/src/session.rs`，键是（对端 ID、连接类型），值是这次连接的路径、传输、中继名，或者服务器的拒绝原因。不按界面 session_id 存：`race_ice` 拿到的是对端会话（上游的 `Session`），一个对端会话可以挂多个界面会话；上游 `flutter::sessions` 的 `SESSIONS` 就是按（`lc.id`、`conn_type`）存对端会话、每个键只有一个（`insert_session` 用 `entry().or_insert`），`race_ice` 里的 `interface.get_id()` 和 `get_lch()` 的 `conn_type` 正是这个键。
- 导出 `leapgate_session_connection(session_id)`，同步，返回 JSON 字符串（和 C3 一样，F0 实测过的形态）：先用 `sessions::get_session_by_session_id` 找到对端会话、取出键，再查表。例：`{"path":"relay","transport":"tcp","relay":"relay-1.example.com"}`、`{"path":"lan","transport":"tcp"}`；没有记录（还没连上、正在重连、会话已不在）时 `{}`，界面只显示第一级。路径码 `lan`、`direct_ip`、`punch_v4`、`punch_v6`、`relay`、`relay_ws` 和 C3 的原因码一样算接口。不另给地址族：打洞的两种已经带着，其余几种界面用不到。
- 写入：`race_ice` 一进来先删掉这个键的旧记录，成功时写新记录，失败时只在有服务器拒绝原因时写。重连（`Session::reconnect`、自动重试）每次都重新走 `Client::start`，所以重连期间查到 `{}`，连上以后换成新路径，界面在这一轮的连接就绪事件后重新取。`Session::reconnect` 在"正在连接"时直接返回，同一个对端会话不会有两轮 `Client::start` 同时跑。
- 清理：不加挂钩，照 V1 的做法：每次调 `leapgate_session_connection` 时顺手删掉已经没有对端会话的键（用上游 `sessions::get_session_by_peer_id` 判断，查的时候不拿着表的锁）。放在导出里而不是写入时，`race_ice` 就不用引用只有 Flutter 构建才有的 `flutter::sessions`；不带界面的构建没人查，表里每个连过的（对端、连接类型）留一条，不会无限长。
- 端口转发、出口隧道也经 `Client::start`，同样会写（连接类型不同，键互不影响）；界面不查它们，出口的状态由 E2 给。
- 服务器拒绝：`race_ice` 返回错误、记录器里有服务器拒绝原因时，把原因写进同一张表，导出返回 `{"refused":"<原文>"}`；界面收到连接阶段的 msgbox 后调这个导出，有 `refused` 就显示"服务器拒绝了此连接：<原文>"。错误原文不动，旧界面和以前一样。ICE 在上游被拒以后照样可能连上，那时按成功写路径，不给 `refused`。两轮 `_start_inner` 一轮被拒、另一轮因别的原因失败时，返回的错误可能是另一轮的，`refused` 照样给（服务器确实拒绝了）。

##### 5. 拼不全、有风险的地方

- 记录器只在 `race_ice` 的 future 里被 poll 时有效。上游哪天把 `_start_inner`、`connect` 或中继竞速改成 `tokio::spawn`，就拿不到局域网标记和中继名：局域网的 TCP 直连会被判成打洞直连，中继没有名字，不报错。单测覆盖不到，合并上游时核对 `_start`、`_start_inner`、`connect`、`request_relay` 里有没有新增 spawn，以及 `create_relay` 是否仍是所有中继连接的必经之处。
- 一次尝试里记到两台不同的中继时不给名字（见第 2 节）。
- 上游的局域网判断靠服务端的 `is_local`：服务端误判同网（两端公网出口相同、其实不在一个局域网，§3.4 的已知限制）时，上游的 TCP 直连被判成局域网直连；服务端判成不同网、其实在一个局域网、走了 TCP 打洞时，判成打洞直连。ICE 按地址判，不受这条影响。
- 上游 `is_local` 那一轮 IPv6 打洞赢了算打洞直连（IPv6），哪怕两台在同一局域网。

##### 6. 合并上游时核对

- `_start`、`_start_inner`、`connect`、`request_relay` 里有没有新增 `tokio::spawn`（把建连接的那段搬进 spawn 出去的任务，记录器就拿不到，见第 5 节）。
- `create_relay` 是否仍是所有中继连接的必经之处，入参是否仍是服务端下发的原串；`bail!(ph.other_failure)`、`bail!(rs.refuse_reason)` 还在不在、有没有新的服务器拒绝出口。
- 返回元组的连接类型标签（`"TCP"`、`"UDP"`、`"IPv6"`、`"Relay"`、`"WebSocket"`、`"WebRTC"`）有没有增减或改名，`direct` 的含义变没变：`classify` 按它们判。
- 上游登录时的 `display_name` 算法（`src/client.rs` 里 `LoginConfigHandler` 组 `LoginRequest` 那段）变没变，变了就改 `libs/leapgate/src/ui.rs` 的 `display_name` 和单测。

##### 维护者的决定（2026-10-31，全部按推荐）

1. Q3 的挂钩放 `create_relay`，不放 03 写的 `request_relay`（理由见第 2 节）。
2. C3 的"服务器拒绝了此连接："前缀要做（`src/client.rs` 再加 2 处，共 3 处）：拒绝原因写进本表、由 `leapgate_session_connection` 返回，错误原文不动、旧界面不受影响。没选的备选：在 `race_ice` 里把错误正文改写成 `Server refused the connection: <原因>`，代价是旧界面也显示这句英文。
3. ICE 选中的对端地址是私网 IPv4 或 ULA 时判成 `lan`（显示"局域网直连"，显示的是实际走的网络）。没选的备选：ICE 一律按地址族显示打洞直连，和旧界面的标签一致。

### 10.5 验收记录

#### M0 工程骨架（2026-10-30，`f426ef520`）

03 §5.2 M0 的验收：

| 项 | 结果 |
|---|---|
| `-Ui leapgate` 从干净的构建 worktree 编出便携目录 | 通过。detached worktree、全量 cargo；产物齐（`leapgate.exe`、`libleapgate.dll`、两个纹理插件、`data\app.so`、`dylib_virtual_display.dll`），`flutter_windows.dll` 是自编引擎（哈希和清单一致），两个 `pubspec.lock` 没有漂移。产物里另有 `dartjni.dll`：core 解析到的 path_provider 2.1.6 带了 jni，上游锁的 2.1.5 没有，不影响运行 |
| `-Ui upstream` 照常编出旧界面，五项冒烟 | 通过。同一 worktree 全量编出（`6de7a1349`，Rust 和 `f426ef520` 相同），两端都用这份构建：连接（ICE 胜出，登录成功）、强制中继（`--relay`）、文件传输两个方向（哈希一致）、TCP 端口转发（HTTP 200）、出口（socks5h 和 CONNECT 都 200，直连和经中继各一次） |
| 启动后显示本机 ID 和服务状态 | 通过。日志有版本和本机 ID 两行；窗口左栏显示三位一组的 ID 和"已就绪" |
| W1：再次启动把已有窗口提到前面；`--connect` 交给运行中的主窗口；标题改掉以后照样成立；两个界面同时运行时互不交给对方 | 通过。再次启动的进程约 0.2 秒退出，原窗口（含先最小化的情形）恢复并到前台；`--connect` 后原进程日志有 `link received`；用 `SetWindowText` 把标题改成"测试设备 - Leapgate"后两条照样成立；新旧界面同时运行时各自的 `--connect` 只到自己的主窗口，只开一个界面时也不交给对方、各自起自己的实例 |
| 窗口尺寸 | 部分通过。3840×2160、150% 上默认客户区 1280×800、最小 960×600（逻辑像素），整窗在工作区内居中。1920×1080 开 150%、1366×768 开 100% 两种组合未验证（没有这种显示器，也没改系统显示设置），按代码核对：首次客户区取 max(min(1280×800, 0.9×工作区), min(960×600, 工作区))，非客户区按实际量 |
| 拖动、双击最大化、四边改大小、窗口按钮；125%、150%、200% 下清楚 | 部分通过。左、右、下三边的原生改大小（命中测试）、最小化 / 最大化 / 还原 / 关闭按钮、双击空白最大化和还原，用窗口消息驱动验过；150% 下清楚。拖动空白移动窗口、拖上沿改大小、悬停效果（关闭按钮变红、提示气泡）、125% 和 200% 未验证：会话里注入不了真实鼠标，台式机上维护者可能正在用，没有接管 |
| 画廊输入框用中文输入法，候选框位置正确 | 未验证：要真实键盘和输入法 |
| 画廊 M0 组件浅色 / 深色 × 简洁 / 详细，和 `A-基础.html` 对照 | 通过。88 个组件状态 × 4 导出 352 张；顶栏、菜单和样稿并排对照过；两轮审查（基建一轮、界面一轮）后必修项清零，其余小差异记进总仓库 `docs/新界面/待调.md` |

单测：core 8 个、app 33 个，3.44.9 和 3.47.9 下都通过；`flutter analyze` 两个包都没有问题。

最新 stable 检查（03 §8.8）：Flutter 3.47.9（2026-10-29，Dart 3.13.7），官方 SDK、官方引擎、Impeller 默认开。
1. 按 `-Ui leapgate` 编一次：通过。`pub get` 改了两个锁文件里 18 个包的版本（检查完已还原，不提交）；frb 1.80.1 照常生成两块桥；构建只报预期的"不是自编引擎"警告。
2. 组件画廊：通过。352 张全部导出，和同一提交在 3.44.9 下的导出逐张比较，版面一致，差异在抗锯齿级别；两处可见差异：菜单面板的 Material elevation 阴影在 Impeller 下略深、略往下（引擎层，记录不处理）；标签溢出那张的滚动位置不同，是截图时滚动动画还没走完。
3. 4K 上屏：不适用，M2a 起才有会话页。
4. `flutter analyze`：core、app 都没有问题，没有废弃提示（复制件也没有）。

发现的问题：
- **新旧界面同时运行时 IPC 互相拒绝**：上游 2026-05 起，主 IPC 管道（`\\.\pipe\Leapgate\query`）只接受和本进程同一路径的 exe（`src/ipc/auth.rs` 的 `authorize_windows_main_ipc_connection`）。新旧界面的 exe 在不同目录，先启动的占住管道，后启动的连上去被拒、不停重试：日志每秒约 3 行，后启动的界面显示"未就绪"、一次性密码一直"正在生成"。两个界面都是便携版时就会这样；装着的旧界面（服务进程在安装目录）加新界面便携版，按读码应当一样。03 §7.1 的"共用配置、ID、IPC 管道"因此不成立。维护者 2026-10-30 定：新界面便携版只在旧界面不运行时用（装着的旧界面连托盘和服务一起停掉），不放宽上游校验、不分开命名，03 §7.1 已改。
- 新界面首次启动时不处理自己命令行里的链接（只开旧界面时跑新界面的 `--connect`，新界面起来了，但没有接这个链接）；`--connect` 交给已有主窗口后窗口不到前台。都随 M2a 的连接入口做。
- 每启动一次辅助进程（第二个实例、`--connect`），日志文件 `leapgate_rCURRENT.log` 都会被改名换新，常驻进程接着写改名后的文件（上游行为），读日志要扫全部文件。

#### M1 core 第一批（2026-10-31，`951605d69`）

范围是 03 §3.5 第 2~5 步（第 1 步随 M0 做了），分四块：A 结构、D 选项 model、B 复制上游 models、C 连接状态，结构和取舍见 10.6、10.7。同期合入的 Rust 导出：C3 原因码、V1 标签可见性（10.4）。审查做了三路：B 单独一轮；C 的连接状态一轮；M1 整体衔接加 C3、V1 一轮。必须改的都改了，可以不改的按 10.6 记成已知限制或留给后面的块。

03 §5.2 M1 的验收：

| 项 | 结果 |
|---|---|
| §3.4 每一条都有回放测试并通过 | 通过。对照表在 10.6；core 66 个测试全过。连接状态几处关键的复位和判断，逐个去掉后都有测试失败 |
| `core` 不引用 `app` | 通过。core 的 pubspec 不依赖 `leapgate_ui`，`lib/` 里没有 `package:leapgate_ui` |
| `flutter analyze` 相对上游原件没有新告警 | 通过。3.44.9 下 core 是 92 条 info，全在复制件里（`input_model` 71、`model` 9、`relative_mouse_model` 6、`local_flutter_shortcuts` 5、`file_model` 1），抽查过和上游原件同一位置的提示一致；改写和新写的文件 0 条。app 0 条 |
| "只删界面调用"那一档和上游原件的差异只有界面调用和导入 | 通过。B 的审查逐个复制件比过，整体审查又抽查了 4 个；允许的偏离（快捷键暂删、`kWindowId` 判断、按会话记的状态、`desktop_render_texture` 一行）都写在文件头的来源行和 10.6 里 |

Rust：`cargo test -p leapgate` 135 个通过；主 crate 用 `--features hwcodec,vram,flutter` 做 `cargo check` 通过（C3、V1 合入时）。`git diff main HEAD -- flutter/` 为空。

最新 stable 检查（03 §8.8）：Flutter 3.47.9（2026-10-29，仍是当时最新的 stable），官方 SDK、官方引擎、Impeller 默认开。检查做在 `b3f94489a` 上；之后的 `951605d69` 只改了 core 的 Dart 和 `reason.rs`，在 3.44.9 下重跑过测试和 analyze。
1. 按 `-Ui leapgate` 编一次：通过。`pub get` 改了锁文件里的几个基础包（app 5 个：intl、matcher、meta、test_api、vector_math；core 4 个，没有 intl），检查完已还原，不提交。
2. 组件画廊：通过。两版各导出 352 张，逐张比较，差异在抗锯齿级别；能看出来的两处和 M0 相同：菜单面板的 elevation 阴影在 Impeller 下略深，标签溢出那几张截图时滚动动画还没走完。
3. 4K 上屏：不适用，M2a 起才有会话页。
4. `flutter analyze`：app 没有问题；core 是 97 条，比 3.44.9 多出 5 条 warning `unawaited_return_in_try_block`，在复制件 `models/file_model.dart` 的 :1466、:1486、:1492、:1501、:1518。这 5 行和上游原件逐字相同，属于上游带来的提示，按 10.1 不改，等上游改了随三方合并带过来。因为是 warning，3.47.9 下 core 的 `flutter analyze --no-fatal-infos` 退出码不是 0；拿退出码当关卡时要知道这一点。新写和改写的文件没有新提示，也没有废弃提示。core 61 个、app 33 个测试（另跳过 1 个）在 3.47.9 下都通过。

留给后面的块的，都写在 10.6：截图、打印、`switch_back`、聊天和语音事件随 M2b；`cm_file_model` 和 CM 的全局事件随 M3；`shortcut_model` 改写时补回暂删的几行；V1 接入时要处理 1.5 秒唤醒；01 §4.1 的"查找设备""建立连接"合成一步。

#### M2a 最小控制端（2026-10-31，`0810e2b43`）

黑盒验收，两台便携端点无人值守跑：新界面（`0810e2b43`，3.44.9 自编引擎）当控制端，旧界面（`8fcdabb1e`，Rust 和 `0810e2b43` 相同）当被控端；被控端是 4K、DXGI 每约 5 秒失效一次的机器。面板上的输入和点击用 `scripts/e2e/leapgate-post-input.ps1` 向窗口投递消息，按 PrintWindow 截图的坐标操作（UI Automation 用不了，见问题 3）。要点按键的一项用了真实按键注入。依据 04 §6，冒烟清单第一版在总仓库 `docs/新界面/冒烟清单.md`。

**04 §6.3 真实连接**

| 项 | 结果 |
|---|---|
| 直连 | 通过。上游 IPv6 直连胜出，标签和工具栏"直连"，轻提示"已建立直连" |
| 经中继 | 通过。`--relay`，没有 ICE 行，标签"经中继"。`--relay` 照上游写进对端的 `force-always-relay`，测完复原 |
| 自研 ICE 胜出 | 通过。`leapgate ice: selected host/v6/ethernet <-> host/v6 in 2266 ms`，服务端 `ice_result` 同一行逐项一致，随后登录 |
| 存过密码直接进 | 通过。面板勾"记住密码"登录一次后，不带密码再连直接登录 |
| 输密码 | 通过。两步进度"建立连接 ✓ → 验证身份"，密码框自动获得焦点，空时"连接"不可点；回车提交，短暂显示"已连接，正在等待画面…"后出画面 |
| 密码错误 | 通过。红字"密码错误"（输入被清空，见待调） |
| 2FA | 未验证：被控端开二次验证要在旧界面设置里扫码绑定，旧界面的语义树也用不了，没有无界面的开法 |
| 等对方接受 | 通过。面板"正在等待对方接受…"、"已等待 ‹n› 秒"、"取消"；被控端 CM 点"接受"后连上。被控端 3 分钟没处理时它关掉连接，控制端自动重连、回到等待。缺"显示给对方的名称"（已在待调） |
| 不安全连接确认 | 未验证：控制端清空 Key 后服务端回 Key mismatch，面板"本机与服务器的密钥（Key）不一致，无法连接服务器。"、只有"关闭标签"；没有不配 Key 的会合服务 |
| 断线后自动重试 | 部分通过。经中继的会话里停掉被控端：面板"连接已被远程设备断开。"、"1 秒后重试（第 1 次）"、"重试"，随后重连。第二次失败是"Failed to connect via rendezvous server: Please try later"，按表归成"无法连接服务器。请检查网络连接。"、不自动重试，所以翻倍没看到（问题 4）。经 KCP（上游 IPv6 打洞）的会话里被控端消失时是上游的 `Peer stopped answering, reconnecting`，面板直接回到"正在连接" |
| 对方重启后静默重连 | 未验证：要被控端真的重启，两台端点都不能重启，同网测试虚拟机这次没开机（它重启后也不会自动起便携版） |
| 1.5 秒唤醒锁屏 | 未验证：两台被控端连上后都在 1.5 秒内出画面，没有锁屏又能安全解锁的被控端 |
| "改用中继" | 未验证：造不出直连被重置的错误 |
| 对方断开 | 通过。被控端 CM 点"断开连接"：面板"对方已断开连接。"、"关闭标签""重新连接"，标签"已断开"；"重新连接"能连上 |
| 出错文案（附带） | ID 不存在："未找到 ID 为 ‹ID› 的设备。…"、"关闭标签""修改 ID"，标签"连接失败" |

**04 §4 会话标签和输入**

| 项 | 结果 |
|---|---|
| 只有当前标签收键盘、切走时远程设备收到抬起 | 不通过，见问题 1：新界面的会话没有把键盘发给远程设备 |
| 标签"×" | 通过。断开（`Exit io_loop`）并关掉标签 |
| "+"回主页 | 通过。切到主页，光标在连接框里，直接打字出现"搜索结果"、"连接到 ‹输入›"、"未找到匹配的设备" |
| 系统窗口标题跟着标签 | 通过。主页"Leapgate"，会话"‹设备名› - Leapgate"，还没拿到名称时"‹格式化 ID› - Leapgate" |
| 关窗流程 | 部分通过。`CloseSessions` 路径（两个选项预设）通过：会话断开、窗口隐藏、进程留着。没有会话时问"关闭窗口？"（退出 / 在后台运行、记住此选择）；有会话且 `enable-confirm-closing-tabs = 'Y'` 时是"断开全部 1 个会话并关闭窗口？"加"不再提示"，选"在后台运行"后会话断开、窗口隐藏。没写这个选项时（新配置）有会话也只问"关闭窗口？"，见问题 2 |
| `--connect` 交给运行中的主窗口后到前台 | 通过。窗口隐藏、最小化、被别的窗口挡住三种情况下都显示出来并到前台，开新标签 |

**04 §6.4 引擎**

- 4K、频繁重建采集的被控端：通过。新界面在这台被控端上开过十几个会话（单个最长约 7 分钟），画面持续更新，Windows 应用程序日志里没有 `leapgate.exe` 的崩溃事件。解码器两个界面一样，都是 `hevc … D3D11VA ram decoder`。
- 开着 UI Automation 客户端（每秒遍历一次整棵树，持续 7 分钟）开、关会话标签和两种关窗确认：通过，不崩溃。讲述人没开（控制端那台机器有人在用，讲述人会出声）。但树始终只有窗口和 `FLUTTERVIEW` 两个元素，见问题 3。

**V1 占用对比**（只有一台被控端有画面，用一个会话；被控端开一个不停刷新的控制台窗口让画面一直在变；会话标签切到后台的办法是再开一个 ID 不存在的标签，效果和停在主页相同；控制端进程的 CPU 按单核百分比、GPU 是各引擎利用率，各 30 秒平均）

| 提交 | 会话标签在前 | 会话标签在后台 |
|---|---|---|
| `0e3db691d`（接 V1 之前，Flutter 部分单独编，Rust 产物和最终构建同一份） | CPU 25.1%、3D 2.4%、视频解码 2.5% | CPU 18.9%、3D 0.9%、视频解码 2.5% |
| `0810e2b43` | CPU 25.7%、3D 2.4%、视频解码 2.5% | CPU 16.8%、3D 0.9%、视频解码 2.5% |

后台时照常收流、解码（视频解码不变，符合设计）；V1 比接入前在后台再少约 2 个百分点的单核 CPU，3D 两者一样（接入前后台标签本来就不重绘）。

**04 §6.6 和样稿对照**：浅色对照了 P1 本机区、最近列表、连接框搜索，P2 会话标签、面板（要密码、密码错误、等对方接受、等画面、出错和倒计时、对方断开、Key 不一致）、工具栏默认态和收起态、轻提示、两种关窗确认。必修项见问题 2；版面层级、令牌没看到用错的；小差异 3 条记进总仓库 `docs/新界面/待调.md`（ID 的"复制"是实心按钮、密码错误后输入被清空且没有"输入密码"标签、还没拿到对端信息时标题和副标题都是 ID）。深色未验证：M2a 没有切换主题的入口，本地选项 `theme = 'dark'` 不起作用；画廊的深色导出看过几张，没有发现问题。

**04 §6.8 旧界面五项**：通过。两端都用 `8fcdabb1e` 旧界面：连接（ICE 胜出，登录成功）、`--relay`、文件传输两个方向（两边 SHA-256 一致）、TCP 端口转发（HTTP 200）、出口（socks5h 和 HTTP CONNECT 都 200，`tunnel up (direct)`）。ID 加盐：空配置目录起一次，`Generated id` 是 9 位、≥ 268435456，测完放回原配置。

最新 stable 检查（03 §8.8）：Flutter 3.47.9（2026-10-29，验收时仍是最新 stable），官方 SDK、官方引擎、Impeller 默认开。
1. 按 `-Ui leapgate` 编一次：通过。`pub get` 改了两个锁文件，检查完已还原，不提交。
2. 组件画廊：通过。两版各导出 824 张，584 张逐像素相同，其余每张差异像素不到 0.02%（抗锯齿级别）。
3. 4K 上屏：通过。只用 `--connect --password`，没开任何 UI Automation 客户端；被控端每约 5 秒重建一次采集，会话约 7 分钟，画面正常，没有崩溃；stderr 只有 "Using the Impeller rendering backend (OpenGLESSDF)"。
4. `flutter analyze`：app 没有问题；core 97 条，和 M1 相同（92 条 info 全在复制件，5 条 warning 在复制件 `models/file_model.dart`），新写和改写的文件没有提示，也没有废弃提示。core 117 个、app 197 个测试（跳过 2 个）在 3.47.9 下都通过。

发现的问题：
1. **会话里的键盘没有发到远程设备**（必须在交付试用前查清）。新界面会话标签在前、真实光标在画面上并真实点过画面后，用 `keybd_event` 注入左 Shift、F12，被控端 `GetAsyncKeyState` 一次按下都没看到；同一台机器、同样做法换旧界面当控制端，被控端看到了按下和抬起。投递 `WM_KEYDOWN` 也没有发过去。鼠标是通的（投递的点击在远程设备上生效）。还没用真实键盘确认，注入的按键带 `LLKHF_INJECTED`，如果新界面有意过滤注入事件，就要换真实键盘再测一次。
2. **没写过 `enable-confirm-closing-tabs` 时，有会话关窗不确认断开**（必须改）。上游这个选项缺省是开（`enable-` 开头的选项空值算开），新配置里没有这个键；新界面在缺省时只问"关闭窗口？"，不提断开会话、也没有"不再提示"，写成 `'Y'` 才出现 01 §2.1 要的确认。
3. **语义树始终为空**（不挡试用，要单独查）。自编引擎上，UI Automation 只看到窗口和 `FLUTTERVIEW`，从第一次查询起就是这样；stderr 每次语义更新都是 "Accessibility bridge rebuilt after failed update: 0 will not be in the tree and is not the new root"（也有 45、64、74 号节点）。根节点 0 被判成不在树里，补丁 0001 随后重建，树一直是空的：讲述人读不到任何控件，04 §6.3 原定的 UI Automation 脚本也用不了。官方引擎上是否也这样没测（不能在官方引擎上开 UI Automation 客户端）。
4. 对方掉线后重连失败的文案不对（可以记待调）：会话里被控端退出约 20 秒后，Rust 报 "Failed to connect via rendezvous server: Please try later"，按 01 §4.3 的表显示"无法连接服务器。请检查网络连接。"，实际服务器是通的、是对方不在线；这一条不自动重试，所以对方很快回来也不会自己连上。

复验（2026-10-31，`3ca7230f8`，同样的两台端点和做法）：
- 问题 1（键盘）：通过。会话页创建时补调 `bind.mainInitInputSource()` 后，真实注入的左 Shift、F12 在被控端都收到了按下和抬起；在会话标签按住 Shift 再点另一个标签，被控端在切走的那一刻收到抬起，比真正松开早约 2 秒。另一个标签是 ID 不存在的标签（只有一台被控端有画面），"新标签那台没收到按下"这一半没法用真设备验。
- 问题 2（关窗确认）：复现不出，判通过。程序停着时 `Leapgate_local.toml` 里没有 `enable-confirm-closing-tabs`，也没有 `leapgate-close-action`；有一个会话时发 WM_CLOSE，出现"断开全部 1 个会话并关闭窗口？"和"不再提示"。照上一轮的顺序（先在没有会话时关窗、取消，再连上、再关窗）也一样。上一轮那次为什么只问"关闭窗口？"没查清：那次两个键是用 `Configure` 写空串删掉的，删掉后才启动程序。
- 小改：本机区 ID 下面的"复制"是文字按钮，和 ID 左对齐；连接"最近"里有记录的设备时，连接中和要密码时面板标题、会话标签、窗口标题都先显示设备名，副标题是 ID。

#### M2b 控制端完整会话页和主页（2026-11-01，`9799bb9ec`）

黑盒验收，无人值守。控制端 A（新界面，3.44.9 自编引擎，补丁 0003）连被控端 B（4K，旧界面 `8fcdabb1e`；Q3 的挂钩只在控制端，所以 B 没有重编）。依据 05 §6。面板操作用 `scripts/e2e/leapgate-uia.ps1`（原生 COM 的 IUIAutomation，按语义名），工具栏菜单项没有 Invoke 模式、用它的 `Click`（真实鼠标）；点击窗口里没有名字的位置用 `leapgate-post-input.ps1`。含被控端画面的截图读完即删，不留证据。

**05 §6.1 自动测试**：通过。core `flutter analyze` 92 条 info（基线不变，全在复制件里），测试 170 个通过；app analyze 0 条，测试 405 个通过、2 个跳过。Rust：`leapgate` crate 139 个通过，其中有 `session::tests::connection_paths`（Q3 分类，逐种路径）和 `ui::tests::display_name_as_upstream_computes_it`（本机名对上游算法）；根 crate `cargo test --lib leapgate` 11 个通过（`leapgate_hooks`）。

**05 §6.3 真实连接**

| 项 | 结果 |
|---|---|
| 连接方式详情，自研 ICE 胜出 | 通过。日志 `leapgate ice: selected host/v6/ethernet <-> host/v6`；详情"路径 打洞直连（IPv6）、传输 UDP、加密 已加密"，指纹带复制按钮；画面数据（编码 H265、帧率、目标码率、色度 4:2:0、速度）；延迟只有"端到端"一行，带当前、最低、平均、最高和近 60 秒折线；"在画面上显示质量数据"开关 |
| 经中继 | 通过。`--relay`；详情"路径 经中继、中继服务器 ‹地址›、传输 TCP"，地址和日志 `relay_server` 一致；标签语义名里带"经中继" |
| 上游直连、局域网直连 | 未验证：两端都在 ICE 抢先，造不出上游直连；局域网直连要同局域网的第二台端点（测试虚拟机宿主内存紧，没开机） |
| 工具栏菜单 | 通过。远程桌面、画面、输入、操作、会话、聊天六个菜单各打开一次，条目和 01 的分组一致；"添加备注"灰显并有"登录后可添加备注"说明 |
| 画质、缩放 | 通过。选"速度优先"后对端配置 `image_quality = 'low'`；选"适应窗口"后 `view_style = 'adaptive'` |
| 截图并另存 | 通过。操作 › 截图后出"截图已完成"和"另存为""复制到剪贴板"；另存为弹出系统对话框，保存的 PNG 有效（约 500 KB，已删） |
| 隐私模式 | 未验证：便携构建没带 `WindowInjection.dll`，被控端开不起来。点开关后出一条只有"失败"二字的通知，没有原因（见问题 1） |
| 阻止、取消阻止本地输入 | 未验证：被控端非提权，`BlockInput` 超时，通知"无法阻止远程设备的本地输入（Error: … os error 1460）"，文案和提示框都正常出现 |
| 锁定远程设备 | 未做：被控端是别人的笔记本，锁屏后没有办法解锁 |
| 切显示器、"全部显示器" | 未验证：被控端只有一块屏 |
| 聊天 | 部分通过。控制端发一条，被控端 CM 的聊天里出现；被控端回复、未读数、"更多"里的未读数未验证（往被控端 CM 输入框里没法发进按键），列入试用清单 |
| 主页：收藏 | 通过。多选 › 加入收藏，轻提示"已加入收藏"，卡片带"已收藏"，"收藏"分类里有它，配置里 `fav` 写入 |
| 主页：分类、视图、详细模式 | 通过。最近 / 收藏 / 局域网切换；卡片和列表两种视图（列表有状态、名称、ID、用户@主机、标签列）；视图菜单里"简洁 / 详细"切换立即生效；排序菜单（名称、ID、用户名、在线状态）能打开，条目太少，排序结果没验 |
| 主页：多选删除、重命名 | 通过。用测试时造的记录：多选 › 删除弹"删除 1 台设备？"（取消 / 删除），确认后对应的对端配置文件被删；设备菜单 › 重命名，输入框正常（中文输入法组字可用），确定后卡片名改变。设备菜单分组"连接方式 / 设备 / 管理 / 危险操作"，条目和 05 §1.1 一致 |
| 局域网分类 | 未验证：没有同一局域网里的 Leapgate 端点。空状态"未在局域网中发现设备"正常 |
| 断线重连、错误文案 | 部分通过。经中继的会话里停掉被控端：面板"连接已被远程设备断开。"、"1 秒后重试（第 1 次）"，随后"正在连接 ‹设备名›…"；第二次失败是"无法连接服务器。请检查网络连接。"加"重试"，不再自动重试，所以"2 秒后重试（第 2 次）"造不出来（`待调.md` 第 31 条，Rust 的规则，M2b 不动）。另验：ID 不存在（"未找到 ID 为 ‹ID› 的设备。…"）、密码错误（红字"密码错误"，输入被清空，见待调） |
| 打印、语音通话、提权、Android / Wayland 对端、虚拟显示器驱动 | 未验证：没有对应环境，列入试用清单 |

**05 §4.5 V1 占用复测**。同一个被控端、同一个不停刷屏的控制台（比 M2a 时刷得快，所以绝对值不能直接和 M2a 的数字比），先后用 `3ca7230f8`（M2a）和 `9799bb9ec` 各量一遍，会话标签在前 30 秒、退到后台 30 秒（再开一个 ID 不存在的标签），控制端进程 CPU 按单核算：

| 提交 | 会话标签在前 | 会话标签在后台 |
|---|---|---|
| `3ca7230f8`（M2a） | CPU 32.7%、3D 7.1%、视频解码 6.8% | CPU 24.0%、3D 4.2%、视频解码 8.9% |
| `9799bb9ec`（M2b） | CPU 30.0%、3D 7.6%、视频解码 6.8% | CPU 22.4%、3D 3.4%、视频解码 7.9% |

工具栏、通知、聊天多了以后后台标签没有回退（后台比前台约低 8 个百分点，和 M2a 一致）。M2a 当时的数字（前台 25.7%、后台 16.8%）见上一节。

**05 §6.4 和样稿对照**：抽样，没有逐区块对。浅色真机对了 P1 设备页（本机区、导航、卡片、设备菜单分组）、P2 的连接面板（要密码、密码错误、连接失败）、工具栏和六个菜单、连接方式详情、聊天面板、通知；深色看了画廊导出的设备页、连接方式详情、聊天面板、通知（新界面主题跟随系统，没动控制端的系统主题）。没有发现必修项（版面层级、缺状态、文案、令牌用错）。没有对的：P2 的拖动和停靠、八种标签状态逐个、详细模式下工具栏、P1 的最小窗口和各主页对话框，留给试用。记进 `待调.md` 的小差异见该文件（来源"对照样稿"和"验收"）。

**05 §6.5 最新 stable 检查**：Flutter 官方 releases 页面（`storage.googleapis.com/flutter_infra_release/releases/releases_windows.json`，2026-11-01 查）最新 stable 仍是 3.47.9（2026-10-29 发布）。
1. 按 `-Ui leapgate` 编：通过。`pub get` 改了两个锁文件，检查完已还原。
2. 组件画廊：通过。两版各导出 1424 张，1022 张逐像素相同，其余每张差异像素不超过 0.02%（抗锯齿级别）。
3. 4K 上屏：通过。只用 `--connect`，没开 UI Automation 客户端；会话约 3 分钟（M2a 是 7 分钟），画面持续更新，没有崩溃事件，stderr 只有 "Using the Impeller rendering backend (OpenGLESSDF)"。
4. analyze 和测试：app 没有问题；core 97 条（92 条 info 加复制件 `file_model.dart` 的 5 条 warning，和 M2a 相同）；core 170 个、app 405 个测试通过（画廊导出那个多跑一次）。
构建 worktree 已用 3.44.9 和自编引擎编回（`app.so` 和之前逐字节相同，`libleapgate.dll` 因为重新链接哈希变了）。

**旧界面五项冒烟（`9799bb9ec` 的 Rust，旧界面）**：连接（ICE 胜出，登录成功）、`--relay`（有 `relay_server` 日志，没有 ICE 行）、TCP 端口转发（HTTP 200）、出口（socks5h 和 HTTP CONNECT 都 200，`tunnel up (direct)`）通过；文件传输未验证（没做旧界面文件传输窗口的坐标点击；这条路径 M2b 没碰，Q3 挂钩只记录连接路径）。ID 加盐：空配置目录起一次，`Generated id` 是 9 位、≥ 268435456，测完放回原配置。

**发现的问题**（都不挡试用）：
1. 隐私模式点开后的失败通知只有"失败"两个字，没有原因（01 P2 区块 E 要求写原因）。被控端有 `WindowInjection.dll` 时是否仍这样没查。已修（`0ab9b3ef0`）：缺这个 dll 时被控端回 `PrvOnFailed` 不带原因，Rust 的通知正文是 "Failed"；现在显示"无法开启隐私模式"，"Failed to turn off" 显示"无法退出隐私模式"，被控端给了原因时显示"无法切换隐私模式（原因）"（原因里看不出是开还是关）。
2. 工具栏菜单打开后，按 Esc 不关闭（投递的 Esc 和真实的 `SendKeys` 都试过；真实按键可能被会话抓去发给远程设备，没分清）；点菜单外面能关。试用时用真实键盘确认。已修（`b84f68d36`、`873d088aa`）：菜单打开时键盘焦点还在画面上，Rust 的键盘钩子照样把按键截走发给远程设备，投递的 Esc 也被画面的按键处理吃掉；现在工具栏菜单按钮打开菜单时拿走焦点（同上游 SubmenuButton），画面随之 `enterOrLeave(false)` 关掉钩子，Esc 由菜单处理；菜单开着时鼠标经过画面、窗口切出再切回都不再把焦点拿回去，点画面才拿；菜单关闭时（Esc、选了一项）鼠标如果在画面上，画面当场拿回焦点（这时不会再有"鼠标进入画面"）。
3. 语义树：菜单行只是 `Text`，没有 Invoke 模式，辅助技术不能激活；会话处在连接失败、要密码等整页面板时，顶部的标签栏不在语义树里（这时 stderr 有 "dropped semantics nodes unreachable from root 0"）。0003 的收尾项，不挡试用。
4. 删除最近记录时没有同时清掉收藏里的这个 ID（配置里 `fav` 留着已不存在的 ID）。上游行为，不改：上游单台删除（`peer_card.dart` `_removeAction`）和多选删除（`peer_tab_page.dart` `deleteSelection`）在"最近"里都只调 `mainRemovePeer`（删对端配置文件），不动收藏；"收藏"分类按对端配置列出，所以这台设备从"收藏"里也看不到了，以后再连接它、配置重建后又会出现在"收藏"里。
5. 验收过程中窗口在两次操作之间多次被最小化或换位置（同时控制端前台是别的程序），没查清是不是应用自己做的，试用时留意。

**试用清单**：拖工具栏、停靠四边、窗口窄时的"更多"和未读数；聊天的收发、未读数和语音通话（要真实麦克风）；快捷键（切标签、截图、全屏、切显示器）；被控时的遮罩（在别的机器上连进来、鼠标进主页）；多显示器和"全部显示器"；隐私模式、阻止输入（被控端提权）、锁定远程设备；局域网分类和局域网直连；打印、提权、虚拟显示器驱动；Esc 关菜单；`待调.md` 第 25、29、30、33 条是否满意。

#### M3 被控端连接管理小窗（2026-11-01，`ef182b887`）

黑盒验收，无人值守。被控端 B（4K，系统缩放 150%，新界面便携版，小窗和主窗口都在它上面）、控制端 A（新界面做聊天、权限和远程点击，旧界面做审批、文件传输、端口转发和出口，同一台机器上新旧界面不同时运行）。依据 06 §5。B 上用 `leapgate-uia.ps1` 按语义名操作小窗（窗口类 `LEAPGATE_UI_CM`；按钮、标签、对话框按钮用 `Invoke`，菜单行和旧界面小窗的按钮要真实鼠标）。含被控端画面的截图读完即删，不留证据。被控端审批方式用 `approve-mode`（`both`、`click`、`password`）逐个改。

**06 §5.1 自动测试**：通过。core `flutter analyze` 92 条 info（基线不变，全在复制件里），测试 181 个通过；app analyze 0 条，测试 503 个通过、2 个跳过。Rust：`leapgate` crate 141 个通过（含 `ipc::tests::counts_by_type_with_exits_apart`、`ipc::tests::msg_round_trips_and_cm_events_read_as_documented`）；根 crate `cargo test --lib leapgate` 11 个通过。根 crate 里 `Data::Leapgate` 两头的分发没有单独的测试，由下面的真实连接覆盖。

**06 §5.2 真实连接**

| 项 | 结果 |
|---|---|
| 审批方式"输入密码或在本机接受"（两者都可） | 通过。不带密码连入：小窗"正在请求连接本机…"，按钮"接受""接受并提升权限""拒绝"；点"接受"当场收成贴边小条。带密码连入（在被控端用新界面时）：直接连入，约 3 秒后收成小条 |
| 审批方式"在本机接受" | 通过。请求中同样三个按钮；点"拒绝"，控制端报"连接错误"，小窗隐藏（约 1.4 秒），进程约 6 秒后退出；点"接受并提升权限"当场连入 |
| 审批方式"输入密码" | 通过。不带密码连入：小窗"对方正在输入密码…"加"拒绝"，没有"接受"；控制端输入正确密码后连入，收成小条 |
| 出口会话 | 通过。出口代理 socks5h 和 HTTP CONNECT 都经出口访问成功；小窗标签"作为出口"，说明"对方正在通过本机访问网络（仅 TCP），无法查看本机屏幕。"，没有权限区和聊天；只剩这一个连接时小条写"‹名字› 正在将本机用作出口"。普通端口转发的标签写"端口转发：example.com:80" |
| 断开全部会话 | 通过。两个连接时点标题栏的关闭，弹"断开全部会话？"，"取消"后连接仍在，"断开"后全部断开、小窗进程不到 1 秒退出 |
| 权限开关 | 通过。会话中关掉"键盘和鼠标"，控制端工具栏的"输入"变成"输入. 未获得键盘和鼠标控制权限"（灰显）；再打开恢复 |
| 文件传输 | 通过。控制端（旧界面）上传一个 395.77 KB 文件、下载一个 195.31 KB 文件，小窗文件记录里是"上传到本机，已完成"和"从本机下载，已完成"，文件名、大小对，最新的在上面，被控端磁盘上文件大小一致（测完删除） |
| 聊天 | 通过。控制端发一条，被控端小窗自动展开成 700 宽的聊天侧栏，显示消息、对方名字和时间；被控端在侧栏回一条，控制端收到，读屏名是"对方，时间：内容" |
| 远程点击保护 | 通过。控制端在远程画面里（适应窗口）点被控端小窗的"断开"，连接不断开，按钮上方出现"无法远程执行此操作"（两次，截图在 `shots/remoteclick-light.png`） |
| 主窗口本机区 | 通过。远程桌面加文件传输（或出口）时"正在被远程控制（2 个会话）"；只有端口转发加出口时"2 个传入会话进行中"；"查看"在小条状态下把小窗展开提到前面 |
| 系统切深色再切回 | 通过。B 的系统应用主题改深色，主窗口和小窗背景一起变（取样 `#FFFFFF`→`#203033`，`#EAF1F1`→`#142529`），切回后复原 |
| 主窗口切详细模式 | 部分通过。小窗的间距、字号收紧（权限标签不再折行），窗口尺寸不变（700×500），06 §5.2 的"换尺寸"实际是令牌，不是窗口大小 |
| 没有来访后进程退出 | 通过。最后一个连接结束后小窗隐藏，约 6 秒后进程退出（控制端关窗：隐藏约 2 秒后再 6 秒；控制端被强杀：约 21 秒后隐藏再 6 秒） |
| 贴边小条 | 通过。一个连接（按类型的文案）和几个连接（"N 个会话进行中"加"展开"，没有"断开"）的样子对；沿屏幕上边拖动（真实鼠标）从 x=3360 移到 2707，展开再收起仍在 2707，进程退出重来回到 3360 |
| 已断开的标签 | 未验证。所有断开的路径（本地点"断开"、控制端关窗、被强杀）里，断开的标签都当场被移除，没有看到"已断开"加"关闭"的状态；01 §3.3 的"已断开"状态在实际使用里看不到 |

**06 §5.2 旧界面五项冒烟**（构建 `ef182b887` 的 Rust，A、B 都是旧界面）：连接（ICE 胜出，登录成功）、`--relay`（日志 `Relay connection`，没有 ICE 行）、文件传输（会话建起，小窗显示"传输文件"；没有再做上传下载，这条路径 M3 没碰）、TCP 端口转发（HTTP 200）、出口（socks5h 和 HTTP CONNECT 都 200）通过。旧界面小窗：在"在本机接受"下请求中点"接受"（真实鼠标）连入，通过；权限开关、聊天未验证（旧界面小窗的权限图标没有语义名，窗口最小化，聊天要按坐标输入）。ID 加盐：空配置目录起一次，`Generated id` 是 471945469（9 位、≥ 268435456），测完放回原配置。

**06 §5.3 和样稿对照**：`A-P3.html` 抽样，浅色、深色各对了请求中（输入密码）、已连接远程控制（权限区）、出口会话、聊天侧栏、文件记录、贴边小条（一个、几个）。版面层级、状态、文案、令牌颜色都对得上，唯一的差异见下面"必修"。深色看了已连接远程控制、出口、几个连接的小条，浅色看了全部（B 上切系统主题后截小窗，没有留一次性密码）。没有逐画框对的：语音来电、通话中、没有麦克风（要真实麦克风）、终端、摄像头、互换（造不出）、多个来访标签的深色。

**必修（样稿对照）**：紧凑模式（320×500）下权限开关的标签折行：B 在 150% 缩放，"文件复制粘贴"变成"文件复制粘 / 贴"、"阻止本地输入"变成"阻止本地输 / 入"，样稿里都是单行；"阻止本地输入"这一行折成两行以后，第二行的"入"贴着下面的按钮，请求中（输入密码）状态下和"对方正在输入密码…"那块几乎相碰。详细模式下不折行。出口说明那段话的断行也和样稿不同（字体宽度差异，不影响）。复现：被控端 150% 缩放，对方连入后看权限区。已修（`566da0b1e`）：窗口外框 320 含 Windows 的不可见缩放边框，150% 下客户区实测约 309，样稿的 14 号字加 8 间距放不下 6 个汉字；权限标签字号固定 13、开关和文字间距改 6，按最窄客户区 304（`kLgCmNarrowestClient`）设计，画廊和测试按 304 宽核对单行，真机待试用时再看。

**06 §5.3 最新 stable 检查**：Flutter 官方 releases（`storage.googleapis.com/flutter_infra_release/releases/releases_windows.json`，2026-11-01 查）最新 stable 仍是 3.47.9（2026-10-29 发布）。
1. 按 `-Ui leapgate` 编：在 `ef182b887` 上不通过，修好后（`6ea135d92`）通过。验收时 `bridge` 步里 build_runner 的 freezed 在 core 报 `Exception: Missing implementation of visitDotShorthandPropertyAccess`，随后卡在 `freezed on lib/leapgate/local_status.dart` 不结束（证据 `80-stable-run.txt`）。
   - 根因：core 的 build_runner 用的是 `analyzer` 7.7.1（`freezed` 2.5.8 要求 analyzer 低于 8，7.7.1 是 7.x 最后一版，不是解析漂移，3.44.9 下也是它）。3.47.9 的 `package:flutter/src/services/platform_views.dart` 里 `initUiKitView` 有一个参数默认值用了点号简写（`= .fallbackToPluginDefault`），analyzer 7.7.1 链接这个库、写 summary 时没实现这种节点，分析调度器抛异常后不再处理请求，后面的 build 步骤就一直等。source_gen 只解析带顶层注解的文件：M2b 里带顶层注解的只有 `leapgate/bridge.dart`（只引 `flutter/foundation.dart`，碰不到 services）；M3 给 `local_status.dart` 的 `IncomingSessions` 加了 `@immutable`，这个文件经 `models/platform_model.dart` 引到 `flutter/services.dart`，于是被解析、触发。去掉这一行在 3.47.9 下就通过（只用于验证，没提交）。
   - M2b 那次没撞上，是因为它的 stable 检查里 `bridge` 步判断桥接代码是新的、跳过了生成，build_runner 根本没在 3.47.9 下跑；强制生成（`-ForceBridge`）时 `61225d783` 在 3.47.9 下通过。
   - 修法：core 加 `build.yaml`，freezed 只对 `lib/generated_bridge.dart` 生成（core 里只有它用 freezed，它的依赖链不碰 `package:flutter`），以后哪个文件加了顶层注解也不会被 freezed 解析。没有改依赖版本：升 freezed 3 要改桥接生成的代码。3.44.9 下生成的 `generated_bridge.freezed.dart`、`generated_bridge.dart` 和加之前逐字节相同，3.47.9 生成的也相同；build_runner 的动作从 175 个降到 17 个。
   - 复跑（`6ea135d92`，3.47.9 强制生成桥接代码）：编出来（`leapgate.exe` `BE58E4F4…`、`app.so` `B22208B7…`，官方引擎 `30494FB0…`）。
2. 组件画廊：通过。在 `6ea135d92` 上 3.44.9 和 3.47.9 各导出 1580 张，1070 张逐像素相同，没有一张差异像素超过 1%（最大差异像素比例 0.02%，抗锯齿级别），和验收时那次一致。
3. 4K 上屏：通过。被控端 B（4K）用 `ef182b887` 的旧界面构建，控制端只用 `--connect`，没开 UI Automation 客户端；会话约 5 分钟，直连，画面持续更新（每分钟截一次，内容都不同），进程一直在（句柄稳定在约 1500），没有崩溃事件，stderr 只有 "Using the Impeller rendering backend (OpenGLESSDF)"。
4. analyze 和测试：app 没有问题；core 97 条（92 条 info 加复制件 `file_model.dart` 的 5 条 warning，和 M2a、M2b 相同）；core 181 个、app 503 个测试通过（跳过 2 个），这次用的是 3.47.9 自己生成的桥接代码。
构建 worktree 已用 3.44.9 和自编引擎编回 `6ea135d92`（强制生成桥接代码）：`app.so` 和验收构建逐字节相同，`flutter_windows.dll` 是带 0003 的 `8667024A…`；`leapgate.exe` 重新链接后和验收构建只差 PE 头和调试目录里的两处链接时间戳（6 个字节），所以哈希不同；`libleapgate.dll` 因为重新链接哈希变了。

**发现的问题**：
1. 上面"必修"的权限标签折行：已修（`566da0b1e`，见上）。
2. 最新 stable 检查第 1 步不通过：已查清并修好（`6ea135d92`，见上），四步复跑通过。
3. 被控端点"接受并提升权限"后，系统弹 UAC 确认框（secure desktop），无人在场时一直挡着被控端的真实鼠标键盘输入（`SetCursorPos` 失败），要远程结束 `consent.exe` 才恢复；UI Automation 的 `Invoke` 不受影响。不是产品问题，试用时在场的人点掉即可，写进试用说明。
4. 01 §3.3 的"已断开 + 关闭"状态实际看不到（见上表）。
5. 被控端的聊天输入框用 UI Automation 的 `Type`（`SendKeys`）能输入；控制端那边台式机的中文输入法会吃掉空格，聊天里的空格丢失，是环境问题。

**试用清单**：真实麦克风的语音通话（接听、选麦克风、挂断、没有麦克风的提示）；多显示器时小条在主显示器；拖动小条的手感；在完整小窗里移动鼠标取消自动收起；小条上"断开"的远程点击保护；权限开关全部八项和只读态（内置选项禁止改权限）；摄像头、终端会话的小窗（造不出）；互换后的"撤销交换"；多个来访标签和未读数；语音来电；旧界面小窗的权限开关和聊天；"接受并提升权限"的系统确认框；`待调.md` 里 CM 相关几条是否满意。

### 10.6 core 的结构（M1）

03 §3.3 第 1、2、4、5、6、8 条在 `core/lib/leapgate/` 落成下面几个文件，复制进来的 models 和改写的 `FfiModel` 接在这上面。

| 文件 | 放了什么 | 怎么接 |
|---|---|---|
| `session.dart` | 会话对象 `FFI`（改写档，沿用上游类名和 `sessionId`、`id`、`connType`、`closed` 这几个成员名）和 `ConnType`（从 `model.dart` 挪来，`.index` 传给 Rust，顺序不能动）；`events`、`notices`、按会话记的状态、`connToken`、`ask`、`start`、`close` | 每个会话自己的 model 字段（`imageModel`、`ffiModel`、`canvasModel` 等）照上游写成 `late final`，在构造函数里用 `WeakReference(this)` 建；`start` 里各 model 的初始化、`close` 里的清理（放在 `bind.sessionClose` 之前）、`_onMessage` 里 `Rgba`、`Cursor`、`Texture` 三种消息，照上游 `FFI.start`、`FFI.close` 补进去 |
| `session_registry.dart` | 会话注册表：一台设备一个标签，标签里每个视图一个会话；`open`、`close`、`closeDevice`；同一设备再开别的视图时用标签里已有会话的连接令牌；`singleSession` 时（手机，01 §8 Q8）开新会话前关掉已开的 | 只有它创建、启动、关闭 `FFI`；页面不再自己 `FFI(...)`、`start`、`close` |
| `app_core.dart` | 全局持有者 `AppCore`（窗口接口、注册表、全局轻提示、提问接口），全局变量 `appCore` 由 app 的 `main` 设 | 上游 `FFI` 里标着 global 的 model（`serverModel`、`abModel`、`groupModel`、`userModel`、`peerTabModel`、三个 `Peers`、CM 的 `cmFileModel`）不进会话对象，到各自的里程碑（M3、M4）加到这里 |
| `session_events.dart` | 事件按 `name` 查表分发，会话流和全局流各用一个表；没人处理的名字经 L1 写一行警告（只写流和名字，事件里可能有密码和路径），每种流每个名字一次运行只写一次 | 会话流 `ffi.events.on('<name>', handler)`，全局流 `appCore.events.on(...)`。复制进来的 model 的事件在 `FFI` 构造函数里登记，`FfiModel` 的在它自己的构造函数里登记；同一个名字只能登记一次 |
| `notices.dart` | 会话通知 `SessionNotices`（列表，后来的不冲掉前面的；同 `tag` 的原地替换，`dismissTag` 按 tag 去掉）和全局轻提示 `Toasts`（一次一条，新的替换旧的，到时自动消失） | 通知和轻提示都只带 key 和参数，文案在 app。key 用上游的翻译 key（`translate(...)` 的参数、Rust 推来的文本）。`showToast(translate(k))` 改成 `appCore.toasts.show(k)`；上游弹窗前的 `dialogManager.dismissAll()` 不再照搬；Rust 的 `cancel_msgbox` 对应 `dismissTag(evt['tag'])` |
| `prompts.dart` | 提问接口 `Prompter.ask(prompt, session:)`：带会话时只遮那个会话的标签，不带时只遮主页；关掉不答返回 null。三种提问：`OverwritePrompt`（覆盖 / 跳过 / 取消 + 全部照此）、`DeletePrompt`（删除 / 取消 + 全部照此）、`RenamePrompt`（提交时用 `check` 校验，返回新名字） | 会话里用 `ffi.ask(...)`。`file_model` 里 `showFileConfirmDialog`、`showRemoveDialog` 保留函数名和返回值，函数体改成调 `ask` 再换回上游的 `bool?` 和"全部照此"勾选；`renameAction` 改成 `RenamePrompt`，重名和非法名放进 `check`。`removeAction` 里的 `showLoading` 没有对应接口，出错的 `msgBox` 改成会话通知 |
| `app_window.dart` | 窗口接口 `AppWindow`：`getFrame`（物理像素）、`setFullscreen`、`bringToFront`；app 的 `lib/shell/app_window.dart` 用 `window_manager` 实现 | 见下面的对照 |

按设备 ID 记的共享状态（上游 `common/shared_state.dart` 按 tag `Get.put`）改成会话对象上的字段，复制件里 `XxxState.find(id).value` 改成 `parent.target!.xxx.value`（或 `ffi.xxx.value`），算在允许的差异里：`KeyboardEnabledState` → `keyboardEnabled`，`CurrentDisplayState` → `currentDisplay`，`PrivacyModeState` → `privacyMode`，`BlockInputState` → `blockInput`，`FingerprintState` → `fingerprint`，`ShowRemoteCursorState` → `showRemoteCursor`（`CursorModel.showsRemoteCursor` 的 `Get.isRegistered` 那段一起换），`RemoteCursorMovedState` → `remoteCursorMoved`。`models/desktop_render_texture.dart:158` 也读 `CurrentDisplayState`，这一行照样改，来源行后注明。其余几个不在这里：`ConnectionTypeState` 归连接状态（每个会话一份，`FfiModel` 改写时定）；`PeerStringOption`（`model.dart:780` 的 `tabLabel`）是设备选项，归会话选项；`UnreadChatCountState` 随 `chat_model` 改写；`stateGlobal.relativeMouseModeState` 按设备 ID 记，但一台设备只有一个远程桌面视图，先不动，随 `state_model` 改写再定。

上游 models 里碰窗口的地方怎么改：

| 上游 | 改成 |
|---|---|
| `WindowController.fromWindowId(kWindowId!).getFrame()`（`input_model.dart:1954`、`relative_mouse_model.dart:779`） | `appCore.window.getFrame()` |
| `WindowController.fromWindowId(windowId).setFullscreen(...)`（`state_model.dart:109`） | `appCore.window.setFullscreen(...)` |
| `windowOnTop(null)`（`model.dart:760`、`chat_model.dart:415`、`:434`、`server_model.dart:579`、`:760`） | `appCore.window.bringToFront()` |
| `rustDeskWinManager.getOtherRemoteWindowCoordsFromMain()`（`input_model.dart:1953`） | 单 engine 下没有别的会话窗口，空列表 |
| `rustDeskWinManager.call(WindowType.Main, kWindowBumpMouse, …)`（`model.dart:2673`） | 本来就在主窗口里，直接调 `RdPlatformChannel.instance.bumpMouse` |
| 按 `desktopType`、`kWindowId` 分支 | 按主窗口处理 |

接口里没有的：`windowManager.minimize`、`close`（`server_model.dart:169`、`:584`，CM 是单独的进程，M3 再定）；`model.dart:755-756` 的关闭全部窗口（URL 动作，只来自 macOS 和 Linux）；窗口标题（跟着当前标签，在 app 的外壳里设）；`chat_model.dart:319-332` 的聊天窗口大小（`chat_model` 只留消息存储）。

**复制进来的 models 和 `FfiModel`（M1 B 块）**。下面的行号都是上游 `bd9262397` 的。

- `FfiModel` 的改写在 `core/lib/leapgate/ffi_model.dart`，是 `models/model.dart` 的 `part`（它要写 `Display._scale`，上游也是同一个库）。只做非连接部分：peer info、显示器（切换、同步、跟随、分辨率）、权限、光标、剪贴板、屏蔽输入、隐私模式、指纹、会话选项同步、纹理渲染切换、便携服务、退出相对鼠标；这些事件在它的构造函数里登记。复制进来的 model 的事件（文件传输 8 个、`update_quality_status`、`record_status`）在 `FFI` 的构造函数里登记。上游 `FfiModel` 里属于"不要"的（`CachedPeerData`、`handleCachedPeerData`、`_queryAuditGuid`、结束时询问备注）、多窗口的（`tryUseAllMyDisplaysForTheRemoteSession`，:1500、:1535-1577）、手机的（`VirtualMouseMode`、`tryShowAndroidActionsOverlay`、Android 文档选择器）、终端的分支，以及界面组件（`getConnectionImageText`）都没搬。`openMonitorInTheSameTab` 搬进了 core 的 `common.dart`。
- **连接状态（M1 C 块）**：`core/lib/leapgate/connection.dart` 的 `ConnectionModel`（改写档，ChangeNotifier），每个会话一个，挂在 `FFI.connection`（`FFI` 构造函数里建，在 `FfiModel` 之后；事件按名字查表，登记顺序不影响分发）。代替上游 `handleMsgBox`（:888-976）的模态框链和重连里的弹窗（:1124）。它登记会话流的 `msgbox`、`set_multiple_windows_session`、`connection_ready`（代替上游按设备 ID 记的 `ConnectionTypeState` 和 `FfiModel` 的 `_secure`、`_direct`）、`cancel_msgbox`（→ `notices.dismissTag`）。`toast` 不登记：Rust 在 `bd9262397` 和当前代码里都不推 `toast`（`src`、`libs` 里搜不到），上游 `handleToast` 是走不到的分支；真出现时兜底日志会记下。
  - 字段（只读）：`stage`（`ConnStage`：connecting = 01 §4.1 第 1~3 阶段，insecure = 3a，verifying = 4，waitingForImage = 5，connected = 6、7，restarting = 7 的对方重启，failed = 7 的中断和 8 的结束）；`input`（verifying 时要用户做什么，`ConnInput`：none 即"正在验证"、password、twoFactor、osAccount、osAccountAndPassword、windowsSession、remoteAccept）；`reason`（`ConnReason`：`code`、`params` 来自块 2 的 `leapgateMsgboxReason`，另留 msgbox 的 `type`、`title`、`text`，`other` 时界面显示原文；failed 时一定有；密码再输时是 `wrong_password`，2FA 输错时是 `wrong_2fa`，第一次要时为 null，即 C4）；`retryCountdown`（秒，null 表示不自动重试）和 `retryAttempt`（第几次，从 1 起）；`dimLastFrame`（= restarting）；`windowsSessions`；`rememberPassword`（要密码时从 `sessionGetRemember` 读的初值）；`trustedDevicesEnabled`；`secure`、`direct`、`streamType`。
  - 给界面的方法（内部调的 bind 和顺序照上游；每个只在它回答的那个状态里起作用，`login`、`submit2fa`、`selectWindowsSession` 要求 verifying 加对应的 `input`，`continueInsecure`、`rejectInsecure` 要求 insecure，否则什么都不做，连按回车不会再发一次）：`login(osUsername, osPassword, password, remember)`（三项都先 trim，照上游 `common/widgets/dialog.dart:1000-1002`；必填项 trim 后为空时不发）、`submit2fa(code, trustThisDevice:)`、`selectWindowsSession(sid)`、`continueInsecure()`、`rejectInsecure()`（回车的默认动作，等于断开并关掉这个视图）、`retry()`、`useRelay()`（`sessionReconnect(forceRelay: true)`，Rust 写进这台设备的配置）、`cancel()`（`appCore.sessions.close`）。
  - 挂在别处的调用：`ffi_model.dart` 的 `handlePeerInfo` 开头 `connection.onPeerInfo()`（:1355）、`displays.isNotEmpty` 里 `connection.onDisplays()`（:1454-1456，重连计数、30 秒起点、重启计时复位）、`_handleUseTextureRender` 末尾 `connection.showConnectedWaitingForImage()`（:729-730）；`session.dart` 的 `onEvent2UIRgba` 开头 `connection.onImage()`（:4322-4326）、首帧分支里 `connection.onFirstImage()`（:4330-4331）、`close` 里 `closed = true` 的下一行、第一个 await 之前 `connection.clear()`（:254-264，免得关会话的往返期间倒计时或 1.5 秒计时器对它调 bind）；`handleSyncPeerInfo` 里显示器全没了时 `connection.showMsgBox('nocancel-error', 'Prompt', 'No displays', false)`（上游 :1713 的框点确定就关会话；正文用 Rust 的小写写法，C3 归 `no_displays`）。30 秒窗口用 `package:clock` 取时间，测试里 `fake_async` 能控制。
  - msgbox 分三路（`handleMsgBox` 里按这个顺序判断；开头照上游对错误类先退出相对鼠标模式）：

    | 条件 | 去向 |
    |---|---|
    | `re-input-password`、`input-password`、`terminal-admin-login(-password)`、`input-2fa`、`wait-remote-accept-nook` | 连接状态 verifying，加对应的 `input`；只有 `re-input-password` 和输错的 2FA 调 C3（标题 `2FA Required` 的第一次不调，免得白记一行没认出的空正文） |
    | `restarting` | restarting，立即 `sessionReconnect`，5 秒后再重连一次（照上游） |
    | `restarting-show` | 重连（`reconnect()` 在当前已是 restarting 时保持 restarting，否则进 connecting）；标题 "Restarting remote device" 时再进 restarting，所以 "Connecting..."（对端静默检测）在重启中仍是 restarting、不在重启中是 connecting |
    | `on-uac`、`on-foreground-elevated`、`elevation-error` | 会话通知，tag = type（Rust 按 type 发 `cancel_msgbox`）；已有 `wait-uac` 时不加 `on-uac` 一类 |
    | `wait-uac` | 去掉 `on-uac` 一类通知，加通知 `wait_accept_uac_tip`，tag `wait-uac` |
    | type 含 `insecure-connection` | insecure |
    | `relay-hint`、`relay-hint2` | failed，原因 `direct_reset`，不自动重试、不动重连计数 |
    | 正文是 `Connected, waiting for image...` | waitingForImage，起 1.5 秒唤醒计时。换渲染方式（`use_texture_render`）也走这里，但它会推给所有会话（`src/flutter_ffi.rs:1259-1273`），所以那时只有 connected 的会话进 waitingForImage，其他阶段（等密码、倒计时等）不变；计时器和 `sessionOnWaitingForImageDialogShow` 照旧 |
    | 不是错误（错误 = 标题 `Connection Error`，或 type 含 `error` 且不含 `custom`） | 会话通知：key = 正文，参数 type、title、link；tag `type-title-text-link`（上游对话框的 tag 去掉会话 ID） |
    | 其余（错误） | failed 加原因码；能否自动重试取事件的 `hasRetry`，否则看 30 秒不在线规则；能重试就按 1、2、4…秒倒计时后重连 |

  - §3.4 各条对应的回放测试（`core/test/connection_test.dart`，另两条在别的文件）：

    | §3.4 | 测试 |
    |---|---|
    | 网络中断后翻倍重连、没有上限 | `network errors retry after 1 s, doubling each time without a cap; ... (model.dart:123, :1093-1102, :1454)`、`the countdown ticks each second and "Retry" does not wait for it` |
    | 连上过的 30 秒内不在线重试 | group `"Remote desktop is offline" (model.dart:1002-1030)` 三条（第一次连不重试、连上过的重试 30 秒、`the 30 s start again once a retry got displays (model.dart:1454-1456)`） |
    | 对方重启后静默重连 | `a restarting remote device reconnects silently, last frame dimmed (model.dart:929-948)`、`a silent peer reconnects as restarting only while it restarts (io_loop.rs:335, :361)`、`a first frame ends the silent restart window (model.dart:4330)` |
    | 1.5 秒没画面发空系统密码 | group `1.5 s without a frame ... (model.dart:1201-1205)` 三条（没画面、先来画面、换渲染方式）；`a render switch reaches every session but changes only a connected one ... (model.dart:724-731, flutter_ffi.rs:1259-1273)` |
    | 不安全连接确认，回车等于断开 | group `an insecure connection waits for the user (io_loop.rs:220-222, common.dart:1186-1219)` 两条 |
    | 改用中继写进设备配置 | `"Use relay" reconnects with force relay ... (ui_session_interface.rs:1329-1336)` |
    | 能否自动重试沿用 Rust | `whether to retry by itself is hasRetry from Rust (client.rs:5192-5210)` |
    | 打开其他视图复用连接令牌 | `session_registry_test.dart` 的 `another view of an open device joins its tab with its connection token (upstream toolbar.dart:580-610)` |
    | 文件传输续传、替换确认 | `file_model_test.dart`（B 块） |

    另有 §3.7 示例序列、2FA 的 C4、等对方接受加选 Windows 会话、通知分流和 `cancel_msgbox`、取消关视图、`no displays ends the connection (model.dart:1713, ui_session_interface.rs:1845)`、`the password is trimmed, and sent once (common/widgets/dialog.dart:1000-1002)` 几条。变异检查过：去掉 `_reconnects *= 2`、`pi.isSet` 条件、`!isRefreshing`、`onDisplays` 里的 30 秒起点复位、`onFirstImage` 里的重启计时复位、密码 trim、渲染切换的阶段判断、`login` 的状态检查，各自都有测试失败。
  - 和上游不同的地方：任何状态变化都结束倒计时（上游手动重试后定时器还会再重连一次）；通知类 msgbox 不动重连计时和重连计数（上游的 else 分支会取消、重置）；隐私模式的通知不延迟 3 秒（上游怕画布刷新冲掉对话框）；等画面计时器重开前先取消（上游只覆盖引用）；`restarting-show` 标题是 Restarting 时进 restarting 面板（上游只显示 Connecting）；`wait-uac` 去掉 `on-uac` 通知（上游 `dismissAll`）；`connection_ready` 一律进 verifying，所以重启时最后一帧变暗在通道建立时就结束了，而不是第一帧到时；5 秒计时器触发的重连保持 restarting（上游显示 Connecting）；换渲染方式只在 connected 时进等画面（上游在任何状态上都叠一个等画面框）。Android 文档选择器的分支（手机阶段）和结束时询问备注（01 §5.5 已去掉）没搬。
  - 已知限制和留给后面的：01 §4.1 进度条的"查找设备""建立连接"两步 Rust 不区分（`connection_ready` 之前没有任何事件），合成 connecting 一种，要分就得在 Rust 加挂钩，暂不做；提权通知上的"请求提升权限"按钮要弹选方式的对话框，随 M2b 的工具栏做，现在通知没有动作；"已等待多久"、等画面超过几秒后加的那行说明，由页面自己计时；要密码时 `sessionGetRemember` 返回之前，如果 `wait-remote-accept-nook` 先到，返回后阶段会被打回密码框（上游也一样，修要加状态，不修）。
  - **接 V1 时要处理**（M2b 的标签切换）：第一帧到之前标签就被隐藏时，`showConnectedWaitingForImage` 起的 1.5 秒计时会误发空的系统登录密码（隐藏后 Rust 不再推帧）。接 V1 时，隐藏期间不按"没画面"处理（例如隐藏时取消计时，切回时如果仍在 `waitForFirstImage`，再起一次），具体做法 M2b 定。
- Rust 推事件走两种流：每个会话自己的流（`sessionStart`），和全局流（`startGlobalEventStream`，`PlatformFFI.init` 里开始收）。全局流的事件先给 `PlatformFFI.tryHandle`，没人认领的交给 `setEventCallback` 设的回调（`models/native_model.dart:274-277`）。新界面的回调是 `AppCore.events`（`SessionEvents(stream: 'global')`），在 `AppCore` 的构造函数里设；app 的 `main` 先建 `AppCore` 再调 `platformFFI.init`，所以一开始的事件也不会丢。两种流没人处理的名字都按"每种流每个名字一次"写日志，日志里写明是哪种流。
- 会话流上没登记、等各自的块或要主会话定的：`screenshot`（:468，:484-550，"另存为"要选文件的对话框）、`printer_request`（:466，:552-722，要选打印机的提问）、`switch_back`（:407-410）；聊天和语音的 6 个（`chat_client_mode`、`chat_server_mode`、`on_voice_call_*`，:362-367、:416-428）随 M2b（`chat_model` 改写）；`terminal_response`（第三轮）；`selected_files`、`send_emptry_dirs` 只在 Web 上有。
- 全局流上没登记的：CM 的 `add_connection`、`on_client_remove`、`show_elevation`、`update_voice_call_state`、`cm_file_transfer_log`（`src/flutter.rs:1534-1596`）在 M3，`sync_peer_hash_password_to_personal_ab`（`src/client.rs:3742`）在 M4，都登记在 `appCore.events` 上，不登记在会话的表上；`on_url_scheme_received`（`src/server.rs:776`，只来自 macOS 和 Linux）。
- M2a 的会话页要做的：`canvasModel.initializeEdgeScrollFallback(this)`（`desktop/pages/remote_page.dart:179`，要页面的 TickerProvider）。会话 model 的其余初始化已在 `FFI.start` 里：首帧时 `activateLocalCursor`（只远程桌面）和录制状态（`remote_page.dart:160-165`、`view_camera_page.dart:105-110`），`checkShowQualityMonitor`（`remote_page.dart:198`）。
- **M1 暂删、M2b 已照上游原样补回**（`shortcut_model` 复制进 core 时，见 10.9 会话·工具栏）：`models/input_model.dart:426` 本地快捷键分发器里的 `ffi.shortcutModel.onTriggered(action)`；同文件 `_matchFlutterShortcut` 的匹配部分（:1212-1236，读 `ShortcutModel.config`；`shortcut_utils.dart` 一并复制）；`model.dart:473-477` 的 `kShortcutEventName` 事件在 `leapgate/session.dart` 登记；会话关闭时照上游 `model.dart:4397` 调 `shortcutModel.clear()`。
- `cm_file_model.dart` 推迟到 M3，和 `server_model` 一起复制（它读 `serverModel.clients`、`tabController` 和 `chatModel`）。`ElevationModel` 留在 `model.dart` 里（peer info 和便携服务事件要用）。`QualityMonitorModel.webrtcTransport` 只在 Web 上有值、读 `CachedPeerData`，删了。
- 复制件里的提示：`msgBox` 改成会话通知，key 用 msgbox 的正文（`file_model` 的单向传输错误是翻译 key `one-way-file-transfer-tip`，删除时的出错是原始错误文本）；`JobState.display`、`JobProgress.display` 这类返回界面文字的仍调 core 的 `translate`（经 Rust 翻译），没改。
- `FFI.close` 除了上游 `FFI.close` 的清理，还做了上游页面在关会话前做的 model 清理：文件视图的 `FileModel.close`（`file_manager_page.dart:125`），远程桌面的纹理、图像、光标图（`remote_page.dart:676`、`:684-685`）。纹理在 `start` 里建，跟会话走，不跟页面走。页面自己的（`enterOrLeave`、`hostStopSystemKeyPropagate`、键盘焦点）归 M2a 的会话页。
- `StateGlobal`（`models/state_model.dart`，改写档）只留复制件和 `FfiModel` 用到的：`fullscreen`；`setFullscreen`（经 `appCore.window.setFullscreen`）M1 里没有调用方，留着给 M2a 的全屏；`windowBorderWidth`、`tabBarHeight`、`relativeMouseModeState`、`getInputSource`。工具栏分辨率菜单记的上次选择（`_lastResolutionGroupValues` 和它的三个方法）M2b 已随工具栏补回，`leapgate/ffi_model.dart` 的 `handlePeerInfo` 照上游 :1487 在每次 peer info 后清它。`relativeMouseModeState` 照上游按设备 ID 记：一台设备只有一个远程桌面视图，不会互相覆盖。`tabBarHeight` 照上游是 28（全屏时 0），`CanvasModel` 拿它算画面可用的高度；M2a 的会话页上方占的高度不同时改这里。`consts.dart` 的 `kDragToResizeAreaPadding` 恒为 0（上游只在 Linux 上留改大小的边）。
- core 的 `flutter analyze` 用 `--no-fatal-infos` 跑。M1 B 块后的基线是 92 条 info，全是复制件从上游原件带来的（同一份原件在同样规则下也报，主要是 `RawKeyEvent` 和 `window` 的废弃提示），只看新增的。

### 10.7 选项 model（M1）

代码在 `leapgate_ui/core/lib/leapgate/options.dart`（03 §3.3 第 7 条、§3.6）。页面读写选项只经它，不直接调 `bind.*`。core 里的复制件和改写档（`FfiModel`、`ConnectionModel` 等）照上游直接用 bind 读选项，只有页面经 `OptionsModel`、`SessionOptions`。

- **`OptionsModel`**：全应用一份，由 `AppCore` 持有（通知只在同一个实例里传）。
  - `config`：Config，`bind.mainGetOptionSync` / `mainSetOption`。安装版由服务进程保管，界面读的是 Rust 经 IPC 刷新的副本，写入经 IPC 交给服务。
  - `local`：LocalConfig，`bind.mainGetLocalOption` / `mainSetLocalOption`。
  - `peer(id)`：一台远程设备的选项，`bind.mainGetPeerOptionSync` / `mainSetPeerOption`；同一个 ID 每次拿到同一个对象。这台设备有会话开着时改走会话选项：会话读的是 Rust 自己内存里的副本，看不到这里写的值。
  - `isFixed(key)`：`bind.mainIsOptionFixed`。Leapgate 里恒为假（02 R2-Q4），设置页照样保留只读样式。
  - `isInstalled`：`bind.mainIsInstalled`，安装版还是便携版（M2a 关窗时的确认按它分，01 Q6）。
- 三种作用域是同一个 `OptionScope`：`get` / `set`（字符串，空串表示没设，写空串删除这个键）、`getBool` / `setBool`、`listenable(key)`。
- **`SessionOptions(sessionId)`**：一个会话的选项，只依赖会话 ID，由会话对象持有。`get` / `set` 是 `bind.sessionGetOption` / `sessionPeerOption`（会话内存里的设备选项，写入时存回设备文件；会话已关时 `get` 返回 null）；`getToggle` / `toggle` 是 `bind.sessionGetToggleOptionSync` / `sessionToggleOption`。开关选项只有 "Y" 和空两种值，不用 `option2bool`（上游 `common.dart:1676-1678`）。
- **布尔语义**：`option2bool` 照抄上游（`enable-` 开头和其他键空值为真；`allow-` 开头、`stop-service`、`direct-server`、`force-always-relay` 只认 "Y"）。`bool2option` 一律写 'Y' / 'N'：上游在 `isCustomClient` 为真时就是这样，而 Leapgate 的应用名不是 RustDesk，`isCustomClient` 恒为真，所以和旧界面写进配置的值相同。只认 "Y" 但不在上面名单里的键（例如 `leapgate-allow-exit`，空值按 `option2bool` 会算成真）用 `get(key) == 'Y'`，不用 `getBool`。
- **写入的返回值**：`set`、`setBool`、`toggle` 返回是否保存成功。S9（03 §6.1）到位之前 Rust 不报结果，桥调用返回就算成功、恒为真；桥抛的异常照常往上抛（由 M0 的全局错误处理写进日志），不吞。S9 到位后改成 Rust 给的真值，接口不变。
- **变更通知**：`listenable(key)` 在经同一个对象写这个键之后触发（值没变也触发），监听方自己重新读。别处改的值不通知：服务进程、服务端策略（心跳策略直接改 Config）、上游界面。需要跟上这类变化的页面在显示时重新读。
- **接入办法**（每块开工的第一步）：
  1. 列出这一块页面要用的上游 `bind.*` 选项调用，对照两份说明去掉已经不做的功能。
  2. 选项键用常量，不在页面里写字面值：上游有的照上游名字和值补进 core 的 `consts.dart`（以后复制进来的 models 直接能用），Leapgate 新加的键放在用它的 core 文件里。
  3. 普通读写直接用 `config` / `local` / `peer(id)` / `SessionOptions`；有特殊读写规则的（例如上游 `main_set_option` 对 `stop-service` 会去装卸服务、`leapgate-allow-exit` 只认 "Y"）在 core 里包一个具名方法，页面调方法。
  4. 选项以外的 `bind.*`（例如画质 `sessionGetImageQuality`、Flutter 选项 `sessionGetFlutterOption`）按领域收进对应的 model，不往 `OptionsModel` 里堆；作用域本身不够用时（例如 LocalConfig 的 `ui_flutter`）再加一个 `OptionScope` 子类。

### 10.8 M2a 的分工约定

依据：总仓库 `docs/新界面/04-M2a拆法.md`（下称"04"；维护者 2026-10-31 定了 D1~D5：V1、全屏、"重启远程设备"提前进 M2a，连接进度合成两步）。界面行为以 01 为准（P1 区块 A、E、F，P2 区块 A~E、G，§2.1、§4.1、§4.3、§4.4、§4.5、§7.6），样稿 `A-P1.html`、`A-P2.html`，令牌和图标以 `A-基础.html` 为准。04 §7 列的不做。

**分支和文件边界**（都从 `ui/m2a` 切，做完合回 `ui/m2a`）

| 分支 | 谁 | 只改这些 |
|---|---|---|
| `ui/m2a-ds` | designer | `app/lib/widgets/`（新组件；M0 组件缺什么补什么）、`app/lib/gallery_main.dart`、`app/test/` 里组件的测试 |
| `ui/m2a-session` | coder A | `app/lib/shell/`、`app/lib/pages/session/`、`app/lib/main.dart`、core 的 `leapgate/session.dart`、`leapgate/session_registry.dart`、`models/state_model.dart` 和它们的测试；`app/windows/` 只在链接和窗口前台确实需要时改 |
| `ui/m2a-home` | coder B | `app/lib/pages/home/`、core 的新文件（"输入像不像地址"的判断等）、`leapgate/local_status.dart`、`leapgate/app_core.dart`（只加最近列表的 model）和它们的测试 |

- 两个 coder 都要往 `app/lib/l10n/app_zh.arb`、`app_en.arb` 加键：会话块的键以 `session`、`conn`、`toolbar`、`closing` 开头，主页块以 `home`、`connectBox`、`recent` 开头，各自加在文件末尾，冲突在整合时解决。两种语言同时加，文案照 01 §7.6 和术语表；01 里写好的句子逐字照抄，没写的按 §7.6 写，并在提交说明里列出新写的句子。
- 两个 coder 先用 M0 的组件和简单的占位控件把逻辑写通，整合时换成 designer 的组件。占位控件不求好看，但行为测试要能按文字和语义标签找到它们。
- 外壳和主页的两条约定（2026-10-31 审查主页块时补）：外壳把非当前标签（包括被会话标签盖住的主页）包在 `TickerMode(enabled: false)` 里，主页靠它停掉在线状态查询（`IndexedStack`、`Offstage`、`Visibility.maintain` 都不关 ticker）；主页切走时不销毁。全局轻提示的 key 是上游翻译 key（例如 `Copied`），文案在 ARB 里，由外壳显示。
- 本机区 ID 旁的"复制"和双击 ID 复制（01 区块 A）M0 没做，归主页块。
- 共用接口 `app/lib/shell/navigation.dart`（`ui/m2a` 上已有）：`mainNavigation.connect(id, …)` 开会话或切到已有标签；`mainNavigation.showHome(focusConnectBox:, connectBoxText:)` 回主页；主页监听 `connectBoxFocusRequests`。会话块实现，主页块只调用，测试里换成假的。

**组件约定（designer）**

- 组件只管画：输入是普通的值和回调，不引用 core 的 model、会话对象和 `bind`（身份色这类纯函数可以用）；文字全部由调用方传进来（照 M0 `LgTitleBarLabels` 的做法），组件里不写死文案、不读 `AppLocalizations`。
- 每个可操作的地方带语义标签：`Semantics` 的 label 用它显示的文字，只有图标的用它的名字。讲述人和端到端的 UI Automation 脚本都靠它找控件（04 §6.3）。
- 浅色、深色和简洁、详细两套尺寸都对；尺寸、颜色、间距、圆角只用令牌。
- 每个组件的每种状态在画廊（`buildSpecimens`）里有一项，能用 `LG_GALLERY_EXPORT` 导出和样稿对照；`app/test/` 里写行为测试（回调被调、禁用时不响应、焦点能到），不比像素。
- 要做的组件（名字是建议，可以按 M0 的命名习惯改，接口的意思不变）：

| 组件 | 数据和回调 | 样稿 |
|---|---|---|
| `LgDeviceAvatar` | 设备 ID（取身份色）、平台（Windows、macOS、Linux、Android、未知）、尺寸 | 设备卡片和列表视图的平台图标 |
| `LgDeviceRow` | 名称、格式化的 ID、`用户名@主机名`、平台、在线状态（在线、离线、正在查询，带文字）、可选的来源分类文字；选中、高亮（连接框里键盘移到的那一行）；`onTap`、`onDoubleTap`、`onConnect`（悬停时出现的"连接"）、`focusNode`；"连接"按钮的文字 | `p1-list-simple`、`p1-card-*`、`p1-cb-*` |
| `LgConnectToRow` | 整行文字（"连接到 ‹输入›"，调用方拼好）、高亮、`onTap`；行尾的"⋯"（连接方式菜单）随 M2b，先不放 | `p1-cb-conn`、`p1-cb-none` |
| 连接框 | 输入框用 M0 的 `LgTextField`；问号按钮和说明弹层（文字由调用方传）；"连接"带下拉的按钮（菜单项由调用方传，用 M0 的 `LgMenuItem`；禁用态） | `p1-cb-empty`、`p1-cb-help`、`p1-cb-menu` |
| 空、加载中、搜索无结果 | 文字；加载中的骨架行 | `p1-cb-none`、`p1-st-empty-recent`、`p1-st-loading` |
| `LgPasswordRow` | 标签、内容、可选的小字说明、内容是否灰显（"已设置""不可用"这类）、`onCopy`（null 时不显示"复制"）；留一个可选的操作区给 M2b 的"刷新""修改" | `p1-ben-*` |
| `LgConnectionPanel` | 标题（设备名）、副标题（ID）；可选的进度（两步，每步待做、进行中、完成）；语气（普通、警告、错误）；主文字、次要文字（已等待时间、等画面的说明、"‹n› 秒后重试（第 ‹k› 次）"等，调用方拼好）；是否转圈；输入区（调用方传控件列表）；按钮（文字、主次、`onPressed`；回车的默认动作由调用方用 `isDefault` 显式标记，没标就没有，只在焦点位于输入框里时执行，没有输入框时默认按钮自带焦点。M2a 只标五处：不安全连接的"断开"、密码面板的"连接"、验证码的"验证"、Windows 用户会话的"连接"、确认框的主按钮；出错面板不标，免得断线时一个回车就"改用中继"）。面板和确认框把 Tab 焦点限制在卡片内。"对方重启中"时面板盖在变暗的最后一帧上，变暗由调用方给开关 | `c-*`、`e-*`、`c-reboot` |
| 面板用的输入件 | 密码框带"显示明文"切换（可以在 `LgTextField` 尾部加按钮）；验证码框（输满 6 位回调一次 `onCompleted`）；下拉选择（Windows 用户会话，选项是文字）；勾选用 M0 的 `LgCheckbox` | `c-pwd`、`c-2fa*`、`c-winuser` |
| `LgSessionToolbar` | 按钮列表（调用方传）；是否固定、`onTogglePin`；是否收起、`onExpand`；收起后的拖动条：连接方式小点（直连、经中继，未加密加警告）、"展开"、"全屏 / 退出全屏"；全屏时最左的设备名（带身份色上沿）和拖动条上的"最小化"。拖动换位置和停靠不做 | `s-default`、`s-collapsed*`、`x-full` |
| 工具栏按钮、菜单按钮 | 图标、文字（简洁模式菜单按钮只写文字，详细模式图标加文字，01 §2.3）、`onPressed` 或菜单项列表、展开时的选中态、禁用态和悬停说明；分隔 | `s-menu-view`、`m-display`、`m-action` |
| `LgNoticeStack` | 通知列表（文字、语气、按钮、能否关闭）、`onDismiss`；最多显示 3 条，后来的排在下面，再多的排队；自动消失的计时归调用方 | `u-toasts` |
| `LgToast` | 文字；窗口一级的位置和进出 | `A-P6-设置.html` 里的轻提示 |
| `LgConfirmDialog`、页内确认条 | 标题（问句）、正文、附加控件（"不再提示""记住此选择"勾选，Q6 的两个单选和单选下面的说明）、按钮（文字、主次、危险）；遮罩颜色和卡片。遮罩只盖调用方给的那一块，挂在哪由会话块的作用域浮层决定 | `p1-close-sessions`、`p1-close-exit`、`g-close` |
| 会话标签的状态 | M0 `LgSessionTab.status` 放得下的不新做；按 `tabs-s` 补齐连接中（转圈加"正在连接…"）、已中断、连接失败、已断开变灰，和悬停提示的内容块 | `tabs-s`、`tabs-tip` |

**会话块（coder A）**

- 输入和焦点照 04 §4 的七条。上游依据：`flutter/lib/desktop/pages/remote_page.dart` 的 `_windowsCanFocusRemoteInput`、`enterView`、`leaveView`、`onWindowBlur`、`onWindowFocus`、`RawKeyFocusScope` 的 `onFocusChange`、`dispose`；`hostStopSystemKeyPropagate` 在画面的 `MouseRegion` 进出时切换。macOS、Linux 专用的分支不搬（第一阶段只做 Windows）。
- 从上游复制、按改写档登记（04 §2.5）：`ImagePaint`、`CursorPaint`、`_ViewStyleUpdater`（`flutter/lib/desktop/pages/remote_page.dart`）放 `app/lib/pages/session/image_paint.dart`；`RawKeyFocusScope`、`RawPointerMouseRegion`（`flutter/lib/common/widgets/remote_input.dart`）放 `app/lib/pages/session/remote_input.dart`。来源行写 `// 上游：<路径>@bd9262397（改写：只留 <类名>；…）`，写明删了什么、改了什么（按设备 ID 的共享状态改成会话字段、`Get.find` 改成参数等）。合并上游时这两个上游文件按改写档人工核对（03 §3.8 第 2 条）。
- core：`FFI.start`、`SessionRegistry.open` 加 `password`、`isSharedPassword`、`switchUuid` 参数（04 §2.4），注册表测试跟着补；`StateGlobal.tabBarHeight` 改成新顶栏的高度、全屏时 0；会话页开始时调 `canvasModel.initializeEdgeScrollFallback(this)`、会话开始后读"显示远程光标"的初值（10.6 末尾几条）。
- 外壳：标签列表跟 `appCore.sessions`；每个标签的内容区一个 `Overlay`，会话里的确认框和面板只挡这个标签（03 §4.5）；`appCore.prompter` 在这里实现（带会话的只遮那个标签，不带的只遮主页），M2a 还没有提问的来源，结构先做好；窗口标题"Leapgate"或"‹设备名› - Leapgate"；"+" 调 `showHome(focusConnectBox: true)`；`MainNavigation` 的实现：`connect` 照上游 `flutter/lib/common.dart:2572` 的 `connect`（去空格，`bind.mainHandleRelayId` 去掉 `/r` 并转成强制中继），标签按处理后的 ID 记。
- 连接状态面板：`ConnectionModel` 的 `stage`、`input`、`reason`、`retryCountdown`、`retryAttempt`、`dimLastFrame` 映射到面板（01 P2 区块 D 的表；进度两步"建立连接 → 验证身份"，connecting 时第 1 步进行中，verifying 起第 1 步完成）；按钮调 `login`、`submit2fa`、`selectWindowsSession`、`continueInsecure`、`rejectInsecure`、`retry`、`useRelay`、`cancel`。原因码到文案和下一步按钮的表照 01 §4.3（10.4 C3 表的"对应"一列），`other` 显示 `reason.text`；"修改 ID"调 `showHome(connectBoxText: id)`；"打开网络设置"在 M2a 不显示；"已等待时间"、等画面几秒后加的说明由页面计时。
- 工具栏：04 §1.1 那一行，加 D3 全屏（`appCore.window.setFullscreen`，全屏时顶栏隐藏）和 D4"重启远程设备"（确认框文案在 01 §4.4，确认后调 `bind.sessionRestartRemoteDevice`，照上游 `common/widgets/dialog.dart:1403-1431` 的出现条件）；不固定时鼠标进入画面 5 秒后收起（上游 `remote_toolbar.dart:648-676`）；画质三档、显示器切换照上游的导出；位置固定在顶部居中。
- V1（D2）：标签切走时 `lgBind.leapgateSessionSetVisible(..., false)`，切回时设回 `true` 再 `bind.sessionRefresh`；第一帧到之前就被切走时取消 1.5 秒唤醒计时，切回时仍在等第一帧再起一次（10.4 V1、10.6"接 V1 时要处理"）。先在不接 V1 的提交上把会话页做完（验收要在它上面量一次占用基线），V1 单独一个提交。
- 会话通知横条接 `ffi.notices`，轻提示接 `appCore.toasts`。通知的 key 是上游的英文原文或翻译 key：01 P2 区块 E 有文案的照它，没有的显示原文，每个 key 只写一次日志。第一次连上时轻提示"已建立直连"或"已建立中继连接"。
- 关闭：标签"×"、工具栏"断开"关这个标签（M2a 一个标签只有一个视图）。关窗：有会话时确认"断开全部 ‹N› 个会话并关闭窗口？"带"不再提示"（选项 `enable-confirm-closing-tabs`，上游 `flutter/lib/consts.dart:170`）；便携版（`appCore.options.isInstalled` 为假）把 Q6 的"退出 Leapgate / 在后台运行"和"记住此选择"合进同一个确认，没有会话时只问 Q6，记住的选择是新的 LocalConfig 键（`leapgate-` 开头，放在用它的文件里，10.7 接入办法第 2 条）；安装版隐藏到托盘。"在后台运行"隐藏窗口，进程照常当被控端，再次启动程序把窗口找回来（W1）。
- 链接：`uni_links` 收到的 `--connect` 和 `leapgate://` 链接（M0 只写日志）解析出 ID、密码、是否中继，调 `mainNavigation.connect` 并把窗口提到前面；进程自己启动时命令行里带的链接同样处理（10.5 M0"发现的问题"第二条）。解析照上游 `flutter/lib/common.dart:2207-2256` 的 `handleUriLink`，只做新建远程桌面连接这一种，其余动作写一行日志。

**主页块（coder B）**

- 本机区密码行：01 P1 区块 A 表的五种。数据（一次性密码、审批方式 `approve-mode`、密码方式 `verification-method`、服务是否停止）加在 `LocalStatusModel` 上，照上游 `flutter/lib/models/server_model.dart` 的读法；"复制"后轻提示"已复制"。"刷新""修改"随 M2b。
- 连接框：01 P1 区块 E、Q2。"输入像不像地址"写成 core 里的纯函数加单测（纯数字 ID、IPv4、IPv6、`域名:端口`、带 `@服务器`、带 `/r`）；回车规则、上下键、Esc；匹配 ID、别名、主机名、用户名、备注，M2a 的结果只来自"最近"；输入为空时"连接"禁用；下拉只有"远程桌面""经中继连接"（后者下面那行说明照 01）；问号说明照上游 `id_input_tip` 按 §7.6 重写。
- 最近列表：`Peers(name: 'recent', loadEvent: 'load_recent_peers', …)`（复制件 `models/peer_model.dart`）由 `AppCore` 持有一份，`bind.mainLoadRecentPeers` 触发加载；在线状态照上游 `flutter/lib/common/widgets/peers_view.dart:313-346`：只查看得见的行、每 6 秒一次、窗口失焦就停；名称取别名、主机名、格式化的 ID 中第一个有的；单击选中，双击或回车连接，悬停出现"连接"；空状态和加载中。连接一律调 `mainNavigation.connect`。

**测试和合入**

- core 的新代码有单测；app 每个页面状态一个行为测试（03 §8.3）：面板的每一种（用假的连接状态）、最近列表空和加载中、连接框几种默认高亮、关窗确认的几种组合（有无会话 × 便携或安装 × 是否勾过不再提示）。
- 合入前：`git diff main -- flutter/` 为空；core 的 `flutter analyze --no-fatal-infos` 不超出 92 条基线，app 0 条；复制件不跑格式化（10.1）。
- 审查重点：会话块看焦点和按键释放、钩子开关的先后、关闭流程、注册表参数、复制件和上游原件的差异；主页块看回车规则和匹配；组件看样稿对照的必修项（03 §8.4）。

### 10.9 M2b 的分工约定

依据：总仓库 `docs/新界面/05-M2b拆法.md`（下称"05"；维护者 2026-10-31 四条全部按推荐定）。界面行为以 01 为准（P1 区块 A~C、E、F、J、K，P2 区块 A~C、E、F，§2.1、§2.3、§4.2、§4.4），界面模式和工具栏、显示器的几项设置看 02；样稿 `A-P1.html`、`A-P2.html`，令牌和图标以 `A-基础.html` 为准，画框名见 05 §2.2。05 §1.3 列的项等对应的块做完再加，§7 列的不做。

**分支和文件边界**（都从 `ui/m2b` 切，做完合回 `ui/m2b`；`ui/m2b` 上已有下面"挂载点"的骨架）

| 分支 | 谁 | 只改这些 |
|---|---|---|
| `ui/rust-q3` | coder R | Q3、本机显示名两个块 2 导出和 `src/client.rs` 的挂钩（10.4） |
| `ui/m2b-ds` | designer | `app/lib/widgets/`、`app/lib/gallery_main.dart`、`app/test/` 里组件的测试 |
| `ui/m2b-toolbar` | coder A（会话·工具栏） | `app/lib/pages/session/session_toolbar.dart`、新目录 `app/lib/pages/session/toolbar/`、`canvas_hints.dart`、`app/lib/shell/tab_shortcuts.dart`；core 新复制的 `models/shortcut_model.dart`、`models/input_model.dart` 里 10.6 暂删的几处、`models/state_model.dart`；它们的测试 |
| `ui/m2b-session` | coder B（会话·其余） | `app/lib/pages/session/` 下的 `route_details.dart`、`quality_overlay.dart`、`recording.dart`、`chat/`、`session_notices.dart`、`connection_panel.dart`，`app/lib/shell/tab_menu.dart`；core 改写的 `models/chat_model.dart` 和新文件（延迟统计等）；`app/pubspec.yaml` 和锁文件（只加 `file_picker`）；它们的测试 |
| `ui/m2b-home` | coder C（主页） | `app/lib/pages/home/`；`app/lib/main.dart` 里界面模式接到主题的那几行；`app/lib/theme/` 里按选项切 `LgMode` 要的（不改令牌值）；core 的 `leapgate/local_status.dart`、`leapgate/app_core.dart`（只加分类的 `Peers`）、`leapgate/recent_peers.dart` 和新文件；它们的测试 |

- A、B 都可能要改 core 的 `leapgate/session.dart`：A 加 `shortcutModel` 和 `kShortcutEventName` 的登记，B 加聊天 model 和 6 个聊天语音事件、`screenshot`、`printer_request`、`switch_back` 的登记。只在字段表和构造函数里追加，整合时合并相邻行。其余文件不越界；确实要改别人的文件时写进汇报，由主会话协调。
- ARB 的键按前缀分：A 用 `toolbar`、`menu`、`shortcut`；B 用 `route`、`notice`、`chat`、`record`、`tabMenu`、`conn`；C 用 `home`、`peers`、`peerMenu`、`pwd`、`uiMode`。加在文件末尾，中英文同时加，文案照 01 §7.6：01 里写好的句子逐字照抄，没写的按 §7.6 写，并在提交说明里列出新写的句子。已有的键能用就用。
- 三个 coder 先用 M0、M2a 的组件和简单的占位控件把逻辑写通，整合时换成 designer 的组件。占位控件不求好看，但行为测试要能按文字和语义标签找到它们。

**挂载点**（`ui/m2b` 上的骨架提交，行为和 M2a 相同）

| 文件 | 现在的内容 | 谁填 |
|---|---|---|
| `pages/session/route_details.dart` | `sessionRouteMark(context, ffi, overlays)`：工具栏上的连接方式标记，连接就绪前是 null；现在是 M2a 的标记加悬停说明，要改成能点开详情（01 §4.2） | B |
| `pages/session/chat/chat.dart` | `chatToolbarButtons(context, ffi, overlays)`（现在是空表）、`ChatLayer`（会话页里通知之上的一层，现在不画东西） | B |
| `pages/session/recording.dart` | `recordButton(context, ffi)`，现在是 null | B |
| `pages/session/quality_overlay.dart` | `QualityOverlay`，画面之上第一层 | B |
| `pages/session/canvas_hints.dart` | `CanvasHints`：相对鼠标模式的提示、Android 导航浮条，在质量数据浮层之上 | A |
| `shell/tab_menu.dart` | `tabUnread(view)`、`showSessionTabMenu(context, device, position)`；主窗口已经接到标签的未读数和右键 | B |
| `shell/tab_shortcuts.dart` | `TabShortcuts(onNext:, onPrevious:, child:)` 包着整个主窗口；切到下一个 / 上一个标签的逻辑（主页算第一个，首尾循环）在主窗口的 `_selectBy` 里已经写好 | A |

- 工具栏里的顺序已经放好：A 现有和要加的菜单（视图、显示器、画面、输入、操作、会话）之后，是 `chatToolbarButtons` 和 `recordButton` 一组，然后 `sessionRouteMark`，最后"断开"。"更多"按"录制、聊天、会话"的顺序收（01 P2 区块 B），A 按这一组的位置判断，B 的函数不用另外返回什么。
- 会话页的层（从下往上）：画面 → `QualityOverlay` → `CanvasHints` → 工具栏 → 通知 → `ChatLayer` → 连接状态面板。每层都是 `Positioned.fill`，自己定位；没画东西的地方要让鼠标事件落到画面上，所以层里不铺满底色、不加整块的手势监听。菜单和详情弹层用现有的菜单浮层或这个标签的 `TabOverlays`。

**组件（designer）**：规则同 10.8"组件约定"（只管画、文字由调用方传、带语义标签、两套主题和两套尺寸、画廊里每种状态一项、有行为测试）。要做的组件和样稿画框见 05 §2.2。接口补充：

- 设备卡片 `LgDeviceCard` 和列表视图 `LgDeviceTable`：数据同 `LgDeviceRow`，另有星标、来源分类、选中、多选时的勾选、`onMore`（"⋯"）；表格的列、可排序的列和当前排序由调用方给。卡片网格每列至少 300 宽（01 区块 F）。
- 菜单：在 `LgMenuItem`、`LgMenuGroup` 上补滑块项（标签、值、范围、步长、显示值的格式化、`onChanged`）、步进器项、右侧的快捷键文字、灰显项的悬停说明、危险项、组标题旁的说明（例如"此地址簿为只读"）。
- 工具栏：`LgSessionToolbar` 加沿边拖动（回调给出新位置，0~1 的相对值）、停靠的边（上下左右）、左右两边竖排只显示图标、拖动时的落点预览、"更多"（调用方给出可以收进去的项和顺序，组件按宽度决定收几个）、显示器平铺按钮、收起后拖动条上的切屏按钮。位置记忆和吸附规则由 A 算，组件只画。
- 连接方式详情 `LgRouteDetails`：分组的键值行、可复制的值（指纹）、延迟表（每行名字、当前值、最低、平均、最高）、折线 `LgSparkline`（多条线，颜色加线型，图例文字由调用方传）、开关行。
- 聊天面板 `LgChatPanel`：消息列表（自己 / 对方、时间、文字）、输入框、发送、关闭、拖动。语音通话的几种状态不在面板里，画在工具栏的聊天按钮和它的菜单上（2026-11-01 按实现回写）。
- 通知：`LgNoticeStack` 加按钮组、勾选（"记住此选择"）、一直保留直到处理。
- 对话框：设置固定密码 `LgPasswordDialog`（两个输入框、强度条、规则逐条通过、错误、按钮）；其他小对话框用 `LgConfirmDialog` 加输入件拼，不另做。
- 本机提示卡、被控时的遮罩、多选条、分类分段、列表工具条。
- 详细模式：组件已经支持两套尺寸；`LgRouteMark` 详细模式下的路径标记画法、工具栏菜单按钮的"图标加文字"按 `LgTokens.of(context).mode` 切换，不另加参数（01 §2.3）。

**会话·工具栏（coder A）**

- 菜单：05 §1.1 会话页表的"显示器""画面""输入""操作""会话"五行和"灰显和快捷键"一行。每项的出现条件和动作照上游 `flutter/lib/common/widgets/toolbar.dart`、`flutter/lib/desktop/widgets/remote_toolbar.dart`（01 P2 区块 B 有行号），分组照 01 的表，不搬上游的菜单结构；权限不够、仅查看模式时灰显并给说明（01 的文案），隐私模式和录制两处例外照上游。菜单文件放 `pages/session/toolbar/`，文件头注明对应的上游出处。
- 菜单打开的小对话框（自定义分辨率、键盘布局 ANSI / ISO、系统登录密码、请求提升权限的方式、交换控制方向确认、Wayland 授权确认、添加备注）也放 `pages/session/toolbar/`，挂在这个标签的 `TabOverlays` 上。"请求提升权限的方式"做成能从外面调的函数，B 的提权通知按钮也调它。
- 工具栏拖动和停靠、"更多"；显示器的三种形态（读 `show_monitors_toolbar` 等现有选项，01 P2 区块 B）和"全部显示器"（`kAllDisplayValue`，同一个标签里合并显示）。
- 快捷键：把 `flutter/lib/models/shortcut_model.dart` 复制进 core（只删界面调用），补回 10.6"暂删、`shortcut_model` 改写时补回"的几处；菜单项右侧显示绑定的组合键（默认绑定见 01 P2 区块 B）；`TabShortcuts` 实现切标签，按键照上游 `shortcut_model` 的切标签动作。
- `StateGlobal` 补回分辨率菜单记的上次选择（10.6 末尾）。
- `CanvasHints`：相对鼠标模式的提示（这时工具栏隐藏，上游 `remote_page.dart:782-792`）、Android 导航浮条。
- `待调.md` 第 29 条（自动收起后点"展开"会把收起设置存成开）对照上游行为判断，改不改写进汇报。

**会话·其余（coder B）**

- 连接方式详情（01 §4.2 第二级）：路径、中继名用 Q3 的导出 `leapgate_session_connection(session_id)`（10.4；coder R 在 `ui/rust-q3` 上做，合进 `ui/m2b` 之前用一个测试里能换掉的取值函数，返回值照 10.4 的 JSON），每次连接就绪后重新取，返回 `{}` 时不显示"路径""中继服务器"两行。指纹、画面数据来自 core 已有的 `FfiModel`、`QualityMonitorModel`。延迟只有"端到端"一行（Q13 之前，01 §4.2）：core 里每个会话记近 60 秒每 2 秒一个点和本次会话的最低、平均、最高，重连后接着记。"在画面上显示质量数据"照上游的会话选项；界面模式是详细时默认开（02 R2-Q11）。
- "服务器拒绝了此连接："：连接阶段出错、原因码是 `other` 时调同一个导出，有 `refused` 就照 01 §4.3 显示前缀加原文。
- 通知：登记 `screenshot`、`printer_request`、`switch_back`（10.6），做 01 P2 区块 E 里带按钮的几种。截图"另存为"要选位置，加 `file_picker`（版本先用上游 `flutter/pubspec.lock` 锁的，解析不了时选能和 frb 1.80.1 的 `uuid ^3.0.6`、`js ^0.6.4` 共存的版本）；提权通知的"请求提升权限"调 A 的选方式对话框；录屏通知的"停止"。权限中途被收回时加一条通知。
- 聊天和语音：`chat_model` 改写进 core（只留消息存储、未读数、语音状态；消息类型用 core 自己的，不带 `dash_chat_2`），登记 6 个事件；`ChatLayer` 里的面板、`chatToolbarButtons` 的聊天菜单（文字聊天、语音通话、等待接听、通话中的麦克风选择和挂断）、`tabUnread`。
- 录制：`recordButton` 和录制态，权限例外照上游。
- 标签右键菜单：`showSessionTabMenu`，"复制设备 ID""关闭其他标签""关闭"。
- 连接状态面板：等对方接受时加"显示给对方的名称：‹本机名›"（块 2 导出 `leapgate_local_display_name()`，coder R 做，取值方式同上）；`待调.md` 第 30 条（密码错误后保留输入、带"输入密码"标签）、第 33 条（关掉确认框后密码框拿回焦点）照样稿改。

**主页（coder C）**

- 分类：最近、收藏、局域网三类。`AppCore` 加收藏、局域网两份 `Peers`（照 M2a 的 `recentPeers`），加载用 `bind.mainLoadFavPeers`、`bind.mainLoadLanPeers`，事件 `load_fav_peers`、`load_lan_peers`。哪些分类显示、顺序照上游的选项（`peer_tab_page.dart` 的读法），在"视图"菜单里改。
- 卡片和列表视图、排序（修掉上游按在线状态排序那个不合法的比较函数，`peers_view.dart:389-391`）、多选、设备菜单（四组，出现条件照上游 `peer_card.dart:958-1348`，地址簿相关的项不出现）、各分类的空状态、1000 台上限；在线状态查询照 M2a。网络唤醒、创建桌面快捷方式、始终经中继、重命名（别名）、收藏、清除保存的密码、删除（最近）、移除（局域网）各照上游的调用。
- 连接框：搜索扩到三类（同一个 ID 只出现一次，标出来源，顺序最近、收藏、局域网）；"连接到"行尾的"⋯"（远程桌面、经中继连接）；结果按当前视图显示（`待调.md` 第 25 条）。"输入看起来像地址"的判断和回车规则不变。
- 本机区：密码行"刷新"（一次性密码）、"修改"（只在便携版显示，打开设置固定密码对话框，校验和保存照上游 `desktop_home_page.dart:890-1126`）；服务已停止时的"启动服务"；"正在被远程控制（N 个会话）"，N 用现有的远程桌面连接数，"查看"不显示（M3）；提示卡只显示系统错误那张。
- 被控时的遮罩：照上游 `canBeBlocked`、`shouldBeBlocked`（`flutter/lib/common.dart:3138-3205`），只盖主页。
- 界面模式：02 §4.1 的新选项，键 `leapgate-ui-mode`（值 `detail` 是详细，其余是简洁），Leapgate 自己的 LocalConfig 键放在用它的文件里（10.7 接入办法第 2 条）；"视图"菜单里切换；`main.dart` 把它接到 `buildLgTheme` 的 `mode`，切换立即生效；设备页默认视图跟着它，用户手动选过视图后按用户选的。

**测试和合入**

- core 的新代码有单测（延迟统计、分类合并搜索、排序、遮罩判断、聊天消息存储）；app 每个页面状态一个行为测试（05 §6.1）。
- 合入前：`git diff main -- flutter/` 为空；core 的 `flutter analyze --no-fatal-infos` 在 3.44.9 下不超出 92 条 info 的基线，新复制的 `shortcut_model` 带来的上游提示单列；app 0 条；复制件不跑格式化。改已有文件时不对整个文件跑 `dart format`：M2a 的文件不是按当前格式化器的样式排的，整文件格式化会把差异放大到几百行；只格式化新文件。
- 审查重点见 05 §3 第 2 步。

### 10.10 M3 的分工约定

依据：总仓库 `docs/新界面/06-M3拆法.md`（下称"06"；维护者 2026-10-31 按推荐定）。界面行为以 01 §3.3（P3 全部）为准，02 §0.4 第 2、11 条、R2-Q16 有更正；样稿 `A-P3.html`，画框名见 06 §2.2；令牌和图标以 `A-基础.html` 为准。M3 和 M2b 并行，M2b 的约定在 10.9（在 `ui/m2b` 上，合入后两节并存）。

**两段**：第一段现在做（窗口、来访标签、信息头、权限区、操作区、贴边小条、远程点击保护、关窗确认、主题和语言跟随（2026-11-01 改为和主窗口一样跟随系统，见下面"主题、语言"），加 Rust 三项）；第二段等 M2b 合入 main、main 合进 `ui/m3` 以后做（聊天侧栏、文件记录侧栏、主窗口本机区的连入数和"查看"、界面模式跟随）。

**分支和文件边界**（都从 `ui/m3` 切，做完合回 `ui/m3`）

| 分支 | 谁 | 只改这些 |
|---|---|---|
| `ui/rust-m3` | Rust coder | `src/ipc.rs`（`Data` 末尾一个变体，主进程一侧 `handle` 一处分发）、`src/ui_cm_interface.rs`（CM 一侧消息循环一处分发）、`src/server/connection.rs`（只在出口连接的编号从现有挂钩拿不到时加一行）、`src/leapgate_ffi.rs`（末尾追加 M3 一段）、`src/leapgate_hooks` 下的新文件、`libs/leapgate/src/ipc.rs`（新）；测试 |
| `ui/m3-ds` | designer | `app/lib/widgets/` 下 `lg_cm` 开头的新文件、`app/lib/gallery_main.dart` 的追加、这些组件的测试 |
| `ui/m3-cm` | CM coder | `app/lib/cm/`（新）、`app/lib/main.dart` 的 `--cm` 分支、`app/windows/runner/main.cpp` 里 CM 窗口的初值；core 的 `models/server_model.dart`（新复制）、`leapgate/` 下 `cm_` 开头的新文件、`consts.dart`（只追加）；它们的测试 |

- 和 M2b 重叠的只有 `app/lib/main.dart`（M2b 主页块改界面模式接主题那几行）、core `consts.dart`（M2b 两个 coder 也追加选项键）、`gallery_main.dart`，都只追加，整合时合并相邻行。
- ARB 键用 `cm` 前缀，加在两个 ARB 文件末尾，中英文同时加，文案照 01 §3.3 和 §7.6，新写的句子列进提交说明。
- CM coder 先用 M0、M2a 的组件和简单占位把逻辑写通，整合时换成 designer 的组件；占位要能被行为测试按文字和语义标签找到。

**进程间消息和块 2 导出**（Rust coder 做；Rust 合进 `ui/m3` 之前，CM coder 用测试里能换掉的取值函数）

`ipc::Data` 末尾加 `Leapgate(leapgate::ipc::Msg)`，`Msg` 定义在 `libs/leapgate/src/ipc.rs`，以后 Leapgate 的进程间消息都加在 `Msg` 里（03 §6.1 C1），只追加、不改已有变体的顺序和含义。上游 `Data` 两头的消息循环都有兜底的 `_ => {}`，两头各加一处分发，漏了新消息会被静默吞掉。

| 导出（块 2） | 谁调 | 做什么 |
|---|---|---|
| `leapgate_incoming_counts()`，异步，返回 JSON 字符串 | 主窗口本机区（第二段） | 连服务进程的进程间通道问一次，返回 `{"remote":n,"file_transfer":n,"port_forward":n,"exit":n,"camera":n,"terminal":n}`；服务进程不在时 `{}`。端口转发里属于出口的只算进 `exit`。不改上游 `ui_interface.rs` 的状态轮询（C1） |
| `leapgate_show_cm()` | 主窗口"查看"（第二段） | 经上游 `send_to_cm`（`src/ui_interface.rs`）同一条路发 `Msg::ShowCm`；CM 进程不在时什么也不做（C2） |
| `leapgate_ui_mode_changed(mode)` | 主窗口改了界面模式以后（第二段） | 发 `Msg::UiMode(mode)` 给 CM（S7） |
| `leapgate_cm_events(sink)`，`StreamSink<String>` | CM 启动时订阅 | CM 一侧收到 `Msg::ShowCm` 推 `{"name":"show_cm"}`，收到 `Msg::UiMode` 推 `{"name":"ui_mode","mode":"…"}`。不往上游的 `InvokeUiCM` 加方法（10.1） |

- C1 的出口：出口连接的编号在已有的 Leapgate 出口挂钩里记进 `libs/leapgate`（出口在登录时判定，`port_forward_mux.leapgate_exit`）；数的时候按上游连接表（`AUTHED_CONNS`）分类，端口转发里编号在出口表中的算出口，出口表里已经不在连接表的编号顺手删掉（V1 的做法）。上游的连接表和 `AuthedConn` 不加字段。
- 已知限制：新旧版本的进程短暂同时在跑时，旧进程收不懂新变体，解码失败（上游 `Data::DrmCursor` 的注释写过同类问题）。新界面便携版和旧界面不同时运行（03 §7.1），日常碰不到。
- C1 在 M6 也要用（关出口前的确认）。

**组件（designer）**：规则同 10.8"组件约定"。要做的见 06 §2.2：CM 外框（可拖动的标题区、"收起""关闭"，紧凑和展开两种宽度）、来访标签条、信息头（头像规则同 01 §3.1 区块 D）、几种会话类型的信息区、权限区（带文字的开关两列、只读态）、操作区的各种组合、贴边小条（一个连接按类型的文案、几个连接）、远程点击被拦下的提示、文件记录侧栏的列表行和空状态、关窗确认。聊天侧栏是第二段 designer 做的 `LgCmChat`（`app/lib/widgets/lg_cm_chat.dart`：M2b 聊天气泡的嵌入形态，铺满侧栏、没有标题和关闭，带只读态；`LgChatMessage` 加了可选的 `sender`）。CM 的颜色跟主题，信息头用固定的浅青功能底（01 §2.4），不用来访者的身份色。

**CM 页面（CM coder，第一段）**

- 初始化：`--cm` 分支照上游 `flutter/lib/main.dart:285-302`：先建 `AppCore`，再按 CM 初始化平台接口（`kAppTypeConnectionManager`，它会调 Rust 的 `cm_init`，`core/lib/models/native_model.dart` 里已有这一处），登记 CM 的全局事件 `add_connection`、`on_client_remove`、`show_elevation`、`update_voice_call_state`（登记在 `appCore.events`，10.6；`theme`、`language` 不登记，见下面"主题、语言"），第二段加了 `chat_server_mode`、`cm_file_transfer_log`（见下面"第二段"）。不读 `hide_cm`（03 §5.2 M3）。
- 复制件：`flutter/lib/models/server_model.dart` 复制进 core，CM 用到的部分按"只删界面调用"保留（客户端列表、`addConnection`、`onClientRemove`、接受和拒绝、断开、提权、撤销交换、语音状态、关闭全部、500 ms 的轮询和约 6 秒退出），主窗口和 Android 的部分（密码、ID、起停服务）整段删掉，来源行写明删了什么。标签不用上游的 `DesktopTabController`，用自己的列表。一条连接的两次 `add_connection`、`on_client_remove` 的关闭标记、同一个人重连时删旧的那条，照上游的规则（06 §4.2）。
- 窗口：紧凑态 320×500、贴主显示器工作区右上角、置顶、不能改大小；展开侧栏时向左展开到 700×500（2026-10-31 组件审查后定：样稿是 320×500，01 §3.3 写"约 300~320 宽"，选 320；外框 320 含不可见缩放边框，客户区 150% 下约 309，组件按最窄客户区 304 设计，见 §10.5 M3 必修项的修法；尺寸用组件里的 `kLgCmWidth`、`kLgCmHeight`、`kLgCmExpandedWidth`，不另写一套）；隐藏照上游用透明加隐藏、不销毁；runner 里 CM 的初值（现在 800×600）改成和 Dart 一致。
- 贴边小条：同一个窗口缩成一条，贴主显示器上边、靠右，沿上边左右拖动、位置只在本次运行内记住（记在 `LgCmWindow` 的内存里，不写 LocalConfig：CM 进程的 LocalConfig 是启动时读的快照，写任何一个键都会把整份旧配置存回文件，盖掉主窗口之后改过的本地配置；第一段原来写的 `leapgate-cm-strip-offset` 键第二段审查后去掉）；授权后自动收起的时机和取消条件照上游 `server_model.dart:571-590`、`server_page.dart:180-186`（01 §3.3 改成"收成小条"而不是最小化）；新来访时恢复成完整小窗并置顶。
- 远程点击保护：照上游 `server_page.dart:1237-1253`，被拦下时在按钮旁提示"无法远程执行此操作"；`allow-remote-cm-modification` 开着时放行。小条上的"断开"同样受保护。
- 关窗：多于一个连接时始终确认"断开全部会话？"，不读 `enable-confirm-closing-tabs`（R2-Q16）；关闭照上游 `closeAll`。标题栏"关闭"和确认里的"断开"也做远程点击保护，问的是任意一个还连着的来访（已断开的问不到、会读到旧值）；一个都没连着时直接执行。整个窗口（标题栏按钮、标签、面板、确认框、小条）都不接键盘焦点（`allow-remote-cm-modification` 开着时除外）：服务端只在左键抬起和回车时更新对方的输入时间，Tab 加空格能绕过点击判断。
- 主题、语言（2026-11-01 整体审查后定，代替原来"启动时读设置、运行中收事件切换"的写法）：CM 和新主窗口一样跟随系统，不读 LocalConfig 的 `theme`、`lang`，也不登记 `theme`、`language` 事件（新主窗口现在只跟系统、不会发）；到 M6 设置页存下用户的选择时，主窗口和 CM 一起接。语言只有简体中文和英文，系统是其他语言时用英文（IQ10）。

**测试和合入**

- core：客户端列表的增删和两次事件、已断开的保留和清理、自动收起的取消条件、没有来访时退出的计时（用假时钟），各有单测；Rust：C1 的分类（含出口表清理）、`Msg` 的编解码。app：06 §5.1 列的每种状态一个行为测试。
- 合入前：`git diff main -- flutter/` 为空；core 的 `flutter analyze --no-fatal-infos` 在 3.44.9 下不超出 92 条 info 的基线，新复制的 `server_model` 带来的上游提示单列；app 0 条；复制件不跑格式化；改已有文件时不对整个文件跑 `dart format`。
- 审查重点：Rust 看两头分发都在、出口计数和清理、旧界面的 CM 不受影响；CM 看事件处理和上游规则一致、窗口和小条的状态切换、远程点击保护；组件看样稿必修项。

**CM 的已知限制**

- 远程点击保护靠"本地点击比对方最近一次输入晚 120 ms 以上"判断：CM 进程卡顿超过 120 ms 时，对方的点击可能被当成本地点击放行。
- 它也挡不住经讲述人或 UI Automation 按语义调用 CM 的按钮。能控制键盘鼠标的人本来就能在本机运行程序，不另做防护。
- 按 Alt+F4 关闭 CM 不弹"断开全部会话？"，直接断开全部会话（同上游）。
- 第二位来访者的自动收起计时会覆盖第一位的：在小窗里移动鼠标只取消最后一个，前一个到时照样收起（同上游）。

**第二段**（2026-11-01，M2b 合入 main 后把 main 合进 `ui/m3` 再做）

- 侧栏：信息头按钮开关侧栏（远程点击保护照旧）。侧栏只在所选来访者有侧栏时显示（已授权的远程桌面、摄像头是聊天，文件传输是文件记录；`_hasSide`），窗口宽度跟着它：显示时 700（`kLgCmExpandedWidth`），否则 320。`LgCmWindow.setExpanded` 记住这个宽度，`_toFront`（新来访、从小条展开、"查看"）照它摆，不再一律放回 320。侧栏开着时来了新来访：新来访者已授权（密码直接通过）时侧栏照开、宽度不变；还在请求中时没有侧栏，窗口回到 320，接受后回到 700。所有来访者都没了时侧栏关上，6 秒内再来的来访者从关着开始。
- 聊天：`leapgate/cm_chat.dart` 的 `CmChatModel`，管上游 `ChatModel` 在 CM 里的那部分。消息按来访者 ID 存（上游 `MessageKey` 也只比 ID），重连后还能看到；发送用所在标签的连接编号，所以上游 `_addTab` 里的 `chatModel.updateConnIdOfKey` 没有加回（复制件来源行已写明）。收到消息时（上游 `receive`）：窗口提到前面（小条会展开；已经是完整小窗时只显示、取得焦点，不挪回角落，同上游 `main.dart:321-329`），切到发消息的人的标签并打开聊天；正在聊天里写字（侧栏开着、输入框有焦点）时不切，发消息的是另一个人（按 `peerId` 比，同一个人的远程桌面和摄像头共用一份聊天）才计入他标签上的未读数。发送时当场取出文字、清空输入框，再走远程点击保护（要等约 120 ms），所以连按不会发两次、等待期间输入的新草稿不会被清掉；被拦下时输入框还空着就把原文填回去。回车发送后输入框留着焦点（`LgTextField` 透传 `onEditingComplete`，会话页的 `LgChatPanel` 一起改）。点有未读的标签会打开它的侧栏（上游 `server_page.dart:131-145`）。对方断开后聊天只读，提示"对方已断开连接"。
- 文件记录：`models/cm_file_model.dart` 复制上游并改写（来源行列了差异）：日志解析、每条记录的状态规则、删目录时去掉其下的删除记录照抄；记录表在第一条日志到时建（上游在标签被选中时建，没选中过的连接的日志会被丢掉）；"侧栏正显示这个连接"由页面设 `shownConnId`。方向按 Windows 上 CM 的读写定：`isRemote`（CM 读文件、对方下载）是"从本机下载"，其余是"上传到本机"；名字只显示最后一段路径，重命名是"旧名 → 新名"；最新的在上面；已取消或跳过的显示"已跳过"。
- 未读数：聊天和文件记录共用上游的 `Client.unreadChatMessageCount`，改它的地方都会接着通知页面（聊天、文件记录 model 的通知，页面自己的 `setState`），标签和侧栏按钮跟着变。
- 焦点：`LgCmFrame` 加了 `sideFocusOnly`（默认 false，和原来一样不管焦点）。CM 页面传 `!allowRemoteCmModification()`：标题行、标签、面板、确认层不接焦点，侧栏可以（聊天输入框要能打字），代替第一段在整个窗口外包的 `ExcludeFocus`。发送只有两条路：输入框里按回车、鼠标点"发送"，都走远程点击保护（服务端在对方按回车和左键抬起时更新对方的输入时间，所以对方的回车和点击都会被拦下，提示出现在侧栏上方）。"发送"按钮不接焦点（`LgCmChat` 里包了 `ExcludeFocus`）：Tab 加空格不会更新对方的输入时间，否则对方点进输入框打字后能用它以本机身份发出。"查看"在 CM 没有来访者时不处理，免得弹出空窗口。
- 语音：通话中操作区一行是麦克风选择加"挂断"（`LgCmMicRow`）。设备照上游 `AudioInput`（`isCm: true`）：能用"系统声音"时它在第一项、也是默认；一个设备都没有时点选择框提示"未找到音频输入设备" 3 秒。选设备不做远程点击保护（同上游），"挂断"做。
- 主窗口：本机区按 06 M3-1，N 是 C1 的全部类型之和，有远程桌面或终端时"正在被远程控制（N 个会话）"，否则"‹N› 个传入会话进行中"，旁边"查看"调 `leapgate_show_cm`。`LocalStatusModel` 每 3 秒问一次 `leapgate_incoming_counts`（单独的计时器，不放在每秒的状态轮询里）：主窗口收不到会话开始、结束的事件，`video_conn_count` 又只数远程桌面；一次查询是本机的一次进程间连接，服务进程在内存里数，最坏约 2 秒，3 秒的间隔不会叠起来。原来的 `remoteSessions`（`video_conn_count`）删掉。
- 界面模式：主窗口切换简洁 / 详细（`setDetailMode`）后调 `leapgate_ui_mode_changed`，值和 LocalConfig 里的一样（`detail` 或空）。CM 启动时读一次 LocalConfig，并订阅 `leapgate_cm_events`（`listenToMainWindow`）：`ui_mode` 换 `LeapgateApp` 的 `detailMode`，只换尺寸；`show_cm` 把窗口提到前面。CM 不把收到的模式写回 LocalConfig：CM 进程里的 LocalConfig 是启动时读的，写一次会把这份旧的整个存回去，盖掉主窗口之后的改动。

**第二段的已知限制**

- 所有来访者共用一份聊天草稿（同上游只有一个输入框）：给 A 写了一半切到 B，草稿还在输入框里。
- 远程点击被拦下的提示出现或消失时侧栏会重建，输入框失去焦点（草稿不丢）。
- 主窗口的连入数最多晚约 5 秒（3 秒间隔加一次查询）。
- 选麦克风不做远程点击保护（同上游）。
- 没有聊天侧栏的连接（文件传输、终端）发来聊天时，标签切过去但消息看不到，也不计未读（同上游）。
- 收成小条时侧栏正开着某个连接的文件记录，这期间该连接的新记录不计未读。
- 麦克风列表只在通话那一行出现时读一次（上游每次点都重读）；读回来之前点选择框，会短暂提示"未找到音频输入设备"。
- 文件日志每来一块就让整个 CM 页面重建一次（Flutter 按帧合并），上游只重建文件记录那一页。

### 10.11 M4 的分工约定

依据：总仓库 `docs/新界面/07-M4拆法.md`（下称"07"；维护者 2026-11-02 把 M4-1~M4-9 全部按推荐定）。界面行为以 01 §3.1 区块 D、E、F、G、H、K 为准，账号的文案看 02 §1.5.3，标签颜色看 02 §3.6；样稿 `A-P1.html`，画框名见 07 §2.2；令牌和图标以 `A-基础.html` 为准。07 §6 列的不做。

**分支和文件边界**（都从 `ui/m4` 切，做完合回 `ui/m4`；`ui/m4` 上已有下面"挂载点"的骨架）

| 分支 | 谁 | 只改这些 |
|---|---|---|
| `ui/rust-h1` | coder R（H1） | `libs/leapgate/src/api.rs`（加一个带 Bearer 的通用请求函数）、`libs/leapgate/src/account/`（新）、`libs/leapgate/src/lib.rs`（声明模块一行）、`src/leapgate_ffi.rs`（末尾追加 M4 一段）；测试。不改 Dart，不生成桥 |
| `ui/m4-ds` | designer | `app/lib/widgets/`（新组件；`LgDeviceCard`、`LgDeviceRow`、`LgDeviceTable` 加备注）、`app/lib/gallery_main.dart`、组件的测试 |
| `ui/m4-account` | coder A（账号、登录、同组设备） | core `leapgate/account.dart`、`leapgate/group.dart`、`leapgate/peer_tabs.dart`（只改 `isEnabled`）；app `pages/home/account/`、`pages/home/group/`、`pages/home/home_page.dart` 的 `_SideColumn`（账号区摆在哪、间距）、`main.dart`（启动时调 `appCore.account.start()` 那几行）；它们的测试 |
| `ui/m4-ab` | coder B（地址簿） | core `leapgate/address_book.dart`、`leapgate/peer_list.dart` 的 `peerMenu`（条件和参数）、`consts.dart`（只追加地址簿的选项键）；app `pages/home/address_book/`、`peer_views.dart` 里 `peerMenuItems` 调 `peerMenu` 那几行（跟着参数改）；它们的测试 |

- 共用文件只往挂载点里填，挂载点以外的行不改：`devices_page.dart`、`peer_views.dart`、`account_category.dart`，core 的 `account_api.dart`、`app_core.dart`，`core/test/account_fakes.dart`。挂载点的签名不够用、或者要改共用文件的别处时，写进汇报，由主会话改。
- ARB：A 的键以 `account`、`login`、`group` 开头，B 以 `ab` 开头，加在两个 ARB 文件末尾，中英文同时加，文案照 01 §7.6：01 里写好的句子逐字照抄，新写的句子列进提交说明。分类名 `abCategory`、`groupCategory` 骨架里已经加了。
- 两个 coder 先用 M0~M3 的组件和简单的占位控件把逻辑写通，整合时换成 designer 的组件。占位不求好看，但行为测试要能按文字和语义标签找到它们。
- 测试里换掉导出：设 `accountApi = FakeAccountApi()`（`core/test/account_fakes.dart`；app 的测试照 `home_fakes.dart` 引 `FakeLeapgate` 的办法用相对路径引它）。三个 model 第一次用到时才建，`accountApi` 要在第一次用 `appCore.account`、`addressBook`、`group` 之前设好。

**H1 的块 2 导出**（coder R；R 合进 `ui/m4` 之前，A、B 只经 `account_api.dart`，测试用 `FakeAccountApi`）

都放在 `src/leapgate_ffi.rs` 末尾新的 "Account (M4)" 一段，逻辑在 `libs/leapgate/src/account/`，`src/` 只做薄壳。除 `leapgate_account_local` 外在 Dart 侧都是异步：Rust 函数照 `leapgate_incoming_counts` 的写法同步返回 `String`，请求放在用 `#[tokio::main(flavor = "current_thread")]` 包的函数里跑（frb 在工作线程上调，不在运行时里，符合 AGENTS.md 的 Tokio 规则）。返回值都是 JSON 字符串，出错时是下面"错误的形状"。

| 导出 | 参数 | 成功时返回 | 做什么 |
|---|---|---|---|
| `leapgate_account_local()`，同步 | | 有令牌时 `{"user":<user_info>}`，没有时 `{}` | 不发请求：读 LocalConfig 的 `access_token`（只看是否非空）和 `user_info` |
| `leapgate_account_login_options()` | | `{}` | `GET /api/login-options`，2xx 就算成功，内容不解析（M4-4；rustdesk-api 回 `common-oidc/null` 也照样成功） |
| `leapgate_account_login(username, password)` | 原样，trim 由界面做 | `{"user":<用户对象>}` | `POST /api/login`，体 `{username, password, id, uuid, autoLogin: true, type: "account", deviceInfo}`（上游 `common/hbbs/hbbs.dart` `LoginRequest`，不带验证码字段）；`id`、`uuid`、`deviceInfo` 由导出在 `src/` 取（`ui_interface::get_id()`、`get_uuid()`、`get_login_device_info()`）再传进 `libs/leapgate`。成功后写 `access_token`、`user_info` |
| `leapgate_account_current_user()` | | `{"user":<用户对象>}` | `POST /api/currentUser`，体 `{id, uuid}`；成功后重写 `user_info` |
| `leapgate_account_logout()` | | 总是 `{}` | `POST /api/logout`，体 `{id, uuid}`，2 秒超时；不管结果如何都删 `access_token`、`user_info`、两份缓存（M4-9） |
| `leapgate_ab_cache()` | | `{"entries":[…]}` | 不发请求：`_ab` 缓存里的令牌和当前令牌相同时，原样给它的 `ab_entries`（每条 `guid`、`name`、`peers`、`tags`、`tag_colors`），否则空数组 |
| `leapgate_group_cache()` | | `{"users":[…],"peers":[…]}` 或 `{}` | 不发请求：`_group` 缓存的令牌相同时给它的 `users`、`peers`（上游 `toGroupCacheJson` 的格式），否则 `{}` |
| `leapgate_ab_books()` | | `{"max_peers":n,"personal":"<guid>","shared":[{"guid","name","owner","note","rule"}…]}` | `POST /api/ab/personal`、`/api/ab/settings`、`/api/ab/shared/profiles`（分页）。任一个失败整个失败；`personal` 回 404 是 `unsupported`（07 §4.4）；`max_peers` 是 0 表示不限 |
| `leapgate_ab_book(guid, name, personal)` | 簿的 guid；`name`、`personal` 只用来写缓存 | `{"peers":[…],"tags":[{"name","color"}…]}` | `POST /api/ab/peers?current&pageSize&ab=<guid>`（分页，按 ID 去重，某一页没有新 ID 就停，07 §4.3）、`POST /api/ab/tags/<guid>`。`peers` 是服务器给的设备对象原样（个人簿带 `hash`、共享簿带 `password`，M4-3）。成功后写 `_ab` 缓存（见下面"缓存"） |
| `leapgate_ab_add_peer(guid, peer)` | `peer`：设备对象的 JSON 字符串 | `{}` | `POST /api/ab/peer/add/<guid>`，体原样（个人簿去掉 `password`、共享簿去掉 `hash` 由界面做，上游 `addPeers`） |
| `leapgate_ab_update_peer(guid, peer)` | `peer`：`id` 加要改的字段的 JSON 字符串 | `{}` | `PUT /api/ab/peer/update/<guid>`，体原样。上游 5 处都走它：标签、别名、备注、`hash` 或 `password`、与最近会话同步 |
| `leapgate_ab_delete_peers(guid, ids)` | `ids: Vec<String>` | `{}` | `DELETE /api/ab/peer/<guid>`，体是 ID 数组 |
| `leapgate_ab_add_tag(guid, name, color)` | `color: i64`（ARGB，同 Flutter `Color.value`） | `{}` | `POST /api/ab/tag/add/<guid>`，体 `{name, color}` |
| `leapgate_ab_rename_tag(guid, old_name, new_name)` | | `{}` | `PUT /api/ab/tag/rename/<guid>`，体 `{old, new}` |
| `leapgate_ab_set_tag_color(guid, name, color)` | `color: i64` | `{}` | `PUT /api/ab/tag/update/<guid>`，体 `{name, color}` |
| `leapgate_ab_delete_tags(guid, names)` | `names: Vec<String>` | `{}` | `DELETE /api/ab/tag/<guid>`，体是标签名数组 |
| `leapgate_group()` | | `{"users":[<用户对象>…],"peers":[<设备对象>…]}` | `GET /api/users`、`GET /api/peers`（都带 `accessible`、`status=1`，分页，`current` 和 `page` 都带，07 §4.3）；两个都成功才算成功，成功后整份重写 `_group` 缓存。不调 `/api/device-group/accessible`（M4-6） |

- 共 17 个导出，覆盖 07 的 18 个端点。写操作按端点各一个、不合成"操作种类 + 参数"的一个：各端点的体和 404、409 的含义都不同，合成一个要在 JSON 里再编一层，界面调用反而不清楚。参数名避开 Dart 的保留字（`new`），所以叫 `old_name`、`new_name`。一次加一台设备、一个标签（上游 `addPeers`、`addTags` 也是逐个发），多选"加入地址簿"由界面循环，遇到第一个错误就停（上游同样）。
- 用户对象、设备对象都是服务器给的原样（用户对象有 `name`、`display_name`、`avatar`、`email`、`note`、`status`、`is_admin`），界面按 `account_api.dart` 的数据类解析。
- 写 `user_info` 照上游 `UserPayload.toJson`：`{"name","display_name","avatar","status"}`，`status` 照它的换算（0 停用、-1 未验证、其余 1）。Rust 别处在读它：登录消息的显示名（`src/client.rs`）、本机显示名导出。
- 写操作 2xx 且体为空或体里没有 `error` 时算成功（上游 `_jsonDecodeActionResp`）。

**错误的形状**：`{"error":"<种类>","text":"<原文>"}`。`text` 取服务器 JSON 的 `error` 字段，没有时 `HTTP <状态码>`；`network` 时是错误描述。`text` 截到 200 个字符，不含令牌。

| 种类 | 什么时候 | Rust 顺带做的 |
|---|---|---|
| `unauthorized` | 登录以外的接口回 401；`currentUser` 回 400 | 删 `access_token`、`user_info`、`_ab`、`_group` |
| `wrong_credentials` | 登录回 401：Leapgate 服务端用它表示用户名或密码错误（07 §4.1） | 不动令牌 |
| `verification_required` | 登录 2xx 但 `type` 不是 `access_token`（要验证码或 2FA，M4-1） | 不写令牌；界面显示"此服务器要求验证码登录，Leapgate 暂不支持" |
| `not_found` | 写操作回 404（设备、标签不在这本簿里） | |
| `conflict` | 409（新标签名已存在） | |
| `unsupported` | `ab/personal` 回 404 | |
| `network` | 连不上、TLS 失败、超时（单次 12 秒，登出 2 秒） | |
| `server` | 其余：别的 4xx（含限流 429、只读簿写入的 403、簿满的 400）和 5xx，2xx 里带 `error`（`currentUser` 的内部错误），回的不是预期的 JSON；`settings`、`shared/profiles` 的 404 也在这里（07 §4.4） | |

- `currentUser` 的 400 照上游（`models/user_model.dart:85-88`）也清令牌。上游 400 只清令牌、不当场复位地址簿和组，但紧接着 finally 里的拉取因为没有令牌也会复位它们，结果和 401 相同，所以这里两者一样处理。
- 界面不认识的种类当 `server`（`parseApiResult`）。

**缓存**（M4-2、M4-9）

- `_ab`：格式照 `hbb_common::config::Ab`（`access_token` 加 `ab_entries`）。个人簿那条的 `name` 必须是 `My address book`：`AbEntry::personal()` 按名字认，`src/client.rs` 的 `try_get_password_from_personal_ab` 靠它找个人簿里存的密码（07 §4.2）。`leapgate_ab_book` 成功后改写：最多两条，个人簿一条、最近拉过的共享簿一条（上游存"个人簿 + 当前簿"，界面拉的共享簿就是当前簿）；`personal` 为真时换个人簿那条，否则换共享簿那条；文件里的令牌和当前令牌不同时先清空再写。条目的 `peers` 照 `AbPeer` 只留 `id`、`username`、`hostname`、`platform`、`alias`、`tags`，个人簿另带 `hash`（上游 `toCustomJson(includingHash:)`）；`tag_colors` 是 `{"名字": 颜色}` 的 JSON 字符串。
- `_group`：照 `config::Group`，`leapgate_group` 成功后整份重写。
- 退出、`unauthorized` 时两份都删。登录成功时不删（令牌不同的缓存不会被读到）。

**令牌和请求**（M4-3、M4-8、IQ7）：`access_token` 只在 Rust 里读写，Dart 不读不写它，也不写 `user_info`。API 地址用 `report::api_root()`（已知限制：不认程序文件名里带的配置，M4-8）。请求用 `api.rs` 的严格客户端（系统根证书加 webpki、不跟随重定向、证书失败不回退、按上游规则走代理），带 `Authorization: Bearer <令牌>`。日志不记令牌、密码、`hash`、共享密码，失败只记端点路径和状态码。

**Dart 侧的调用层**：`core/lib/leapgate/account_api.dart`（骨架，共用）

- 数据类：`AccountUser`（`displayNameOrName`）、`ShareRule`（上游同名枚举去掉文字）、`AbProfile`、`AbBooks`、`AbTag`、`AbBookData`（设备用 core 的 `Peer.fromJson`）、`GroupData`（设备经 `groupPeer`，照抄上游 `PeerPayload.toPeer`，`loginName` 是主人的用户名）。
- `ApiErrorKind`（上表八种）、`ApiError(kind, text)`、`ApiResult<T>`（`ok`、`value`、`error`）、`parseApiResult(json, ok)`。
- 接口 `AccountApi`，方法和导出一一对应：`localUser`、`loginOptions`、`login`、`currentUser`、`logout`、`abCache`（返回 `entries` 的列表）、`groupCache`、`books`、`book(guid, name:, personal:)`、`addPeer(guid, peer)`、`updatePeer(guid, id, fields)`（`id` 由它并进体里）、`deletePeers`、`addTag`、`renameTag`、`setTagColor`、`deleteTags`、`group`。全局 `accountApi` 默认是 `RustAccountApi`，测试换成 `FakeAccountApi`。
- `RustAccountApi` 现在是占位：`localUser` 回 null，两份缓存回空，`logout` 什么也不做，其余回 `unsupported`。整合时每个方法体换成一行 `lgBind.leapgate…` 加 `parseApiResult`。

**core 的三个 model**（`ChangeNotifier`，同 M1 的做法，不用 Get、Rx；挂在 `appCore` 上，`late final`，第一次用时建）

| model | 文件 | 谁 | 别的路要用的成员 |
|---|---|---|---|
| `AccountModel` | `leapgate/account.dart` | A | `user`（null 是没登录）、`loggedIn`、`error`（最近一次和服务器核对失败的原因，仍算登录着）、`disabled`、`start()`、`checkLoginOptions()`、`login(username, password)`、`logout()`、`refresh()`、`signedOutByServer()` |
| `AddressBookModel` | `leapgate/address_book.dart` | B | `disabled`、`loaded`、`loading`、`unsupported`、`pullError`、`books`（个人簿第一、共享簿按名字）、`current`、`isPersonal(book)`、`peers`、`shownPeers`（经标签筛选）、`allPeers`（已加载的各簿，连接框用）、`canWrite`、`writableBooks`（"加入地址簿"列的簿）、`sharedPasswordOf(id)`、`syncPeerHash(id, hash)` |
| `GroupModel` | `leapgate/group.dart` | A | `disabled`、`loaded`、`loading`、`error`、`users`（自己第一）、`peers`、`selectedUser`、`selectUser(name)`、`shownPeers` |

- 地址簿和组都实现 `AccountData`（`loadCache()`、`pull()`、`reset()`，定义在 `account.dart`）。`AccountModel` 构造时拿到 `[addressBook, group]`（M5 的出口目录以后也加进来），由它按下面的顺序调这三个方法；页面上的"刷新""重试"直接调各自 model 的 `pull()`。其余成员各路自定，不进约定。
- 顺序（A 实现，照上游 `refreshCurrentUser`、`updateOtherModels`）：`start()` 先读 `localUser()`，有就当已登录、调各 `loadCache()` 先显示；再 `currentUser()`：成功就更新用户、并行调各 `pull()`；`network`、`server` 记进 `error`、保持登录、不拉（上游 `pullAb`、`group.pull` 在有网络错误时直接返回），"重试"调 `refresh()` 再走一遍；`unauthorized` 走 `signedOutByServer()`。`login` 成功后更新用户、并行拉。`logout()` 调导出后清用户、`reset()` 各个。`signedOutByServer()` 清用户和 `error`、`reset()` 各个（令牌 Rust 已经删了）。
- 地址簿和组的请求回 `unauthorized` 时，调 `appCore.account.signedOutByServer()`，不自己复位别人。
- 在线状态：地址簿和同组设备的 `Peer.online` 由各自的 model 更新：照 `CategoryPeers` 用 `platformFFI.registerEventHandler('callback_query_onlines', <自己的 handler 名>, …)`，只改自己列表里的设备，变了就通知。页面判断"有没有回答"沿用 `categoryPeers(...).hasOnlineState`（每个 `CategoryPeers` 都收下全部 ID，不用改）。
- 内置选项：`disabled` 分别读 `bind.isDisableAccount()`、`isDisableAb()`、`isDisableGroupPanel()`。`PeerTabs.isEnabled` 对地址簿是"账号、地址簿都没禁用"，对同组设备是"账号、组面板都没禁用"（上游 `models/peer_tab_model.dart` 的 `isEnabled`）；没登录时分类照常显示，内容是"登录后可查看…"。
- 本地选项：上游的 `current-ab-name`（Flutter 选项）、`sync-ab-with-recent-sessions`、`sync-ab-tags`、`filter-ab-by-intersection`（LocalConfig）照上游的键和值，归 B，键追加进 core 的 `consts.dart`（10.7 接入办法第 2 条）。登录框"预填上次的用户名"：上游读 `user_info` 的 `name`，退出后就空了；要做到 01 的"上次的"，A 加一个 Leapgate 自己的 LocalConfig 键在登录成功时记下（键放 `account.dart`）。
- 全局事件 `sync_peer_hash_password_to_personal_ab`（`src/client.rs` 登录后推）已在 `AppCore` 构造函数里登记，转给 `addressBook.syncPeerHash`（B 填；上游 `changePersonalHashPassword`：这台设备在个人簿里才写）。

**挂载点**（`ui/m4` 上的骨架提交，行为和 M3 相同）

| 文件 | 现在的内容 | 谁填 |
|---|---|---|
| `pages/home/account/account.dart` | `accountArea(context, overlays)`：左栏最下面的账号区，现在是空；`showLoginDialog(overlays)`：登录对话框，返回是否登录成功，地址簿和同组设备"没登录"状态的登录按钮也调它 | A |
| `pages/home/group/group.dart` | `groupCategory(context, overlays)`，返回 `AccountCategoryView` | A |
| `pages/home/address_book/address_book.dart` | `addressBookCategory(context, overlays)`；连接框的 `withAccountPeers(sourced)`（在最近、收藏、局域网之后接地址簿和同组设备里还没出现的设备）、`accountPeersLoading()`；卡片和列表的 `abPeerTags(item)`、`abPeerKeyLabel(l10n, item)`（共享簿存了密码时的钥匙说明，null 不显示）；设备菜单的 `abPeerMenuItem(l10n, item, action, overlays:)`（返回 null 时用页面自己的项）、`abMenuGroupNote(l10n, item, group, groups)`；多选条的 `abSelectionActions(l10n, category, ids, overlays:, done:)` | B |
| `pages/home/account_category.dart` | `AccountCategoryView`：`tools`（接在"多选"后面：刷新、标签筛选开关）、`header`（列表上方：簿切换、标签条、报错横幅）、`side`（列表左边：人员列表）、`state`（代替列表：没登录、加载中、不提供地址簿、网络错误、空；null 时列出设备） | 共用 |
| `pages/home/devices_page.dart` | 地址簿、同组设备两类走 `_accountList`：设备是 model 的 `shownPeers`，照当前视图和排序、1000 台上限照旧；上面 `header`、左边 `side`，有 `state` 时显示它；工具条接 `tools`；搜索结果经 `withAccountPeers`，"正在加载其他分类…"加上 `accountPeersLoading()`；多选条在这两类里只有 `abSelectionActions`，在其他分类里接在原有动作后面；单击"连接"、回车、搜索结果都经 `connectPeer` 并带上设备所在的分类 | 共用 |
| `pages/home/peer_views.dart` | `connectPeer(id, category:, relay:)`：地址簿分类带上 `sharedPasswordOf(id)` 的共享密码（`isSharedPassword`，上游 `connectInPeerTab`）；卡片和行的标签、钥匙接上面两个函数；菜单项先问 `abPeerMenuItem`，组标题旁的说明问 `abMenuGroupNote`；`PeerAction` 新加的六个只由 `abPeerMenuItem` 画，`deleteFromAb` 归危险组 | 共用（B 改 `peerMenu` 的调用参数） |
| `pages/home/home_page.dart` | `_SideColumn` 多了 `overlays`，导航之后是 `accountArea(...)` | A（摆放和间距） |
| core `leapgate/peer_list.dart` | `PeerAction` 加了 `addToAb`、`editTags`、`editNote`、`setSharedPassword`、`showBooks`、`deleteFromAb`；`peerMenu` 还不出它们 | B |
| core `leapgate/peer_tabs.dart` | `isEnabled` 对两类仍是 false | A |
| core `leapgate/app_core.dart` | `addressBook`、`group`、`account` 三个 `late final`；上面那个全局事件的登记 | 共用 |

- `peerMenu` 照 01 区块 F 的菜单表：管理组补"加入地址簿"（已登录，各分类）、"编辑标签""编辑备注""设置共享密码"（地址簿；共享密码只在共享簿）、"查看所在地址簿"；危险组在地址簿里是"从地址簿中删除"；同组设备只有连接方式和"加入地址簿"；只读簿的写操作灰显（`LgMenuItem.disabledNote`），说明只在第一个出现灰显项的组标题旁写一次。地址簿分类里的"重命名"改的是簿里的别名，"清除保存的密码"在个人簿有 `hash` 时清的是簿里的（上游 `common/widgets/peer_card.dart` 的 `AddressBookPeerCard`），这两项由 `abPeerMenuItem` 接管。
- 骨架里多选条的写法（`if (!accountCategory)` 下面那段没有重新缩进）是为了不动原有的行，整合时可以格式化这一段。

**组件（designer）**：规则同 10.8"组件约定"（只管画、文字由调用方传、带语义标签、两套主题和两套尺寸、画廊里每种状态一项、有行为测试）。要做的和样稿画框见 07 §2.2。接口要点：

- 账号区：没登录（"登录"按钮、下面一行说明，`onLogin`）；已登录（头像字、显示名，点开菜单向上展开：`@用户名` 那一行、"退出登录"，菜单项由调用方给）；退出的页内确认条（问句、正文、两个按钮）。头像字由调用方算好传入（01 区块 D 的规则归 A）。
- 登录对话框：用户名、密码两个输入框（控制器由调用方给）、"登录"按钮（忙时转圈，输入框不可改）；错误文字三处：用户名框下、密码框下（服务器返回的错误也在这）、整块的"无法获取登录选项"加"重试"（`onRetry`）；回车提交。
- 簿切换下拉：当前簿名，旁边的权限文字和所有者（调用方拼好）；展开后有搜索框、簿的列表（簿名、权限文字、所有者、选中态）、底部一行说明；`onSelect`。
- 标签筛选条：第一项"未标记"（文字由调用方给），其余每项是 `LgDeviceTag` 加选中态（描边加勾，不用标签色铺满）；`onToggle`、`onContextMenu(tag, globalPosition)`（标签右键）；放不下时横向滚动。
- 地址簿"更多"菜单、只读簿的设备菜单：用现成的菜单项拼，designer 只核对 `p1-ab-more`、`p1-ab-readonly`、`p1-ab-readonly-card`。
- 人员列表：搜索框；每行头像字、显示名、"我"标记；选中行带 ×（`onClear`）；`onSelect`。
- 卡片和列表视图的备注：`LgDeviceCard`、`LgDeviceRow` 加 `note`（null 不显示那一行或那一格），`LgDeviceColumn` 加 `note`，有没有这一列由调用方的表头决定（地址簿和同组设备有）。
- 列表状态：没登录（一句话加"登录"按钮）、网络错误（一句话加"重试"）、报错横幅（现有 `lg_banner.dart` 加"重试"按钮、可关闭，两句文字由调用方拼）、两类空、加载中骨架（现成的）。"服务器不提供地址簿"用空状态的样式。
- 添加设备对话框：ID、别名、密码（只在共享簿，下面一行提示）、备注（300 字上限）、标签选择（浅底小块，可多选）；提交中、ID 重复、簿满、服务器报错四种状态的文字由调用方给。其余小对话框（添加标签、重命名标签、编辑标签、编辑备注、设置共享密码、加入地址簿、查看所在地址簿）照它的样式用 `LgConfirmDialog` 加输入件拼，不另做组件。
- 修改标签颜色对话框：预览（标签小块）、一排预设色、自定义（色相环加明度条，自己画，不引第三方依赖）、`#RRGGBB` 输入框（格式错误的提示文字由调用方给）；提交中、失败；结果是 ARGB 整数（和上游存的一样）。

**测试和合入**

- R：每个端点的请求（方法、路径、查询、体）、响应解析、状态码到错误种类的映射（两种 401、`currentUser` 400、`personal` 404、409、2xx 带 `error`）、分页去重和停止条件、缓存的写入和删除（个人簿的名字、令牌不同时清空）；对两种服务器的集成测试 `#[ignore]`，地址和测试账号由环境变量给（07 §5.1）。假 HTTP 服务照 `api.rs` 现有的测试起。
- core：A 的启动顺序（有没有本地用户 × `currentUser` 的几种结果）、登录、退出、`signedOutByServer` 复位、人员筛选和自己排第一；B 的权限判断、只读簿灰显项、标签筛选（并集和交集）、与最近会话同步的比对、`syncPeerHash`、退出后清空。都用 `FakeAccountApi`。
- app：07 §5.1 列的每个页面状态一个行为测试。
- 改写档登记来源（10.1）：`account.dart` 改写上游 `models/user_model.dart`，`group.dart` 改写 `models/group_model.dart`，`address_book.dart` 改写 `models/ab_model.dart`；照上游 `common/widgets/login.dart`、`my_group.dart`、`address_book.dart` 重写的页面在文件头注明出处。
- 合入前：`git diff main -- flutter/` 为空；core 的 `flutter analyze --no-fatal-infos` 在 3.44.9 下不超出 92 条 info 的基线，app 0 条；复制件不跑格式化；改已有文件时不对整个文件跑 `dart format`，只格式化新文件。

**整合时要做的**

1. 合 R：重新生成块 2 的桥；`RustAccountApi` 的方法体换成 `lgBind` 调用加 `parseApiResult`；`core/test/fakes.dart` 的 `FakeLeapgate` 补上新导出（测试走 `FakeAccountApi`，补的可以直接抛错）。
2. 换上 designer 的组件；`PeerCard`、`PeerTableRow` 在地址簿和同组设备里传 `note`，表头加备注列。
3. 合 A、B：两个 ARB 文件的末尾合并；`peer_views.dart` 里 `peerMenu` 的调用参数以 B 为准。
4. 整体审查，再按 07 §5 验收。

**已知限制和与上游的不同**

- `leapgate_ab_books` 任一步失败整个失败；上游 `settings`、`shared/profiles` 失败时照样显示个人簿。两种支持的服务器都实现了这两个端点，失败多半是网络，整体重试就行。
- 缓存只存个人簿和最近拉过的共享簿（上游是"当前簿"，界面里两者相同）。
- `currentUser` 回 400 和 401 一样处理（理由见上面"错误的形状"）。
- API 地址不认程序文件名里带的配置（M4-8）。

**H1 的实现结论**（2026-11-02，分支 `ui/rust-h1`）

- 代码：`api.rs` 的 `bearer`（令牌为空时不带 `Authorization`，登录和登录选项用）；`libs/leapgate/src/account/` 的 `mod.rs`（账号四个端点、状态码映射、分页、令牌和 `user_info`）、`ab.rs`、`group.rs`；`src/leapgate_ffi.rs` 末尾 17 个导出。设备 ID、UUID、登录设备信息在导出里、进运行时之前取：桌面上 `get_id` 经 IPC 问服务，自己会起运行时，放进 `#[tokio::main]` 里就是嵌套运行时。令牌、`user_info`、两份缓存经一个小接口 `Store` 读写，正式实现就是 LocalConfig 和 `config::{Ab, Group}`，测试换成内存里的，免得单测写进本机的配置目录。
- 和上面约定的出入（都不改界面的用法）：
  - `leapgate_ab_books` 的 `shared`、`leapgate_ab_book` 的 `tags` 是服务器给的原样对象，会多出字段（rustdesk-api 的标签带 `id`、`user_id`、时间），界面按字段名取。
  - 所有分页请求都同时带 `current` 和 `page`，不止 `users`、`peers`（Leapgate 服务端不认识的参数照常忽略）。每页 100 条，同上游。
  - `leapgate_account_login_options` 不带令牌，非 2xx 一律报 `server`、不清登录。
  - `leapgate_ab_book` 在 `personal` 为真时，缓存条目的名字固定写 `My address book`，不用传进来的 `name`；个人簿条目的 `guid` 写真实的（上游写空串，没有读者在意）。
  - 拉取过程中退出了登录：写缓存前再核对一次令牌，变了就不写，免得把刚删掉的缓存写回来。
  - 2xx 但内容不是这个端点该回的形状，报 `server`，文字 `HTTP 200`。`ab/tags` 回 `null` 当没有标签（rustdesk-api 簿里没有标签时）。
  - `_group` 缓存按 `config::Group` 的字段写（用户 `name`、`display_name`；设备 `id`、`username`、`hostname`、`platform`、`login_name`），没有备注和设备组名：上游缓存本来就不存备注，`Group::load` 也会丢掉设备组名。`leapgate_group_cache` 给的设备是这种缓存格式，不是 `/api/peers` 的原样。
  - 日志：非 2xx 只记路径和状态码，连不上记路径和错误描述，两处各自每分钟最多一行（`throttled_log`）；登出失败另记一行。
- 测试：`libs/leapgate` 单测 156 个（新增 15 个，测试里起最小的假 HTTP 服务，覆盖每类端点的请求、两种 401、`currentUser` 400、`personal` 404、404/409、2xx 带 `error`、两种分页停止、缓存的写入、替换、令牌不同时清空和登出、401 时删除）；对真实服务器的集成测试 `account::live_tests::live_account_flow`（`#[ignore]`，环境变量见文件头）。core 的 `RustAccountApi` 用假绑定测了一条（184 个测试，analyze 92 条 info 不变）。
- 对两种服务器的实测（2026-11-02，从开发机跑集成测试；两边都用命令行或管理接口新建的专用账号、三本各一种权限的共享簿、一个共享组）：

| 项目 | Leapgate 服务端（验收服务 `7fbe55a`） | rustdesk-api v2.7（Docker `lejianwen/rustdesk-api:v2.7`，2025-09-28 发布，2026-11 时最新稳定版） |
|---|---|---|
| 登录选项 | 通过（`[]`） | 通过；回的是 `["common-oidc/[{\"name\":\"webauth\"}]","oidc/webauth"]`，不是读码推断的 `common-oidc/null`，只看 2xx，不受影响 |
| 密码错 | 通过：401 → `wrong_credentials` | 回 400 `Username or password error.` → `server`，文字照原文显示 |
| 登录、`user_info`、当前用户 | 通过 | 通过 |
| 簿列表 | 通过：`max_peers` 5000，三本共享簿的 `rule` 1/2/3、`owner` 对 | 通过：`max_peers` 0（不限），`rule`、`owner` 对 |
| 个人簿加设备、改设备（标签、备注）、加标签、改颜色、改名、删标签、删设备 | 通过；读回 `hash`，缓存个人簿条目名字和 `hash` 对 | 通过；不存设备的 `note`（读回 `null`），标签改名不级联到设备上的标签 |
| 改名到已有的标签名 | `conflict` | 400 `Item already exists.` → `server` |
| 改不存在的设备、标签 | `not_found` | 400 `Item not found.` → `server` |
| 删除含不存在名字的标签 | 忽略不存在的 | 整个请求失败（400 `Item not found.`） |
| 分页（个人簿 121 台） | 通过：按 `total` 取两页，121 台 | 通过：`ab/peers` 不看任何分页参数（`current`、`page` 换成 2 都回同样的全部条目，实测 120 条），第二页没有新 ID 就停，121 台 |
| 只读簿写入 | 拒绝（403 `Read-only address book` → `server`） | 拒绝（400 `No access.` → `server`） |
| 读写簿加、删设备 | 通过 | 加通过；删要完全控制，读写簿删除回 400 `No access.` |
| 完全控制簿加、删设备 | 通过 | 通过 |
| 共享簿读回 `password`、缓存里不带 `hash` | 通过 | 通过 |
| 同组设备 | 通过：人员是自己和同组的人；设备列表为空 | 通过：同上；`users` 认 `page`、不认 `current`（`page=2&pageSize=1` 回第二个人，`current=2&pageSize=1` 回第一个人） |
| 退出后旧令牌 | 通过：`currentUser` 回 401 → `unauthorized` | 通过：同左 |

- 没验的：同组设备有设备时的转换（两边的测试账号名下都没有设备，`/api/peers` 只验了请求和空列表，转换由单测覆盖）；簿满；登录限流；个人簿自动填密码（要真实连接，归 07 §5.2 验收）；经 frb 的实际调用（桥已生成、根 crate 编译通过，Dart 侧只用假绑定测了）。
- rustdesk-api 的几处行为（找不到、重名都回 400，读写簿不能删设备，不存备注，标签改名不级联）是它自己的，界面照 `server` 显示服务器原文，不另做适配。
