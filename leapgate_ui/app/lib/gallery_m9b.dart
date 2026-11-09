// The M9b part of the component gallery: the terminal and camera views' components next to the
// P9 and P10 mockups of A-P9-终端.html, A-P10-摄像头.html and A-P2.html#c-terminal. A part of
// gallery_main.dart, so that it shares its helpers. Only the designer edits it
// (`LEAPGATE.md` §10.18).

part of 'gallery_main.dart';

// ---- the terminal view's bar -------------------------------------------------------------

List<LgTermTabItem> _m9bTabs(int n, {bool en = false}) => [
  for (var i = 1; i <= n; i++)
    LgTermTabItem(
      label: _x(en, '终端 $i', 'Terminal $i'),
      closeLabel: _x(en, '关闭终端 $i', 'Close terminal $i'),
    ),
];

/// The title bar of the terminal view in the states of the P9 frames. [selected] is 0-based;
/// [admin] is the administrator terminal (the view switch says so); [connecting] shows the
/// connecting status where the connection method goes; [newEnabled] false greys "+".
Widget _m9bBar({
  double width = 1280,
  int tabs = 1,
  int selected = 0,
  bool admin = false,
  bool connecting = false,
  bool newEnabled = true,
  bool compact = false,
  bool en = false,
}) => SizedBox(
  width: width,
  child: LgViewBar(
    compact: compact,
    viewSwitch: LgToolbarMenuButton(
      label: admin
          ? _x(en, '终端（管理员）', 'Terminal (administrator)')
          : _x(en, '终端', 'Terminal'),
      icon: LgIcons.terminal,
      highlighted: true,
      items: const [],
    ),
    route: connecting
        ? LgToolbarStatus(
            child: LgStatusText(
              LgStatus.connecting,
              _x(en, '正在连接…', 'Connecting…'),
            ),
          )
        : LgToolbarRouteButton(
            route: LgRoute.direct,
            label: _x(en, '直连', 'Direct'),
            onPressed: _noop,
          ),
    middle: LgTermTabs(
      tabs: _m9bTabs(tabs, en: en),
      selected: selected,
      onSelect: (_) {},
      onClose: (_) {},
      onNew: newEnabled ? _noop : null,
      semanticLabel: _x(en, '终端', 'Terminals'),
      newLabel: _x(en, '新建终端', 'New terminal'),
      newTooltip: _x(en, '新建终端（Ctrl+Shift+T）', 'New terminal (Ctrl+Shift+T)'),
      allLabel: _x(en, '全部终端', 'All terminals'),
    ),
    more: LgViewMoreButton(label: _x(en, '更多', 'More'), items: const []),
    disconnectLabel: _x(en, '断开', 'Disconnect'),
    onDisconnect: _noop,
  ),
);

/// A bar with something drawn under it in the place where a menu or a tooltip would open: the
/// menu itself cannot be open in a still picture, so its panel is drawn where it opens.
Widget _m9bBarWith(
  Widget bar,
  Widget overlay, {
  required double width,
  required double height,
  double? right,
  double? left,
  double top = 52,
}) => Builder(
  builder: (context) => SizedBox(
    width: width,
    height: height,
    child: ColoredBox(
      color: LgTokens.of(context).colors.bg,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          bar,
          Positioned(top: top, left: left, right: right, child: overlay),
        ],
      ),
    ),
  ),
);

// ---- the terminal itself -----------------------------------------------------------------

/// What the terminal of the mockup shows: a prompt in green and blue, a listing, the cursor.
const _m9bSession =
    '\x1b[1;32mmedia@minipc\x1b[0m:\x1b[1;34m~/backup\x1b[0m\$ ls -l\r\n'
    'total 12\r\n'
    'drwxr-xr-x 2 media media 4096 Nov  1 03:00 \x1b[1;34m2026-11-01\x1b[0m\r\n'
    'drwxr-xr-x 2 media media 4096 Nov  4 03:00 \x1b[1;34m2026-11-04\x1b[0m\r\n'
    'drwxr-xr-x 2 media media 4096 Nov  7 03:00 \x1b[1;34m2026-11-07\x1b[0m\r\n'
    '\x1b[1;32mmedia@minipc\x1b[0m:\x1b[1;34m~/backup\x1b[0m\$ echo done\r\n'
    'done\r\n'
    '\x1b[1;32mmedia@minipc\x1b[0m:\x1b[1;34m~/backup\x1b[0m\$ ';

