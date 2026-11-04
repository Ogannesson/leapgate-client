// The M6 part of the component gallery: the frame of the settings page (the
// navigation, the content, the lock bar), the rows and what they hold, the
// search box and its results, the trusted devices, the shortcut list and its
// recording dialog, the QR code, and the dialogs that use the new footer and
// QR parts, next to the P6 mockups of A-P6-设置.html and A-P6-设置-对话框.html
// (`p6-*`). A part of gallery_main.dart, so that it shares its helpers.
//
// Sample data is the 02 §5.3 data: ID 135 792 468, 张三, leapgate.example.com,
// the documentation address ranges.

part of 'gallery_main.dart';

// ---- sections of the navigation ----------------------------------------------

typedef _M6Section = ({String zh, String en});

const _m6Incoming = <_M6Section>[
  (zh: '访问与密码', en: 'Access and passwords'),
  (zh: '权限', en: 'Permissions'),
  (zh: '二次验证', en: 'Two-factor authentication'),
  (zh: '访问限制', en: 'Access restrictions'),
  (zh: '会话', en: 'Sessions'),
  (zh: '出口', en: 'Exit node'),
  (zh: '远程打印', en: 'Remote printing'),
  (zh: '服务与 ID', en: 'Service and ID'),
];

const _m6Outgoing = <_M6Section>[
  (zh: '连接方式', en: 'Connection methods'),
  (zh: '新设备的默认设置', en: 'Defaults for new devices'),
  (zh: '会话期间', en: 'During sessions'),
  (zh: '工具栏与显示器', en: 'Toolbar and monitors'),
  (zh: '渲染', en: 'Rendering'),
  (zh: '快捷键', en: 'Keyboard shortcuts'),
  (zh: '收到的打印任务', en: 'Incoming print jobs'),
];

const _m6General = <_M6Section>[
  (zh: '外观', en: 'Appearance'),
  (zh: '网络和服务器', en: 'Network and server'),
  (zh: '账号', en: 'Account'),
  (zh: '其他', en: 'Other'),
  (zh: '关于', en: 'About'),
];

Widget _m6Nav({
  bool en = false,
  int selected = 0,
  bool locked = false,
  String query = '',
  FocusNode? searchFocus,
}) {
  Widget group(
    String title,
    List<_M6Section> items,
    int offset,
    bool lockAll,
  ) => LgSettingsNavGroup(
    title: title,
    items: [
      for (final (i, s) in items.indexed)
        LgSettingsNavItem(
          label: en ? s.en : s.zh,
          selected: offset + i == selected,
          locked: locked && (lockAll || s.zh == '网络和服务器'),
          lockedLabel: _x(en, '已锁定', 'Locked'),
          onPressed: _noop,
        ),
    ],
  );
  return LgSettingsNav(
    semanticLabel: _x(en, '设置分区', 'Settings sections'),
    search: LgSettingsSearchField(
      controller: TextEditingController(text: query),
      focusNode: searchFocus,
      placeholder: _x(en, '搜索设置', 'Search settings'),
      clearLabel: _x(en, '清除搜索', 'Clear search'),
    ),
    children: [
      group(_x(en, '传入连接', 'Incoming connections'), _m6Incoming, 0, true),
      group(
        _x(en, '传出连接', 'Outgoing connections'),
        _m6Outgoing,
        _m6Incoming.length,
        false,
      ),
      group(
        _x(en, '通用', 'General'),
        _m6General,
        _m6Incoming.length + _m6Outgoing.length,
        false,
      ),
    ],
  );
}

// ---- rows ---------------------------------------------------------------------

Widget _m6Radios(bool en, List<String> labels, int on) => LgSettingsOptions(
  children: [
    for (final (i, l) in labels.indexed)
      LgRadio<int>(value: i, groupValue: on, onChanged: (_) {}, label: l),
  ],
);

LgSettingsRow _m6Approve(bool en, {int on = 2, bool marked = false}) =>
    LgSettingsRow(
      name: _x(en, '审批方式', 'Approval method'),
      description: _x(en, '仅对之后的连接生效', 'Applies to later connections only'),
      marked: marked,
      body: _m6Radios(en, [
        _x(en, '输入密码', 'Enter password'),
        _x(en, '在本机接受', 'Accept on this device'),
        _x(en, '输入密码或在本机接受', 'Enter password or accept on this device'),
      ], on),
    );

LgSettingsRow _m6PasswordMode(bool en, {int on = 2, String? error}) =>
    LgSettingsRow(
      name: _x(en, '密码方式', 'Password method'),
      error: error,
      body: _m6Radios(en, [
        _x(en, '仅一次性密码', 'One-time password only'),
        _x(en, '仅固定密码', 'Fixed password only'),
        _x(en, '一次性密码或固定密码', 'One-time or fixed password'),
      ], on),
    );

LgSettingsRow _m6Length(bool en) => LgSettingsRow(
  name: _x(en, '长度', 'Length'),
  wide: true,
  control: LgSegmented<int>(
    segments: const [LgSegment(6, '6'), LgSegment(8, '8'), LgSegment(10, '10')],
    selected: 6,
    onChanged: (_) {},
  ),
);

List<Widget> _m6AccessChildren(bool en) => [
  LgSettingsBlock(children: [_m6Approve(en)]),
  LgSettingsBlock(children: [_m6PasswordMode(en)]),
  LgSettingsSubtitle(_x(en, '一次性密码', 'One-time password')),
  LgSettingsBlock(
    children: [
      _m6Length(en),
      LgSettingsRow.toggle(
        name: _x(en, '仅使用数字', 'Digits only'),
        value: false,
        onChanged: (_) {},
      ),
    ],
  ),
  LgSettingsBlock(
    gap: true,
    children: [
      LgSettingsRow(
        name: _x(en, '固定密码', 'Fixed password'),
        control: LgSettingsValueActions(
          value: _x(en, '未设置', 'Not set'),
          actions: [
            LgSettingsAction(
              label: _x(en, '设置固定密码', 'Set fixed password'),
              onPressed: _noop,
            ),
          ],
        ),
      ),
    ],
  ),
];

