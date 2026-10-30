// Component gallery (docs/新界面/03-实施方案.md §4.6): every component and
// state in light / dark × compact / detail.
//
//   flutter run -t lib/gallery_main.dart -d windows
//
// With --dart-define=LG_GALLERY_EXPORT=<dir> it renders each component state
// at a fixed size to <dir>/<section>_<state>_<theme>-<mode>.png and exits;
// used to put the components next to the mockups (03 §8.4).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hbb/leapgate/identity_color.dart';

import 'icons/lg_icon.dart';
import 'theme/lg_theme.dart';
import 'theme/lg_tokens.dart';
import 'widgets/lg_banner.dart';
import 'widgets/lg_button.dart';
import 'widgets/lg_connect_box.dart';
import 'widgets/lg_connection_panel.dart';
import 'widgets/lg_device.dart';
import 'widgets/lg_feedback.dart';
import 'widgets/lg_menu.dart';
import 'widgets/lg_panel_inputs.dart';
import 'widgets/lg_password_row.dart';
import 'widgets/lg_pressable.dart';
import 'widgets/lg_selection.dart';
import 'widgets/lg_session_toolbar.dart';
import 'widgets/lg_status.dart';
import 'widgets/lg_tab_tip.dart';
import 'widgets/lg_text_field.dart';
import 'widgets/lg_title_bar.dart';
import 'widgets/lg_tooltip.dart';

const _exportDir = String.fromEnvironment('LG_GALLERY_EXPORT');

void main() =>
    runApp(GalleryApp(exportDir: _exportDir.isEmpty ? null : _exportDir));

class GalleryVariant {
  const GalleryVariant(this.brightness, this.mode);

  final Brightness brightness;
  final LgMode mode;

  String get name => '${brightness.name}-${mode.name}';
}

const galleryVariants = [
  GalleryVariant(Brightness.light, LgMode.compact),
  GalleryVariant(Brightness.light, LgMode.detail),
  GalleryVariant(Brightness.dark, LgMode.compact),
  GalleryVariant(Brightness.dark, LgMode.detail),
];

/// One component state, rendered at [size] (padding included).
class Specimen {
  const Specimen(
    this.section,
    this.name,
    this.size,
    this.builder, {
    this.states = const {},
    this.padding = 16,
  });

  final String section;
  final String name;
  final Size size;
  final WidgetBuilder builder;

  /// Interaction states forced on the components (hover, pressed, focus).
  final Set<WidgetState> states;
  final double padding;

  String fileName(GalleryVariant v) => '${section}_${name}_${v.name}.png';
}

const _hover = {WidgetState.hovered};
const _pressed = {WidgetState.pressed};
const _focus = {WidgetState.focused};
const _states = <String, Set<WidgetState>>{
  'normal': {},
  'hover': _hover,
  'pressed': _pressed,
  'focus': _focus,
};

void _noop() {}

const _labels = LgTitleBarLabels(
  home: '主页',
  newTab: '新建连接',
  allTabs: '全部标签',
  closeTab: '关闭标签',
  minimize: '最小化',
  maximize: '最大化',
  restore: '还原',
  close: '关闭',
);

Widget _tabTooltip(
  String name,
  String id,
  List<(String, Widget)> views,
) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Builder(
      builder: (context) => Text(
        name,
        style: LgTokens.of(context).text.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    Builder(
      builder: (context) =>
          Text(id, style: TextStyle(color: LgTokens.of(context).colors.text2)),
    ),
    for (final (view, mark) in views)
      Padding(
        padding: const EdgeInsets.only(top: LgSpace.s1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 64,
              child: Builder(
                builder: (context) => Text(
                  view,
                  style: TextStyle(color: LgTokens.of(context).colors.text2),
                ),
              ),
            ),
            const SizedBox(width: LgSpace.s4),
            mark,
          ],
        ),
      ),
  ],
);

List<LgSessionTab> _sessions({int count = 4}) {
  const relay = LgRouteMark(route: LgRoute.relay, label: '经中继');
  final all = <LgSessionTab>[
    const LgSessionTab(
      name: '老王的 MacBook',
      identity: 3,
      status: LgStatusText(LgStatus.connecting, '正在连接…'),
    ),
    const LgSessionTab(
      name: '书房台式机',
      identity: 5,
      status: LgRouteMark(route: LgRoute.direct, label: '直连'),
    ),
    LgSessionTab(
      name: '妈妈的笔记本',
      identity: 4,
      status: relay,
      tooltip: _tabTooltip('妈妈的笔记本', '234 567 891', [('远程桌面', relay)]),
    ),
    const LgSessionTab(
      name: '工作室绘图电脑',
      identity: 2,
      status: LgRouteMark(
        route: LgRoute.direct,
        label: '直连',
        encrypted: false,
        unencryptedLabel: '未加密',
        worstOnly: true,
      ),
    ),
    const LgSessionTab(
      name: '客厅迷你主机',
      identity: 6,
      status: LgStatusText(LgStatus.warning, '已中断'),
    ),
    const LgSessionTab(
      name: '办公室电脑',
      identity: 2,
      status: LgStatusText(LgStatus.warning, '连接失败'),
    ),
    const LgSessionTab(
      name: '爸爸的台式机',
      identity: 3,
      status: LgStatusText(LgStatus.offline, '已断开'),
      disconnected: true,
    ),
    const LgSessionTab(
      name: '备用手机',
      identity: 0,
      status: LgRouteMark(route: LgRoute.direct, label: '直连'),
      unread: 2,
    ),
  ];
  return all.take(count).toList();
}

