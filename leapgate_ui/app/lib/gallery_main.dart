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

import 'icons/lg_icon.dart';
import 'theme/lg_theme.dart';
import 'theme/lg_tokens.dart';
import 'widgets/lg_button.dart';
import 'widgets/lg_menu.dart';
import 'widgets/lg_pressable.dart';
import 'widgets/lg_selection.dart';
import 'widgets/lg_status.dart';
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
      status: LgStatusText(LgStatus.disconnected, '已断开'),
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
  const LgMenuItem(label: '传输文件', icon: LgIcons.files, onPressed: _noop),
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
          label: '传输文件',
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
            LgMenuItem(label: '传输文件', icon: LgIcons.files, onPressed: _noop),
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
      LgStatus.disconnected => '已断开',
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

/// One specimen in one theme and mode, at its fixed size.
class SpecimenCell extends StatelessWidget {
  const SpecimenCell({
    super.key,
    required this.specimen,
    required this.variant,
  });

  final Specimen specimen;
  final GalleryVariant variant;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildLgTheme(brightness: variant.brightness, mode: variant.mode),
      child: Builder(
        builder: (context) => Material(
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
        child: SpecimenCell(specimen: s, variant: v),
      ),
    );
  }
}