Widget _m6Content({
  required String title,
  required List<Widget> children,
  double width = 680,
  double height = 520,
  String? lede,
  Widget? lockBar,
  bool locked = false,
}) => SizedBox(
  width: width,
  height: height,
  child: LgSettingsContent(
    title: title,
    lede: lede,
    lockBar: lockBar,
    locked: locked,
    children: children,
  ),
);

Widget _m6LockBar(
  bool en, {
  String? error,
  bool busy = false,
}) => LgSettingsLockBar(
  text: _x(
    en,
    '已锁定。修改这些设置需要管理员权限。',
    'Locked. Administrator permission is required to change these settings.',
  ),
  unlockLabel: _x(en, '解锁', 'Unlock'),
  error: error,
  busy: busy,
  onUnlock: _noop,
);

/// The navigation next to the content, 8 from the left edge, as in the window.
Widget _m6Frame({
  required Widget nav,
  required Widget content,
  double width = 1040,
  double height = 660,
}) => SizedBox(
  width: width,
  height: height,
  child: LgSettingsLayout(navigation: nav, content: content),
);

LgSettingsStatusRow _m6Status(
  bool en,
  LgTone tone,
  String zh,
  String english, {
  String? zhNote,
  String? enNote,
  bool button = false,
}) => LgSettingsStatusRow(
  tone: tone,
  text: _x(en, zh, english),
  description: zhNote == null ? null : _x(en, zhNote, enNote ?? zhNote),
  toneLabel: switch (tone) {
    LgTone.success => _x(en, '已满足', 'Met'),
    LgTone.warning => _x(en, '需要注意', 'Needs attention'),
    _ => null,
  },
  actions: [
    if (button)
      LgSettingsAction(
        label: _x(en, tone == LgTone.warning ? '设置' : '编辑', 'Edit'),
        onPressed: _noop,
      ),
  ],
);

// ---- trusted devices, shortcuts ----------------------------------------------

List<LgTrustedDevice> _m6Trusted(bool en) => [
  LgTrustedDevice(
    id: '912345678',
    name: _x(en, '李四的台式机', "Li Si's desktop"),
    formattedId: '912 345 678',
    platform: LgPlatform.windows,
    remaining: _x(en, '剩余 23 天', '23 days left'),
  ),
  LgTrustedDevice(
    id: '147258369',
    name: _x(en, '王五的笔记本', "Wang Wu's laptop"),
    formattedId: '147 258 369',
    platform: LgPlatform.windows,
    remaining: _x(en, '剩余 81 天', '81 days left'),
  ),
  LgTrustedDevice(
    id: '678912345',
    name: _x(en, '备用手机', 'Spare phone'),
    formattedId: '678 912 345',
    platform: LgPlatform.android,
    remaining: _x(en, '今天到期', 'Expires today'),
  ),
];

Widget _m6TrustedList(
  bool en, {
  List<LgTrustedDevice>? devices,
  Set<String> picked = const {},
}) => LgTrustedDevices(
  title: _x(en, '受信设备', 'Trusted devices'),
  devices: devices ?? _m6Trusted(en),
  picked: picked,
  onToggle: (_) {},
  deleteAllLabel: _x(en, '全部删除', 'Delete all'),
  onDeleteAll: _noop,
  emptyText: _x(en, '暂无受信设备', 'No trusted devices'),
  pickedCountLabel: _x(
    en,
    '已选择 ${picked.length} 台',
    '${picked.length} selected',
  ),
  deleteLabel: _x(en, '删除', 'Delete'),
  onDeleteSelected: _noop,
);

LgShortcutRow _m6Shortcut(
  bool en,
  String zh,
  String english,
  List<String> keys,
) => LgShortcutRow(
  action: _x(en, zh, english),
  keys: keys,
  unsetLabel: _x(en, '未设置', 'Not set'),
  editLabel: _x(en, '修改', 'Edit'),
  onEdit: _noop,
  clearLabel: _x(en, '清除', 'Clear'),
  onClear: _noop,
  editSemanticLabel: _x(en, '修改快捷键：$zh', 'Edit shortcut: $english'),
);

Widget _m6ShortcutGroups(bool en, {bool disabled = false}) {
  const mod = ['Ctrl', 'Alt', 'Shift'];
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LgShortcutGroup(
        title: _x(en, '显示器', 'Displays'),
        disabled: disabled,
        rows: [
          _m6Shortcut(en, '下一个显示器', 'Next display', [...mod, '→']),
          _m6Shortcut(en, '上一个显示器', 'Previous display', [...mod, '←']),
          _m6Shortcut(en, '全部显示器', 'All displays', const []),
        ],
      ),
      const SizedBox(height: LgSpace.s5),
      LgShortcutGroup(
        title: _x(en, '画面', 'Screen'),
        disabled: disabled,
        rows: [
          _m6Shortcut(en, '原始大小', 'Original size', const []),
          _m6Shortcut(en, '适应窗口', 'Fit window', const []),
          _m6Shortcut(en, '刷新画面', 'Refresh screen', [...mod, 'R']),
        ],
      ),
    ],
  );
}

Widget _m6RecordDialog(
  bool en,
  LgShortcutRecordState state,
  List<String> keys, {
  String? status,
  String confirm = '保存',
  String confirmEn = 'Save',
}) => LgShortcutRecordDialog(
  title: _x(en, '设置快捷键：刷新画面', 'Set shortcut: Refresh screen'),
  state: state,
  keys: keys,
  statusText: status,
  cancelLabel: _x(en, '取消', 'Cancel'),
  confirmLabel: _x(en, confirm, confirmEn),
  onCancel: _noop,
  onConfirm: _noop,
);

/// A dialog over a dimmed ground, like the mockups' dialog frames.
Widget _m6Stage(Widget dialog, {double width = 520, double height = 360}) =>
    Builder(
      builder: (context) => SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: LgTokens.of(context).colors.bg,
          child: LgDialogScrim(onEscape: _noop, child: dialog),
        ),
      ),
    );

