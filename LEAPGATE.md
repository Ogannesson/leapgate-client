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

依据：总仓库 `docs/research/第三期/04-TUN下的局域网直连.md`（读码结论、mihomo/sing-tun 的路由行为、选网卡规则都在里面，动手前先读）。做法是多候选地址，改 proto 和服务端转发。

### 3.1 问题

局域网路径（服务端发现两端公网出口相同 → `FetchLocalAddr` → 被控端回 `LocalAddr` → 服务端转成 `PunchHoleResponse{is_local}` 给控制端）里，被控端报的 `local_addr` 是它连 hbbs 那条 socket 的本地地址，控制端连的时候也把源地址绑在自己连 hbbs 那条 socket 的本地地址上。开 TUN 代理（Clash Verge / mihomo 等）的机器上，这两个地址都是虚拟网卡的（例如 `198.18.0.1`），直连必然失败、1 秒后退回中继。

### 3.2 协议（在 leapgate-cardo）

- `LocalAddr.leapgate_local_addrs = 1000`（`repeated bytes`）：被控端的局域网候选地址，`AddrMangle::encode` 编码（和 `local_addr` 同一种编码），最好的在前，端口都等于 `local_addr` 的端口。
- `PunchHoleResponse.leapgate_local_addrs = 1000`：服务端在 `is_local` 的响应里原样带给控制端。
- 原版 hbbs、原版客户端遇到这两个字段直接忽略。

### 3.3 被控端（`handle_intranet`）

- 新增 `libs/leapgate/src/lan.rs`，提供 `local_candidates(sock_local: SocketAddr) -> Vec<SocketAddr>`：
  - 只取 IPv4。候选来自物理网卡：排除虚拟/隧道网卡（Windows `IfType` 53/131/23/24，Wintun 是 53；接口名 `utun*`、`tun*`、`Mihomo`、`wintun` 一类）、`198.18.0.0/15`、`100.64.0.0/10`、回环、`169.254.0.0/16`；要求网卡有默认网关（顺带排除 WSL/Hyper-V 的 vEthernet）。
  - 排序：有线在前，再按链路速度；去重；最多 8 个。端口都用 `sock_local` 的端口。
  - `sock_local` 本身不是虚拟地址时，它排第一（和上游行为一致），后面再跟其他物理网卡地址。
  - 网卡枚举用 `GetAdaptersAddresses`（`windows` crate，和主 crate 同版本）。在 Windows 上实测：`default-net 0.14.1` 的 `get_interfaces()` 每次 4.2~5.3 秒，原因是它对一块断开但配了静态网关的网卡发 `SendARP` 等到超时，而且整个跳过 IfType 53 的网卡；`GetAdaptersAddresses` 每次 5~10 ms，还能读到在线状态、借此排除断开的网卡。不能用 `default_net::get_default_interface()`：开 TUN 时它选中的正是 TUN。
- 挂钩：组 `LocalAddr` 时，`local_addr` 改成候选的第一个（`sock_local` 是物理地址时就是它自己，不变），`leapgate_local_addrs` 填全部候选。
- 监听：被控端随后在 `local_addr` 的 IP:端口上开 18 秒、只收一条的监听（上游 `src/server.rs` `accept_connection_`）。候选里有和 `sock_local` 不同的 IP 时，改为监听 `0.0.0.0:同一端口`，否则照上游（Windows 上实测能在同一端口上绑 `0.0.0.0`）。监听地址由纯函数 `leapgate::lan::listen_addr(candidates, sock_local)` 算出，候选列表在 `handle_intranet_` 里算一次，作为新参数经 `accept_connection` 传到 `accept_connection_`（这处签名改动可以接受：`pub(crate)`、只有一个调用方）。不在发出 `LocalAddr` 之后再枚举网卡：那会把"发出地址到开始监听"的空档从微秒拉长到 5~10 ms。
- 没有任何物理候选时，一切照上游。

### 3.4 控制端（收到 `is_local` 的 `PunchHoleResponse`）

- `leapgate_local_addrs` 非空时：对全部候选并发发起 TCP 连接，不绑定源地址（局域网网段的路由比 TUN 的更具体，自然从物理网卡出去；依据见笔记 04），TCP 连接的等待和上游局域网的 1 秒一致；第一个完成 TCP 连接**并且**完成安全握手的胜出，其余丢弃。握手另有 3 秒上限：被控端的监听只收一条连接，其余连上的候选会排在队列里永远等不到握手回应，没有上限就要等上游的 `READ_TIMEOUT` 才回落中继。
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
- 端到端：两台 Windows（都开 Clash Verge TUN、都装 Leapgate），连同一个 leapgate-server；期望服务端 `conn_attempt.outcome = direct_lan`，控制端日志里连的是物理网卡地址。

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
- proto：`PunchHoleRequest.leapgate_from_id = 1000`（string，在 leapgate-cardo 客户端线），`rendezvous.proto` 文件头注明 Leapgate 字段占 1000~1999。

### 5.2 心跳里的字段

- 请求：`routing_rev`（手里那份候选列表的 rev，没有为 0）；`probes`（最近一轮有效测量，没有就省略）：`{ routing_rev, age_s, rtt: { 原串: 毫秒 }, down: [原串] }`。只有这一轮的 rev 等于当前列表、并且结束不超过 900 秒才发。
- 响应：`routing`（`{ rev, probe_interval_secs, relays }`，服务端只在请求的 `routing_rev` 和它的不同时下发）。`on_heartbeat_ok` 每次成功的心跳都调：没配 Key（`sign::server_pk()` 不是 `Ok(Some(_))`）时什么都不做，不采用 `routing`、不刷新确认时间，防明文 HTTP 上的中间人往 `relays` 里塞任意地址、把设备当端口扫描器；配了 Key 时刷新确认时间，`routing` 解析失败整个忽略，`probe_interval_secs` 限在 60~3600，`relays` 截到 32 台；rev 变了就换列表、清掉旧结果，第一次拿到非空列表时起测速线程。
- `reset()`（API 根地址变了、能力判为不支持时由 `report` 调）清空状态。

### 5.3 测速线程（`route/probe.rs`）

- 进程内一个专用 `std::thread`（`Once`），阻塞的 `std::net`，不用 tokio：心跳跑在 `sync.rs` 的单线程运行时上，那里每个 tick 还会同步调阻塞函数，计时会被拉长。
- 测的条件：有非空列表、15 分钟内有成功的心跳。新列表（rev 变了）先等 10~30 秒随机时间再测第一轮，之后每轮间隔 `interval × (0.9~1.1)`；状态变了用 `Condvar` 唤醒重算。
- 每轮开头：开了代理（`Config::is_proxy()`）、开了 WebSocket（`use_ws()`）或没配 Key 时不测，并清掉旧结果。
- 测速和真实中继连接走同一条路（契约 02a）：不绑本地地址，系统解析、系统路由，开着 TUN 就进 TUN、由代理按它的规则转发。代理会在本地或路由器上先完成握手、之后才去连中继，所以不计握手时间，计的是中继关连接：hbbr 的 `make_pair_` 收到不是 `RequestRelay` 的首帧就直接返回，不打日志。
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
- 测速不看网卡（§5.3），原来给它用的 `physical_snapshot` 已删。`is_physical` 的 IPv6 分支因此暂时只有测试在用，留着不动。

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
- 位置：leapgate-cardo 客户端线（`leapgate/client`）。新文件 `src/leapgate_id.rs` 的 `salt`：`sha256("leapgate-auto-id\0" ‖ 上游 ID 的 4 字节小端)` 取前 4 字节按小端转 `u32`，再 `(h & 0x0FFF_FFFF) | 0x1000_0000`，结果固定 9 位（268435456~536870911）。`src/config.rs` 的 `get_auto_id` 在 `id &= 0x1FFFFFFF;` 后加 2 行挂钩；`src/lib.rs` 加模块声明，安卓和 iOS 不编（那里上游本来就用随机 ID）。不放 `libs/leapgate`，因为 `get_auto_id` 在 hbb_common 里，而 `libs/leapgate` 依赖 hbb_common。服务端不生成 ID，服务端线不放。
- 影响：只有第一次生成 ID 的设备（配置里 `id` 为空）拿到加盐后的 ID，已有 ID 的设备不变。`allow-hostname-as-id` 打开时用主机名，上游收到 `UUID_MISMATCH` 时换的随机 10 位 ID，都不经过这里。日志 `Generated id` 打的是加盐后的值。
- 已装 Leapgate、又要和原版指向同一服务器的机器：停掉 Leapgate，删掉配置文件 `Leapgate.toml`（安装版是服务进程那份）里的 `id` 和 `enc_id` 两项，再启动，Leapgate 按加盐后的规则重新生成 ID。界面上的"修改 ID"在 leapgate-server 上不可用（回 `NOT_SUPPORT`）。
- 测试：`leapgate_id::tests` 一条，三组固定输入的输出和另一种实现（Python）算出的值逐字一致，都是 9 位、和输入不同。端到端的测法见契约 03 §6 第 4 项。

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

- 启用条件，全部满足才出 ICE：不是只允许入站；对端不是直连 IP 或 `域名:端口`；不是 `id@server?key=`（`other_server` 为空）；不强制中继（含 `/r`、代理、WebSocket）；没开 `disable-udp`；`enable-udp-punch` 和 `enable-ipv6-punch` 至少开一个（上游 `get_udp_punch_enabled`、`get_ipv6_punch_enabled`，控制端本地选项；两个都关说明用户不要 UDP 直连）；有可信 Key（`get_rs_pk` 能解出）；能力缓存含 `ice`。连接类型不特判。
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
- 被控端的静默判断是 20 秒、没有 consent 保活：控制端还在、但链路断了约 20 秒以上（换 Wi-Fi、睡眠唤醒）时，被控端照样关会话，上游给控制端的关闭原因发不出去。不用 8 秒，是因为下面两条（数值是读码估算，假设控制端本机网络正常、被控端地址没变、用密码登录，没有实测；点击确认的会话重连时要被控端再点一次确认，效果等于锁屏）：
  - 远程桌面这类走 `io_loop` 的会话：控制端静默满 8 秒就自动重连，重连那一轮的打洞请求在 3 秒、9 秒各重发一次，18 秒放弃（报不能自动重试的错误）。对方要求了"会话结束后锁屏"时，上游靠"旧连接关闭时，同一会话的新连接已经登录"来避免误锁（#16124 的 `session_reconnected`）。被控端 8 秒就关的话，重连还没登录，断链只要长到触发重连就几乎都会锁屏。20 秒时，会合服务器在近处，断链约 17 秒以内基本不锁；在远处（往返约 200 毫秒），约 11 秒以内不锁、11~19 秒有时会锁（看 9 秒那次重发送到后，上游路径多快接上），约 19 秒以上会锁。以前的 30 秒档也只扛到 9 秒那次重发（重连那一轮最后一次发送）的时刻：远处约 18~19 秒，近处约 17 秒，所以近处和 20 秒时一样；再长，重连那一轮在约 27 秒失败、会话结束。要在远处服务器下也完全追平以前，阈值要约 23 秒。断的是控制端本机网络时，重连常当场报不能自动重试的错误，阈值多少都一样。被控端关旧连接时如果正好卡在发送上（走发送失败那条路，上游不锁），就不锁，所以准确说是"通常会锁"。挂钩读不到 `lock_after_session_end`，不改上游文件没法只对开了锁屏的会话放宽。
  - 端口转发（mux）和出口隧道：控制端不看 KCP 静默，空闲时靠 `tunnel_loop` 的 18 秒读超时发现断链，实际能扛约 11~18 秒的断链（受 KCP 重传退避影响）。被控端 20 秒才关，不比这个早，所以和以前一样；8 秒时约 5~9 秒的断链就会断，而且被控端先关、控制端要到 17~18 秒才发现。断链期间一直有本地流量时，以前能扛约 20~29 秒，20 秒时约 18~21 秒，略短。断链超过这个时长后，控制端要到"最后一次本地事件 + 18 秒"和 kcp-sys 约 60~70 秒的回收里较早的那个才发现，期间本地连接挂着，这一点以前也一样。
  - 非复用的端口转发（旧式映射、旧版 RDP）走不到这里：ICE 只在两端都是 Leapgate 时出现，Leapgate 被控端对非复用的端口转发回 `MSG_NEED_MUX`（§9.1）。
- UDP 被封的网络，以及两端都是对称 NAT、端口受限对对称 NAT 又没有 IPv6 时打不通，走上游路径和中继。
- 被控端的 ICE 可以被人占满：知道它的 ID 和服务端 Key 的人能让服务端不断转发 FORWARD，占满 8 个名额或去重表，这段时间 ICE 不可用、走上游路径。
- 隐私面：任何知道被控端 ID、服务端 Key、被控端又在线的人，都能拿到它物理网卡上的私网 IPv4、ULA、每个 /64 一个临时全局 IPv6 和 srflx（跨网时也给）；链路上看不到，只有服务端看得到。ICE 有意不经系统的 VPN/TUN，开着全隧道 VPN 时，两端物理网卡的公网出口（srflx 或全局 IPv6）和局域网地址照样交给服务端和对端；上游走 VPN 时对端只看得到 VPN 的出口。
- 网卡过滤靠 IfType 和关键字：描述不在表里、IfType 又报 6 或 71 的新虚拟网卡会被当成物理网卡，最坏只是一对检查失败。
- 被控端系统时钟往回跳、心跳还没改回偏移时，链路上截获过的旧 FORWARD 可能被重放一次，后果只是起一个空 agent、占一个名额到 `AGENT_TTL`。
- 上游先报错而 ICE 还在跑时要等 ICE，最长约 16 秒（信令 3 秒和收集并行、等 ANSWER 4 秒、检查 3 秒、KCP 和身份握手各 3 秒）；对端离线、Key 不对这类常见错误 ICE 一两个往返就失败。
- 非 Windows 平台枚举不到物理网卡，不出 ICE（第一阶段只做 Windows）。
- 会合服务器离两端很远时 ICE 可能输给中继窗口：ICE 比上游中继多几个经过会合服务器的往返（两端各建一条信令连接并做密钥交换、OFFER/FORWARD/ANSWER）。实测会合服务器到两端往返约 200 毫秒时，ICE 选中要 2.2~3.7 秒，上游中继约 1.3 秒给出、再等 2.5 秒，200 次里 6 次（3%）输给窗口，走中继、控制端打 `lost the relay window`。会合服务器离得近时快得多。
- 被控端会话期间句柄缓慢增长，和 ICE 无关：实测被控端主进程在会话开着时每秒约多 0.5 个内核句柄（Mutant、Section 成对），关掉会话、空闲后不回落，线程数和专用字节平稳；每次约 25 秒的连接净增约 9 个，控制端开、关 ICE 各 200 次斜率相同（都是每次 9.0 个）。来源后来查明在显卡驱动：NVIDIA 的 `nvspcap64.dll` 每次 `DuplicateOutput` 漏一对 Mutant 和 Section；被控端的 DXGI 采集遇到 ACCESS_LOST 时会整条重建采集和编码（上游 1.5.0 起的恢复逻辑），失效越频繁漏得越多。本仓库的代码里没有按事件创建互斥量或共享内存的地方。

## 8. 不配也能用：自动降级与可选优化

Leapgate 不要求用户配置任何代理规则。

- 路由第二级（§5）：测速和真实中继连接走同一条路，量到中继关连接为止，本机 TUN、路由器透明代理、全隧道 VPN 下量到的都是真实中继路径的往返，不需要任何配置。
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

上游 Dart（F7 写死的例外，不在下表的上游 Dart 文件不改；新 Dart 文件都在 `flutter/lib/leapgate/`：`exit_tunnel.dart` 放哨兵常量和出口行控件，`exit_nodes.dart` 是目录对话框，`exit_settings.dart` 是设置页的 part 文件）：

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

依据：总仓库 `docs/新界面/03-实施方案.md`（下称"03"），界面行为以 `01-内容与逻辑说明.md`、`02-第二轮内容与逻辑说明.md` 为准，令牌和图标以 `docs/新界面/样稿/A-基础.html` 为准。新界面放在 `leapgate_ui/`（`core` 包沿用上游包名 `flutter_hbb`，放桥、models、会话和状态；`app` 包 `leapgate_ui` 放页面、组件、令牌、Windows 启动代码），和上游 `flutter/` 互不引用。除分段延迟（Q13）单独写契约外，03 §6.1 的表加本节就是新界面各 Rust 项的实施契约；每项动手前把挂钩位置写进本节，合入时补上取值。

### 10.1 规则

- **上游 `flutter/` 一行不改**（architecture §3.3）。评审规则：新界面的分支合入 main 之前，`git diff main -- flutter/` 必须为空（切换之后那次还原除外，03 §7.3）。构建会打补丁、改写 `flutter/` 下被跟踪的文件，所以在构建过的 worktree 里只 `git add <具体路径>`，不用 `git add -A`、`git commit -a`。编旧界面还会在 `flutter/` 下留下块 2 的三个未跟踪文件（`flutter/lib/generated_bridge_leapgate.dart`、`flutter/macos/Runner/bridge_generated_leapgate.h`、`flutter/ios/Runner/bridge_generated_leapgate.h`），构建 worktree 把它们加进 `.git/info/exclude`（不改上游的 `.gitignore`）。
- **复制件头上写来源**：从上游复制的每个文件第一行写来源，例如 `// 上游：flutter/lib/models/input_model.dart@bd9262397（只删界面调用，不格式化）`。分三档：原样复制、只删界面调用、改写（03 §3.2）。合并上游 tag 之后，总仓库的 `scripts/windows/sync-ui-upstream.ps1`（计划中）对前两档做三方合并（base = 头上记的提交里的上游原件，ours = 副本，theirs = 新 tag 的上游原件，`git merge-file`），冲突留给人，成功后改头上的提交号；改写档列出 `git log <旧>..<新> -- <上游文件>` 逐个人工判断。来源只记在文件头上，不另建对照表。来源行通常是第一行；有格式要求的文件放在允许的第一个位置（`Runner.rc` 在 `#pragma code_page(65001)` 之后，`runner.exe.manifest` 在 XML 声明之后），同步脚本按内容（`上游：` 开头的注释）找来源行，不按行号。
- **一个上游文件混了两档时**（`models/model.dart`：`ImageModel`、`CanvasModel`、`CursorModel`、`QualityMonitorModel`、`RecordingModel`、`PeerInfo` 等属于只删界面调用，`FfiModel`、`FFI` 属于改写）：整份复制到 `core/lib/models/model.dart`，保留的类按只删界面调用处理，改写的两个类整段删掉（`FFI` 前面的 `ConnType` 跟着 `FFI` 走），改写版放进 `lib/leapgate/` 下的新文件，沿用原类名和复制件用到的成员名。来源行写"只删界面调用；`FfiModel`、`FFI` 改写到 `lib/leapgate/<文件名>`"（`FFI` 在 `lib/leapgate/session.dart`）。同步脚本照常对它做三方合并；上游改了那两个类，会以冲突的形式冒出来，由人工移植到改写文件。
- **复制件和上游原件的差异保持最小**：`core` 原样使用上游的 `flutter/analysis_options.yaml`；"原样复制""只删界面调用"两档不跑 `dart format`、`dart fix`，不顺手修 lint；`flutter analyze` 的"新告警"以上游原件为基准算。评审时看 `git diff --no-index <上游原件> <副本>`，"只删界面调用"那一档的差异应该只有界面调用和导入。
- **废弃 API**（03 §8.8）：新写的代码和"改写"档的文件不用最新 stable 已标记废弃的 API，最新 stable 检查报出的这类提示当场处理。"原样复制""只删界面调用"两档按上一条不改：上游原件在同一版 SDK 下也报的提示单独记下，等上游改了随三方合并带过来，到升级 Flutter 时还没改的在升级时处理；某个 API 在最新 stable 里已经删掉、复制件编不过时，照最小差异改，并在文件头的来源行后注明。
- 新的 FFI 函数只放 `src/leapgate_ffi.rs`（frb 的第二个块），逻辑在 `libs/leapgate`，按领域分段追加；Leapgate 自己的事件用块 2 的 `StreamSink`，不往上游的 `InvokeUiSession` 加方法。上游文件里的挂钩照 §1 的纪律写。
- 公开仓库里不写真实 IP、域名、设备 ID（测试夹具和文档用文档地址段）。

### 10.2 验收记录的写法

验收记录不在公开仓库（§10.5）。

### 10.3 frb 第二个块（F0）

- 块 1 是 `src/flutter_ffi.rs`（上游，类名 `Rustdesk`），块 2 是 `src/leapgate_ffi.rs`（类名 `Leapgate`）。块 2 的 Rust 输出在 `src/leapgate_bridge/`（目录自带 `.gitignore`），由 `leapgate_ffi.rs` 用 `#[path]` 声明，不改 `src/lib.rs`。生成参数见总仓库 `scripts/windows/build-client.ps1` 的 bridge 步。Rust 侧两个界面共用，所以编哪个界面都生成两块：旧界面的 Dart 和 C 头落在 `flutter/`（块 2 的 Dart 旧界面不用，也不提交），新界面的落在 `leapgate_ui/core/`。
- 试验结论：
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
- 已知限制：exe 名以 `install.exe` 结尾时，core_main 会注入 `--install`、不起服务，runner 按安装页处理，新界面写一行日志后退出。构建脚本出的便携单文件叫 `leapgate-‹版本›-x86_64.exe`，不带 `install`，只有用户自己把 exe 或便携包改名成以 `install.exe` 结尾、或者手动带 `--install` 才会碰到。安装从便携版主页的"安装"卡和安装页发起（§10.16、§10.18）。
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
- 不在 01 §4.3 里的错误不给码，归 `other`：摄像头、终端的（`No cameras`、`view_camera_unsupported_tip`、`Remote terminal is not supported by the remote side`）尚未给码；`No active console user logged on…` 01 没有文案。
- Linux 对端的另几种登录错误（`x11 expected`、`ubuntu-21-04-required`、portal 不可用）归 `other`、显示原文；01 §4.3 只给了 Wayland 登录界面那一条。
- `Failed to listen on` 一律归 `local_port_in_use`。Windows 上端口落在系统保留段时报的是 10013（访问被拒），文案"被占用"不准，但"改用其他端口"的建议仍然对。
- 没认出的正文入表和写日志前截到 200 个字符（按字符边界），因为有的正文来自对端。
- 合并上游时：`git diff <旧> <新> -- src | grep msgbox` 看 msgbox 文本有没有变，变了就改 `reason.rs` 的表和单测（03 §3.8 第 3 条）；`check_if_retry` 的签名或语义变了，核对 `leapgate_msgbox_reason`。

#### Q3 连接路径和中继名

下文的行号以 `7bc0abd92` 为准，取舍见末尾"取舍"。按 03 §6.1 Q3、§12 IQ14。界面要什么见 01 §4.2（第二级的"路径""中继服务器""传输"三项）。

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
- 01 §4.2 要求不区分 ICE 和上游打洞，这里只按"实际走的是不是局域网地址"分 `lan` 和打洞。全局 IPv6 即使两端在同一 /64 也算打洞直连（IPv6），和上游 IPv6 打洞一致。srflx 的对端地址都是公网地址，归打洞。
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

##### 取舍

1. Q3 的挂钩放 `create_relay`，不放 03 写的 `request_relay`（理由见第 2 节）。
2. C3 的"服务器拒绝了此连接："前缀要做（`src/client.rs` 再加 2 处，共 3 处）：拒绝原因写进本表、由 `leapgate_session_connection` 返回，错误原文不动、旧界面不受影响。没选的备选：在 `race_ice` 里把错误正文改写成 `Server refused the connection: <原因>`，代价是旧界面也显示这句英文。
3. ICE 选中的对端地址是私网 IPv4 或 ULA 时判成 `lan`（显示"局域网直连"，显示的是实际走的网络）。没选的备选：ICE 一律按地址族显示打洞直连，和旧界面的标签一致。

### 10.5 验收记录

验收记录不在公开仓库。

### 10.6 core 的结构（M1）

03 §3.3 第 1、2、4、5、6、8 条在 `core/lib/leapgate/` 落成下面几个文件，复制进来的 models 和改写的 `FfiModel` 接在这上面。

| 文件 | 放了什么 | 怎么接 |
|---|---|---|
| `session.dart` | 会话对象 `FFI`（改写档，沿用上游类名和 `sessionId`、`id`、`connType`、`closed` 这几个成员名）和 `ConnType`（从 `model.dart` 挪来，`.index` 传给 Rust，顺序不能动）；`events`、`notices`、按会话记的状态、`connToken`、`ask`、`start`、`close` | 每个会话自己的 model 字段（`imageModel`、`ffiModel`、`canvasModel` 等）照上游写成 `late final`，在构造函数里用 `WeakReference(this)` 建；`start` 里各 model 的初始化、`close` 里的清理（放在 `bind.sessionClose` 之前）、`_onMessage` 里 `Rgba`、`Cursor`、`Texture` 三种消息，照上游 `FFI.start`、`FFI.close` 补进去 |
| `session_registry.dart` | 会话注册表：一台设备一个标签，标签里每个视图一个会话；`open`、`close`、`closeDevice`；同一设备再开别的视图时用标签里已有会话的连接令牌；`singleSession` 时（手机，01 §8 Q8）开新会话前关掉已开的 | 只有它创建、启动、关闭 `FFI`；页面不再自己 `FFI(...)`、`start`、`close` |
| `app_core.dart` | 全局持有者 `AppCore`（窗口接口、注册表、全局轻提示、提问接口），全局变量 `appCore` 由 app 的 `main` 设 | 上游 `FFI` 里标着 global 的 model（`serverModel`、`abModel`、`groupModel`、`userModel`、`peerTabModel`、三个 `Peers`、CM 的 `cmFileModel`）不进会话对象，随用到它们的功能加到这里（§10.10、§10.11） |
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

接口里没有的：`windowManager.minimize`、`close`（`server_model.dart:169`、`:584`，CM 是单独的进程，见 §10.10）；`model.dart:755-756` 的关闭全部窗口（URL 动作，只来自 macOS 和 Linux）；窗口标题（跟着当前标签，在 app 的外壳里设）；`chat_model.dart:319-332` 的聊天窗口大小（`chat_model` 只留消息存储）。

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
  - 已知限制：01 §4.1 进度条的"查找设备""建立连接"两步 Rust 不区分（`connection_ready` 之前没有任何事件），合成 connecting 一种，要分就得在 Rust 加挂钩，不做；提权通知上的"请求提升权限"按钮弹的选方式对话框由工具栏提供（§10.9）；"已等待多久"、等画面超过几秒后加的那行说明，由页面自己计时；要密码时 `sessionGetRemember` 返回之前，如果 `wait-remote-accept-nook` 先到，返回后阶段会被打回密码框（上游也一样，修要加状态，不修）。
  - **接 V1 时要处理**（标签切换）：第一帧到之前标签就被隐藏时，`showConnectedWaitingForImage` 起的 1.5 秒计时会误发空的系统登录密码（隐藏后 Rust 不再推帧）。接 V1 时，隐藏期间不按"没画面"处理（隐藏时取消计时，切回时如果仍在 `waitForFirstImage`，再起一次），见 §10.8 的 V1 一条。
- Rust 推事件走两种流：每个会话自己的流（`sessionStart`），和全局流（`startGlobalEventStream`，`PlatformFFI.init` 里开始收）。全局流的事件先给 `PlatformFFI.tryHandle`，没人认领的交给 `setEventCallback` 设的回调（`models/native_model.dart:274-277`）。新界面的回调是 `AppCore.events`（`SessionEvents(stream: 'global')`），在 `AppCore` 的构造函数里设；app 的 `main` 先建 `AppCore` 再调 `platformFFI.init`，所以一开始的事件也不会丢。两种流没人处理的名字都按"每种流每个名字一次"写日志，日志里写明是哪种流。
- 会话流上 M1 没登记、由各自的块登记的：`screenshot`（:468，:484-550，"另存为"要选文件的对话框）、`printer_request`（:466，:552-722，要选打印机的提问）、`switch_back`（:407-410）；聊天和语音的 6 个（`chat_client_mode`、`chat_server_mode`、`on_voice_call_*`，:362-367、:416-428）由 M2b 登记（`chat_model` 改写，§10.9）；`terminal_response`（M9b，§10.18）；`selected_files`、`send_emptry_dirs` 只在 Web 上有。
- 全局流上没登记的：CM 的 `add_connection`、`on_client_remove`、`show_elevation`、`update_voice_call_state`、`cm_file_transfer_log`（`src/flutter.rs:1534-1596`）在 M3，`sync_peer_hash_password_to_personal_ab`（`src/client.rs:3742`）在 M4，都登记在 `appCore.events` 上，不登记在会话的表上；`on_url_scheme_received`（`src/server.rs:776`，只来自 macOS 和 Linux）。
- M2a 的会话页要做的：`canvasModel.initializeEdgeScrollFallback(this)`（`desktop/pages/remote_page.dart:179`，要页面的 TickerProvider）。会话 model 的其余初始化已在 `FFI.start` 里：首帧时 `activateLocalCursor`（只远程桌面）和录制状态（`remote_page.dart:160-165`、`view_camera_page.dart:105-110`），`checkShowQualityMonitor`（`remote_page.dart:198`）。
- **照上游原样保留的快捷键部分**（`shortcut_model` 复制进 core 时，见 10.9 会话·工具栏）：`models/input_model.dart:426` 本地快捷键分发器里的 `ffi.shortcutModel.onTriggered(action)`；同文件 `_matchFlutterShortcut` 的匹配部分（:1212-1236，读 `ShortcutModel.config`；`shortcut_utils.dart` 一并复制）；`model.dart:473-477` 的 `kShortcutEventName` 事件在 `leapgate/session.dart` 登记；会话关闭时照上游 `model.dart:4397` 调 `shortcutModel.clear()`。
- `cm_file_model.dart` 归 M3，和 `server_model` 一起复制（它读 `serverModel.clients`、`tabController` 和 `chatModel`）。`ElevationModel` 留在 `model.dart` 里（peer info 和便携服务事件要用）。`QualityMonitorModel.webrtcTransport` 只在 Web 上有值、读 `CachedPeerData`，删了。
- 复制件里的提示：`msgBox` 改成会话通知，key 用 msgbox 的正文（`file_model` 的单向传输错误是翻译 key `one-way-file-transfer-tip`，删除时的出错是原始错误文本）；`JobState.display`、`JobProgress.display` 这类返回界面文字的仍调 core 的 `translate`（经 Rust 翻译），没改。
- `FFI.close` 除了上游 `FFI.close` 的清理，还做了上游页面在关会话前做的 model 清理：文件视图的 `FileModel.close`（`file_manager_page.dart:125`），远程桌面的纹理、图像、光标图（`remote_page.dart:676`、`:684-685`）。纹理在 `start` 里建，跟会话走，不跟页面走。页面自己的（`enterOrLeave`、`hostStopSystemKeyPropagate`、键盘焦点）归 M2a 的会话页。
- `StateGlobal`（`models/state_model.dart`，改写档）只留复制件和 `FfiModel` 用到的：`fullscreen`；`setFullscreen`（经 `appCore.window.setFullscreen`，会话页的全屏用它）；`windowBorderWidth`、`tabBarHeight`、`relativeMouseModeState`、`getInputSource`。工具栏分辨率菜单记的上次选择（`_lastResolutionGroupValues` 和它的三个方法）随工具栏照上游保留，`leapgate/ffi_model.dart` 的 `handlePeerInfo` 照上游 :1487 在每次 peer info 后清它。`relativeMouseModeState` 照上游按设备 ID 记：一台设备只有一个远程桌面视图，不会互相覆盖。`tabBarHeight` 照上游是 28（全屏时 0），`CanvasModel` 拿它算画面可用的高度；会话页上方占的高度不同时改这里（§10.8）。`consts.dart` 的 `kDragToResizeAreaPadding` 恒为 0（上游只在 Linux 上留改大小的边）。
- core 的 `flutter analyze` 用 `--no-fatal-infos` 跑。基线是 92 条 info，全是复制件从上游原件带来的（同一份原件在同样规则下也报，主要是 `RawKeyEvent` 和 `window` 的废弃提示），只看新增的。

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
- **写入的返回值**：`set`、`setBool`、`toggle` 返回是否保存成功。`config.set` 的返回值是 S9（03 §6.1）给的真值（§10.13），其余写入桥调用返回就算成功；桥抛的异常照常往上抛（由 M0 的全局错误处理写进日志），不吞。
- **变更通知**：`listenable(key)` 在经同一个对象写这个键之后触发（值没变也触发），监听方自己重新读。别处改的值不通知：服务进程、服务端策略（心跳策略直接改 Config）、上游界面。需要跟上这类变化的页面在显示时重新读。
- **接入办法**（每块开工的第一步）：
  1. 列出这一块页面要用的上游 `bind.*` 选项调用，对照两份说明去掉已经不做的功能。
  2. 选项键用常量，不在页面里写字面值：上游有的照上游名字和值补进 core 的 `consts.dart`（以后复制进来的 models 直接能用），Leapgate 新加的键放在用它的 core 文件里。
  3. 普通读写直接用 `config` / `local` / `peer(id)` / `SessionOptions`；有特殊读写规则的（例如上游 `main_set_option` 对 `stop-service` 会去装卸服务、`leapgate-allow-exit` 只认 "Y"）在 core 里包一个具名方法，页面调方法。
  4. 选项以外的 `bind.*`（例如画质 `sessionGetImageQuality`、Flutter 选项 `sessionGetFlutterOption`）按领域收进对应的 model，不往 `OptionsModel` 里堆；作用域本身不够用时（例如 LocalConfig 的 `ui_flutter`）再加一个 `OptionScope` 子类。

### 10.8 M2a 的分工约定

M2a 是最小控制端：连接框、最近列表、会话标签、画面和输入、连接状态面板、基础工具栏、关窗确认，另含 V1、全屏和"重启远程设备"；连接进度合成"建立连接 → 验证身份"两步。界面行为以 01 为准（P1 区块 A、E、F，P2 区块 A~E、G，§2.1、§4.1、§4.3、§4.4、§4.5、§7.6），样稿 `A-P1.html`、`A-P2.html`，令牌和图标以 `A-基础.html` 为准。

**分支和文件边界**（都从 `ui/m2a` 切，做完合回 `ui/m2a`）