/// The note lines the application writes into the terminal (`p9-info-*`).
String _m9bNotes(bool en) =>
    '$_m9bSession\r\n'
    '${lgTerminalNote(_x(en, '无法打开终端：远程设备拒绝了请求。', 'Cannot open the terminal: the remote device refused.'))}\r\n'
    '${lgTerminalNote(_x(en, '已重新连接，原终端会话已结束。', 'Reconnected. The earlier terminal session has ended.'))}\r\n';

/// The terminal area, dressed as the view dresses it: the dark ground, the scroll bar, the theme
/// and the face. [text] is written once; [select] marks the second line (`p9-sel`).
class _M9bTerminal extends StatefulWidget {
  const _M9bTerminal({
    required this.text,
    this.dimmed = false,
    this.select = false,
    this.banner,
  });

  final String text;
  final bool dimmed;
  final bool select;
  final Widget? banner;

  @override
  State<_M9bTerminal> createState() => _M9bTerminalState();
}

class _M9bTerminalState extends State<_M9bTerminal> {
  late final xterm.Terminal _terminal = xterm.Terminal(maxLines: 500)
    ..write(widget.text);
  final _controller = xterm.TerminalController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.select) {
      _controller.setSelection(
        _terminal.buffer.createAnchor(0, 1),
        _terminal.buffer.createAnchor(26, 1),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      LgTerminalSurface(
        dimmed: widget.dimmed,
        child: LgTerminalScrollbar(
          controller: _scroll,
          child: xterm.TerminalView(
            _terminal,
            controller: _controller,
            scrollController: _scroll,
            theme: lgTerminalTheme(),
            // The gallery's test engine draws any face it does not know in a block face; the
            // export loads Consolas, the second face of the style, so that the picture reads.
            textStyle: lgTerminalStyle().copyWith(fontFamily: 'Consolas'),
            padding: const EdgeInsets.only(top: 3),
            hardwareKeyboardOnly: true,
            autofocus: true,
          ),
        ),
      ),
      if (widget.banner != null)
        Positioned(top: 0, left: 0, right: 0, child: widget.banner!),
    ],
  );
}

LgClipboardRequest _m9bClipboard({bool en = false}) => LgClipboardRequest(
  text: _x(
    en,
    '远程终端中的应用请求写入本机剪贴板。允许后，所有远程终端中的应用均可写入本机剪贴板，可在设置“终端应用写入剪贴板”中修改。',
    'An app in the remote terminal asks to write to this computer\'s clipboard. If you allow it, '
        'apps in all remote terminals can; you can change this in Settings under "Terminal apps writing to the clipboard".',
  ),
  allowLabel: _x(en, '允许', 'Allow'),
  denyLabel: _x(en, '拒绝', 'Deny'),
  onAllow: _noop,
  onDeny: _noop,
  semanticLabel: _x(en, '剪贴板写入请求', 'Clipboard write request'),
);

// ---- the connection panel for an administrator terminal ----------------------------------

