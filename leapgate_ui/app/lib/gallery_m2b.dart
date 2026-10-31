// The M2b part of the component gallery: every component and state of
// docs/新界面/03 §4.6 added for M2b (device card and list view, home chrome,
// menu rows, toolbar docking and overflow, route details, chat, notices with
// buttons, the fixed-password dialog), next to the mockups A-P1.html and
// A-P2.html. A part of gallery_main.dart, so that it shares its helpers.

part of 'gallery_main.dart';

// ---- helpers ------------------------------------------------------------------

const _tbLabels2 = LgToolbarLabels(
  toolbar: '会话工具栏',
  pin: '固定工具栏',
  fullscreen: '全屏',
  exitFullscreen: '退出全屏',
  minimize: '最小化',
  collapse: '收起工具栏',
  expand: '展开工具栏',
  drag: '移动工具栏',
  more: '更多',
);

/// The three tag colours of the mockups (`--lg-tag-home`, `-work`, `-common`),
/// taken from the identity colours so that they follow the theme.
String _pct(double v) => '${v.round()}%';
String _int(double v) => '${v.round()}';

List<LgDeviceTag> _tagsOf(BuildContext context, List<int> which) {
  final c = LgTokens.of(context).colors;
  const names = ['家里', '工作', '常用'];
  const groups = [0, 5, 6];
  return [
    for (final i in which) LgDeviceTag(names[i], c.identity[groups[i]].solid),
  ];
}

LgDeviceCard _card(
  BuildContext context,
  _Dev d, {
  List<int> tags = const [0],
  bool favorite = false,
  bool savedPassword = false,
  bool selected = false,
  bool? picked,
  bool actions = true,
  String? source,
  LgDeviceStatus? status,
  String? name,
}) {
  final s = status ?? d.status;
  return LgDeviceCard(
    name: name ?? d.name,
    id: d.id,
    platform: d.platform,
    status: s,
    statusLabel: s == LgDeviceStatus.querying ? '正在查询…' : d.statusLabel,
    userHost: d.userHost,
    tags: _tagsOf(context, tags),
    source: source,
    favorite: favorite,
    savedPassword: savedPassword,
    favoriteLabel: '已收藏',
    savedPasswordLabel: '已保存密码',
    selected: selected,
    picked: picked,
    onTap: _noop,
    onDoubleTap: _noop,
    onConnect: actions ? _noop : null,
    connectLabel: actions ? '连接' : null,
    onMore: actions ? _noop : null,
    moreLabel: actions ? '更多操作' : null,
  );
}

LgDeviceRow _tableRow(
  BuildContext context,
  _Dev d,
  int i, {
  bool first = false,
  bool selected = false,
  bool? picked,
  String? source,
  bool more = true,
}) {
  const tagSets = [
    [0],
    [0],
    [1],
    <int>[],
    <int>[],
    <int>[],
    <int>[],
    [1, 2],
  ];
  return LgDeviceRow(
    name: d.name,
    id: d.id,
    platform: d.platform,
    status: d.status,
    statusLabel: d.statusLabel,
    userHost: d.userHost,
    source: source,
    tags: source == null ? _tagsOf(context, tagSets[i % tagSets.length]) : null,
    favorite: i == 0,
    savedPassword: i == 6,
    favoriteLabel: '已收藏',
    savedPasswordLabel: '已保存密码',
    selected: selected,
    picked: picked,
    topDivider: !first,
    onTap: _noop,
    onDoubleTap: _noop,
    onConnect: _noop,
    connectLabel: '连接',
    onMore: more ? _noop : null,
    moreLabel: more ? '更多操作' : null,
  );
}

const _columns = [
  LgTableColumn(LgDeviceColumn.status, '状态', sortable: true),
  LgTableColumn(LgDeviceColumn.name, '名称', sortable: true),
  LgTableColumn(LgDeviceColumn.id, 'ID', sortable: true),
  LgTableColumn(LgDeviceColumn.userHost, '用户@主机', sortable: true),
  LgTableColumn(LgDeviceColumn.tags, '标签'),
];

Widget _table(
  BuildContext context, {
  LgTableSort? sort = const LgTableSort(LgDeviceColumn.name),
  int selected = -1,
  bool? picked,
  int count = 8,
  bool source = false,
}) {
  final rows = <Widget>[
    for (var i = 0; i < count; i++)
      _tableRow(
        context,
        _devices[i % _devices.length],
        i,
        first: i == 0,
        selected: i == selected,
        picked: picked == null ? null : i < 3,
        source: source ? '收藏' : null,
      ),
  ];
  return LgDeviceTable(
    columns: source
        ? const [
            LgTableColumn(LgDeviceColumn.status, '状态'),
            LgTableColumn(LgDeviceColumn.name, '名称'),
            LgTableColumn(LgDeviceColumn.id, 'ID'),
            LgTableColumn(LgDeviceColumn.userHost, '用户@主机'),
            LgTableColumn(LgDeviceColumn.source, '来源'),
          ]
        : _columns,
    rows: rows,
    sort: sort,
    onSort: (_) {},
    pickColumn: picked != null,
    moreColumn: true,
    ascendingLabel: '升序',
    descendingLabel: '降序',
    semanticLabel: '设备列表',
  );
}

LgListToolMenu _viewTool() => LgListToolMenu(
  icon: LgIcons.grid,
  label: '视图',
  items: _viewToolMenu(true, true),
);

List<Widget> _viewToolMenu(bool cards, bool expanded) => [
  const LgMenuGroup('视图'),
  LgMenuItem(label: '卡片', checked: cards, onPressed: _noop),
  LgMenuItem(label: '列表', checked: !cards, onPressed: _noop),
  const LgMenuGroup('界面模式'),
  LgMenuSegmentedItem<int>(
    segments: const [LgSegment(0, '简洁'), LgSegment(1, '详细')],
    selected: 0,
    onChanged: (_) {},
  ),
  const LgMenuDivider(),
  LgMenuExpandRow(label: '调整显示的分类和顺序', expanded: expanded, onToggle: _noop),
  if (expanded)
    for (final name in ['最近', '收藏', '局域网', '地址簿', '同组设备'])
      LgMenuItem(
        label: name,
        checked: true,
        onPressed: _noop,
        trailing: const LgMenuGrip(),
        keepOpen: true,
      ),
];

List<Widget> _sortToolMenu() => const [
  LgMenuItem(label: '名称', checked: true, onPressed: _noop),
  LgMenuItem(label: 'ID', checked: false, onPressed: _noop),
  LgMenuItem(label: '用户名', checked: false, onPressed: _noop),
  LgMenuItem(label: '在线状态', checked: false, onPressed: _noop),
];

Widget _listToolbar({
  int selected = 0,
  bool sort = false,
  bool multi = false,
  bool refresh = false,
  bool viewOpen = false,
  bool sortOpen = false,
}) {
  return LgListToolbar(
    tabs: LgCategoryTabs<int>(
      categories: const [
        LgCategory(0, '最近'),
        LgCategory(1, '收藏'),
        LgCategory(2, '局域网'),
        LgCategory(3, '地址簿'),
        LgCategory(4, '同组设备'),
      ],
      selected: selected,
      onSelect: (_) {},
      semanticLabel: '设备分类',
    ),
    tools: [
      viewOpen
          ? LgStateOverride(
              states: const {WidgetState.selected},
              child: _viewTool(),
            )
          : _viewTool(),
      if (sort)
        sortOpen
            ? LgStateOverride(
                states: const {WidgetState.selected},
                child: LgListToolMenu(
                  icon: LgIcons.sort,
                  label: '排序',
                  items: _sortToolMenu(),
                ),
              )
            : LgListToolMenu(
                icon: LgIcons.sort,
                label: '排序',
                items: _sortToolMenu(),
              ),
      LgListToolButton(
        icon: LgIcons.select,
        label: '多选',
        onPressed: _noop,
        active: multi,
      ),
      if (refresh)
        const LgListToolButton(
          icon: LgIcons.refresh,
          label: '刷新',
          onPressed: _noop,
        ),
    ],
  );
}

Widget _pageStage(Size size, Widget Function(BuildContext) child) => Builder(
  builder: (context) => SizedBox(
    width: size.width,
    height: size.height,
    child: ColoredBox(
      color: LgTokens.of(context).colors.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LgSpace.s2,
          LgSpace.s4,
          LgSpace.s6,
          0,
        ),
        child: child(context),
      ),
    ),
  ),
);