| 分支 | 块 | 只改这些 |
|---|---|---|
| `ui/m2a-ds` | 组件 | `app/lib/widgets/`（新组件；M0 组件缺什么补什么）、`app/lib/gallery_main.dart`、`app/test/` 里组件的测试 |
| `ui/m2a-session` | 会话块 | `app/lib/shell/`、`app/lib/pages/session/`、`app/lib/main.dart`、core 的 `leapgate/session.dart`、`leapgate/session_registry.dart`、`models/state_model.dart` 和它们的测试；`app/windows/` 只在链接和窗口前台确实需要时改 |
| `ui/m2a-home` | 主页块 | `app/lib/pages/home/`、core 的新文件（"输入像不像地址"的判断等）、`leapgate/local_status.dart`、`leapgate/app_core.dart`（只加最近列表的 model）和它们的测试 |

- 会话块和主页块都要往 `app/lib/l10n/app_zh.arb`、`app_en.arb` 加键：会话块的键以 `session`、`conn`、`toolbar`、`closing` 开头，主页块以 `home`、`connectBox`、`recent` 开头，各自加在文件末尾，冲突在整合时解决。两种语言同时加，文案照 01 §7.6 和术语表；01 里写好的句子逐字照抄，没写的按 §7.6 写，并在提交说明里列出新写的句子。
- 会话块和主页块先用 M0 的组件和简单的占位控件把逻辑写通，整合时换成组件块的组件。占位控件不求好看，但行为测试要能按文字和语义标签找到它们。
- 外壳和主页的两条约定：外壳把非当前标签（包括被会话标签盖住的主页）包在 `TickerMode(enabled: false)` 里，主页靠它停掉在线状态查询（`IndexedStack`、`Offstage`、`Visibility.maintain` 都不关 ticker）；主页切走时不销毁。全局轻提示的 key 是上游翻译 key（例如 `Copied`），文案在 ARB 里，由外壳显示。
- 本机区 ID 旁的"复制"和双击 ID 复制（01 区块 A）归主页块。
- 共用接口 `app/lib/shell/navigation.dart`（`ui/m2a` 上已有）：`mainNavigation.connect(id, …)` 开会话或切到已有标签；`mainNavigation.showHome(focusConnectBox:, connectBoxText:)` 回主页；主页监听 `connectBoxFocusRequests`。会话块实现，主页块只调用，测试里换成假的。

**组件约定**

- 组件只管画：输入是普通的值和回调，不引用 core 的 model、会话对象和 `bind`（身份色这类纯函数可以用）；文字全部由调用方传进来（照 M0 `LgTitleBarLabels` 的做法），组件里不写死文案、不读 `AppLocalizations`。
- 每个可操作的地方带语义标签：`Semantics` 的 label 用它显示的文字，只有图标的用它的名字。讲述人和端到端的 UI Automation 脚本都靠它找控件。
- 合并语义的容器（`MergeSemantics`，以及自己包了一层的 `MenuItemButton` 这类上游控件）里不放带浮层的组件（悬停提示、弹层的锚点）：锚点被合并后照样发给引擎，成了从根走不到的孤儿，补丁 0003 会丢掉它（`docs/新界面/无障碍语义树为空排查.md` §10）。非放不可时在外面包 `Semantics(label: …, excludeSemantics: true)`，照 `LgEllipsisText`。可以点的行要有 `button` 标志，上游 `MenuItemButton` 只在 web 上给，没有标志的叶子节点在 Windows 上只当静态文字、没有 Invoke。
- 浅色、深色和简洁、详细两套尺寸都对；尺寸、颜色、间距、圆角只用令牌。
- 每个组件的每种状态在画廊（`buildSpecimens`）里有一项，能用 `LG_GALLERY_EXPORT` 导出和样稿对照；`app/test/` 里写行为测试（回调被调、禁用时不响应、焦点能到），不比像素。
- 要做的组件（名字是建议，可以按 M0 的命名习惯改，接口的意思不变）：

| 组件 | 数据和回调 | 样稿 |
|---|---|---|
| `LgDeviceAvatar` | 设备 ID（取身份色）、平台（Windows、macOS、Linux、Android、未知）、尺寸 | 设备卡片和列表视图的平台图标 |
| `LgDeviceRow` | 名称、格式化的 ID、`用户名@主机名`、平台、在线状态（在线、离线、正在查询，带文字）、可选的来源分类文字；选中、高亮（连接框里键盘移到的那一行）；`onTap`、`onDoubleTap`、`onConnect`（悬停时出现的"连接"）、`focusNode`；"连接"按钮的文字 | `p1-list-simple`、`p1-card-*`、`p1-cb-*` |
| `LgConnectToRow` | 整行文字（"连接到 ‹输入›"，调用方拼好）、高亮、`onTap`；行尾的"⋯"（连接方式菜单）见 §10.9 | `p1-cb-conn`、`p1-cb-none` |
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

**会话块**

- 输入和焦点的上游依据：`flutter/lib/desktop/pages/remote_page.dart` 的 `_windowsCanFocusRemoteInput`、`enterView`、`leaveView`、`onWindowBlur`、`onWindowFocus`、`RawKeyFocusScope` 的 `onFocusChange`、`dispose`；`hostStopSystemKeyPropagate` 在画面的 `MouseRegion` 进出时切换。macOS、Linux 专用的分支不搬（第一阶段只做 Windows）。
- 从上游复制、按改写档登记：`ImagePaint`、`CursorPaint`、`_ViewStyleUpdater`（`flutter/lib/desktop/pages/remote_page.dart`）放 `app/lib/pages/session/image_paint.dart`；`RawKeyFocusScope`、`RawPointerMouseRegion`（`flutter/lib/common/widgets/remote_input.dart`）放 `app/lib/pages/session/remote_input.dart`。来源行写 `// 上游：<路径>@bd9262397（改写：只留 <类名>；…）`，写明删了什么、改了什么（按设备 ID 的共享状态改成会话字段、`Get.find` 改成参数等）。合并上游时这两个上游文件按改写档人工核对（03 §3.8 第 2 条）。
- core：`FFI.start`、`SessionRegistry.open` 加 `password`、`isSharedPassword`、`switchUuid` 参数，注册表测试跟着补；`StateGlobal.tabBarHeight` 改成新顶栏的高度、全屏时 0；会话页开始时调 `canvasModel.initializeEdgeScrollFallback(this)`、会话开始后读"显示远程光标"的初值（10.6 末尾几条）。
- 外壳：标签列表跟 `appCore.sessions`；每个标签的内容区一个 `Overlay`，会话里的确认框和面板只挡这个标签（03 §4.5）；`appCore.prompter` 在这里实现（带会话的只遮那个标签，不带的只遮主页）；窗口标题"Leapgate"或"‹设备名› - Leapgate"；"+" 调 `showHome(focusConnectBox: true)`；`MainNavigation` 的实现：`connect` 照上游 `flutter/lib/common.dart:2572` 的 `connect`（去空格，`bind.mainHandleRelayId` 去掉 `/r` 并转成强制中继），标签按处理后的 ID 记。
- 连接状态面板：`ConnectionModel` 的 `stage`、`input`、`reason`、`retryCountdown`、`retryAttempt`、`dimLastFrame` 映射到面板（01 P2 区块 D 的表；进度两步"建立连接 → 验证身份"，connecting 时第 1 步进行中，verifying 起第 1 步完成）；按钮调 `login`、`submit2fa`、`selectWindowsSession`、`continueInsecure`、`rejectInsecure`、`retry`、`useRelay`、`cancel`。原因码到文案和下一步按钮的表照 01 §4.3（10.4 C3 表的"对应"一列），`other` 显示 `reason.text`；"修改 ID"调 `showHome(connectBoxText: id)`；"打开网络设置"不在这里显示；"已等待时间"、等画面几秒后加的说明由页面计时。
- 工具栏：基础工具栏，加全屏（`appCore.window.setFullscreen`，全屏时顶栏隐藏）和"重启远程设备"（确认框文案在 01 §4.4，确认后调 `bind.sessionRestartRemoteDevice`，照上游 `common/widgets/dialog.dart:1403-1431` 的出现条件）；不固定时鼠标进入画面 5 秒后收起（上游 `remote_toolbar.dart:648-676`）；画质三档、显示器切换照上游的导出；位置固定在顶部居中。
- V1：标签切走时 `lgBind.leapgateSessionSetVisible(..., false)`，切回时设回 `true` 再 `bind.sessionRefresh`；第一帧到之前就被切走时取消 1.5 秒唤醒计时，切回时仍在等第一帧再起一次（10.4 V1、10.6"接 V1 时要处理"）。V1 单独一个提交，不接 V1 的那个提交用来量占用基线。
- 会话通知横条接 `ffi.notices`，轻提示接 `appCore.toasts`。通知的 key 是上游的英文原文或翻译 key：01 P2 区块 E 有文案的照它，没有的显示原文，每个 key 只写一次日志。第一次连上时轻提示"已建立直连"或"已建立中继连接"。
- 关闭：标签"×"、工具栏"断开"关这个标签（这时一个标签只有一个视图，多视图见 §10.15）。关窗：有会话时确认"断开全部 ‹N› 个会话并关闭窗口？"带"不再提示"（选项 `enable-confirm-closing-tabs`，上游 `flutter/lib/consts.dart:170`）；便携版（`appCore.options.isInstalled` 为假）把 Q6 的"退出 Leapgate / 在后台运行"和"记住此选择"合进同一个确认，没有会话时只问 Q6，记住的选择是新的 LocalConfig 键（`leapgate-` 开头，放在用它的文件里，10.7 接入办法第 2 条）；安装版隐藏到托盘。"在后台运行"隐藏窗口，进程照常当被控端，再次启动程序把窗口找回来（W1）。
- 链接：`uni_links` 收到的 `--connect` 和 `leapgate://` 链接（M0 只写日志）解析出 ID、密码、是否中继，调 `mainNavigation.connect` 并把窗口提到前面；进程自己启动时命令行里带的链接同样处理。解析照上游 `flutter/lib/common.dart:2207-2256` 的 `handleUriLink`，只做新建远程桌面连接这一种，其余动作写一行日志。

**主页块**

- 本机区密码行：01 P1 区块 A 表的五种。数据（一次性密码、审批方式 `approve-mode`、密码方式 `verification-method`、服务是否停止）加在 `LocalStatusModel` 上，照上游 `flutter/lib/models/server_model.dart` 的读法；"复制"后轻提示"已复制"。"刷新""修改"见 §10.9。
- 连接框：01 P1 区块 E、Q2。"输入像不像地址"写成 core 里的纯函数加单测（纯数字 ID、IPv4、IPv6、`域名:端口`、带 `@服务器`、带 `/r`）；回车规则、上下键、Esc；匹配 ID、别名、主机名、用户名、备注，M2a 的结果只来自"最近"；输入为空时"连接"禁用；下拉只有"远程桌面""经中继连接"（后者下面那行说明照 01）；问号说明照上游 `id_input_tip` 按 §7.6 重写。
- 最近列表：`Peers(name: 'recent', loadEvent: 'load_recent_peers', …)`（复制件 `models/peer_model.dart`）由 `AppCore` 持有一份，`bind.mainLoadRecentPeers` 触发加载；在线状态照上游 `flutter/lib/common/widgets/peers_view.dart:313-346`：只查看得见的行、每 6 秒一次、窗口失焦就停；名称取别名、主机名、格式化的 ID 中第一个有的；单击选中，双击或回车连接，悬停出现"连接"；空状态和加载中。连接一律调 `mainNavigation.connect`。

**测试和合入**

- core 的新代码有单测；app 每个页面状态一个行为测试（03 §8.3）：面板的每一种（用假的连接状态）、最近列表空和加载中、连接框几种默认高亮、关窗确认的几种组合（有无会话 × 便携或安装 × 是否勾过不再提示）。
- 合入前：`git diff main -- flutter/` 为空；core 的 `flutter analyze --no-fatal-infos` 不超出 92 条基线，app 0 条；复制件不跑格式化（10.1）。
- 评审重点：会话块看焦点和按键释放、钩子开关的先后、关闭流程、注册表参数、复制件和上游原件的差异；主页块看回车规则和匹配；组件看样稿对照的必修项（03 §8.4）。

### 10.9 M2b 的分工约定

M2b 是控制端完整的会话页和主页。界面行为以 01 为准（P1 区块 A~C、E、F、J、K，P2 区块 A~C、E、F，§2.1、§2.3、§4.2、§4.4），界面模式和工具栏、显示器的几项设置看 02；样稿 `A-P1.html`、`A-P2.html`，令牌和图标以 `A-基础.html` 为准。

**分支和文件边界**（都从 `ui/m2b` 切，做完合回 `ui/m2b`；`ui/m2b` 上已有下面"挂载点"的骨架）

| 分支 | 块 | 只改这些 |
|---|---|---|
| `ui/rust-q3` | Rust | Q3、本机显示名两个块 2 导出和 `src/client.rs` 的挂钩（10.4） |
| `ui/m2b-ds` | 组件 | `app/lib/widgets/`、`app/lib/gallery_main.dart`、`app/test/` 里组件的测试 |
| `ui/m2b-toolbar` | A（会话·工具栏） | `app/lib/pages/session/session_toolbar.dart`、新目录 `app/lib/pages/session/toolbar/`、`canvas_hints.dart`、`app/lib/shell/tab_shortcuts.dart`；core 新复制的 `models/shortcut_model.dart`、`models/input_model.dart` 里 10.6 暂删的几处、`models/state_model.dart`；它们的测试 |
| `ui/m2b-session` | B（会话·其余） | `app/lib/pages/session/` 下的 `route_details.dart`、`quality_overlay.dart`、`recording.dart`、`chat/`、`session_notices.dart`、`connection_panel.dart`，`app/lib/shell/tab_menu.dart`；core 改写的 `models/chat_model.dart` 和新文件（延迟统计等）；`app/pubspec.yaml` 和锁文件（只加 `file_picker`）；它们的测试 |
| `ui/m2b-home` | C（主页） | `app/lib/pages/home/`；`app/lib/main.dart` 里界面模式接到主题的那几行；`app/lib/theme/` 里按选项切 `LgMode` 要的（不改令牌值）；core 的 `leapgate/local_status.dart`、`leapgate/app_core.dart`（只加分类的 `Peers`）、`leapgate/recent_peers.dart` 和新文件；它们的测试 |

- A、B 都可能要改 core 的 `leapgate/session.dart`：A 加 `shortcutModel` 和 `kShortcutEventName` 的登记，B 加聊天 model 和 6 个聊天语音事件、`screenshot`、`printer_request`、`switch_back` 的登记。只在字段表和构造函数里追加，整合时合并相邻行。其余文件不越界。
- ARB 的键按前缀分：A 用 `toolbar`、`menu`、`shortcut`；B 用 `route`、`notice`、`chat`、`record`、`tabMenu`、`conn`；C 用 `home`、`peers`、`peerMenu`、`pwd`、`uiMode`。加在文件末尾，中英文同时加，文案照 01 §7.6：01 里写好的句子逐字照抄，没写的按 §7.6 写，并在提交说明里列出新写的句子。已有的键能用就用。
- A、B、C 三块先用 M0、M2a 的组件和简单的占位控件把逻辑写通，整合时换成组件块的组件。占位控件不求好看，但行为测试要能按文字和语义标签找到它们。

**挂载点**（`ui/m2b` 上的骨架提交，行为和 M2a 相同）

| 文件 | 骨架里的内容 | 由哪块填 |
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

**组件**：规则同 10.8"组件约定"（只管画、文字由调用方传、带语义标签、两套主题和两套尺寸、画廊里每种状态一项、有行为测试）。接口补充：

- 设备卡片 `LgDeviceCard` 和列表视图 `LgDeviceTable`：数据同 `LgDeviceRow`，另有星标、来源分类、选中、多选时的勾选、`onMore`（"⋯"）；表格的列、可排序的列和当前排序由调用方给。卡片网格每列至少 300 宽（01 区块 F）。
- 菜单：在 `LgMenuItem`、`LgMenuGroup` 上补滑块项（标签、值、范围、步长、显示值的格式化、`onChanged`）、步进器项、右侧的快捷键文字、灰显项的悬停说明、危险项、组标题旁的说明（例如"此地址簿为只读"）。
- 工具栏：`LgSessionToolbar` 加沿边拖动（回调给出新位置，0~1 的相对值）、停靠的边（上下左右）、左右两边竖排只显示图标、拖动时的落点预览、"更多"（调用方给出可以收进去的项和顺序，组件按宽度决定收几个）、显示器平铺按钮、收起后拖动条上的切屏按钮。位置记忆和吸附规则由 A 算，组件只画。
- 连接方式详情 `LgRouteDetails`：分组的键值行、可复制的值（指纹）、延迟表（每行名字、当前值、最低、平均、最高）、折线 `LgSparkline`（多条线，颜色加线型，图例文字由调用方传）、开关行。
- 聊天面板 `LgChatPanel`：消息列表（自己 / 对方、时间、文字）、输入框、发送、关闭、拖动。语音通话的几种状态不在面板里，画在工具栏的聊天按钮和它的菜单上。
- 通知：`LgNoticeStack` 加按钮组、勾选（"记住此选择"）、一直保留直到处理。
- 对话框：设置固定密码 `LgPasswordDialog`（两个输入框、强度条、规则逐条通过、错误、按钮）；其他小对话框用 `LgConfirmDialog` 加输入件拼，不另做。
- 本机提示卡、被控时的遮罩、多选条、分类分段、列表工具条。
- 详细模式：组件已经支持两套尺寸；`LgRouteMark` 详细模式下的路径标记画法、工具栏菜单按钮的"图标加文字"按 `LgTokens.of(context).mode` 切换，不另加参数（01 §2.3）。

**会话·工具栏（A）**

- 菜单："显示器""画面""输入""操作""会话"五组，以及灰显和快捷键。每项的出现条件和动作照上游 `flutter/lib/common/widgets/toolbar.dart`、`flutter/lib/desktop/widgets/remote_toolbar.dart`（01 P2 区块 B 有行号），分组照 01 的表，不搬上游的菜单结构；权限不够、仅查看模式时灰显并给说明（01 的文案），隐私模式和录制两处例外照上游。菜单文件放 `pages/session/toolbar/`，文件头注明对应的上游出处。
- 菜单打开的小对话框（自定义分辨率、键盘布局 ANSI / ISO、系统登录密码、请求提升权限的方式、交换控制方向确认、Wayland 授权确认、添加备注）也放 `pages/session/toolbar/`，挂在这个标签的 `TabOverlays` 上。"请求提升权限的方式"做成能从外面调的函数，B 的提权通知按钮也调它。
- 工具栏拖动和停靠、"更多"；显示器的三种形态（读 `show_monitors_toolbar` 等现有选项，01 P2 区块 B）和"全部显示器"（`kAllDisplayValue`，同一个标签里合并显示）。
- 快捷键：把 `flutter/lib/models/shortcut_model.dart` 复制进 core（只删界面调用），补回 10.6 列的快捷键那几处；菜单项右侧显示绑定的组合键（默认绑定见 01 P2 区块 B）；`TabShortcuts` 实现切标签，按键照上游 `shortcut_model` 的切标签动作。
- `StateGlobal` 补回分辨率菜单记的上次选择（10.6 末尾）。
- `CanvasHints`：相对鼠标模式的提示（这时工具栏隐藏，上游 `remote_page.dart:782-792`）、Android 导航浮条。

**会话·其余（B）**

- 连接方式详情（01 §4.2 第二级）：路径、中继名用 Q3 的导出 `leapgate_session_connection(session_id)`（10.4；取值函数在测试里能换掉，返回值照 10.4 的 JSON），每次连接就绪后重新取，返回 `{}` 时不显示"路径""中继服务器"两行。指纹、画面数据来自 core 已有的 `FfiModel`、`QualityMonitorModel`。延迟只有"端到端"一行（Q13 之前，01 §4.2）：core 里每个会话记近 60 秒每 2 秒一个点和本次会话的最低、平均、最高，重连后接着记。"在画面上显示质量数据"照上游的会话选项；界面模式是详细时默认开（02 R2-Q11）。
- "服务器拒绝了此连接："：连接阶段出错、原因码是 `other` 时调同一个导出，有 `refused` 就照 01 §4.3 显示前缀加原文。
- 通知：登记 `screenshot`、`printer_request`、`switch_back`（10.6），做 01 P2 区块 E 里带按钮的几种。截图"另存为"要选位置，加 `file_picker`（版本先用上游 `flutter/pubspec.lock` 锁的，解析不了时选能和 frb 1.80.1 的 `uuid ^3.0.6`、`js ^0.6.4` 共存的版本）；提权通知的"请求提升权限"调 A 的选方式对话框；录屏通知的"停止"。权限中途被收回时加一条通知。
- 聊天和语音：`chat_model` 改写进 core（只留消息存储、未读数、语音状态；消息类型用 core 自己的，不带 `dash_chat_2`），登记 6 个事件；`ChatLayer` 里的面板、`chatToolbarButtons` 的聊天菜单（文字聊天、语音通话、等待接听、通话中的麦克风选择和挂断）、`tabUnread`。
- 录制：`recordButton` 和录制态，权限例外照上游。
- 标签右键菜单：`showSessionTabMenu`，"复制设备 ID""关闭其他标签""关闭"。
- 连接状态面板：等对方接受时加"显示给对方的名称：‹本机名›"（块 2 导出 `leapgate_local_display_name()`，取值方式同上）；密码错误后保留输入、带"输入密码"标签，关掉确认框后密码框拿回焦点，照样稿。

**主页（C）**

- 分类：最近、收藏、局域网三类。`AppCore` 加收藏、局域网两份 `Peers`（照 M2a 的 `recentPeers`），加载用 `bind.mainLoadFavPeers`、`bind.mainLoadLanPeers`，事件 `load_fav_peers`、`load_lan_peers`。哪些分类显示、顺序照上游的选项（`peer_tab_page.dart` 的读法），在"视图"菜单里改。
- 卡片和列表视图、排序（修掉上游按在线状态排序那个不合法的比较函数，`peers_view.dart:389-391`）、多选、设备菜单（四组，出现条件照上游 `peer_card.dart:958-1348`，地址簿相关的项不出现）、各分类的空状态、1000 台上限；在线状态查询照 M2a。网络唤醒、创建桌面快捷方式、始终经中继、重命名（别名）、收藏、清除保存的密码、删除（最近）、移除（局域网）各照上游的调用。
- 连接框：搜索扩到三类（同一个 ID 只出现一次，标出来源，顺序最近、收藏、局域网）；"连接到"行尾的"⋯"（远程桌面、经中继连接）；结果按当前视图显示。"输入看起来像地址"的判断和回车规则不变。
- 本机区：密码行"刷新"（一次性密码）、"修改"（只在便携版显示，打开设置固定密码对话框，校验和保存照上游 `desktop_home_page.dart:890-1126`）；服务已停止时的"启动服务"；"正在被远程控制（N 个会话）"，N 的算法和"查看"见 §10.10 第二段；提示卡只显示系统错误那张。
- 被控时的遮罩：照上游 `canBeBlocked`、`shouldBeBlocked`（`flutter/lib/common.dart:3138-3205`），只盖主页。
- 界面模式：02 §4.1 的新选项，键 `leapgate-ui-mode`（值 `detail` 是详细，其余是简洁），Leapgate 自己的 LocalConfig 键放在用它的文件里（10.7 接入办法第 2 条）；"视图"菜单里切换；`main.dart` 把它接到 `buildLgTheme` 的 `mode`，切换立即生效；设备页默认视图跟着它，用户手动选过视图后按用户选的。

**测试和合入**

- core 的新代码有单测（延迟统计、分类合并搜索、排序、遮罩判断、聊天消息存储）；app 每个页面状态一个行为测试。
- 合入前：`git diff main -- flutter/` 为空；core 的 `flutter analyze --no-fatal-infos` 在 3.44.9 下不超出 92 条 info 的基线，新复制的 `shortcut_model` 带来的上游提示单列；app 0 条；复制件不跑格式化。改已有文件时不对整个文件跑 `dart format`：M2a 的文件不是按当前格式化器的样式排的，整文件格式化会把差异放大到几百行；只格式化新文件。

### 10.10 M3 的分工约定

M3 是被控端的连接管理小窗（CM）。界面行为以 01 §3.3（P3 全部）为准，02 §0.4 第 2、11 条、R2-Q16 有更正；样稿 `A-P3.html`；令牌和图标以 `A-基础.html` 为准。M3 和 M2b 并行开发，M2b 的约定在 10.9。

**两段**：第一段是窗口、来访标签、信息头、权限区、操作区、贴边小条、远程点击保护、关窗确认、主题和语言跟随（见下面"主题、语言"），加 Rust 三项；第二段依赖 M2b，是聊天侧栏、文件记录侧栏、主窗口本机区的连入数和"查看"、界面模式跟随。

**分支和文件边界**（都从 `ui/m3` 切，做完合回 `ui/m3`）

| 分支 | 块 | 只改这些 |
|---|---|---|
| `ui/rust-m3` | Rust | `src/ipc.rs`（`Data` 末尾一个变体，主进程一侧 `handle` 一处分发）、`src/ui_cm_interface.rs`（CM 一侧消息循环一处分发）、`src/server/connection.rs`（只在出口连接的编号从现有挂钩拿不到时加一行）、`src/leapgate_ffi.rs`（末尾追加 M3 一段）、`src/leapgate_hooks` 下的新文件、`libs/leapgate/src/ipc.rs`（新）；测试 |
| `ui/m3-ds` | 组件 | `app/lib/widgets/` 下 `lg_cm` 开头的新文件、`app/lib/gallery_main.dart` 的追加、这些组件的测试 |
| `ui/m3-cm` | CM 页面 | `app/lib/cm/`（新）、`app/lib/main.dart` 的 `--cm` 分支、`app/windows/runner/main.cpp` 里 CM 窗口的初值；core 的 `models/server_model.dart`（新复制）、`leapgate/` 下 `cm_` 开头的新文件、`consts.dart`（只追加）；它们的测试 |

- 和 M2b 重叠的只有 `app/lib/main.dart`（M2b 主页块改界面模式接主题那几行）、core `consts.dart`（M2b 也追加选项键）、`gallery_main.dart`，都只追加，整合时合并相邻行。
- ARB 键用 `cm` 前缀，加在两个 ARB 文件末尾，中英文同时加，文案照 01 §3.3 和 §7.6，新写的句子列进提交说明。
- CM 页面先用 M0、M2a 的组件和简单占位把逻辑写通，整合时换成组件块的组件；占位要能被行为测试按文字和语义标签找到。

**进程间消息和块 2 导出**（CM 页面用测试里能换掉的取值函数）

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

**组件**：规则同 10.8"组件约定"。要做的：CM 外框（可拖动的标题区、"收起""关闭"，紧凑和展开两种宽度）、来访标签条、信息头（头像规则同 01 §3.1 区块 D）、几种会话类型的信息区、权限区（带文字的开关两列、只读态）、操作区的各种组合、贴边小条（一个连接按类型的文案、几个连接）、远程点击被拦下的提示、文件记录侧栏的列表行和空状态、关窗确认。聊天侧栏用第二段加的 `LgCmChat`（`app/lib/widgets/lg_cm_chat.dart`：M2b 聊天气泡的嵌入形态，铺满侧栏、没有标题和关闭，带只读态；`LgChatMessage` 加了可选的 `sender`）。CM 的颜色跟主题，信息头用固定的浅青功能底（01 §2.4），不用来访者的身份色。

**CM 页面（第一段）**

- 初始化：`--cm` 分支照上游 `flutter/lib/main.dart:285-302`：先建 `AppCore`，再按 CM 初始化平台接口（`kAppTypeConnectionManager`，它会调 Rust 的 `cm_init`，`core/lib/models/native_model.dart` 里已有这一处），登记 CM 的全局事件 `add_connection`、`on_client_remove`、`show_elevation`、`update_voice_call_state`（登记在 `appCore.events`，10.6；`theme`、`language` 不登记，见下面"主题、语言"），第二段加了 `chat_server_mode`、`cm_file_transfer_log`（见下面"第二段"）。不读 `hide_cm`（03 §5.2 M3）。
- 复制件：`flutter/lib/models/server_model.dart` 复制进 core，CM 用到的部分按"只删界面调用"保留（客户端列表、`addConnection`、`onClientRemove`、接受和拒绝、断开、提权、撤销交换、语音状态、关闭全部、500 ms 的轮询和约 6 秒退出；最后一个来访离开时当场关窗，见下面"没有来访后退出"），主窗口和 Android 的部分（密码、ID、起停服务）整段删掉，来源行写明删了什么。标签不用上游的 `DesktopTabController`，用自己的列表。一条连接的两次 `add_connection`、`on_client_remove` 的关闭标记、同一个人重连时删旧的那条，照上游的规则。
- 窗口：紧凑态 320×500、贴主显示器工作区右上角、置顶、不能改大小；展开侧栏时向左展开到 700×500（样稿是 320×500，01 §3.3 写"约 300~320 宽"，选 320；外框 320 含不可见缩放边框，客户区 150% 下约 309，组件按最窄客户区 304 设计；尺寸用组件里的 `kLgCmWidth`、`kLgCmHeight`、`kLgCmExpandedWidth`，不另写一套）；隐藏照上游用透明加隐藏、不销毁；runner 里 CM 的初值和 Dart 一致（原来是 800×600）。
- 贴边小条：同一个窗口缩成一条，贴主显示器上边、靠右，沿上边左右拖动、位置只在本次运行内记住（记在 `LgCmWindow` 的内存里，不写 LocalConfig：CM 进程的 LocalConfig 是启动时读的快照，写任何一个键都会把整份旧配置存回文件，盖掉主窗口之后改过的本地配置；所以没有 `leapgate-cm-strip-offset` 这样的键）；授权后自动收起的时机和取消条件照上游 `server_model.dart:571-590`、`server_page.dart:180-186`（01 §3.3 改成"收成小条"而不是最小化）；新来访时恢复成完整小窗并置顶。
- 远程点击保护：照上游 `server_page.dart:1237-1253`，被拦下时在按钮旁提示"无法远程执行此操作"；`allow-remote-cm-modification` 开着时放行。小条上的"断开"同样受保护。
- 关窗：多于一个连接时始终确认"断开全部会话？"，不读 `enable-confirm-closing-tabs`（R2-Q16）；关闭照上游 `closeAll`。标题栏"关闭"和确认里的"断开"也做远程点击保护，问的是任意一个还连着的来访（已断开的问不到、会读到旧值）；一个都没连着时直接执行。整个窗口（标题栏按钮、标签、面板、确认框、小条）都不接键盘焦点（`allow-remote-cm-modification` 开着时除外）：服务端只在左键抬起和回车时更新对方的输入时间，Tab 加空格能绕过点击判断。
- 主题、语言：CM 和新主窗口一样跟随系统，不读 LocalConfig 的 `theme`、`lang`，也不登记 `theme`、`language` 事件；设置页存下用户的选择以后，主窗口和 CM 一起接，见 §10.13 的"外观"。语言只有简体中文和英文，系统是其他语言时用英文（IQ10）。

**测试和合入**

- core：客户端列表的增删和两次事件、已断开的保留和清理、自动收起的取消条件、没有来访时退出的计时（用假时钟），各有单测；Rust：C1 的分类（含出口表清理）、`Msg` 的编解码。app：每种状态一个行为测试。
- 合入前：`git diff main -- flutter/` 为空；core 的 `flutter analyze --no-fatal-infos` 在 3.44.9 下不超出 92 条 info 的基线，新复制的 `server_model` 带来的上游提示单列；app 0 条；复制件不跑格式化；改已有文件时不对整个文件跑 `dart format`。
- 评审重点：Rust 看两头分发都在、出口计数和清理、旧界面的 CM 不受影响；CM 看事件处理和上游规则一致、窗口和小条的状态切换、远程点击保护；组件看样稿必修项。

**没有来访后退出**

- 上游有两条关窗的路：标签控制器移除最后一个标签时 `server_page.dart` 的 `onRemoveId` 当场 `windowManager.close()`（`onClientRemove` 以关闭移除、`sendLoginResponse` 拒绝时都走它）；500 ms 轮询里空着数到 12 次再关是兜底。复制件不用标签控制器，第一条路跟着丢了，小窗进程在最后一个来访断开后还要活 6~6.5 秒。
- 后果：同一台控制端约 6 秒后再连进来，登录正好落在轮询请求关窗和 `onWindowClose` 之间，`closeAll` 把这个新来访一起关掉（服务端 `Connection closed: connection manager`，控制端收到不重试的"Closed manually by the peer"）。
- 改法：`onClientRemove` 里列表因关闭（`close` 为真）变空时，隐藏之后当场 `window.close()`（带 `leapgate:` 注释），对应上游的 `onRemoveId`。拒绝时上游也当场关；这里拒绝后服务端随即结束连接、发来 `close` 为真的 `on_client_remove`，同样走这一行。轮询的 6 秒计数保留，只管上游也只靠它的情形：启动后一直没有来访、轮询发现和服务进程的列表对不上并重读成空表。
- 剩下的竞争窗口和上游一样：另一台控制端恰好在这一台断开后的几十毫秒内登录，仍会被 `closeAll` 带走。

**CM 的已知限制**

- 远程点击保护靠"本地点击比对方最近一次输入晚 120 ms 以上"判断：CM 进程卡顿超过 120 ms 时，对方的点击可能被当成本地点击放行。
- 它也挡不住经讲述人或 UI Automation 按语义调用 CM 的按钮。能控制键盘鼠标的人本来就能在本机运行程序，不另做防护。
- 按 Alt+F4 关闭 CM 不弹"断开全部会话？"，直接断开全部会话（同上游）。
- 第二位来访者的自动收起计时会覆盖第一位的：在小窗里移动鼠标只取消最后一个，前一个到时照样收起（同上游）。

**第二段**（依赖 M2b）

