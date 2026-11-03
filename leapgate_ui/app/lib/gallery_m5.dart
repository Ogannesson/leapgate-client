// The M5 part of the component gallery: the exit card in every state, the card
// grid, the exit page and the states of its directory, the row of the
// directory, the by-ID row, the thin loading bar, the count with its reminder
// mark on the navigation and on the home tab, next to the P1 mockups of
// A-P1.html (`p1-exit-*`, `p1-ex-*`, `p1-xc-*`). A part of gallery_main.dart,
// so that it shares its helpers.

part of 'gallery_main.dart';

// ---- sample data and helpers -------------------------------------------------

String _x(bool en, String zh, String english) => en ? english : zh;

String _exitDevice(bool en) => en ? "Li Si's desktop" : '李四的台式机';

const _exitId = '912 345 678';
const _exitHelpCode = '--proxy-server=socks5://127.0.0.1:21180';

LgExitAddress _exitSocks(bool en, {int port = 21180}) => LgExitAddress(
  address: 'socks5h://127.0.0.1:$port',
  copyLabel: _x(en, '复制 SOCKS5 地址', 'Copy SOCKS5 address'),
  onCopy: _noop,
);

LgExitAddress _exitHttp(bool en, {int port = 21180}) => LgExitAddress(
  address: 'http://127.0.0.1:$port',
  copyLabel: _x(en, '复制 HTTP 地址', 'Copy HTTP address'),
  onCopy: _noop,
);

List<LgExitAddress> _exitAddresses(bool en, {int port = 21180}) => [
  _exitSocks(en, port: port),
  _exitHttp(en, port: port),
];

LgExitAction _exitChangePort(bool en, {bool primary = false}) => LgExitAction(
  label: _x(en, '修改端口', 'Change port'),
  icon: LgIcons.edit,
  kind: primary ? LgButtonKind.primary : LgButtonKind.text,
  onPressed: _noop,
);

LgExitAction _exitBrowserHelp(bool en, {bool open = false}) => LgExitAction(
  label: _x(en, '浏览器设置说明', 'Browser setup'),
  expanded: open,
  onPressed: _noop,
);

LgExitAction _exitStop(bool en) => LgExitAction(
  label: _x(en, '停止', 'Stop'),
  icon: LgIcons.square,
  kind: LgButtonKind.secondary,
  onPressed: _noop,
);

LgExitAction _exitRemove(bool en) => LgExitAction(
  label: _x(en, '移除', 'Remove'),
  icon: LgIcons.trash,
  kind: LgButtonKind.secondary,
  onPressed: _noop,
);

LgExitAction _exitRetry(bool en) => LgExitAction(
  label: _x(en, '重试', 'Retry'),
  icon: LgIcons.refresh,
  kind: LgButtonKind.primary,
  onPressed: _noop,
);

LgExitAction _exitCancel(bool en) => LgExitAction(
  label: _x(en, '取消', 'Cancel'),
  kind: LgButtonKind.secondary,
  onPressed: _noop,
);

LgExitAction _exitConnect(bool en) => LgExitAction(
  label: _x(en, '连接', 'Connect'),
  kind: LgButtonKind.primary,
  onPressed: _noop,
);

LgExitAction _exitVerify(bool en) => LgExitAction(
  label: _x(en, '验证', 'Verify'),
  kind: LgButtonKind.primary,
  onPressed: _noop,
);

LgExitStatus _exitInUseStatus(bool en, LgRoute route) => LgExitStatus(
  route == LgRoute.direct ? LgExitStatusKind.direct : LgExitStatusKind.relay,
  route == LgRoute.direct
      ? _x(en, '可用 · 直连', 'In use · Direct')
      : _x(en, '可用 · 经中继', 'In use · Via relay'),
  note: route == LgRoute.relay
      ? _x(
          en,
          '流量由中继服务器转发，速度可能较慢',
          'Traffic is forwarded by the relay server and may be slower',
        )
      : null,
);

LgExitHelp _exitHelp(bool en) => LgExitHelp(
  title: _x(en, '浏览器设置说明', 'Browser setup'),
  items: [
    LgExitHelpItem(_x(en, '仅支持 TCP。', 'TCP only.')),
    LgExitHelpItem(
      _x(
        en,
        '仅已配置代理的应用经出口访问网络。',
        'Only applications set to use the proxy go through the exit.',
      ),
    ),
    LgExitHelpItem(
      _x(
        en,
        'Firefox：手动配置 SOCKS v5 代理，并勾选“使用 SOCKS v5 时代理 DNS 查询”。',
        'Firefox: set a SOCKS v5 proxy by hand and turn on "Proxy DNS when using SOCKS v5".',
      ),
    ),
    LgExitHelpItem(
      _x(
        en,
        'Chrome、Edge：使用代理扩展，或添加启动参数 ',
        'Chrome, Edge: use a proxy extension, or add the start parameter ',
      ),
      code: _exitHelpCode,
      after: _x(en, '。', '.'),
    ),
  ],
);