List<double> _delaySeries() => [
  for (var i = 0; i < 31; i++)
    i == 14 ? 31 : 11.5 + (i * 7 % 5) * .6 + (i % 3 == 0 ? .8 : 0),
];

LgSparkline _spark({bool relay = false}) => LgSparkline(
  series: [
    LgSparkSeries(_delaySeries(), LgLineStyle.primary),
    if (relay) ...[
      LgSparkSeries([for (final v in _delaySeries()) v * .45], LgLineStyle.accent),
      LgSparkSeries([for (final v in _delaySeries()) v * .5], LgLineStyle.relay),
    ],
  ],
  unit: 'ms',
  timeLabels: const ['60 秒前', '30 秒前', '现在'],
  semanticLabel: '近 60 秒端到端延迟，当前 12 ms',
);

LgRouteDetails _details({
  LgRoute route = LgRoute.relay,
  bool encrypted = true,
  bool withPeers = false,
  bool qualityOn = false,
  bool noRoute = false,
  bool noChart = false,
  double? maxHeight,
}) {
  final relay = route == LgRoute.relay;
  return LgRouteDetails(
    route: route,
    title: relay ? '经中继' : '直连',
    semanticLabel: '连接方式',
    why: relay ? '流量由中继服务器转发，速度可能较慢' : '两台设备直接连接，速度取决于双方的网络',
    encrypted: encrypted,
    unencryptedLabel: encrypted ? null : '未加密',
    width: withPeers ? 480 : 400,
    maxHeight: maxHeight,
    groups: [
      LgKeyValueGroup('连接', [
        if (!noRoute) LgKeyValue('路径', relay ? '经中继' : '直连'),
        if (relay && !noRoute) const LgKeyValue('中继服务器', 'relay-1.example.com'),
        const LgKeyValue('传输', 'TCP'),
        LgKeyValue(
          '加密',
          encrypted ? '已加密' : '未加密',
          icon: encrypted ? LgIcons.lock : LgIcons.warn,
        ),
        const LgKeyValue(
          '指纹',
          '3F2A 9C41 7B0E D5A8\n6C1E 04D7 B93A F582',
          copyLabel: '复制指纹',
          onCopy: _noop,
          wrap: true,
        ),
      ]),
      const LgKeyValueGroup('画面数据', [
        LgKeyValue('编码', 'H264'),
        LgKeyValue('帧率', '30'),
        LgKeyValue('目标码率', '2000 kb/s'),
        LgKeyValue('色度', '4:2:0'),
        LgKeyValue('速度', '1.2 MB/s'),
      ]),
    ],
    latency: LgLatencySection(
      title: '延迟（往返）',
      note: '统计自本次会话开始，折线为近 60 秒',
      currentLabel: '当前',
      minLabel: '最低',
      averageLabel: '平均',
      maxLabel: '最高',
      rows: withPeers
          ? const [
              LgLatencyRow(
                name: '端到端',
                line: LgLineStyle.primary,
                current: '39 ms',
                min: '31',
                average: '38',
                max: '66',
              ),
              LgLatencyRow(
                name: '本机 ↔ 中继服务器',
                line: LgLineStyle.accent,
                current: '18 ms',
                min: '16',
                average: '19',
                max: '34',
                indent: true,
              ),
              LgLatencyRow(
                name: '中继服务器 ↔ 远程设备',
                line: LgLineStyle.relay,
                current: '21 ms',
                min: '19',
                average: '22',
                max: '41',
                indent: true,
              ),
            ]
          : [
              LgLatencyRow(
                name: '端到端',
                line: LgLineStyle.primary,
                current: relay ? '39 ms' : '12 ms',
                min: relay ? '31' : '9',
                average: relay ? '38' : '13',
                max: relay ? '66' : '31',
              ),
            ],
      chart: noChart ? null : _spark(relay: withPeers),
    ),
    qualitySwitch: LgDetailsSwitch(
      label: '在画面上显示质量数据',
      value: qualityOn,
      onChanged: (_) {},
    ),
  );
}

List<LgChatMessage> _chat() => const [
  LgChatMessage(text: '你好，我帮你看一下打印机。', time: '10:24', mine: true),
  LgChatMessage(text: '好的，谢谢！', time: '10:25', mine: false),
];

Widget _chatPanel({
  List<LgChatMessage>? messages,
  String draft = '',
  String? empty,
}) => LgChatPanel(
  title: '聊天',
  messages: messages ?? _chat(),
  controller: TextEditingController(text: draft),
  placeholder: '输入消息',
  sendLabel: '发送',
  closeLabel: '关闭',
  mineLabel: '我',
  theirsLabel: '对方',
  emptyText: empty,
  onSend: (_) {},
  onClose: _noop,
  onDrag: (_) {},
);

/// The toolbar of M2b: the view menu, the picture, input, action, session and
/// chat menus, the record button, the route button and "disconnect"; the last
/// three menu-like buttons may fold into "更多".
Widget _toolbar2({
  LgToolbarDock dock = LgToolbarDock.top,
  bool collapsed = false,
  bool fullscreen = false,
  LgRoute route = LgRoute.relay,
  bool encrypted = true,
  bool english = false,
  bool unread = true,
  bool display = false,
  bool displayFlat = false,
  LgToolbarMenuState chat = LgToolbarMenuState.normal,
  bool routeOpen = false,
}) {
  final routeLabel = english
      ? (route == LgRoute.relay ? 'Relayed' : 'Direct')
      : (route == LgRoute.relay ? '经中继' : '直连');
  final unencrypted = encrypted ? null : (english ? 'Unencrypted' : '未加密');
  String l(String zh, String en) => english ? en : zh;
  final chatLabel = switch (chat) {
    LgToolbarMenuState.normal => l('聊天', 'Chat'),
    LgToolbarMenuState.pending => l('等待接听…', 'Calling…'),
    LgToolbarMenuState.live => l('通话中', 'In call'),
  };
  return LgSessionToolbar(
    labels: _tbLabels2,
    dock: dock,
    pinned: true,
    onTogglePin: _noop,
    collapsed: collapsed,
    onToggleCollapsed: _noop,
    fullscreen: fullscreen,
    onToggleFullscreen: _noop,
    onMinimize: _noop,
    deviceName: '妈妈的笔记本',
    deviceId: '234 567 891',
    route: route,
    routeLabel: routeLabel,
    encrypted: encrypted,
    unencryptedLabel: unencrypted,
    collapsedActions: display
        ? [
            const LgToolbarButton(
              icon: LgIcons.displays,
              label: '2/3',
              semanticLabel: '切换显示器，当前第 2 个，共 3 个',
              showText: true,
              onPressed: _noop,
            ),
          ]
        : const [],
    groups: [
      [
        LgToolbarMenuButton(
          label: l('远程桌面', 'Remote desktop'),
          icon: LgIcons.monitor,
          items: _viewMenu(),
        ),
        if (display && !displayFlat)
          LgToolbarMenuButton(
            label: l('显示器', 'Display'),
            icon: LgIcons.displays,
            items: _displayMenu(),
          ),
        if (displayFlat) ...[
          const LgToolbarTextButton(
            label: '1',
            semanticLabel: '显示器 1',
            selected: true,
            onPressed: _noop,
          ),
          const LgToolbarTextButton(
            label: '2',
            semanticLabel: '显示器 2',
            onPressed: _noop,
          ),
          const LgToolbarTextButton(
            label: '3',
            semanticLabel: '显示器 3',
            onPressed: _noop,
          ),
          const LgToolbarButton(
            icon: LgIcons.displays,
            label: '全部显示器',
            onPressed: _noop,
          ),
        ],
      ],
      [
        LgToolbarMenuButton(
          label: l('画面', 'Display'),
          icon: LgIcons.image,
          items: _pictureMenu(),
        ),
        LgToolbarMenuButton(
          label: l('输入', 'Input'),
          icon: LgIcons.pointer,
          items: _viewMenu(),
        ),
        LgToolbarMenuButton(
          label: l('操作', 'Actions'),
          icon: LgIcons.bolt,
          items: _actionMenu(),
        ),
        LgToolbarFoldable(
          badge: 0,
          inline: LgToolbarMenuButton(
            label: l('会话', 'Session'),
            icon: LgIcons.toggles,
            items: _viewMenu(),
          ),
          menuItem: LgSubmenu(
            label: l('会话', 'Session'),
            icon: LgIcons.toggles,
            items: _viewMenu(),
          ),
        ),
        LgToolbarFoldable(
          badge: unread ? 1 : 0,
          inline: LgToolbarMenuButton(
            label: chatLabel,
            icon: LgIcons.chat,
            items: _viewMenu(),
            state: chat,
            badge: unread && chat == LgToolbarMenuState.normal ? 1 : 0,
          ),
          menuItem: LgSubmenu(
            label: l('聊天', 'Chat'),
            icon: LgIcons.chat,
            badge: unread ? 1 : 0,
            items: _viewMenu(),
          ),
        ),
      ],
      [
        const LgToolbarFoldable(
          inline: LgToolbarButton(
            icon: LgIcons.record,
            label: '录制',
            onPressed: _noop,
          ),
          menuItem: LgMenuItem(
            label: '录制',
            icon: LgIcons.record,
            onPressed: _noop,
          ),
        ),
        LgToolbarRouteButton(
          route: route,
          label: routeLabel,
          encrypted: encrypted,
          unencryptedLabel: unencrypted,
          open: routeOpen,
          onPressed: _noop,
        ),
      ],
      [
        LgToolbarButton(
          icon: LgIcons.power,
          label: l('断开', 'Disconnect'),
          danger: true,
          onPressed: _noop,
        ),
      ],
    ],
  );
}