- 侧栏：信息头按钮开关侧栏（远程点击保护照旧）。侧栏只在所选来访者有侧栏时显示（已授权的远程桌面、摄像头是聊天，文件传输是文件记录；`_hasSide`），窗口宽度跟着它：显示时 700（`kLgCmExpandedWidth`），否则 320。`LgCmWindow.setExpanded` 记住这个宽度，`_toFront`（新来访、从小条展开、"查看"）照它摆，不再一律放回 320。侧栏开着时来了新来访：新来访者已授权（密码直接通过）时侧栏照开、宽度不变；还在请求中时没有侧栏，窗口回到 320，接受后回到 700。所有来访者都没了时侧栏关上，6 秒内再来的来访者从关着开始。
- 聊天：`leapgate/cm_chat.dart` 的 `CmChatModel`，管上游 `ChatModel` 在 CM 里的那部分。消息按来访者 ID 存（上游 `MessageKey` 也只比 ID），重连后还能看到；发送用所在标签的连接编号，所以上游 `_addTab` 里的 `chatModel.updateConnIdOfKey` 没有加回（复制件来源行已写明）。收到消息时（上游 `receive`）：窗口提到前面（小条会展开；已经是完整小窗时只显示、取得焦点，不挪回角落，同上游 `main.dart:321-329`），切到发消息的人的标签并打开聊天；正在聊天里写字（侧栏开着、输入框有焦点）时不切，发消息的是另一个人（按 `peerId` 比，同一个人的远程桌面和摄像头共用一份聊天）才计入他标签上的未读数。发送时当场取出文字、清空输入框，再走远程点击保护（要等约 120 ms），所以连按不会发两次、等待期间输入的新草稿不会被清掉；被拦下时输入框还空着就把原文填回去。回车发送后输入框留着焦点（`LgTextField` 透传 `onEditingComplete`，会话页的 `LgChatPanel` 一起改）。点有未读的标签会打开它的侧栏（上游 `server_page.dart:131-145`）。对方断开后聊天只读，提示"对方已断开连接"。
- 文件记录：`models/cm_file_model.dart` 复制上游并改写（来源行列了差异）：日志解析、每条记录的状态规则、删目录时去掉其下的删除记录照抄；记录表在第一条日志到时建（上游在标签被选中时建，没选中过的连接的日志会被丢掉）；"侧栏正显示这个连接"由页面设 `shownConnId`。方向按 Windows 上 CM 的读写定：`isRemote`（CM 读文件、对方下载）是"从本机下载"，其余是"上传到本机"；名字只显示最后一段路径，重命名是"旧名 → 新名"；最新的在上面；已取消或跳过的显示"已跳过"。
- 未读数：聊天和文件记录共用上游的 `Client.unreadChatMessageCount`，改它的地方都会接着通知页面（聊天、文件记录 model 的通知，页面自己的 `setState`），标签和侧栏按钮跟着变。
- 焦点：`LgCmFrame` 加了 `sideFocusOnly`（默认 false，和原来一样不管焦点）。CM 页面传 `!allowRemoteCmModification()`：标题行、标签、面板、确认层不接焦点，侧栏可以（聊天输入框要能打字），不在整个窗口外包 `ExcludeFocus`。发送只有两条路：输入框里按回车、鼠标点"发送"，都走远程点击保护（服务端在对方按回车和左键抬起时更新对方的输入时间，所以对方的回车和点击都会被拦下，提示出现在侧栏上方）。"发送"按钮不接焦点（`LgCmChat` 里包了 `ExcludeFocus`）：Tab 加空格不会更新对方的输入时间，否则对方点进输入框打字后能用它以本机身份发出。"查看"在 CM 没有来访者时不处理，免得弹出空窗口。
- 语音：通话中操作区一行是麦克风选择加"挂断"（`LgCmMicRow`）。设备照上游 `AudioInput`（`isCm: true`）：能用"系统声音"时它在第一项、也是默认；一个设备都没有时点选择框提示"未找到音频输入设备" 3 秒。选设备不做远程点击保护（同上游），"挂断"做。
- 主窗口：本机区的 N 是 C1 的全部类型之和，有远程桌面或终端时"正在被远程控制（N 个会话）"，否则"‹N› 个传入会话进行中"，旁边"查看"调 `leapgate_show_cm`。`LocalStatusModel` 每 3 秒问一次 `leapgate_incoming_counts`（单独的计时器，不放在每秒的状态轮询里）：主窗口收不到会话开始、结束的事件，`video_conn_count` 又只数远程桌面；一次查询是本机的一次进程间连接，服务进程在内存里数，最坏约 2 秒，3 秒的间隔不会叠起来。原来的 `remoteSessions`（`video_conn_count`）删掉。
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

M4 是账号、地址簿和同组设备。登录只做账号密码，不做 2FA 和邮箱验证码。界面行为以 01 §3.1 区块 D、E、F、G、H、K 为准，账号的文案看 02 §1.5.3，标签颜色看 02 §3.6；样稿 `A-P1.html`；令牌和图标以 `A-基础.html` 为准。

**分支和文件边界**（都从 `ui/m4` 切，做完合回 `ui/m4`；`ui/m4` 上已有下面"挂载点"的骨架）

| 分支 | 块 | 只改这些 |
|---|---|---|
| `ui/rust-h1` | Rust（H1） | `libs/leapgate/src/api.rs`（加一个带 Bearer 的通用请求函数）、`libs/leapgate/src/account/`（新）、`libs/leapgate/src/lib.rs`（声明模块一行）、`src/leapgate_ffi.rs`（末尾追加 M4 一段）；测试。不改 Dart，不生成桥 |
| `ui/m4-ds` | 组件 | `app/lib/widgets/`（新组件；`LgDeviceCard`、`LgDeviceRow`、`LgDeviceTable` 加备注）、`app/lib/gallery_main.dart`、组件的测试 |
| `ui/m4-account` | A（账号、登录、同组设备） | core `leapgate/account.dart`、`leapgate/group.dart`、`leapgate/peer_tabs.dart`（只改 `isEnabled`）；app `pages/home/account/`、`pages/home/group/`、`pages/home/home_page.dart` 的 `_SideColumn`（账号区摆在哪、间距）、`main.dart`（启动时调 `appCore.account.start()` 那几行）；它们的测试 |
| `ui/m4-ab` | B（地址簿） | core `leapgate/address_book.dart`、`leapgate/peer_list.dart` 的 `peerMenu`（条件和参数）、`consts.dart`（只追加地址簿的选项键）；app `pages/home/address_book/`、`peer_views.dart` 里 `peerMenuItems` 调 `peerMenu` 那几行（跟着参数改）；它们的测试 |

- 共用文件只往挂载点里填，挂载点以外的行不改：`devices_page.dart`、`peer_views.dart`、`account_category.dart`，core 的 `account_api.dart`、`app_core.dart`，`core/test/account_fakes.dart`。
- ARB：A 的键以 `account`、`login`、`group` 开头，B 以 `ab` 开头，加在两个 ARB 文件末尾，中英文同时加，文案照 01 §7.6：01 里写好的句子逐字照抄，新写的句子列进提交说明。分类名 `abCategory`、`groupCategory` 骨架里已经加了。
- A、B 两块先用 M0~M3 的组件和简单的占位控件把逻辑写通，整合时换成组件块的组件。占位不求好看，但行为测试要能按文字和语义标签找到它们。
- 测试里换掉导出：设 `accountApi = FakeAccountApi()`（`core/test/account_fakes.dart`；app 的测试照 `home_fakes.dart` 引 `FakeLeapgate` 的办法用相对路径引它）。三个 model 第一次用到时才建，`accountApi` 要在第一次用 `appCore.account`、`addressBook`、`group` 之前设好。

**H1 的块 2 导出**（A、B 只经 `account_api.dart`，测试用 `FakeAccountApi`）

都放在 `src/leapgate_ffi.rs` 末尾新的 "Account (M4)" 一段，逻辑在 `libs/leapgate/src/account/`，`src/` 只做薄壳。除 `leapgate_account_local` 外在 Dart 侧都是异步：Rust 函数照 `leapgate_incoming_counts` 的写法同步返回 `String`，请求放在用 `#[tokio::main(flavor = "current_thread")]` 包的函数里跑（frb 在工作线程上调，不在运行时里，符合 AGENTS.md 的 Tokio 规则）。返回值都是 JSON 字符串，出错时是下面"错误的形状"。

| 导出 | 参数 | 成功时返回 | 做什么 |
|---|---|---|---|
| `leapgate_account_local()`，同步 | | 有令牌时 `{"user":<user_info>}`，没有时 `{}` | 不发请求：读 LocalConfig 的 `access_token`（只看是否非空）和 `user_info` |
| `leapgate_account_login_options()` | | `{}` | `GET /api/login-options`，2xx 就算成功，内容不解析（rustdesk-api 回的登录方式列表也照样成功） |
| `leapgate_account_login(username, password)` | 原样，trim 由界面做 | `{"user":<用户对象>}` | `POST /api/login`，体 `{username, password, id, uuid, autoLogin: true, type: "account", deviceInfo}`（上游 `common/hbbs/hbbs.dart` `LoginRequest`，不带验证码字段）；`id`、`uuid`、`deviceInfo` 由导出在 `src/` 取（`ui_interface::get_id()`、`get_uuid()`、`get_login_device_info()`）再传进 `libs/leapgate`。成功后写 `access_token`、`user_info` |
| `leapgate_account_current_user()` | | `{"user":<用户对象>}` | `POST /api/currentUser`，体 `{id, uuid}`；成功后重写 `user_info` |
| `leapgate_account_logout()` | | 总是 `{}` | `POST /api/logout`，体 `{id, uuid}`，2 秒超时；不管结果如何都删 `access_token`、`user_info`、两份缓存 |
| `leapgate_ab_cache()` | | `{"entries":[…]}` | 不发请求：`_ab` 缓存里的令牌和当前令牌相同时，原样给它的 `ab_entries`（每条 `guid`、`name`、`peers`、`tags`、`tag_colors`），否则空数组 |
| `leapgate_group_cache()` | | `{"users":[…],"peers":[…]}` 或 `{}` | 不发请求：`_group` 缓存的令牌相同时给它的 `users`、`peers`（上游 `toGroupCacheJson` 的格式），否则 `{}` |
| `leapgate_ab_books()` | | `{"max_peers":n,"personal":"<guid>","shared":[{"guid","name","owner","note","rule"}…]}` | `POST /api/ab/personal`、`/api/ab/settings`、`/api/ab/shared/profiles`（分页）。任一个失败整个失败；`personal` 回 404 是 `unsupported`；`max_peers` 是 0 表示不限 |
| `leapgate_ab_book(guid, name, personal)` | 簿的 guid；`name`、`personal` 只用来写缓存 | `{"peers":[…],"tags":[{"name","color"}…]}` | `POST /api/ab/peers?current&pageSize&ab=<guid>`（分页，按 ID 去重，某一页没有新 ID 就停）、`POST /api/ab/tags/<guid>`。`peers` 是服务器给的设备对象原样（个人簿带 `hash`、共享簿带 `password`）。成功后写 `_ab` 缓存（见下面"缓存"） |
| `leapgate_ab_add_peer(guid, peer)` | `peer`：设备对象的 JSON 字符串 | `{}` | `POST /api/ab/peer/add/<guid>`，体原样（个人簿去掉 `password`、共享簿去掉 `hash` 由界面做，上游 `addPeers`） |
| `leapgate_ab_update_peer(guid, peer)` | `peer`：`id` 加要改的字段的 JSON 字符串 | `{}` | `PUT /api/ab/peer/update/<guid>`，体原样。上游 5 处都走它：标签、别名、备注、`hash` 或 `password`、与最近会话同步 |
| `leapgate_ab_delete_peers(guid, ids)` | `ids: Vec<String>` | `{}` | `DELETE /api/ab/peer/<guid>`，体是 ID 数组 |
| `leapgate_ab_add_tag(guid, name, color)` | `color: i64`（ARGB，同 Flutter `Color.value`） | `{}` | `POST /api/ab/tag/add/<guid>`，体 `{name, color}` |
| `leapgate_ab_rename_tag(guid, old_name, new_name)` | | `{}` | `PUT /api/ab/tag/rename/<guid>`，体 `{old, new}` |
| `leapgate_ab_set_tag_color(guid, name, color)` | `color: i64` | `{}` | `PUT /api/ab/tag/update/<guid>`，体 `{name, color}` |
| `leapgate_ab_delete_tags(guid, names)` | `names: Vec<String>` | `{}` | `DELETE /api/ab/tag/<guid>`，体是标签名数组 |
| `leapgate_group()` | | `{"users":[<用户对象>…],"peers":[<设备对象>…]}` | `GET /api/users`、`GET /api/peers`（都带 `accessible`、`status=1`，分页，`current` 和 `page` 都带）；两个都成功才算成功，成功后整份重写 `_group` 缓存。不调 `/api/device-group/accessible` |

- 共 17 个导出，覆盖 18 个端点。写操作按端点各一个、不合成"操作种类 + 参数"的一个：各端点的体和 404、409 的含义都不同，合成一个要在 JSON 里再编一层，界面调用反而不清楚。参数名避开 Dart 的保留字（`new`），所以叫 `old_name`、`new_name`。一次加一台设备、一个标签（上游 `addPeers`、`addTags` 也是逐个发），多选"加入地址簿"由界面循环，遇到第一个错误就停（上游同样）。
- 用户对象、设备对象都是服务器给的原样（用户对象有 `name`、`display_name`、`avatar`、`email`、`note`、`status`、`is_admin`），界面按 `account_api.dart` 的数据类解析。
- 写 `user_info` 照上游 `UserPayload.toJson`：`{"name","display_name","avatar","status"}`，`status` 照它的换算（0 停用、-1 未验证、其余 1）。Rust 别处在读它：登录消息的显示名（`src/client.rs`）、本机显示名导出。
- 写操作 2xx 且体为空或体里没有 `error` 时算成功（上游 `_jsonDecodeActionResp`）。

**错误的形状**：`{"error":"<种类>","text":"<原文>"}`。`text` 取服务器 JSON 的 `error` 字段，没有时 `HTTP <状态码>`；`network` 时是错误描述。`text` 截到 200 个字符，不含令牌。

| 种类 | 什么时候 | Rust 顺带做的 |
|---|---|---|
| `unauthorized` | 登录以外的接口回 401；`currentUser` 回 400 | 删 `access_token`、`user_info`、`_ab`、`_group` |
| `wrong_credentials` | 登录回 401：Leapgate 服务端用它表示用户名或密码错误 | 不动令牌 |
| `verification_required` | 登录 2xx 但 `type` 不是 `access_token`（要验证码或 2FA） | 不写令牌；界面显示"此服务器要求验证码登录，Leapgate 暂不支持" |
| `not_found` | 写操作回 404（设备、标签不在这本簿里） | |
| `conflict` | 409（新标签名已存在） | |
| `unsupported` | `ab/personal` 回 404 | |
| `network` | 连不上、TLS 失败、超时（单次 12 秒，登出 2 秒） | |
| `server` | 其余：别的 4xx（含限流 429、只读簿写入的 403、簿满的 400）和 5xx，2xx 里带 `error`（`currentUser` 的内部错误），回的不是预期的 JSON；`settings`、`shared/profiles` 的 404 也在这里 | |

- `currentUser` 的 400 照上游（`models/user_model.dart:85-88`）也清令牌。上游 400 只清令牌、不当场复位地址簿和组，但紧接着 finally 里的拉取因为没有令牌也会复位它们，结果和 401 相同，所以这里两者一样处理。
- 界面不认识的种类当 `server`（`parseApiResult`）。

**缓存**

- `_ab`：格式照 `hbb_common::config::Ab`（`access_token` 加 `ab_entries`）。个人簿那条的 `name` 必须是 `My address book`：`AbEntry::personal()` 按名字认，`src/client.rs` 的 `try_get_password_from_personal_ab` 靠它找个人簿里存的密码。`leapgate_ab_book` 成功后改写：最多两条，个人簿一条、最近拉过的共享簿一条（上游存"个人簿 + 当前簿"，界面拉的共享簿就是当前簿）；`personal` 为真时换个人簿那条，否则换共享簿那条；文件里的令牌和当前令牌不同时先清空再写。条目的 `peers` 照 `AbPeer` 只留 `id`、`username`、`hostname`、`platform`、`alias`、`tags`，个人簿另带 `hash`（上游 `toCustomJson(includingHash:)`）；`tag_colors` 是 `{"名字": 颜色}` 的 JSON 字符串。
- `_group`：照 `config::Group`，`leapgate_group` 成功后整份重写。
- 退出、`unauthorized` 时两份都删。登录成功时不删（令牌不同的缓存不会被读到）。

**令牌和请求**（IQ7）：`access_token` 只在 Rust 里读写，Dart 不读不写它，也不写 `user_info`。API 地址用 `report::api_root()`（已知限制：不认程序文件名里带的配置）。请求用 `api.rs` 的严格客户端（系统根证书加 webpki、不跟随重定向、证书失败不回退、按上游规则走代理），带 `Authorization: Bearer <令牌>`。日志不记令牌、密码、`hash`、共享密码，失败只记端点路径和状态码。

**Dart 侧的调用层**：`core/lib/leapgate/account_api.dart`（骨架，共用）

- 数据类：`AccountUser`（`displayNameOrName`）、`ShareRule`（上游同名枚举去掉文字）、`AbProfile`、`AbBooks`、`AbTag`、`AbBookData`（设备用 core 的 `Peer.fromJson`）、`GroupData`（设备经 `groupPeer`，照抄上游 `PeerPayload.toPeer`，`loginName` 是主人的用户名）。
- `ApiErrorKind`（上表八种）、`ApiError(kind, text)`、`ApiResult<T>`（`ok`、`value`、`error`）、`parseApiResult(json, ok)`。
- 接口 `AccountApi`，方法和导出一一对应：`localUser`、`loginOptions`、`login`、`currentUser`、`logout`、`abCache`（返回 `entries` 的列表）、`groupCache`、`books`、`book(guid, name:, personal:)`、`addPeer(guid, peer)`、`updatePeer(guid, id, fields)`（`id` 由它并进体里）、`deletePeers`、`addTag`、`renameTag`、`setTagColor`、`deleteTags`、`group`。全局 `accountApi` 默认是 `RustAccountApi`，测试换成 `FakeAccountApi`。
- `RustAccountApi` 的每个方法体是一行 `lgBind.leapgate…` 加 `parseApiResult`。

**core 的三个 model**（`ChangeNotifier`，同 M1 的做法，不用 Get、Rx；挂在 `appCore` 上，`late final`，第一次用时建）

| model | 文件 | 块 | 别的块要用的成员 |
|---|---|---|---|
| `AccountModel` | `leapgate/account.dart` | A | `user`（null 是没登录）、`loggedIn`、`error`（最近一次和服务器核对失败的原因，仍算登录着）、`disabled`、`start()`、`checkLoginOptions()`、`login(username, password)`、`logout()`、`refresh()`、`signedOutByServer()` |
| `AddressBookModel` | `leapgate/address_book.dart` | B | `disabled`、`loaded`、`loading`、`unsupported`、`pullError`、`books`（个人簿第一、共享簿按名字）、`current`、`isPersonal(book)`、`peers`、`shownPeers`（经标签筛选）、`allPeers`（已加载的各簿，连接框用）、`canWrite`、`writableBooks`（"加入地址簿"列的簿）、`sharedPasswordOf(id)`、`syncPeerHash(id, hash)` |
| `GroupModel` | `leapgate/group.dart` | A | `disabled`、`loaded`、`loading`、`error`、`users`（自己第一）、`peers`、`selectedUser`、`selectUser(name)`、`shownPeers` |

- 地址簿和组都实现 `AccountData`（`loadCache()`、`pull()`、`reset()`，定义在 `account.dart`）。`AccountModel` 构造时拿到 `[addressBook, group]`（M5 的出口目录也实现它，§10.12），由它按下面的顺序调这三个方法；页面上的"刷新""重试"直接调各自 model 的 `pull()`。其余成员各块自定，不进约定。
- 顺序（A 实现，照上游 `refreshCurrentUser`、`updateOtherModels`）：`start()` 先读 `localUser()`，有就当已登录、调各 `loadCache()` 先显示；再 `currentUser()`：成功就更新用户、并行调各 `pull()`；`network`、`server` 记进 `error`、保持登录、不拉（上游 `pullAb`、`group.pull` 在有网络错误时直接返回），"重试"调 `refresh()` 再走一遍；`unauthorized` 走 `signedOutByServer()`。`login` 成功后更新用户、并行拉。`logout()` 调导出后清用户、`reset()` 各个。`signedOutByServer()` 清用户和 `error`、`reset()` 各个（令牌 Rust 已经删了）。
- 地址簿和组的请求回 `unauthorized` 时，调 `appCore.account.signedOutByServer()`，不自己复位别人。
- 在线状态：地址簿和同组设备的 `Peer.online` 由各自的 model 更新：照 `CategoryPeers` 用 `platformFFI.registerEventHandler('callback_query_onlines', <自己的 handler 名>, …)`，只改自己列表里的设备，变了就通知。页面判断"有没有回答"沿用 `categoryPeers(...).hasOnlineState`（每个 `CategoryPeers` 都收下全部 ID，不用改）。
- 内置选项：`disabled` 分别读 `bind.isDisableAccount()`、`isDisableAb()`、`isDisableGroupPanel()`。`PeerTabs.isEnabled` 对地址簿是"账号、地址簿都没禁用"，对同组设备是"账号、组面板都没禁用"（上游 `models/peer_tab_model.dart` 的 `isEnabled`）；没登录时分类照常显示，内容是"登录后可查看…"。
- 本地选项：上游的 `current-ab-name`（Flutter 选项）、`sync-ab-with-recent-sessions`、`sync-ab-tags`、`filter-ab-by-intersection`（LocalConfig）照上游的键和值，归 B，键追加进 core 的 `consts.dart`（10.7 接入办法第 2 条）。登录框"预填上次的用户名"：上游读 `user_info` 的 `name`，退出后就空了；要做到 01 的"上次的"，A 加一个 Leapgate 自己的 LocalConfig 键在登录成功时记下（键放 `account.dart`）。
- 全局事件 `sync_peer_hash_password_to_personal_ab`（`src/client.rs` 登录后推）已在 `AppCore` 构造函数里登记，转给 `addressBook.syncPeerHash`（B 填；上游 `changePersonalHashPassword`：这台设备在个人簿里才写）。

**挂载点**（`ui/m4` 上的骨架提交，行为和 M3 相同）

| 文件 | 骨架里的内容 | 由哪块填 |
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

- `peerMenu` 照 01 区块 F 的菜单表：管理组补"加入地址簿"（已登录，各分类）、"编辑标签""编辑备注""设置共享密码"（地址簿；共享密码只在共享簿）、"查看所在地址簿"；危险组在地址簿里是"从地址簿中删除"；同组设备只有连接方式和"加入地址簿"；只读簿的写操作灰显（`LgMenuItem.disabledNote`），说明只在第一个出现灰显项的组标题旁写一次。地址簿分类里的"重命名"改的是簿里的别名（上游 `common/widgets/peer_card.dart` 的 `AddressBookPeerCard`），由 `abPeerMenuItem` 接管；"清除保存的密码"在所有分类都由 `abPeerMenuItem` 接管：设备在个人簿里时连簿里的 `hash` 一起清，再清本机保存的密码（上游 `_unrememberPasswordAction`，否则 Rust 下次连接仍会从 `_ab` 缓存自动填）。
- 骨架里多选条的写法（`if (!accountCategory)` 下面那段没有重新缩进）是为了不动原有的行，整合时可以格式化这一段。

**组件**：规则同 10.8"组件约定"（只管画、文字由调用方传、带语义标签、两套主题和两套尺寸、画廊里每种状态一项、有行为测试）。接口要点：

- 账号区：没登录（"登录"按钮、下面一行说明，`onLogin`）；已登录（头像字、显示名，点开菜单向上展开：`@用户名` 那一行、"退出登录"，菜单项由调用方给）；退出的页内确认条（问句、正文、两个按钮）。头像字由调用方算好传入（01 区块 D 的规则归 A）。
- 登录对话框：用户名、密码两个输入框（控制器由调用方给）、"登录"按钮（忙时转圈，输入框不可改）；错误文字三处：用户名框下、密码框下（服务器返回的错误也在这）、整块的"无法获取登录选项"加"重试"（`onRetry`）；回车提交。
- 簿切换下拉：当前簿名，旁边的权限文字和所有者（调用方拼好）；展开后有搜索框、簿的列表（簿名、权限文字、所有者、选中态）、底部一行说明；`onSelect`。
- 标签筛选条：第一项"未标记"（文字由调用方给），其余每项是 `LgDeviceTag` 加选中态（描边加勾，不用标签色铺满）；`onToggle`、`onContextMenu(tag, globalPosition)`（标签右键）；放不下时横向滚动。
- 地址簿"更多"菜单、只读簿的设备菜单：用现成的菜单项拼，组件块只核对 `p1-ab-more`、`p1-ab-readonly`、`p1-ab-readonly-card`。
- 其余小对话框（添加标签、重命名、编辑标签、编辑备注、设置共享密码、加入地址簿、查看所在地址簿）统一用表单外壳 `LgFormDialog` + `LgFormField` + `LgTextArea` 拼。忙态时正在操作的控件一禁用焦点就会掉，失败后由调用方把焦点放回出错的输入框（例如登录失败放回密码框）。
- 人员列表：搜索框；每行头像字、显示名、"我"标记；选中行带 ×（`onClear`）；`onSelect`。
- 卡片和列表视图的备注：`LgDeviceCard`、`LgDeviceRow` 加 `note`（null 不显示那一行或那一格），`LgDeviceColumn` 加 `note`，有没有这一列由调用方的表头决定（地址簿和同组设备有）。
- 列表状态：没登录（一句话加"登录"按钮）、网络错误（一句话加"重试"）、报错横幅（现有 `lg_banner.dart` 加"重试"按钮、可关闭，两句文字由调用方拼）、两类空、加载中骨架（现成的）。"服务器不提供地址簿"用空状态的样式。
- 添加设备对话框：ID、别名、密码（只在共享簿，下面一行提示）、备注（300 字上限）、标签选择（浅底小块，可多选）；提交中、ID 重复、簿满、服务器报错四种状态的文字由调用方给。其余小对话框见上一条，用 `LgFormDialog` 拼。
- 修改标签颜色对话框：预览（标签小块）、一排预设色、自定义（色相环加明度条，自己画，不引第三方依赖）、`#RRGGBB` 输入框（格式错误的提示文字由调用方给）；提交中、失败；结果是 ARGB 整数（和上游存的一样）。

**测试和合入**

- R：每个端点的请求（方法、路径、查询、体）、响应解析、状态码到错误种类的映射（两种 401、`currentUser` 400、`personal` 404、409、2xx 带 `error`）、分页去重和停止条件、缓存的写入和删除（个人簿的名字、令牌不同时清空）；对两种服务器的集成测试 `#[ignore]`，地址和测试账号由环境变量给。假 HTTP 服务照 `api.rs` 现有的测试起。
- core：A 的启动顺序（有没有本地用户 × `currentUser` 的几种结果）、登录、退出、`signedOutByServer` 复位、人员筛选和自己排第一；B 的权限判断、只读簿灰显项、标签筛选（并集和交集）、与最近会话同步的比对、`syncPeerHash`、退出后清空。都用 `FakeAccountApi`。
- app：每个页面状态一个行为测试。
- 改写档登记来源（10.1）：`account.dart` 改写上游 `models/user_model.dart`，`group.dart` 改写 `models/group_model.dart`，`address_book.dart` 改写 `models/ab_model.dart`；照上游 `common/widgets/login.dart`、`my_group.dart`、`address_book.dart` 重写的页面在文件头注明出处。
- 合入前：`git diff main -- flutter/` 为空；core 的 `flutter analyze --no-fatal-infos` 在 3.44.9 下不超出 92 条 info 的基线，app 0 条；复制件不跑格式化；改已有文件时不对整个文件跑 `dart format`，只格式化新文件。

**整合时要做的**

1. 合 R：重新生成块 2 的桥；`RustAccountApi` 的方法体换成 `lgBind` 调用加 `parseApiResult`；`core/test/fakes.dart` 的 `FakeLeapgate` 补上新导出（测试走 `FakeAccountApi`，补的可以直接抛错）。
2. 换上组件块的组件；`PeerCard`、`PeerTableRow` 在地址簿和同组设备里传 `note`，表头加备注列。
3. 合 A、B：两个 ARB 文件的末尾合并；`peer_views.dart` 里 `peerMenu` 的调用参数以 B 为准。
4. `shell/toast_view.dart` 的 `toastText` 补 B 的两个轻提示 `abToastAdded`、`abToastDeleted`（不补会显示键名）。

另外几处取舍：共享簿的默认共享密码（上游设备自己没存密码时退回用簿资料里的默认密码）不做，Leapgate 服务端的簿资料 `info` 恒为空；从地址簿连接时把地址簿别名抄到本机记录（上游行为）不做；网络错误时整块显示"无法连接服务器"盖住缓存，照 01 和上游；同组设备菜单照 01 没有"始终经中继连接""创建桌面快捷方式"，地址簿分类菜单照 01 有收藏项，删除标签照上游不确认。

**已知限制和与上游的不同**

- `leapgate_ab_books` 任一步失败整个失败；上游 `settings`、`shared/profiles` 失败时照样显示个人簿。两种支持的服务器都实现了这两个端点，失败多半是网络，整体重试就行。
- 缓存只存个人簿和最近拉过的共享簿（上游是"当前簿"，界面里两者相同）。
- `currentUser` 回 400 和 401 一样处理（理由见上面"错误的形状"）。
- API 地址不认程序文件名里带的配置。
- 地址簿正在拉取时，写操作之后的静默重新拉取被跳过，那次拉取的结果可能盖掉刚做的本地改动，直到下一次拉取（上游 `abPulling` 同样）。
- 从连接框搜到别的共享簿里的设备，连接时不带那本簿的共享密码，只看当前簿（上游 `connectInPeerTab` 同样）。
- 退出后马上用同一账号登回来，旧那轮拉取在簿列表回来之前分不清两次登录，可能接着写完（数据是同一账号的）；簿列表回来之后的部分已挡住（地址簿按"拉取开始时的用户名"和"簿列表是否被换掉"核对）。彻底分清要代次计数，不做。
- 退出后马上用同一账号登回来，旧令牌的请求（`refresh()` 的 `currentUser`，地址簿和同组设备在途的拉取、写入，所有导出都一样）12 秒内回 401 时，Rust 那边因为令牌已换、不清新登录，Dart 这边却调了 `signedOutByServer()`：界面显示没登录，下次启动又显示已登录（Dart 侧只按用户名丢弃账号变了以后的回答，令牌的比对只在 Rust 侧）。
- 菜单的语义（排查文档 §10）：菜单行文字的提示锚点不成孤儿，菜单行带 `button` 标志。还剩两种孤儿，0003 丢掉它们不少信息：菜单行尾部带提示的按钮（目前只有"输入系统密码"那行的编辑按钮）、悬停放不下的文字时提示浮层自带的空节点。`LgTextField` 尾部的按钮（显示 / 隐藏、清除）是同一类缺 `button` 标志的问题，没修。
- 在最近、收藏、局域网里点"清除保存的密码"：本机密码先清掉，再清个人簿里的 `hash`；后一步失败（例如网络错误）时本机已清，错误只显示在地址簿的横幅里（上游同样）。
- 启动时先显示缓存、服务器回答之前，共享簿一律按只读显示（簿切换写"只读"、写操作灰显），时间很短。
- 正在登录时点"取消"或按 Esc 关掉对话框，请求仍会完成并登录上（上游相同）。
- 启动时核对账号遇到网络错误，同组设备整个列表换成"无法连接服务器"，已显示的缓存被盖住（上游 `netWorkErrorWidget` 相同）。
- 每个请求新建一个 reqwest 客户端，分页每一页都重新建连接和握手（同 `api.rs` 现有的请求，上游也是每次新建）。
- 服务器上名叫 `My address book` 的共享簿会被当成个人簿（`AbEntry::personal()` 按名字认，上游用簿名做键，有同样的歧义）。Leapgate 服务端不许共享簿用这个名字，rustdesk-api 不拦。

**H1 的实现结论**

- 代码：`api.rs` 的 `bearer`（令牌为空时不带 `Authorization`，登录和登录选项用）；`libs/leapgate/src/account/` 的 `mod.rs`（账号四个端点、状态码映射、分页、令牌和 `user_info`）、`ab.rs`、`group.rs`；`src/leapgate_ffi.rs` 末尾 17 个导出。设备 ID、UUID、登录设备信息在导出里、进运行时之前取：桌面上 `get_id` 经 IPC 问服务，自己会起运行时，放进 `#[tokio::main]` 里就是嵌套运行时。令牌、`user_info`、两份缓存经一个小接口 `Store` 读写，正式实现就是 LocalConfig 和 `config::{Ab, Group}`，测试换成内存里的，免得单测写进本机的配置目录。
- 和上面约定的出入（都不改界面的用法）：
  - `leapgate_ab_books` 的 `shared`、`leapgate_ab_book` 的 `tags` 是服务器给的原样对象，会多出字段（rustdesk-api 的标签带 `id`、`user_id`、时间），界面按字段名取。
  - 所有分页请求都同时带 `current` 和 `page`，不止 `users`、`peers`（Leapgate 服务端不认识的参数照常忽略）。每页 100 条，同上游。
  - `leapgate_account_login_options` 不带令牌，非 2xx 一律报 `server`、不清登录。
  - `leapgate_ab_book` 在 `personal` 为真时，缓存条目的名字固定写 `My address book`，不用传进来的 `name`；个人簿条目的 `guid` 写真实的（上游写空串，没有读者在意）。
  - 每个导出在 frb 各自的线程上跑，两份缓存是"读出、改、写回"，所以加了一把进程内的锁（`account::CACHE`）：写 `_ab`（核对令牌加读改写）、写 `_group`（核对令牌加写）、退出和令牌失效时的清理、读缓存都在锁里做，都是同步的一小段，不跨 `.await`。不加锁时两本簿同时拉完会互相覆盖，个人簿条目连同 `hash` 丢掉，自动填密码静默失效。
  - 一次操作（拉簿列表、拉一本簿、拉同组设备、一次写、当前用户）开头取一次令牌，所有请求都用它。回 401 时只有这个令牌仍是当前令牌才清登录：退出后马上重新登录时，旧操作迟到的 401 不会把新登录清掉。拉取过程中退出了登录：写缓存前在锁里核对令牌，变了就不写，免得把刚删掉的缓存写回来；`currentUser` 成功时同样在锁里核对令牌、没变才重写 `user_info`（登录消息的显示名和本机显示名不看令牌、直接读它）。
  - 2xx 但内容不是这个端点该回的形状，报 `server`，文字 `HTTP 200`。写操作的 2xx 只认空体或不带 `error` 的 JSON，非 JSON 的内容（例如代理插进来的网页）报 `server`（上游 `_jsonDecodeActionResp` 同样算失败）。`ab/tags` 回 `null` 当没有标签（rustdesk-api 簿里没有标签时）。
  - `_group` 缓存按 `config::Group` 的字段写（用户 `name`、`display_name`；设备 `id`、`username`、`hostname`、`platform`、`login_name`），没有备注和设备组名：上游缓存本来就不存备注，`Group::load` 也会丢掉设备组名。`leapgate_group_cache` 给的设备是这种缓存格式，不是 `/api/peers` 的原样。
  - 日志：非 2xx 只记路径和状态码，连不上记路径和错误描述，两处各自每分钟最多一行（`throttled_log`）；登出失败另记一行。