Widget _titleBar({int count = 4, int selected = 0, bool maximized = false}) =>
    Builder(
      builder: (context) => ColoredBox(
        color: LgTokens.of(context).colors.bg,
        child: LgTitleBar(
          labels: _labels,
          sessions: _sessions(count: count),
          selected: selected,
          homeBadge: 1,
          maximized: maximized,
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
    );

List<Widget> _menuItems() => [
  const LgMenuGroup('显示'),
  const LgMenuItem(label: '适应窗口', checked: true, onPressed: _noop),
  const LgMenuItem(label: '原始大小', checked: false, onPressed: _noop),
  const LgMenuItem(
    label: '自定义',
    checked: false,
    hint: '5%~1000%',
    onPressed: _noop,
  ),
  const LgMenuGroup('操作'),
  const LgMenuItem(label: '文件传输', icon: LgIcons.files, onPressed: _noop),
  const LgMenuItem(
    label: '这是一个很长很长的菜单项名称，放不下时省略并在悬停时显示全文',
    icon: LgIcons.note,
    onPressed: _noop,
  ),
  const LgSubmenu(
    label: '显示器',
    icon: LgIcons.displays,
    items: [
      LgMenuItem(label: '显示器 1', checked: true, onPressed: _noop),
      LgMenuItem(label: '显示器 2', checked: false, onPressed: _noop),
    ],
  ),
  const LgMenuItem(label: '交换控制方向', icon: LgIcons.forward, onPressed: null),
  const LgMenuItem(
    label: '断开',
    icon: LgIcons.power,
    danger: true,
    onPressed: _noop,
  ),
];

List<Specimen> buildSpecimens() {
  final list = <Specimen>[];
  const btn = Size(220, 76);
  for (final kind in LgButtonKind.values) {
    for (final e in _states.entries) {
      list.add(
        Specimen(
          'button',
          '${kind.name}-${e.key}',
          btn,
          states: e.value,
          (_) => LgButton(label: '连接', kind: kind, onPressed: _noop),
        ),
      );
    }
    list.add(
      Specimen(
        'button',
        '${kind.name}-disabled',
        btn,
        (_) => LgButton(label: '连接', kind: kind, onPressed: null),
      ),
    );
  }
  list
    ..add(
      Specimen(
        'button',
        'primary-large',
        btn,
        (_) => const LgButton(
          label: '连接',
          kind: LgButtonKind.primary,
          large: true,
          onPressed: _noop,
        ),
      ),
    )
    ..add(
      Specimen(
        'button',
        'secondary-large',
        btn,
        (_) => const LgButton(label: '取消', large: true, onPressed: _noop),
      ),
    )
    ..add(
      Specimen(
        'button',
        'secondary-icon',
        btn,
        (_) => const LgButton(
          label: '文件传输',
          icon: LgIcons.files,
          onPressed: _noop,
        ),
      ),
    );

  for (final e in _states.entries) {
    list.add(
      Specimen(
        'icon-button',
        e.key,
        const Size(80, 76),
        states: e.value,
        (_) => const LgIconButton(
          icon: LgIcons.copy,
          label: '复制',
          onPressed: _noop,
        ),
      ),
    );
  }
  list.add(
    Specimen(
      'icon-button',
      'disabled',
      const Size(80, 76),
      (_) =>
          const LgIconButton(icon: LgIcons.copy, label: '复制', onPressed: null),
    ),
  );

  const field = Size(380, 120);
  list
    ..add(
      Specimen(
        'text-field',
        'placeholder',
        field,
        (_) => const LgTextField(placeholder: '输入 ID 或搜索设备'),
      ),
    )
    ..add(
      Specimen(
        'text-field',
        'filled',
        field,
        (_) =>
            LgTextField(controller: TextEditingController(text: '234 567 891')),
      ),
    )
    ..add(
      Specimen(
        'text-field',
        'focus',
        field,
        states: _focus,
        (_) =>
            LgTextField(controller: TextEditingController(text: '234 567 891')),
      ),
    )
    ..add(
      Specimen(
        'text-field',
        'error',
        field,
        (_) => LgTextField(
          controller: TextEditingController(text: 'password'),
          obscureText: true,
          errorText: '密码错误',
          trailing: const LgIcon(LgIcons.eye, size: 22),
        ),
      ),
    )
    ..add(
      Specimen(
        'text-field',
        'disabled',
        field,
        (_) => LgTextField(
          controller: TextEditingController(text: '234 567 891'),
          enabled: false,
        ),
      ),
    );

  const small = Size(240, 76);
  for (final on in [false, true]) {
    for (final e in _states.entries) {
      list.add(
        Specimen(
          'switch',
          '${on ? 'on' : 'off'}-${e.key}',
          small,
          states: e.value,
          (_) => LgSwitch(value: on, onChanged: (_) {}),
        ),
      );
      list.add(
        Specimen(
          'checkbox',
          '${on ? 'on' : 'off'}-${e.key}',
          small,
          states: e.value,
          (_) => LgCheckbox(value: on, label: '记住密码', onChanged: (_) {}),
        ),
      );
    }
    list.add(
      Specimen(
        'switch',
        '${on ? 'on' : 'off'}-disabled',
        small,
        (_) => LgSwitch(value: on, onChanged: null),
      ),
    );
    list.add(
      Specimen(
        'checkbox',
        '${on ? 'on' : 'off'}-disabled',
        small,
        (_) => LgCheckbox(value: on, label: '记住密码', onChanged: null),
      ),
    );
  }

  Widget radios({required bool enabled}) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LgRadio(
        value: 1,
        groupValue: 1,
        label: '输入密码',
        onChanged: enabled ? (_) {} : null,
      ),
      LgRadio(
        value: 2,
        groupValue: 1,
        label: '在本机接受',
        onChanged: enabled ? (_) {} : null,
      ),
    ],
  );
  for (final e in _states.entries) {
    list.add(
      Specimen(
        'radio',
        e.key,
        const Size(260, 120),
        states: e.value,
        (_) => radios(enabled: true),
      ),
    );
  }
  list.add(
    Specimen(
      'radio',
      'disabled',
      const Size(260, 120),
      (_) => radios(enabled: false),
    ),
  );

  Widget seg({required bool enabled}) => LgSegmented(
    segments: const [LgSegment(0, '鼠标模式'), LgSegment(1, '触控模式')],
    selected: 0,
    onChanged: enabled ? (_) {} : null,
  );
  for (final e in _states.entries) {
    list.add(
      Specimen(
        'segmented',
        e.key,
        const Size(300, 76),
        states: e.value,
        (_) => seg(enabled: true),
      ),
    );
  }
  list.add(
    Specimen(
      'segmented',
      'disabled',
      const Size(300, 76),
      (_) => seg(enabled: false),
    ),
  );

  const menu = Size(360, 520);
  list
    ..add(
      Specimen('menu', 'panel', menu, (_) => LgMenuPanel(items: _menuItems())),
    )
    ..add(
      Specimen(
        'menu',
        'item-hover',
        const Size(360, 100),
        states: _hover,
        (_) => const LgMenuPanel(
          items: [
            LgMenuItem(label: '文件传输', icon: LgIcons.files, onPressed: _noop),
          ],
        ),
      ),
    )
    ..add(
      Specimen(
        'menu',
        'danger-hover',
        const Size(360, 100),
        states: _hover,
        (_) => const LgMenuPanel(
          items: [
            LgMenuItem(
              label: '断开',
              icon: LgIcons.power,
              danger: true,
              onPressed: _noop,
            ),
          ],
        ),
      ),
    );

  list
    ..add(
      Specimen(
        'tooltip',
        'text',
        const Size(360, 80),
        (_) => const LgTooltipBox(child: Text('复制 ID')),
      ),
    )
    ..add(
      Specimen(
        'tooltip',
        'tab',
        const Size(360, 140),
        (_) => LgTooltipBox(
          child: _tabTooltip('妈妈的笔记本', '234 567 891', [
            ('远程桌面', const LgRouteMark(route: LgRoute.relay, label: '经中继')),
            ('文件传输', const LgRouteMark(route: LgRoute.direct, label: '直连')),
          ]),
        ),
      ),
    );

  for (final s in LgStatus.values) {
    final label = switch (s) {
      LgStatus.online => '在线',
      LgStatus.offline => '离线',
      LgStatus.connecting => '正在连接…',
      LgStatus.querying => '正在查询…',
      LgStatus.warning => '已中断',
      LgStatus.error => '已停止',
    };
    list.add(
      Specimen(
        'status',
        s.name,
        const Size(220, 56),
        (_) => LgStatusText(s, label),
      ),
    );
  }
  final marks = <String, Widget>{
    'direct': const LgRouteMark(route: LgRoute.direct, label: '直连'),
    'relay': const LgRouteMark(route: LgRoute.relay, label: '经中继'),
    'direct-unencrypted': const LgRouteMark(
      route: LgRoute.direct,
      label: '直连',
      encrypted: false,
      unencryptedLabel: '未加密',
    ),
    'relay-unencrypted': const LgRouteMark(
      route: LgRoute.relay,
      label: '经中继',
      encrypted: false,
      unencryptedLabel: '未加密',
    ),
    'direct-unencrypted-worst': const LgRouteMark(
      route: LgRoute.direct,
      label: '直连',
      encrypted: false,
      unencryptedLabel: '未加密',
      worstOnly: true,
    ),
    'relay-unencrypted-worst': const LgRouteMark(
      route: LgRoute.relay,
      label: '经中继',
      encrypted: false,
      unencryptedLabel: '未加密',
      worstOnly: true,
    ),
  };
  for (final e in marks.entries) {
    list.add(Specimen('route', e.key, const Size(260, 56), (_) => e.value));
  }
  list
    ..add(Specimen('badge', '1', const Size(80, 56), (_) => const LgBadge(1)))
    ..add(
      Specimen('badge', '12', const Size(80, 56), (_) => const LgBadge(12)),
    );

  list
    ..add(
      Specimen(
        'title-bar',
        'home',
        const Size(1280, 40),
        padding: 0,
        (_) => _titleBar(),
      ),
    )
    ..add(
      Specimen(
        'title-bar',
        'session',
        const Size(1280, 40),
        padding: 0,
        (_) => _titleBar(selected: 3),
      ),
    )
    ..add(
      Specimen(
        'title-bar',
        'maximized',
        const Size(1280, 40),
        padding: 0,
        (_) => _titleBar(selected: 2, maximized: true),
      ),
    )
    ..add(
      Specimen(
        'title-bar',
        'overflow',
        const Size(960, 40),
        padding: 0,
        (_) => _titleBar(count: 8, selected: 3),
      ),
    );

  list.add(
    Specimen('icons', 'all', const Size(1200, 1300), (context) {
      return Wrap(
        spacing: LgSpace.s3,
        runSpacing: LgSpace.s3,
        children: [
          for (final icon in LgIcons.values)
            SizedBox(
              width: 160,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      LgIcon(icon, size: 20),
                      const SizedBox(width: LgSpace.s2),
                      LgIcon(icon, size: 28),
                    ],
                  ),
                  const SizedBox(height: LgSpace.s1),
                  Text(
                    icon.name,
                    style: LgTokens.of(
                      context,
                    ).textS.copyWith(color: LgTokens.of(context).colors.text2),
                  ),
                ],
              ),
            ),
        ],
      );
    }),
  );

  list.addAll(_m2aSpecimens());

  // Interactive only: open the menus with the mouse.
  list.add(
    Specimen('live', 'dropdown-and-context-menu', const Size(420, 120), (
      context,
    ) {
      return Row(
        children: [
          LgMenuAnchor(
            items: _menuItems(),
            builder: (context, controller) => LgButton(
              label: '视图',
              icon: LgIcons.chevD,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
          const SizedBox(width: LgSpace.s4),
          LgContextMenuRegion(
            items: _menuItems(),
            child: Container(
              width: 200,
              height: 72,
              alignment: Alignment.center,
              color: LgTokens.of(context).colors.surface,
              child: const Text('Right-click here'),
            ),
          ),
        ],
      );
    }),
  );
  return list;
}

// ---- M2a: devices, connection box, session ---------------------------------
// Sample texts are the Chinese texts of 01 §7.4; IDs and addresses are the
// invented ones of the mockups.

class _Dev {
  const _Dev(this.name, this.id, this.platform, this.status, this.userHost);

  final String name;
  final String id;
  final LgPlatform platform;
  final LgDeviceStatus status;
  final String userHost;

  String get statusLabel => switch (status) {
    LgDeviceStatus.online => '在线',
    LgDeviceStatus.offline => '离线',
    LgDeviceStatus.querying => '正在查询…',
  };
}

const _devices = [
  _Dev(
    '书房台式机',
    '123 456 789',
    LgPlatform.windows,
    LgDeviceStatus.online,
    'zhangsan@DESKTOP-SHUFANG',
  ),
  _Dev(
    '妈妈的笔记本',
    '234 567 891',
    LgPlatform.windows,
    LgDeviceStatus.online,
    'mama@LAPTOP-MAMA',
  ),
  _Dev(
    '办公室电脑',
    '345 678 912',
    LgPlatform.windows,
    LgDeviceStatus.offline,
    'zhangsan@OFFICE-PC01',
  ),
  _Dev(
    '客厅迷你主机',
    '456 789 123',
    LgPlatform.linux,
    LgDeviceStatus.online,
    'media@minipc',
  ),
  _Dev(
    '老王的 MacBook',
    '567 891 234',
    LgPlatform.macos,
    LgDeviceStatus.offline,
    'wang@Wangs-MacBook-Air',
  ),
  _Dev(
    '备用手机',
    '678 912 345',
    LgPlatform.android,
    LgDeviceStatus.online,
    'android-phone',
  ),
  _Dev(
    '爸爸的台式机',
    '789 123 456',
    LgPlatform.windows,
    LgDeviceStatus.offline,
    'baba@DESKTOP-BABA',
  ),
  _Dev(
    '工作室绘图电脑',
    '891 234 567',
    LgPlatform.windows,
    LgDeviceStatus.online,
    'studio@DESKTOP-STUDIO',
  ),
];

Widget _deviceRow(
  _Dev d, {
  bool first = false,
  bool selected = false,
  bool highlighted = false,
  String? source,
  bool connect = true,
  LgDeviceStatus? status,
}) {
  final s = status ?? d.status;
  return LgDeviceRow(
    name: d.name,
    id: d.id,
    platform: d.platform,
    status: s,
    statusLabel: s == LgDeviceStatus.querying ? '正在查询…' : d.statusLabel,
    userHost: d.userHost,
    source: source,
    selected: selected,
    highlighted: highlighted,
    topDivider: !first,
    connectLabel: connect ? '连接' : null,
    onConnect: connect ? _noop : null,
    onTap: _noop,
    onDoubleTap: _noop,
  );
}

Widget _deviceList(
  List<_Dev> devices, {
  String? source,
  int selected = -1,
  int highlighted = -1,
}) => LgListSurface(
  child: Column(
    children: [
      LgDeviceListHeader(
        status: '状态',
        name: '名称',
        id: 'ID',
        userHost: '用户@主机',
        source: source == null ? null : '来源',
      ),
      for (final (i, d) in devices.indexed)
        _deviceRow(
          d,
          first: i == 0,
          selected: i == selected,
          highlighted: i == highlighted,
          source: source,
        ),
    ],
  ),
);

const _helpContent = LgHelpContent(
  title: '可输入',
  rows: [
    ('设备 ID', '123 456 789'),
    ('IP 地址（直连）', '192.0.2.10'),
    ('域名:端口', 'pc.example.com:21118'),
    ('ID@服务器', '123456789@leapgate.example.com'),
  ],
);

List<Widget> _connectMenu() => const [
  LgMenuItem(label: '远程桌面', checked: true, hint: '默认', onPressed: _noop),
  LgMenuItem(
    label: '经中继连接',
    checked: false,
    description: '今后连接此设备将始终经中继。可在设备菜单中取消“始终经中继连接”。',
    onPressed: _noop,
  ),
];

Widget _connectBar(String text, {bool focused = true}) => _AutoFocus(
  key: ValueKey('bar-$text-$focused'),
  focus: focused,
  builder: (node) => LgConnectBar(
    controller: TextEditingController(text: text),
    focusNode: node,
    placeholder: '输入 ID 或搜索设备',
    connectLabel: '连接',
    onConnect: text.isEmpty ? null : _noop,
    menuItems: _connectMenu(),
    menuLabel: '连接方式',
    clearLabel: '清除',
    helpLabel: '输入说明',
    help: _helpContent,
  ),
);

/// Focuses its field after the first frame, so that the focus ring of a
/// specimen is the real one and the other buttons of the specimen are not
/// drawn focused.
class _AutoFocus extends StatefulWidget {
  const _AutoFocus({super.key, required this.builder, this.focus = true});

  final Widget Function(FocusNode node) builder;
  final bool focus;

  @override
  State<_AutoFocus> createState() => _AutoFocusState();
}

class _AutoFocusState extends State<_AutoFocus> {
  final _node = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _node.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_node);
}

