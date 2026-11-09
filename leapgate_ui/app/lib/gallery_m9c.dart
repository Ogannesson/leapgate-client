// The M9c part of the component gallery: the tunnel cards' components next to the P8 mockups of
// A-P8-隧道.html. A part of gallery_main.dart, so that it shares its helpers (the exit cards'
// buttons and areas of gallery_m5.dart among them). Only the designer edits it (`LEAPGATE.md`
// §10.18).

part of 'gallery_main.dart';

const _tunId = '123 456 789';
const _rdpId = '234 567 891';

String _tunName(bool en) => _x(en, '书房台式机', 'Study desktop');
String _rdpName(bool en) => _x(en, '妈妈的笔记本', "Mom's laptop");

LgTunnelKindMark _tunKind(bool en) => LgTunnelKindMark(
  icon: LgIcons.forward,
  label: _x(en, 'TCP 隧道', 'TCP tunnel'),
);

LgTunnelKindMark _rdpKind(bool en) => LgTunnelKindMark(
  icon: LgIcons.rdp,
  label: _x(en, 'RDP · 端口 3389', 'RDP · port 3389'),
);

LgExitStatus _fwStatus(bool en, String kind) => switch (kind) {
  'direct' => LgExitStatus(
    LgExitStatusKind.direct,
    _x(en, '可用 · 直连', 'In use · Direct'),
  ),
  'relay' => LgExitStatus(
    LgExitStatusKind.relay,
    _x(en, '可用 · 经中继', 'In use · Via relay'),
  ),
  'connecting' => LgExitStatus(
    LgExitStatusKind.busy,
    _x(en, '正在连接…', 'Connecting…'),
  ),
  'interrupted' => LgExitStatus(
    LgExitStatusKind.warning,
    _x(en, '连接已中断', 'Connection lost'),
    reason: _x(
      en,
      '，下次有应用使用此端口时将自动重新连接',
      '. It reconnects when an application uses this port next.',
    ),
    note: _x(en, '远程设备不在线', 'The remote device is offline'),
  ),
  'port-in-use' => LgExitStatus(
    LgExitStatusKind.error,
    _x(
      en,
      '本机端口 8080 已被其他应用占用',
      'Local port 8080 is in use by another application',
    ),
  ),
  _ => LgExitStatus(
    LgExitStatusKind.error,
    _x(en, '已停止：', 'Stopped: '),
    reason: _x(
      en,
      '远程设备不允许建立 TCP 隧道',
      'The remote device does not allow TCP tunnels',
    ),
  ),
};

LgForwardAction _fwDelete(bool en, String port) => LgForwardAction(
  label: _x(en, '删除', 'Delete'),
  kind: LgForwardButtonKind.neutral,
  semanticLabel: _x(en, '删除端口转发 $port', 'Delete port forward $port'),
  onPressed: _noop,
);

LgForwardAction _fwRetry(bool en, String port, {bool reconnect = false}) =>
    LgForwardAction(
      label: reconnect ? _x(en, '重新连接', 'Reconnect') : _x(en, '重试', 'Retry'),
      semanticLabel: reconnect
          ? _x(en, '重新连接端口转发 $port', 'Reconnect port forward $port')
          : _x(en, '重试端口转发 $port', 'Retry port forward $port'),
      onPressed: _noop,
    );

LgForwardRow _fwRow(
  bool en,
  String port,
  String host,
  String targetPort,
  String kind, {
  List<LgForwardAction>? actions,
  bool copy = true,
  bool note = false,
}) => LgForwardRow(
  localHost: '127.0.0.1:',
  localPort: port,
  targetHost: '$host:',
  targetPort: targetPort,
  status: _fwStatus(en, kind),
  copyLabel: copy ? _x(en, '复制 127.0.0.1:$port', 'Copy 127.0.0.1:$port') : null,
  onCopy: copy ? _noop : null,
  actions: actions ?? [_fwDelete(en, port)],
  notice: note
      ? LgExitNotice(
          id: 'unreachable',
          text: _x(
            en,
            '无法访问 192.0.2.40:3306。请确认远程设备可以访问该地址，且端口已开放。',
            'Cannot reach 192.0.2.40:3306. Make sure the remote device can reach that address and the port is open.',
          ),
          dismissLabel: _x(en, '关闭', 'Close'),
          onDismiss: _noop,
        )
      : null,
);