const _m6Otpauth =
    'otpauth://totp/Leapgate%20Connection:135792468?secret=ABCDEFGHIJKLMNOPQRSTUVWXYZ234567&issuer=Leapgate%20Connection';

List<Specimen> _m6Specimens() {
  final list = <Specimen>[];

  // ---- the frame -------------------------------------------------------------
  Specimen frame(
    String name,
    Widget Function(bool en) build, {
    bool en = false,
    double w = 1040,
    double h = 660,
    Set<WidgetState> states = const {},
  }) => Specimen(
    'settings-frame',
    name,
    Size(w, h),
    padding: 0,
    states: states,
    (_) => build(en),
  );

  Widget access(bool en, {bool locked = false, String? lockError}) => _m6Frame(
    nav: _m6Nav(en: en, locked: locked),
    content: _m6Content(
      title: _x(en, '访问与密码', 'Access and password'),
      width: 1040 - 8 - 180 - 16,
      height: 660,
      locked: locked,
      lockBar: locked ? _m6LockBar(en, error: lockError) : null,
      children: _m6AccessChildren(en),
    ),
  );

  list
    ..add(frame('access', (en) => access(en)))
    ..add(frame('access-english', (en) => access(en), en: true))
    ..add(frame('locked', (en) => access(en, locked: true)))
    ..add(
      frame(
        'unlock-failed',
        (en) => access(en, locked: true, lockError: '未获得管理员权限，设置仍处于锁定状态'),
      ),
    )
    // The smallest window: 960 wide, the left column 240, so 720 for the page.
    ..add(
      frame(
        'smallest-window',
        (en) => _m6Frame(
          width: 720,
          height: 560,
          nav: _m6Nav(en: en),
          content: _m6Content(
            title: _x(en, '访问与密码', 'Access and password'),
            width: 720 - 8 - 180 - 16,
            height: 560,
            children: _m6AccessChildren(en),
          ),
        ),
        w: 720,
        h: 560,
      ),
    )
    ..add(
      frame(
        'smallest-window-english',
        (en) => _m6Frame(
          width: 720,
          height: 560,
          nav: _m6Nav(en: en, selected: 1),
          content: _m6Content(
            title: 'Permissions',
            width: 720 - 8 - 180 - 16,
            height: 560,
            children: [
              LgSettingsBlock(
                children: [
                  LgSettingsRow(
                    name: 'Access mode',
                    description: 'Applies to later connections only',
                    wide: true,
                    control: LgSegmented<int>(
                      segments: const [
                        LgSegment(0, 'Custom'),
                        LgSegment(1, 'Full'),
                        LgSegment(2, 'Screen only'),
                      ],
                      selected: 1,
                      onChanged: (_) {},
                    ),
                  ),
                ],
              ),
              const LgSettingsNote('Decided by the access mode "Full"'),
              LgSettingsBlock(
                disabled: true,
                children: [
                  LgSettingsRow.toggle(
                    name: 'Allow keyboard and mouse control',
                    value: true,
                    onChanged: (_) {},
                  ),
                  LgSettingsRow.toggle(
                    name: 'Allow TCP tunnelling',
                    description:
                        'Anyone who knows the access password can reach devices on this device\'s local network through a TCP tunnel',
                    value: true,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ],
          ),
        ),
        en: true,
        w: 720,
        h: 560,
      ),
    );

  // ---- the navigation by itself --------------------------------------------------
  Specimen navItem(
    String name, {
    bool selected = false,
    bool locked = false,
    String label = '访问与密码',
    Set<WidgetState> states = const {},
  }) => Specimen(
    'settings-nav-item',
    name,
    const Size(212, 84),
    states: states,
    (_) => SizedBox(
      width: 180,
      child: LgSettingsNavItem(
        label: label,
        selected: selected,
        locked: locked,
        lockedLabel: '已锁定',
        onPressed: _noop,
      ),
    ),
  );
  list
    ..add(navItem('normal'))
    ..add(navItem('hover', states: _hover))
    ..add(navItem('focus', states: _focus))
    ..add(navItem('selected', selected: true))
    ..add(navItem('selected-focus', selected: true, states: _focus))
    ..add(navItem('locked', locked: true))
    ..add(navItem('locked-selected', locked: true, selected: true))
    ..add(navItem('long-label', label: '新设备的默认设置与更多的连接选项'))
    ..add(
      navItem(
        'long-label-english',
        selected: true,
        locked: true,
        label: 'Two-factor authentication',
      ),
    );

  // ---- search ----------------------------------------------------------------------
  Specimen searchField(
    String name,
    String query, {
    Set<WidgetState> states = const {},
    bool en = false,
  }) => Specimen(
    'settings-search-field',
    name,
    const Size(212, 60),
    states: states,
    (_) => SizedBox(
      width: 180,
      child: LgSettingsSearchField(
        controller: TextEditingController(text: query),
        placeholder: _x(en, '搜索设置', 'Search settings'),
        clearLabel: _x(en, '清除搜索', 'Clear search'),
      ),
    ),
  );
  list
    ..add(searchField('empty', ''))
    ..add(searchField('focus', '', states: _focus))
    ..add(searchField('typed', '密码'))
    ..add(searchField('typed-focus', '密码', states: _focus))
    ..add(searchField('empty-english', '', en: true));

  List<LgSettingsSearchResult> hits(bool en) => [
    LgSettingsSearchResult(
      path: _x(en, '传入连接 › 访问与密码', 'Incoming › Access and password'),
      name: _x(en, '审批方式', 'Approval method'),
      description: _x(
        en,
        '输入密码 · 在本机接受 · 输入密码或在本机接受',
        'Enter password · Accept on this device · Enter password or accept on this device',
      ),
    ),
    LgSettingsSearchResult(
      path: _x(en, '传入连接 › 访问与密码', 'Incoming › Access and password'),
      name: _x(en, '密码方式', 'Password method'),
      description: _x(
        en,
        '仅一次性密码 · 仅固定密码 · 一次性密码或固定密码',
        'One-time password only · Fixed password only · One-time or fixed password',
      ),
    ),
    LgSettingsSearchResult(
      path: _x(en, '传入连接 › 访问与密码', 'Incoming › Access and password'),
      name: _x(en, '固定密码', 'Fixed password'),
    ),
    LgSettingsSearchResult(
      path: _x(en, '传入连接 › 权限', 'Incoming › Permissions'),
      name: _x(en, '允许建立 TCP 隧道', 'Allow TCP tunnelling'),
      description: _x(
        en,
        '知道访问密码的人可通过 TCP 隧道访问本机所在局域网中的设备',
        'Anyone who knows the access password can reach devices on the local network through a TCP tunnel',
      ),
    ),
    LgSettingsSearchResult(
      path: _x(en, '传入连接 › 访问限制', 'Incoming › Access limits'),
      name: _x(en, 'ID 白名单', 'ID allow list'),
      description: _x(
        en,
        'ID 由连接本机的设备自行上报，不能代替密码',
        'The ID is reported by the connecting device and cannot replace the password',
      ),
    ),
  ];

  Specimen searchFrame(
    String name, {
    int selected = 2,
    bool none = false,
    bool en = false,
  }) =>
      Specimen('settings-search', name, const Size(1040, 560), padding: 0, (_) {
        final q = en ? 'password' : '密码';
        return _m6Frame(
          height: 560,
          nav: _m6Nav(en: en, query: none ? 'zzz' : q),
          content: SizedBox(
            width: 1040 - 8 - 180 - 16,
            height: 560,
            child: LgSettingsContent(
              children: [
                LgSettingsSearchResults(
                  results: none ? const [] : hits(en),
                  query: q,
                  selectedIndex: selected,
                  onOpen: (_) {},
                  emptyText: _x(en, '未找到匹配的设置', 'No matching settings'),
                ),
              ],
            ),
          ),
        );
      });
  list
    ..add(searchFrame('results'))
    ..add(searchFrame('results-first', selected: 0))
    ..add(searchFrame('results-english', en: true))
    ..add(searchFrame('none', none: true));

  // The hit that was opened: the row is marked.
  list.add(
    Specimen(
      'settings-search',
      'opened-hit-marked',
      const Size(716, 520),
      padding: 0,
      (_) => _m6Content(
        title: '访问与密码',
        width: 716,
        height: 520,
        children: [
          LgSettingsBlock(children: [_m6Approve(false)]),
          LgSettingsBlock(children: [_m6PasswordMode(false)]),
          const LgSettingsSubtitle('一次性密码'),
          LgSettingsBlock(
            children: [
              _m6Length(false),
              LgSettingsRow.toggle(
                name: '仅使用数字',
                value: false,
                onChanged: (_) {},
              ),
            ],
          ),
          LgSettingsBlock(
            gap: true,
            children: [
              LgSettingsRow(
                name: '固定密码',
                marked: true,
                control: LgSettingsValueActions(
                  value: '未设置',
                  actions: const [
                    LgSettingsAction(label: '设置固定密码', onPressed: _noop),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  // ---- lock bar ------------------------------------------------------------------------
  Specimen lockBar(
    String name, {
    String? error,
    bool busy = false,
    bool en = false,
  }) => Specimen(
    'settings-lock-bar',
    name,
    Size(680, error == null ? 88 : 120),
    (_) => SizedBox(
      width: 648,
      child: _m6LockBar(en, error: error, busy: busy),
    ),
  );
  list
    ..add(lockBar('default'))
    ..add(lockBar('busy', busy: true))
    ..add(lockBar('failed', error: '未获得管理员权限，设置仍处于锁定状态'))
    ..add(lockBar('english', en: true))
    ..add(
      Specimen(
        'settings-lock-bar',
        'button-focus',
        const Size(680, 88),
        states: _focus,
        (_) => SizedBox(width: 648, child: _m6LockBar(false)),
      ),
    );

  // ---- rows -------------------------------------------------------------------------------
  Specimen row(
    String name,
    List<Widget> rows, {
    double w = 632,
    double h = 120,
    bool narrow = false,
    bool disabledBlock = false,
    Set<WidgetState> states = const {},
  }) => Specimen(
    'settings-row',
    name,
    Size(w + 32, h + 24),
    states: states,
    (_) => SizedBox(
      width: w,
      child: LgSettingsMetrics(
        narrow: narrow,
        child: LgSettingsBlock(disabled: disabledBlock, children: rows),
      ),
    ),
  );

  list
    ..add(
      row('toggle-on', [
        LgSettingsRow.toggle(
          name: '传入会话期间阻止系统睡眠',
          description: '远程桌面会话期间同时保持屏幕常亮',
          value: true,
          onChanged: (_) {},
        ),
      ], h: 92),
    )
    ..add(
      row('toggle-off-pair', [
        LgSettingsRow.toggle(
          name: '传入会话期间移除桌面壁纸',
          description: '会话结束后恢复',
          value: false,
          onChanged: (_) {},
        ),
        LgSettingsRow.toggle(
          name: '允许 RDP 会话共享',
          description: '本机有多个 Windows 用户会话时，对方可选择要连接的用户',
          value: true,
          onChanged: (_) {},
        ),
      ], h: 168),
    )
    ..add(
      row(
        'toggle-focus',
        [LgSettingsRow.toggle(name: '自适应码率', value: true, onChanged: (_) {})],
        h: 76,
        states: _focus,
      ),
    )
    ..add(
      row('indented', [
        LgSettingsRow.toggle(
          name: '允许直接 IP 访问',
          description: '其他设备可输入本机的 IP 地址直连本机，不经过服务器。此方式同样受白名单、密码和审批方式限制。',
          value: true,
          onChanged: (_) {},
        ),
        const LgSettingsRow(
          name: '端口',
          description: '本机地址：192.0.2.10、2001:db8::10',
          indented: true,
          control: LgSettingsNumberField(
            text: '21118',
            semanticLabel: '端口',
            onSubmitted: _ignoreText,
          ),
        ),
      ], h: 210),
    )
    ..add(
      row('value-and-buttons', [
        LgSettingsRow(
          name: 'IP 白名单',
          description: '开启后，仅列表中的 IP 地址可以连接本机，且本机不接受部分直连方式，连接本机时更可能经中继',
          wide: true,
          control: LgSettingsValueActions(
            value: '已启用 · 3 条',
            emphasized: true,
            actions: const [LgSettingsAction(label: '编辑', onPressed: _noop)],
          ),
        ),
        LgSettingsRow(
          name: '解锁 PIN',
          description: '设置后，可输入 PIN 解锁，不弹出用户账户控制（UAC）窗口',
          wide: true,
          control: LgSettingsValueActions(
            value: '已设置',
            emphasized: true,
            actions: const [
              LgSettingsAction(label: '修改', onPressed: _noop),
              LgSettingsAction(label: '移除', onPressed: _noop),
            ],
          ),
        ),
      ], h: 210),
    )
    ..add(
      row('uac-buttons', [
        LgSettingsRow(
          name: '服务',
          body: const Padding(
            padding: EdgeInsets.only(top: LgSpace.s1),
            child: LgStatusText(LgStatus.error, '服务已停止，本机无法接受远程连接', gap: 8),
          ),
          control: LgSettingsValueActions(
            actions: const [
              LgSettingsAction(
                label: '启动服务',
                icon: LgIcons.uac,
                onPressed: _noop,
              ),
            ],
          ),
        ),
        LgSettingsRow(
          name: '本机 ID',
          wide: true,
          control: LgSettingsValueActions(
            value: '135 792 468',
            emphasized: true,
            actions: const [
              LgSettingsAction(
                label: '复制',
                icon: LgIcons.copy,
                kind: LgButtonKind.text,
                onPressed: _noop,
              ),
            ],
          ),
        ),
      ], h: 190),
    )
    ..add(
      row('disabled-with-reason', [
        const LgSettingsRow(
          name: '一次性密码',
          disabled: true,
          disabledReason: '密码方式为“仅固定密码”时不使用',
          wide: true,
          control: LgSegmented<int>(
            segments: [
              LgSegment(6, '6'),
              LgSegment(8, '8'),
              LgSegment(10, '10'),
            ],
            selected: 6,
            onChanged: null,
          ),
        ),
      ], h: 100),
    )
    ..add(
      row('error-line', [
        LgSettingsRow(
          name: '审批方式',
          description: '仅对之后的连接生效',
          error: '无法保存设置',
          body: _m6Radios(false, ['输入密码', '在本机接受', '输入密码或在本机接受'], 2),
        ),
      ], h: 250),
    )
    ..add(
      row('marked', [
        LgSettingsRow.toggle(name: '自适应码率', value: true, onChanged: (_) {}),
        LgSettingsRow.toggle(
          name: '使用 DirectX 采集屏幕',
          description: '关闭后改用 GDI 采集屏幕，部分硬件编码方式不可用',
          value: true,
          onChanged: (_) {},
          marked: true,
        ),
        LgSettingsRow.toggle(name: '隐私模式', value: false, onChanged: (_) {}),
      ], h: 220),
    )
    ..add(
      row('marked-first-row', [
        LgSettingsRow(
          name: '审批方式',
          marked: true,
          body: _m6Radios(false, ['输入密码', '在本机接受', '输入密码或在本机接受'], 0),
        ),
      ], h: 190),
    )
    ..add(
      row(
        'narrow-control-under-name',
        [
          _m6Length(false),
          LgSettingsRow(
            name: '声音来源',
            description: '远程控制期间向对方传输的声音',
            wide: true,
            control: SizedBox(
              width: 260,
              child: LgSelectField<int>(
                dense: true,
                semanticLabel: '声音来源',
                items: const [LgSelectItem(0, '系统声音'), LgSelectItem(1, '麦克风')],
                value: 0,
                onChanged: (_) {},
              ),
            ),
          ),
        ],
        w: 508,
        h: 210,
        narrow: true,
      ),
    )
    ..add(
      row('wide-control-beside-name', [
        _m6Length(false),
        LgSettingsRow(
          name: '声音来源',
          description: '远程控制期间向对方传输的声音',
          wide: true,
          control: SizedBox(
            width: 260,
            child: LgSelectField<int>(
              dense: true,
              semanticLabel: '声音来源',
              items: const [LgSelectItem(0, '系统声音'), LgSelectItem(1, '麦克风')],
              value: 0,
              onChanged: (_) {},
            ),
          ),
        ),
      ], h: 170),
    )
    ..add(
      row(
        'select-focus',
        [
          LgSettingsRow(
            name: '声音来源',
            wide: true,
            control: SizedBox(
              width: 260,
              child: LgSelectField<int>(
                dense: true,
                semanticLabel: '声音来源',
                items: const [LgSelectItem(0, '系统声音'), LgSelectItem(1, '麦克风')],
                value: 0,
                onChanged: (_) {},
              ),
            ),
          ),
        ],
        h: 76,
        states: _focus,
      ),
    )
    ..add(
      row('sliders', [
        LgSettingsRow(
          name: '默认画质',
          wide: true,
          control: SizedBox(
            width: 240,
            child: LgSlider(
              value: .6,
              onChanged: (_) {},
              semanticLabel: '默认画质',
            ),
          ),
        ),
      ], h: 76),
    )
    ..add(
      row('toggle-english', [
        LgSettingsRow.toggle(
          name: 'Block system sleep during incoming sessions',
          description:
              'Also keeps the screen on while a remote desktop session is open',
          value: true,
          onChanged: (_) {},
        ),
        LgSettingsRow.toggle(
          name: 'Only accept connections while Leapgate is running',
          description: 'A hidden main window still counts as running',
          value: false,
          onChanged: (_) {},
        ),
      ], h: 170),
    );

  // Blocks, small titles and notes --------------------------------------------------------
  list
    ..add(
      Specimen(
        'settings-flow',
        'block-note-block',
        const Size(680, 420),
        padding: 0,
        (_) => _m6Content(
          title: '访问与密码',
          height: 420,
          children: [
            LgSettingsBlock(children: [_m6Approve(false, on: 1)]),
            const LgSettingsNote('审批方式为“在本机接受”时不使用密码'),
            LgSettingsBlock(disabled: true, children: [_m6PasswordMode(false)]),
            const LgSettingsSubtitle('一次性密码'),
            LgSettingsBlock(
              disabled: true,
              children: [
                _m6Length(false),
                LgSettingsRow.toggle(
                  name: '仅使用数字',
                  value: false,
                  onChanged: (_) {},
                ),
              ],
            ),
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'settings-flow',
        'banner-and-blocks',
        const Size(680, 420),
        padding: 0,
        (_) => _m6Content(
          title: '连接方式',
          height: 420,
          children: [
            const LgBanner(
              tone: LgTone.warning,
              slim: true,
              dense: true,
              text: '已设置代理，本机无法被其他设备连接，传出连接将始终经中继。',
            ),
            LgSettingsBlock(
              children: [
                LgSettingsRow.toggle(
                  name: '打洞直连',
                  description: '尝试在两台设备之间直接建立连接，失败时经中继',
                  value: true,
                  onChanged: (_) {},
                ),
              ],
            ),
            const LgSettingsSubtitle('高级'),
            const LgSettingsBlock(
              children: [
                LgSettingsRow(
                  name: '等待直连的时间',
                  description: '超过这个时间仍未直连时改用中继',
                  control: LgSettingsNumberField(
                    text: '2.5',
                    unit: '秒',
                    semanticLabel: '等待直连的时间（秒）',
                    onSubmitted: _ignoreText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

  // ---- status rows ----------------------------------------------------------------------------
  Specimen status(
    String name,
    List<Widget> rows, {
    double w = 632,
    double h = 150,
    bool narrow = false,
  }) => Specimen(
    'settings-status-row',
    name,
    Size(w + 32, h + 24),
    (_) => SizedBox(
      width: w,
      child: LgSettingsMetrics(
        narrow: narrow,
        child: LgSettingsBlock(children: rows),
      ),
    ),
  );
  list
    ..add(
      status('exit-prerequisites', [
        _m6Status(false, LgTone.warning, '固定密码：未设置', 'x', button: true),
        _m6Status(
          false,
          LgTone.warning,
          '审批方式：在本机接受，需有人在本机接受连接',
          'x',
          button: true,
        ),
      ]),
    )
    ..add(
      status('met-and-note', [
        _m6Status(
          false,
          LgTone.success,
          '放行的网段：未放行任何网段',
          'x',
          zhNote: '出口默认禁止访问本机所在的局域网，可按网段放行；本机地址、回环地址、链路本地地址、云元数据地址和保留地址始终禁止。',
          button: true,
        ),
        _m6Status(
          false,
          LgTone.warning,
          'TCP 隧道：已允许，知道访问密码的人可通过 TCP 隧道访问本机所在局域网中的设备',
          'x',
          button: true,
        ),
      ], h: 230),
    )
    ..add(
      status('info-and-error', [
        _m6Status(false, LgTone.info, '尚未登录，出口目录不可用', 'x'),
        _m6Status(false, LgTone.error, '无法读取出口目录', 'x', button: true),
      ], h: 150),
    )
    ..add(
      status(
        'narrow-buttons-below',
        [
          _m6Status(
            false,
            LgTone.warning,
            '审批方式：在本机接受，需有人在本机接受连接',
            'x',
            button: true,
          ),
          _m6Status(false, LgTone.success, '固定密码：已设置', 'x', button: true),
        ],
        w: 508,
        h: 190,
        narrow: true,
      ),
    )
    ..add(
      status('english', [
        _m6Status(
          true,
          LgTone.warning,
          'Fixed password: not set',
          'Fixed password: not set',
          button: true,
        ),
        _m6Status(
          true,
          LgTone.success,
          'Allowed networks: none',
          'Allowed networks: none',
          button: true,
        ),
      ]),
    );

  // ---- number field -------------------------------------------------------------------------------
  Specimen number(
    String name, {
    String text = '1',
    String? unit = '分钟',
    String? error,
    bool disabled = false,
    Set<WidgetState> states = const {},
  }) => Specimen(
    'settings-number-field',
    name,
    Size(680, error == null ? 104 : 136),
    states: states,
    (_) => SizedBox(
      width: 632,
      child: LgSettingsBlock(
        children: [
          LgSettingsRow(
            name: '无操作时自动断开',
            description: '远程桌面会话无键盘鼠标操作超过设定时间后自动断开，仅对之后的连接生效',
            error: error,
            errorAtEnd: true,
            control: LgSettingsNumberField(
              text: text,
              unit: unit,
              semanticLabel: '无操作时自动断开（分钟）',
              errorText: error,
              enabled: !disabled,
              onSubmitted: _ignoreText,
            ),
          ),
        ],
      ),
    ),
  );
  list
    ..add(number('default'))
    ..add(number('focus', states: _focus))
    ..add(number('error', text: '0', error: '请输入 1 到 1440 之间的整数'))
    ..add(number('disabled', disabled: true));

  // ---- label and value rows, the about page -------------------------------------------------------
  list
    ..add(
      Specimen(
        'settings-info-row',
        'server-summary',
        const Size(680, 340),
        (_) => SizedBox(
          width: 632,
          child: LgSettingsBlock(
            children: [
              const LgSettingsInfoRow(
                label: 'ID 服务器',
                value: 'leapgate.example.com（默认）',
              ),
              const LgSettingsInfoRow(
                label: 'API 服务器',
                value: 'https://leapgate.example.com（默认）',
              ),
              const LgSettingsInfoRow(label: 'Key', value: '已设置（默认）'),
              const LgSettingsInfoRow(label: '服务器类型', value: 'Leapgate'),
              LgSettingsRow(
                name: '',
                control: LgSettingsValueActions(
                  actions: const [
                    LgSettingsAction(label: '修改', onPressed: _noop),
                    LgSettingsAction(label: '导入', onPressed: _noop),
                    LgSettingsAction(label: '导出', onPressed: _noop),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'settings-info-row',
        'about',
        const Size(680, 520),
        padding: 0,
        (_) => _m6Content(
          title: '关于',
          height: 520,
          children: [
            const LgSettingsAboutHeader(name: 'Leapgate（跃门）'),
            const LgSettingsBlock(
              children: [
                LgSettingsInfoRow(
                  label: '版本',
                  value: '0.4.0',
                  caption: '基于 RustDesk 1.5.1',
                  copyLabel: '复制',
                  onCopy: _noop,
                  copySemanticLabel: '复制版本',
                ),
                LgSettingsInfoRow(label: '构建日期', value: '2026-10-29'),
                LgSettingsInfoRow(
                  label: '指纹',
                  value: '3F2A 9C41 7B0E D5A8\n6C1E 04D7 B93A F582',
                  mono: true,
                  copyLabel: '复制',
                  onCopy: _noop,
                  copySemanticLabel: '复制指纹',
                ),
                LgSettingsInfoRow(
                  label: '本机 ID',
                  value: '135 792 468',
                  copyLabel: '复制',
                  onCopy: _noop,
                  copySemanticLabel: '复制本机 ID',
                ),
                LgSettingsInfoRow(
                  label: '链接',
                  child: Wrap(
                    spacing: LgSpace.s5,
                    children: [
                      LgTextLink(label: '隐私声明', onPressed: _noop),
                      LgTextLink(label: '网站', onPressed: _noop),
                      LgTextLink(label: '源代码', onPressed: _noop),
                    ],
                  ),
                ),
              ],
            ),
            const LgSettingsFootnote(
              'Copyright © 2026 Purslane Tech Pte. Ltd.',
            ),
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'settings-info-row',
        'about-english',
        const Size(680, 300),
        (_) => const SizedBox(
          width: 632,
          child: LgSettingsBlock(
            children: [
              LgSettingsInfoRow(
                label: 'Version',
                value: '0.4.0',
                caption: 'Based on RustDesk 1.5.1',
                copyLabel: 'Copy',
                onCopy: _noop,
              ),
              LgSettingsInfoRow(label: 'Build date', value: '2026-10-29'),
              LgSettingsInfoRow(
                label: 'Fingerprint',
                value: '3F2A 9C41 7B0E D5A8\n6C1E 04D7 B93A F582',
                mono: true,
                copyLabel: 'Copy',
                onCopy: _noop,
              ),
            ],
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'settings-text-link',
        'states',
        const Size(420, 60),
        (_) => const Row(
          children: [
            LgTextLink(label: '隐私声明', onPressed: _noop),
            SizedBox(width: LgSpace.s5),
            LgTextLink(label: '网站', onPressed: _noop),
            SizedBox(width: LgSpace.s5),
            LgTextLink(label: '源代码', onPressed: null),
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'settings-text-link',
        'focus',
        const Size(220, 60),
        states: _focus,
        (_) => const LgTextLink(label: '改用管理员权限解锁', onPressed: _noop),
      ),
    );

  // ---- trusted devices -------------------------------------------------------------------------------
  Specimen trusted(
    String name, {
    List<LgTrustedDevice>? devices,
    Set<String> picked = const {},
    bool en = false,
    double w = 560,
    double h = 240,
    Set<WidgetState> states = const {},
  }) => Specimen(
    'trusted-devices',
    name,
    Size(w + 32, h + 24),
    states: states,
    (_) => SizedBox(
      width: w,
      child: LgSettingsBlock(
        children: [
          LgSettingsRowFrame(
            indented: true,
            child: _m6TrustedList(en, devices: devices, picked: picked),
          ),
        ],
      ),
    ),
  );
  list
    ..add(trusted('three'))
    ..add(trusted('two-picked', picked: {'912345678', '678912345'}, h: 250))
    ..add(trusted('empty', devices: const [], h: 130))
    ..add(trusted('row-hover', states: _hover))
    ..add(trusted('row-focus', states: _focus))
    ..add(trusted('three-english', en: true))
    ..add(trusted('narrow', w: 508))
    ..add(
      trusted(
        'long-name',
        devices: [
          const LgTrustedDevice(
            id: '912345678',
            name: '李四在公司三楼会议室里的那台很长名字的台式机',
            formattedId: '912 345 678',
            platform: LgPlatform.windows,
            remaining: '剩余 23 天',
          ),
        ],
        h: 150,
      ),
    );

  // ---- shortcuts -----------------------------------------------------------------------------------------
  list
    ..add(
      Specimen(
        'shortcut-list',
        'groups',
        const Size(680, 392),
        (_) => SizedBox(
          width: 632,
          child: LgSettingsMetrics(
            narrow: false,
            child: _m6ShortcutGroups(false),
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'shortcut-list',
        'paused',
        const Size(680, 488),
        (_) => SizedBox(
          width: 632,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LgSettingsListHeader(
                title: '快捷键列表',
                trailing: [LgButton(label: '恢复默认', onPressed: _noop)],
              ),
              const SizedBox(height: LgSpace.s4),
              const LgSettingsNote('已暂停全部快捷键'),
              const SizedBox(height: LgSpace.s5),
              _m6ShortcutGroups(false, disabled: true),
            ],
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'shortcut-list',
        'groups-english',
        const Size(680, 392),
        (_) => SizedBox(width: 632, child: _m6ShortcutGroups(true)),
      ),
    )
    ..add(
      Specimen(
        'shortcut-list',
        'row-focus',
        const Size(680, 120),
        states: _focus,
        (_) => SizedBox(
          width: 632,
          child: LgSettingsBlock(
            children: [
              _m6Shortcut(false, '刷新画面', 'Refresh screen', [
                'Ctrl',
                'Alt',
                'Shift',
                'R',
              ]),
            ],
          ),
        ),
      ),
    );

  Specimen record(
    String name,
    LgShortcutRecordState state,
    List<String> keys, {
    String? status,
    String confirm = '保存',
    String confirmEn = 'Save',
    bool en = false,
  }) => Specimen(
    'shortcut-record-dialog',
    name,
    const Size(448, 330),
    padding: 0,
    (_) => _m6Stage(
      width: 448,
      height: 330,
      _m6RecordDialog(
        en,
        state,
        keys,
        status: status,
        confirm: confirm,
        confirmEn: confirmEn,
      ),
    ),
  );
  list
    ..add(
      record(
        'waiting',
        LgShortcutRecordState.waiting,
        const [],
        status: '请按下组合键',
      ),
    )
    ..add(
      record(
        'unsupported',
        LgShortcutRecordState.unsupported,
        const ['Ctrl', 'Caps Lock'],
        status: '“Caps Lock”不能用作快捷键',
      ),
    )
    ..add(
      record(
        'missing-modifier',
        LgShortcutRecordState.missingModifier,
        const ['P'],
        status: '组合键须包含 Ctrl、Alt 或 Shift',
      ),
    )
    ..add(
      record(
        'conflict',
        LgShortcutRecordState.conflict,
        const ['Ctrl', 'Alt', 'Shift', 'P'],
        status: '已用于“截图”，替换后该操作将没有快捷键',
        confirm: '替换',
        confirmEn: 'Replace',
      ),
    )
    ..add(
      record('valid', LgShortcutRecordState.valid, const [
        'Ctrl',
        'Alt',
        'Shift',
        'R',
      ]),
    )
    ..add(
      record(
        'conflict-english',
        LgShortcutRecordState.conflict,
        const ['Ctrl', 'Alt', 'Shift', 'P'],
        status:
            'Already used for "Screenshot"; replacing it leaves that action without a shortcut',
        confirm: '替换',
        confirmEn: 'Replace',
        en: true,
      ),
    );

  // ---- QR code and the dialogs that use the new footer --------------------------------------------------------
  list
    ..add(
      Specimen(
        'qr-code',
        'default',
        const Size(240, 240),
        (_) => const LgQrCode(data: _m6Otpauth, semanticLabel: '二维码'),
      ),
    )
    ..add(
      Specimen(
        'qr-code',
        'key-row',
        const Size(448, 90),
        (_) => const SizedBox(
          width: 416,
          child: LgQrKeyRow(
            label: '密钥',
            value: 'ABCD EFGH IJKL MNOP\nQRST UVWX YZ23 4567',
            copyLabel: '复制',
            onCopy: _noop,
            copySemanticLabel: '复制密钥',
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'settings-dialog',
        'turn-on-2fa',
        const Size(520, 620),
        padding: 0,
        (_) => _m6Stage(
          width: 520,
          height: 620,
          const LgFormDialog(
            title: '开启二次验证',
            icon: LgIcons.shield,
            actions: [
              LgDialogAction(label: '取消', onPressed: _noop),
              LgDialogAction(
                label: '开启',
                kind: LgButtonKind.primary,
                onPressed: null,
              ),
            ],
            children: [
              SizedBox(height: LgSpace.s4),
              Center(
                child: LgQrCode(data: _m6Otpauth, semanticLabel: '二维码'),
              ),
              SizedBox(height: LgSpace.s2),
              LgQrKeyRow(
                label: '密钥',
                value: 'ABCD EFGH IJKL MNOP\nQRST UVWX YZ23 4567',
                copyLabel: '复制',
                onCopy: _noop,
                copySemanticLabel: '复制密钥',
              ),
              LgFormField(
                label: '验证码',
                child: LgTextField(placeholder: '输入 6 位验证码'),
              ),
            ],
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'settings-dialog',
        'unlock-pin-link',
        const Size(520, 280),
        padding: 0,
        (_) => _m6Stage(
          width: 520,
          height: 280,
          const LgFormDialog(
            title: '输入解锁 PIN',
            icon: LgIcons.lock,
            leading: LgTextLink(label: '改用管理员权限解锁', onPressed: _noop),
            actions: [
              LgDialogAction(label: '取消', onPressed: _noop),
              LgDialogAction(
                label: '解锁',
                kind: LgButtonKind.primary,
                onPressed: null,
              ),
            ],
            children: [
              LgFormField(
                label: 'PIN',
                child: LgTextField(placeholder: '输入解锁 PIN'),
              ),
            ],
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'settings-dialog',
        'undo-button-at-start',
        const Size(520, 340),
        padding: 0,
        (_) => _m6Stage(
          width: 520,
          height: 340,
          LgFormDialog(
            title: '放行的网段',
            icon: LgIcons.exit,
            note: '每行一个 IP 地址或网段，例如 10.0.0.0/24、10.0.0.5、198.18.0.0/15（虚拟地址）',
            banner: const LgBanner(
              tone: LgTone.warning,
              slim: true,
              dense: true,
              text: '第 3 行属于始终禁止访问的地址，不会生效',
            ),
            leading: const LgButton(
              label: '清除',
              kind: LgButtonKind.danger,
              onPressed: _noop,
            ),
            actions: const [
              LgDialogAction(label: '取消', onPressed: _noop),
              LgDialogAction(
                label: '确定',
                kind: LgButtonKind.primary,
                onPressed: _noop,
              ),
            ],
            children: [
              LgFormField(
                label: '网段',
                child: LgTextArea(
                  controller: TextEditingController(
                    text: '10.0.0.0/24\n10.0.0.5\n169.254.169.254',
                  ),
                  height: 96,
                  semanticLabel: '网段',
                ),
              ),
            ],
          ),
        ),
      ),
    );

  return list;
}

void _ignoreText(String _) {}
