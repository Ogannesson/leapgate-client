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

主 crate 的 `src/leapgate_hooks.rs` 放需要调用上游私有函数的胶水代码（例如传进 `libs/leapgate` 的握手闭包）：`libs/leapgate` 调不到主 crate 的私有函数，又不想把闭包组装写在热点文件的调用处。上游文件里的挂钩只调用 `leapgate::…` 或 `crate::leapgate_hooks::…`。不要建 `src/leapgate.rs`，会和外部 crate `leapgate` 撞名。05 在这里加了 `race_ice`（控制端：启用条件、到会合服务器的信令 TCP、验 S 签过的被控端 IdPk、检查、KCP connect、`secure_connection`、和上游路径竞速）和 `on_ice_offer`（被控端：spawn、验签解密去重、名额、回 ANSWER、KCP accept、`create_tcp_connection` 用 ICE 选中的远端地址），见 §7。第四期加了子模块 `src/leapgate_hooks/exit.rs`：控制端的出口监听循环 `run`（本地代理握手、第一个本地连接到来时建隧道、登录后按 `exit::after_login` 决定用、停还是冷却）和出口目录的 `get_common`，见 §9。

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

上游直连先赢、ICE 被取消，以及没有物理网卡候选时不打。被控端丢弃 FORWARD（任一步校验不过、名额满）只打 `leapgate ice: dropped a forwarded offer`，每分钟最多一条；检查收发、STUN 校验失败、agent 超时、KCP 交接失败只用 `trace`。名字：类型 `host`/`srflx`/`prflx`，地址族 `v4`/`v6`，网卡 `ethernet`/`wlan`/`other`，结果 `no_answer`/`bad_answer`/`no_pair`/`kcp_failed`/`secure_failed`，原因 `bad`/`offline`/`unsupported`/`relay`/`busy`。

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
- 选中后不换路径：选中的地址失效（ULA、临时地址过期、换网）时 KCP 静默 8 秒后整次重连。
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
- 应用出口（§9）：被控端开着 TUN 代理或全隧道 VPN 时，出口的 DNS 查询和连接仍绑物理网卡地址、从物理网卡出去，不经本机代理和 VPN，不用配规则（契约 B9）。

## 9. 应用出口（第四期）

依据：总仓库 `docs/第四期实施契约/`（README 是总述、两端共用的接口和兼容矩阵；02 是被控端，03 是控制端，01 是服务端目录；B、C 开头的编号指契约清单里的条目）。被控端在设置里打开"允许作为出口"后，Leapgate 控制端可以在它的 TCP 隧道窗口里加一条"出口"映射：本机 `127.0.0.1:<端口>` 上开一个 SOCKS5/HTTP CONNECT 代理，每个本地连接成为同一条多路复用隧道里的一个通道，目标由被控端在自己的物理网卡上解析、过滤、连接。出口映射的登录目标是哨兵 `leapgate-exit.invalid:65536`（`exit::is_exit_target` 只认这一个写法；65536 在普通添加行里填不进去）。两个选项 `leapgate-allow-exit`、`leapgate-exit-allow-nets` 存 Config（服务进程看不到界面进程的 LocalConfig），服务端策略写不进。`libs/leapgate` 版本 0.4.0。下面和契约原文有出入的地方以本文（即代码）为准。

### 9.1 上游挂钩

每处前一行 `// leapgate: …`。除了 K0、`server/port_forward_mux.rs` 的 M-1~M-5、V-1~V-3 的可见性和 `server_page.dart` 那一处判断，其余都是纯插入。

控制端（Rust）：

| 文件 | 位置 | 作用 | 编号 |
|---|---|---|---|
| `src/port_forward.rs` | `listen` 里 `connect_and_login` 的成功分支；`connect_and_login` 的返回类型、`Client::start` 的解构和返回值 | 不再丢掉 `Client::start` 给的 KCP 守卫，转发任务结束后交给 `release_kcp` | K0 |
| `src/port_forward.rs` | `connect_and_login_mux` 的解构和返回值、`LoginOutcome.kcp`、`establish_tunnel` 调 `set_muxed`、`run_legacy` | 同上；多路复用隧道把守卫交给隧道循环，裸管道交给转发任务 | K0（含 03 H-6） |
| `src/port_forward.rs` | 新函数 `release_kcp` | 流结束后对端还在应答就再等，最多 10 秒，让没发完的数据和 FIN 发出去（直接丢守卫会当场停掉 KCP 端点） | K0 |
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