/// The five rows of `p8-tcp-rows`: direct, lost, port taken, relayed with a note, connecting.
List<LgForwardRow> _fwFive(bool en) => [
  _fwRow(en, '2222', 'localhost', '22', 'direct'),
  _fwRow(
    en,
    '15432',
    '192.0.2.20',
    '5432',
    'interrupted',
    actions: [_fwRetry(en, '15432', reconnect: true), _fwDelete(en, '15432')],
  ),
  _fwRow(
    en,
    '8080',
    '192.0.2.30',
    '80',
    'port-in-use',
    copy: false,
    actions: [_fwRetry(en, '8080'), _fwDelete(en, '8080')],
  ),
  _fwRow(en, '13306', '192.0.2.40', '3306', 'relay', note: true),
  _fwRow(en, '18443', '192.0.2.50', '443', 'connecting'),
];

/// The three rows that wait while a question is open.
List<LgForwardRow> _fwWaiting(bool en, {bool firstDirect = false}) => [
  _fwRow(en, '2222', 'localhost', '22', firstDirect ? 'direct' : 'connecting'),
  _fwRow(en, '15432', '192.0.2.20', '5432', 'connecting'),
  _fwRow(en, '8080', '192.0.2.30', '80', 'connecting'),
];

LgForwardList _fwList(bool en, List<LgForwardRow> rows) => LgForwardList(
  localLabel: _x(en, '本机', 'Local'),
  targetLabel: _x(en, '目标', 'Target'),
  semanticLabel: _x(en, '端口转发', 'Port forwards'),
  rows: rows,
);

LgForwardAddRow _fwAdd(
  bool en, {
  String local = '',
  String host = '',
  String remote = '',
  bool enabled = false,
  String? error,
  LgForwardField field = LgForwardField.local,
}) => LgForwardAddRow(
  localHost: '127.0.0.1:',
  localController: TextEditingController(text: local),
  localLabel: _x(en, '本机端口', 'Local port'),
  localPlaceholder: _x(en, '本机端口', 'Local port'),
  hostController: TextEditingController(text: host),
  hostLabel: _x(en, '目标主机', 'Target host'),
  hostPlaceholder: 'localhost',
  remoteController: TextEditingController(text: remote),
  remoteLabel: _x(en, '远程端口', 'Remote port'),
  remotePlaceholder: _x(en, '远程端口', 'Remote port'),
  addLabel: _x(en, '添加', 'Add'),
  cancelLabel: _x(en, '取消', 'Cancel'),
  onAdd: enabled ? _noop : null,
  onCancel: _noop,
  errorText: error,
  errorField: field,
  semanticLabel: _x(en, '添加端口转发', 'Add a port forward'),
);

LgExitAction _tunAddForward(bool en) => LgExitAction(
  label: _x(en, '添加端口转发', 'Add a port forward'),
  icon: LgIcons.plus,
  onPressed: _noop,
);

LgExitAction _tunStop(bool en, {bool rdp = false}) => LgExitAction(
  label: _x(en, '停止', 'Stop'),
  icon: LgIcons.square,
  kind: LgButtonKind.secondary,
  semanticLabel: _x(
    en,
    '停止 ${rdp ? _rdpName(en) : _tunName(en)} 的 ${rdp ? 'RDP' : 'TCP 隧道'}',
    'Stop the ${rdp ? 'RDP connection' : 'TCP tunnel'} of ${rdp ? _rdpName(en) : _tunName(en)}',
  ),
  onPressed: _noop,
);