LgExitNotice _exitBlocked(bool en) => LgExitNotice(
  id: 'blocked',
  text: _x(
    en,
    '远程设备已阻止一次访问：目标位于其局域网内、是该设备本身，或其网络的 DNS 返回了虚拟地址。若要访问该设备的局域网，需由其所有者在出口设置中放行相应网段。',
    'The remote device blocked an access: the target is on its local network, is the device itself, or its network\'s DNS returned a virtual address. To reach its local network, its owner must allow the network range in the exit settings.',
  ),
  dismissLabel: _x(en, '关闭', 'Close'),
  onDismiss: _noop,
);

LgExitNotice _exitFakeIp(bool en) => LgExitNotice(
  id: 'fake-ip',
  text: _x(
    en,
    '目标是本机代理应用分配的虚拟地址。请在应用的代理设置中改用远程 DNS 解析（socks5h）。',
    'The target is a virtual address handed out by a proxy application on this computer. In the application\'s proxy settings, use remote DNS resolution (socks5h).',
  ),
  dismissLabel: _x(en, '关闭', 'Close'),
  onDismiss: _noop,
);

LgExitPasswordArea _exitPassword(bool en, {String? error}) => LgExitPasswordArea(
  controller: TextEditingController(text: error == null ? '' : '12345678'),
  semanticLabel: _x(en, '密码', 'Password'),
  placeholder: _x(en, '密码', 'Password'),
  showLabel: _x(en, '显示密码', 'Show password'),
  hideLabel: _x(en, '隐藏密码', 'Hide password'),
  rememberLabel: _x(en, '记住密码', 'Remember password'),
  remember: false,
  onRememberChanged: (_) {},
  errorText: error,
);

LgExitCodeArea _exitCode(
  bool en, {
  String? error,
  String typed = '',
  bool trust = true,
}) => LgExitCodeArea(
  semanticLabel: _x(en, '验证码', 'Verification code'),
  controller: TextEditingController(text: typed),
  // Only when the other side has trusted devices turned on.
  trustLabel: trust ? _x(en, '信任本机', 'Trust this device') : null,
  trust: trust ? false : null,
  onTrustChanged: trust ? (_) {} : null,
  errorText: error,
);

LgExitPortEdit _exitPortEdit(bool en, {String text = '21181', String? error}) =>
    LgExitPortEdit(
      controller: TextEditingController(text: text),
      semanticLabel: _x(en, '端口', 'Port'),
      confirmLabel: _x(en, '确定', 'OK'),
      cancelLabel: _x(en, '取消', 'Cancel'),
      onConfirm: _noop,
      onCancel: _noop,
      hint: _x(
        en,
        '代理地址将改为新端口，需同步修改应用中的代理设置。',
        'The proxy address changes to the new port. Update the proxy settings in your applications.',
      ),
      errorText: error,
    );