/// The first ID that gets identity colour group [k].
String _idForGroup(int k) {
  for (var n = 100000000; ; n++) {
    if (identityGroup('$n') == k) return '$n';
  }
}

/// Neutral ground like the surroundings of the remote picture, with an
/// invented picture on it when [picture] is set.
Widget _stage(
  Size size,
  Widget Function(BuildContext context) child, {
  bool picture = false,
}) => Builder(
  builder: (context) => SizedBox(
    width: size.width,
    height: size.height,
    child: ClipRect(
      child: ColoredBox(
        color: LgTokens.of(context).colors.canvas,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (picture) ...const [
              ColoredBox(color: Color(0xFF3F5F7E)),
              Positioned(
                left: 120,
                top: 110,
                width: 560,
                height: 300,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFE7ECF4),
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
              ),
              Positioned(
                left: 420,
                top: 200,
                width: 420,
                height: 260,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
              ),
            ],
            child(context),
          ],
        ),
      ),
    ),
  ),
);

List<LgPanelStep> _steps(LgStepState a, LgStepState b) => [
  LgPanelStep('建立连接', a),
  LgPanelStep('验证身份', b),
];

const _panelSize = Size(960, 560);

Specimen _panel(
  String name,
  LgConnectionPanel Function(BuildContext context) build, {
  bool picture = false,
}) => Specimen(
  'connection-panel',
  name,
  _panelSize,
  padding: 0,
  (_) => _stage(_panelSize, build, picture: picture),
);

LgConnectionPanel _hostPanel({
  List<LgPanelStep>? steps,
  LgPanelTone tone = LgPanelTone.normal,
  String? message,
  LgIcons? messageIcon,
  String? detail,
  bool busy = false,
  String? secondary,
  String? notice,
  String? hint,
  LgPanelCountdown? countdown,
  List<Widget> inputs = const [],
  List<LgPanelAction> actions = const [],
  bool dimBackdrop = false,
  double width = 440,
  String title = '客厅迷你主机',
  String id = '456 789 123',
  LgPlatform platform = LgPlatform.linux,
}) => LgConnectionPanel(
  title: title,
  subtitle: id,
  platform: platform,
  steps: steps,
  tone: tone,
  message: message,
  messageIcon: messageIcon,
  detail: detail,
  busy: busy,
  secondary: secondary,
  notice: notice,
  hint: hint,
  countdown: countdown,
  inputs: inputs,
  actions: actions,
  dimBackdrop: dimBackdrop,
  width: width,
  semanticLabel: '连接过程',
);