LgTunnelCard _tunnelCard(
  bool en, {
  LgTunnelQuestion? question,
  LgExitStatus? status,
  List<LgForwardRow>? rows,
  String? empty,
  LgForwardAddRow? addRow,
  List<LgExitAction> leading = const [],
  List<LgExitAction> actions = const [],
  String? name,
  String? id,
  LgPlatform platform = LgPlatform.windows,
}) => LgTunnelCard(
  name: name ?? _tunName(en),
  id: id ?? _tunId,
  platform: platform,
  kindMark: _tunKind(en),
  semanticLabel: '${name ?? _tunName(en)} · ${_x(en, 'TCP 隧道', 'TCP tunnel')}',
  question: question,
  status: status,
  forwards: rows == null ? null : _fwList(en, rows),
  emptyText: empty,
  addRow: addRow,
  leadingActions: leading,
  actions: actions,
);

LgTunnelCard _rdpCard(bool en, String state) {
  LgExitAction newRdp() => LgExitAction(
    label: _x(en, '新建 RDP 连接', 'New RDP connection'),
    icon: LgIcons.rdp,
    onPressed: _noop,
  );
  LgExitAction settings() => LgExitAction(
    label: _x(en, 'RDP 设置', 'RDP settings'),
    icon: LgIcons.gear,
    onPressed: _noop,
  );
  LgTunnelCard card({
    required LgExitStatus status,
    List<LgExitNotice> notices = const [],
    List<LgExitAction> leading = const [],
    List<LgExitAction> actions = const [],
  }) => LgTunnelCard(
    name: _rdpName(en),
    id: _rdpId,
    platform: LgPlatform.windows,
    kindMark: _rdpKind(en),
    semanticLabel: '${_rdpName(en)} · RDP',
    status: status,
    notices: notices,
    leadingActions: leading,
    actions: actions,
  );
  final relayNote = _x(
    en,
    '流量由中继服务器转发，速度可能较慢',
    'Traffic is forwarded by the relay server and may be slower',
  );
  switch (state) {
    case 'connecting':
      return card(
        status: LgExitStatus(
          LgExitStatusKind.busy,
          _x(en, '正在连接 ${_rdpName(en)}…', 'Connecting to ${_rdpName(en)}…'),
        ),
        actions: [_exitCancel(en)],
      );
    case 'drop':
      return card(
        status: LgExitStatus(
          LgExitStatusKind.warning,
          _x(en, '连接已中断', 'Connection lost'),
          reason: _x(
            en,
            '，新建 RDP 连接时将自动重新连接',
            '. It reconnects when a new RDP connection is made.',
          ),
        ),
        leading: [newRdp(), settings()],
        actions: [_tunStop(en, rdp: true)],
      );
    case 'old':
      return card(
        status: LgExitStatus(
          LgExitStatusKind.error,
          _x(en, '已停止：', 'Stopped: '),
          reason: _x(
            en,
            '远程设备的版本过低，不支持端口转发',
            'The remote device is too old to support port forwarding',
          ),
        ),
        leading: [settings()],
        actions: [_exitRemove(en)],
      );
    case 'note':
      return card(
        status: LgExitStatus(
          LgExitStatusKind.relay,
          _x(en, '可用 · 经中继', 'In use · Via relay'),
          note: relayNote,
        ),
        notices: [
          LgExitNotice(
            id: 'rdp',
            text: _x(
              en,
              '无法访问远程设备的 RDP 服务。请确认远程设备已开启远程桌面。',
              'Cannot reach the remote device\'s RDP service. Make sure Remote Desktop is turned on there.',
            ),
            dismissLabel: _x(en, '关闭', 'Close'),
            onDismiss: _noop,
          ),
        ],
        leading: [newRdp(), settings()],
        actions: [_tunStop(en, rdp: true)],
      );
    default:
      return card(
        status: LgExitStatus(
          LgExitStatusKind.relay,
          _x(en, '可用 · 经中继', 'In use · Via relay'),
          note: relayNote,
        ),
        leading: [newRdp(), settings()],
        actions: [_tunStop(en, rdp: true)],
      );
  }
}

LgTunnelQuestion _askPassword(bool en, {String? error}) =>
    LgTunnelQuestion.password(
      title: _x(en, '输入密码', 'Enter password'),
      password: _exitPassword(en, error: error),
      confirm: _exitConnect(en),
      cancel: _exitCancel(en),
    );