Leapgate 自己的文件里和挂钩配套的：`report/heartbeat.rs` 在开关打开时带 `"exit": true`（关着不带键，放行网段不上报）；`lan.rs` 的 `Nic` 多两个字段 `ipv4_prefixes`（每个 IPv4 的在链前缀长度）、`all_ipv6`（全部 IPv6 单播地址，含已弃用的临时地址），供地址策略认本机地址和链路网段，原有的 `ipv6` 和 ICE 的候选选择不变；`ice/mod.rs` 加 `public_v4`（B11：用 ICE 的 Binding 探测问会合服务器本机的公网 IPv4，不建 ICE 会话）；proto 只有 `libs/base` 的 `Features.leapgate_exit = 1000`，cardo 不动。

上游 Dart（F7 写死的例外，超出要维护者同意；新 Dart 文件都在 `flutter/lib/leapgate/`：`exit_tunnel.dart` 放哨兵常量和出口行控件，`exit_nodes.dart` 是目录对话框，`exit_settings.dart` 是设置页的 part 文件）：

| 文件 | 改动 | 归属 |
|---|---|---|
| `flutter/lib/desktop/pages/port_forward_page.dart` | 1 行 import；`initState`、`dispose` 里 `leapgateExitAttach`/`leapgateExitDetach`（出口行显示连接类型）；Add 按钮后加"添加出口"按钮；`buildTunnelDataRow` 开头把出口映射换成出口行 | 03 |
| `flutter/lib/desktop/pages/connection_page.dart` | 1 行 import；连接菜单 TCP tunneling 后加"出口节点"一项（只在桌面端） | 03 |
| `flutter/lib/desktop/pages/desktop_setting_page.dart` | import 之后 `part '../../leapgate/exit_settings.dart';`；安全设置页权限卡片之后插"出口节点"卡片（只在 Windows，`enabled` 跟解锁状态） | 02 |
| `flutter/lib/desktop/pages/server_page.dart` | 1 行 import；CM 卡片上哨兵目标显示"作为出口"，其余照旧 "Port Forward: …" | 02 |

### 9.2 固定日志

前缀 `leapgate exit:`，文字固定，端到端测试按此查找。日志文件里不出现成功访问的目标和域名。

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
- 系统解析和物理网卡 DNS 同时发起，目标域名会经系统解析器发给本机的代理、VPN 或公司 DNS（答案不采用）；物理网卡 DNS 不读 hosts。
- 单会话缓存上限、主循环发送阻塞时关开关后的断开会推迟；所有通道共用发送队列和一条有序隧道（队头阻塞、KCP 不做拥塞控制、隧道不换路径）。
- 控制端：本地端口不认证；乐观应答；不安全确认框；连接状态不随断开更新；10 秒冷却；空闲不拆、经中继时一直占一对 hbbr 连接；重建照上游认证；Chrome、Edge 要扩展或启动参数；建隧道期间删除映射要等登录结束才停。
- C11 之后 Leapgate 控制端对 1.5.0 以前的原版做不了端口转发和 RDP。
- 拒绝日志每分钟只留第一条加累计次数，还原不了完整的拒绝历史。

### 9.5 合并上游时要核对

- `src/port_forward.rs`：`connect_and_login`、`connect_and_login_mux` 仍从 `Client::start` 拿到 KCP 守卫且没有新的丢弃点；`LoginOutcome` 的字段；`establish_tunnel` 的分支结构（H-5 插在不支持多路复用的那支）；`mux_enabled` 的选项读法；`listen` 的 `Claim::Legacy` 分支。
- `src/port_forward_mux.rs`：`set_muxed` 和 `tunnel_loop` 的签名、spawn 方式；`CHANNEL_WINDOW`、`UPDATE_THRESHOLD`（以后调窗口时 `UPDATE_THRESHOLD` 要钉成字面量 128 KiB，契约 03 §3.11）。
- `src/server/port_forward_mux.rs`：M-1~M-5 五处就是冲突面；核对 `on_open` 里 `retain`、权限检查、规范化和登录目标比较的顺序，`run_controlled_channel` 的签名和连接臂里 `match res` 按值绑定的写法，通道仍由 `tokio::spawn` 跑（`exit::dial::connect` 的 future 必须是 `Send`）。
- `src/server/connection.rs`：`on_message` 登录分支里 `PortForward` 那支（`enable-tunnel` 检查、`normalize_port_forward_target`、`self.lr` 在 `match lr.union` 之前赋值）；`connect_port_forward_if_needed` 读的仍是原始登录目标；端口转发的 `Features` 字面量；`test_delay_timer` 的周期和 `on_close` 的清理链（`port_forward_mux.take()` 后 `close_all`）。
- `src/ui_session_interface.rs` 的 `start_one_port_forward` 签名，`src/flutter_ffi.rs` 的 `main_get_common`，`src/hbbs_http/sync.rs` 的 `handle_config_options`。
- 四个上游 Dart 文件的挂钩位置（§9.1），尤其 `desktop_setting_page.dart` 的 import 块（`part` 必须在全部 import 之后）和 `_SafetyState.build()` 的卡片列表。