- 测试：`libs/leapgate` 单测里起最小的假 HTTP 服务，覆盖每类端点的请求、两种 401、旧令牌的 401 不清新登录、`currentUser` 400、`personal` 404、404/409、2xx 带 `error` 或非 JSON、两种分页停止（各自单独起作用）、缓存的写入、替换、令牌不同时清空、登出和 401 时删除、拉取中途退出不写回、两本簿同时保存都留下）；对真实服务器的集成测试 `account::live_tests::live_account_flow`（`#[ignore]`，环境变量见文件头）。core 的 `RustAccountApi` 用假绑定测了一条。
- 对 Leapgate 服务端和 rustdesk-api v2.7 实测，两者在下面几处不同，导出都能处理：
  - rustdesk-api 的登录选项回的是登录方式列表（例如 `["common-oidc/[…]","oidc/webauth"]`），只看 2xx，不受影响。
  - rustdesk-api 密码错回 400 `Username or password error.`，归 `server`，文字照原文显示；改名到已有的标签名、改不存在的设备或标签回 400（`Item already exists.`、`Item not found.`），也归 `server`，Leapgate 服务端分别是 `conflict`、`not_found`。
  - rustdesk-api 不存设备的 `note`（读回 `null`），标签改名不级联到设备上的标签；删除的标签名里有一个不存在时整个请求失败，Leapgate 服务端忽略不存在的。
  - rustdesk-api 的 `ab/peers` 不看任何分页参数、每次回全部条目，靠"某一页没有新 ID 就停"收住；`users` 认 `page`、不认 `current`。
  - 只读簿写入两边都拒绝（Leapgate 服务端 403，rustdesk-api 400 `No access.`），都归 `server`；rustdesk-api 在读写簿里删设备也要完全控制。
  - rustdesk-api 的 `max_peers` 是 0（不限）。
- rustdesk-api 的几处行为（找不到、重名都回 400，读写簿不能删设备，不存备注，标签改名不级联）是它自己的，界面照 `server` 显示服务器原文，不另做适配。

### 10.12 M5 的分工约定

M5 是出口页。界面行为以 01 §3.1 区块 I（出口页）、区块 C（导航）、区块 E、F（"用作出口"入口）、§2.1（窗口关闭）为准；样稿 `A-P1.html` 的 `p1-exit-*`、`p1-ex-*`、`p1-xc-*`、`p1-close-exit`、`p1-cb-menu`、`p1-menu-more-top`。出口本身的实现说明在 §9。

**分支和文件边界**（都从 `ui/m5` 切，做完合回 `ui/m5`）

| 分支 | 块 | 只改这些 |
|---|---|---|
| `ui/rust-exit` | Rust（E1~E3） | `src/leapgate_hooks/exit.rs`、`src/leapgate_ffi.rs`（末尾追加 M5 一段）、`libs/leapgate/src/exit/`（状态类型和 JSON，新文件或追加）、`src/port_forward_mux.rs`（只加 `Tunnel::ended()`，带 `// leapgate:` 注释）、本节的 Rust 部分 |
| `ui/m5-ds` | 组件 | `app/lib/widgets/`（新组件；`LgTitleBar` 加提醒标记的参数）、`app/lib/gallery_*.dart`、组件的测试 |
| `ui/m5-exit` | E（core 和出口页） | core `leapgate/exit_api.dart`、`exit_directory.dart`、`exit_nodes.dart`、`exit_card.dart`（都是新文件）、`app_core.dart`（加出口 model 一处）、`peer_list.dart`（加 `PeerAction.useAsExit` 和条件）、`consts.dart`（只追加选项键）；app `pages/home/exit/`（新目录）、`home_page.dart`（出口页分支、导航数字）、`main_window.dart`（主页标签的数字和提醒）、`shell/window_close.dart`（出口那句和便携版的退出确认）、`shell/navigation.dart`（打开出口页并使用某台设备）、`peer_views.dart`、`devices_page.dart`（两处下拉加"用作出口"）；ARB；测试 |

- ARB 键以 `exit` 开头，加在两个 ARB 文件末尾，中英文同时加，文案照 01：区块 I 里写好的句子逐字照抄，英文照 §7.5 新加的两行；新写的句子列进提交说明。
- E 先用 M0~M4 的组件和简单的占位控件把逻辑写通，整合时换成组件块的组件。占位不求好看，但行为测试要能按文字和语义标签找到它们。
- `RustExitApi` 调块 2 的真实导出；测试一律用 `FakeExitApi`（放 `core/test/exit_fakes.dart`）。

**Rust 导出（块 2）**

| 导出 | 参数 | 返回 / 事件 |
|---|---|---|
| `leapgate_exit_session_add` | `session_id: SessionID`、`id: String`、`port: i32`、`password: String`、`is_shared_password: bool`、`conn_token: Option<String>`、`force_relay: bool` | `SyncReturn<String>`：成功 `{}`；失败 `{"error":"already"}`（这台设备已有出口或端口转发会话）、`{"error":"invalid_port"}`（不在 1~65535）、`{"error":"invalid_id"}`（上游建会话时改写了这个 ID，例如 `ID@服务器?key=…`、末尾的 `/r`；卡片按原样的 ID 登记和查找，改写过的找不到）、`{"error":"other","text":…}`。成功后界面照常调第一块的 `bind.sessionStart(sessionId, id)` 拿这个会话的事件流 |
| `leapgate_exit_events` | `sink: StreamSink<String>` | 新订阅替换旧的；订阅时先把每张卡片的当前状态各推一次。每条 `{"id":设备ID,"session_id":会话ID,"port":端口,"state":…}`，`state` 见下；`session_id` 是这张卡片的出口会话的 SessionID 字符串（和 `leapgate_exit_session_add` 收到的同一个），界面停止一张卡片后马上对同一台设备再"使用"时，按它丢掉旧会话迟到的事件（补推的当前状态也带） |
| `leapgate_exit_retry` | `id: String` | `SyncReturn<bool>`（没有这张卡片为假）：清冷却、马上登录。"重试"（已停止）和"重新连接"（暂时断开）共用 |
| `leapgate_exit_set_port` | `id: String`、`port: i32` | `SyncReturn<bool>`：关旧监听、在新端口监听，隧道保留；新端口被占时推 `port_in_use` |
| 停止、取消 | 第一块现成的 `bind.sessionClose(sessionId)` | 卡片模式收到关闭后关监听、关隧道（登录中也能取消，见下），推 `closed` |
| 目录 | 第一块现成的 `bind.mainGetCommon(key: 'leapgate-exits')` | `{"state":"ok","exits":[{"id","hostname","owner","own"}]}` / `unsupported` / `not_logged_in` / `error`，不改 |
| 路径和中继名 | 现成的 `leapgate_session_connection(session_id)` | 出口卡片不用 |

`state` 的取值：
- `connecting`：首次登录或懒重连正在进行。输密码、2FA、等对方接受这几步看会话事件流，E2 只说"正在连接"。
- `in_use`：带 `"transport":"direct"|"relay"`。
- `interrupted`：带 `"cause":"tunnel_ended"|"login_failed"`；`login_failed` 时带 `"retry_after_ms"`（冷却剩余，界面不显示）。
- `stopped`：监听已关、运行实例在等重试或关闭。Rust 知道原因时带 `"reason"`（C3 的 `Reason` JSON）：`exit_not_supported`、不安全提示被拒后的 `exit_need_encryption`；被控端拒绝登录时不带，界面取会话流里最后一条的原因码。
- `port_in_use`：带 `"port"`。
- `closed`：卡片模式结束。

**Rust 的做法和约束**
- `leapgate_exit_session_add` 照 `session_add`（`src/flutter.rs:1301-1380`）抄，固定 `ConnType::PORT_FORWARD`，`args = [端口, 出口哨兵地址, "65536"]`，走 `io_loop` 现成的三参数分支（`src/ui_session_interface.rs:2050-2069`），不碰设备配置里的 `port_forwards`；去掉 `LocalConfig::set_remote_id`；先查 `get_session_by_peer_id(id, PORT_FORWARD)`，有了就回 `already`；登记进 `exit.rs` 的卡片登记表（键是设备 ID）。
- `exit.rs` 的 `run` 开头按卡片登记表分流：查到就进卡片模式 `run_card`，查不到走原来的懒登录。原来的 `run`、`serve` 一行不动。
- `run_card`：起监听 → 失败推 `port_in_use`，等改端口或关闭（不登录）→ 成功就立刻登录。第一次登录的占位连接三条约束：监听起来后**先**接受自己连自己的那条占位连接，**再**开始接真实客户端；占位连接不交给 SOCKS / HTTP 握手；登录函数返回后两头一起丢，不开通道。代码注释写清原因。
- 取消：`run_card` 自己持有会话的接收端，登录和关闭信号放进同一个 `select!`；收到 `Close` 就关监听、关掉转给登录的那个接收端，等登录自己收尾后推 `closed`；其余 `Data`（`Login`、`Message`、`ContinueInsecureConnection` / `RejectInsecureConnection`）转给登录。登录（`connect_and_login_mux`，上游函数里加了两处 `leapgate:`）看到接收端关了就先丢 stream 再 `release_kcp`、返回 `Ok(None)`，走 KCP 时 FIN 也能发出去，被控端当场关连接、CM 消失；登录恰好在关闭时完成的，也照 K0 先丢 stream 再 `release_kcp`。不能直接丢掉登录：KCP 守卫跟着丢、端点当场中止，被控端要等自己的超时：上游 IPv6 打洞的 KCP 没有 20 秒静默关闭，一般是约 30 秒的空闲超时先到（登录等待期间控制端仍回 TestDelay，空闲计时从最后一条消息算），取消得晚时由 180 秒的登录期限先关。已知限制：卡片停在"不安全连接"提示时取消，`connect_and_login_mux` 在提示返回 false 后直接 `return`，守卫照旧被丢，被控端约 30 秒后才关；在提示上点"拒绝"也一样，这是上游原样的行为，改它会连带改旧界面拒绝不安全连接的路径，不改。
- 登录结局照 `serve` 的三种处理守卫（K0）：可用 → `set_muxed`，推 `in_use`；被拒 → 先丢 stream 再 `release_kcp`（`exit.rs:165-169`），关监听，推 `stopped`，运行实例不退出、原地等重试或关闭；临时失败 → 推 `interrupted`（`login_failed`），记冷却。
- 隧道结束：`Tunnel::ended()`（`self.state.subscribe()` 后等到不再是 `Muxed`），推 `interrupted`（`tunnel_ended`）；之后照 C9 由下一条本地连接触发懒重连（推 `connecting`）。
- 事件推送照 M3 的 `leapgate_cm_events`：块 2 一个全局 `StreamSink<String>`，不经会话事件流、不经 `libs/leapgate` 的广播。
- 状态类型和 JSON 放 `libs/leapgate`，带单测。

**会话事件流里卡片要看的**（第一块 `sessionStart` 的流，msgbox 的 `type`）：`input-password`、`re-input-password`（密码错）、`input-2fa`、`wait-remote-accept-nook`、`insecure-connection*`（卡片直接回 `RejectInsecureConnection`，显示"已停止：此连接未加密，无法用作出口"）；错误框的 C3 原因码里 `exit_blocked`、`exit_fake_ip_literal` 是**卡片通知**（同一原因只提示一次、可关），不是失败；`exit_not_enabled`、`exit_not_supported`、`exit_need_encryption`、`too_many_attempts`、`peer_too_old` 是"已停止"的原因；`local_port_in_use` 以 E2 的 `port_in_use` 为准。两条流没有先后保证，卡片状态以 E2 为准，会话流只补"要输入什么"和失败原因。

**core（E）**
- `exit_api.dart`：`abstract interface class ExitApi`（`sessionAdd`、`events`、`retry`、`setPort`、`close`、`directory`、`connection`），`RustExitApi`（调块 2 导出），全局 `exitApi`（测试里换成 `FakeExitApi`），照 M4 的 `account_api.dart`。
- `exit_directory.dart`：`ExitDirectoryModel`，状态 `loading / ok / empty / unsupported / notLoggedIn / error`；没登录时不发请求；打开出口页时取一次、"刷新"再取，不轮询；实现 M4 的 `AccountData`（退出登录清空）。目录回 `not_logged_in` 而账号区仍是已登录时，调 `appCore.account` 的当前用户确认一次（服务端回了 401 时按 M4 的令牌失效走）。
- `exit_nodes.dart`：`ExitNodesModel`，进 `AppCore`：卡片列表（按添加顺序）、`use(id, {String? name})`（已有就返回那张）、`remove(id)`、`runningCount`（本地监听开着的卡片：正在连接、要密码、要验证码、正在验证、等对方接受、在用、暂时断开）、`needsAttention`（任一卡片在要密码、要验证码、等对方接受）、端口：本机配置一张表，键 `leapgate-exit-ports`（LocalConfig，JSON `{设备ID: 端口}`），建议值从 21180 起，跳过别的卡片在用的和表里别的设备记过的；改端口撞上另一张卡片时不调 Rust，直接报"此端口已被另一个出口使用"。卡片只在内存里，重启不恢复。退出登录不动卡片。
- `exit_card.dart`：`ExitCard`，一张卡片一个出口会话（`SessionID` 由卡片生成）：订阅这个会话的事件流和 E2（按设备 ID 过滤），状态 `connecting / password / twoFactor / verifying / waitAccept / inUse(direct|relay) / interrupted / stopped(reason) / portBusy`；动作 `submitPassword(password, remember)`、`submit2fa(code, trust)`、`cancel()`、`stop()`（停止和移除都是它：`sessionClose` 后从列表移走）、`retry()`、`changePort(port)`；通知集合按原因去重、可关。"要输入什么"的判断照 `ConnectionModel`（`connection.dart:225-262`）抄一份，不改 `ConnectionModel`。
- **出口会话不登记进 `appCore.sessions`，不建 `FFI`，不用 `ConnectionModel`**：注册表里的会话关主窗口时会被一起关掉（`window_close.dart:83-87`），`ConnectionModel` 的自动重试会让 Rust 再起一个运行实例抢端口。

**app（E）**
- `pages/home/exit/exit_page.dart`（页面、三块、滚到卡片和高亮、按 ID 指定：只收设备 ID 去空格和 `ID@服务器`）、`exit_card_view.dart`（`ExitCard` 到卡片组件的映射、文案；"已停止"的原因文字用 `pages/session/reasons.dart` 的 `reasonView`）、`exit_directory_view.dart`。
- "用作出口"：`PeerAction.useAsExit`，在连接方式组，**对端**平台是 Windows 时才列（菜单现有的 `windows:` 参数是本机平台，另加一个参数），手输 ID 的"连接到 ‹输入›"行照常列；点了等于目录里点"使用"：切到主页标签的出口页、`use(id)`、滚过去。
- 导航"出口"和主页标签：数字 `runningCount`，提醒 `needsAttention`；出口页正显示时导航上不画提醒；读屏名"出口，‹N› 个正在使用"，有提醒时加"，需要处理"。
- 关窗：有出口在跑时，动作是"在后台运行"或安装版关窗才加"‹N› 个出口将在后台继续运行。"；便携版动作是"退出 Leapgate"（包括记住了"退出"、没有会话不再问的情况）时仍确认：标题"退出 Leapgate？"，正文"‹N› 个出口将停止。"，按钮"退出""取消"。

**组件**：规则同 10.8"组件约定"（只管画、文字由调用方传、带语义标签、两套主题和两套尺寸、画廊里每种状态一项、有行为测试），加 10.8 的"合并语义的容器里不放带浮层的组件"。要做的：出口页版式、出口卡片（含验证码态、端口被占用加"移除"、暂时断开加地址行，这三张样稿没画，照现有画框推）、卡片里原地改端口、浏览器设置说明展开块、目录行、线性不定进度条、按 ID 指定行、导航项的数字和提醒标记、`LgTitleBar` 主页标签的提醒标记、滚到卡片后的短暂高亮。

**测试**
- R：状态类型的 JSON；`run_card` 的三种登录结局和守卫交还；中途取消；改端口；`already`；旧的 `run` / `serve` 测试照常过。
- E：卡片状态在两条流下的走向（含先后颠倒）；目标被拦按原因去重；`runningCount`、`needsAttention`；端口建议值和撞端口；退出登录只清目录；页面三块的各态；"用作出口"只在对端是 Windows 时出现；关窗两种文案。

**已知限制（界面一侧）**
- 会话流里 `relay-hint` 这类提示卡片不处理：出口没有"改用中继"，这种失败只进"暂时断开"。
- 目录回"没登录"而账号确认碰上网络错误时，目录显示"登录后可查看出口目录"加登录按钮，账号区仍是已登录。
- 两条流先后颠倒：已停止时点"重试"当场清掉原因、进"正在连接"；E2 的 `connecting` 只在从"暂时断开"进来时清原因；已停止或端口被占用时收到的输入提示丢掉。这只缩小空当，新旧两轮登录要彻底分开得靠 Rust 在事件里带轮次序号。
- ID 也收字母以后，连接框里输入 `study-pc` 这类 6~16 个字符的名字，"连接到 ‹输入›"行的"⋯"里也会出"用作出口"，点了会去连一个可能不存在的 ID，卡片进"已停止"（取舍，不改）。
- 起会话后几毫秒内就关：Rust 的会话主循环还没设好发送端，关闭消息会被上游静默丢掉，会话照常起监听和登录，界面上看不到（上游所有会话都有这个空当）。
- 停止要等关会话的异步调用回来才移卡片，这几毫秒里再"使用"同一台设备会拿到正在移除的旧卡片，那次点击落空。

**Rust 实现说明**

- 代码：
  - `libs/leapgate/src/exit/card.rs`：卡片状态 `State`（带 `Transport`、`Cause`）、事件 JSON `event(id, session_id, port, &State)`、`stopped(msg, insecure_refused)`（Rust 知道的两种原因）。
  - `src/leapgate_hooks/exit.rs` 末尾的 `cards` 模块：卡片登记表（键是设备 ID，值是代号 `gen`、最后一条事件、控制通道）、`session_add`（E3）、`run_card`、`retry`、`set_port`、`set_events`。`run` 开头加了 4 行分流（`cards::take` 拿到就进 `run_card`），`run` 的其余部分和 `serve` 一行没动。
  - `src/port_forward_mux.rs`：`Tunnel::ended()`，6 行。
  - `src/leapgate_ffi.rs` 末尾四个导出：`leapgate_exit_session_add(session_id: SessionID, id: String, port: i32, password: String, is_shared_password: bool, conn_token: Option<String>, force_relay: bool) -> SyncReturn<String>`、`leapgate_exit_events(sink: StreamSink<String>) -> ResultType<()>`、`leapgate_exit_retry(id: String) -> SyncReturn<bool>`、`leapgate_exit_set_port(id: String, port: i32) -> SyncReturn<bool>`。Android、iOS 上是空实现：`session_add` 回 `other`，`retry`、`set_port` 回假。
- 和约定不同的地方：
  - 占位连接不连卡片自己的端口，而是另开一个只用一次的回环监听（`127.0.0.1:0`）连成一对，登录用其中一头。约定的三条约束因此都自然成立：浏览器早就指着卡片端口时，它的连接照常进握手、排队等登录结束，不会被当成占位连接；占位连接不经过卡片的监听，进不了 SOCKS / HTTP 握手；登录返回后两头一起丢，不开通道。连自己端口的写法还得按地址认出哪条是自己的，多一段判断，结果一样。
  - `port_in_use` 不另带 `port` 字段：事件顶层的 `port` 就是被占的端口（每条事件的 `port` 都是卡片当时在用或刚试过的端口，改端口后是新端口）。
  - 改端口先关旧监听再开新的，所以改成原来的端口也行。新端口被占时旧监听已经关了，卡片进 `port_in_use`，隧道仍保留；再改一个能用的端口就回到 `in_use`，不重新登录。新端口开好时如果没有隧道（一开始就被占、暂时断开、已停止），马上登录，和"重试"一样。`set_port` 的端口不在 1~65535 时直接回假，不推事件。
  - 登录结局照 `serve` 仍各调一次上游的提示：版本不支持时 `on_error`，临时失败时 `on_establish_connection_error`。会话事件流里因此有原来的错误框，界面取失败原因用它；卡片状态以 E2 为准。
  - `stopped` 的 `reason` 是 C3 `Reason` 的 JSON 对象，例如 `{"code":"exit_not_supported"}`、`{"code":"exit_need_encryption"}`。
  - 新订阅补发的是每张卡片最后一条事件的原文，`interrupted` 里的 `retry_after_ms` 是推出时的值（10000），不扣掉已经过去的时间（界面不显示它）。
  - 为了不接真实对端也能测，`run_card` 对会话的要求收成一个小接口 `CardSession`（登录、隧道建立后发连接就绪事件两个方法），正式实现就是 `Session<T>`，测试换成假的。
- 已知限制：
  - 登录中途取消时，登录还在上游 `Client::start` 里（打洞、连中继）的话，要等它连上或失败才收尾（登录循环开始前先看接收端，关了就直接关连接，不向被控端发登录请求）；监听当场关，卡片在界面上当场消失，只是 Rust 这边的会话线程多留一会儿。收尾时 `release_kcp` 最多再等 10 秒。
  - 旧界面懒登录中途关隧道窗口时，`Close` 仍被上游登录循环吞掉，监听一直留着（不修）。
  - 登录进行中收到的"重试""改端口"排队，等这次登录结束再处理。
  - 刚 `session_close` 一张卡片、它的运行实例还没关掉监听时，马上为同一台设备再 `session_add`，新卡片可能先报 `port_in_use`（端口还被旧的占着），再"重试"一次就好。登记表按代号区分新旧卡片：新卡片登记以后，旧卡片的事件不再推出、清理也不会删掉新卡片的登记；新卡片登记之前已经推出的旧事件，界面按 `session_id` 丢掉。
  - 加了会话却一直没调 `session_start` 的卡片会留在登记表里（只是一条记录，不占端口），下次为同一台设备 `session_add` 时被替换；它还没有事件，订阅时不补发。
  - 改端口时先关旧监听，新端口被占时两个端口都不在听：卡片进 `port_in_use`，由用户再改一个。这时隧道断了也仍报 `port_in_use`（没有监听，谈不上暂时断开）。
  - 界面不能对出口会话调 `sessionReconnect`：上游会另起一个 `io_loop`，和正在跑的卡片抢同一个端口（所以界面不调）。
  - 停掉一张走 KCP、隧道正在用的卡片时，`run_card` 丢掉隧道后马上返回，会话的运行时随 `io_loop` 结束，隧道任务和它后面的 `release_kcp` 来不及跑完，KCP 发不出 FIN，被控端要等约 20 秒静默关闭；登录被拒、守卫刚交给 `release_kcp` 后不久（对端常不回 FIN，`release_kcp` 通常等满 10 秒，§9 K0）就关卡片，同样会被截断。要修得让 `run_card` 返回前等这些任务做完：被拒那一路要在循环里记下任务句柄；隧道那一路要改 `port_forward_mux.rs` 的 `set_muxed` 交出它起的任务。都是新加的状态，不做；改成在循环里直接等 `release_kcp` 也试过，卡片会有几秒不响应"重试"和关闭，没采用。
- 测试：`libs/leapgate` 2 个（每种状态的事件 JSON、`stopped` 的原因）；根 crate `leapgate_hooks::exit::cards` 7 个，用假会话和本机回环连接：登录成功后第一个通道是本地程序的（占位连接没开通道）、对端断开后进 `interrupted`（`tunnel_ended`）；版本不支持时进 `stopped`（`exit_not_supported`）、监听关掉、KCP 守卫交给 `release_kcp` 后对端收到关闭（把守卫改成直接丢掉，这个测试会失败），"重试"后不安全连接被拒进 `stopped`（`exit_need_encryption`），再"重试"进 `in_use`；临时失败进 `interrupted`（`login_failed`，`retry_after_ms` 10000）、监听留着，"重试"马上登录；登录中途关闭，1 秒内卡片关掉、端口不再接受连接并能被别的程序占用；改端口后旧端口关掉、新端口的连接走原来的隧道（没有第二次登录）；端口被占时不登录，改端口后登录；`retry`、`set_port` 只对登记过的卡片和合法端口生效。端口关没关用连接去试（3 秒内不再接受连接即可）：整套测试一起跑时，丢掉的监听在 Windows 上还会接受连接约 1 秒，单独跑时当场关。
- 只有新界面调的几个（`register`、`retry`、`set_port`、`send`、`NEXT_GEN`、`Card.ctl`）带 `#[cfg(any(feature = "flutter", test))]`，`Ctl` 在不带 flutter 时允许未构造，默认特性的 `cargo check --lib` 不报它们未使用。
- 单测没覆盖、要真实对端或上游会话表的：`already`、`invalid_id`（要上游的会话表；单测里建会话会在本机配置目录写一份设备配置，并经 IPC 把会话数报给正在运行的服务，所以不做）；经 frb 的实际调用；真实对端下的密码、2FA、等对方接受、不安全连接提示（卡片回拒绝之后带 `exit_need_encryption` 那一步用假登录结果验了）；`connection_ready` 之后 `leapgate_session_connection` 给出的路径；中途取消时被控端当场关（单测用假登录验了 `login_or_close` 让登录自己收尾，`connect_and_login_mux` 里那两处要真实对端）；登录被拒时被控端 CM 当场消失（03 §8.5 第 9 项）。

**组件接口**

组件都只画：参数是普通的值、数据类和回调，文字全部由调用方传，不引用 core 的 model、会话对象和 `bind`。每个参数、每种状态在画廊（`app/lib/gallery_m5.dart`，分区 `exit-card`、`exit-grid`、`exit-page`、`exit-directory`、`exit-by-id`、`exit-parts`、`exit-reminder`）里有一项，行为测试在 `app/test/exit_components_test.dart`。

文件：`app/lib/widgets/lg_exit_card.dart`（卡片、卡片格栅、短暂高亮）、`lg_exit_page.dart`（页面版式、目录、目录行、按 ID 行、进度条、空状态条）。已有组件只加了参数，默认值不变：`LgButton`（`iconSize`、`trailingIcon`、`expanded`）、`LgTextField`（`showErrorText`，为假时框和读屏名照样说有错、但不画框下那一行，调用方自己画）、`lg_status.dart`（新增 `LgCountMark`）、`LgTitleBar`（`homeAlert`、`homeSemanticLabel`）。`gallery_export_test.dart` 多加载了 Consolas（启动参数用等宽字体）。

**`LgExitCard`**（卡片，一张一台设备）。从上到下：设备头、状态行、要输入的区（密码或验证码）、两行地址、通知、改端口或按钮行、展开的说明；为空的部分不画，卡片随状态长高缩短（说明展开有 160 ms 动画，系统要求减弱动效时没有）。整张卡片是一个读屏分组，名字默认 `"$name $id"`，头里的文字只给眼睛看。

| 参数 | 类型 | 说明 |
|---|---|---|
| `name`、`id`、`platform` | `String`、`String`（已格式化，如 `912 345 678`，身份色从它取）、`LgPlatform` | 名字太长时省略，悬停显示全文 |
| `status` | `LgExitStatus(kind, label, {reason, elapsed, note})` | `kind`：`busy`（转圈）、`password`（钥匙）、`code`（盾牌）、`direct`、`relay`（连接方式标记，详细模式画路径）、`warning`、`error`。`label` 粗体、取状态色；`reason` 紧跟其后、常规字重、正文色（"已停止："加原因）；`elapsed` 画在 label 后面、同一行、同样粗体同色（"（已等待 0:12）"，英文要自带前导空格）；`note` 是旁边的灰色小字（经中继的说明），可换行。只有标记、`label`、`reason` 是读屏的实时区，变化会被念出来；`elapsed` 和 `note` 在实时区外、当普通文字读，不然计时每秒念一次（会话面板的"已等待"也这样）。调用方每秒换一次 `elapsed` |
| `password` | `LgExitPasswordArea?` | 密码框（带显示 / 隐藏）、"记住密码"勾选；字段：`controller`、`semanticLabel`、`placeholder`、`showLabel`、`hideLabel`、`rememberLabel`、`remember`、`onRememberChanged`、`onSubmitted`（框里按回车）、`onChanged`、`focusNode`、`errorText`（"密码错误"，框变红、下面一行常规字重）、`enabled`。自动聚焦只是兜底，焦点约定见"整合时要注意的" |
| `code` | `LgExitCodeArea?` | 和会话面板同一个六格框；字段：`semanticLabel`、`trustLabel`、`trust`、`onTrustChanged`（三个都可空：`trustLabel` 和 `trust` 都给了才画"信任本机"勾选，对方没开受信设备时都不传）、`onCompleted`（输满最后一位时调一次）、`onChanged`、`controller`、`focusNode`、`errorText`、`enabled`、`length`。自动聚焦同上 |
| `addresses` | `List<LgExitAddress>` | 每项 `address`、`copyLabel`（"复制 SOCKS5 地址"，也是读屏名）、`onCopy`；地址长了省略。两行之间 4 px |
| `notices` | `List<LgExitNotice>` | 每项 `id`（原因，用作 key，关掉一条不影响另一条）、`text`、`dismissLabel`、`onDismiss`；信息语气，不打断 |
| `portEdit` | `LgExitPortEdit?` | 非空时按钮行让位给它：只收数字、最多五位的框（最宽 160）、"确定"、"取消"；字段：`controller`、`semanticLabel`、`confirmLabel`、`cancelLabel`、`onConfirm`（为空则"确定"禁用、回车无效）、`onCancel`（Esc 也调它）、`hint`（框下小字）、`errorText`（有错时代替 `hint`，框变红，错误文字读屏时只在框的名字里念一次）、`focusNode`。自动聚焦同上 |
| `leadingActions`、`actions` | `List<LgExitAction>` | 按钮行：左边是文字按钮、右边是主要按钮和描边按钮。`LgExitAction(label, onPressed, {kind, icon, expanded, semanticLabel})`；`onPressed` 为空时禁用（不响应、Tab 跳过）；`expanded` 非空时按钮后面画箭头并告诉读屏展开了没有。左边第一个按钮向左探出 8 px，图标和上面的文字对齐 |
| `help` | `LgExitHelp?` | 展开的"浏览器设置说明"：`title` 加 `items`；每项 `LgExitHelpItem(text, {code, after})`，`code` 用等宽字体，整块可以用鼠标选中复制。展开和收起由调用方切换 `help` 是否为空，同时切换"浏览器设置说明"那个按钮的 `expanded` |
| `semanticLabel` | `String?` | 整张卡片的读屏名 |

九种状态对应的参数（01 区块 I 的表；文案照 01 §7.6 和第 7.5 节的英文）：

| 状态 | `status` | 其余 |
|---|---|---|
| 正在连接 | `busy`，"正在连接 ‹设备名›…" | `actions`：取消（`secondary`） |
| 要密码（含输错） | `password`，"输入密码" | `password`（输错时带 `errorText`）；`actions`：连接（`primary`）、取消（`secondary`） |
| 要验证码 | `code`，"输入验证码" | `code`（对方开了受信设备才带"信任本机"勾选）；`actions`：验证（`primary`）、取消（和会话面板同一个主按钮和文案，01 已改） |
| 正在验证 | `busy`，"正在验证…" | `actions`：取消 |
| 等对方接受 | `busy`，label 写"正在等待对方接受…"，`elapsed` 写"（已等待 0:12）" | `actions`：取消；计时归调用方，每秒换一次 `elapsed` |
| 在用 | `direct` "可用 · 直连" 或 `relay` "可用 · 经中继"（带 `note`） | `addresses` 两行；`leadingActions`：修改端口（`LgIcons.edit`）、浏览器设置说明（带 `expanded`）；`actions`：停止（`secondary`，`LgIcons.square`）；`notices`、`help` 按需 |
| 暂时断开 | `warning`，"连接已中断，下次有应用使用此代理时将自动重新连接" | `addresses` 两行；`actions`：重新连接（`primary`，`LgIcons.restart`）、停止（`secondary`，`LgIcons.square`） |
| 已停止 | `error`，label "已停止："、`reason` 是原因 | `actions`：重试（`primary`，`LgIcons.refresh`，只有未开启、验证次数过多两种有）、移除（`secondary`，`LgIcons.trash`） |
| 端口被占用 | `error`，"本机端口 ‹端口› 已被其他应用占用" | `actions`：修改端口（`primary`，`LgIcons.edit`）、移除 |
| 改端口 | 保持原状态 | 再加 `portEdit`（"在用"时 `hint` 写"代理地址将改为新端口，需同步修改应用中的代理设置。"） |

**`LgFlash(child, {count, showing, radius})`**：给 child 套一圈 2 px 强调色内描边（`.xc.flash`）。`count` 变大才闪（每加 1 闪一次，变小或不变不闪）：立刻出现，停约 1 秒后渐隐；系统要求减弱动效时不渐隐、约 1.5 秒后消失。`showing` 为真时一直亮（画廊用）。滚到卡片、闪一下的做法：卡片外面包 `LgFlash`，给它一个 `GlobalKey`，`Scrollable.ensureVisible(key.currentContext!)` 之后把 `count` 加 1。

**`LgExitCardGrid(children, {semanticLabel, minWidth = 440, gap = 12})`**：卡片按添加顺序排进尽可能多的列，每列至少 440 宽；同一行的卡片一样高（自己写的布局，不用 `IntrinsicHeight`；卡片变高时同行的跟着变）；窗口变宽变窄时子部件不重建。自己不滚动，放进页面的滚动区；列数跟着宽度走，所以宽度必须有界（放进横向滚动或 `Row` 里会触发 assert，说明写在断言里）。`kLgExitCardMinWidth` 是 440。