Widget _m9bAdminPanel({bool withPassword = false, bool en = false}) {
  final inputs = <Widget>[
    if (withPassword) ...[
      _passwordInput('12345678', focused: false),
      LgCheckbox(
        value: false,
        label: _x(en, '记住密码', 'Remember password'),
        onChanged: (_) {},
      ),
    ],
    _AutoFocus(
      key: ValueKey('admin-$withPassword'),
      builder: (node) => LgAdminAccountInputs(
        title: _x(
          en,
          '远程设备上的管理员账户',
          'Administrator account on the remote device',
        ),
        description: _x(
          en,
          '终端将以 SYSTEM 账户运行',
          'The terminal runs as the SYSTEM account',
        ),
        userController: TextEditingController(
          text: withPassword ? 'zhangsan' : '',
        ),
        passwordController: TextEditingController(),
        userLabel: _x(en, '系统用户名', 'System user name'),
        passwordLabel: _x(en, '系统密码', 'System password'),
        showLabel: _x(en, '显示密码', 'Show password'),
        hideLabel: _x(en, '隐藏密码', 'Hide password'),
        withRule: withPassword,
        userFocusNode: node,
      ),
    ),
  ];
  return Builder(
    builder: (context) => SizedBox(
      width: 960,
      height: 560,
      child: ColoredBox(
        color: LgTokens.of(context).colors.bg,
        child: _hostPanel(
          title: '书房台式机',
          id: '123 456 789',
          platform: LgPlatform.windows,
          steps: _steps(LgStepState.done, LgStepState.current),
          message: withPassword ? _x(en, '输入密码', 'Enter password') : null,
          inputs: inputs,
          actions: [
            LgPanelAction(label: _x(en, '取消', 'Cancel'), onPressed: _noop),
            LgPanelAction(
              label: _x(en, '登录', 'Log in'),
              onPressed: withPassword ? _noop : null,
              primary: true,
              isDefault: true,
            ),
          ],
        ),
      ),
    ),
  );
}

// ---- the camera view ---------------------------------------------------------------------

LgToolbarLabels _m9bToolbarLabels(bool en) => LgToolbarLabels(
  toolbar: _x(en, '会话工具栏', 'Session toolbar'),
  pin: _x(en, '固定工具栏', 'Pin toolbar'),
  fullscreen: _x(en, '全屏', 'Full screen'),
  exitFullscreen: _x(en, '退出全屏', 'Exit full screen'),
  minimize: _x(en, '最小化', 'Minimize'),
  collapse: _x(en, '收起工具栏', 'Collapse toolbar'),
  expand: _x(en, '展开工具栏', 'Expand toolbar'),
);

List<Widget> _m9bCameraMenu({bool en = false, bool all = false}) => [
  LgMenuItem(
    label: _x(en, '摄像头 1', 'Camera 1'),
    checked: !all,
    trailing: const LgMenuRowNote('Integrated Camera'),
    onPressed: _noop,
  ),
  LgMenuItem(
    label: _x(en, '摄像头 2', 'Camera 2'),
    checked: false,
    trailing: const LgMenuRowNote('USB Camera'),
    onPressed: _noop,
  ),
  const Divider(height: 9, thickness: 1, indent: 16, endIndent: 16),
  LgMenuItem(
    label: _x(en, '全部摄像头', 'All cameras'),
    keepOpen: true,
    trailing: LgSwitch(value: all, onChanged: (_) {}),
    onPressed: _noop,
  ),
];

