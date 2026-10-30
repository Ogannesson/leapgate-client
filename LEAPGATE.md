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

- 新界面 runner 的窗口类：主窗口 `LEAPGATE_UI_MAIN`，CM（`--cm`）`LEAPGATE_UI_CM`，安装页（`--install`）`LEAPGATE_UI_INSTALL`。三者分开，按主窗口类名找时不会找到另外两个。主窗口的类名（`leapgate_ui/app/windows/runner/main.cpp` 的 `kMainWindowClass`）和 `libs/leapgate/src/ui.rs` 的 `MAIN_WINDOW_CLASS` 要一致；另外两个 Rust 不找，只在 runner 里。
- 合并上游时核对：`core_main_invoke_new_connection` 的 Windows 分支仍按 `send_message_to_hnwd` 加 `WM_USER + 2` 把链接交给已有窗口（`uni_links_desktop` 认这个消息号）；上游有没有新增按 `FLUTTER_RUNNER_WIN32_WINDOW_CLASS` 或窗口标题找窗口的地方（`git grep -n "FLUTTER_RUNNER_WIN32_WINDOW\|FindWindow"`）。
- 已知限制：新界面还没有安装页（第三轮）。exe 名以 `install.exe` 结尾时，core_main 会注入 `--install`、不起服务，runner 按安装页处理，新界面目前写一行日志后退出。M0 只出名叫 `leapgate.exe` 的便携目录，碰不到；做便携打包（03 §1.7 第 5 步）或安装页时处理。

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
- 已知限制：服务器自定义的拒绝原因（`PunchHoleResponse.other_failure`、`RelayResponse.refuse_reason`）在 msgbox 里只是任意正文，和系统错误原文分不开，归 `other`、显示原文。01 §4.3 要的"服务器拒绝了此连接："前缀，得在 `src/client.rs` 加两处挂钩（`_start_inner` 的 `bail!(ph.other_failure)`、`request_relay` 的 `bail!(rs.refuse_reason)`），等 Q3 的挂钩位置交维护者确认时一起问。
- 不在 01 §4.3 里的错误不给码，归 `other`：摄像头、终端的（`No cameras`、`view_camera_unsupported_tip`、`Remote terminal is not supported by the remote side`）第三轮随说明一起补；`No active console user logged on…` 01 没有文案。
- Linux 对端的另几种登录错误（`x11 expected`、`ubuntu-21-04-required`、portal 不可用）归 `other`、显示原文；01 §4.3 只给了 Wayland 登录界面那一条。
- `Failed to listen on` 一律归 `local_port_in_use`。Windows 上端口落在系统保留段时报的是 10013（访问被拒），文案"被占用"不准，但"改用其他端口"的建议仍然对。
- 没认出的正文入表和写日志前截到 200 个字符（按字符边界），因为有的正文来自对端。
- 合并上游时：`git diff <旧> <新> -- src | grep msgbox` 看 msgbox 文本有没有变，变了就改 `reason.rs` 的表和单测（03 §3.8 第 3 条）；`check_if_retry` 的签名或语义变了，核对 `leapgate_msgbox_reason`。

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
- **暂删、`shortcut_model` 改写时（随 M2a/M2b）照上游原样补回**：`models/input_model.dart:426` 本地快捷键分发器里的 `ffi.shortcutModel.onTriggered(action)`（回调留空体）；同文件 `_matchFlutterShortcut` 的匹配部分（:1212-1236，现在只剩 `return null`，因为它读 `ShortcutModel.config`；`shortcut_utils.dart` 因此没复制）；`model.dart:473-477` 的 `kShortcutEventName` 事件不登记。
- `cm_file_model.dart` 推迟到 M3，和 `server_model` 一起复制（它读 `serverModel.clients`、`tabController` 和 `chatModel`）。`ElevationModel` 留在 `model.dart` 里（peer info 和便携服务事件要用）。`QualityMonitorModel.webrtcTransport` 只在 Web 上有值、读 `CachedPeerData`，删了。
- 复制件里的提示：`msgBox` 改成会话通知，key 用 msgbox 的正文（`file_model` 的单向传输错误是翻译 key `one-way-file-transfer-tip`，删除时的出错是原始错误文本）；`JobState.display`、`JobProgress.display` 这类返回界面文字的仍调 core 的 `translate`（经 Rust 翻译），没改。
- `FFI.close` 除了上游 `FFI.close` 的清理，还做了上游页面在关会话前做的 model 清理：文件视图的 `FileModel.close`（`file_manager_page.dart:125`），远程桌面的纹理、图像、光标图（`remote_page.dart:676`、`:684-685`）。纹理在 `start` 里建，跟会话走，不跟页面走。页面自己的（`enterOrLeave`、`hostStopSystemKeyPropagate`、键盘焦点）归 M2a 的会话页。
- `StateGlobal`（`models/state_model.dart`，改写档）只留复制件和 `FfiModel` 用到的：`fullscreen`；`setFullscreen`（经 `appCore.window.setFullscreen`）M1 里没有调用方，留着给 M2a 的全屏；`windowBorderWidth`、`tabBarHeight`、`relativeMouseModeState`、`getInputSource`。工具栏分辨率菜单记的上次选择（`_lastResolutionGroupValues` 和它的三个方法，`FfiModel.handlePeerInfo` 在 :1487 清它）随 M2b 的工具栏一起补。`relativeMouseModeState` 照上游按设备 ID 记：一台设备只有一个远程桌面视图，不会互相覆盖。`tabBarHeight` 照上游是 28（全屏时 0），`CanvasModel` 拿它算画面可用的高度；M2a 的会话页上方占的高度不同时改这里。`consts.dart` 的 `kDragToResizeAreaPadding` 恒为 0（上游只在 Linux 上留改大小的边）。
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