**`LgExitPage`**（页面主体）：`lede`、`inUseTitle`、`inUse`（`LgExitCardGrid` 或 `LgExitEmptyNote`）、`directoryTitle`、`refreshLabel`、`onRefresh`（为空时"刷新"禁用，目录加载中用）、`directory`（下面 `LgExitDirectory` 的某个状态）、`byIdTitle`、`byId`（`LgExitByIdRow`）、`controller`（滚动控制器）。自带整页滚动。放在主页的页标题"出口"正下方、和标题隔 4 px（页标题是主页自己画的），占满剩下的高度。`LgExitSection(title, {action})` 是小节标题（粗体、上面 24 px、读屏里是标题；`action` 向右探出 8 px）。`LgExitEmptyNote(text)` 是"暂无正在使用的出口"那张白条。

**`LgExitDirectory`**（目录，六种状态用命名构造函数选）：`.loading(semanticLabel)`（进度条，读屏的实时区）、`.unsupported(text)`（信息横幅）、`.notLoggedIn(text, actionLabel, onAction)`、`.empty(text)`、`.error(text, actionLabel, onAction)`（红色图标加"重试"）、`.rows(entries)`（`List<LgExitEntry>`：`name`、`id`（已格式化）、`platform`、`owner`（"我的"或"所有者：李四"）、`actionLabel`（"使用"或"使用中"）、`onPressed`、`inUse`）。行里的按钮读屏名是 `"$actionLabel $name"`，整行是一个读屏分组（名字、ID、所有者只念一次）。"使用中"按钮是柔和底加对勾，点了去滚到那张卡片（`onPressed` 里做）。除 `.rows` 外各状态离上面的标题 8 px（`.loading` 是 12 px），`.rows` 紧贴。`LgExitDirectoryRow(entry, {topDivider})` 是单独的一行，`LgIndeterminateBar(semanticLabel)` 是目录加载中的 4 px 细条（系统要求减弱动效时停在原位）。

**`LgExitByIdRow`**：`controller`、`placeholder`、`semanticLabel`、`useLabel`、`onUse`（为空时"使用"禁用，框里按回车同样无效）、`focusNode`、`errorText`（"ID 格式不正确"，框变红、下面一行常规字重）、`onChanged`、`enabled`。框最宽 520，按钮紧跟在后面、和框同高同顶。

**导航项和主页标签上的数字、提醒**：`LgCountMark(count, {alert, gap})`（在 `lg_status.dart`）是数字徽标加可选的提醒标记（16 px 警告三角，警告色，画在数字前面）；读屏里它整个不出节点，名字由放它的控件给。导航项（`home_page.dart` 的 `_NavItem`）：`Row` 末尾放 `LgCountMark(n, alert: …)`（间距默认 16，样稿的 `.navi .rmd+.badge`），`LgPressable.semanticLabel` 写"出口，‹N› 个正在使用"（有提醒加"，需要处理"），行里的文字用 `ExcludeSemantics` 包住，免得名字念两遍；数字为 0 时不画；出口页正显示时传 `alert: false`。主页标签：`LgTitleBar(homeBadge: n, homeAlert: …, homeSemanticLabel: …)`，标签名就是 `homeSemanticLabel`（不传时是"主页 ‹n›"），数字和三角不另出节点。

**整合时要注意的**
- 卡片里的文字和按钮名全由调用方传；`LgExitAction.semanticLabel` 不传时读屏名就是按钮文字，两张卡片都有"停止"时调用方要不要加设备名由整合定（读屏下找不到谁的"停止"时加 `"停止 ‹设备名›"`，目录行的按钮已经这样做）。
- 输错的红字用常规字重（`LgDialogFields`，样稿的 `.ferr`），卡片里的所有输入框、按 ID 的框都已包好，调用方不用管。
- 焦点（实测的行为）：密码框、验证码框、改端口框第一次建出来时带 `autofocus`，只是兜底，它只在页面上当时没有别的控件有焦点时才拿得到。两张卡片先后要密码时，焦点留在先出现的那张；页面上已有控件有焦点时（例如键盘按过目录行的"使用"），后来进入要密码的卡片拿不到。所以卡片因为用户操作进入要密码或要验证码（点"使用"、"重试"、"重新连接"之后）时，调用方给区域传 `focusNode` 并主动 `requestFocus()`，改端口也一样；重连时又要密码是后台事件，不抢焦点，只靠提醒标记叫用户回来，不要调 `requestFocus()`。
- Esc 只在改端口的框里有效（取消）；框里按回车会让框失去焦点（Flutter 的默认），所以回车确认之后要接着用键盘时，由调用方把焦点放回去。
- 卡片里没有会弹浮层的组件放在合并语义的容器里；头里的名字省略时的悬停全文在 `ExcludeSemantics` 里，读屏从分组名读。
- 样稿的身份色是写死的 `data-k="2"`，组件按 ID 算身份色（和设备卡片一致），画廊里同一个 ID 是赭黄，不是样稿的陶橙，不算差异。

### 10.13 M6a 的分工约定

M6a 是设置页的框架、搜索、解锁和八个小节，设置页的全部组件和全部 Rust 项也在这一段；其余十二个小节是 M6b（§10.14）。界面行为以 `docs/新界面/02-第二轮内容与逻辑说明.md`（下称"02"）§1.2~§1.6、§3 为准，主页的联动以 01 §3.1 区块 A 为准；样稿 `A-P6-设置.html`、`A-P6-设置-对话框.html`（"修改 ID"、多语言列表、TLS 回退的旧说明按 02 §5.2 作废）。

**分支和文件边界**（都从 `ui/m6a` 切，做完合回 `ui/m6a`）

| 分支 | 块 | 只改这些 |
|---|---|---|
| `ui/rust-m6` | Rust | `libs/leapgate/src/`（`exit/policy.rs` 拆出逐项解析、新文件 `server_info.rs`（S1、S2）、`sign.rs`、`lan.rs`、新文件 `direct.rs`（S5）、`ipc.rs` 的 `Msg` 末尾加变体、`lang.rs`（Telegram 正文）、`report/mod.rs`（S2 的落盘、`root_from` 改调 S1 的推导）、`exit/directory.rs`）；`src/leapgate_ffi.rs`（末尾追加 M6 一段）；`src/leapgate_hooks/ipc.rs`（S5 的分支）；新文件 `src/leapgate_hooks/settings.rs`（S9、S10 的进程间部分）；上游只两处：`src/rendezvous_mediator.rs` 监听那一行（S5）、`src/server/connection.rs` Telegram 正文那 6 行换成 1 个调用（S11），各带 `// leapgate:` 注释；本节的 Rust 部分 |
| `ui/m6-ds` | 组件 | `app/lib/widgets/`（新组件）、`app/lib/icons/`（盾牌图标）、`app/lib/gallery_*.dart`、组件的测试；`app/pubspec.yaml` 加 `qr_flutter: 4.1.0` 和用同一个 `PUB_CACHE` 重新生成的 lock |
| `ui/m6a-access` | A（框架和访问） | core 新文件 `leapgate/settings/unlock.dart` 和 A 需要的其他 `leapgate/settings/*.dart`；`consts.dart`（只在"M6a access"下追加）；app `pages/settings/` 下的 `settings_page.dart`（换掉占位）、`settings_section_state.dart`（可加成员，不改已有接口）、新文件（搜索、导航之类）、`sections/access.dart`、`permissions.dart`、`service.dart`、`dialogs/` 下解锁 PIN 和设置 PIN 两个对话框；`pages/home/home_page.dart`（密码行"修改"先解锁、服务状态行的警告）、`pages/home/password_row.dart`（"更多访问设置"）、`shell/main_window.dart`（切标签、窗口隐藏时让解锁控制器上锁）；ARB；测试 |
| `ui/m6a-net` | B（出口和网络） | core `leapgate/settings/` 下 B 需要的新文件（服务器配置的导入导出编解码、出口前提的计算等）；`consts.dart`（只在"M6a network"下追加）；app `pages/settings/sections/exit_node.dart`、`connection.dart`、`appearance.dart`、`network.dart`、`account.dart`，`dialogs/` 下放行的网段、服务器、代理三个对话框；`app/lib/main.dart`（主题、语言）、`app/lib/cm/cm_main.dart`（登记 `theme`、`language` 事件）、`pages/session/reasons.dart`、`pages/session/connection_panel.dart`（"打开网络设置"）；ARB；测试 |

- `settings_registry.dart`、`settings_ids.dart`、`shell/navigation.dart` 的 `showSettings` 和 `settingsPageRequests`、core `leapgate/settings/settings_api.dart`、两份 `settings_fakes.dart` 是第 0 步写好的接口，A、B 都不改。小节文件只认注册表、选项 model、`settingsApi` 和组件，彼此不引用。
- ARB 键以 `settings` 开头，A 用 `settingsAccess*`、`settingsPerm*`、`settingsService*`、`settingsUnlock*`、`settingsSearch*`，B 用 `settingsExit*`、`settingsConn*`、`settingsAppearance*`、`settingsNet*`、`settingsAccount*`；加在两个 ARB 文件末尾，中英文同时加，文案照 02 逐字照抄，英文照 02 §5.5，没有的新写并列进提交说明。改完 ARB 跑 `flutter gen-l10n`。
- A、B 先用 M0~M5 的组件和简单的占位控件把逻辑写通，整合时换成组件块的组件。占位不求好看，但行为测试要能按文字和语义标签找到它们。
- `RustSettingsApi` 调块 2 的真实导出；测试一律用 `FakeSettingsApi`（core 和 app 的 `test/settings_fakes.dart` 各一份，内容相同）。页面不直接调 `bind`：第一块的 `bind.main*` 调用包在 core 的 model 里（§10.7），会弹 UAC 的三处见下。

**框架的接口**（`app/lib/pages/settings/`）
- `settings_ids.dart`：三组、二十个小节的固定 id（`SettingsSectionId`），链接在小节建好之前就能指名。
- `settings_registry.dart`：`SettingsSection`（id、标题、`items()`、`visible()`、`locked`、`build(context, ctx)`）、`SettingsItem`（id、名字、说明、单选项名，给搜索用）、`SettingsSectionContext`（`overlays`、`locked`、`keyOf(item)`、`isMarked(item)`、`errorOf` / `setError`、`save(item, write)`）、`settingsSections(l10n)`（按 id 顺序；M6b 的小节也登记在这里）。`items()` 只列此刻显示的项（被开关藏起来的不列，锁住的照列）。
- `settings_section_state.dart`：`SettingsSectionState`，上面接口的实现，页面和测试共用；`save` 失败时那一项下面写 `settingsSaveFailed`，成功清掉，两种都重建小节。
- 小节在每次重建时从选项 model 重新读值；页面在打开小节、主窗口拿回焦点、保存之后重建，不加定时刷新。
- 跨小节链接用的项 id（出口前提的"修改"要用，A 必须用这几个 id 登记）：访问与密码的 `approve-mode`、`verification-method`、`permanent-password`；权限的 `enable-tunnel`。其余项 id 用选项键或小写短横线的名字，各自定。
- `MainNavigation.showSettings(section, {item})`：切到主页标签的设置页、打开那个小节、滚到那一项并标记约 2 秒（`SettingsSectionState.mark`）。
- 选项 model（§10.7）加了 `userDefault`（UserDefaultConfig）。`config.set` 走 S9（`stop-service` 除外），`failed` 时返回 false。

**解锁**（A，02 §1.2.6，R2-Q3、R2-Q31）
- 只在安装版。`locked` 为真的小节（访问与密码、权限、出口、服务与 ID、网络和服务器，以及 M6b 的传入连接各节）共用一次解锁；离开设置页（切到设备、出口页，切到任一会话标签，主窗口隐藏或关闭）上锁，设置页里切小节、搜索不上锁。
- 点"解锁"时才调 `mainGetUnlockPin`（同步、内部经 IPC 最多等 1 秒，不在构建时调）：有 PIN 就弹"输入解锁 PIN"（底部"改用管理员权限解锁"），在界面里比对、不限次数；没有就调 `mainCheckSuperUserPermission`，返回假就在锁定条下写"未获得管理员权限，设置仍处于锁定状态"。
- 主页密码行"修改"在安装版先走同一套解锁，成功后打开设置固定密码对话框，对话框关闭时上锁。
- 不受锁约束的：服务的启动 / 停止（自己弹 UAC）。

**A 的其余要点**
- 服务与 ID：服务状态行和主页逐字相同（`LocalStatusModel`）；安装版停止 / 启动服务调 `mainSetOption('stop-service', …)`，成功时进程退出重开，调用返回就说明没成，下面写"未获得管理员权限，服务未停止"（启动时"……服务未启动"），取消和失败不分；便携版停止的确认正文按 02 §4.3 第 3 条（R2-Q7）。解锁 PIN：设置 / 修改 / 移除，长度在 Dart 里先校验（至少 4 个字符）。
- 访问与密码：选"仅固定密码"而没设固定密码时先开对话框（02 §1.3.1）；"仅使用数字"改了当场刷新一次性密码。
- 权限：访问模式不是"自定义"时整组灰显并显示实际生效的值（02 §1.3.2）。
- 搜索：索引来自各小节的 `items()`，只匹配当前语言，不区分大小写，键盘上下、回车、Esc（02 §1.2.4）。
- 本次运行内记住上次打开的小节。
- 主页服务状态行在代理、WebSocket、禁用 UDP 开着时的警告：做法取决于 02 §4.3 第 4 条的实测结果。

**B 的要点**
- 出口：开关写 Y / N；前提状态行从访问与密码、权限的值算，"修改"用 `showSettings` 和上面固定的项 id；关闭前的确认数在点关闭时现查一次 C1 的 `exit`（为 0 时不确认，查不到时用不带数字的那句）；放行的网段对话框用 `settingsApi.allowNetsCheck`，保存它给的 `value`。
- 连接方式：打洞直连和三个键的对应照 02 §1.4.1（打开只写 `enable-ipv6-punch = Y`，关闭两个都写 N）；等待直连的时间 0.1~99.9、一位小数、空 = 2.5；顶部状态条：代理、WebSocket、禁用 UDP、Key 不可用（`keyCheck` 为 `invalid`，或为 `empty` 且 S1 的 Key 来源是 `none`）、兼容服务器（`serverKind`）。
- 外观：`theme`、`lang` 是和旧界面共用的 LocalConfig 键；写入后主题照上游调 `mainChangeTheme`，语言调 `leapgate_lang_changed`（传解析后的语言，不调上游 `mainChangeLanguage`，见下表）；主窗口的 `MaterialApp` 按这两个键设 `themeMode` 和 `locale` 并监听；CM 只登记 `theme` 全局事件，语言从 `leapgate_cm_events` 的 `lang` 事件来、不写盘。`lang` 存的是新界面不支持的语言时按"跟随系统"显示和处理、不改写。启动时和改语言后，把解析后的实际语言（`zh-cn` 或 `en`）经 S9 写进 Config 键 `leapgate-ui-lang`（值不同才写）。
- 网络和服务器：摘要用 `serverSummary` 和 `serverKind`；实际生效的 API 是明文 http 且不是回环地址时显示警告；服务器对话框照 02 §1.6.8，"API 留空时会用的地址"用第一块现成的 `mainGetCommonSync('resolve-api-server:…')`，Key 用 `keyCheck`，ID 和中继服务器用 `mainTestIfValidServer` 验证；已登录且 API 变了时先验证、再向旧服务器退出登录、再保存，退出失败不挡保存；导入导出走剪贴板，编解码照上游 `common.dart:2921-2973`，导入只预填、点"确定"才保存；代理对话框读 `mainGetSocks`、写 `settingsApi.setSocks`；WebSocket、禁用 UDP 开启前页内确认。TLS 回退的说明写明还有哪些 HTTP 请求走上游代码（IQ7）。
- 账号：照 02 §1.5.3，用 M4 的账号 model 和登录对话框。
- 会话错误 `key_mismatch`、`secure_tcp_failed` 加 `NextStep.openNetworkSettings`：`mainNavigation.showSettings(SettingsSectionId.network)`（先切到主页标签，`showSettings` 自己会切）。

**Rust 导出（块 2）**

| 导出 | 参数 | 返回 |
|---|---|---|
| `leapgate_set_options`（S9） | `changes: String`（JSON 对象 `{键: 值}`，空值删除） | `String`：`saved` / `saved_local` / `failed` |
| `leapgate_set_socks`（S9） | `proxy`、`username`、`password: String` | `bool`：服务进程收下了 |
| `leapgate_exit_allow_nets_check`（E5） | `text: String`（对话框原文，每行一条） | `SyncReturn<String>`：`{"valid":bool,"count":N,"lines":[{"line":行号,"state":"invalid"\|"blocked"}],"value":要存的值}`；行号从 1 起、按原文；`blocked` 是"始终禁止"的警告，仍可保存 |
| `leapgate_server_summary`（S1） | — | `String`：`{"id":{"value","source","default"},"api":{"value","source"},"key":{"source","builtin"},"relay":{"value"}}`；`id.default` 是本构建内置默认列表的第一台 ID 服务器（写法同 `value`，不带补上的默认端口），没有内置默认值时为空串，服务器对话框"留空时使用默认值"用它；`key.builtin`（bool）是本构建有没有内置的 Key，和当前用的是哪个 Key 无关，为假时 Key 一栏不写"留空时使用内置的 Key"；`id` 的来源 `exe` / `user` / `custom` / `cache_default` / `cache_last` / `default` / `none`，`api` 的 `exe` / `user` / `derived` / `default` / `none`，`key` 的 `exe` / `user` / `default` / `none` |
| `leapgate_server_kind`（S2） | — | `SyncReturn<String>`：`{"kind":"leapgate"\|"compat"\|"checking","features":[…]}` |
| `leapgate_key_check`（S3） | `key: String` | `SyncReturn<String>`：`empty` / `valid` / `invalid` |
| `leapgate_local_addresses`（S4） | — | `String`：`[{"name","ipv4":[…],"ipv6":[…]}]`，不列临时 IPv6 地址 |
| `leapgate_direct_listen`（S5） | — | `String`：`{"state":"listening","port":N}` / `{"state":"failed","port":N,"error":"in_use"\|"denied"\|"other"}` / `{}`（服务不在或还没有结果） |
| `leapgate_bot_lookup`（S10 第一步） | `token: String` | `String`：`{"result":"ok","chat":{"id":…,"type":"private"\|"group"\|"supergroup"\|"channel","label":…}}` / `{"result":"network"\|"invalid_token"\|"no_chat"\|"other","text":…}`。请求没发出去或没拿到响应（`post_request_sync` 出错、线程 panic）→ `network`；Telegram 回了 401、404 → `invalid_token`；Telegram 回了其他 `error_code`（例如设过 webhook 时的 409），或响应不是 JSON、结构解析不了 → `other`。只查、不存 |
| `leapgate_bot_save`（S10 第二步） | `token: String`，`chat_id: String` | `String`：`ok` / `other`（服务进程没存上） |
| `leapgate_verify_2fa` | `code: String` | `String`：`ok` / `wrong_code` / `not_saved` |
| `leapgate_lang_changed` | `lang: String`（解析后的实际语言，`zh-cn` 或 `en`） | 无。经 `send_to_cm` 发 `Msg::Lang`，CM 推 `{"name":"lang","lang":…}` 给 `leapgate_cm_events`，CM 直接切换、不写盘。代替上游 `mainChangeLanguage`：上游的 `Data::Language` 让 CM 把内存里整份旧的 LocalConfig 写回文件（`src/ui_cm_interface.rs` 收到语言消息那一处），会盖掉主窗口之后写的主题、界面模式、出口端口表等 |

没有 `SyncReturn` 的都是异步导出。S11 不导出：界面经 S9 写 Config 键 `leapgate-ui-lang`。

**Rust 的做法和约束**
- S9：自己开一条 IPC 连接，同一条连接上先发 `Options(None)` 取服务进程当前的整表，合并改动，发 `Options(Some)`，等服务进程回 `Options(None)` 确认；确认到了写本地 `Config::set_options` 并调 `ui_interface::refresh_options()`，返回 `saved`。连不上时：安装版、`stop-service` 不是 Y → `failed`，不写本地；其他情况写本地，返回 `saved_local`（服务下次启动时导入）。照搬上游写选项时的副作用：`CheckTestNatType` 的判断、TLS 回退改了清 TLS 缓存、`audio-input` 改了重启音频服务。上游 `ui_interface.rs`、`ipc.rs` 不改。
- S1、S2 和 `exit/directory.rs`：服务器地址和能力从界面进程的选项缓存（`ui_interface::get_option`）取，交给 `libs/leapgate` 的纯函数；不在界面进程里直接读 `Config`（安装版界面进程的 `Config` 可能是旧的）。S1 的来源推导写成纯函数，`report::root_from` 也改调它，不出第三份复刻。
- S2：确认不支持时写 `leapgate-api-nocaps = <api 根>`，确认支持时清掉；三态 = 有对得上的 caps → `leapgate`，有对得上的 nocaps → `compat`，都没有 → `checking`。
- S5：`leapgate::direct::noted(port, result)` 原样返回 `result` 并记下结果，上游那一行只多这一层包装；查询走 `leapgate::ipc::Msg` 末尾新加的变体，服务端分支在 `src/leapgate_hooks/ipc.rs`。`denied` 对应 Windows 10013。
- S10 分两步（02 §1.6.4"确认收件对话"）：上游 `get_chatid_telegram` 取 getUpdates 里**最早**一条消息的对话、不给人看就保存，机器人的用户名谁都能搜到，有人先给它发过消息，验证码就会发到那个人那里。所以不再调它：`leapgate_bot_lookup` 照上游在新线程里调 `post_request_sync` 发 getUpdates（带 `offset=-100`：不带时 Telegram 给最早未确认的 100 条，积压超过 100 条就拿不到刚发的那条；负数取队尾 100 条，代价是更早的更新被 Telegram 标成已确认、之后不再返回），由 `libs/leapgate` 的 `settings::bot_chat` 取**最近**一条带 `message` 或 `channel_post`（频道里发的帖子是这种）的更新里的对话，两者一视同仁，`edited_message`、`edited_channel_post` 等其他种类跳过（id 数字或字符串都转成字符串；显示名私聊是 `@username`，没有就是"名 姓"、去掉开头的 `@`，免得把名字设成"@某人"冒充用户名；群组、频道是 `title`），什么都不存、不拿保存锁；请求本身失败直接归 `network`，拿到响应后 Telegram 的错误照上游原文的格式（`Telegram API error: … (error_code: N)`）写，再由 `bot_result` 归类：401、404 → `invalid_token`，没有对话 → `no_chat`，其余 Telegram 错误、不是 JSON、没有 `result` 列表 → `other`；`text` 里的 Token 换成 `<token>`。用户确认后 `leapgate_bot_save` 在保存锁下照上游私有的 `TelegramBot::save` 存（用上游公开的 `TelegramBot` 结构序列化，`into_string`、`save` 那几行抄进 `src/leapgate_hooks/settings.rs`，`src/auth_2fa.rs` 不改），再读一次服务进程的配置，`bot` 没存上就回 `other`。`leapgate_verify_2fa` 同理：验证码对了再确认密钥存上了。解析和归类用写死的 getUpdates 响应和 Telegram 错误原文写单测钉住。
- S11：`leapgate-ui-lang` 为 `zh-cn` 时中文正文，其余（含没设）照现在的英文；正文放 `libs/leapgate/src/lang.rs`。
- E5：从 `parse_allow_nets` 拆出逐项解析；"始终禁止"按网段整个落在回环、链路本地、保留段或元数据地址里判断，不拿首地址判断（`0.0.0.0/0` 不能报）；198.18.0.0/15 不算；"本机地址"是动态的，不报。`value` 是 `parse_allow_nets` 读得懂的存储格式。
- 状态类型和 JSON 放 `libs/leapgate`，带单测；上游两处挂钩之外不碰上游文件。

**组件**：规则同 10.8"组件约定"（只管画、文字由调用方传、带语义标签、两套主题和两套尺寸、画廊里每种状态一项、有行为测试），加 10.8 的"合并语义的容器里不放带浮层的组件"。要做的：设置页版式（小节导航含组标题和搜索框、小节内容区、960×600 时控件换到名字下面一行）、设置行（灰显带原因、行下红字、标记约 2 秒）、小节里的小标题、锁定条（带盾牌按钮和下面一行红字）、盾牌图标、状态加按钮的行、数字输入框加单位、搜索结果列表、受信设备列表、快捷键行和录制对话框、二维码（`qr_flutter`）、关于页的行；M6b 用的几样也在这里。

**测试**
- R：S9 的合并和三种返回；S1 的来源推导表；S2 三态；S3；E5 的逐行判断（含 `0.0.0.0/0`、198.18.0.0/15、各类始终禁止）；S10 按上游原文归类；S11 两种语言正文。
- core（A、B 各自的）：解锁控制器的上锁时机；出口前提的计算；服务器摘要的显示规则；导入导出编解码。
- app：02 §1.10 里这八个小节、搜索、锁定的每个状态一个行为测试，用 `FakeSettingsApi` 喂数据。

**已知限制**（不修）
- 已登录时改 API 服务器，先退出登录再保存；保存返回 `failed`（安装版、服务没应答）时，账号已退出、服务器没改。
- 搜索结果或链接指向的行要等异步读值才出现时（出口的"放行的网段"、网络小节的服务器摘要），第一帧找不到这一行，不会滚过去，只在数据到了以后显示标记。这几个小节都短、行在顶部。
- S9 是"读整表、合并、写回"，读和写之间（毫秒级）服务进程自己写的键（`leapgate-api-caps`、`leapgate-api-nocaps`）可能被冲掉；上游 `set_option` 用最多旧 1 秒的缓存整表写回，窗口更大。上游每秒用服务进程的整表覆盖界面的选项缓存，和 S9 的 `refresh_options()` 之间也有约 1 秒的竞争。
- S10 的查询和保存分开（见上面"Rust 的做法和约束"S10 那条）：查询 `leapgate_bot_lookup` 不拿保存锁，只有确认后的 `leapgate_bot_save` 在锁下写一次；上游把查询和保存放在一个函数里，整个 Telegram 请求期间都持有保存锁。

### 10.14 M6b 的分工约定

M6b 是设置页其余十二个小节和三个对话框。界面行为以 02 §1.3.3~§1.3.5、§1.3.7、§1.4.2~§1.4.7、§1.5.4、§1.5.5、§1.6.3~§1.6.5、§1.10、§3.3 为准；样稿同 §10.13。框架、组件、Rust 导出都在 M6a（§10.13），M6b 只写页面，直接用 M6a 的组件和真实导出。

**分支和文件边界**（都从 `ui/m6b` 切，做完合回 `ui/m6b`）

| 分支 | 块 | 只改这些 |
|---|---|---|
| `ui/m6b-in` | C（传入其余） | core `leapgate/settings/` 下 C 需要的新文件（受信设备的解析、声音来源（照上游 `audio_input.dart`）、白名单的校验、二次验证和 Telegram 的状态）；`consts.dart`（只在"M6b incoming"下追加）；app `pages/settings/sections/two_factor.dart`、`restrictions.dart`、`sessions.dart`、`remote_printing.dart`、`during_sessions.dart`（换掉占位），`dialogs/` 下新文件（开启二次验证、Telegram 机器人、IP / ID 白名单）；`shell/main_window.dart` 只改 `keepDisplayOn` 那一处（照 `keep-awake-during-outgoing-sessions`）；ARB；测试 |
| `ui/m6b-out` | D（传出其余和通用） | core `leapgate/settings/` 下 D 需要的新文件（快捷键的绑定读写和录制校验，从上游 `page_body.dart`、`recording_dialog.dart` 去界面化后搬进来，约 250 行）；`consts.dart`（只在"M6b outgoing"下追加）；app `pages/settings/sections/new_device_defaults.dart`、`toolbar.dart`、`rendering.dart`、`shortcuts.dart`、`print_jobs.dart`、`other.dart`、`about.dart`（换掉占位）；`pages/session/toolbar/monitor_menu.dart`（默认值改经选项 model）和会话里读工具栏、显示器、渲染这几项设置的文件，只为让已开的会话当场跟着变（02 §3.3），改了哪些列进提交说明；ARB；测试 |

- 十二个小节都登记在 `settings_registry.dart`，`visible` 按 02 设（例如远程打印、收到的打印任务只在 Windows）。`settings_registry.dart`、`settings_ids.dart`、`settings_page.dart`、`settings_section_state.dart`、`settings_flow.dart`、`settings_status.dart`、`shell/navigation.dart`、core `settings_api.dart`、两份 `settings_fakes.dart`、`app/lib/widgets/` C、D 都不改。小节文件彼此不引用。
- 锁：C 的四个传入小节 `locked: true`，用 `ctx.locked` 灰显；自己弹 UAC 的（RDP 会话共享、安装打印机）不受锁约束，结果这样拿：RDP 调用返回后再读一次 `mainIsShareRdp`，打印机看全局事件 `install-printer-res`。
- ARB 键以 `settings` 开头，C 用 `settingsTwoFactor*`、`settingsRestrict*`、`settingsSessions*`、`settingsRemotePrint*`、`settingsDuring*`，D 用 `settingsDefaults*`、`settingsToolbar*`、`settingsRender*`、`settingsShortcut*`、`settingsPrintJobs*`、`settingsOther*`、`settingsAbout*`；加在两个 ARB 文件末尾，中英文同时加，文案照 02 逐字照抄，英文照 02 §5.5，没有的新写并列进提交说明。改完 ARB 跑 `flutter gen-l10n`。
- 写选项一律经选项 model（`config.set` 走 S9，`ctx.save` 管"无法保存设置"），页面不直接调 `bind`；第一块的 `bind.main*` 调用包在 core 的 model 里。新设备的默认设置用 `userDefault` 作用域（§10.7）。

**用到的 M6a 导出和组件**
- C：`settingsApi.localAddresses`（S4，直接 IP 访问的本机地址）、`directListen`（S5，端口和"端口 ‹端口› 已被其他应用占用"；先读 `direct-server` 选项，记录在关掉以后还在）、Telegram 机器人的查询和保存（S10 拆成的两步 `leapgate_bot_lookup`、`leapgate_bot_save`，见 §10.13）、`verify2fa`（验证码对了再确认密钥存上了，`not_saved` 照 02 §1.6.10 写）；组件 `LgTrustedDevices`、`LgQrCode`、`LgQrKeyRow`、`LgSettingsStatusRow`、`LgSettingsNumberField`、`LgSettingsSubtitle`。
- D：组件 `LgShortcutGroup`、`LgShortcutRow`、`LgShortcutRecordDialog`、`LgSettingsInfoRow`（关于页的行，带复制）、`LgSettingsNumberField`；关于页的版本用 `leapgate_version`（S12）。

**几处约定**
- 二次验证：开启对话框把密钥显示在二维码下（上游的做法，02 §1.6.3）。测试和画廊里只用写死的假密钥。
- S10 拆成查询和保存两步（§10.13"Rust 的做法和约束"S10 那条）：Telegram 对话框先调 `leapgate_bot_lookup`，显示确认态（"验证码将发送给：‹对话›"），用户点"确认"才调 `leapgate_bot_save`；两次请求期间都显示进行中、不能重复点。
- 声音来源改了以后由 S9 照上游重启音频服务（§10.13"Rust 的做法和约束"），页面不另做。
- 录制位置：会话（传入的录制）和会话期间（传出的录制）共用同一个目录项，都在 C；选文件夹用 app 已有的 `file_picker`。
- 快捷键：总开关打开时写入默认绑定，录制的五种状态、冲突替换、恢复默认照 02 §1.4.6；"发送到远程设备"打开时快捷键不生效，判断沿用 M2b 的快捷键 model。
- 关于：版本、源代码链接、上游版权行和"基于 RustDesk"照 02 §1.5.5；行内复制用 `LgSettingsInfoRow`。

**测试**
- core：受信设备的解析；声音来源列表；白名单的逐行校验；快捷键绑定读写和录制校验（五种状态、冲突）。
- app：02 §1.10 里这十二个小节和三个对话框的每个状态一个行为测试，用 `FakeSettingsApi` 喂数据；已开会话在工具栏、渲染改了以后当场跟着变（D）；有出站会话时按 `keep-awake-during-outgoing-sessions` 决定是否阻止熄屏（C）。

### 10.15 M7a 的分工约定

M7a 是文件传输，也第一次在一个会话标签里放多个视图。界面行为以 02 §2.1.1、§2.2、§2.4、§2.5、§3.1、§3.2 为准，一个标签多个视图以 01 §2.1、§3.2 区块 A、G 为准；样稿 `A-P7-文件传输.html`、`A-P7-文件传输-菜单与其他状态.html`、`A-P7-文件传输-对话框.html`（替换确认的两文件对照表去掉：事件里没有大小和时间）。不在 M7a 的：暂停、从失败处重试、个别文件跳过和汇总、"查看详情"（M7b，§10.17），拖出到资源管理器，手机文件传输页。

**分支和文件边界**（都从 `ui/m7a` 切，做完合回 `ui/m7a`）