const _cancel = LgPanelAction(label: '取消', onPressed: _noop);

Widget _passwordInput(
  String text, {
  String? error,
  bool enabled = true,
  bool focused = true,
}) => _AutoFocus(
  key: ValueKey('pwd-$text-$error-$enabled-$focused'),
  focus: focused && enabled,
  builder: (node) => LgPasswordField(
    controller: TextEditingController(text: text),
    focusNode: node,
    placeholder: '密码',
    showLabel: '显示密码',
    hideLabel: '隐藏密码',
    errorText: error,
    enabled: enabled,
  ),
);

const _tbLabels = LgToolbarLabels(
  toolbar: '会话工具栏',
  pin: '固定工具栏',
  fullscreen: '全屏',
  exitFullscreen: '退出全屏',
  minimize: '最小化',
  collapse: '收起工具栏',
  expand: '展开工具栏',
);

List<Widget> _viewMenu() => const [
  LgMenuItem(label: '远程桌面', checked: true, onPressed: _noop),
];

List<Widget> _displayMenu() => const [
  LgMenuItem(label: '显示器 1', checked: true, onPressed: _noop),
  LgMenuItem(label: '显示器 2', checked: false, onPressed: _noop),
];

List<Widget> _pictureMenu() => const [
  LgMenuGroup('缩放'),
  LgMenuItem(label: '原始大小', checked: false, onPressed: _noop),
  LgMenuItem(label: '适应窗口', checked: true, onPressed: _noop),
  LgMenuGroup('画质'),
  LgMenuItem(label: '画质优先', checked: false, onPressed: _noop),
  LgMenuItem(label: '均衡', checked: true, onPressed: _noop),
  LgMenuItem(label: '速度优先', checked: false, onPressed: _noop),
];

List<Widget> _actionMenu() => const [
  LgMenuItem(
    label: '发送 Ctrl+Alt+Del',
    hint: 'Ctrl+Alt+Shift+Delete',
    onPressed: _noop,
  ),
  LgMenuItem(label: '重启远程设备', onPressed: _noop),
];

Widget _toolbar({
  bool pinned = true,
  bool collapsed = false,
  bool fullscreen = false,
  LgRoute route = LgRoute.relay,
  bool encrypted = true,
  bool display = false,
  bool english = false,
}) {
  final routeLabel = english
      ? (route == LgRoute.relay ? 'Relayed' : 'Direct')
      : (route == LgRoute.relay ? '经中继' : '直连');
  final unencrypted = encrypted ? null : (english ? 'Unencrypted' : '未加密');
  return LgSessionToolbar(
    labels: _tbLabels,
    pinned: pinned,
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
    groups: [
      [
        LgToolbarMenuButton(
          label: english ? 'Remote desktop' : '远程桌面',
          icon: LgIcons.monitor,
          items: _viewMenu(),
        ),
      ],
      [
        if (display)
          LgToolbarMenuButton(
            label: english ? 'Display' : '显示器',
            icon: LgIcons.displays,
            items: _displayMenu(),
          ),
        LgToolbarMenuButton(
          label: english ? 'View' : '画面',
          icon: LgIcons.image,
          items: _pictureMenu(),
        ),
        LgToolbarMenuButton(
          label: english ? 'Actions' : '操作',
          icon: LgIcons.bolt,
          items: _actionMenu(),
        ),
      ],
      [
        LgToolbarStatus(
          child: LgRouteMark(
            route: route,
            label: routeLabel,
            encrypted: encrypted,
            unencryptedLabel: unencrypted,
          ),
        ),
      ],
      [
        LgToolbarButton(
          icon: LgIcons.power,
          label: english ? 'Disconnect' : '断开',
          danger: true,
          onPressed: _noop,
        ),
      ],
    ],
  );
}

Widget _toolbarStage(Widget bar, {double width = 1280, double height = 260}) =>
    _stage(
      Size(width, height),
      (_) => Align(alignment: Alignment.topCenter, child: bar),
      picture: true,
    );

LgNotice _screenshotNotice() => const LgNotice(
  id: 'shot',
  text: '截图已完成',
  tone: LgTone.success,
  actions: [LgNoticeAction('另存为', _noop), LgNoticeAction('复制到剪贴板', _noop)],
);

LgNotice _printNotice() => const LgNotice(
  id: 'print',
  text: '收到来自远程设备的打印任务',
  icon: LgIcons.printer,
  actions: [
    LgNoticeAction('使用默认打印机', _noop),
    LgNoticeAction('选择打印机', _noop),
    LgNoticeAction('不打印', _noop),
  ],
);

const _displayNotice = LgNotice(
  id: 'display',
  text: '远程设备的一台显示器已断开，已切换到主显示器',
  tone: LgTone.warning,
);

/// A title bar over the area a confirmation covers, like the mockups.
Widget _dialogStage(Widget dialog, {double height = 400}) => Builder(
  builder: (context) {
    final c = LgTokens.of(context).colors;
    return SizedBox(
      width: 1280,
      height: height,
      child: ColoredBox(
        color: c.bg,
        child: Column(
          children: [
            _titleBar(count: 2, selected: 0),
            Expanded(
              child: LgDialogScrim(onEscape: _noop, child: dialog),
            ),
          ],
        ),
      ),
    );
  },
);