/// The camera view's toolbar (`p10-cam-tiles`, `p10-rec`): the camera switch, the flat camera
/// buttons or the menu button, the recording button with or without the time.
Widget _m9bCameraToolbar({
  bool tiles = false,
  String? recording,
  bool en = false,
}) => Align(
  alignment: Alignment.topCenter,
  child: LgSessionToolbar(
    labels: _m9bToolbarLabels(en),
    pinned: true,
    onTogglePin: _noop,
    collapsed: false,
    onToggleCollapsed: _noop,
    fullscreen: false,
    onToggleFullscreen: _noop,
    groups: [
      [
        LgToolbarMenuButton(
          label: _x(en, '摄像头', 'Camera'),
          icon: LgIcons.camera,
          items: const [],
        ),
        if (tiles) ...[
          LgToolbarTextButton(
            label: '1',
            selected: true,
            semanticLabel: _x(
              en,
              '摄像头 1，Integrated Camera',
              'Camera 1, Integrated Camera',
            ),
            tooltip: _x(en, '摄像头 1', 'Camera 1'),
            tooltipNote: 'Integrated Camera',
            onPressed: _noop,
          ),
          LgToolbarTextButton(
            label: '2',
            semanticLabel: _x(en, '摄像头 2，USB Camera', 'Camera 2, USB Camera'),
            tooltip: _x(en, '摄像头 2', 'Camera 2'),
            tooltipNote: 'USB Camera',
            onPressed: _noop,
          ),
          LgToolbarButton(
            icon: LgIcons.cameras,
            label: _x(en, '全部摄像头', 'All cameras'),
            onPressed: _noop,
          ),
        ] else
          LgToolbarMenuButton(
            label: _x(en, '摄像头 1', 'Camera 1'),
            icon: LgIcons.camera,
            items: _m9bCameraMenu(en: en),
          ),
      ],
      [
        LgToolbarMenuButton(
          label: _x(en, '画面', 'Display'),
          icon: LgIcons.image,
          items: const [],
        ),
        LgToolbarMenuButton(
          label: _x(en, '操作', 'Actions'),
          icon: LgIcons.bolt,
          items: const [],
        ),
        LgToolbarMenuButton(
          label: _x(en, '聊天', 'Chat'),
          icon: LgIcons.chat,
          items: const [],
        ),
      ],
      [
        LgToolbarButton(
          icon: LgIcons.record,
          label: recording == null
              ? _x(en, '录制', 'Record')
              : _x(en, '停止录制', 'Stop recording'),
          recordingText: recording,
          toggled: recording != null,
          onPressed: _noop,
        ),
        LgToolbarRouteButton(
          route: LgRoute.relay,
          label: _x(en, '经中继', 'Relayed'),
          onPressed: _noop,
        ),
      ],
      [
        LgToolbarButton(
          icon: LgIcons.power,
          label: _x(en, '断开', 'Disconnect'),
          danger: true,
          onPressed: _noop,
        ),
      ],
    ],
  ),
);