LgTunnelQuestion _askCode(bool en) => LgTunnelQuestion.code(
  title: _x(en, '输入验证码', 'Enter verification code'),
  code: _exitCode(en),
  confirm: LgExitAction(
    label: _x(en, '验证', 'Verify'),
    kind: LgButtonKind.primary,
    onPressed: null,
  ),
  cancel: _exitCancel(en),
);

LgTunnelQuestion _askBusy(bool en, {String? elapsed}) => LgTunnelQuestion.busy(
  text: elapsed == null
      ? _x(en, '正在验证…', 'Verifying…')
      : _x(en, '正在等待对方接受…', 'Waiting for the other side to accept…'),
  elapsed: elapsed,
  cancel: _exitCancel(en),
);

LgTunnelQuestion _askInsecure(bool en) => LgTunnelQuestion.insecure(
  title: _x(en, '未加密', 'Not encrypted'),
  message: _x(
    en,
    '此连接未使用端到端加密，传输的内容可能被第三方读取。',
    'This connection is not end-to-end encrypted. What is sent may be read by a third party.',
  ),
  confirm: LgExitAction(
    label: _x(en, '断开', 'Disconnect'),
    kind: LgButtonKind.primary,
    autofocus: true,
    onPressed: _noop,
  ),
  cancel: LgExitAction(
    label: _x(en, '继续', 'Continue'),
    kind: LgButtonKind.secondary,
    onPressed: _noop,
  ),
);

LgRdpSettingsDialog _rdpDialog(
  bool en, {
  String? portError,
  String port = '',
  bool running = false,
}) => LgRdpSettingsDialog(
  title: _x(en, 'RDP 设置', 'RDP settings'),
  deviceName: _rdpName(en),
  deviceId: _rdpId,
  portLabel: _x(en, '端口', 'Port'),
  portController: TextEditingController(text: port),
  portPlaceholder: '3389',
  portError: portError,
  usernameLabel: _x(en, '用户名', 'User name'),
  usernameController: TextEditingController(text: 'mama'),
  passwordLabel: _x(en, '密码', 'Password'),
  passwordController: TextEditingController(text: '12345678'),
  showPasswordLabel: _x(en, '显示密码', 'Show password'),
  hidePasswordLabel: _x(en, '隐藏密码', 'Hide password'),
  runningNote: running
      ? _x(
          en,
          '停止后重新打开 RDP，新的设置才会生效。',
          'Stop and open RDP again for the new settings to take effect.',
        )
      : null,
  cancelLabel: _x(en, '取消', 'Cancel'),
  confirmLabel: _x(en, '确定', 'OK'),
  onCancel: _noop,
  onConfirm: _noop,
);