| 分支 | 块 | 只改这些 |
|---|---|---|
| `ui/rust-m7` | Rust | 新文件 `libs/leapgate/src/ft_reason.rs`（FT2 归类，纯函数加单测）、`libs/leapgate/src/lib.rs`（加 `pub mod ft_reason;`）、`libs/leapgate/src/reason.rs`（只把截断和日志去重改成能共用，C3 的行为不变）；新文件 `src/leapgate_hooks/file_transfer.rs`（本机读文件夹、删链接里要用会话和 `fs` 的部分）、`src/leapgate_hooks.rs`（加 `pub(crate) mod file_transfer;`）；`src/leapgate_ffi.rs`（末尾追加 M7a 一段）；上游只一处：`src/common.rs` 的 `_make_fd_to_json` 加 `is_hidden` 一行（FT1），带 `// leapgate:` 注释；本节的 Rust 部分 |
| `ui/m7-ds` | 组件 | `app/lib/widgets/`（新组件；`LgTitleBar` 画出 `LgSessionTab` 的 `progress`、`alert`；`LgEmptyState` 这类现成组件只加参数、默认值不变）、`app/lib/icons/`（缺的图标）、`app/lib/gallery_m7.dart`（已登记进 `gallery_main.dart`，组件块只改这个文件）、组件的测试 |
| `ui/m7a-core` | A（core） | core `leapgate/file_transfer/` 下：新文件 `file_model.dart`（改写的 `FileModel`、`FileController`）、`sort.dart`，`jobs.dart` 和 `errors.dart` 的分隔线以下，`pane.dart` 里 `fileTransferOf` 的函数体；`models/file_model.dart`（删掉 `FileModel`、`FileController` 两个类，其余照"只删界面调用"不动；来源行第 0 步已写成最终的样子）；`leapgate/session.dart`（事件登记、`FileModel` 的导入）、`leapgate/ffi_model.dart`（只在 `onReady` 那一处需要时改）；`leapgate/prompts.dart`（只删旧的三种提问，见下）；`consts.dart`（只在"M7a core"下追加）；core 的测试（`file_model_test.dart` 跟着改写） |
| `ui/m7a-shell` | B（多视图外壳、队列、对话框） | `app/lib/shell/`（新文件放标签里的视图容器；`main_window.dart`、`tab_menu.dart`、`window_close.dart`、`tab_overlays.dart` 的 `ShellPrompter`；`navigation.dart` 只写实现、接口不改）；`app/lib/pages/session/` 的 `session_toolbar.dart`（视图切换做成真的）、`session_page.dart`（`active` 的含义）、`connection_panel.dart`、`reasons.dart`（"关闭文件传输"）；`app/lib/pages/files/` 的 `queue_panel.dart`、`file_dialogs.dart`、新文件 `file_route_details.dart`；"文件传输"入口：core `leapgate/peer_list.dart`（`PeerAction.fileTransfer` 和条件）和它的测试、app `pages/home/peer_views.dart`、`devices_page.dart` 和地址簿里列设备菜单项的地方（只加这一项）；`consts.dart`（只在"M7a shell"下追加）；ARB；测试 |
| `ui/m7a-panes` | C（两栏） | `app/lib/pages/files/` 里 B 那三个以外的文件：`file_view.dart`（换掉占位），新文件 `pane.dart`、`breadcrumb.dart`、`file_list.dart`、`pane_menus.dart`、`drag_drop.dart`、`formats.dart` 等；`consts.dart`（只在"M7a panes"下追加）；ARB；测试 |

- 第 0 步写好的接口谁都不改：core `leapgate/file_transfer/file_transfer_api.dart`、`pane.dart`（A 只填 `fileTransferOf` 的函数体）、`errors.dart` 和 `jobs.dart` 的分隔线以上、`prompts.dart` 里 `Ft` 开头的提问；app `FileView` 的构造参数、`FileQueuePanel(jobs:)`、`MainNavigation.openFileTransfer`、`LgSessionTab` 的 `progress` 和 `alert`、`ConnectionPanel.lastView`；core 和 app 的 `test/file_transfer_fakes.dart`（两份内容相同；要多的在自己的测试文件里继承）。
- ARB：C 的键以 `files` 开头；B 的新键以 `ft`、`queue` 开头，外壳已有前缀（`tab`、`closing`、`conn`、`toolbar`）下新加的也归 B；A 不加（core 不带文案）。加在两个 ARB 文件末尾，中英文同时加，文案照 02 §2.2、§2.4、§2.5、§3.1、§3.2 逐字照抄，英文照 02 §5.5，没有的新写并列进提交说明。改完 ARB 跑 `flutter gen-l10n`。
- A、B、C 先用现成组件和简单的占位控件把逻辑写通，整合时换成组件块的组件。占位不求好看，但行为测试要能按文字和语义标签找到它们。
- `RustFileTransferApi` 调块 2 的真实导出；测试一律用 `FakeFileTransferApi`。B、C 的测试给 `FileView` 传 `FakeFileTransferModel`。
- 整合时要接的：`RustFileTransferApi`；`fileTransferOf`（A）；`ShellPrompter.ask` 调 `showFilePrompt`（B）；视图容器挂上 `FileView`（B）；复制件的旧提问删掉以后 `ShellPrompter` 只画 `Ft` 开头的（A、B）。

**Rust 导出（块 2）**

| 导出 | 参数 | 返回 |
|---|---|---|
| `leapgate_ft_reason`（FT2） | `text: String`（`job_error` 的 `err` 原文）、`peer_platform: String`（对端信息的 `platform` 原样：`Windows`、`Linux`、`Mac OS`、`Android`；空或认不出时按 Windows 查）、`side: String`（`local` / `remote` / `unknown`） | `SyncReturn<String>`：`{"reason":码,"args":[…],"text":原文}`。`args` 一律是字符串：`invalid_name_windows` 是 `[名字]`，`too_many_files` 是 `[本次数, 上限]`（02 文案里的 ‹N› 是上限、‹M› 是本次数，取参时别弄反），其余 `[]`；`text` 截到 200 个字符（按字符边界，同 C3），每种码都带 |
| `leapgate_ft_read_local_dir` | `path: String`、`show_hidden: bool` | `SyncReturn<String>`：成功时和上游 `session_read_local_dir_sync` 一样（同样先过 `fs::get_path`，带 FT1 的 `is_hidden`）；失败时 `{"error":原文（截到 200 个字符）,"reason":码}`，码按 `side = local` 归 |
| `leapgate_ft_remove_link` | `session_id: SessionID`、`act_id: i32`、`path: String`、`is_remote: bool`、`is_dir_link: bool` | 异步、没有返回值。结果照常经会话事件 `job_done` / `job_error` 回，`id` 是 `act_id`、`file_num` 是 0；会话不在时什么也不做（和上游的 `session_*` 导出一样），Dart 自己有超时 |

- 空文件夹不加导出。本机读空文件夹失败照旧只拿到空串，附注写"未能读取"，和远程同一句。
- FT1：上游 `_make_fd_to_json`（`src/common.rs`）每条加 `"is_hidden"`，三条读文件夹的路（本机、远程 `file_dir`、空文件夹）都带上；旧界面多一个字段、不读。Dart 半边（复制件 `Entry.isHidden`，缺省 false）也加了，来源行注明了例外。符号链接不加字段：`entry_type` 2 是目录链接（Windows 的目录联接也算），5 是文件链接。

**FT2 的归类**
- 码（snake_case，界面按它查表，改名等于改接口）：`permission_denied`、`in_use`、`not_found`、`disk_full`、`file_too_large`、`path_too_long`、`invalid_name`、`invalid_name_windows`、`symlink_in_path`、`one_way`、`too_many_files`、`android_scope`、`skipped`（不是错误）、`other`。`timeout` 只在 Dart 里有（`FtError.timeout()`），Rust 不返回。
- 原文里有 `(os error N)` 的，取最后一次出现的 N（`validation failed: …`、`failed to validate path component '…': …` 这类前缀里，内层在末尾），只认错误码、不认文字（Windows 的文字随系统语言变）：

| 码 | Windows（Win32） | Linux、Android（errno） | macOS（errno） |
|---|---|---|---|
| `permission_denied` | 5、1920、19（写保护） | 13、1、30（只读文件系统） | 13、1、30 |
| `in_use` | 32、33 | 26、16 | 26、16 |
| `not_found` | 2、3、15、21（盘不在） | 2、20 | 2、20 |
| `disk_full` | 112、39 | 28、122 | 28、69 |
| `file_too_large` | 223、665 | 27 | 27 |
| `path_too_long` | 206 | 36 | 63 |
| `invalid_name` | 123、161 | 22、84 | 22、92 |
| `symlink_in_path` | — | 40 | 62 |

- 没有错误码的，按上游自己拼的句子认：`symlink path component is not allowed` → `symlink_in_path`；以 `invalid Windows download file name: ` 开头 → `invalid_name_windows`（冒号后面是名字）；`invalid download file name`、`invalid file name component`、`invalid file name in remote directory listing: …`、`file name contains null bytes`、`path traversal detected in file name`、`absolute path detected in file name`、`empty file name in multi-file transfer`、`… cannot be empty`、`… contains null bytes`、`new file name cannot be empty`、`Invalid path` → `invalid_name`；`Not exists`、以 ` not exists` 结尾的（`"‹路径›" not exists`、`Parent directoy of … not exists`）→ `not_found`；正文等于 `one-way-file-transfer-tip`（是翻译键）→ `one_way`；以 `file transfer rejected: too many files (` 开头 → `too_many_files`，从括号里取两个数；正文等于 `Permission denied`（没有错误码，Android 的范围检查）→ `android_scope`；正文等于 `skipped` → `skipped`；其余 → `other`（续传临时文件异常、`Wrong id` 这类内部错误也是 `other`）。Windows 被控端连接管理进程给读任务的初始化错误包了一层 `validation failed: `（`ui_cm_interface.rs` `start_read_job`），先去掉再认，`validation failed: Not exists` 是 `not_found`；`validation task failed: `、`task failed: `、`serialize failed: ` 后面是任务异常或序列化错误，照旧 `other`。
- `side`：`local` 按本机平台的表查（本机平台用 `cfg!` 取，不写死 Windows）；`remote` 按 `peer_platform` 的表查；`unknown`（传输任务）：对端也是 Windows 时两边同一张表；对端不是 Windows 时，看 `(os error N)` 前面的文字是不是那个 errno 的英文原句（Linux glibc、Android bionic、macOS 各一张小表，约 15 条；bionic 和 glibc 只有 5、40、84、122 的措辞不同，码表和 Linux 共用），是就按对端平台查，否则按本机查。只有 `(os error N)` 紧挨原文末尾时才认作错误码，在路径或名字中间的不算。小表除了上面表里的 errno，还收了号码和上面 Windows 那列撞上的文件类 errno（5 EIO、19 ENODEV、21 EISDIR、32 EPIPE、Linux 和 Android 的 39 ENOTEMPTY、123 ENOMEDIUM），否则对端的 `Input/output error (os error 5)` 会按本机查成没有访问权限；它们按对端查不到，是 `other`。实现（`ft_reason.rs` `unknown_side`）不假定本机是 Windows：两端不同时，以非 Windows 那端（都不是时以对端）的原句判断。原因：上传时本机读出错，被控端会把同一句原文原样发回来，"从远程回来的"不一定是远程设备的错误。
- 没认出的同一段正文只在日志里写一次，和 C3 共用截断和去重。
- FT2 是纯函数，不依赖任务状态；M7b 在 `io_loop.rs` 加 FT3~FT5 挂钩时调同一个函数。

**Rust 的做法和约束**
- `leapgate_ft_remove_link`：远程时由 Rust 从会话自己的对端信息取平台，不由 Dart 传。Windows 对端、目录链接 → 发 `FileRemoveDir { id: act_id, path, recursive: false }`（被控端只调 `std::fs::remove_dir`，只删链接或联接本身，各版本对端都认）；其余（文件链接，Linux、macOS 对端的目录链接）→ 发 `FileRemoveFile { id: act_id, path, file_num: 0 }`。本机：Windows 上按链接自身的属性（`symlink_metadata` 带目录属性 0x10）调 `std::fs::remove_dir`，不看 `is_dir_link`（目标已不存在的目录链接上游列成文件链接），其余调 `std::fs::remove_file`，结果照本机删文件那样推 `job_done` / `job_error`。上游删文件夹的导出（固定递归）不改。
- `leapgate_ft_read_local_dir` 直接调 `fs::read_dir(&fs::get_path(&path), show_hidden)` 和 `crate::common::make_fd_to_json`，失败时把错误原文交给 FT2 的归类。
- 上游文件只改两处，其余都在 `libs/leapgate` 和 `src/leapgate_*`：`src/common.rs` 一处（FT1）；`src/client/io_loop.rs` 的 `sync_jobs_status_to_local` 开头，不是文件传输会话就返回（`// leapgate:` 注释、3 行）。上游每个会话结束时都把自己的未完成任务写进这台设备的配置，远程桌面会话没有任务、写的是空表；同一标签里两个视图同时断开时谁后退出谁说了算，未完成的传输有一半概率被冲掉（表现是断线较久后续传卡住、重开后任务消失；上游旧界面同样会冲掉）。

**core 的接口**（`core/lib/leapgate/file_transfer/`；A 实现，B、C 只认它们）
- `file_transfer_api.dart`：`FileTransferApi`（`reason`、`readLocalDir`、`removeLink`）、全局 `fileTransferApi`、`RustFileTransferApi`（调块 2 导出）。
- `errors.dart`：`FtReason`（14 个码加 `timeout`；`code` 是 JSON 值，认不出的当 `other`）、`FtSide`、`FtError {reason, args, text}`（`fromJson`、`timeout()`）。文案由 app 映射成 02 §2.5 的句子：C 管栏顶横幅、路径框下和列表区，B 管队列行和对话框。"本机 / 远程设备的磁盘空间不足"这类按方向定：空间不足、文件过大、名称无效、路径过长、目标路径含符号链接只会发生在目标那一侧（上传是远程设备，下载是本机）。
- `pane.dart`：
  - `FilePane`（一栏，`Listenable`，下面每项变了都通知）：`isLocal`；`isWindows`（这一侧的路径规则，"此电脑"是 `/`）；`path`（还没打开过任何文件夹时为空）；`entries`（已按 `sort` 排好、带完整路径，"显示隐藏的项目"关着时不含隐藏项）；`isThisPc`；`canGoBack`、`canGoUp`；`reading`（在读的路径和开始时间，页面约 0.5 秒后才显示"正在读取…"，读的不是当前文件夹时旧内容变暗）；`openError`（打开失败的路径和原因：`path` 为空时显示在列表区、带"转到主文件夹""重试"，否则是栏顶横幅）和 `dismissOpenError()`；`openDirectory(path, showError:)`（返回失败原因；路径输入框传 `showError: false`，错误写在框下、不出横幅）；`goBack()`、`goUp()`、`goHome()`、`refresh()`（保留选择）；`drives()`（根下拉的盘符）；`showHidden` / `setShowHidden`；`sort` / `setSort`（`FileSort` 是列加方向，A 按两栏分别记在本机）；`selection` / `select`（打开别的文件夹时清空，盘符不进选择）；`canRename`（远程栏要求对端版本不低于 1.3.0）；`transfer(items, to:)`（每个顶层项目一个任务，传到另一栏当前文件夹，或放下的那个文件夹或盘符行）；`newFolder()`、`rename(entry)`、`delete(items)`。新建、重命名、删除和传输里的替换确认都由 A 在调用里经 `appCore.prompter` 提问，页面只调方法。
  - `FileTransferModel`（一个文件传输会话）：`local`、`remote`、`jobs`、`uploadPaths(paths, to:)`（从资源管理器拖进来的本机路径，上传到远程栏当前文件夹或放下的那个文件夹行）。
  - `fileTransferOf(FFI)`：返回 `session.fileModel`。
  - `Entry.isLink`（扩展：`entry_type` 2 或 5）；`Entry.isHidden` 在复制件里。
- `jobs.dart`：`FileJobs`（`Listenable`）：`rows`（加入的顺序）；`summary`（`active` 含正在统计、进行中、正在删除，以及 `queued`、`waitingConfirm`、`failed`、`paused`、`interrupted`、`finished`（已完成、已跳过、已取消，"清除已完成"看它）、`progress`（进行中和排队里已知大小的合计 0~1，没有时为空））；`unfinished`（排队中、正在统计、进行中、等待确认，02 §3.1 那句的 ‹N›；已暂停、已中断不算）；`cancel`、`resume`、`resumeAll`、`remove`、`clearFinished`。`FileJobRow`：方向（上传、下载、删除）、名称、源、目标、`FileJobStatus`（排队中、正在统计、进行中、等待确认、正在删除、已暂停、已中断、已完成、已跳过、已取消、失败）、已传和总字节、第几个和共几个文件、只含空文件夹时建了几个文件夹、速度、剩余时间、`FtError`、附注（`EmptyFoldersNotCreated`、`ResumeUnsupported`）。
- `prompts.dart` 里 `Ft` 开头的提问（A 问，B 画；对话框都只遮这个会话标签）：
  - `FtOverwritePrompt`：`name`（文件名，标题用）、`folder`（目标文件夹，正文用）、`kind`（`existing`、`identical`（多一行、默认焦点"跳过"）、`tempOnly`、`existingOrTemp`（判断不了时合并的那句））；回 `OverwriteAnswer`（沿用：替换 / 跳过 / 取消传输，加"对此次传输中的其他冲突执行相同操作"），关掉不答等于"取消传输"。几个冲突由 A 排队，一次只问一个。
  - `FtDeletePrompt`：`isRemote`（"远程设备 / 本机"）、`state`（`ValueListenable<FtDeleteState>`：`FtDeleteCounting`；`FtDeleteReady`（`kind` 文件、空文件夹、文件夹或几项、链接，名称、项数、文件数、字节数）；`FtDeleteCountFailed`（文件夹名、原因）；`FtDeleteOverLimit`（文件夹名、上限、文件数））、`retry`。回 true 才删；关掉、"取消"、"关闭"都是空。对话框跟着 `state` 变：A 有文件夹要统计时先以 `FtDeleteCounting` 问，统计完再改 `state`；统计途中被取消，A 停下（远程的 `ReadAllFiles` 收不回，只是丢掉结果）。
  - `FtNewFolderPrompt`、`FtRenamePrompt`：`isWindows`（"名称不能包含下列字符："按目标系统写）、`check`（输入时就调，返回 `FtNameError`：非法字符、已有同名）、`submit`（点按钮时调，等 Rust 回结果：空是成功，对话框关掉并回名字；非空时对话框写"无法新建文件夹。‹原因›。"/"无法重命名。‹原因›。"、不关）。重命名另有 `name`、`isDirectory`（文件选中扩展名之前的部分），名字没变时"重命名"不可点。"新建"预填的"新建文件夹"是文案，由 B 填。
  - `FtDisconnectPrompt(unfinished)`：回 true 才断开。
  - 旧的 `OverwritePrompt`、`DeletePrompt`、`RenamePrompt`（连同 `DeleteKind`、`DeleteAnswer`、`RenameError`）只被复制件的 `FileModel`、`FileController` 和它们的测试用，A 改写后删掉；`OverwriteChoice`、`OverwriteAnswer` 留着。

**外壳和文件视图的接口**（B、C）
- 视图容器（B，`shell/` 下新文件）：一个标签里按打开的顺序放这台设备的视图，一个当前视图，新打开的视图成为当前视图。远程桌面视图是 `SessionPage(active: 标签选中且当前视图是它)`，不在前台时调 V1 `leapgate_session_set_visible(false)`，切回时设 `true` 再要一帧（§10.4 V1，第一帧之前被切走的处理同 §10.8）。文件视图挂成：

  ```dart
  FileView(
    ffi: s,
    model: fileTransferOf(s),
    active: tabSelected && current == s, // 只有它能拿键盘
    lastView: views.length == 1,         // 连接过程面板写"关闭标签"还是"关闭文件传输"
    viewSwitch: …,                       // B：和远程桌面工具栏同一个控件，"文件传输"带进度
    route: …,                            // B：连接方式标记，点开是 file_route_details.dart
    onDisconnect: …,                     // B：有未完成传输时先 FtDisconnectPrompt，再关这个视图
  )
  ```

- `FileView` 只是一个组件（C），不 import `shell/`。C 画视图标题栏（用组件块的组件，把 `viewSwitch`、`route`、"断开"放进去）、两栏和分隔线；把 `ConnectionPanel(ffi:, active:, lastView:)` 盖在两栏和队列上（`ModalBarrier` 加面板，照 `session_page.dart` 末尾）；把 B 的 `FileQueuePanel(jobs: model.jobs)` 放在底部、占满宽度。
- 键盘：只有当前视图拿键盘。文件视图的快捷键（02 §2.2"键盘"）只在 `active` 时生效，不发给远程设备；标签切换和"关闭标签"（`TabShortcuts`）照常。
- 标签（B）：状态标记取几个视图里最差的连接方式；悬停每个视图一行；未读来自远程桌面视图；`LgSessionTab.progress` 取文件视图的 `jobs.summary.progress`（没有文件视图、没有进行中和排队的任务时为空），`alert` 是 `summary.waitingConfirm > 0`（画提醒标记、不画进度环）。
- 确认（B，02 §3.1、01 §3.2 区块 G）：标签 × 和右键"关闭"同一套：一个视图时直接关（只有文件视图、而且有未完成传输时和视图的"断开"同样确认）；几个视图时"断开与此设备的 ‹N› 个会话？"，有未完成传输时多"‹N› 个传输尚未完成，下次打开文件传输时可继续。"；"关闭其他标签"只在有未完成传输时确认一次；关窗确认加传输那一句，勾过"不再提示"以后有未完成传输仍问（只含传输那句，标题"关闭窗口？"，按钮"关闭""取消"）。传输那句的 ‹N› 是有关标签 `jobs.unfinished` 的合计。
- 入口（B）：`PeerAction.fileTransfer`（设备"⋯"菜单和连接按钮下拉，位置照 01 §3.1 区块 E、F）、标签右键"打开文件传输"、远程桌面工具栏的视图切换，都调 `mainNavigation.openFileTransfer`；已有标签时切到那个标签、显示文件视图；已有远程桌面时 `SessionRegistry.open` 复用连接令牌（现成）。
- `ConnectionPanel.lastView`：为假时按钮写"关闭文件传输"、只关这个视图（B）。

**组件**：规则同 10.8"组件约定"（只管画、文字由调用方传、带语义标签、两套主题和两套尺寸、画廊里每种状态一项、有行为测试），加 10.8 的"合并语义的容器里不放带浮层的组件"。要做的：视图标题栏和视图切换里带进度的一行、小进度环和提醒标记（标签、视图切换按钮、菜单行三处）、栏外框和栏头、导航行、面包屑和路径输入态、根下拉、操作行和栏内搜索框、文件列表的列头和行、状态行、列表空态和错误态（最多两个按钮）、"正在读取"时旧内容变暗、队列面板和各状态的行（"查看详情"展开是 M7b 用的，可以一起做）、拖放的高亮和提示、删除确认"正在统计"那一态。栏顶横幅先试 `LgBanner`；连接方式详情、菜单、表单对话框、断开确认用现成组件。现成组件补了三处（默认参数下画廊导出逐字节不变）：`LgConfirmDialog.leading`（左下的前置按钮，接法同 `LgFormDialog.leading`）；`LgFormDialog.icon` 可以不传（不画标题前的图标块）；`LgMenuItem` 勾选时带勾选语义，读屏能读出。

**几处约定**
- 远程读文件夹没有编号：A 让远程栏同一时刻只发一个读取，后来的排队；`drives()` 用最近一次读"此电脑"的结果，没有时等当前读取结束。远程读文件夹、删除前统计、读空文件夹的超时都是 30 秒，超时是 `FtError.timeout()`。
- 新建、重命名、删除的请求编号由 A 生成、记下，Rust 回 `job_done` / `job_error` 用同一个编号，不改 Rust；新建、重命名等结果再关对话框，失败写在对话框里（`submit` 的返回值）。
- 错误来自哪一侧：Dart 知道是哪一栏的（新建、重命名、删除、统计、读文件夹）直接传 `side`；传输任务传 `unknown`，由 Rust 消歧。`job_error` 的 `cancel` 由 A 先挡掉（行变已取消），`skipped` 当已跳过，都不调 FT2。
- 替换确认的判法（只在 Dart，`io_loop.rs` 不加挂钩）：事件里"两个文件相同"为真 → `identical`；下载（目标在本机）：目标文件在 → `existing`，不在而旁边有 `‹名字›.download` 或 `.digest` → `tempOnly`；上传：目标文件夹正好是远程栏当前打开的文件夹时按已读到的列表同样判，否则 `existingOrTemp`。事件里的路径下载时是本机目标文件的完整路径，上传时是本机源文件的路径；上传的远程目标和正文里的"目标文件夹"由任务的目标文件夹加文件的相对路径拼。
- 删除（R2-Q23）：选中项里有文件夹（不算链接）时先统计（可取消）、问一次、逐个删、删完再删空文件夹；链接（`isLink`）不统计、不递归，调 `removeLink`。
- 传文件夹总带隐藏项（R2-Q22）；"此电脑"不能作目标（页面灰显按钮、拖放不接受，A 在 `transfer`、`newFolder` 里再拒一次）；上次打开的文件夹每次打开成功就存。
- 排序方式、列宽、两栏分隔线的位置、队列面板高度存 LocalConfig 的新键，以 `leapgate-ft-` 开头，键名写在 `consts.dart` 各自那一节。
- 日期用 app 已有的 `win32` 调系统的短日期和时间格式（跟着用户在系统里改过的格式），不是 Windows 时退回 `intl`。
- 拖放用 `desktop_drop` 0.4.4（和上游同版本；加在 `app/pubspec.yaml`，用同一个 `PUB_CACHE` 重新生成 lock；插件注册由 `flutter pub get` 生成进被忽略的 `windows/flutter/generated_plugins.cmake`，不用手改任何文件）；整个窗口一个拖放目标，落在哪栏哪行由 C 按坐标判断；栏间拖放用 Flutter 自带的 `Draggable` / `DragTarget`。从资源管理器拖进来的按本机路径交给 `uploadPaths`（上游方向反了、文件夹被当成文件，按 02 区块 G 重写）。
- 右键"关闭"和 × 同一套确认；"关闭其他标签"只在有未完成的传输时确认一次。
- 大小三位有效数字的新格式只用在文件视图（C 的 `formats.dart`）；`core/lib/common.dart` 的 `readableFileSize` 不改（连接管理小窗的文件记录在用）。
- 复制件里还调 `translate` 的 `JobState.display`、`JobProgress.display` 和写死英文的 "files"，界面不调，留着不改。
- 文件视图不用会话通知横条：复制件 `JobController.jobError` 里单向传输的会话通知照旧发出、没人画，单向传输由 FT2 的 `one_way` 在行里显示。
- 关闭的确认（B）：标签 ×、右键"关闭"、快捷键"关闭标签"共用 `closeSessionTab`；"关闭窗口前确认断开会话"关掉以后，多视图的标签直接关，有未完成传输时仍问，只含传输那一句（标题"关闭标签？"、按钮"关闭""取消"，新文案）。关窗确认的"断开全部 ‹N› 个会话"数的是会话（视图），不是标签。勾过"不再提示"、只因未完成传输而弹的关窗确认：安装版只有传输那一句；便携版记住了"退出"又有出口在跑时，按 §10.12 的关窗规则本来就要确认，合成一个框，正文是传输那句加"‹N› 个出口将停止"。标签里还有文件视图时，远程桌面出错后连接过程面板的按钮写"关闭远程桌面"（`SessionPage.lastView`，新文案），只关这个视图。全屏时关掉远程桌面视图、标签里剩下文件视图，先退出全屏。
- 断线时正在删的删除行记成失败、原因 `FtReason.disconnected`（"连接已中断"，Dart 才有），重新连上也不再接着删（02"删除任务不保存、不续传"）。

**已知限制**
- 拖入时做不出"不接受"的系统光标（插件不设置拖放效果），只在应用里画提示；超过 260 个字符的路径被插件截断（读码推断，未实测）。
- 传输任务收到过 `job_error`（`cancel`、`skipped` 除外）以后，行一直显示"失败：‹第一次的原因›"，随后的 `job_done` 不再把它改成已完成（`jobs.dart` 按任务编号记下第一次的错误，清除行时一起清；例如上传到没有写权限的文件夹，上游先报错、再报完成）。所以文件夹任务里一个文件出错，即使其余文件传完了，整行也显示失败；M7b 的 FT5 再细分（§10.17）。
- 文件视图里的提问照旧按设备遮整个标签，替换确认开着时远程桌面视图也拿不到键盘（和 02"只遮这个会话标签"一致）。
- 打开文件传输时这台设备的远程桌面还在连接、还没拿到令牌，文件传输会再问一次密码（上游同样）。
- 远程读文件夹串行：慢的网络盘上快速连点两层文件夹，后一个要等前一个（排着的读取轮到时已经不是要打开的文件夹，就不发，所以最多多等一次）。
- 远程读文件夹超时（30 秒）以后，迟到的结果会算到下一个读取头上（远程读取的编号是 0、失败不带路径）：横幅写的是下一个文件夹，下一个是"主文件夹"时迟到的成功结果可能被当成主文件夹显示。重试一次恢复。
- 远程读空文件夹失败时被控端什么都不回，只能等到超时，附注写"空文件夹未创建：未能读取。"（两种情况都拿不到个数，附注不带数字）。
- 删除文件夹时中途有文件删不掉，最后一个 `job_done` 会把行改回"已完成"（和上游一致；M7b 改成显示"‹N› 个项目未删除"、可重试，见 §10.17）；本机删空文件夹时 Rust 不回结果，删完直接标完成，删失败也显示完成。
- 删除任务里取消一个单文件删除行，如果 Rust 的结果随后才到，行会从"已取消"变成"已完成"（文件确实已经删掉了）。
- 连接断开、不会自动重试时，进行中的传输行派生成"已暂停"，但任务表里还是进行中，点"继续"不起作用；所以没连上时队列不画"继续""全部继续"（`FileQueuePanel(connection:)`）。
- 重新打开文件传输时列出的上次没传完的任务（`load_last_job`）只写"已暂停"、不画进度条：保存的任务不带字节数（`fs.rs` `TransferJobMeta` 只有编号、路径、第几个文件），点"继续"以后才有进度。
- 上传覆盖被控端上被独占打开的文件时，上游什么错误都不报，行显示"完成"，被控端原文件不变、只留下 `‹名字›.download`（02 §4.3 第 22 条的顺带发现）；M7b 没有专门处理，仍按上游，Leapgate 被控端能不能报出来没有复测。
- 双击在第二次按下时判定：单击一行后 300 毫秒内马上按住拖，会先当成双击（修要加新标记）。
- 队列行的失败短句比 02 §2.5 少半句（"失败：没有访问权限"，02 是"无法读取 / 写入“‹名称›”：……"，FT2 分不出读还是写），文件夹任务里用的是任务的顶层名、不是出错的那个文件；按文件给完整句归 M7b 的"查看详情"（§10.17）。
- Linux 被控端的系统文字被翻译成本地语言时，`unknown` 的消歧会退化：撞号时可能归错，查不到时显示原文。
- 远程 Windows 上目标已不存在的目录链接或目录联接删不掉，报没有访问权限：上游把它列成文件链接（`entry_type` 5），`leapgate_ft_remove_link` 只能发 `FileRemoveFile`。本机这一侧按链接自身的目录属性选 `remove_dir`，不受影响。
- FAT32 上超过 4 GB 的文件显示"磁盘空间不足"（112），下载最后改名时目标正被占用显示"没有访问权限"（5）：在 Windows 上实测如此。错误码和真的盘满、真的没权限一样，只认错误码就分不出来，表不改。
- Windows 安装版远程设备停在登录界面时打不开文件传输，显示上游的英文原文"No active console user logged on, please connect and logon first."（C3 不认识这句，还没有中文文案）。

**测试**
- R：FT2 每条上游原文一个单测（注明源码位置，照 C3），每个码在 Windows、Linux、macOS 各一条，撞号消歧，截断；FT1 的 JSON 带 `is_hidden`；`leapgate_ft_read_local_dir` 的成功和失败；`leapgate_ft_remove_link` 在本机对目录符号链接、目录联接、文件链接只删链接、目标完好（Windows 上建一次性数据测）。
- A：队列行的状态派生（排队中、进行中、正在统计、已中断）、速度和剩余时间、`unfinished`；排序（文件夹和盘符在前、盘符不丢）；删除流程（统计、一次确认、取消、链接不递归，用 `FakeFileTransferApi`）；错误按请求编号交回；远程读取串行；超时；替换确认四态的判法。
- B：外壳的多视图（切换、键盘归属、远程桌面不在前台时 V1）、各种确认（标签 ×、右键关闭、关闭其他标签、关窗、视图断开）、标签上的进度环和提醒标记、各个入口；队列面板各状态和对话框各态，用 `FakeFileJobs` 和假的提问。
- C：02 §2.2"P7 桌面要画的状态"里两栏那几组每组一个行为测试，用 `FakeFileTransferModel`；拖放按坐标判断落点。
- 合入前：`git diff main -- flutter/` 为空；core `flutter analyze --no-fatal-infos` 在 3.44.9 下不超出 92 条 info 的基线，app 0 条；复制件不跑格式化；改已有文件时不对整个文件跑 `dart format`，只格式化新文件。远程桌面的冒烟照跑（改的是它每天都走的外壳）。

### 10.16 M8 的分工约定

M8 是切换：主页的"安装""升级"卡、便携包和发布构建、链接打开文件传输。提示卡的行为以 01 P1 区块 B 为准，文案按 01 §7.6。

**分支**：直接在 `ui/m8` 上做。

**Rust 导出（块 2，`src/leapgate_ffi.rs` 加 `src/leapgate_hooks/` 新文件 `install.rs`）**

| 导出 | 参数 | 返回 |
|---|---|---|
| `leapgate_install` | `kind: String`：`install` 或 `upgrade`（M9a 起加了 `path` 和三个选项，`install` 不再用 `INSTALL_OPTIONS`，子进程参数是 `‹kind› ‹path› ‹options›`，见 §10.18；下面两条说的是 M8 的样子） | 非 `SyncReturn`（frb 在工作线程里跑，Dart 拿到 `Future<String>`）。**成功时不返回**：安装在子进程里跑（见下），子进程退出码是 0 时本进程 `std::process::exit(0)`。失败时返回 JSON `{"result":"uac_denied"\|"failed","text":"‹原文›"}` |