/// A bar in its place on the picture, in a placer that also gives the grip.
Widget _placed(
  LgToolbarPlacement placement,
  Widget bar, {
  LgToolbarPlacement? preview,
  Size size = const Size(1280, 420),
}) => _stage(
  size,
  (_) => LgToolbarPlacer(
    placement: placement,
    preview: preview,
    anyEdge: true,
    child: bar,
  ),
  picture: true,
);

/// A bar drawn lifted, as while its grip is dragged.
Widget _lifted(
  LgToolbarPlacement placement,
  Widget bar, {
  LgToolbarPlacement? preview,
  Size size = const Size(1280, 420),
}) => _stage(
  size,
  (_) => LgToolbarPlacer(
    placement: placement,
    preview: preview,
    child: LgToolbarDragScope(
      dragging: true,
      onStart: (_) {},
      onUpdate: (_) {},
      onEnd: _noop,
      onNudge: (_) {},
      child: bar,
    ),
  ),
  picture: true,
);

// ---- the specimens ----------------------------------------------------------------

List<Specimen> _m2bSpecimens() {
  final list = <Specimen>[];
  const wide = 1040.0;

  // Menu rows ------------------------------------------------------------------
  const menuStage = Size(360, 560);
  Specimen menu(
    String name,
    List<Widget> items, {
    Size size = menuStage,
    double width = kLgMenuWidth,
  }) => Specimen(
    'menu-rows',
    name,
    size,
    (_) => LgMenuPanel(items: items, width: width),
  );
  list
    ..add(
      menu('view-menu', _viewToolMenu(true, true), size: const Size(360, 640)),
    )
    ..add(
      menu('view-menu-folded', _viewToolMenu(false, false), size: const Size(360, 330)),
    )
    ..add(menu('sort-menu', _sortToolMenu(), size: const Size(280, 260), width: 240))
    ..add(
      menu('picture-zoom', [
        const LgMenuGroup('缩放'),
        const LgMenuItem(label: '原始大小', checked: false, onPressed: _noop),
        const LgMenuItem(label: '适应窗口', checked: true, onPressed: _noop),
        const LgMenuItem(
          label: '自定义',
          checked: false,
          hint: '5%~1000%',
          onPressed: _noop,
        ),
        LgMenuSliderItem(
          value: 100,
          min: 5,
          max: 1000,
          format: _pct,
          semanticLabel: '自定义缩放',
          onChanged: (_) {},
        ),
        const LgMenuGroup('滚动方式'),
        const LgMenuItem(label: '自动', checked: true, onPressed: _noop),
        const LgMenuItem(label: '滚动条', checked: false, onPressed: null),
        const LgMenuItem(label: '边缘滚动', checked: false, onPressed: null),
      ], size: const Size(360, 560)),
    )
    ..add(
      menu('input-menu', [
        const LgMenuGroup('键盘模式'),
        const LgMenuItem(label: '传统', checked: false, onPressed: _noop),
        const LgMenuItem(label: '映射', checked: true, onPressed: _noop),
        const LgMenuItem(label: '翻译', checked: false, onPressed: _noop),
        const LgMenuGroup('输入源'),
        const LgMenuItem(label: '输入源 1', checked: true, onPressed: _noop),
        const LgMenuItem(label: '输入源 2', checked: false, onPressed: _noop),
        const LgMenuDivider(),
        LgMenuSwitchItem(label: '仅查看模式', value: false, onChanged: (_) {}),
        LgMenuSwitchItem(
          label: '显示本机光标',
          value: false,
          indent: true,
          onChanged: (_) {},
        ),
        LgMenuSwitchItem(label: '相对鼠标模式', value: true, onChanged: (_) {}),
        LgMenuSwitchItem(label: '反转滚动方向', value: false, onChanged: (_) {}),
        const LgMenuGroup('触控板速度'),
        LgMenuSliderItem(
          value: 100,
          min: 10,
          max: 1000,
          format: _pct,
          semanticLabel: '触控板速度',
          onChanged: (_) {},
        ),
      ], size: const Size(360, 700)),
    )
    ..add(
      menu('action-menu', [
        const LgMenuItem(
          label: '发送 Ctrl+Alt+Del',
          shortcut: 'Ctrl+Alt+Shift+Delete',
          onPressed: _noop,
        ),
        const LgMenuItem(label: '锁定远程设备', onPressed: _noop),
        const LgMenuItem(label: '重启远程设备', onPressed: _noop),
        const LgMenuDivider(),
        const LgMenuItem(
          label: '阻止远程设备的本地输入',
          shortcut: 'Ctrl+Alt+Shift+I',
          onPressed: _noop,
        ),
        const LgMenuItem(label: '请求提升权限', onPressed: _noop),
        const LgMenuItem(
          label: '输入系统登录密码',
          onPressed: _noop,
          trailing: LgIcon(LgIcons.edit, size: 18, color: Color(0xFF6B7F7D)),
        ),
        const LgMenuItem(label: '键入剪贴板文本', onPressed: _noop),
        const LgMenuDivider(),
        const LgMenuItem(label: '刷新画面', onPressed: _noop),
        const LgMenuItem(
          label: '截图',
          shortcut: 'Ctrl+Alt+Shift+P',
          onPressed: _noop,
        ),
        const LgMenuItem(label: '交换控制方向', onPressed: _noop),
        const LgMenuItem(label: '添加备注', onPressed: _noop),
      ], size: const Size(420, 640), width: 380),
    )
    ..add(
      menu(
        'action-menu-view-only',
        width: 380,
        size: const Size(420, 240),
        const [
        LgMenuItem(
          label: '发送 Ctrl+Alt+Del',
          shortcut: 'Ctrl+Alt+Shift+Delete',
          onPressed: null,
          disabledNote: '仅查看模式下不可用',
        ),
        LgMenuItem(
          label: '锁定远程设备',
          onPressed: null,
          disabledNote: '仅查看模式下不可用',
        ),
        LgMenuItem(label: '刷新画面', onPressed: _noop),
        LgMenuItem(
          label: '截图',
          shortcut: 'Ctrl+Alt+Shift+P',
          onPressed: _noop,
        ),
      ]),
    )
    ..add(
      menu('session-menu', [
        LgMenuSwitchItem(
          label: '静音',
          shortcut: 'Ctrl+Alt+Shift+S',
          value: false,
          onChanged: (_) {},
        ),
        LgMenuSwitchItem(label: '同步剪贴板', value: true, onChanged: (_) {}),
        LgMenuSwitchItem(label: '允许复制粘贴文件', value: true, onChanged: (_) {}),
        LgMenuSwitchItem(
          label: '会话结束后锁定远程设备',
          value: false,
          onChanged: (_) {},
        ),
        const LgSubmenu(
          label: '隐私模式',
          items: [LgMenuItem(label: '遮挡屏幕', onPressed: _noop)],
        ),
      ], size: const Size(380, 320), width: 340),
    )
    ..add(
      menu('switch-disabled', [
        const LgMenuSwitchItem(
          label: '允许复制粘贴文件',
          value: true,
          onChanged: null,
          disabledNote: '远程设备没有授予此权限',
        ),
        const LgMenuSwitchItem(label: '同步剪贴板', value: false, onChanged: null),
      ], size: const Size(360, 140)),
    )
    ..add(
      menu('check-item', [
        const LgMenuGroup('设备'),
        LgMenuCheckItem(label: '始终经中继连接', value: false, onChanged: (_) {}),
        LgMenuCheckItem(label: '始终经中继连接', value: true, onChanged: (_) {}),
        const LgMenuItem(label: '创建桌面快捷方式', onPressed: _noop),
      ], size: const Size(360, 240)),
    )
    ..add(
      menu('resolution', [
        const LgMenuItem(label: '原始分辨率', checked: true, onPressed: _noop),
        const LgMenuItem(label: '与本机相同', checked: false, onPressed: _noop),
        const LgMenuDivider(),
        const LgMenuGroup('远程设备支持的分辨率'),
        const LgMenuItem(label: '1920×1080', checked: false, onPressed: _noop),
        const LgMenuItem(label: '1680×1050', checked: false, onPressed: _noop),
        const LgMenuItem(label: '1600×900', checked: false, onPressed: _noop),
        const LgMenuItem(label: '1440×900', checked: false, onPressed: _noop),
      ], size: const Size(320, 520), width: 280),
    )
    ..add(
      menu('picture-menu-rows', const [
        LgMenuItem(label: '显示远程光标', checked: true, shortcut: 'Ctrl+Alt+Shift+M', onPressed: _noop),
        LgMenuItem(label: '跟随远程光标', checked: false, onPressed: _noop),
        LgSubmenu(
          label: '分辨率',
          value: '1920×1080',
          items: [LgMenuItem(label: '原始分辨率', checked: true, onPressed: _noop)],
        ),
        LgSubmenu(
          label: '虚拟显示器',
          items: [LgMenuItem(label: '虚拟显示器 1', checked: true, onPressed: _noop)],
        ),
      ], size: const Size(360, 260)),
    )
    ..add(
      menu('group-note', const [
        LgMenuGroup('地址簿', note: '此地址簿为只读'),
        LgMenuItem(label: '加入地址簿', onPressed: null),
      ], size: const Size(360, 140)),
    )
    ..add(
      menu('more-menu', const [
        LgSubmenu(label: '会话', icon: LgIcons.toggles, items: [LgMenuItem(label: '静音', onPressed: _noop)]),
        LgSubmenu(label: '聊天', icon: LgIcons.chat, badge: 1, items: [LgMenuItem(label: '文字聊天', onPressed: _noop)]),
        LgMenuItem(label: '录制', icon: LgIcons.record, onPressed: _noop),
      ], size: const Size(360, 200)),
    )
    ..add(
      menu('voice-call-menu', width: 300, size: const Size(340, 400), [
        const LgMenuGroup('麦克风'),
        const LgMenuItem(label: '默认麦克风', checked: true, onPressed: _noop),
        const LgMenuItem(label: '耳机麦克风', checked: false, onPressed: _noop),
        const LgMenuItem(label: '系统声音', checked: false, onPressed: _noop),
        const LgMenuDivider(),
        const LgMenuItem(
          label: '挂断',
          icon: LgIcons.callEnd,
          danger: true,
          onPressed: _noop,
        ),
      ]),
    )
    ..add(
      menu('voice-wait-menu', width: 240, size: const Size(280, 120), const [
        LgMenuItem(label: '取消', icon: LgIcons.x, onPressed: _noop),
      ]),
    )
    ..add(
      menu('tab-context-menu', width: 240, size: const Size(280, 200), const [
        LgMenuItem(label: '复制设备 ID', onPressed: _noop),
        LgMenuItem(label: '关闭其他标签', onPressed: _noop),
        LgMenuDivider(),
        LgMenuItem(label: '关闭', onPressed: _noop),
      ]),
    )
    ..add(
      menu('device-menu', [
        const LgMenuGroup('连接方式'),
        const LgMenuItem(label: '远程桌面', onPressed: _noop),
        const LgMenuItem(label: '用作出口', onPressed: _noop),
        LgMenuItem(
          label: 'RDP',
          onPressed: _noop,
          trailing: Builder(
            builder: (c) => LgIcon(
              LgIcons.edit,
              size: 18,
              color: LgTokens.of(c).colors.text2,
            ),
          ),
        ),
        const LgMenuGroup('设备'),
        LgMenuCheckItem(label: '始终经中继连接', value: false, onChanged: (_) {}),
        const LgMenuItem(label: '创建桌面快捷方式', onPressed: _noop),
        const LgMenuGroup('管理'),
        const LgMenuItem(label: '重命名', onPressed: _noop),
        const LgMenuItem(label: '移出收藏', onPressed: _noop),
        const LgMenuItem(label: '清除保存的密码', onPressed: _noop),
        const LgMenuGroup('危险操作'),
        const LgMenuItem(label: '删除', danger: true, onPressed: _noop),
      ], size: const Size(360, 700)),
    );
  // Menu row states, forced.
  for (final e in {'hover': _hover, 'focus': _focus}.entries) {
    list.add(
      Specimen(
        'menu-rows',
        'switch-${e.key}',
        const Size(380, 120),
        states: e.value,
        (_) => LgMenuPanel(
          width: 340,
          items: [
            LgMenuSwitchItem(
              label: '同步剪贴板',
              shortcut: 'Ctrl+Alt+Shift+S',
              value: true,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
  }
  for (final e in {'normal': <WidgetState>{}, 'hover': _hover, 'focus': _focus}.entries) {
    list.add(
      Specimen(
        'menu-rows',
        'slider-${e.key}',
        const Size(360, 100),
        states: e.value,
        (_) => LgMenuPanel(
          items: [
            LgMenuSliderItem(
              value: 3,
              min: 1,
              max: 10,
              step: 1,
              format: _int,
              semanticLabel: '数量',
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
  }
  list
    ..add(
      Specimen(
        'menu-rows',
        'slider-disabled',
        const Size(360, 100),
        (_) => const LgMenuPanel(
          items: [
            LgMenuSliderItem(
              value: 50,
              min: 0,
              max: 100,
              format: _pct,
              semanticLabel: '数量',
              onChanged: null,
            ),
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'menu-rows',
        'stepper',
        const Size(360, 200),
        (_) => LgMenuPanel(
          items: [
            LgMenuStepperItem(
              value: 2,
              min: 1,
              max: 4,
              decreaseLabel: '减少虚拟显示器',
              increaseLabel: '增加虚拟显示器',
              valueLabel: '虚拟显示器数量',
              onChanged: (_) {},
            ),
            const LgMenuDivider(),
            const LgMenuItem(label: '全部移除', onPressed: _noop),
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'menu-rows',
        'stepper-at-min',
        const Size(360, 100),
        (_) => LgMenuPanel(
          items: [
            LgMenuStepperItem(
              value: 0,
              min: 0,
              max: 4,
              decreaseLabel: '减少虚拟显示器',
              increaseLabel: '增加虚拟显示器',
              valueLabel: '虚拟显示器数量',
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'menu-rows',
        'display-map',
        const Size(360, 300),
        (_) => LgMenuPanel(
          items: [
            LgDisplayMap(
              current: 1,
              onSelect: (_) {},
              tiles: const [
                LgDisplayTile(
                  rect: Rect.fromLTWH(-1280, 200, 1280, 800),
                  label: '2',
                  semanticLabel: '显示器 2',
                ),
                LgDisplayTile(
                  rect: Rect.fromLTWH(0, 0, 1920, 1080),
                  label: '1',
                  semanticLabel: '显示器 1',
                ),
                LgDisplayTile(
                  rect: Rect.fromLTWH(1920, -300, 1080, 1920),
                  label: '3',
                  semanticLabel: '显示器 3',
                ),
              ],
            ),
            const LgMenuDivider(),
            LgMenuSwitchItem(label: '全部显示器', value: false, onChanged: (_) {}),
          ],
        ),
      ),
    );

  // Slider alone
  list
    ..add(
      Specimen(
        'slider',
        'values',
        const Size(420, 220),
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LgSlider(value: 0, onChanged: (_) {}),
            const SizedBox(height: LgSpace.s3),
            LgSlider(value: .4, onChanged: (_) {}),
            const SizedBox(height: LgSpace.s3),
            LgSlider(value: 1, onChanged: (_) {}),
            const SizedBox(height: LgSpace.s3),
            const LgSlider(value: .6, onChanged: null),
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'slider',
        'focus',
        const Size(420, 80),
        states: _focus,
        (_) => LgSlider(value: .4, onChanged: (_) {}),
      ),
    );

  // Device card -----------------------------------------------------------------
  const cardCell = Size(392, 144);
  Specimen card(
    String name,
    Widget Function(BuildContext) build, {
    Set<WidgetState> states = const {},
  }) => Specimen('device-card', name, cardCell, states: states, build);
  list
    ..add(
      card('normal', (c) => SizedBox(width: 360, child: _card(c, _devices[0], favorite: true, actions: true))),
    )
    ..add(
      card(
        'hover',
        (c) => SizedBox(width: 360, child: _card(c, _devices[0], favorite: true)),
        states: _hover,
      ),
    )
    ..add(
      card(
        'selected',
        (c) => SizedBox(
          width: 360,
          child: _card(c, _devices[0], favorite: true, selected: true),
        ),
      ),
    )
    ..add(
      card(
        'focus',
        (c) => SizedBox(width: 360, child: _card(c, _devices[0], favorite: true)),
        states: _focus,
      ),
    )
    ..add(
      card(
        'pressed',
        (c) => SizedBox(width: 360, child: _card(c, _devices[0], favorite: true)),
        states: _pressed,
      ),
    )
    ..add(
      card(
        'querying',
        (c) => SizedBox(
          width: 360,
          child: _card(
            c,
            _devices[0],
            favorite: true,
            status: LgDeviceStatus.querying,
          ),
        ),
      ),
    )
    ..add(
      card(
        'offline-marks',
        (c) => SizedBox(
          width: 360,
          child: _card(c, _devices[6], savedPassword: true, tags: const []),
        ),
      ),
    )
    ..add(
      card(
        'many-tags',
        (c) => SizedBox(
          width: 360,
          child: _card(c, _devices[7], tags: const [0, 1, 2], favorite: true),
        ),
      ),
    )
    ..add(
      card(
        'long-name-hover',
        (c) => SizedBox(
          width: 360,
          child: _card(
            c,
            _devices[1],
            name: '妈妈在客厅沙发旁边那台用了很多年的笔记本电脑',
            favorite: true,
            savedPassword: true,
          ),
        ),
        states: _hover,
      ),
    )
    ..add(
      card(
        'multi-select-off',
        (c) => SizedBox(
          width: 360,
          child: _card(c, _devices[3], tags: const [], picked: false),
        ),
      ),
    )
    ..add(
      card(
        'multi-select-on',
        (c) => SizedBox(
          width: 360,
          child: _card(c, _devices[0], favorite: true, picked: true),
        ),
      ),
    )
    ..add(
      card(
        'with-source',
        (c) => SizedBox(
          width: 360,
          child: _card(c, _devices[2], source: '收藏', tags: const []),
        ),
      ),
    )
    ..add(
      card(
        'skeleton',
        (c) => const SizedBox(width: 360, child: LgDeviceCardSkeleton()),
      ),
    );

  // Card grid
  Widget grid(BuildContext c, int count, {bool picked = false}) => LgDeviceCardGrid(
    semanticLabel: '最近连接的设备',
    children: [
      for (var i = 0; i < count; i++)
        _card(
          c,
          _devices[i % _devices.length],
          tags: i == 0 || i == 1
              ? const [0]
              : i == 2
              ? const [1]
              : i == 7
              ? const [1, 2]
              : const [],
          favorite: i == 0,
          savedPassword: i == 6,
          selected: !picked && i == 0,
          picked: picked ? i < 3 : null,
          actions: !picked,
        ),
    ],
  );
  list
    ..add(
      Specimen(
        'device-card-grid',
        'three-columns',
        const Size(1072, 420),
        (c) => SizedBox(width: wide, child: grid(c, 8)),
      ),
    )
    ..add(
      Specimen(
        'device-card-grid',
        'two-columns',
        const Size(712, 420),
        (c) => SizedBox(width: 680, child: grid(c, 6)),
      ),
    )
    ..add(
      Specimen(
        'device-card-grid',
        'one-column',
        const Size(352, 420),
        (c) => SizedBox(width: 320, child: grid(c, 3)),
      ),
    )
    ..add(
      Specimen(
        'device-card-grid',
        'multi-select',
        const Size(1072, 420),
        (c) => SizedBox(width: wide, child: grid(c, 8, picked: true)),
      ),
    )
    ..add(
      Specimen(
        'device-card-grid',
        'loading',
        const Size(1072, 260),
        (c) => SizedBox(
          width: wide,
          child: Semantics(
            label: '正在加载',
            child: LgDeviceCardGrid(
              children: [for (var i = 0; i < 6; i++) const LgDeviceCardSkeleton()],
            ),
          ),
        ),
      ),
    );

  // Device list view ---------------------------------------------------------
  Specimen table(
    String name,
    Widget Function(BuildContext) build, {
    Size size = const Size(1072, 460),
    Set<WidgetState> states = const {},
  }) => Specimen('device-table', name, size, states: states, build);
  list
    ..add(
      table(
        'sorted-by-name',
        (c) => SizedBox(width: wide, child: _table(c, selected: 0)),
      ),
    )
    ..add(
      table(
        'sorted-descending',
        (c) => SizedBox(
          width: wide,
          child: _table(c, sort: const LgTableSort(LgDeviceColumn.status, ascending: false), count: 4),
        ),
        size: const Size(1072, 260),
      ),
    )
    ..add(
      table(
        'unsorted',
        (c) => SizedBox(width: wide, child: _table(c, sort: null, count: 4)),
        size: const Size(1072, 260),
      ),
    )
    ..add(
      table(
        'multi-select',
        (c) => SizedBox(width: wide, child: _table(c, picked: true, count: 6)),
        size: const Size(1072, 380),
      ),
    )
    ..add(
      table(
        'with-source',
        (c) => SizedBox(width: wide, child: _table(c, sort: null, source: true, count: 4)),
        size: const Size(1072, 260),
      ),
    )
    ..add(
      table(
        'row-hover',
        (c) => SizedBox(width: wide, child: _table(c, sort: null, count: 2)),
        size: const Size(1072, 190),
        states: _hover,
      ),
    )
    ..add(
      table(
        'row-focus',
        (c) => SizedBox(width: wide, child: _table(c, sort: null, count: 2)),
        size: const Size(1072, 190),
        states: _focus,
      ),
    )
    ..add(
      table(
        'narrow',
        (c) => SizedBox(width: 760, child: _table(c, count: 3)),
        size: const Size(792, 230),
      ),
    );

  // Device page parts --------------------------------------------------------
  list
    ..add(
      Specimen(
        'list-chrome',
        'toolbar-recent',
        const Size(1072, 76),
        (_) => SizedBox(width: wide, child: _listToolbar()),
      ),
    )
    ..add(
      Specimen(
        'list-chrome',
        'toolbar-favorites',
        const Size(1072, 76),
        (_) => SizedBox(
          width: wide,
          child: _listToolbar(selected: 1, sort: true),
        ),
      ),
    )
    ..add(
      Specimen(
        'list-chrome',
        'toolbar-view-open',
        const Size(1072, 76),
        (_) => SizedBox(
          width: wide,
          child: _listToolbar(viewOpen: true),
        ),
      ),
    )
    ..add(
      Specimen(
        'list-chrome',
        'toolbar-multi-on',
        const Size(1072, 76),
        (_) => SizedBox(
          width: wide,
          child: _listToolbar(multi: true, sort: true, refresh: true),
        ),
      ),
    )
    ..add(
      Specimen(
        'list-chrome',
        'toolbar-narrow',
        const Size(560, 76),
        (_) => SizedBox(width: 528, child: _listToolbar(selected: 2)),
      ),
    );
  for (final e in _states.entries) {
    list.add(
      Specimen(
        'list-tool',
        e.key,
        const Size(160, 76),
        states: e.value,
        (_) => const LgListToolButton(
          icon: LgIcons.select,
          label: '多选',
          onPressed: _noop,
        ),
      ),
    );
  }
  list
    ..add(
      Specimen(
        'list-tool',
        'active',
        const Size(160, 76),
        (_) => const LgListToolButton(
          icon: LgIcons.select,
          label: '多选',
          onPressed: _noop,
          active: true,
        ),
      ),
    )
    ..add(
      Specimen(
        'list-tool',
        'disabled',
        const Size(160, 76),
        (_) => const LgListToolButton(
          icon: LgIcons.sort,
          label: '排序',
          onPressed: null,
        ),
      ),
    )
    ..add(
      Specimen(
        'category-tabs',
        'states',
        const Size(520, 76),
        (_) => LgCategoryTabs<int>(
          categories: const [
            LgCategory(0, '最近'),
            LgCategory(1, '收藏'),
            LgCategory(2, '局域网'),
          ],
          selected: 1,
          onSelect: (_) {},
        ),
      ),
    )
    ..add(
      Specimen(
        'category-tabs',
        'hover',
        const Size(520, 76),
        states: _hover,
        (_) => LgCategoryTabs<int>(
          categories: const [
            LgCategory(0, '最近'),
            LgCategory(1, '收藏'),
            LgCategory(2, '局域网'),
          ],
          selected: 1,
          onSelect: (_) {},
        ),
      ),
    )
    ..add(
      Specimen(
        'category-tabs',
        'focus',
        const Size(520, 76),
        states: _focus,
        (_) => LgCategoryTabs<int>(
          categories: const [
            LgCategory(0, '最近'),
            LgCategory(1, '收藏'),
            LgCategory(2, '局域网'),
          ],
          selected: 0,
          onSelect: (_) {},
        ),
      ),
    );

  // Selection bar, notes, empty states
  List<LgSelectionAction> pickActions(bool enabled) => [
    LgSelectionAction(
      label: '删除',
      icon: LgIcons.trash,
      danger: true,
      onPressed: enabled ? _noop : null,
    ),
    LgSelectionAction(
      label: '加入收藏',
      icon: LgIcons.star,
      onPressed: enabled ? _noop : null,
    ),
  ];
  list
    ..add(
      Specimen(
        'selection-bar',
        'three-picked',
        const Size(1072, 76),
        (_) => SizedBox(
          width: wide,
          child: LgSelectionBar(
            actions: pickActions(true),
            countText: '已选择 3 台',
            selectAllLabel: '全选',
            onSelectAll: _noop,
            doneLabel: '完成',
            onDone: _noop,
            semanticLabel: '多选',
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'selection-bar',
        'none-picked',
        const Size(1072, 76),
        (_) => SizedBox(
          width: wide,
          child: LgSelectionBar(
            actions: pickActions(false),
            countText: '已选择 0 台',
            selectAllLabel: '全选',
            onSelectAll: _noop,
            doneLabel: '完成',
            onDone: _noop,
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'selection-bar',
        'narrow',
        const Size(560, 120),
        (_) => SizedBox(
          width: 528,
          child: LgSelectionBar(
            actions: [
              ...pickActions(true),
              const LgSelectionAction(
                label: '加入地址簿',
                icon: LgIcons.book,
                onPressed: _noop,
              ),
            ],
            countText: '已选择 3 台',
            selectAllLabel: '全选',
            onSelectAll: _noop,
            doneLabel: '完成',
            onDone: _noop,
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'list-note',
        'over-1000',
        const Size(1072, 70),
        (_) => const SizedBox(
          width: wide,
          child: LgListNote('仅显示前 1000 台设备，可使用搜索缩小范围'),
        ),
      ),
    )
    ..add(
      Specimen(
        'empty-state',
        'favorites',
        const Size(1072, 220),
        (_) => const SizedBox(
          width: wide,
          child: LgEmptyState('暂无收藏的设备', icon: LgIcons.star),
        ),
      ),
    )
    ..add(
      Specimen(
        'empty-state',
        'lan',
        const Size(1072, 220),
        (_) => const SizedBox(
          width: wide,
          child: LgEmptyState('未在局域网中发现设备', icon: LgIcons.wifi),
        ),
      ),
    );

  // Local area
  list
    ..add(
      Specimen(
        'local-notice',
        'error',
        const Size(280, 140),
        (_) => const SizedBox(
          width: 208,
          child: LgLocalNotice(
            tone: LgTone.error,
            text: '无法写入配置文件：拒绝访问（错误 5）。',
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'local-notice',
        'warning-with-action',
        const Size(280, 220),
        (_) => const SizedBox(
          width: 208,
          child: LgLocalNotice(
            tone: LgTone.warning,
            text: '服务已停止，无法接受连接。',
            actionLabel: '启动服务',
            onAction: _noop,
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'local-notice',
        'info',
        const Size(280, 140),
        (_) => const SizedBox(
          width: 208,
          child: LgLocalNotice(
            tone: LgTone.info,
            text: '当前以免安装方式运行。',
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'controlled-note',
        'with-view',
        const Size(280, 100),
        (_) => const SizedBox(
          width: 208,
          child: LgControlledNote(
            text: '正在被远程控制\n（2 个会话）',
            viewLabel: '查看',
            onView: _noop,
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'controlled-note',
        'without-view',
        const Size(280, 100),
        (_) => const SizedBox(
          width: 208,
          child: LgControlledNote(text: '正在被远程控制\n（1 个会话）'),
        ),
      ),
    )
    ..add(
      Specimen(
        'blocked-overlay',
        'blocked',
        const Size(720, 330),
        padding: 0,
        (c) => _pageStage(
          const Size(720, 330),
          (c) => LgBlockedOverlay(
            blocked: true,
            message: '远程控制期间无法修改设置',
            child: SizedBox(
              width: 700,
              child: LgDeviceCardGrid(
                children: [
                  for (var i = 0; i < 4; i++) _card(c, _devices[i]),
                ],
              ),
            ),
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'blocked-overlay',
        'free',
        const Size(720, 330),
        padding: 0,
        (c) => _pageStage(
          const Size(720, 330),
          (c) => LgBlockedOverlay(
            blocked: false,
            message: '远程控制期间无法修改设置',
            child: SizedBox(
              width: 700,
              child: LgDeviceCardGrid(
                children: [
                  for (var i = 0; i < 4; i++) _card(c, _devices[i]),
                ],
              ),
            ),
          ),
        ),
      ),
    );

  // The page together, for the overall impression
  list
    ..add(
      Specimen(
        'device-page',
        'cards-hover',
        const Size(1072, 540),
        padding: 0,
        (_) => _pageStage(
          const Size(1072, 540),
          (c) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _connectBar('', focused: false),
              const SizedBox(height: LgSpace.s6),
              _listToolbar(),
              const SizedBox(height: LgSpace.s5),
              Expanded(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: LgDeviceCardGrid(
                    children: [
                      for (var i = 0; i < 6; i++)
                        _card(
                          c,
                          _devices[i],
                          tags: i < 2 ? const [0] : i == 2 ? const [1] : const [],
                          favorite: i == 0,
                          savedPassword: i == 6,
                          selected: i == 0,
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
        'device-page',
        'multi-select',
        const Size(1072, 540),
        padding: 0,
        (_) => _pageStage(
          const Size(1072, 540),
          (c) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _connectBar('', focused: false),
              const SizedBox(height: LgSpace.s6),
              LgSelectionBar(
                actions: pickActions(true),
                countText: '已选择 3 台',
                selectAllLabel: '全选',
                onSelectAll: _noop,
                doneLabel: '完成',
                onDone: _noop,
              ),
              const SizedBox(height: LgSpace.s4),
              Expanded(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: LgDeviceCardGrid(
                    children: [
                      for (var i = 0; i < 6; i++)
                        _card(
                          c,
                          _devices[i],
                          tags: i < 2 ? const [0] : i == 2 ? const [1] : const [],
                          picked: i < 3,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

  // Notices with buttons ---------------------------------------------------------
  const noticeStage = Size(560, 420);
  Specimen notices(String name, List<LgNotice> items) => Specimen(
    'notice-stack',
    name,
    noticeStage,
    padding: 0,
    (_) => _stage(
      noticeStage,
      (_) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(LgSpace.s4),
          child: LgNoticeStack(
            notices: items,
            dismissLabel: '关闭',
            onDismiss: (_) {},
          ),
        ),
      ),
      picture: true,
    ),
  );
  LgNotice printAsk({bool checked = false}) => LgNotice(
    id: 'print',
    text: '收到来自远程设备的打印任务',
    icon: LgIcons.printer,
    actions: const [
      LgNoticeAction('使用默认打印机', _noop),
      LgNoticeAction('选择打印机', _noop),
      LgNoticeAction('不打印', _noop, secondary: true),
    ],
    check: LgNoticeCheck(label: '记住此选择', value: checked, onChanged: (_) {}),
  );
  list
    ..add(notices('print-ask', [printAsk()]))
    ..add(notices('print-ask-remembered', [printAsk(checked: true)]))
    ..add(
      notices('elevation-ask', const [
        LgNotice(
          id: 'elevate',
          text: '需要更高权限才能操作远程设备的这个窗口',
          tone: LgTone.warning,
          actions: [LgNoticeAction('请求提升权限', _noop)],
        ),
        LgNotice(
          id: 'elevating',
          text: '正在等待远程设备同意提升权限…',
          tone: LgTone.info,
          actions: [LgNoticeAction('取消', _noop, secondary: true)],
        ),
      ]),
    )
    ..add(
      notices('recording', const [
        LgNotice(
          id: 'rec',
          text: '已开始自动录制',
          icon: LgIcons.record,
          tone: LgTone.info,
          actions: [LgNoticeAction('停止', _noop)],
        ),
      ]),
    )
    ..add(
      notices('screenshot-failed', const [
        LgNotice(
          id: 'shot-fail',
          title: '截图失败',
          text: '远程设备未能返回画面，请稍后再试。',
          tone: LgTone.error,
          actions: [LgNoticeAction('重试', _noop)],
        ),
      ]),
    )
    ..add(
      notices('keep-until-answered', [
        printAsk(),
        const LgNotice(
          id: 'switch',
          text: '隐私模式需要先切换到显示器 1',
          tone: LgTone.warning,
          actions: [LgNoticeAction('切换到显示器 1', _noop)],
        ),
        _screenshotNotice(),
      ]),
    );

  // Password dialog --------------------------------------------------------------
  const pwLabels = LgPasswordDialogLabels(
    title: '设置固定密码',
    passwordLabel: '密码',
    passwordPlaceholder: '输入密码',
    confirmLabel: '确认密码',
    confirmPlaceholder: '再次输入密码',
    showPassword: '显示密码',
    hidePassword: '隐藏密码',
    strength: '密码强度',
    ruleMet: '已满足',
    ruleUnmet: '未满足',
    cancel: '取消',
    confirm: '确定',
    remove: '移除',
  );
  Specimen password(
    String name, {
    String text = '',
    String confirm = '',
    int strength = 0,
    List<bool> met = const [false, false, false, false],
    String? note,
    String? error,
    String? confirmError,
    bool ready = false,
    bool remove = false,
  }) => Specimen(
    'password-dialog',
    name,
    const Size(1280, 600),
    padding: 0,
    (_) => _dialogStage(
      LgPasswordDialog(
        labels: pwLabels,
        passwordController: TextEditingController(text: text),
        confirmController: TextEditingController(text: confirm),
        rules: [
          LgPasswordRule('包含数字', met[0]),
          LgPasswordRule('包含大写字母', met[1]),
          LgPasswordRule('包含小写字母', met[2]),
          LgPasswordRule('至少 8 个字符', met[3]),
        ],
        strength: strength,
        note: note,
        error: error,
        confirmError: confirmError,
        onCancel: _noop,
        onConfirm: ready ? _noop : null,
        onRemove: remove ? _noop : null,
      ),
      height: 600,
    ),
  );
  list
    ..add(password('empty'))
    ..add(
      password(
        'already-set',
        note: '已设置的密码不会显示',
        remove: true,
      ),
    )
    ..add(
      password(
        'typing',
        text: 'abc12',
        strength: 1,
        met: const [true, false, true, false],
      ),
    )
    ..add(
      password(
        'mismatch',
        text: 'Abcdef12',
        confirm: 'Abcdef13',
        strength: 4,
        met: const [true, true, true, true],
        confirmError: '两次输入的密码不一致',
        ready: true,
      ),
    )
    ..add(
      password(
        'save-failed',
        text: 'Abcdef12',
        confirm: 'Abcdef12',
        strength: 4,
        met: const [true, true, true, true],
        error: '无法保存密码',
        ready: true,
      ),
    );

  // Route details ---------------------------------------------------------------
  Specimen details(String name, LgRouteDetails d, {Size? size}) => Specimen(
    'route-details',
    name,
    size ?? Size(d.width + 32, 880),
    (_) => d,
  );
  list
    ..add(details('relay', _details()))
    ..add(details('relay-quality-on', _details(qualityOn: true)))
    ..add(details('direct', _details(route: LgRoute.direct)))
    ..add(
      details(
        'direct-unencrypted',
        _details(route: LgRoute.direct, encrypted: false),
      ),
    )
    ..add(details('no-route-rows', _details(noRoute: true)))
    ..add(details('three-lines', _details(withPeers: true), size: const Size(512, 960)))
    ..add(
      details(
        'scrolls-in-low-window',
        _details(maxHeight: 420),
        size: const Size(432, 456),
      ),
    )
    ..add(
      Specimen(
        'sparkline',
        'one-line',
        const Size(380, 170),
        (_) => SizedBox(width: 340, child: _spark()),
      ),
    )
    ..add(
      Specimen(
        'sparkline',
        'three-lines-with-gap',
        const Size(380, 170),
        (_) => SizedBox(
          width: 340,
          child: LgSparkline(
            series: [
              LgSparkSeries([
                for (var i = 0; i < 31; i++) i > 10 && i < 15 ? null : 20 + (i % 7) * 3,
              ], LgLineStyle.primary),
              LgSparkSeries([
                for (var i = 0; i < 31; i++) i > 10 && i < 15 ? null : 9 + (i % 5) * 2,
              ], LgLineStyle.accent),
              LgSparkSeries([
                for (var i = 0; i < 31; i++) i > 10 && i < 15 ? null : 11 + (i % 4) * 2,
              ], LgLineStyle.relay),
            ],
            unit: 'ms',
            timeLabels: const ['60 秒前', '30 秒前', '现在'],
            semanticLabel: '近 60 秒延迟',
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'sparkline',
        'line-keys',
        const Size(240, 120),
        (_) => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LgLineKey(LgLineStyle.primary),
            SizedBox(height: LgSpace.s3),
            LgLineKey(LgLineStyle.accent),
            SizedBox(height: LgSpace.s3),
            LgLineKey(LgLineStyle.relay),
          ],
        ),
      ),
    );

  // Chat -----------------------------------------------------------------------
  list
    ..add(
      Specimen('chat-panel', 'messages', const Size(392, 380), (_) => _chatPanel()),
    )
    ..add(
      Specimen(
        'chat-panel',
        'typing',
        const Size(392, 380),
        (_) => _chatPanel(draft: '收到，马上处理'),
      ),
    )
    ..add(
      Specimen(
        'chat-panel',
        'empty',
        const Size(392, 380),
        (_) => _chatPanel(messages: const [], empty: '暂无消息'),
      ),
    )
    ..add(
      Specimen(
        'chat-panel',
        'long-messages',
        const Size(392, 380),
        (_) => _chatPanel(
          messages: const [
            LgChatMessage(
              text: '这台电脑的打印机驱动好像坏了，我先重装一下驱动，再试着打印一份测试页给你看，你看到测试页以后告诉我。',
              time: '10:24',
              mine: true,
            ),
            LgChatMessage(text: '好的', time: '10:25', mine: false),
            LgChatMessage(text: '我这边看到了，谢谢你！', time: '10:31', mine: false),
          ],
        ),
      ),
    );

  // Toolbar of M2b -----------------------------------------------------------------
  const top = LgToolbarPlacement(LgToolbarDock.top);
  list
    ..add(
      Specimen(
        'toolbar-m2b',
        'default-with-grip',
        const Size(1280, 200),
        padding: 0,
        (_) => _placed(top, _toolbar2(), size: const Size(1280, 200)),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'display-flat',
        const Size(1280, 200),
        padding: 0,
        (_) => _placed(
          top,
          _toolbar2(display: true, displayFlat: true),
          size: const Size(1280, 200),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'collapsed-with-switch',
        const Size(640, 160),
        padding: 0,
        (_) => _placed(
          top,
          _toolbar2(collapsed: true, display: true, route: LgRoute.direct),
          size: const Size(640, 160),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'collapsed-relay',
        const Size(640, 160),
        padding: 0,
        (_) => _placed(top, _toolbar2(collapsed: true), size: const Size(640, 160)),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'dragging-with-preview',
        const Size(1280, 420),
        padding: 0,
        (_) => _lifted(
          top,
          _toolbar2(),
          preview: const LgToolbarPlacement(LgToolbarDock.left, .5),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'dock-left',
        const Size(1280, 520),
        padding: 0,
        (_) => _placed(
          const LgToolbarPlacement(LgToolbarDock.left, .3),
          _toolbar2(dock: LgToolbarDock.left),
          size: const Size(1280, 520),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'dock-right',
        const Size(1280, 520),
        padding: 0,
        (_) => _placed(
          const LgToolbarPlacement(LgToolbarDock.right, .3),
          _toolbar2(dock: LgToolbarDock.right, route: LgRoute.direct),
          size: const Size(1280, 520),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'dock-bottom',
        const Size(1280, 260),
        padding: 0,
        (_) => _placed(
          const LgToolbarPlacement(LgToolbarDock.bottom, .5),
          _toolbar2(dock: LgToolbarDock.bottom),
          size: const Size(1280, 260),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'collapsed-left',
        const Size(520, 300),
        padding: 0,
        (_) => _placed(
          const LgToolbarPlacement(LgToolbarDock.left, .3),
          _toolbar2(
            dock: LgToolbarDock.left,
            collapsed: true,
            display: true,
            route: LgRoute.direct,
          ),
          size: const Size(520, 300),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'collapsed-bottom',
        const Size(640, 180),
        padding: 0,
        (_) => _placed(
          const LgToolbarPlacement(LgToolbarDock.bottom, .5),
          _toolbar2(dock: LgToolbarDock.bottom, collapsed: true),
          size: const Size(640, 180),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'fullscreen-with-grip',
        const Size(1280, 200),
        padding: 0,
        (_) => _placed(
          top,
          _toolbar2(fullscreen: true, display: true),
          size: const Size(1280, 200),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'narrow-folds-into-more',
        const Size(960, 200),
        padding: 0,
        (_) => _placed(
          top,
          _toolbar2(display: true),
          size: const Size(960, 200),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'narrower-folds-more',
        const Size(840, 200),
        padding: 0,
        (_) => _placed(
          top,
          _toolbar2(display: true),
          size: const Size(840, 200),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'english-narrow',
        const Size(960, 200),
        padding: 0,
        (_) => _placed(
          top,
          _toolbar2(display: true, english: true),
          size: const Size(960, 200),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'voice-pending',
        const Size(1280, 200),
        padding: 0,
        (_) => _placed(
          top,
          _toolbar2(chat: LgToolbarMenuState.pending),
          size: const Size(1280, 200),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'voice-live',
        const Size(1280, 200),
        padding: 0,
        (_) => _placed(
          top,
          _toolbar2(chat: LgToolbarMenuState.live),
          size: const Size(1280, 200),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'route-details-open',
        const Size(1280, 200),
        padding: 0,
        (_) => _placed(
          top,
          _toolbar2(routeOpen: true),
          size: const Size(1280, 200),
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-m2b',
        'unencrypted-direct',
        const Size(1280, 200),
        padding: 0,
        (_) => _placed(
          top,
          _toolbar2(route: LgRoute.direct, encrypted: false),
          size: const Size(1280, 200),
        ),
      ),
    );
  // The grip and the new buttons on their own
  for (final e in _states.entries) {
    list.add(
      Specimen(
        'toolbar-grip',
        e.key,
        const Size(120, 76),
        states: e.value,
        (_) => LgToolbarDragScope(
          dragging: false,
          onStart: (_) {},
          onUpdate: (_) {},
          onEnd: _noop,
          onNudge: (_) {},
          child: const LgToolbarGrip(label: '移动工具栏'),
        ),
      ),
    );
  }
  for (final e in _states.entries) {
    list.add(
      Specimen(
        'toolbar-text-button',
        e.key,
        const Size(120, 76),
        states: e.value,
        (_) => const LgToolbarTextButton(
          label: '2',
          semanticLabel: '显示器 2',
          onPressed: _noop,
        ),
      ),
    );
  }
  list
    ..add(
      Specimen(
        'toolbar-text-button',
        'selected',
        const Size(120, 76),
        (_) => const LgToolbarTextButton(
          label: '1',
          semanticLabel: '显示器 1',
          selected: true,
          onPressed: _noop,
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-route-button',
        'relay',
        const Size(220, 76),
        (_) => const LgToolbarRouteButton(
          route: LgRoute.relay,
          label: '经中继',
          onPressed: _noop,
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-route-button',
        'direct-open',
        const Size(220, 76),
        (_) => const LgToolbarRouteButton(
          route: LgRoute.direct,
          label: '直连',
          open: true,
          onPressed: _noop,
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-route-button',
        'unencrypted',
        const Size(280, 76),
        (_) => const LgToolbarRouteButton(
          route: LgRoute.direct,
          label: '直连',
          encrypted: false,
          unencryptedLabel: '未加密',
          onPressed: _noop,
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-menu-button',
        'pending',
        const Size(220, 76),
        (_) => LgToolbarMenuButton(
          label: '等待接听…',
          icon: LgIcons.chat,
          items: _viewMenu(),
          state: LgToolbarMenuState.pending,
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-menu-button',
        'live',
        const Size(220, 76),
        (_) => LgToolbarMenuButton(
          label: '通话中',
          icon: LgIcons.chat,
          items: _viewMenu(),
          state: LgToolbarMenuState.live,
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-menu-button',
        'with-badge',
        const Size(220, 76),
        (_) => LgToolbarMenuButton(
          label: '聊天',
          icon: LgIcons.chat,
          items: _viewMenu(),
          badge: 3,
        ),
      ),
    );

  // Detail mode of the marks that change with it
  // Over the picture -------------------------------------------------------------
  const canvasStage = Size(640, 240);
  list
    ..add(
      Specimen(
        'canvas-parts',
        'quality-overlay',
        canvasStage,
        padding: 0,
        (_) => _stage(
          canvasStage,
          (_) => const Padding(
            padding: EdgeInsets.all(LgSpace.s4),
            child: Align(
              alignment: Alignment.topLeft,
              child: LgQualityOverlay(
                semanticLabel: '质量数据',
                rows: [
                  ('速度', '1.2 MB/s'),
                  ('帧率', '30'),
                  ('延迟', '45 ms'),
                  ('目标码率', '2000 kb/s'),
                  ('编码', 'H264'),
                  ('色度', '4:2:0'),
                ],
              ),
            ),
          ),
          picture: true,
        ),
      ),
    )
    ..add(
      Specimen(
        'canvas-parts',
        'relative-mouse-hint',
        canvasStage,
        padding: 0,
        (_) => _stage(
          canvasStage,
          (_) => const Padding(
            padding: EdgeInsets.all(LgSpace.s4),
            child: Align(
              alignment: Alignment.topCenter,
              child: LgCanvasHint(text: '按 Ctrl+Alt 退出鼠标锁定'),
            ),
          ),
          picture: true,
        ),
      ),
    )
    ..add(
      Specimen(
        'canvas-parts',
        'android-nav-bar',
        canvasStage,
        padding: 0,
        (_) => _stage(
          canvasStage,
          (_) => Padding(
            padding: const EdgeInsets.all(LgSpace.s4),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: LgAndroidNavBar(
                backLabel: '返回',
                homeLabel: '主屏幕',
                recentsLabel: '最近任务',
                dragLabel: '移动导航键',
                onBack: _noop,
                onHome: _noop,
                onRecents: _noop,
                onDrag: (_) {},
              ),
            ),
          ),
          picture: true,
        ),
      ),
    );
  return list;
}