/// One card in the state `name`; the states are the rows of 01's table.
LgExitCard _exitCard(
  String state, {
  bool en = false,
  String? name,
  String? id,
  LgPlatform platform = LgPlatform.windows,
}) {
  final device = name ?? _exitDevice(en);
  final spec = id ?? _exitId;
  LgExitCard card({
    required LgExitStatus status,
    LgExitPasswordArea? password,
    LgExitCodeArea? code,
    List<LgExitAddress> addresses = const [],
    List<LgExitNotice> notices = const [],
    LgExitPortEdit? portEdit,
    List<LgExitAction> leading = const [],
    List<LgExitAction> actions = const [],
    LgExitHelp? help,
  }) => LgExitCard(
    name: device,
    id: spec,
    platform: platform,
    status: status,
    password: password,
    code: code,
    addresses: addresses,
    notices: notices,
    portEdit: portEdit,
    leadingActions: leading,
    actions: actions,
    help: help,
  );

  LgExitStatus busy(String zh, String english) =>
      LgExitStatus(LgExitStatusKind.busy, _x(en, zh, english));
  LgExitStatus stopped(String zh, String english) => LgExitStatus(
    LgExitStatusKind.error,
    _x(en, '已停止：', 'Stopped: '),
    reason: _x(en, zh, english),
  );
  List<LgExitAction> inUseLeading({bool open = false}) => [
    _exitChangePort(en),
    _exitBrowserHelp(en, open: open),
  ];

  switch (state) {
    case 'connecting':
      return card(
        status: busy('正在连接 $device…', 'Connecting to $device…'),
        actions: [_exitCancel(en)],
      );
    case 'password':
      return card(
        status: LgExitStatus(
          LgExitStatusKind.password,
          _x(en, '输入密码', 'Enter password'),
        ),
        password: _exitPassword(en),
        actions: [_exitConnect(en), _exitCancel(en)],
      );
    case 'password-wrong':
      return card(
        status: LgExitStatus(
          LgExitStatusKind.password,
          _x(en, '输入密码', 'Enter password'),
        ),
        password: _exitPassword(
          en,
          error: _x(en, '密码错误', 'Wrong password'),
        ),
        actions: [_exitConnect(en), _exitCancel(en)],
      );
    case 'code':
      return card(
        status: LgExitStatus(
          LgExitStatusKind.code,
          _x(en, '输入验证码', 'Enter verification code'),
        ),
        code: _exitCode(en, typed: '482'),
        actions: [_exitVerify(en), _exitCancel(en)],
      );
    case 'code-no-trust':
      return card(
        status: LgExitStatus(
          LgExitStatusKind.code,
          _x(en, '输入验证码', 'Enter verification code'),
        ),
        code: _exitCode(en, typed: '482', trust: false),
        actions: [_exitVerify(en), _exitCancel(en)],
      );
    case 'code-wrong':
      return card(
        status: LgExitStatus(
          LgExitStatusKind.code,
          _x(en, '输入验证码', 'Enter verification code'),
        ),
        code: _exitCode(
          en,
          typed: '482915',
          error: _x(en, '验证码错误', 'Wrong verification code'),
        ),
        actions: [_exitVerify(en), _exitCancel(en)],
      );
    case 'verifying':
      return card(
        status: busy('正在验证…', 'Verifying…'),
        actions: [_exitCancel(en)],
      );
    case 'waiting':
      return card(
        status: LgExitStatus(
          LgExitStatusKind.busy,
          _x(en, '正在等待对方接受…', 'Waiting for the other side to accept…'),
          elapsed: _x(en, '（已等待 0:12）', ' (0:12)'),
        ),
        actions: [_exitCancel(en)],
      );
    case 'direct':
      return card(
        status: _exitInUseStatus(en, LgRoute.direct),
        addresses: _exitAddresses(en),
        leading: inUseLeading(),
        actions: [_exitStop(en)],
      );
    case 'relay':
      return card(
        status: _exitInUseStatus(en, LgRoute.relay),
        addresses: _exitAddresses(en),
        leading: inUseLeading(),
        actions: [_exitStop(en)],
      );
    case 'interrupted':
      return card(
        status: LgExitStatus(
          LgExitStatusKind.warning,
          _x(
            en,
            '连接已中断，下次有应用使用此代理时将自动重新连接',
            'Connection lost. It reconnects when an application uses this proxy next.',
          ),
        ),
        addresses: _exitAddresses(en),
        actions: [
          LgExitAction(
            label: _x(en, '重新连接', 'Reconnect'),
            icon: LgIcons.restart,
            kind: LgButtonKind.primary,
            onPressed: _noop,
          ),
          _exitStop(en),
        ],
      );
    case 'stopped-off':
      return card(
        status: stopped(
          '远程设备未开启“允许作为出口”',
          'The remote device has not turned on "Allow as exit node"',
        ),
        actions: [_exitRetry(en), _exitRemove(en)],
      );
    case 'stopped-old':
      return card(
        status: stopped(
          '远程设备的版本不支持用作出口',
          'The remote device\'s version cannot be used as an exit node',
        ),
        actions: [_exitRemove(en)],
      );
    case 'stopped-plain':
      return card(
        status: stopped(
          '此连接未加密，无法用作出口',
          'This connection is not encrypted and cannot be used as an exit node',
        ),
        actions: [_exitRemove(en)],
      );
    case 'stopped-limit':
      return card(
        status: stopped(
          '验证失败次数过多，请 1 分钟后重试',
          'Too many failed attempts. Try again in 1 minute',
        ),
        actions: [_exitRetry(en), _exitRemove(en)],
      );
    case 'port-busy':
      return card(
        status: LgExitStatus(
          LgExitStatusKind.error,
          _x(
            en,
            '本机端口 21180 已被其他应用占用',
            'Local port 21180 is in use by another application',
          ),
        ),
        actions: [_exitChangePort(en, primary: true), _exitRemove(en)],
      );
    case 'port-edit':
      return card(
        status: _exitInUseStatus(en, LgRoute.relay),
        addresses: _exitAddresses(en),
        portEdit: _exitPortEdit(en),
      );
    case 'port-edit-error':
      return card(
        status: _exitInUseStatus(en, LgRoute.relay),
        addresses: _exitAddresses(en),
        portEdit: _exitPortEdit(
          en,
          text: '21182',
          error: _x(
            en,
            '此端口已被另一个出口使用',
            'This port is already used by another exit node',
          ),
        ),
      );
    case 'port-edit-busy':
      return card(
        status: LgExitStatus(
          LgExitStatusKind.error,
          _x(
            en,
            '本机端口 21180 已被其他应用占用',
            'Local port 21180 is in use by another application',
          ),
        ),
        portEdit: LgExitPortEdit(
          controller: TextEditingController(text: '21181'),
          semanticLabel: _x(en, '端口', 'Port'),
          confirmLabel: _x(en, '确定', 'OK'),
          cancelLabel: _x(en, '取消', 'Cancel'),
          onConfirm: _noop,
          onCancel: _noop,
        ),
      );
    case 'notice-blocked':
      return card(
        status: _exitInUseStatus(en, LgRoute.relay),
        addresses: _exitAddresses(en),
        notices: [_exitBlocked(en)],
        leading: inUseLeading(),
        actions: [_exitStop(en)],
      );
    case 'notice-fake-ip':
      return card(
        status: _exitInUseStatus(en, LgRoute.relay),
        addresses: _exitAddresses(en),
        notices: [_exitFakeIp(en)],
        leading: inUseLeading(),
        actions: [_exitStop(en)],
      );
    case 'notice-two':
      return card(
        status: _exitInUseStatus(en, LgRoute.direct),
        addresses: _exitAddresses(en),
        notices: [_exitBlocked(en), _exitFakeIp(en)],
        leading: inUseLeading(),
        actions: [_exitStop(en)],
      );
    case 'help':
      return card(
        status: _exitInUseStatus(en, LgRoute.relay),
        addresses: _exitAddresses(en),
        leading: inUseLeading(open: true),
        actions: [_exitStop(en)],
        help: _exitHelp(en),
      );
  }
  throw ArgumentError(state);
}