List<Specimen> _m9cSpecimens() {
  final list = <Specimen>[];

  // A card is 1008 wide in a 1280 window; the specimen's 16 px frame makes it 1040 (720 for the
  // 960 window, whose card is 688).
  void card(
    String section,
    String name,
    double height,
    Widget Function(bool en) build, {
    double width = 1040,
    bool english = false,
  }) {
    list.add(
      Specimen(
        section,
        name,
        Size(width, height),
        (_) => SizedBox(width: width - 32, child: build(false)),
      ),
    );
    if (english) {
      list.add(
        Specimen(
          section,
          '$name-english',
          Size(width, height),
          (_) => SizedBox(width: width - 32, child: build(true)),
        ),
      );
    }
  }

  // ---- the table of forwards (p8-tcp-*) -----------------------------------------------------
  card(
    'tunnel-card',
    'rows',
    560,
    (en) => _tunnelCard(
      en,
      rows: _fwFive(en),
      leading: [_tunAddForward(en)],
      actions: [_tunStop(en)],
    ),
    english: true,
  );
  card(
    'tunnel-card',
    'rows-narrow',
    660,
    (en) => _tunnelCard(
      en,
      rows: _fwFive(en),
      leading: [_tunAddForward(en)],
      actions: [_tunStop(en)],
    ),
    width: 720,
  );
  card(
    'tunnel-card',
    'new',
    290,
    (en) => _tunnelCard(
      en,
      empty: _x(en, '暂无端口转发', 'No port forwards'),
      addRow: _fwAdd(en),
      actions: [_exitRemove(en)],
    ),
  );
  card(
    'tunnel-card',
    'add-ready',
    380,
    (en) => _tunnelCard(
      en,
      rows: [_fwRow(en, '2222', 'localhost', '22', 'direct')],
      addRow: _fwAdd(
        en,
        local: '15432',
        host: '192.0.2.20',
        remote: '5432',
        enabled: true,
      ),
      actions: [_tunStop(en)],
    ),
  );
  card(
    'tunnel-card',
    'add-err-port',
    380,
    (en) => _tunnelCard(
      en,
      rows: [_fwRow(en, '2222', 'localhost', '22', 'direct')],
      addRow: _fwAdd(
        en,
        local: '70000',
        host: 'localhost',
        remote: '22',
        error: _x(
          en,
          '端口无效。端口应为 1~65535。',
          'Invalid port. Use a number from 1 to 65535.',
        ),
      ),
      actions: [_tunStop(en)],
    ),
  );
  card(
    'tunnel-card',
    'add-err-dup',
    380,
    (en) => _tunnelCard(
      en,
      rows: [_fwRow(en, '2222', 'localhost', '22', 'direct')],
      addRow: _fwAdd(
        en,
        local: '2222',
        host: 'localhost',
        remote: '22',
        error: _x(en, '此端口已有一条端口转发', 'This port already has a port forward'),
      ),
      actions: [_tunStop(en)],
    ),
  );
  card(
    'tunnel-card',
    'add-err-used',
    380,
    (en) => _tunnelCard(
      en,
      rows: [_fwRow(en, '2222', 'localhost', '22', 'direct')],
      addRow: _fwAdd(
        en,
        local: '3000',
        host: 'localhost',
        remote: '22',
        error: _x(
          en,
          '此端口已被另一个出口或隧道使用',
          'This port is used by another exit or tunnel',
        ),
      ),
      actions: [_tunStop(en)],
    ),
  );
  card(
    'tunnel-card',
    'add-narrow',
    440,
    (en) => _tunnelCard(
      en,
      rows: [_fwRow(en, '2222', 'localhost', '22', 'direct')],
      addRow: _fwAdd(
        en,
        local: '70000',
        host: 'localhost',
        remote: '22',
        error: _x(
          en,
          '端口无效。端口应为 1~65535。',
          'Invalid port. Use a number from 1 to 65535.',
        ),
      ),
      actions: [_tunStop(en)],
    ),
    width: 720,
  );
  card(
    'tunnel-card',
    'stopped',
    270,
    (en) => _tunnelCard(
      en,
      name: _x(en, '客厅迷你主机', 'Living room mini PC'),
      id: '456 789 123',
      platform: LgPlatform.linux,
      rows: [
        LgForwardRow(
          localHost: '127.0.0.1:',
          localPort: '19000',
          targetHost: 'localhost:',
          targetPort: '9000',
          status: _fwStatus(en, 'stopped'),
          copyLabel: _x(en, '复制 127.0.0.1:19000', 'Copy 127.0.0.1:19000'),
          onCopy: _noop,
          actions: [_fwRetry(en, '19000'), _fwDelete(en, '19000')],
        ),
      ],
      leading: [_tunAddForward(en)],
      actions: [_exitRemove(en)],
    ),
  );
  card(
    'tunnel-card',
    'conflict',
    210,
    (en) => _tunnelCard(
      en,
      name: _x(en, '李四的台式机', "Li Si's desktop"),
      id: '912 345 678',
      status: LgExitStatus(
        LgExitStatusKind.error,
        _x(en, '已停止：', 'Stopped: '),
        reason: _x(
          en,
          '本机已有连接此设备的出口',
          'This computer already uses this device as an exit',
        ),
      ),
      actions: [_exitRetry(en), _exitRemove(en)],
    ),
  );
  list.add(
    Specimen(
      'tunnel-card',
      'flash',
      const Size(1040, 260),
      (_) => SizedBox(
        width: 1008,
        child: LgFlash(
          showing: true,
          child: _tunnelCard(
            false,
            rows: [_fwRow(false, '2222', 'localhost', '22', 'direct')],
            leading: [_tunAddForward(false)],
            actions: [_tunStop(false)],
          ),
        ),
      ),
    ),
  );

  // ---- the question area (p8-q-*) -----------------------------------------------------------
  card(
    'tunnel-question',
    'password',
    590,
    (en) => _tunnelCard(
      en,
      question: _askPassword(en),
      rows: _fwWaiting(en),
      leading: [_tunAddForward(en)],
      actions: [_tunStop(en)],
    ),
    english: true,
  );
  card(
    'tunnel-question',
    'password-wrong',
    630,
    (en) => _tunnelCard(
      en,
      question: _askPassword(en, error: _x(en, '密码错误', 'Wrong password')),
      rows: _fwWaiting(en),
      leading: [_tunAddForward(en)],
      actions: [_tunStop(en)],
    ),
  );
  card(
    'tunnel-question',
    'code',
    590,
    (en) => _tunnelCard(
      en,
      question: _askCode(en),
      rows: _fwWaiting(en),
      leading: [_tunAddForward(en)],
      actions: [_tunStop(en)],
    ),
  );
  card(
    'tunnel-question',
    'verifying',
    450,
    (en) => _tunnelCard(
      en,
      question: _askBusy(en),
      rows: _fwWaiting(en),
      leading: [_tunAddForward(en)],
      actions: [_tunStop(en)],
    ),
  );
  card(
    'tunnel-question',
    'waiting',
    450,
    (en) => _tunnelCard(
      en,
      question: _askBusy(en, elapsed: _x(en, '（已等待 0:12）', ' (0:12 so far)')),
      rows: _fwWaiting(en, firstDirect: true),
      leading: [_tunAddForward(en)],
      actions: [_tunStop(en)],
    ),
  );
  card(
    'tunnel-question',
    'insecure',
    510,
    (en) => _tunnelCard(
      en,
      question: _askInsecure(en),
      rows: _fwWaiting(en),
      leading: [_tunAddForward(en)],
      actions: [_tunStop(en)],
    ),
    english: true,
  );
  card(
    'tunnel-question',
    'password-narrow',
    700,
    (en) => _tunnelCard(
      en,
      question: _askPassword(en),
      rows: _fwWaiting(en),
      leading: [_tunAddForward(en)],
      actions: [_tunStop(en)],
    ),
    width: 560,
  );

  // ---- the RDP card (p8-rdp-*) --------------------------------------------------------------
  for (final state in ['connecting', 'relay', 'drop', 'old', 'note']) {
    card(
      'rdp-card',
      state,
      state == 'note' ? 280 : 220,
      (en) => _rdpCard(en, state),
      english: state == 'relay',
    );
  }
  card('rdp-card', 'narrow', 220, (en) => _rdpCard(en, 'relay'), width: 720);

  // ---- the RDP settings dialog (p8-dlg-rdp*) ------------------------------------------------
  for (final (name, builder) in <(String, LgRdpSettingsDialog Function(bool))>[
    ('plain', (en) => _rdpDialog(en)),
    (
      'port-invalid',
      (en) => _rdpDialog(
        en,
        port: '70000',
        portError: _x(
          en,
          '端口无效。端口应为 1~65535。',
          'Invalid port. Use a number from 1 to 65535.',
        ),
      ),
    ),
    ('running', (en) => _rdpDialog(en, running: true)),
    ('english', (en) => _rdpDialog(true)),
  ]) {
    list.add(
      Specimen(
        'rdp-dialog',
        name,
        const Size(560, 640),
        padding: 0,
        (_) => _m9aStage(builder(false), height: 640),
      ),
    );
  }

  // ---- the page with three levels of headings (p8-full-light, p8-empty-light) -----------------
  Widget page(
    BuildContext context,
    bool en, {
    required bool none,
    required double height,
  }) {
    final t = LgTokens.of(context);
    return SizedBox(
      width: 1040,
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LgSpace.s2,
          LgSpace.s4,
          LgSpace.s6,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _x(en, '出口与隧道', 'Exits & tunnels'),
              style: LgTokens.style(
                20,
                28,
                FontWeight.w700,
              ).copyWith(color: t.colors.text),
            ),
            const SizedBox(height: LgSpace.s1),
            Expanded(
              child: LgExitPage(
                sectionIcon: LgIcons.exit,
                sectionTitle: _x(en, '出口', 'Exit nodes'),
                lede: _x(
                  en,
                  '通过其他设备的网络访问互联网。仅对已配置代理的应用生效，且只支持 TCP 连接。',
                  "Reach the internet through another device's network. Only applications set to use the proxy are affected, and only TCP connections are supported.",
                ),
                inUseTitle: _x(en, '正在使用', 'In use'),
                inUse: none
                    ? LgExitEmptyNote(
                        _x(en, '暂无正在使用的出口', 'No exit nodes in use'),
                      )
                    : LgExitCardGrid(
                        semanticLabel: _x(en, '正在使用的出口', 'Exit nodes in use'),
                        children: [_exitCard('relay', en: en)],
                      ),
                directoryTitle: _x(en, '可用的出口', 'Available exit nodes'),
                refreshLabel: _x(en, '刷新', 'Refresh'),
                onRefresh: _noop,
                directory: LgExitDirectory.rows(
                  entries: _exitEntries(en, inUse: !none),
                ),
                byIdTitle: _x(en, '按 ID 指定出口', 'Use an exit node by ID'),
                byId: _exitById(en),
                tunnels: LgPageSection(
                  icon: LgIcons.forward,
                  title: _x(en, '隧道', 'Tunnels'),
                  lede: _x(
                    en,
                    '将本机端口转发到远程设备或其所在网络中的地址。',
                    'Forward ports of this computer to the remote device or to an address on its network.',
                  ),
                  children: [
                    LgTunnelStack(
                      emptyText: _x(en, '暂无正在使用的隧道', 'No tunnels in use'),
                      semanticLabel: _x(en, '正在使用的隧道', 'Tunnels in use'),
                      children: none
                          ? const []
                          : [
                              _tunnelCard(
                                en,
                                rows: _fwFive(en),
                                leading: [_tunAddForward(en)],
                                actions: [_tunStop(en)],
                              ),
                              _rdpCard(en, 'relay'),
                            ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  list
    ..add(
      Specimen(
        'tunnel-page',
        'full',
        const Size(1040, 1560),
        padding: 0,
        (context) => page(context, false, none: false, height: 1560),
      ),
    )
    ..add(
      Specimen(
        'tunnel-page',
        'empty',
        const Size(1040, 780),
        padding: 0,
        (context) => page(context, false, none: true, height: 780),
      ),
    )
    ..add(
      Specimen(
        'tunnel-page',
        'full-english',
        const Size(1040, 1560),
        padding: 0,
        (context) => page(context, true, none: false, height: 1560),
      ),
    );

  // ---- the parts on their own ----------------------------------------------------------------
  list
    ..add(
      Specimen(
        'tunnel-parts',
        'kind-marks',
        const Size(420, 160),
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tunKind(false),
            const SizedBox(height: LgSpace.s3),
            _rdpKind(false),
            const SizedBox(height: LgSpace.s3),
            _rdpKind(true),
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'tunnel-parts',
        'section-heads',
        const Size(720, 330),
        (_) => const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LgPageSection(
              first: true,
              icon: LgIcons.exit,
              title: '出口',
              lede: '通过其他设备的网络访问互联网。仅对已配置代理的应用生效，且只支持 TCP 连接。',
              children: [
                LgExitSection(title: '正在使用', level: LgExitSectionLevel.sub),
              ],
            ),
            LgPageSection(
              icon: LgIcons.forward,
              title: '隧道',
              lede: '将本机端口转发到远程设备或其所在网络中的地址。',
            ),
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'tunnel-parts',
        'forward-buttons',
        const Size(520, 110),
        (_) => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LgForwardButton(label: '重新连接', onPressed: _noop),
                SizedBox(width: 2),
                LgForwardButton(
                  label: '删除',
                  kind: LgForwardButtonKind.neutral,
                  onPressed: _noop,
                ),
                SizedBox(width: 2),
                LgForwardButton(
                  label: '添加',
                  kind: LgForwardButtonKind.primary,
                  onPressed: _noop,
                ),
              ],
            ),
            SizedBox(height: LgSpace.s3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LgForwardButton(label: '重新连接', onPressed: null),
                SizedBox(width: 2),
                LgForwardButton(
                  label: '删除',
                  kind: LgForwardButtonKind.neutral,
                  onPressed: null,
                ),
                SizedBox(width: 2),
                LgForwardButton(
                  label: '添加',
                  kind: LgForwardButtonKind.primary,
                  onPressed: null,
                ),
              ],
            ),
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'tunnel-parts',
        'forward-buttons-hover',
        const Size(520, 70),
        states: _hover,
        (_) => const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LgForwardButton(label: '重新连接', onPressed: _noop),
            SizedBox(width: 2),
            LgForwardButton(
              label: '删除',
              kind: LgForwardButtonKind.neutral,
              onPressed: _noop,
            ),
            SizedBox(width: 2),
            LgForwardButton(
              label: '添加',
              kind: LgForwardButtonKind.primary,
              onPressed: _noop,
            ),
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'tunnel-parts',
        'forward-buttons-focus',
        const Size(520, 70),
        states: _focus,
        (_) => const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LgForwardButton(label: '重新连接', onPressed: _noop),
            SizedBox(width: 6),
            LgForwardButton(
              label: '删除',
              kind: LgForwardButtonKind.neutral,
              onPressed: _noop,
            ),
            SizedBox(width: 6),
            LgForwardButton(
              label: '添加',
              kind: LgForwardButtonKind.primary,
              onPressed: _noop,
            ),
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'tunnel-parts',
        'forward-status',
        const Size(420, 330),
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final kind in [
              'direct',
              'relay',
              'connecting',
              'interrupted',
              'port-in-use',
              'stopped',
            ]) ...[
              SizedBox(
                width: 280,
                child: LgForwardStatusText(_fwStatus(false, kind)),
              ),
              const SizedBox(height: LgSpace.s3),
            ],
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'tunnel-parts',
        'stack-empty',
        const Size(1040, 130),
        (_) => const SizedBox(
          width: 1008,
          child: LgTunnelStack(emptyText: '暂无正在使用的隧道', children: []),
        ),
      ),
    );

  // ---- the edit button in a menu row (the "RDP" row of a device menu) ---------------------------
  List<Widget> rdpMenu({bool en = false, bool off = false}) => [
    LgMenuItem(
      label: _x(en, '远程桌面', 'Remote desktop'),
      icon: LgIcons.monitor,
      onPressed: _noop,
    ),
    LgMenuItem(
      label: 'RDP',
      icon: LgIcons.rdp,
      onPressed: off ? null : _noop,
      trailing: LgMenuRowButton(
        label: _x(en, '编辑 RDP 设置', 'Edit RDP settings'),
        onPressed: off ? null : _noop,
      ),
    ),
    LgMenuItem(
      label: _x(en, '用作出口', 'Use as exit node'),
      icon: LgIcons.exit,
      onPressed: _noop,
    ),
  ];
  list
    ..add(
      Specimen(
        'menu-row-button',
        'normal',
        const Size(340, 190),
        (_) => LgMenuPanel(width: 308, items: rdpMenu()),
      ),
    )
    ..add(
      Specimen(
        'menu-row-button',
        'hover',
        const Size(340, 190),
        states: _hover,
        (_) => LgMenuPanel(width: 308, items: rdpMenu()),
      ),
    )
    ..add(
      Specimen(
        'menu-row-button',
        'focus',
        const Size(340, 190),
        states: _focus,
        (_) => LgMenuPanel(width: 308, items: rdpMenu()),
      ),
    )
    ..add(
      Specimen(
        'menu-row-button',
        'greyed',
        const Size(340, 190),
        (_) => LgMenuPanel(width: 308, items: rdpMenu(off: true)),
      ),
    )
    ..add(
      Specimen(
        'menu-row-button',
        'english',
        const Size(340, 190),
        (_) => LgMenuPanel(width: 308, items: rdpMenu(en: true)),
      ),
    );

  return list;
}