List<Specimen> _m9bSpecimens() {
  final list = <Specimen>[];

  // ---- the bar of the terminal view: p9-d-def-l, d-three, d-min, d-cp-admin, d-more -------
  void bar(
    String name,
    Widget Function() build, {
    double width = 1280,
    double height = 64,
    Set<WidgetState> states = const {},
  }) => list.add(
    Specimen(
      'term-bar',
      name,
      Size(width, height),
      padding: 0,
      states: states,
      (_) => build(),
    ),
  );

  bar('one', () => _m9bBar()); // d-more (one tab)
  bar('three', () => _m9bBar(tabs: 3, selected: 1)); // d-three
  bar('three-hover', () => _m9bBar(tabs: 3, selected: 1), states: _hover);
  bar('three-focus', () => _m9bBar(tabs: 3, selected: 1), states: _focus);
  bar(
    'admin-connecting', // d-cp-admin: no terminal yet, "+" greyed
    () => _m9bBar(admin: true, connecting: true, tabs: 0, newEnabled: false),
  );
  bar(
    'overflow', // d-min: 960×600 window, six terminals, the fifth selected
    () => _m9bBar(width: 960, tabs: 6, selected: 4, compact: true),
    width: 960,
    height: 56,
  );
  bar(
    'overflow-first', // the first selected: no fade at the start
    () => _m9bBar(width: 960, tabs: 6, selected: 0, compact: true),
    width: 960,
    height: 56,
  );
  bar('english', () => _m9bBar(tabs: 3, selected: 1, en: true));

  list
    ..add(
      Specimen(
        'term-bar',
        'new-tooltip', // d-three: the pointer on "+"
        const Size(1280, 110),
        padding: 0,
        (_) => _m9bBarWith(
          _m9bBar(tabs: 3, selected: 1),
          const LgTooltipBox(child: Text('新建终端（Ctrl+Shift+T）')),
          width: 1280,
          height: 110,
          left: 432,
          top: 60,
        ),
      ),
    )
    ..add(
      Specimen(
        'term-bar',
        'overflow-menu', // d-min: the list of every terminal
        const Size(960, 400),
        padding: 0,
        (_) => _m9bBarWith(
          _m9bBar(width: 960, tabs: 6, selected: 4, compact: true),
          LgMenuPanel(
            width: 200,
            items: [
              for (final (i, t) in _m9bTabs(6).indexed)
                LgMenuItem(label: t.label, checked: i == 4, onPressed: _noop),
            ],
          ),
          width: 960,
          height: 400,
          right: 28,
          top: 48,
        ),
      ),
    )
    ..add(
      Specimen(
        'term-bar',
        'more-menu', // d-more: "⋯" open
        const Size(1280, 220),
        padding: 0,
        (_) => _m9bBarWith(
          _m9bBar(tabs: 1),
          const LgMenuPanel(
            width: 320,
            items: [
              LgMenuItem(
                label: '新建终端',
                icon: LgIcons.plus,
                shortcut: 'Ctrl+Shift+T',
                onPressed: _noop,
              ),
              LgMenuItem(label: '断开连接后保持终端会话', checked: true, onPressed: _noop),
            ],
          ),
          width: 1280,
          height: 220,
          right: 12,
          top: 56,
        ),
      ),
    )
    ..add(
      Specimen(
        'term-bar',
        'more-menu-off', // d-more-off: no connection yet, "新建终端" greyed
        const Size(1280, 220),
        padding: 0,
        (_) => _m9bBarWith(
          _m9bBar(tabs: 0, newEnabled: false),
          const LgMenuPanel(
            width: 320,
            items: [
              LgMenuItem(
                label: '新建终端',
                icon: LgIcons.plus,
                shortcut: 'Ctrl+Shift+T',
                onPressed: null,
              ),
              LgMenuItem(label: '断开连接后保持终端会话', checked: true, onPressed: _noop),
            ],
          ),
          width: 1280,
          height: 220,
          right: 12,
          top: 56,
        ),
      ),
    );

  // ---- the terminal area: p9-d-def-l, d-sel, d-info-*, d-net, d-clip-* ----------------------
  Specimen area(
    String name,
    Widget Function() build, {
    Size size = const Size(760, 300),
  }) => Specimen('term-area', name, size, padding: 0, (_) => build());

  list
    ..add(area('default', () => const _M9bTerminal(text: _m9bSession)))
    ..add(
      area(
        'selection',
        () => const _M9bTerminal(text: _m9bSession, select: true),
      ),
    )
    ..add(
      area(
        'scrollback', // the scroll bar shows once there is something to scroll back to
        () => _M9bTerminal(
          text: [
            for (var i = 1; i <= 40; i++) 'line $i of the output\r\n',
            _m9bSession,
          ].join(),
        ),
      ),
    )
    ..add(area('notes', () => _M9bTerminal(text: _m9bNotes(false))))
    ..add(area('notes-english', () => _M9bTerminal(text: _m9bNotes(true))))
    ..add(
      area('dimmed', () => const _M9bTerminal(text: _m9bSession, dimmed: true)),
    )
    ..add(
      area(
        'clipboard-request',
        () => _M9bTerminal(text: _m9bSession, banner: _m9bClipboard()),
      ),
    )
    ..add(
      area(
        'clipboard-request-english',
        () => _M9bTerminal(text: _m9bSession, banner: _m9bClipboard(en: true)),
      ),
    )
    ..add(
      area(
        'clipboard-request-narrow',
        () => _M9bTerminal(text: _m9bSession, banner: _m9bClipboard()),
        size: const Size(520, 200),
      ),
    );

  // ---- the palette (the sixteen colours as the area shows them) ----------------------------
  list.add(
    Specimen(
      'term-palette',
      'ansi',
      const Size(760, 200),
      padding: 0,
      (_) => _M9bTerminal(
        text: [
          for (final base in [30, 90])
            '${[for (var k = 0; k < 8; k++) '\x1b[${base + k}m ${base + k} \x1b[0m'].join()}\r\n',
          '\x1b[1mbold\x1b[0m \x1b[3mitalic\x1b[0m \x1b[4munderline\x1b[0m \x1b[7mreverse\x1b[0m\r\n',
          '中文输出：年度报告.docx 照片\r\n',
        ].join(),
      ),
    ),
  );

  // ---- the connection panel with the administrator account: d-cp-admin, d-cp-admin-pw -------
  list
    ..add(
      Specimen(
        'term-admin',
        'account-only',
        const Size(960, 560),
        padding: 0,
        (_) => _m9bAdminPanel(),
      ),
    )
    ..add(
      Specimen(
        'term-admin',
        'password-and-account',
        const Size(960, 560),
        padding: 0,
        (_) => _m9bAdminPanel(withPassword: true),
      ),
    )
    ..add(
      Specimen(
        'term-admin',
        'account-only-english',
        const Size(960, 560),
        padding: 0,
        (_) => _m9bAdminPanel(en: true),
      ),
    );

  // ---- the camera view: p10-cam-tiles, p10-cam-menu, p10-rec -------------------------------
  list
    ..add(
      Specimen(
        'camera-toolbar',
        'tiles',
        const Size(1100, 100),
        (_) =>
            _stage(const Size(1068, 84), (_) => _m9bCameraToolbar(tiles: true)),
      ),
    )
    ..add(
      Specimen(
        'camera-toolbar',
        'tiles-tooltip', // the pointer on tile 1: two lines
        const Size(1100, 170),
        (_) => _stage(
          const Size(1068, 154),
          (_) => Stack(
            children: [
              _m9bCameraToolbar(tiles: true),
              Positioned(
                left: 210,
                top: 72,
                child: LgTooltipBox(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Builder(
                        builder: (context) => Text(
                          '摄像头 1',
                          style: LgTokens.of(
                            context,
                          ).text.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Builder(
                        builder: (context) => Text(
                          'Integrated Camera',
                          style: TextStyle(
                            color: LgTokens.of(context).colors.text2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'camera-toolbar',
        'recording',
        const Size(1100, 100),
        (_) => _stage(
          const Size(1068, 84),
          (_) => _m9bCameraToolbar(recording: '00:42'),
        ),
      ),
    )
    ..add(
      Specimen(
        'camera-toolbar',
        'recording-english',
        const Size(1100, 100),
        (_) => _stage(
          const Size(1068, 84),
          (_) => _m9bCameraToolbar(recording: '00:42', en: true),
        ),
      ),
    );

  for (final e in {
    'normal': <WidgetState>{},
    'hover': _hover,
    'focus': _focus,
  }.entries) {
    list.add(
      Specimen(
        'record-button',
        'recording-${e.key}',
        const Size(240, 76),
        states: e.value,
        (_) => const LgToolbarButton(
          icon: LgIcons.record,
          label: '停止录制',
          recordingText: '00:42',
          toggled: true,
          onPressed: _noop,
        ),
      ),
    );
  }
  list.add(
    Specimen(
      'record-button',
      'idle',
      const Size(240, 76),
      (_) => const LgToolbarButton(
        icon: LgIcons.record,
        label: '录制',
        onPressed: _noop,
      ),
    ),
  );

  list
    ..add(
      Specimen(
        'camera-menu',
        'list',
        const Size(360, 230),
        (_) => LgMenuPanel(width: 330, items: _m9bCameraMenu()),
      ),
    )
    ..add(
      Specimen(
        'camera-menu',
        'list-all',
        const Size(360, 230),
        (_) => LgMenuPanel(width: 330, items: _m9bCameraMenu(all: true)),
      ),
    )
    ..add(
      Specimen(
        'camera-menu',
        'long-name',
        const Size(360, 120),
        (_) => const LgMenuPanel(
          width: 330,
          items: [
            LgMenuItem(
              label: '摄像头 1',
              checked: true,
              trailing: LgMenuRowNote(
                'Integrated Camera with a very long vendor name (USB 2.0 UVC HD Webcam)',
              ),
              onPressed: _noop,
            ),
          ],
        ),
      ),
    );

  return list;
}