// ---- the specimens ------------------------------------------------------------

List<Specimen> _m5Specimens() {
  final list = <Specimen>[];

  Specimen card(
    String name,
    String state, {
    double height = 196,
    bool en = false,
    Set<WidgetState> states = const {},
  }) => Specimen(
    'exit-card',
    name,
    Size(530, height),
    states: states,
    (_) => SizedBox(width: 498, child: _exitCard(state, en: en)),
  );

  // States of 01's table, in the order of the table ------------------------------
  list
    ..add(card('connecting', 'connecting'))
    ..add(card('password', 'password', height: 300))
    ..add(card('password-wrong', 'password-wrong', height: 336))
    ..add(
      card(
        'password-focus',
        'password',
        height: 300,
        states: const {WidgetState.focused},
      ),
    )
    ..add(card('code', 'code', height: 330))
    ..add(card('code-no-trust', 'code-no-trust', height: 290))
    ..add(card('code-wrong', 'code-wrong', height: 360))
    ..add(card('verifying', 'verifying'))
    ..add(card('waiting', 'waiting'))
    ..add(card('in-use-direct', 'direct', height: 300))
    ..add(card('in-use-relay', 'relay', height: 300))
    ..add(
      card('in-use-hover', 'relay', height: 300, states: const {WidgetState.hovered}),
    )
    ..add(
      card('in-use-focus', 'relay', height: 300, states: const {WidgetState.focused}),
    )
    ..add(card('interrupted', 'interrupted', height: 300))
    ..add(card('stopped-not-enabled', 'stopped-off'))
    ..add(card('stopped-too-old', 'stopped-old'))
    ..add(card('stopped-unencrypted', 'stopped-plain'))
    ..add(card('stopped-too-many-attempts', 'stopped-limit'))
    ..add(card('port-busy', 'port-busy'))
    ..add(card('port-edit', 'port-edit', height: 344))
    ..add(card('port-edit-error', 'port-edit-error', height: 360))
    ..add(card('port-edit-busy', 'port-edit-busy', height: 260))
    ..add(card('notice-blocked', 'notice-blocked', height: 424))
    ..add(card('notice-fake-ip', 'notice-fake-ip', height: 380))
    ..add(card('notice-two', 'notice-two', height: 520))
    ..add(card('help-open', 'help', height: 500));

  // The same in English, where the words run longer ------------------------------
  list
    ..add(card('connecting-english', 'connecting', en: true))
    ..add(card('password-english', 'password', height: 300, en: true))
    ..add(card('password-wrong-english', 'password-wrong', height: 336, en: true))
    ..add(card('code-english', 'code', height: 330, en: true))
    ..add(card('waiting-english', 'waiting', height: 220, en: true))
    ..add(card('in-use-relay-english', 'relay', height: 340, en: true))
    ..add(card('interrupted-english', 'interrupted', height: 330, en: true))
    ..add(card('stopped-english', 'stopped-off', height: 240, en: true))
    ..add(card('port-busy-english', 'port-busy', height: 240, en: true))
    ..add(card('port-edit-english', 'port-edit', height: 380, en: true))
    ..add(card('notice-blocked-english', 'notice-blocked', height: 480, en: true))
    ..add(card('help-open-english', 'help', height: 540, en: true));

  // A name and an ID that do not fit; a different platform ----------------------
  list
    ..add(
      Specimen(
        'exit-card',
        'long-name',
        const Size(530, 300),
        (_) => SizedBox(
          width: 498,
          child: _exitCard(
            'direct',
            name: '工作室二楼靠窗那台一直开着的绘图工作站（备用）',
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'exit-card',
        'macos',
        const Size(530, 300),
        (_) => SizedBox(
          width: 498,
          child: _exitCard('direct', name: '老王的 MacBook', id: '234 567 891', platform: LgPlatform.macos),
        ),
      ),
    );

  // The short frame round a card that was scrolled to ---------------------------
  list.add(
    Specimen(
      'exit-card',
      'flash',
      const Size(530, 300),
      (_) => SizedBox(
        width: 498,
        child: LgFlash(showing: true, child: _exitCard('relay')),
      ),
    ),
  );

  // The grid ----------------------------------------------------------------------
  Specimen grid(String name, double width, double height, List<Widget> Function() cards,
      {double pad = 16}) {
    return Specimen(
      'exit-grid',
      name,
      Size(width, height),
      padding: pad,
      (_) => SizedBox(
        width: width - pad * 2,
        child: LgExitCardGrid(
          semanticLabel: '正在使用的出口',
          children: cards(),
        ),
      ),
    );
  }

  list
    ..add(
      grid('two-columns', 1040, 400, () => [
        _exitCard('relay'),
        _exitCard('password', name: '书房台式机', id: '123 456 789'),
      ]),
    )
    ..add(
      grid('three-cards-two-columns', 1040, 760, () => [
        _exitCard('relay'),
        _exitCard('password', name: '书房台式机', id: '123 456 789'),
        _exitCard('stopped-off', name: '妈妈的笔记本', id: '234 567 891', platform: LgPlatform.macos),
      ]),
    )
    ..add(
      grid('one-column', 560, 760, () => [
        _exitCard('direct'),
        _exitCard('interrupted', name: '书房台式机', id: '123 456 789'),
      ]),
    )
    ..add(
      grid('three-columns', 1440, 400, () => [
        _exitCard('direct'),
        _exitCard('connecting', name: '书房台式机', id: '123 456 789'),
        _exitCard('stopped-old', name: '妈妈的笔记本', id: '234 567 891'),
      ]),
    );

  // The page ----------------------------------------------------------------------
  Widget pagePane(Widget Function(BuildContext) body, {required double height}) =>
      SizedBox(
        width: 1040,
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            LgSpace.s2,
            LgSpace.s4,
            LgSpace.s6,
            0,
          ),
          child: Builder(builder: body),
        ),
      );

  Widget pageTitle(BuildContext context) => Text(
    '出口',
    style: LgTokens.style(
      20,
      28,
      FontWeight.w700,
    ).copyWith(color: LgTokens.of(context).colors.text),
  );

  Widget page(
    BuildContext context, {
    bool en = false,
    Widget? inUse,
    Widget? directory,
    Widget? byId,
    bool refresh = true,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      pageTitle(context),
      const SizedBox(height: LgSpace.s1),
      Expanded(
        child: LgExitPage(
          lede: _x(
            en,
            '通过其他设备的网络访问互联网。仅对已配置代理的应用生效，且只支持 TCP 连接。',
            'Reach the internet through another device\'s network. Only applications set to use the proxy are affected, and only TCP connections are supported.',
          ),
          inUseTitle: _x(en, '正在使用', 'In use'),
          inUse: inUse ?? const SizedBox.shrink(),
          directoryTitle: _x(en, '可用的出口', 'Available exit nodes'),
          refreshLabel: _x(en, '刷新', 'Refresh'),
          onRefresh: refresh ? _noop : null,
          directory: directory ?? const SizedBox.shrink(),
          byIdTitle: _x(en, '按 ID 指定出口', 'Use an exit node by ID'),
          byId: byId ?? _exitById(en),
        ),
      ),
    ],
  );

  list
    ..add(
      Specimen(
        'exit-page',
        'one-card',
        const Size(1040, 760),
        padding: 0,
        (_) => pagePane(
          (context) => page(
            context,
            inUse: LgExitCardGrid(
              semanticLabel: '正在使用的出口',
              children: [_exitCard('relay')],
            ),
            directory: LgExitDirectory.rows(entries: _exitEntries(false, inUse: true)),
          ),
          height: 760,
        ),
      ),
    )
    ..add(
      Specimen(
        'exit-page',
        'one-card-english',
        const Size(1040, 760),
        padding: 0,
        (_) => pagePane(
          (context) => page(
            context,
            en: true,
            inUse: LgExitCardGrid(
              semanticLabel: 'Exit nodes in use',
              children: [_exitCard('relay', en: true)],
            ),
            directory: LgExitDirectory.rows(entries: _exitEntries(true, inUse: true)),
          ),
          height: 760,
        ),
      ),
    )
    ..add(
      Specimen(
        'exit-page',
        'none-in-use',
        const Size(1040, 384),
        padding: 0,
        (_) => pagePane(
          (context) => page(
            context,
            inUse: const LgExitEmptyNote('暂无正在使用的出口'),
            directory: LgExitDirectory.rows(entries: _exitEntries(false)),
          ),
          height: 384,
        ),
      ),
    )
    ..add(
      Specimen(
        'exit-page',
        'two-cards',
        const Size(1040, 900),
        padding: 0,
        (_) => pagePane(
          (context) => page(
            context,
            inUse: LgExitCardGrid(
              semanticLabel: '正在使用的出口',
              children: [
                _exitCard('relay'),
                _exitCard('password', name: '书房台式机', id: '123 456 789'),
              ],
            ),
            directory: LgExitDirectory.rows(entries: _exitEntries(false, inUse: true)),
          ),
          height: 900,
        ),
      ),
    )
    ..add(
      Specimen(
        'exit-page',
        'scrolled',
        const Size(1040, 420),
        padding: 0,
        (_) => pagePane(
          (context) => page(
            context,
            inUse: LgExitCardGrid(
              semanticLabel: '正在使用的出口',
              children: [
                _exitCard('relay'),
                _exitCard('password', name: '书房台式机', id: '123 456 789'),
              ],
            ),
            directory: LgExitDirectory.rows(entries: _exitEntries(false, inUse: true)),
          ),
          height: 420,
        ),
      ),
    );

  // The directory, one state at a time (the crops of the mockup) --------------------
  Specimen directory(
    String name,
    double height,
    LgExitDirectory Function(bool en) state, {
    bool en = false,
    bool refresh = true,
    Widget? byId,
  }) => Specimen(
    'exit-directory',
    name,
    Size(1040, height),
    padding: 0,
    (_) => pagePane(
      (context) => SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LgExitSection(
              title: _x(en, '可用的出口', 'Available exit nodes'),
              action: LgButton(
                label: _x(en, '刷新', 'Refresh'),
                icon: LgIcons.refresh,
                kind: LgButtonKind.text,
                onPressed: refresh ? _noop : null,
              ),
            ),
            state(en),
            LgExitSection(title: _x(en, '按 ID 指定出口', 'Use an exit node by ID')),
            const SizedBox(height: LgSpace.s2),
            byId ?? _exitById(en),
          ],
        ),
      ),
      height: height,
    ),
  );

  list
    ..add(
      directory(
        'rows',
        300,
        (en) => LgExitDirectory.rows(entries: _exitEntries(en)),
      ),
    )
    ..add(
      directory(
        'rows-in-use',
        300,
        (en) => LgExitDirectory.rows(entries: _exitEntries(en, inUse: true)),
      ),
    )
    ..add(
      directory(
        'rows-english',
        300,
        en: true,
        (en) => LgExitDirectory.rows(entries: _exitEntries(en, inUse: true)),
      ),
    )
    ..add(
      directory(
        'loading',
        232,
        refresh: false,
        (en) => LgExitDirectory.loading(
          semanticLabel: _x(en, '正在加载出口目录', 'Loading the exit directory'),
        ),
      ),
    )
    ..add(
      directory(
        'unsupported',
        272,
        (en) => LgExitDirectory.unsupported(
          text: _x(
            en,
            '当前服务器不提供出口目录。仍可按 ID 指定出口。',
            'This server does not provide an exit directory. You can still name an exit node by ID.',
          ),
        ),
      ),
    )
    ..add(
      directory(
        'unsupported-english',
        272,
        en: true,
        (en) => LgExitDirectory.unsupported(
          text: _x(
            en,
            '当前服务器不提供出口目录。仍可按 ID 指定出口。',
            'This server does not provide an exit directory. You can still name an exit node by ID.',
          ),
        ),
      ),
    )
    ..add(
      directory(
        'not-logged-in',
        448,
        (en) => LgExitDirectory.notLoggedIn(
          text: _x(en, '登录后可查看出口目录', 'Sign in to see the exit directory'),
          actionLabel: _x(en, '登录', 'Sign in'),
          onAction: _noop,
        ),
      ),
    )
    ..add(
      directory(
        'empty',
        420,
        (en) => LgExitDirectory.empty(
          text: _x(
            en,
            '暂无可用的出口。此处仅列出当前账号有权使用、在线，且已在设备设置中开启“允许作为出口”的设备。',
            'No exit nodes are available. This list only shows devices that this account may use, that are online and that have turned on "Allow as exit node" in their settings.',
          ),
        ),
      ),
    )
    ..add(
      directory(
        'empty-english',
        420,
        en: true,
        (en) => LgExitDirectory.empty(
          text: _x(
            en,
            '暂无可用的出口。此处仅列出当前账号有权使用、在线，且已在设备设置中开启“允许作为出口”的设备。',
            'No exit nodes are available. This list only shows devices that this account may use, that are online and that have turned on "Allow as exit node" in their settings.',
          ),
        ),
      ),
    )
    ..add(
      directory(
        'error',
        448,
        (en) => LgExitDirectory.error(
          text: _x(en, '无法加载出口目录', 'Could not load the exit directory'),
          actionLabel: _x(en, '重试', 'Retry'),
          onAction: _noop,
        ),
      ),
    );

  // The by-ID row ----------------------------------------------------------------
  Specimen byId(
    String name,
    Widget Function(bool en) build, {
    double height = 140,
    bool en = false,
    Set<WidgetState> states = const {},
  }) => Specimen(
        'exit-by-id',
        name,
        Size(1040, height),
        padding: 0,
        states: states,
        (_) => pagePane(
          (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LgExitSection(title: _x(en, '按 ID 指定出口', 'Use an exit node by ID')),
              const SizedBox(height: LgSpace.s2),
              build(en),
            ],
          ),
          height: height,
        ),
      );

  list
    ..add(byId('empty', (en) => _exitById(en)))
    ..add(
      byId(
        'typed',
        (en) => _exitById(en, text: '135792468', onUse: _noop),
      ),
    )
    ..add(
      byId(
        'focus',
        (en) => _exitById(en, text: '135792468', onUse: _noop),
        states: const {WidgetState.focused},
      ),
    )
    ..add(
      byId(
        'error',
        (en) => _exitById(
          en,
          text: '12345',
          onUse: _noop,
          error: _x(en, 'ID 格式不正确', 'The ID is not valid'),
        ),
        height: 180,
      ),
    )
    ..add(
      byId(
        'english',
        (en) => _exitById(en, text: '135792468', onUse: _noop),
        en: true,
      ),
    );

  // Parts ----------------------------------------------------------------------------
  list
    ..add(
      Specimen(
        'exit-parts',
        'loading-bar',
        const Size(520, 60),
        (_) => const SizedBox(
          width: 488,
          child: LgIndeterminateBar(semanticLabel: '正在加载出口目录'),
        ),
      ),
    )
    ..add(
      Specimen(
        'exit-parts',
        'section-title',
        const Size(520, 80),
        (_) => const SizedBox(
          width: 488,
          child: LgExitSection(
            title: '可用的出口',
            action: LgButton(
              label: '刷新',
              icon: LgIcons.refresh,
              kind: LgButtonKind.text,
              onPressed: _noop,
            ),
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'exit-parts',
        'section-title-disabled',
        const Size(520, 80),
        (_) => const SizedBox(
          width: 488,
          child: LgExitSection(
            title: '可用的出口',
            action: LgButton(
              label: '刷新',
              icon: LgIcons.refresh,
              kind: LgButtonKind.text,
              onPressed: null,
            ),
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'exit-parts',
        'empty-note',
        const Size(520, 110),
        (_) => const SizedBox(width: 488, child: LgExitEmptyNote('暂无正在使用的出口')),
      ),
    )
    ..add(
      Specimen(
        'exit-parts',
        'count-marks',
        const Size(420, 100),
        (_) => const Row(
          children: [
            LgCountMark(1),
            SizedBox(width: LgSpace.s5),
            LgCountMark(2, alert: true),
            SizedBox(width: LgSpace.s5),
            LgCountMark(12, alert: true, gap: 12),
            SizedBox(width: LgSpace.s5),
            LgCountMark(99),
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'exit-parts',
        'directory-row-use',
        const Size(1040, 90),
        padding: 0,
        (_) => pagePane(
          (_) => LgListSurface(
            child: LgExitDirectoryRow(
              topDivider: false,
              entry: _exitEntries(false).first,
            ),
          ),
          height: 90,
        ),
      ),
    )
    ..add(
      Specimen(
        'exit-parts',
        'directory-row-use-hover',
        const Size(1040, 90),
        padding: 0,
        states: const {WidgetState.hovered},
        (_) => pagePane(
          (_) => LgListSurface(
            child: LgExitDirectoryRow(
              topDivider: false,
              entry: _exitEntries(false).first,
            ),
          ),
          height: 90,
        ),
      ),
    )
    ..add(
      Specimen(
        'exit-parts',
        'directory-row-use-focus',
        const Size(1040, 90),
        padding: 0,
        states: const {WidgetState.focused},
        (_) => pagePane(
          (_) => LgListSurface(
            child: LgExitDirectoryRow(
              topDivider: false,
              entry: _exitEntries(false).first,
            ),
          ),
          height: 90,
        ),
      ),
    )
    ..add(
      Specimen(
        'exit-parts',
        'directory-row-in-use',
        const Size(1040, 90),
        padding: 0,
        (_) => pagePane(
          (_) => LgListSurface(
            child: LgExitDirectoryRow(
              topDivider: false,
              entry: _exitEntries(false, inUse: true).first,
            ),
          ),
          height: 90,
        ),
      ),
    )
    ..add(
      Specimen(
        'exit-parts',
        'directory-row-long-name',
        const Size(1040, 90),
        padding: 0,
        (_) => pagePane(
          (_) => const LgListSurface(
            child: LgExitDirectoryRow(
              topDivider: false,
              entry: LgExitEntry(
                name: '工作室二楼靠窗那台一直开着的绘图工作站（备用）',
                id: '234 567 891',
                platform: LgPlatform.windows,
                owner: '所有者：李四的工作室',
                actionLabel: '使用',
                onPressed: _noop,
              ),
            ),
          ),
          height: 90,
        ),
      ),
    );

  // The reminder on the navigation and on the home tab (`p1-ex-remind`) -------------
  list
    ..add(
      Specimen(
        'exit-reminder',
        'waiting',
        const Size(720, 280),
        padding: 0,
        (_) => _exitReminderFrame(alert: true),
      ),
    )
    ..add(
      Specimen(
        'exit-reminder',
        'running',
        const Size(720, 280),
        padding: 0,
        (_) => _exitReminderFrame(alert: false),
      ),
    )
    ..add(
      Specimen(
        'exit-reminder',
        'on-exit-page',
        const Size(720, 280),
        padding: 0,
        (_) => _exitReminderFrame(alert: true, selectExit: true),
      ),
    );
  return list;
}

Widget _exitById(
  bool en, {
  String text = '',
  VoidCallback? onUse,
  String? error,
}) => LgExitByIdRow(
  controller: TextEditingController(text: text),
  placeholder: _x(en, '输入设备 ID', 'Enter the device ID'),
  semanticLabel: _x(en, '设备 ID', 'Device ID'),
  useLabel: _x(en, '使用', 'Use'),
  onUse: onUse,
  errorText: error,
);

List<LgExitEntry> _exitEntries(bool en, {bool inUse = false}) => [
  LgExitEntry(
    name: _exitDevice(en),
    id: _exitId,
    platform: LgPlatform.windows,
    owner: _x(en, '所有者：李四', 'Owner: Li Si'),
    actionLabel: inUse ? _x(en, '使用中', 'In use') : _x(en, '使用', 'Use'),
    inUse: inUse,
    onPressed: _noop,
  ),
  LgExitEntry(
    name: _x(en, '书房台式机', 'Study desktop'),
    id: '123 456 789',
    platform: LgPlatform.windows,
    owner: _x(en, '我的', 'Mine'),
    actionLabel: _x(en, '使用', 'Use'),
    onPressed: _noop,
  ),
];

/// The title bar and the navigation as `p1-ex-remind` draws them: the home tab
/// and the "出口" item with the count, and with the reminder mark while a card
/// waits for the user.
Widget _exitReminderFrame({required bool alert, bool selectExit = false}) =>
    Builder(
      builder: (context) {
        final t = LgTokens.of(context);
        final c = t.colors;
        Widget item(LgIcons icon, String label, {bool selected = false, Widget? mark}) =>
            Container(
              height: t.sizes.nav,
              padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
              decoration: BoxDecoration(
                color: selected ? c.nav : null,
                borderRadius: BorderRadius.circular(LgRadius.r12),
              ),
              child: Row(
                children: [
                  LgIcon(icon, size: 24, color: selected ? c.navFg : c.text),
                  const SizedBox(width: LgSpace.s3),
                  Expanded(
                    child: Text(
                      label,
                      style: t.text.copyWith(
                        color: selected ? c.navFg : c.text,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  ?mark,
                ],
              ),
            );
        return ColoredBox(
          color: c.bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Builder(
                builder: (context) => LgTitleBar(
                  labels: _labels,
                  sessions: _sessions(count: 2),
                  selected: 0,
                  homeBadge: 1,
                  homeAlert: alert,
                  homeSemanticLabel: alert ? '主页，1 个出口正在使用，需要处理' : '主页，1 个出口正在使用',
                  maximized: false,
                  onSelect: (_) {},
                  onCloseTab: (_) {},
                  onNewTab: _noop,
                  onMinimize: _noop,
                  onToggleMaximize: _noop,
                  onClose: _noop,
                  onStartDrag: _noop,
                  onStartResize: (_) {},
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(LgSpace.s2, LgSpace.s2, 0, 0),
                child: SizedBox(
                  width: 224,
                  child: Column(
                    children: [
                      item(LgIcons.monitor, '设备', selected: !selectExit),
                      const SizedBox(height: 2),
                      item(
                        LgIcons.exit,
                        '出口',
                        selected: selectExit,
                        // On the exit page itself the reminder is not drawn on the
                        // navigation (the card is in front of the eyes), the number is.
                        mark: LgCountMark(1, alert: alert && !selectExit),
                      ),
                      const SizedBox(height: 2),
                      item(LgIcons.gear, '设置'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