List<Specimen> _m2aSpecimens() {
  final list = <Specimen>[];
  const wide = 1040.0;

  // Avatars
  list
    ..add(
      Specimen('device-avatar', 'platforms', const Size(420, 76), (_) {
        return Row(
          children: [
            for (final (i, p) in LgPlatform.values.indexed) ...[
              if (i > 0) const SizedBox(width: LgSpace.s3),
              LgDeviceAvatar(id: _devices[i + 1].id, platform: p),
            ],
          ],
        );
      }),
    )
    ..add(
      Specimen('device-avatar', 'identity-colours', const Size(420, 76), (_) {
        return Row(
          children: [
            for (var k = 0; k < kIdentityGroups; k++) ...[
              if (k > 0) const SizedBox(width: LgSpace.s2),
              LgDeviceAvatar(id: _idForGroup(k), platform: LgPlatform.windows),
            ],
          ],
        );
      }),
    )
    ..add(
      Specimen('device-avatar', 'plain', const Size(320, 56), (_) {
        return Row(
          children: [
            for (final (i, p) in LgPlatform.values.indexed) ...[
              if (i > 0) const SizedBox(width: LgSpace.s3),
              Builder(
                builder: (context) => LgDeviceAvatar(
                  id: _devices[i + 1].id,
                  platform: p,
                  size: LgTokens.of(context).sizes.icon,
                  tile: false,
                ),
              ),
            ],
          ],
        );
      }),
    );

  // Device rows
  const rowSize = Size(wide + 32, 100);
  Specimen row(
    String name,
    Widget Function() build, {
    Set<WidgetState> states = const {},
  }) => Specimen(
    'device-row',
    name,
    rowSize,
    states: states,
    (_) => SizedBox(
      width: wide,
      child: LgListSurface(child: build()),
    ),
  );
  list
    ..add(row('normal', () => _deviceRow(_devices[0], first: true)))
    ..add(
      row('hover', () => _deviceRow(_devices[0], first: true), states: _hover),
    )
    ..add(
      row(
        'pressed',
        () => _deviceRow(_devices[0], first: true),
        states: _pressed,
      ),
    )
    ..add(
      row('focus', () => _deviceRow(_devices[0], first: true), states: _focus),
    )
    ..add(
      row(
        'selected',
        () => _deviceRow(_devices[0], first: true, selected: true),
      ),
    )
    ..add(
      row(
        'highlighted',
        () => _deviceRow(_devices[0], first: true, highlighted: true),
      ),
    )
    ..add(row('offline', () => _deviceRow(_devices[2], first: true)))
    ..add(
      row(
        'querying',
        () => _deviceRow(
          _devices[0],
          first: true,
          status: LgDeviceStatus.querying,
        ),
      ),
    )
    ..add(
      row(
        'long-name',
        () => _deviceRow(
          const _Dev(
            'DESKTOP-ABCDEFGHIJKLMNOPQRSTUVWXYZ-很长很长的设备名称放不下时省略',
            '123 456 789',
            LgPlatform.windows,
            LgDeviceStatus.online,
            'administrator@DESKTOP-ABCDEFGHIJKLMNOPQRSTUVWXYZ-0123456789',
          ),
          first: true,
        ),
      ),
    )
    ..add(
      row(
        'no-connect-button',
        () => _deviceRow(_devices[0], first: true, connect: false),
      ),
    )
    ..add(
      Specimen(
        'device-row',
        'list-recent',
        const Size(wide + 32, 460),
        (_) => SizedBox(width: wide, child: _deviceList(_devices, selected: 0)),
      ),
    )
    ..add(
      Specimen(
        'device-row',
        'list-narrow',
        const Size(720 + 32, 460),
        (_) => SizedBox(width: 720, child: _deviceList(_devices)),
      ),
    );

  // The search results of the connection box
  Widget results(String input, {int highlighted = 0, List<_Dev>? matches}) =>
      SizedBox(
        width: wide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _connectBar(input),
            const SizedBox(height: LgSpace.s6),
            const LgSectionTitle('搜索结果'),
            const SizedBox(height: LgSpace.s2),
            LgConnectToRow(
              text: '连接到 $input',
              emphasis: input,
              highlighted: highlighted == 0,
              onTap: _noop,
            ),
            const SizedBox(height: LgSpace.s3),
            if (matches != null && matches.isNotEmpty)
              _deviceList(matches, source: '最近', highlighted: highlighted - 1)
            else
              const LgNoResultsNote('未找到匹配的设备'),
          ],
        ),
      );
  list
    ..add(
      Specimen(
        'connect-box',
        'results',
        const Size(wide + 32, 560),
        (_) => results('6789', matches: _devices.take(6).toList()),
      ),
    )
    ..add(
      Specimen(
        'connect-box',
        'results-device-highlighted',
        const Size(wide + 32, 560),
        (_) =>
            results('6789', highlighted: 2, matches: _devices.take(3).toList()),
      ),
    )
    ..add(
      Specimen(
        'connect-box',
        'no-results',
        const Size(wide + 32, 260),
        (_) => results('办公桌'),
      ),
    )
    ..add(
      Specimen(
        'connect-box',
        'empty',
        const Size(wide + 32, 100),
        (_) => SizedBox(width: wide, child: _connectBar('')),
      ),
    )
    ..add(
      Specimen(
        'connect-box',
        'typed',
        const Size(wide + 32, 100),
        (_) => SizedBox(width: wide, child: _connectBar('246813579')),
      ),
    )
    ..add(
      Specimen(
        'connect-box',
        'help-open',
        const Size(wide + 32, 340),
        (_) => SizedBox(
          width: wide,
          height: 300,
          child: Stack(
            children: [
              _connectBar('', focused: false),
              const Positioned(
                right: 0,
                top: 56,
                child: LgMenuPanel(
                  items: [LgHelpPanel(_helpContent)],
                  width: 400,
                ),
              ),
            ],
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'connect-box',
        'menu-open',
        const Size(wide + 32, 300),
        (_) => SizedBox(
          width: wide,
          height: 260,
          child: Stack(
            children: [
              _connectBar('246813579'),
              Positioned(
                right: 0,
                top: 56,
                child: LgMenuPanel(items: _connectMenu()),
              ),
            ],
          ),
        ),
      ),
    );
  Widget split({bool enabled = true}) => LgSplitButton(
    label: '连接',
    onPressed: enabled ? _noop : null,
    menuItems: _connectMenu(),
    menuLabel: '连接方式',
  );
  for (final e in _states.entries) {
    list.add(
      Specimen(
        'split-button',
        e.key,
        const Size(260, 76),
        states: e.value,
        (_) => split(),
      ),
    );
  }
  list.add(
    Specimen(
      'split-button',
      'disabled',
      const Size(260, 76),
      (_) => split(enabled: false),
    ),
  );

  // Connect-to row
  for (final e in _states.entries) {
    list.add(
      Specimen(
        'connect-to-row',
        e.key,
        const Size(wide + 32, 76),
        states: e.value,
        (_) => const SizedBox(
          width: wide,
          child: LgConnectToRow(
            text: '连接到 6789',
            emphasis: '6789',
            onTap: _noop,
          ),
        ),
      ),
    );
  }
  list.add(
    Specimen(
      'connect-to-row',
      'highlighted',
      const Size(wide + 32, 76),
      (_) => const SizedBox(
        width: wide,
        child: LgConnectToRow(
          text: '连接到 6789',
          emphasis: '6789',
          highlighted: true,
          onTap: _noop,
        ),
      ),
    ),
  );

  // List states
  list
    ..add(
      Specimen(
        'list-state',
        'empty-recent',
        const Size(wide + 32, 240),
        (_) => const SizedBox(width: wide, child: LgEmptyState('暂无最近连接的设备')),
      ),
    )
    ..add(
      Specimen(
        'list-state',
        'loading',
        const Size(wide + 32, 300),
        (_) => const SizedBox(
          width: wide,
          child: LgDeviceSkeleton(semanticLabel: '正在加载'),
        ),
      ),
    );

  // Password row, as in the left column (240 wide, 16 inside)
  Specimen password(String name, LgPasswordRow Function() build) => Specimen(
    'password-row',
    name,
    const Size(288, 200),
    (_) => Builder(
      builder: (context) => Container(
        width: 240,
        padding: const EdgeInsets.all(LgSpace.s4),
        decoration: BoxDecoration(
          color: LgTokens.of(context).colors.surface,
          borderRadius: BorderRadius.circular(LgRadius.r20),
        ),
        child: build(),
      ),
    ),
  );
  list
    ..add(
      password(
        'one-time',
        () => const LgPasswordRow(
          label: '一次性密码',
          value: 'a1b2c3',
          style: LgPasswordValue.code,
          onCopy: _noop,
          copyLabel: '复制',
          actions: [
            LgButton(
              label: '刷新',
              icon: LgIcons.refresh,
              kind: LgButtonKind.text,
              onPressed: _noop,
            ),
          ],
        ),
      ),
    )
    ..add(
      password(
        'both',
        () => const LgPasswordRow(
          label: '一次性密码',
          value: 'a1b2c3',
          style: LgPasswordValue.code,
          note: '也可使用固定密码',
          onCopy: _noop,
          copyLabel: '复制',
        ),
      ),
    )
    ..add(
      password(
        'fixed-only',
        () => const LgPasswordRow(
          label: '固定密码',
          value: '已设置',
          actions: [
            LgButton(label: '修改', icon: LgIcons.edit, onPressed: _noop),
          ],
        ),
      ),
    )
    ..add(
      password(
        'approve-here',
        () => const LgPasswordRow(
          label: '审批方式',
          value: '需在本机接受连接请求',
          style: LgPasswordValue.sentence,
        ),
      ),
    )
    ..add(
      password(
        'service-stopped',
        () => const LgPasswordRow(label: '一次性密码', value: '不可用', dim: true),
      ),
    );

  // Panel inputs on their own
  const inputSize = Size(440, 150);
  list
    ..add(
      Specimen(
        'panel-input',
        'password-empty',
        inputSize,
        (_) => SizedBox(width: 400, child: _passwordInput('')),
      ),
    )
    ..add(
      Specimen(
        'panel-input',
        'password-hidden',
        inputSize,
        (_) => SizedBox(width: 400, child: _passwordInput('secret12')),
      ),
    )
    ..add(
      Specimen(
        'panel-input',
        'password-wrong',
        inputSize,
        (_) => SizedBox(
          width: 400,
          child: _passwordInput('secret12', error: '密码错误'),
        ),
      ),
    )
    ..add(
      Specimen(
        'panel-input',
        'password-disabled',
        inputSize,
        (_) => SizedBox(
          width: 400,
          child: _passwordInput('secret12', enabled: false),
        ),
      ),
    );
  Widget code(String text, {String? error, bool enabled = true}) => SizedBox(
    width: 400,
    child: LgCodeField(
      semanticLabel: '验证码',
      controller: TextEditingController(text: text),
      errorText: error,
      enabled: enabled,
    ),
  );
  list
    ..add(
      Specimen(
        'panel-input',
        'code-empty',
        inputSize,
        states: _focus,
        (_) => code(''),
      ),
    )
    ..add(
      Specimen(
        'panel-input',
        'code-typing',
        inputSize,
        states: _focus,
        (_) => code('481'),
      ),
    )
    ..add(
      Specimen('panel-input', 'code-full', inputSize, (_) => code('481035')),
    )
    ..add(
      Specimen(
        'panel-input',
        'code-wrong',
        inputSize,
        (_) => code('481035', error: '验证码错误或已过期'),
      ),
    )
    ..add(
      Specimen(
        'panel-input',
        'code-disabled',
        inputSize,
        (_) => code('481035', enabled: false),
      ),
    );
  Widget select({bool enabled = true}) => SizedBox(
    width: 400,
    child: LgSelectField<String>(
      semanticLabel: 'Windows 用户',
      value: 'zhangsan',
      items: const [
        LgSelectItem('zhangsan', 'zhangsan'),
        LgSelectItem('lisi', 'lisi'),
      ],
      onChanged: enabled ? (_) {} : null,
    ),
  );
  list
    ..add(Specimen('panel-input', 'select', inputSize, (_) => select()))
    ..add(
      Specimen(
        'panel-input',
        'select-hover',
        inputSize,
        states: _hover,
        (_) => select(),
      ),
    )
    ..add(
      Specimen(
        'panel-input',
        'select-focus',
        inputSize,
        states: _focus,
        (_) => select(),
      ),
    )
    ..add(
      Specimen(
        'panel-input',
        'select-open',
        const Size(440, 220),
        states: const {WidgetState.selected},
        (_) => SizedBox(
          width: 400,
          height: 190,
          child: Stack(
            children: [
              select(),
              const Positioned(
                top: 52,
                width: 400,
                child: LgMenuPanel(
                  width: 400,
                  items: [
                    LgMenuItem(
                      label: 'zhangsan',
                      checked: true,
                      onPressed: _noop,
                    ),
                    LgMenuItem(label: 'lisi', checked: false, onPressed: _noop),
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
        'panel-input',
        'select-disabled',
        inputSize,
        (_) => select(enabled: false),
      ),
    );

  // Connection panel, every state of 01 §3.2 block D
  list
    ..add(
      _panel(
        'connecting',
        (_) => _hostPanel(
          steps: _steps(LgStepState.current, LgStepState.todo),
          message: '正在连接 客厅迷你主机…',
          busy: true,
          actions: const [_cancel],
        ),
      ),
    )
    ..add(
      _panel(
        'password',
        (_) => _hostPanel(
          steps: _steps(LgStepState.done, LgStepState.current),
          message: '输入密码',
          inputs: [
            _passwordInput(''),
            LgCheckbox(value: false, label: '记住密码', onChanged: (_) {}),
          ],
          actions: const [
            _cancel,
            LgPanelAction(label: '连接', primary: true, onPressed: null),
          ],
        ),
      ),
    )
    ..add(
      _panel(
        'password-typed',
        (_) => _hostPanel(
          steps: _steps(LgStepState.done, LgStepState.current),
          message: '输入密码',
          inputs: [
            _passwordInput('secret12'),
            LgCheckbox(value: true, label: '记住密码', onChanged: (_) {}),
          ],
          actions: const [
            _cancel,
            LgPanelAction(label: '连接', primary: true, onPressed: _noop),
          ],
        ),
      ),
    )
    ..add(
      _panel(
        'password-wrong',
        (_) => _hostPanel(
          steps: _steps(LgStepState.done, LgStepState.current),
          message: '输入密码',
          inputs: [
            _passwordInput('secret12', error: '密码错误'),
            LgCheckbox(value: false, label: '记住密码', onChanged: (_) {}),
          ],
          actions: const [
            _cancel,
            LgPanelAction(label: '连接', primary: true, onPressed: _noop),
          ],
        ),
      ),
    )
    ..add(
      _panel(
        'verifying',
        (_) => _hostPanel(
          steps: _steps(LgStepState.done, LgStepState.current),
          message: '正在验证…',
          busy: true,
          inputs: [_passwordInput('secret12', enabled: false)],
          actions: const [_cancel],
        ),
      ),
    )
    ..add(
      _panel(
        '2fa',
        (_) => _hostPanel(
          title: '工作室绘图电脑',
          id: '891 234 567',
          platform: LgPlatform.windows,
          steps: _steps(LgStepState.done, LgStepState.current),
          message: '输入验证码',
          inputs: [
            const LgStateOverride(
              states: _focus,
              child: LgCodeField(semanticLabel: '验证码'),
            ),
            LgCheckbox(value: false, label: '信任本机', onChanged: (_) {}),
          ],
          actions: const [
            _cancel,
            LgPanelAction(label: '验证', primary: true, onPressed: null),
          ],
        ),
      ),
    )
    ..add(
      _panel(
        '2fa-wrong',
        (_) => _hostPanel(
          title: '工作室绘图电脑',
          id: '891 234 567',
          platform: LgPlatform.windows,
          steps: _steps(LgStepState.done, LgStepState.current),
          message: '输入验证码',
          inputs: [
            LgCodeField(
              semanticLabel: '验证码',
              controller: TextEditingController(text: '481035'),
              errorText: '验证码错误或已过期',
            ),
            LgCheckbox(value: false, label: '信任本机', onChanged: (_) {}),
          ],
          actions: const [
            _cancel,
            LgPanelAction(label: '验证', primary: true, onPressed: _noop),
          ],
        ),
      ),
    )
    ..add(
      _panel(
        'accept',
        (_) => _hostPanel(
          title: '备用手机',
          id: '678 912 345',
          platform: LgPlatform.android,
          steps: _steps(LgStepState.done, LgStepState.current),
          message: '正在等待对方接受…',
          busy: true,
          secondary: '已等待 0:12',
          notice: '显示给对方的名称：张三',
          actions: const [_cancel],
        ),
      ),
    )
    ..add(
      _panel(
        'windows-user',
        (_) => _hostPanel(
          title: '工作室绘图电脑',
          id: '891 234 567',
          platform: LgPlatform.windows,
          steps: _steps(LgStepState.done, LgStepState.current),
          message: '远程设备上有多个用户已登录，请选择要连接的用户。',
          inputs: [
            LgSelectField<String>(
              semanticLabel: 'Windows 用户',
              value: 'zhangsan',
              items: const [
                LgSelectItem('zhangsan', 'zhangsan'),
                LgSelectItem('lisi', 'lisi'),
              ],
              onChanged: (_) {},
            ),
          ],
          actions: const [
            LgPanelAction(
              label: '连接',
              primary: true,
              isDefault: true,
              onPressed: _noop,
            ),
          ],
        ),
      ),
    )
    ..add(
      _panel(
        'insecure',
        (_) => _hostPanel(
          steps: _steps(LgStepState.current, LgStepState.todo),
          tone: LgPanelTone.warning,
          message: '未加密',
          detail: '此连接未使用端到端加密，传输的内容可能被第三方读取。',
          actions: const [
            LgPanelAction(label: '继续', onPressed: _noop),
            LgPanelAction(
              label: '断开',
              primary: true,
              isDefault: true,
              onPressed: _noop,
            ),
          ],
        ),
      ),
    )
    ..add(
      _panel(
        'waiting-frame',
        (_) => _hostPanel(
          steps: _steps(LgStepState.done, LgStepState.done),
          message: '已连接，正在等待画面…',
          busy: true,
          actions: const [_cancel],
        ),
      ),
    )
    ..add(
      _panel(
        'waiting-frame-slow',
        (_) => _hostPanel(
          steps: _steps(LgStepState.done, LgStepState.done),
          message: '已连接，正在等待画面…',
          busy: true,
          notice: '远程设备可能已锁屏或未连接显示器。',
          actions: const [_cancel],
        ),
      ),
    )
    ..add(
      _panel(
        'error-offline',
        (_) => _hostPanel(
          title: '办公室电脑',
          id: '345 678 912',
          platform: LgPlatform.windows,
          steps: _steps(LgStepState.failed, LgStepState.todo),
          tone: LgPanelTone.error,
          message: '远程设备不在线。',
          detail: '请确认该设备已开机且 Leapgate 正在运行。',
          actions: const [
            LgPanelAction(label: '关闭标签', onPressed: _noop),
            LgPanelAction(label: '重试', primary: true, onPressed: _noop),
          ],
        ),
      ),
    )
    ..add(
      _panel(
        'error-direct',
        (_) => _hostPanel(
          width: 480,
          steps: _steps(LgStepState.failed, LgStepState.todo),
          tone: LgPanelTone.error,
          messageIcon: LgIcons.wifiOff,
          message: '直连已中断，使用代理或 VPN 时可能出现此问题。',
          detail: '可改用中继，今后连接此设备将始终经中继。',
          hint: '可在设备菜单中取消“始终经中继连接”。',
          actions: const [
            LgPanelAction(label: '关闭标签', onPressed: _noop),
            LgPanelAction(label: '重试', onPressed: _noop),
            LgPanelAction(label: '改用中继', primary: true, onPressed: _noop),
          ],
        ),
      ),
    )
    ..add(
      _panel(
        'error-direct-english',
        (_) => _hostPanel(
          width: 480,
          steps: const [
            LgPanelStep('Connecting', LgStepState.failed),
            LgPanelStep('Authenticating', LgStepState.todo),
          ],
          tone: LgPanelTone.error,
          messageIcon: LgIcons.wifiOff,
          message: 'The direct connection was interrupted.',
          detail:
              'This can happen with a proxy or VPN. Switch to the relay; this device will always connect through the relay from now on.',
          hint:
              'You can undo this in the device menu: "Always connect via relay".',
          actions: const [
            LgPanelAction(label: 'Close tab', onPressed: _noop),
            LgPanelAction(label: 'Retry', onPressed: _noop),
            LgPanelAction(label: 'Use relay', primary: true, onPressed: _noop),
          ],
        ),
      ),
    )
    ..add(
      _panel(
        'error-retrying',
        (_) => _hostPanel(
          steps: _steps(LgStepState.failed, LgStepState.todo),
          tone: LgPanelTone.warning,
          messageIcon: LgIcons.wifiOff,
          message: '连接超时。',
          countdown: const LgPanelCountdown(
            text: '4 秒后重试（第 3 次）',
            progress: .48,
          ),
          actions: const [
            LgPanelAction(label: '关闭标签', onPressed: _noop),
            LgPanelAction(label: '重试', primary: true, onPressed: _noop),
          ],
        ),
      ),
    )
    ..add(
      _panel(
        'device-restarting',
        picture: true,
        (_) => _hostPanel(
          width: 420,
          title: '妈妈的笔记本',
          id: '234 567 891',
          platform: LgPlatform.windows,
          message: '远程设备正在重启，完成后将自动重新连接。',
          busy: true,
          dimBackdrop: true,
          actions: const [LgPanelAction(label: '关闭标签', onPressed: _noop)],
        ),
      ),
    );

  // Toolbar
  const barStage = Size(1280, 260);
  Specimen toolbar(
    String name,
    Widget bar, {
    Set<WidgetState> states = const {},
    Size size = barStage,
  }) => Specimen(
    'session-toolbar',
    name,
    size,
    padding: 0,
    states: states,
    (_) => _toolbarStage(bar, width: size.width, height: size.height),
  );
  list
    ..add(toolbar('default', _toolbar()))
    ..add(toolbar('not-pinned', _toolbar(pinned: false)))
    ..add(toolbar('with-display', _toolbar(display: true)))
    ..add(toolbar('direct', _toolbar(route: LgRoute.direct)))
    ..add(toolbar('unencrypted', _toolbar(encrypted: false)))
    ..add(
      toolbar(
        'minimum-window',
        _toolbar(display: true),
        size: const Size(960, 260),
      ),
    )
    ..add(
      toolbar(
        'english-minimum-window',
        _toolbar(display: true, english: true),
        size: const Size(960, 260),
      ),
    )
    ..add(toolbar('fullscreen', _toolbar(fullscreen: true)))
    ..add(toolbar('collapsed-relay', _toolbar(collapsed: true)))
    ..add(
      toolbar(
        'collapsed-direct',
        _toolbar(collapsed: true, route: LgRoute.direct),
      ),
    )
    ..add(
      toolbar(
        'collapsed-unencrypted',
        _toolbar(collapsed: true, encrypted: false),
      ),
    )
    ..add(
      toolbar(
        'collapsed-fullscreen',
        _toolbar(collapsed: true, fullscreen: true),
      ),
    )
    ..add(
      Specimen(
        'session-toolbar',
        'picture-menu-open',
        const Size(420, 420),
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LgStateOverride(
              states: const {WidgetState.selected},
              child: LgToolbarMenuButton(
                label: '画面',
                icon: LgIcons.image,
                items: _pictureMenu(),
              ),
            ),
            const SizedBox(height: LgSpace.s1),
            LgMenuPanel(items: _pictureMenu()),
          ],
        ),
      ),
    );
  for (final e in _states.entries) {
    list.add(
      Specimen(
        'toolbar-button',
        e.key,
        const Size(120, 76),
        states: e.value,
        (_) => const LgToolbarButton(
          icon: LgIcons.fullscreen,
          label: '全屏',
          dim: true,
          onPressed: _noop,
        ),
      ),
    );
  }
  list
    ..add(
      Specimen(
        'toolbar-button',
        'toggled-on',
        const Size(120, 76),
        (_) => const LgToolbarButton(
          icon: LgIcons.pin,
          label: '固定工具栏',
          toggled: true,
          onPressed: _noop,
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-button',
        'toggled-off',
        const Size(120, 76),
        (_) => const LgToolbarButton(
          icon: LgIcons.pin,
          label: '固定工具栏',
          toggled: false,
          onPressed: _noop,
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-button',
        'danger',
        const Size(120, 76),
        (_) => const LgToolbarButton(
          icon: LgIcons.power,
          label: '断开',
          danger: true,
          onPressed: _noop,
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-button',
        'disabled',
        const Size(120, 76),
        (_) => const LgToolbarButton(
          icon: LgIcons.power,
          label: '断开',
          onPressed: null,
        ),
      ),
    )
    ..add(
      Specimen(
        'toolbar-button',
        'with-text',
        const Size(160, 76),
        (_) => const LgToolbarButton(
          icon: LgIcons.displays,
          label: '2/3',
          showText: true,
          onPressed: _noop,
        ),
      ),
    );
  Widget menuButton({bool enabled = true}) => LgToolbarMenuButton(
    label: '画面',
    icon: LgIcons.image,
    items: enabled ? _pictureMenu() : const [],
    enabled: enabled,
  );
  list
    ..add(
      Specimen(
        'toolbar-menu-button',
        'normal',
        const Size(200, 76),
        (_) => menuButton(),
      ),
    )
    ..add(
      Specimen(
        'toolbar-menu-button',
        'hover',
        const Size(200, 76),
        states: _hover,
        (_) => menuButton(),
      ),
    )
    ..add(
      Specimen(
        'toolbar-menu-button',
        'focus',
        const Size(200, 76),
        states: _focus,
        (_) => menuButton(),
      ),
    )
    ..add(
      Specimen(
        'toolbar-menu-button',
        'open',
        const Size(200, 76),
        states: const {WidgetState.selected},
        (_) => menuButton(),
      ),
    )
    ..add(
      Specimen(
        'toolbar-menu-button',
        'disabled',
        const Size(200, 76),
        (_) => menuButton(enabled: false),
      ),
    );

  // Feedback
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
  list
    ..add(
      notices('three', [_screenshotNotice(), _printNotice(), _displayNotice]),
    )
    ..add(notices('single', [_displayNotice]))
    ..add(
      notices('queued-after-three', [
        _screenshotNotice(),
        _printNotice(),
        _displayNotice,
        const LgNotice(id: 'q1', text: '对方已关闭剪贴板同步'),
        const LgNotice(id: 'q2', text: '已开启隐私模式'),
      ]),
    )
    ..add(
      notices('error-with-title', [
        const LgNotice(
          id: 'e',
          title: '截图失败',
          text: '显示全部显示器时无法截图，请先切换到单个显示器',
          tone: LgTone.error,
        ),
      ]),
    );
  list
    ..add(
      Specimen(
        'toast',
        'success',
        const Size(320, 76),
        (_) => const LgToast('已复制'),
      ),
    )
    ..add(
      Specimen(
        'toast',
        'warning',
        const Size(400, 76),
        (_) => const LgToast('剪贴板中没有服务器配置', tone: LgTone.warning),
      ),
    )
    ..add(
      Specimen(
        'toast',
        'in-window',
        const Size(900, 360),
        padding: 0,
        (_) => _stage(
          const Size(900, 360),
          (_) => const LgToastHost(text: '已建立中继连接', child: SizedBox.expand()),
          picture: true,
        ),
      ),
    );
  const closeActions = [
    LgDialogAction(label: '取消', onPressed: _noop),
    LgDialogAction(label: '断开', kind: LgButtonKind.primary, onPressed: _noop),
  ];
  list
    ..add(
      Specimen(
        'confirm-dialog',
        'close-sessions',
        const Size(1280, 400),
        padding: 0,
        (_) => _dialogStage(
          LgConfirmDialog(
            title: '断开全部 2 个会话并关闭窗口？',
            actions: closeActions,
            children: [
              LgCheckbox(value: false, label: '不再提示', onChanged: (_) {}),
            ],
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'confirm-dialog',
        'close-with-exit-note',
        const Size(1280, 400),
        padding: 0,
        (_) => _dialogStage(
          LgConfirmDialog(
            title: '断开全部 2 个会话并关闭窗口？',
            body: '1 个出口将在后台继续运行。',
            bodyIcon: LgIcons.exit,
            actions: closeActions,
            children: [
              LgCheckbox(value: false, label: '不再提示', onChanged: (_) {}),
            ],
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'confirm-dialog',
        'portable-quit-or-background',
        const Size(1280, 520),
        padding: 0,
        (_) => _dialogStage(
          height: 520,
          LgConfirmDialog(
            title: '关闭窗口？',
            actions: const [
              LgDialogAction(label: '取消', onPressed: _noop),
              LgDialogAction(
                label: '关闭',
                kind: LgButtonKind.primary,
                onPressed: _noop,
              ),
            ],
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LgRadio<int>(
                    value: 0,
                    groupValue: 0,
                    label: '退出 Leapgate',
                    description: '本机将无法接受远程连接，正在使用的出口也将停止。',
                    onChanged: (_) {},
                  ),
                  LgRadio<int>(
                    value: 1,
                    groupValue: 0,
                    label: '在后台运行',
                    onChanged: (_) {},
                  ),
                ],
              ),
              LgCheckbox(value: false, label: '记住此选择', onChanged: (_) {}),
            ],
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'confirm-dialog',
        'close-tab-with-views',
        const Size(1280, 520),
        padding: 0,
        (_) => _dialogStage(
          height: 520,
          LgConfirmDialog(
            width: 420,
            title: '断开与此设备的 2 个会话？',
            subtitle: '妈妈的笔记本',
            actions: const [
              LgDialogAction(label: '取消', isDefault: true, onPressed: _noop),
              LgDialogAction(
                label: '断开',
                kind: LgButtonKind.dangerSolid,
                onPressed: _noop,
              ),
            ],
            children: [
              Builder(
                builder: (context) {
                  final t = LgTokens.of(context);
                  final c = t.colors;
                  Widget line(LgIcons icon, String name, LgRouteMark mark) =>
                      SizedBox(
                        height: t.sizes.row,
                        child: Row(
                          children: [
                            LgIcon(icon, size: 20, color: c.text2),
                            const SizedBox(width: LgSpace.s3),
                            Expanded(
                              child: Text(
                                name,
                                style: t.text.copyWith(
                                  color: c.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            DefaultTextStyle(style: t.text, child: mark),
                          ],
                        ),
                      );
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LgSpace.s4,
                      vertical: LgSpace.s1,
                    ),
                    decoration: BoxDecoration(
                      color: c.bg,
                      borderRadius: BorderRadius.circular(LgRadius.r12),
                    ),
                    child: Column(
                      children: [
                        line(
                          LgIcons.monitor,
                          '远程桌面',
                          const LgRouteMark(route: LgRoute.relay, label: '经中继'),
                        ),
                        Divider(height: 1, color: c.border),
                        line(
                          LgIcons.folder,
                          '文件传输',
                          const LgRouteMark(route: LgRoute.direct, label: '直连'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

  // Tab states and the hover tip
  const relay = LgRouteMark(route: LgRoute.relay, label: '经中继');
  list
    ..add(
      Specimen(
        'title-bar',
        'all-states',
        const Size(2040, 40),
        padding: 0,
        (_) => _titleBar(count: 8, selected: 3),
      ),
    )
    ..add(
      Specimen(
        'tab-tip',
        'views',
        const Size(360, 160),
        (_) => const LgTooltipBox(
          child: LgTabTip(
            name: '妈妈的笔记本',
            id: '234 567 891',
            views: [
              ('远程桌面', relay),
              ('文件传输', LgRouteMark(route: LgRoute.direct, label: '直连')),
            ],
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'tab-tip',
        'retrying',
        const Size(360, 160),
        (_) => const LgTooltipBox(
          child: LgTabTip(
            name: '客厅迷你主机',
            id: '456 789 123',
            lines: ['连接超时', '4 秒后重试（第 3 次）'],
          ),
        ),
      ),
    )
    ..add(
      Specimen(
        'tab-tip',
        'offline',
        const Size(360, 140),
        (_) => const LgTooltipBox(
          child: LgTabTip(name: '办公室电脑', id: '345 678 912', lines: ['远程设备不在线']),
        ),
      ),
    );

  // Interactive only: the real menus, help popover and split button
  list.add(
    Specimen('live', 'm2a-connect-box-and-toolbar', const Size(1280, 420), (_) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: wide, child: _connectBar('', focused: false)),
          const SizedBox(height: LgSpace.s5),
          _toolbarStage(_toolbar(display: true), height: 260),
        ],
      );
    }),
  );
  return list;
}

/// One specimen in one theme and mode, at its fixed size.
class SpecimenCell extends StatelessWidget {
  const SpecimenCell({
    super.key,
    required this.specimen,
    required this.variant,
    this.still = false,
  });

  final Specimen specimen;
  final GalleryVariant variant;

  /// Asks the components for no motion (like the system setting does), so
  /// that an exported picture shows the end of every entrance animation.
  final bool still;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildLgTheme(brightness: variant.brightness, mode: variant.mode),
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: still),
          child: Material(
            color: LgTokens.of(context).colors.bg,
            child: SizedBox.fromSize(
              size: specimen.size,
              child: Padding(
                padding: EdgeInsets.all(specimen.padding),
                child: LgStateOverride(
                  states: specimen.states,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: specimen.builder(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key, this.exportDir});

  final String? exportDir;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
      home: exportDir == null
          ? const _GalleryPage()
          : _Exporter(dir: exportDir!),
    );
  }
}

class _GalleryPage extends StatelessWidget {
  const _GalleryPage();

  @override
  Widget build(BuildContext context) {
    final specimens = buildSpecimens();
    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: specimens.length,
        itemBuilder: (context, i) {
          final s = specimens[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s.section} / ${s.name}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final v in galleryVariants)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.name, style: const TextStyle(fontSize: 12)),
                          SpecimenCell(specimen: s, variant: v),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Renders the boundary under [key] to a PNG file.
Future<void> captureSpecimenPng(
  GlobalKey key,
  File file, {
  double pixelRatio = 1,
}) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  await file.writeAsBytes(data!.buffer.asUint8List());
}

class _Exporter extends StatefulWidget {
  const _Exporter({required this.dir});

  final String dir;

  @override
  State<_Exporter> createState() => _ExporterState();
}

class _ExporterState extends State<_Exporter> {
  final _key = GlobalKey();
  late final _jobs = [
    for (final s in buildSpecimens())
      for (final v in galleryVariants) (s, v),
  ];
  int _i = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final dir = Directory(widget.dir)..createSync(recursive: true);
    final ratio = View.of(context).devicePixelRatio;
    for (var i = 0; i < _jobs.length; i++) {
      setState(() => _i = i);
      // One frame to build, one more for post-frame layout updates.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final (s, v) = _jobs[i];
      await captureSpecimenPng(
        _key,
        File('${dir.path}/${s.fileName(v)}'),
        pixelRatio: ratio,
      );
    }
    stdout.writeln('exported ${_jobs.length} images to ${dir.path}');
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final (s, v) = _jobs[_i];
    // Specimens wider than the window are laid out at full size anyway.
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: 0,
      maxWidth: double.infinity,
      minHeight: 0,
      maxHeight: double.infinity,
      child: RepaintBoundary(
        key: _key,
        child: SpecimenCell(specimen: s, variant: v, still: true),
      ),
    );
  }
}