- `install`：路径传空串（`install_me` 用 `get_default_install_info()` 的默认路径，`src/platform/windows.rs:1641-1647`），选项是默认的开始菜单和桌面快捷方式、**不装打印机**（构建里没带驱动）。选项照上游安装页的写法：不是 JSON，是空格分隔的词（`install_page.dart:286-288` 拼成 `startmenu desktopicon printer` 的子集，`install_me` 用 `contains` 认），所以"安装"传 `startmenu desktopicon`（`leapgate::install::INSTALL_OPTIONS`）。
- `upgrade`：路径 `ui_interface::install_path()`，选项由 `platform::get_install_options()`（`:1377`，注册表值的 JSON `STARTMENUSHORTCUTS`、`DESKTOPSHORTCUTS`、`PRINTER`）照安装页的读法换成上面的词（`leapgate::install::upgrade_options`：快捷方式没记 `"0"` 就要，打印机记了 `"1"` 才要；安装页另外会实查打印机装没装，这里不查）。
- **在子进程里装**（不在界面进程里直接调 `install_me`，原因见下面"根因"）：界面进程起 `leapgate.exe --leapgate-install ‹kind›`（stdout 接管道），等它退出。子进程在 `core_main` 里被一行 `leapgate:` 挂钩（`leapgate_hooks::install::child`）接走：算路径和选项、调 `install_me(…, silent = false, …)`，成功退出 0，失败把上面的 JSON 写进管道、退出 1。界面进程见 0 就退出，否则把管道里的内容原样交回卡片（空的时候是 `failed`，原文写退出码）。
  - 管道不留给孙进程：子进程一开头就把管道句柄设成不可继承，并把自己的标准输出换成空句柄，失败时经留下的句柄写结果。不这样做时，`run_after_run_cmds` 起的 `cmd /c … & ‹exe›` 和 `--tray` 都把这条管道当标准输出继承下去，托盘之后用 `run_me` 开的界面也一样。便携版被结束后管道只剩写端，这些进程里一执行 `println!` 就报 os error 232 而 panic，release 是 `panic = 'abort'`，整个进程中止。触发路径之一：断开最后一个会话 → `ContextSend::enable(false)` → `libs/clipboard/src/platform/windows.rs` 的 `println!("Succeeded to uninit cliprdr")`。实测从托盘打开的界面会这样中止（日志 `clipboard context for file transfer destroyed.` 之后进程就没了）；由 `cmd /c` 起的界面同样操作没有中止（推断：经 cmd 起的图形程序没拿到这条管道，没有查证）。
  - 根因：便携版的界面进程持有主 IPC（`\\.\pipe\Leapgate\query`）。脚本 `sc start` 之后，新服务起的 `--server`（SYSTEM，用户会话里）拿不到这个管道，就走 `server.rs` `stop_main_window_process` → `platform::try_kill_rustdesk_main_window_process`，用 `NtTerminateProcess(…, 1)` 结束"同名、命令行只有一个参数、用户不同"的进程，也就是正在等脚本的界面进程。这时脚本还剩 `reg add …SoftwareSASGeneration` 和 `--uninstall-remote-printer` 两步，`run_cmds` 没返回，`run_after_run_cmds` 起安装版和托盘的那几行就没机会跑。用 WMI 进程跟踪（`Win32_ProcessStartTrace` / `StopTrace`）对照服务的 `log\server\` 可以看到：`--server` 起来约 50 ms 后记 `ipc is occupied by another process, try kill it`、`terminate process ‹便携版 PID› success`，便携版退出码 1，此后没有任何由它起的进程。这是一场竞速，偶尔界面进程能活过去、安装版照常起来。
  - 子进程没有主 IPC，命令行也不止一个参数，`--server` 的那一步放过它（上游的安装页 `--install` 也是这样躲开的）。脚本开头的 `taskkill`（`get_uninstall(false, …)`，`:1837-1858`）按 PID 只放过子进程，界面进程在卸载那一步就被结束：点了以后便携版窗口先消失，几秒后安装版起来。
  - 失败回卡片：提权被取消、`install_me` 在提权前报的错（MSI、路径校验）都发生在脚本开跑之前，界面进程还在，照旧回到卡片。脚本已开跑后才失败（少见）的回不到卡片，界面已被 `taskkill` 结束；改之前这种情况界面也会被 `--server` 结束，一样回不来。
- `silent` 传 `false`：`run_after_run_cmds`（`:3976-3989`）起 `--tray` 和安装版。安装版本该等 2 秒（`cmd /c timeout /t 2 & ‹exe›`），实测 `timeout.exe` 当场退出 1（继承来的标准输入不是控制台），安装版和托盘同时起来。那时便携版界面已被 `taskkill` 结束，安装版找不到它的窗口，不会把自己交过去。
- `uac_denied`：提权被取消。`installer_shell.rs` `run_elevated_and_wait` 的 `ShellExecuteExW` 返回 `ERROR_CANCELLED`（1223），windows-rs 的错误文字是"‹系统语言的说明› (0x800704C7)"，`installer_handoff.rs` `run_cmds` 把它格式化进新错误（原错误链丢了，没法 downcast），所以按文字里的 `0x800704C7` 判（`leapgate::install::failure`）；其余一律 `failed`，带原文（`{e:#}`）。MSI 装过的机器上 `install_me` 直接报错（`:1636-1639`），也是 `failed`。
- 配置：安装脚本建服务时带 `--import-config ‹当前用户的配置文件›`（`get_import_config`，`:3938-3950`），读码看便携版的 ID、固定密码、服务器会带进安装版。
- 单测：原因码映射；`upgrade` 取路径和选项的那层（不真的装）。

**上游文件**：`install_me` 里版本号的两处（`:1652` 拆主次版本号、`:1806` 的 DisplayVersion）改用 Leapgate 的版本（`leapgate::ui::VERSION`，0.4.0），各一行，带 `leapgate:` 注释。`update_me`（`:3452` 起）不改：官方更新已关，Leapgate 不走它。`src/core_main.rs` Windows 参数分派的开头加一行 `leapgate:` 挂钩，把 `--leapgate-install` 交给 `leapgate_hooks::install::child`（见上"在子进程里装"）。

**Dart**

- 提示卡（`app/lib/pages/home/home_page.dart` 的本机区，`LgLocalNotice` 带按钮）：
  - 条件：系统错误优先；否则便携版（`!bind.mainIsInstalled()`）显示"安装"卡；否则 `is_installed_lower_version`（现有绑定）为真时显示"升级"卡。一次一张。状态放 core 的本机状态 model（`leapgate/local_status.dart`），页面只画。
  - 点了：按钮变进行中（`LgButton` 的 busy），卡片其余不变；`Future` 回来（只会是失败）时卡片下写一行原因，按钮恢复。`uac_denied` 写"未获得管理员权限，未安装。"（升级卡写"……未升级。"），`failed` 写"安装失败：‹原文›"（升级卡"升级失败：‹原文›"）。原文为空时只写"安装失败。"。实现：`LgLocalNotice` 加了 `actionBusy`（按钮文字换成"正在安装…""正在升级…"）和 `actionError`（按钮下一行红字，在卡片里，和"启动服务"失败的写法一样）。
  - 便携版连着别人或有出口在跑时点"安装"：不另加确认（上游也不问；安装会断开所有会话，见已知限制）。
- 链接（`app/lib/shell/links.dart`）：`file-transfer`（`--file-transfer` 和 `leapgate://file-transfer/…`）接到 `navigation.dart` 的 `openFileTransfer`，参数和 `connection/new` 的密码、中继一样带过去；`port-forward`、`rdp`、`view-camera`、`terminal`、`terminal-admin` 发全局轻提示（`appCore.toasts`），文案"暂不支持打开‹端口转发 / RDP / 摄像头 / 终端›会话。"，日志照旧。`links_test.dart` 跟着改。
- 标题栏（`app/lib/widgets/lg_title_bar.dart:335-344`）：占位方块换成应用图标，从 `app/windows/runner/resources/app_icon.ico` 导出 32×32 的 PNG 放 `app/assets/`，按 16 逻辑像素画；读屏不读它（装饰）。
- ARB：新键以 `homeInstall`、`homeUpgrade`、`linkUnsupported` 开头。

**构建脚本（`scripts/windows/build-client.ps1`、`setup-toolchain.ps1`，总仓库）**

- 这几项在总仓库。
- `-Ui` 默认值改成 `leapgate`；`-Ui upstream` 保留（旧界面便携版）。
- 新界面加便携打包：第 3 步之后调 `client/libs/portable/generate.py`（参数照 `build.py:969-997`），包名 `leapgate-‹libs/leapgate 版本›-x86_64.exe`，放在产物目录旁边；产物核对加上它；同时打一个发布目录的 zip。dpiAware 那一行没删。
- `setup-toolchain.ps1` 装 brotli（`generate.py` 要它）；`build-client.ps1` 开头检查有没有，没有就报错并提示跑 setup。
- 构建前强制刷新构建时间（`BUILD_DATE`，"升级"卡比的就是它）：根 crate 的 `build.rs` 只声明了 `rerun-if-changed`（`build.rs`、`Cargo.toml`、`windows.cc`），没有可借的环境变量，所以脚本在 cargo 之前把 `build.rs` 的修改时间改成现在（内容不动，git 看不出改动），两种界面都这样。
- 默认服务器不注入：脚本开头打印 `LEAPGATE_RENDEZVOUS_SERVER` 等几个变量是否设了，空着就写"未注入默认服务器"。
- 脚本里不写死发布 worktree 的路径。

**已知限制**
- `--install`（exe 或便携包名以 `install.exe` 结尾、手动带参数）写日志后退出（§10.4）。
- 切换后保留的旧界面便携版如果构建时间晚于装着的新界面，会显示"升级"卡，点了会装回旧界面（不改旧界面）。
- 便携版点"安装"会断开所有会话和出口（安装脚本停服务、杀进程）；装的过程中便携版窗口先消失，安装版几秒后起来。
- 默认窗口（约 1280×800）下有安装卡、升级卡时，左栏导航不用滚就能看到（文案已缩短、提示卡的图标在文字第一行行首；安装卡正好放满，没有余量）；安装失败、最小窗口仍要滚，左栏没有常显的滚动条。
- 便携版没在运行时用 `--connect` 冷启动：会话照常连，但这个进程不起服务（`src/core_main.rs` 带参数时不走 `start_server`），主页本机区一直是"正在生成…"和"无法连接服务器，正在自动重试。请检查网络连接。"，这台也连不进来。上游这时只有远程窗口、没有主页，所以不暴露。只有便携版从命令行冷启动才会碰到：安装版有服务，链接只有安装版注册。文案有误导，修要加状态，按罕见情况不修。
- 第三轮链接（端口转发、RDP、摄像头、终端）的"暂不支持打开……会话。"轻提示和其他全局轻提示一样带成功图标：`Toasts` 没有分语气，失败类的轻提示（网络设置导入失败、Wayland 重置失败等）都是这样。

**左栏的滚动**：账号区固定在底部，其余部分在一个 `SingleChildScrollView` 里（01 §2.1），光标在左栏上时能用滚轮滚。Flutter 的 Windows 嵌入层按真实光标的位置分派滚轮、不看消息里的坐标，所以光标停在别处、只往视图投递带左栏坐标的滚轮消息时左栏不动；按坐标投递输入的自动化脚本滚不动左栏，UI Automation 报的是未滚动时视口外节点的位置。
- 回归测试：`app/test/home_page_test.dart`"the mouse wheel brings the navigation into view"，两种尺寸各一条：有安装卡时滚轮把三项导航滚进视口、在"登录"上方，点"出口"能切过去。

**测试**
- Rust：原因码映射、`upgrade` 取值；`cargo test -p leapgate`、根 crate 的 `leapgate_hooks` 测试照跑。
- Dart：卡片的出现条件（便携、已装且较旧、系统错误优先）和失败态（假导出）；链接分派（`file-transfer` 打开文件传输、第三轮几种出轻提示）。
- 合入前：`git diff main -- flutter/` 为空；core analyze 不超出 91 条 info 的基线，app 0 条；新界面和旧界面都要能编（Rust 改了 `install_me`）。

### 10.17 M7b 的分工约定

M7b 是文件传输的暂停、失败保留和重试、个别文件跳过和"查看详情"。界面行为以 02 §2.2 区块 H、§2.4.5~§2.4.7、§3.1 为准；样稿 `A-P7-文件传输-菜单与其他状态.html` 的队列展开画框。不做：修上游的传输缺陷、扩展协议、恢复行的字节数、手机端、符号链接附注。

**先后**：第一段 Rust 只做总开关、事件流和两个方向的暂停（FT3）；两种暂停实测成立以后，第二段再做失败保留和跳过（FT4、FT5）。Dart 一次做完，全部对着假实现写。

**分支和文件边界**（都从 `ui/m7b` 切，做完合回 `ui/m7b`）

| 分支 | 块 | 只改这些 |
|---|---|---|
| `ui/rust-m7b` | Rust | 新文件 `libs/leapgate/src/ft*.rs`（总开关、失败去重、上传读循环、按原因码分"跳过 / 整任务停"、续传起点、4 GiB 规则，纯逻辑带单测）、`libs/leapgate/src/lib.rs`（加 mod）；`src/leapgate_hooks/file_transfer.rs`（和会话、`Remote`、`fs` 打交道的部分）；`src/leapgate_ffi.rs`（末尾追加 M7b 一段）；上游只下面"具名例外"列的八处；本节的 Rust 部分 |
| `ui/m7b-dart` | Dart | core `leapgate/file_transfer/` 的 `jobs.dart`、`file_model.dart`、`file_transfer_api.dart`；`leapgate/session.dart`（事件分发）、`leapgate/session_registry.dart`（加按会话 ID 查找）、应用启动时订阅事件流的那一处；app `pages/files/queue_panel.dart`；`gallery_m7.dart`（只把"部分未传输"行的按钮改成"重试未传输的文件"）；ARB（新键以 `queue` 开头，加在末尾，中英同加，改完 `flutter gen-l10n`）；core、app 的 `test/file_transfer_fakes.dart`（两份同步改、内容相同）；测试。复制件 `core/lib/models/file_model.dart` 不改（只删界面调用那一档），只用它现成的 `updateJobStatus`、`resumeJob`、`cancelJob`、`JobID.next()` |

- `RustFileTransferApi` 的新方法调块 2 的真实导出；Dart 的测试一律用 `FakeFileTransferApi`。
- 组件不动；画廊和组件测试里已有的状态够用。

**上游文件的具名例外**（03 §7.5 原定 FT3~FT5 在 `io_loop.rs` 只占三处，实际是下表列的六处，另有 `download.rs` 的追加；每处带 `// leapgate:` 注释，`io_loop.rs` 里只调 `crate::leapgate_hooks::file_transfer::…`）

| 文件 | 位置 | 做什么 | 行数上限 |
|---|---|---|---|
| `src/client.rs` | `Data` 枚举末尾 | 加 `Leapgate(leapgate::ft::Command)`（`Data` 不带 flutter 也要编，命令类型放 `libs/leapgate`） | 1 |
| `src/client/io_loop.rs` | `handle_msg_from_ui` 的 `match`，`_ => {}` 之前 | `Data::Leapgate(c)` 交给挂钩（暂停、上传软暂停的继续）；第二段起挂钩模块不带 flutter 也编，分支不再带 `cfg`（实际 2 行） | 3 |
| `src/client/io_loop.rs` | 调 `fs::handle_read_jobs` 的那一行（约 `:322`） | 改调 `file_transfer::read_jobs`：开关关着照旧调上游，开着调 Leapgate 版上传读循环（实际改 1 行加 1 行注释） | 3 |
| `src/client/io_loop.rs` | 下载 digest 出错、取消任务之前（约 `:1965`） | 挂钩认领了就 `return true`（回"跳过"给对端，或停下接着传）（实际 2 行） | 2 |
| `src/client/io_loop.rs` | 写数据块之前（约 `:1981`、`:1990`） | 先存下 `block.file_num`，写失败时交给挂钩，认领了就 `return true`、不走取消（实际 2 行） | 3 |
| `src/client/io_loop.rs` | 收到 `FileTransferError`、删任务之前（约 `:2052`） | 挂钩认领了就 `return true`（单文件错误、对端拒绝、整任务失败分开处理）（实际 2 行） | 2 |
| `src/client/io_loop.rs` | 收到对端文件列表时的 `job.set_files(entries)`（约 `:1817`） | 改调 `file_transfer::set_files`：开关关着照旧调上游 `set_files`，开着调下面的 `leapgate_set_download_files`（例如 macOS 对端的 `a:b.txt` 会让上游整张列表被拒、整个任务失败）（实际改 1 行） | 1 |
| `libs/base/src/fs/download.rs` | 文件末尾追加 | `TransferJob::leapgate_set_download_files` 和判据函数，上游的 `set_files` 和各校验函数不动。非改上游不可：`files` 是私有字段，只能在 `fs` 模块里设，而上游 `set_files` 对两类名字整张拒收（以盘符形式开头，如 `a:b.txt`；目标文件夹已存在时含 `?*<>|"` 等，`symlink_metadata` 报 os error 123，接着传、暂停后继续、重试都会撞上） | 追加约 40 行 |

开关关着时每个挂钩都不认领，走上游原来的路（旧界面便携版因此不受影响）；取消路径（`cancel_transfer_job`）不动。

合上游时：`leapgate_set_download_files` 是把上游 `set_files` 重写了一遍（私有字段只能这样设），不是调用它。合并时比对上游 `set_files` 和 `validate_transfer_file_names` 有没有新增检查，有的话照样加进这个方法。

**总开关**：`leapgate_ft_events` 被订阅时打开（进程内一个原子量，新订阅替换旧的 sink），新界面在应用启动时订阅一次，不在视图打开时订阅。这个流只当开关，上面不推任何东西（sink 留着，Dart 那头的流不会结束）；事件走各会话自己的事件流（下面）。

**Rust 导出（块 2）**

| 导出 | 参数 | 返回 |
|---|---|---|
| `leapgate_ft_events` | `sink: StreamSink<String>` | 只当开关，流上没有事件 |
| `leapgate_ft_pause` | `session_id: SessionID`、`id: i32` | 异步、没有返回值；结果是一条 `paused` 事件。任务不在、已结束、对端低于 1.4.2 时什么也不做 |
| `leapgate_ft_resume` | `session_id: SessionID`、`id: i32` | 异步、没有返回值；只用于本次会话里软暂停的上传任务（把它从"等待"改回来）。下载暂停后的继续、关闭视图后恢复的任务，照旧用上游的 `sessionResumeJob(新 ID)` |

**事件**（会话自己的事件流，和上游的 `job_done`、`job_progress` 同一条、先后顺序一致；形状是 `{"name":"leapgate_ft","value":"<JSON 字符串>"}`，写法同上游 `load_last_job`：`push_event("leapgate_ft", &[("value", json)])`。字段不直接摊在事件上，因为上游把事件名写进 `name`，会盖掉 `file_failed` 的 `name`（debug 构建还会断言失败）。`value` 解开是一个对象，每条都带 `kind`、`id`（事件说的那个 Rust 任务 ID），其余字段见下表；对象里的数值和 bool 是 JSON 的数和 bool，不是字符串。Rust 拿不到 `FlutterHandler`（不是 flutter 会话）时不推）

| `kind` | 其余字段 | 含义和界面要做的 |
|---|---|---|
| `paused` | `new_id`、`soft`（bool）、`resume_from`（下一次从第几个文件开始，0 起）、`restart_file`（bool） | 暂停生效。下载：Rust 已删掉原任务、放好一个 `new_id` 的等待任务（关闭视图时照常保存）；上传：`soft` 为真、`new_id == id`，任务原地等待。界面把行改成已暂停、行对应的任务 ID 换成 `new_id` |
| `kept` | `resume_from`、`err`（原文）、`side`（`local` / `remote`）、`restart_file` | 整任务出错停下（磁盘满、写失败等），Rust 里已经没有这个任务、也不保存；临时文件留着。界面显示失败，"重试"时用 `JobID.next()` 取新 ID，`sessionAddJob(…, fileNum: resume_from)` 加 `sessionResumeJob` |
| `continue_from` | `resume_from`、`restart_file` | 单个文件出错、任务停下（下载时对端读失败、本机写数据阶段失败），要从 `resume_from` 接着传；前面必有这个文件的 `file_failed`。界面立刻用新 ID 重新发起，同一行；同一行连续 20 次就不再接着传、整行显示失败（计数在 Dart） |
| `file_failed` | `file_num`（出错文件在任务里的序号，0 起）、`name`（相对任务根的路径，分隔符 `/`）、`err`、`side` | 记一个没传的文件。任务没停的（下载 digest 阶段回了"跳过"、上传本机读失败、上传对端写失败）后面照常有进度和 `job_done` |

- `restart_file`：下载接着传之前，本机临时文件已超过 4 GiB 的已被删掉，这个文件从头传，行上加一条附注。
- 一个任务结束时照旧收到上游的 `job_done` / `job_error`。认领过的错误不再发上游的 `job_error`（避免一行同时收到两种失败）。
- 原文经 `leapgate_ft_reason` 归类，`side` 照传。

**第一段的实现**
- 开关、命令、`paused` 事件的字段、"刚改名的文件"判断和 4 GiB 规则在 `libs/leapgate/src/ft.rs`；sink、命令处理、推事件（`ui_handler` downcast 成 `FlutterHandler` 后调 `push_event`，载荷放在 `value` 里）在 `src/leapgate_hooks/file_transfer.rs`。`io_loop.rs` 第一段只用了 `handle_msg_from_ui` 那一处，上传读循环那一处（约 `:322`）留到第二段。
- 下载暂停：找到运行中（不是等待中）的普通下载任务才动；续传起点是任务当前的 `file_num`，这个文件已经改名、没有 `.download`、大小和列表一致、修改时间和列表差 2 秒以内（FAT32 只有 2 秒精度）时加一；新任务照 `AddJob` 用 `new_write` 建、`is_last_job`、文件列表为空（继续时对端重发列表）；先丢掉旧任务（关掉临时文件）再看起点那个文件的 `.download` 是否超过 `u32::MAX`，超过就删 `.download`、`.digest`。然后给对端发取消、推 `paused`。
- 上传暂停：运行中的读任务标 `is_last_job`，`resume_from` 是读方当前的 `file_num`。暂停期间进度事件照常每秒一条（速度 0）。`leapgate_ft_resume` 只是把 `is_last_job` 改回来，不核对这个任务是不是软暂停的（关闭视图后恢复、还没 `ResumeJob` 的等待任务不要调它）。
- 下载暂停时对端可能已经发出旧 ID 的 `Done` 或错误（取消还没到），上游收到不认识 ID 的 `Done`、`FileTransferError` 也照发旧 ID 的 `job_done` / `job_error`。这时旧任务已删、最后一个文件可能没写完，新任务照常等继续。`paused` 和它们在同一条流上，界面一定先收到 `paused`，按下面第一条规则忽略这些旧 ID 的事件。

**第二段的实现**
- 挂钩模块 `src/leapgate_hooks/file_transfer.rs` 改成不带 flutter 也编（只有 M7a 的几个函数、sink 和推事件那几行带 flutter 的 `cfg`），`io_loop.rs` 的挂钩因此都不带 `cfg`；不带 flutter 时开关永远关着。各挂钩的判断在 `on_*` 函数里，只记下要发给对端的消息和要推的事件，外层再发、再推（先发后推）。
- 怎么归类（`leapgate::ft::fault`，按 FT2 原因码）：`skipped`、单向传输、文件数超限、Android 范围外走上游原路；磁盘满整任务停（`kept`）；其余算单个文件出错。**只有一个文件的任务**（单文件任务，或文件夹里只有一个文件）单个文件出错一律走上游原路（`job_error`，下载照上游删临时文件），磁盘满照样 `kept`。所以 `file_failed` 只出现在多文件任务里，`name` 不会是空串。
- 下载 digest 出错：digest 检查先给上一个文件改名。上一个文件（任务当前的 `file_num`，不是这个 digest 的文件）还有 `.download` 就算改名失败：记它 `file_failed`、停下、从这个 digest 的文件 `continue_from`。否则是这个文件的名字或路径写不了：给对端回 `Skip`，记 `file_failed`，任务接着跑。
- 写数据块出错：先存下 `block.file_num`。任务当前的 `file_num` 和它不同、且当前文件还有 `.download`，就是改名失败，出错的是当前文件；否则出错的是这一块的文件（建临时文件或写入失败）。磁盘满：停下、`kept`（续传起点是出错的文件，`.download` 留着）；其余：记 `file_failed`、停下、从下一个文件 `continue_from`。
- 收到 `FileTransferError`：
  - 下载：`files()` 为空（对端建任务时就拒绝了）、或原因走上游，**走上游原路**（不推 `kept`）。否则出错的文件是 `file_num - 1`（对端先跳到下一个再报）：本机的流还在它前一个文件上就先 `finish_download` 改名（失败另记一条本机的 `file_failed`），流在出错的文件上就留着 `.download`；记 `file_failed`（`side` 是 `remote`），停下，从下一个文件 `continue_from`。磁盘满推 `kept`（`side` 是 `remote`）。
  - 上传：还什么都没发出去（读方未确认、`transferred()` 为 0，从中间续传的任务也一样，是对端在建任务时拒绝了）、或原因走上游，走上游原路。磁盘满：只删本机读任务、不通知对端（对端的写任务和临时文件留着，重试从远程断点接着传），推 `kept`。其余：读方还停在这个文件就 `set_file_skipped`，给对端回 `Skip(f)`（对端已经过了这个文件的会忽略），记 `file_failed`。同一个文件对端后面每个在路上的数据块还会再报一次，按任务记"已报到第几个文件"，重复的认领、不推事件。
  - 本机已经停掉的任务（`kept`、`continue_from`），对端后面再报的错误一律认领、不推事件（不再有上游的 `job_error`）。
- "停下"：删掉任务（先关临时文件），给对端发取消，起点那个文件的 `.download` 超过 `u32::MAX` 就删掉、事件带 `restart_file`，再推 `kept` 或 `continue_from`。起点已经过了最后一个文件（最后一个文件出错）时不推 `continue_from`，改发上游的 `job_done`。
- 上传读循环（`libs/leapgate/src/ft_read.rs`）：和上游一样，每一轮所有没在等待的任务先打开当前文件（并发 digest），然后只读列表里第一个没在等待的任务。不同的两处：打开或读失败的文件不把错误发给对端（对端 CM 会结束整个任务），读到一半出错的补发 `Skip(f)`，记 `file_failed`（`side` 是 `local`）；这一轮打开失败的任务不再读（上游会在这一轮把它当成"已完成"结束掉），下一轮从下一个文件接着。出错后任务没跳到下一个文件的（打开成功、取修改时间失败，例如修改时间早于 1970 年），照上游处理：错误发给对端，同一轮接着读，任务被判成已完成、发 `Done`、删掉（不这样做会每轮都发一条错误，对端第一条就删了写任务，任务永远等确认，同会话后面的上传也被挡住）。用的都是 `fs` 的公开接口（`init_data_stream_for_cm` 加自己发 digest、`read`、`job_completed`、`job_error`），上游的读循环和被控端都不动。
- 已知的空档：
  - 对端在任务结束时也会发完成：下载时对端读失败、本机已经停掉任务，对端（不经 CM 的那种）随后发来的旧 ID `Done` 照上游发 `job_done`；`continue_from` 之后界面已经换了 ID、会忽略，最后一个文件出错时界面会收到两次 `job_done`。`kept` 之后同样可能收到旧 ID 的 `job_done`（取消还没到对端时它已经发完），界面收到 `kept` 后这一行就不该再认这个 ID。
  - 判断"改名失败"靠上一个文件还有没有 `.download`：上一个文件在别的会话留下过 `.download`、这次又被用户跳过时会认错成改名失败，结果只是多从这个文件重新发起一次。
  - 上传时对端写失败、读方已经过了这个文件，对端已经写进去的部分留成 `.download`（`Skip` 让对端丢掉它的流，不删文件）。
- 已知限制（不修）：
  - 改名成功、但改名之后的步骤失败（删 `.digest`、设修改时间）：错误会被算到下一个文件头上，原因原文也挂在错的文件上。不写坏数据，可以重试。
  - "已处理过的错误"记录表（`ft.rs` 的 `HANDLED`）从不清理，每个处理过的任务留一项，量很小。
  - 下载时对端取修改时间失败、没跳到下一个文件：会白白接着传，直到 Dart 的 20 次上限。上游在这种情况下也是整任务停下。
  - 上传时对端 CM 写失败，还在路上的数据块仍可能写坏文件，或者把截短的文件改成正式名（上游原有的空档，宽度和上游一样）。
  - 名字里带控制字符（如 `c\x01d`）不算"在 Windows 上无效"：目标文件夹不存在时能一路过 `validated_target`，到写数据时才失败，走 `write_failed`（`file_failed` 后从下一个文件 `continue_from`），不写坏东西；目标文件夹已存在时照上游整张拒收。
  - Windows 保留设备名（Windows 11 上实测 `NUL`；Windows 10 上大概还有 `CON`、`AUX`、`COMn`、`LPTn`，带不带扩展名都算）仍按上游整张拒收：`validate_component` 不拒它们，加进判据的话会一路通过 `validated_target`。
  - 不发摘要的老对端碰上连续超过 20 个无效名时，每个都走 `write_failed` → `continue_from`，撞上 Dart 的 20 次上限，这一行整体失败。
  - 以"字母 + 冒号"开头的名字（`a:b.txt`）跳过时，原文是上游的 `absolute path detected in file name`，归成 `invalid_name`，详情显示"名称无效"，不是 02 §2.4.5 那句"在 Windows 上无效"；`x?y.txt`、`ab:c.txt` 显示后者。两种都不能重试，结果一样（不加特例）。
  - 最后一个文件出错后界面会收到两次 `job_done`（Rust 发一次，不经 CM 的对端随后再发一次），Dart 已经处理（有测试）。
- 断线重连时带"自动开始"的恢复沿用旧 ID，`HANDLED` 是按 ID 记的、进程里一直在。读码判断不会吞掉重连后的真实错误：只有上传会按文件去重，记下的是对端报过的文件 f；那时读方已经跳过 f 或早已过了 f，断线时保存的 `file_num` 至少是 f+1，重连后只会传 f 之后的文件，它们的序号都大于记下的值。被停掉的任务（`kept`、`continue_from`）已经从任务表删掉，不会保存，也就不会带旧 ID 恢复（读码判断，未实测）。重连后某个文件出错却没有 `file_failed` 时，先查这一条。

**Dart 侧的规则**
- 行不变、Rust 任务 ID 会变：`FileTransferJobs` 维护"行 → 当前任务 ID"。进度只认当前 ID；`job_done`、`job_error`、`override_file_confirm` 只认当前 ID，旧 ID 一律忽略；已暂停的行不认进度事件（软暂停的上传暂停期间每秒仍有一条速度为 0 的进度）。
- 断线重连时，本次会话里用户暂停过的任务 ID（含 `paused` 的 `new_id`；收到 `paused` 事件时才记，点了暂停、事件没回来就断线的照常自动继续）收到带 `auto_start` 的 `load_last_job` 时照不自动开始处理。旧 ID 不另设集合：换 ID 后表里已经没有它，上游的处理函数按 ID 查不到，本来就丢掉。
- 恢复后的排队序号：行记一个序号，下载"继续"、重试、接着传时取当前最大值加一（对端把恢复的下载排到队尾，重试和接着传都是新任务）；上传"继续"序号不变（Rust 把任务留在读任务列表的原位置，读循环取第一个没在等待的，第二段的 Leapgate 版上传读循环要保留这个语义）；同一方向上序号最小、还没结束的是进行中。
- 替换确认发给 Rust 的"记住选择"一律传否，界面按勾选自己逐个回答，用户选"跳过"的计入已跳过。
- "重试未传输的文件"：为每个原因能重试的未传输文件各建一个单文件任务，挂在原来那一行，行回到进行中，进度合计，全部结束后重新判定。
- 详情最多 50 个文件，后面一行"另有 ‹k› 个文件"；"已完成，部分未传输"的行"清除已完成"不清；全是用户跳过的写"已跳过"、不画重试；失败行不加详情。
- 删除的部分失败和重试只在 Dart（02 §2.4.7）；重试时文件或文件夹已经不在的算完成。
- 远程设备低于 1.4.2 时不画"暂停"（02）。
- 用户在替换确认里跳过的文件，详情里用附注样式（不带错误色）。
- 下载暂停时替换确认框正开着：`FtOverwritePrompt` 的 `withdrawn`（`core/lib/leapgate/prompts.dart`）置真，`app/lib/pages/files/file_dialogs.dart` 不带回答关掉。这两处不在上表 Dart 块的文件范围里，是保留的例外。
- 已知限制：两批传输同时勾了"对此次传输中的其他冲突执行相同操作"，先勾的那批会再被问一次（复制件只记一批的选择，按批次记要加状态）。不会发出错误的回答。
- 另外几条规则：已取消的行不处理迟到的 `paused`、`kept`、`continue_from`（`paused` 顺手取消 Rust 放下的等待任务）；上游原路过来的 `job_error` 原因能重试时也记续传起点（单文件从 0，多文件从这一行最近一次进度所在的文件），和 `kept` 一样带"重试"——上传最后一个文件在对端写失败（Rust 读任务已删、走上游原路）也靠这一条，显示成失败而不是"已完成，部分未传输"；4 GB 附注只挂在已暂停和失败的行上；断线重连时从上次会话恢复成已暂停、又被 Rust 带 `auto_start` 开始的行改成进行中；`kept` 时撤回替换确认框；全是用户跳过的行算已完成、会被"清除已完成"清掉。
- 已知限制（不修）：
  - "重试未传输的文件"进行中时，行上没有"暂停"，也不写剩余时间。
  - `continue_from` 正好撞上断线时，那一行卡在进行中（新 ID 的发起落进已断开的循环，新 ID 也不在保存的任务里）。
  - `continue_from` 接着传以后，进度把失败的那个文件也算成已传（上游续传按序号累加）。
  - `kept` 以后用新 ID 重试上传，对端的旧写任务一直留到连接结束，不写坏数据。

**测试**
- Rust：开关关着时每个挂钩都不认领；下载续传起点（"上一个刚改名、下一个还没开始"的空档）；上传读方序号；按原因码分跳过和整任务停；4 GiB 规则。`cargo test -p leapgate` 和根 crate 的 `leapgate_hooks` 测试照跑。
- Dart：上面"Dart 侧的规则"各条。
- 合入前：`git diff main -- flutter/` 为空；core analyze 不超出 91 条 info 的基线，app 0 条；新界面和旧界面都要能编（Rust 改了 `io_loop.rs`）。

### 10.18 M9 的分工约定

M9 是第三轮：安装页（M9a）、终端和摄像头（M9b）、TCP 隧道和 RDP（M9c）。界面行为以 `docs/新界面/13-第三轮内容与逻辑说明.md`（下称"13"）为准；样稿 `A-P8-隧道.html`、`A-P9-终端.html`、`A-P10-摄像头.html`、`A-P11-安装.html`，菜单和本机提示卡看 `A-P1.html`，终端的连接面板看 `A-P2.html#c-terminal`。不做：手机终端页和摄像头页、"不安装直接运行"、隧道登录失败的冷却、修改一条转发、驱动改名、终端内容的逐行读屏。

**三段和分支**

M9 分三段，各段各自合进 main。本节的约定和第 0 步的挂载点先单独合进 main（分支 `ui/m9-0`），各段都从 main 切分支。

| 分支 | 块 | 段 | 合到 |
|---|---|---|---|
| `ui/rust-m9` | R（Rust） | 三段共用 | 各段的整合分支只合自己要的提交（顺序见"Rust 的做法"末条） |
| `ui/m9-ds` | 组件 | 共用 → M9a → M9b → M9c，每段的组件单独提交 | 同上 |
| `ui/m9a` | I（安装页） | M9a | 本身就是 M9a 的整合分支 |
| `ui/m9b-views` | A（视图框架、摄像头） | M9b | `ui/m9b`（A、B 都做完后从 main 切出、合入两路） |
| `ui/m9b-term` | B（终端） | M9b | `ui/m9b` |
| `ui/m9c` | T（隧道） | M9c，M9a 合入 main 后从 main 切 | 本身就是 M9c 的整合分支 |

- 块 2 的桥在 Rust 合进整合分支后重新生成。
- 合 main 的顺序是 M9a → M9b → M9c；后合的段先把 main 合进来。

**文件边界**

| 块 | 只改这些 |
|---|---|
| R | `libs/leapgate/src/reason.rs`（9 个码）、`install.rs`（选项拼法）、新文件 `tunnel.rs`（事件 JSON、登录结局到下一步的纯函数、通道被拒原文的分类）、名称截断的纯函数（`libs/leapgate` 里，文件自定）、`lib.rs`；`src/leapgate_hooks/` 下新文件 `tunnel.rs`，`exit.rs`（抽出建会话的共用函数、几处改 `pub(super)`、监听换成共用的独占监听函数；出口行为和现有测试不变），`install.rs`（子进程参数）；`src/leapgate_hooks.rs`（`mod tunnel`）；`src/leapgate_ffi.rs`（原地改 `leapgate_install` 的签名，其余在末尾追加 M9 一段）；上游只一处，见"挂钩" |
| 组件 | `app/lib/widgets/`（新组件；`lg_exit_card.dart` 的私有部件拆成公共部件、`LgExitCard` 改用它们拼，对外参数和外观不变；`LgViewBar`、`LgBanner`、`LgLocalNotice`、`LgExitPage`、`LgExitSection`、`LgConnectionPanel` 这类现成组件只加参数、默认值不变）、`app/lib/icons/`（重跑 `tools/gen_icons.dart`）、`app/lib/pages/home/home_page.dart` 里只动 `_NavItem` 这一个类、画廊 `gallery_m9a.dart`、`gallery_m9b.dart`、`gallery_m9c.dart`（第 0 步已登记）、组件的测试 |
| I | core 新文件 `leapgate/install_page.dart`（`InstallPageModel`、四项位置检查）、`leapgate/local_status.dart` 的 `install`；app 新文件 `pages/home/install_dialog.dart`、`home_page.dart` 里本机提示卡的 `_InstallNotice` 类和它的构造处（打开对话框要的 `overlays` 从构造处传进去；卡片不再显示进行中和失败；"升级"卡带盾牌；`_NavItem` 归组件块）、`pages/settings/sections/remote_printing.dart`、`main.dart` 的 `--install` 分支（只改注释和日志文字）；`consts.dart` 只在"M9a"下追加；ARB `install` 前缀；测试；总仓库 `scripts/windows/build-client.ps1` 的打印机驱动一步（见"打印机驱动"） |
| A | `app/lib/shell/` 的 `main_window.dart`（含 `openView` 的实现，第 0 步已按文件传输那条路写好，A 按需要改）、`session_views.dart`、`tab_menu.dart`、`links.dart` 的终端、管理员终端、摄像头三支；`app/lib/pages/session/` 全部（连接面板、原因文案、会话页、工具栏、通知、画面提示、录制、聊天）；core 的 `session_requests.dart`、摄像头名称的取值函数（新文件）；`peer_views.dart`、`devices_page.dart` 里终端、终端（管理员）、摄像头三支菜单项，以及照 `openFileTransferPeer` 写的带地址簿共享密码的打开函数；`consts.dart` 只在"M9b views"下追加；ARB `cam`、`view`、`tabMenu`、`connClose`、`connReason`、`link` 前缀；测试 |
| B | core `models/terminal_*.dart`、`models/rustdesk_terminal.dart`（复制件）、`leapgate/terminal/`（`terminals.dart` 里第 0 步写好的 `TerminalOpen`、`terminalOpenState` 不改，`TerminalTabs` 空壳由 B 写满）、`leapgate/session.dart`、`session_registry.dart`、`ffi_model.dart` 的终端部分；app `pages/terminal/`（`terminal_view.dart` 换掉占位，`disconnectTerminalView` 加确认）；`consts.dart` 只在"M9b terminal"下追加；ARB `term` 前缀；测试 |
| T | core 新文件 `leapgate/tunnels.dart`、`tunnel_card.dart`、`card_login.dart`（从 `exit_card.dart` 抽出），`exit_card.dart`、`exit_nodes.dart`（端口互查）、`exit_api.dart`（只改令牌那一行）、`tunnel_api.dart` 分隔线以下、`app_core.dart`（`tunnels` 和三个后台 getter 加上隧道）；app `pages/home/exit/`（`exit_page.dart` 加插槽、`open_tunnel.dart` 写实现、新文件 `tunnel_section.dart`、隧道卡片、RDP 设置对话框）、`shell/window_close.dart`、`links.dart` 的 TCP 隧道和 RDP 两支、`peer_views.dart` 和 `devices_page.dart` 里 TCP 隧道、RDP 两支和 RDP 行的编辑按钮；`consts.dart` 只在"M9c"下追加；ARB `tunnel` 前缀和关窗新句子的 `closing` 前缀，另改几个已有出口文案的值和 `exitHomeLabel`、`exitHomeLabelAttention`（主页标签读屏名）；测试 |

- 第 0 步写好的接口（下一小节）各块都不改。
- ARB 加在两个 ARB 文件末尾，中英同时加，文案照 13 逐字照抄，英文照 13 的英文表，没有的新写并列进提交说明；改完跑 `flutter gen-l10n`。合并时只会有追加冲突。
- 各块先用现成组件和占位把逻辑写通，整合时换成组件块的组件；行为测试按文字和语义标签找控件。
- 块 2 的新导出在桥重新生成后接上真实调用，在那之前调用它们的 Rust 实现抛 `UnimplementedError`（`TODO(M9 整合)`）；测试一律用假实现。改了签名的 `leapgate_install`：位置和三个选项经 `InstallPageModel` 和 `LocalStatusModel.install` 的参数传给它，`core/test/fakes.dart` 里 `FakeLeapgate` 的重写跟着改。
- B 可以 import `app/lib/shell/tab_shortcuts.dart` 用 `matchShortcut`（终端区先拦会话快捷键，拦到的自己执行、返回 `skipRemainingHandlers`：返回 `ignored` 时 xterm 会接着把它认得的组合键（例如 Ctrl+→）发给远程终端，B 的测试证实过）；只剩终端一个视图时"关闭标签"的 `onCloseTab` 归 A 放开。
- core analyze 的基线是 91 条 info（第 0 步合入时），app 0 条。

**第 0 步放好的**（分支 `ui/m9-0`，各段照用）

- **设备菜单**：`PeerAction` 加 `terminal`、`terminalAdmin`、`camera`、`tcpTunnel`、`rdp`。`peerMenu` 的 `bool peerWindows` 换成 `String peerPlatform = ''`（`kPeerPlatform*` 之一，空串是未知）。连接组照样稿 `A-P1.html` 的顺序列全，平台已知不支持的不列、未知照列（R3-Q12，01 §3.1 区块 F）：终端、TCP 隧道在对端不是 Android 时列；终端（管理员）只在对端已知是 Windows 时列（13 §2.1.1）；摄像头在对端不是 macOS、Android 时列；RDP 在本机是 Windows、对端不是已知的非 Windows 时列（13 §1.1.2）；用作出口照旧（对端不是已知的非 Windows；app 另要求 ID 能当出口，`isExitId`）。连接组的规则在私有的 `_connectGroup` 里，`peerMenu` 和 `connectMenu` 共用。连接按钮下拉和"连接到 ‹输入›"的"⋯"改成按 core 新函数 `connectMenu(String peerPlatform, {bool? windows})` 列（`windows` 是本机平台，不传按本机，给测试用）：样稿 `p1-cb-menu` 的八项（远程桌面、文件传输、终端、摄像头、TCP 隧道、用作出口、RDP、经中继），不列终端（管理员）。
- app 里按 `PeerAction` 建菜单项的地方（`peer_views.dart`、`devices_page.dart` 两处下拉），五个新值第 0 步不建（跳过，`TODO(M9b)` / `TODO(M9c)`），A、T 各填各的。
- **链接**：`ConnectLink` 的 `bool fileTransfer` 换成 `LinkKind kind`（`remoteDesktop`、`fileTransfer`、`terminal`、`terminalAdmin`、`camera`、`tcpTunnel`、`rdp`），第三轮的五种也取 ID 和 `--password`、`--relay`；`_open` 按种类分派，五种新的照旧出轻提示，A、T 各换各的。主窗口已在运行时，Rust 只把它列表里的几种（`--terminal`、`--view-camera` 等，`src/core_main.rs` `core_main_invoke_new_connection`）转成链接交给主窗口，列表里没有 `--terminal-admin`，runner 的 `DispatchToUniLinksDesktop` 又只转第一个参数，所以 `leapgate.exe --terminal-admin <ID>` 到主窗口只剩 `--terminal-admin`、打不开。新界面 runner（`app/windows/runner/main.cpp` `TerminalAdminLink`）照 Rust 的拼法把它拼成 `leapgate://terminal-admin/<ID>?password=…&relay=true` 再发，上游文件不改；冷启动时 Dart 从自己的命令行读，本来就认。
- **打开视图**：`MainNavigation.openView(String id, ConnType kind, {bool terminalAdmin = false, String password = '', bool isSharedPassword = false, bool forceRelay = false})`；`openFileTransfer` 留着、转调它（M7a 的调用和测试不动）。主窗口的实现和 `openFileTransfer` 同一条路（`SessionRegistry.open(id, kind, terminalAdmin:)`、切标签、显示那个视图）；视图容器里终端一支挂 `TerminalViewPage`，摄像头一支挂 `SessionPage`。菜单不列、链接不开，所以第 0 步里走不到。
- **会话对象**：`FFI(id, connType, {bool terminalAdmin = false})`，字段 `final bool terminalAdmin`、`TerminalTabs? terminals`（第 0 步恒为空）；`SessionRegistry.open(…, {bool terminalAdmin = false})` 新建时传给 `FFI`；`SessionRegistry.tokenOf(String id)`（这台设备标签里任一视图的连接令牌，`open` 改用它）。
- **终端**：core `leapgate/terminal/terminals.dart` 里 `class TerminalTabs extends ChangeNotifier`（空壳）；`enum TerminalOpen { none, normal, admin }` 和 `TerminalOpen terminalOpenState(String id)`（写好：这台设备的标签里有没有终端视图、是不是管理员终端），设备菜单和视图切换共用（R3-Q9）。app `pages/terminal/terminal_view.dart`：`TerminalViewPage({required FFI ffi, required bool active, required bool lastView, required Widget viewSwitch, required Widget route, required VoidCallback onDisconnect})`（和 `FileView` 同形、没有 `model`），第 0 步是占位；`Future<void> disconnectTerminalView(FFI view)`（和 `disconnectFileView` 同形），第 0 步直接关视图，B 加 R3-Q15 的确认。
- **后台计数**：`AppCore.backgroundCount`、`backgroundAttention`、`backgroundListenable`，第 0 步只数出口（`exitNodes.runningCount`、`exitNodes.needsAttention`、`exitNodes`）；导航、主页标签、关窗确认、服务启停确认四处改调它们，行为不变。T 在 `app_core.dart` 里加上隧道（`backgroundListenable` 改成 `late final` 的 `Listenable.merge`，不要每次读都新建）；I 的安装页直接用。
- **隧道入口**：`ExitPageRequests.request(id, {highlight, TunnelKind? tunnel})`（空是出口卡片），`take()` 带回 `tunnel`；顶层函数 `openTunnel(String id, TunnelKind kind, {String? name, PeerCategory? category, String password = '', bool forceRelay = false})` 在新文件 `app/lib/pages/home/exit/open_tunnel.dart`，第 0 步只记日志，T 照 `useAsExit` 写。
- **TunnelApi**：core `leapgate/tunnel_api.dart`，分隔线以上是接口，以下是 `RustTunnelApi`（块 1 的调用写真的，块 2 的抛 `UnimplementedError`）；`test/tunnel_fakes.dart`（core、app 各一份，内容相同）里是 `FakeTunnelApi`：

  ```dart
  enum TunnelKind { tcp, rdp }
  typedef TunnelForward = ({int localPort, String host, int remotePort});
  typedef RdpSettings = ({String port, String username, String password});

  abstract interface class TunnelApi {
    /// leapgate_tunnel_session_add; null when added, then block 1's sessionStart as for an exit card.
    TunnelAddError? sessionAdd(SessionID sessionId, String id, TunnelKind kind,
        {String password = '', bool isSharedPassword = false, String? connToken, bool forceRelay = false});
    /// leapgate_tunnel_events as JSON maps; subscribing again replaces the old subscription.
    Stream<Map<String, dynamic>> events();
    /// leapgate_tunnel_retry; [port] is 0 for RDP; false without such a card or forward.
    bool retry(SessionID sessionId, int port);
    /// Block 1: sessionAddPortForward, sessionRemovePortForward, sessionNewRdp, sessionClose.
    Future<void> addForward(SessionID sessionId, int localPort, String host, int remotePort);
    Future<void> removeForward(SessionID sessionId, int localPort);
    Future<void> newRdp(SessionID sessionId);
    Future<void> close(SessionID sessionId);
    /// Block 1 mainGetPeerSync's port_forwards, without the exit sentinel and a local or remote port ≤ 0.
    List<TunnelForward> savedForwards(String id);
    /// rdp_port, rdp_username, rdp_password with mainGetPeerOption / mainSetPeerOption.
    RdpSettings rdpSettings(String id);
    Future<void> setRdpSettings(String id, RdpSettings settings);
  }
  ```

  出口占位的两个常量（目标 `leapgate-exit.invalid:65536`）从 `cm_core.dart` 挪到 `consts.dart`，CM 和 `savedForwards` 共用；解析存下的转发是公开的纯函数 `parseSavedForwards`（`tunnel_api.dart`）。
- **依赖**：core `xterm: 4.0.0`（钉死，和上游同版本）、app `xterm: any`，用同一个 `PUB_CACHE` 重新生成两份 lock。后来改成复制件：xterm 4.0.0 的文本输入连接（`custom_text_edit.dart` 的 `TextInput.attach`）不带 `viewId`，Flutter 3.44 起的 Windows 引擎拒收（`Could not set client, view ID is null`），终端里打不进可打印字符和粘贴；pub.dev 上最新就是 4.0.0。所以把包复制到 `leapgate_ui/third_party/xterm/`（`lib/`、LICENSE 等原样，`example/`、`test/` 等不带），只在那一处加 `viewId: View.of(context).viewId`（`// leapgate:` 注释），core 和 app 都用 path 依赖指过去；来源、改动和"上游出了带 viewId 的版本就删掉副本改回 pub"写在包里的 `LEAPGATE.md`。它是第三方包，不是从上游 `flutter/` 复制的，不走 §10.1 的来源行和三方合并；不在 core、app 目录下，两边的 analyze 本来就不扫它。
- **画廊和常量**：`gallery_m9a.dart`、`gallery_m9b.dart`、`gallery_m9c.dart` 登记进 `gallery_main.dart`；`consts.dart` 加"M9a""M9b views""M9b terminal""M9c"四个锚点。

**Rust 导出（块 2）**

| 导出 | 参数 | 返回 / 事件 |
|---|---|---|
| `leapgate_install`（改） | `kind: String`、`path: String`、`start_menu: bool`、`desktop_shortcut: bool`、`printer: bool` | 返回和失败 JSON 同 §10.16；`upgrade` 时后四个忽略。`path` 是界面拼好的整条路径（选中的文件夹加 `\Leapgate`），空串走默认位置 |
| `leapgate_session_display_names` | `session_id: SessionID` | `SyncReturn<String>`：JSON 字符串数组，对端信息里显示器（摄像头会话里是摄像头）的名称，顺序同编号；去掉控制字符、截到 64 个字符；没有会话或还没登录时 `[]` |
| `leapgate_tunnel_session_add` | `session_id`、`id: String`、`rdp: bool`、`password: String`、`is_shared_password: bool`、`conn_token: Option<String>`、`force_relay: bool` | `SyncReturn<String>`：成功 `{}`；`{"error":"already"}`（TCP：这台设备已有端口转发会话，即出口卡片或还开着的隧道卡片，正在关闭的不算；RDP：已有 RDP 会话）；`{"error":"invalid_id"}`；`{"error":"other","text":…}`。和出口卡片一样不调 `LocalConfig::set_remote_id`；不同的是 `args` 为空（出口卡片带三个参数、走上游的三参数分支），`ConnType` 是 `PORT_FORWARD` 或 `RDP`；成功后界面照常调块 1 的 `sessionStart` 拿会话事件流（提问在那条流上） |
| `leapgate_tunnel_events` | 全局 `StreamSink<String>`，和出口的流分开 | 见"事件"；新订阅替换旧的，订阅时先补推每张卡片每一行最后一条状态（通知不补推） |
| `leapgate_tunnel_retry` | `session_id`、`port: i32`（RDP 传 0） | `SyncReturn<bool>`：没有这张卡片或这一行时为假。"重试""重新连接"共用：监听关着（已停止、端口被占用）就重开，开成了马上登录；中断（监听开着、隧道没了）时马上登录；在用或正在连接时什么都不做 |

增删转发、停止、新建 RDP 连接、读存下的转发、RDP 设置都用块 1 现成的导出（见 `TunnelApi`）。界面先做 13 §1.3 区块 B 的三条校验，Rust 不另查。

**事件**（`leapgate_tunnel_events`）：每条带 `"id"`（设备 ID）、`"session_id"`、`"kind"`（`tcp` / `rdp`）；行事件另带 `"port"`（本机端口，RDP 一律 0），卡片事件不带。

| `state` | 类别 | 其余字段 | 说明 |
|---|---|---|---|
| `connecting` | 行 | — | 首次登录、重试或懒重连正在进行；要输入什么看会话事件流 |
| `in_use` | 行 | `"transport"`：`direct` / `relay` | 这一行自己的连接方式（按行记，不读会话共用的 `lc.direct`） |
| `interrupted` | 行 | `"cause"`：`tunnel_ended` / `login_failed`；`login_failed` 时带 `"reason"`（C3 的原因对象）；`reason` 是 `other` 时另带 `"text"`（截到 200 个字符，`stopped` 同） | 监听还开着，下一条本地连接进来就懒重连；没有冷却 |
| `stopped` | 行 | 有原因时带 `"reason"` | 监听已关，等重试或删除。原因：`peer_too_old`（`feature: port_forward`）、`insecure_declined`、被控端拒绝登录的 C3 分类（`no_permission`、`too_many_attempts`、`not_allowed`、`blocked`……）；会再问的（例如重新输入密码）不算结局 |
| `port_in_use` | 行 | — | 本机端口被占用（见"独占监听"） |
| `notice` | 行 | `"reason"`；`other` 时另带 `"text"`（截到 200 个字符） | 不改变行状态：被控端拒绝打开一条通道（13 §1.3 区块 E），上游已按原文 10 秒去重 |
| `removed` | 行 | — | 这一行已删、监听已关 |
| `closed` | 卡片 | — | 卡片循环结束，各行都已收尾 |

卡片的状态和原因都以本流为准，会话流只用来知道要输入什么；报错类回调由 `RowUi` 拦下（见"Rust 的做法"），会话流上不会出现 error 类的消息框，所以没有 §10.12 已知限制第 3 条的两流先后问题。`session_id` 是小写带连字符的 UUID 字符串（和块 1 的 `SessionID` 序列化一致）。

**原因码**（`libs/leapgate/src/reason.rs`，界面文案归各自的路：终端、摄像头的在 `reasons.dart`（A），隧道的在隧道卡片的原因表（T））

| 码 | 参数 | 原文（整串相等，除注明的） |
|---|---|---|
| `tunnel_unreachable` | `target` | 前缀 `Failed to access remote `，取到 `. Please make sure` 之前；旧式裸管道登录时以登录错误出现的同一句也认 |
| `tunnel_too_many_channels` | — | `Too many port forward channels` |
| `insecure_declined` | — | Rust 自己产生（不安全连接选了"断开"），不从原文匹配 |
| `terminal_unsupported` | — | `Remote terminal is not supported by the remote side` |
| `os_login_failed` | — | `Incorrect username or password.` |
| `no_console_user` | — | `No active console user logged on, please connect and logon first.` |
| `os_login_backoff` | `seconds` | 前缀 `Please try again in `，取数字（`second.` / `seconds.`）；解析失败落 `other` |
| `no_cameras` | — | `No cameras` |
| `camera_unsupported` | — | `view_camera_unsupported_tip` |

`No permission of IP tunneling` 沿用已有的 `no_permission`（`port_forward`）；`Port forward target not authorized` 是 `other`。

**挂钩**（上游唯一一处，03 §7.5 具名例外）：`src/ui_session_interface.rs` `io_loop` 端口转发分支里，`handler.lc.write().unwrap().port_forward_mux = crate::port_forward::mux_enabled();` 之后、RDP 判断之前：

```rust
        // leapgate: a new UI tunnel card runs its own loop (LEAPGATE.md §10.18)
        if let Some(card) = crate::leapgate_hooks::tunnel::take(&handler) { return crate::leapgate_hooks::tunnel::run(handler, card, receiver, &key, &token).await; }
```

所有端口转发会话都经过这一行，所以 `take` 必须精确认出登记时的那个会话：登记表的键是（设备 ID，种类），值里存登记时的会话 ID，`take` 只在 `handler` 的会话 ID 和它相同时才取走，对不上一律返回 `None`（同一台设备的出口卡片会话、登记后没 `sessionStart` 就关掉又重开的会话都不会被认领）。不需要总开关；旧界面从不登记，照走上游原路。出口卡片的会话不登记进隧道表，照旧走三参数分支和出口挂钩。合并上游时核对这个分支的结构（`sender`、`port_forward_mux` 先设好）和 `Data::{AddPortForward, RemovePortForward, NewRDP, Close}`。

**Rust 的做法**
- 实现补充：`take` 认会话的办法是登记时把会话的 `lc` 以 `Weak` 存进登记表，`take` 和 `handler.lc` 比是不是同一个（`Session<T>` 没有会话 ID 字段），效果等于按会话 ID 认，也不依赖会话表还在；懒登录一律不打开远程桌面连接（含监听开好后的第一次 `in_use` 若是由本地连接触发的），只有卡片刚打开、从"已停止"重试成功、`NewRDP`（正在连接时也打开，mstsc 的连接在 backlog 里等登录完）这三种打开，从"已中断"重新连接成功不打开（用户原来的窗口自己会重连）；删一行后、`removed` 推出来之前，同一端口的 `AddPortForward` 被忽略，界面要等到 `removed` 再加；查监听表只在 Windows 上做，RDP（本机端口 0）不做。正在关闭的卡片（已 `sessionClose`）不算 `already`，同出口：同一台设备可以马上再加，新卡片替换旧卡片后旧卡片剩下的事件（含它的 `closed`）都被丢掉，界面不要等旧卡片的 `closed`。
- 卡片循环 `run`：TCP 卡片读 `handler.lc.port_forwards`，跳过出口占位和本机或远程端口 ≤ 0 的（同上游，界面的 `savedForwards` 用同一条规则），每条起一行；RDP 卡片端口照上游取 `rdp_port`（解析不了用 3389），起一行（本机端口 0）。收到 `AddPortForward` 起一行（已有同端口的忽略）、`RemovePortForward` 关那一行后推 `removed`、`NewRDP` 打开远程桌面连接、`Close` 或发送端没了就把关闭发给每一行、等全部收尾（照 `login_or_close`）、推 `closed` 再返回；其余 `Data`（登录、二次验证、不安全连接的回答）照上游广播给每一行。登记表照 `exit::cards`，键是（设备 ID，种类），和出口的表分开。
- 单条转发照 `exit::cards::run_card` 另写一份，原函数不改。差别：登录目标是这一行的目标（RDP 是空主机加 RDP 端口、`is_rdp`）；不做 SOCKS 握手；结局不看出口能力（对端支持多路复用就用，不支持停在 `peer_too_old`）；登录失败不冷却；不安全连接被拒记 `insecure_declined`；没有改端口。占位连接、`login_or_close`、K0 守卫的三种结局、隧道结束后的懒重连照搬。
- 按行的 `Interface` 包装 `RowUi`：只有提问类转给会话（要密码、重新输入密码、二次验证、等待对方接受、不安全连接，界面靠它们画提问区）；**报错类一律拦下**，不进会话流：`on_establish_connection_error`、`on_error`（含 `PEER_TOO_OLD`）、`msgbox` 里类型是 error 的（含 `handle_login_error` 转出的登录失败），原文记进这一行，行停下或中断时按 C3 分类当原因。`update_direct` 同时记进这一行。隧道在用时被控端拒绝打开通道（`on_frame` 来的，被控端有四种原文）一律推这一行的 `notice`：认得的三种按下表分类，其余是 `other` 带原文。所以界面不用处理会话流上的错误框（T 照此写 `CardLogin` 的隧道用法）。
- **独占监听**：不复用地址绑 `127.0.0.1:P`；绑定报地址占用（`AddrInUse`）或拒绝访问（`PermissionDenied`，对方独占绑定、系统保留端口段都报这个）算端口被占用。绑上以后，在 Windows 上查 IPv4、IPv6 两张 TCP 监听表（`GetExtendedTcpTable`），`0.0.0.0:P` 或 `[::]:P` 上有 LISTEN 也算被占用：关掉刚开的监听、推 `port_in_use`。不用试绑 `0.0.0.0:P`：本机有一条源端口是 P 的出站连接时试绑也报占用，会凭空误报（在 Windows 上实测，动态端口 1024~15000 里某一时刻约 1/27 的端口被出站连接占着）。出口卡片和旧界面的出口代理换用同一个函数（出口回归一次）。
- RDP：一行进 `in_use` 时，如果是这次监听开好后的第一次（卡片刚打开或从"已停止"重试成功），打开一次远程桌面连接；懒重连成功不打开；`NewRDP` 随时打开。照上游 `run_rdp` 在 `tunnel.rs` 另写，用户名密码从本会话的选项取（会话开始时读进来的那份），不读也不写进程环境变量；`cmdkey`、`mstsc` 放 `spawn_blocking`；窗口标题用上游的 `set_rdp_window_title`。日志写一行 RDP 的本机端口。
- 连接令牌 Rust 不改：两种卡片的导出都收 `conn_token`，界面传 `SessionRegistry.tokenOf` 的值（R3-Q7）。
- 不对隧道会话调 `sessionReconnect`（同出口，会另起一个 `io_loop`）。
- 提交顺序：M9a 的 `leapgate_install` → M9b 的原因码和 `leapgate_session_display_names` → 隧道登记表和导出骨架（事件格式按本节定死，T 对着假实现写）→ 单条转发和 `RowUi` → RDP → 独占监听和出口回归。每个提交单独能编、单测全过；各段的整合分支合到自己那一步为止。

**各段的要点**（只列接口性的）
- M9a：`LocalStatusModel.install(card, {String? path, InstallOptions? options})`，本机提示卡"安装"改成打开对话框，卡片自己不再显示进行中和失败；对话框用 `overlays.show(null, …)`（只遮主页标签），读 `LocalStatusModel` 已有的 `installing`、`installFailure`。四项位置检查在 core，纯函数加一层取系统信息的薄壳，可注入。"修改"从当前位置的上一级开始。有会话时那一行看 `appCore.sessions`、`appCore.backgroundCount`、`LocalStatusModel.incoming`，不复用 `serviceAsksFirst`。runner 的 `--install` 分支留着。
- M9b 视图框架（A）：`session_views.dart` 里按 `ConnType` 的 `switch`，另加 `hasImage`、`usesViewBar`，不建类层次；用在 13 §5.4 列的各处和另外补的 5 处。终端（B）：`FFI.start` 在 `sessionAddSync` 之前按 `terminalAdmin` 设 `IS_TERMINAL_ADMIN`，`terminal` 类型登记 `terminal_response`，`close()` 清终端，`ffi_model.dart` 补 `onReady` 的终端一支；终端区给 `TerminalMouseInteraction` 传 Leapgate 的快捷键表（去掉 Ctrl+A、加 Ctrl+Shift+A），会话快捷键在终端区 `onKeyEvent` 里用 `matchShortcut` 先拦；写进终端的提示行经 core 可注入的 `terminalNoteText`。复制件 `terminal_mouse_handler.dart` 的 `TerminalMouseInteraction` 加一个 `theme` 参数传给 `TerminalView`（上游没有这个参数，终端配色接不进去），这个文件因此从原样档改成改写档，来源行注明这一处；另加一个可选的 `scrollbar` 参数（终端的滚动控制器在组件内部，不加接不上 `LgTerminalScrollbar`；不传时和上游一样）。R3-Q15 的"断开终端？"由终端视图自己画在视图上（`TerminalTabs.askDisconnect`），不经 prompter；从没选中的标签点 × 时，A 的 `closeSessionTab` 只在 `terminals.needsDisconnectConfirm` 为真时先切到那个标签再调 `disconnectTerminalView`，不问时直接关、不切标签。只剩一个终端时 Ctrl+Shift+W 照 13 不起作用（吞掉，不发给远程）。管理员账户的连接面板输入归 A，B 只调 `conn.login`；面板的键用 `viewAdmin` 前缀（属 A 的 `view`）。摄像头（A）：名称在对端信息到了以后取一次，没有时只写编号；"全部摄像头"实测可用时才保留。终端打开时的行列数：`TerminalTabs` 在连接好、"+"、恢复保留的 shell 时当场 `openTerminal`，这时终端区还没排版，请求里是 xterm 的默认 80 × 24；第一次排版的 `onResize` 落在请求和回应之间，上游只在已打开时发 resize，远程就一直是 80 × 24，直到窗口改大小。上游的终端页在页面第一帧之后才打开（`terminal_page.dart:111-128`），所以一般碰不到，但同一个空档上游也有。改写档 `terminal_model.dart` 记下打开请求里的行列数，回应成功时视图大小不同就补发一次 resize；重新连接时重开的终端早已排版，大小相同，不多发。
- M9c（T）：`TunnelsModel` 另起，和出口只共享后台计数、本机端口占用表、抽出的 `CardLogin`（不安全连接按参数分"自动拒绝"（出口）和"问用户"（隧道），抽完先跑出口现有测试）；提问区在没有任何一行还在 `connecting` 时才收起；冲突要等出口卡片移除才解除。

**打印机驱动**：`build-client.ps1` 照上游 CI（`.github/workflows/flutter-build.yml` 打印机驱动那一步）下载驱动和适配器两个 zip、按 sha256 核对、解到程序旁的 `drivers/`。两个 zip 的 sha256 钉在 `scripts/windows/env.ps1` 的 `$LeapgatePins`（`PrinterDriverSha256`、`PrinterAdapterSha256`），上游换了文件就中止构建。
- 安装页"修改"的选择框起始位置是已知限制：`file_picker` 5.5.0 在 Windows 上不处理 `initialDirectory`（插件里设置起始文件夹那段是注释掉的 TODO），选择框打开在系统记住的上次位置；第二次打开时系统回到上次选的文件夹（就是上一级）。界面照传 `initialDirectory`、加 `lockParentWindow: true`。13 §4.2 区块 A 已注明；不自写选择框。

**已知限制**
1. 停止一张走 KCP、隧道在用的卡片，被控端约 20 秒后才关（每条隧道各自 20 秒，并行），同出口（§10.12）。
2. 停在不安全连接提示时取消或点"断开"，被控端约 30 秒后关，同出口。
3. 刚停止又马上为同一台设备打开，旧监听可能还没关，新行先报"端口被占用"，再"重试"一次就好。
4. 加了会话却没有 `sessionStart` 的卡片留在登记表里，下次同一台设备再加时替换。
5. 隧道登录失败不冷却：应用一直重连而对方不在线时，每条本地连接都触发一次登录（上游同样）。
6. 查监听表和真正开始监听之间有一个很短的空档，别的程序在这期间开始监听通配地址时认不出来（下次打开卡片时才报）。
7. `cmdkey /generic:localhost` 全机一个名字（13 §1.7 第 6 条）。
8. 旧界面（`flutter/` 用的还是 pub 上的 xterm 4.0.0）的终端窗口在路线 C 引擎下同样打不进可打印字符，原因同上面"依赖"那条，旧界面不修。
9. 管理员终端的系统用户名和系统密码都去掉首尾空格再发，末尾带空格的系统密码登不上。上游登录对话框也是这样（`common/widgets/dialog.dart` `_connectDialog` 的 `submit`：`osUsernameController`、`osPasswordController`、`passwordController` 都 `trim()`），新界面 `ConnectionModel.login`（`core/lib/leapgate/connection.dart`）照它，不改。
10. 对端是 Windows 时看不到 R3-Q11 那一行（"已重新连接。原终端会话已结束，当前为新的终端会话。"）：这一行照常写进终端，但上游 `portable-pty` 建 ConPTY 不带 `PSEUDOCONSOLE_INHERIT_CURSOR`，新 shell 的第一帧先清屏，把它擦掉。这时用户看到的是一个清空的新 shell，不会误以为原来的程序还在，和 R3-Q11 要的效果一样。对端是 Linux、macOS 时照常显示。在清屏之后补写一次的做法试过，带 oh-my-posh 的 pwsh 重画提示符时照样会擦掉，所以没有采用。
11. 隧道卡片的一行一次只显示最新一条通知，关掉它才露出前一条。

**测试**：合入前：`git diff main -- flutter/` 为空；core analyze 不超出 91 条 info 的基线，app 0 条；复制件不跑格式化，改已有文件不对整个文件跑 `dart format`；新旧界面都要能编（Rust 改了上游 `ui_session_interface.rs` 和出口监听），旧界面的五项冒烟和出口 B15 冒烟照跑。
