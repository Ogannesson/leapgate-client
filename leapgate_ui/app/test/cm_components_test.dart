// Behaviour of the connection manager (CM) components (06 §2.2): callbacks run,
// inert controls stay inert, the keyboard reaches what the mouse reaches, and
// every control has a name for a screen reader. No pixels are compared.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_cm_actions.dart';
import 'package:leapgate_ui/widgets/lg_cm_close_confirm.dart';
import 'package:leapgate_ui/widgets/lg_cm_files.dart';
import 'package:leapgate_ui/widgets/lg_cm_frame.dart';
import 'package:leapgate_ui/widgets/lg_cm_head.dart';
import 'package:leapgate_ui/widgets/lg_cm_permissions.dart';
import 'package:leapgate_ui/widgets/lg_cm_pill.dart';
import 'package:leapgate_ui/widgets/lg_cm_tabs.dart';
import 'package:leapgate_ui/widgets/lg_feedback.dart';
import 'package:leapgate_ui/widgets/lg_panel_inputs.dart' show LgSelectItem;

import 'helpers.dart';

const _tabs = [
  LgCmTab(
    kind: LgCmKind.remote,
    name: '李四',
    identity: 1,
    unread: 2,
    tooltip: '连接编号 12',
  ),
  LgCmTab(kind: LgCmKind.file, name: '李四', identity: 1),
  LgCmTab(kind: LgCmKind.remote, name: '王五', identity: 5),
];

LgCmHeader _header({LgCmSideButton? sideButton, LgCmStatusLine? status}) =>
    LgCmHeader(
      name: '李四',
      id: '912 345 678',
      identity: 1,
      type: '远程桌面',
      status:
          status ??
          const LgCmStatusLine(
            phase: LgCmPhase.connected,
            label: '已连接',
            time: '00:12:34',
          ),
      sideButton: sideButton,
    );

Widget _window({
  Widget? side,
  Widget? overlay,
  Widget? body,
  Widget? actions,
  VoidCallback? onCollapse,
  VoidCallback? onClose,
  VoidCallback? onStartDrag,
}) => SizedBox(
  width: side == null ? kLgCmWidth : kLgCmExpandedWidth,
  height: kLgCmHeight,
  child: LgCmFrame(
    title: 'Leapgate',
    collapseLabel: '收起',
    closeLabel: '关闭',
    onCollapse: onCollapse ?? () {},
    onClose: onClose ?? () {},
    onStartDrag: onStartDrag,
    tabs: LgCmTabStrip(tabs: _tabs, selected: 0, onSelect: (_) {}),
    panel: LgCmPanel(header: _header(), body: body, actions: actions),
    side: side,
    overlay: overlay,
  ),
);

Finder _icon(LgIcons icon) =>
    find.byWidgetPredicate((w) => w is LgIconButton && w.icon == icon);

void main() {
  group('LgCmTabStrip', () {
    testWidgets('a tab selects on a click and on Enter', (tester) async {
      final picked = <int>[];
      await pumpLg(
        tester,
        SizedBox(
          width: kLgCmWidth,
          height: 36,
          child: LgCmTabStrip(tabs: _tabs, selected: 0, onSelect: picked.add),
        ),
      );
      await tester.tap(find.text('王五'));
      expect(picked, [2]);
      // The first Tab lands on the first tab; Enter selects it.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(picked, [2, 0]);
    });

    testWidgets('unread count is drawn, the selected tab is announced', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        SizedBox(
          width: kLgCmWidth,
          height: 36,
          child: LgCmTabStrip(tabs: _tabs, selected: 2, onSelect: (_) {}),
        ),
      );
      expect(find.text('2'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('王五')),
        isSemantics(label: '王五', isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('李四').first),
        isSemantics(label: '李四', isSelected: false),
      );
      handle.dispose();
    });

    testWidgets('hovering a tab shows the connection number', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: kLgCmWidth,
          height: 36,
          child: LgCmTabStrip(tabs: _tabs, selected: 0, onSelect: (_) {}),
        ),
      );
      await hover(tester, find.text('李四').first);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('连接编号 12'), findsOneWidget);
    });

    testWidgets('a gone tab and many tabs build without overflow', (
      tester,
    ) async {
      await pumpLg(
        tester,
        SizedBox(
          width: kLgCmWidth,
          height: 36,
          child: LgCmTabStrip(
            tabs: [
              for (var i = 0; i < 8; i++)
                LgCmTab(
                  kind: LgCmKind.values[i % LgCmKind.values.length],
                  name: '来访者 $i',
                  identity: i,
                  gone: i == 3,
                ),
            ],
            selected: 7,
            onSelect: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The selected tab was scrolled into the 320 px strip.
      expect(
        tester.getTopRight(find.text('来访者 7')).dx,
        lessThanOrEqualTo(tester.getRect(find.byType(LgCmTabStrip)).right),
      );
    });
  });

  group('LgCmFrame', () {
    testWidgets('collapse and close call back; dragging the title starts a '
        'window drag, a click on a button does not', (tester) async {
      var collapsed = 0, closed = 0, drags = 0;
      await pumpLg(
        tester,
        _window(
          onCollapse: () => collapsed++,
          onClose: () => closed++,
          onStartDrag: () => drags++,
        ),
      );
      await tester.tap(_icon(LgIcons.dockTop));
      await tester.tap(_icon(LgIcons.x));
      expect((collapsed, closed, drags), (1, 1, 0));
      await tester.dragFrom(
        tester.getTopLeft(find.text('Leapgate')) + const Offset(60, 4),
        const Offset(40, 20),
      );
      expect(drags, 1);
    });

    testWidgets(
      'the side panel takes the left 380 and the overlay covers all',
      (tester) async {
        await pumpLg(
          tester,
          _window(
            side: const LgCmSidePanel(
              icon: LgIcons.files,
              title: '文件记录',
              child: SizedBox(),
            ),
            overlay: const ColoredBox(color: Color(0x80000000)),
          ),
        );
        final window = tester.getRect(find.byType(LgCmFrame));
        expect(window.width, kLgCmExpandedWidth);
        expect(
          tester.getRect(find.byType(LgCmSidePanel)).width,
          kLgCmSideWidth,
        );
        expect(find.text('文件记录'), findsOneWidget);
        // The main panel starts right of the side panel.
        expect(
          tester.getTopLeft(find.byType(LgCmHeader)).dx,
          greaterThanOrEqualTo(window.left + kLgCmSideWidth),
        );
      },
    );

    testWidgets('the buttons of the title row are reachable with Tab', (
      tester,
    ) async {
      var collapsed = 0;
      await pumpLg(tester, _window(onCollapse: () => collapsed++));
      // The title buttons come before the tabs in the focus order.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(collapsed, 1);
    });
  });

  group('LgCmHeader', () {
    testWidgets('the avatar shows the first character of the name', (
      tester,
    ) async {
      await pumpLg(tester, SizedBox(width: kLgCmWidth, child: _header()));
      expect(find.text('李'), findsOneWidget);
      expect(find.text('912'), findsOneWidget);
      expect(find.text('00:12:34'), findsOneWidget);
    });

    testWidgets('the side button reports clicks, shows unread and selection', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var pressed = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: kLgCmWidth,
          child: _header(
            sideButton: LgCmSideButton(
              icon: LgIcons.chat,
              label: '聊天',
              onPressed: () => pressed++,
              selected: true,
              unread: 3,
              semanticLabel: '聊天，3 条未读',
            ),
          ),
        ),
      );
      expect(find.text('3'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('聊天，3 条未读')),
        isSemantics(isSelected: true),
      );
      await tester.tap(find.bySemanticsLabel('聊天，3 条未读'));
      expect(pressed, 1);
      handle.dispose();
    });

    testWidgets('every phase builds', (tester) async {
      for (final phase in LgCmPhase.values) {
        await pumpLg(
          tester,
          SizedBox(
            width: kLgCmWidth,
            child: _header(
              status: LgCmStatusLine(
                phase: phase,
                label: '状态',
                time: phase == LgCmPhase.disconnected ? null : '00:00:01',
              ),
            ),
          ),
        );
        expect(
          find.textContaining('状态', findRichText: true),
          findsOneWidget,
          reason: phase.name,
        );
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('LgCmPermissions', () {
    List<LgCmPermission> items(List<bool> log, {bool wired = true}) => [
      for (final (i, label) in ['键盘和鼠标', '剪贴板', '声音'].indexed)
        LgCmPermission(
          label: label,
          value: i == 0,
          onChanged: wired ? (v) => log.add(v) : null,
        ),
    ];

    testWidgets('a click on the switch or its words flips the value', (
      tester,
    ) async {
      final log = <bool>[];
      await pumpLg(
        tester,
        SizedBox(
          width: 272,
          child: LgCmPermissions(title: '允许对方', items: items(log)),
        ),
      );
      await tester.tap(find.text('键盘和鼠标'));
      await tester.tap(find.text('剪贴板'));
      expect(log, [false, true]);
    });

    testWidgets('read-only and unwired items do nothing and are announced as '
        'disabled', (tester) async {
      final handle = tester.ensureSemantics();
      final log = <bool>[];
      await pumpLg(
        tester,
        SizedBox(
          width: 272,
          child: LgCmPermissions(
            title: '允许对方',
            items: items(log),
            readOnly: true,
          ),
        ),
      );
      await tester.tap(find.text('键盘和鼠标'));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(log, isEmpty);
      expect(
        tester.getSemantics(find.bySemanticsLabel('键盘和鼠标')),
        isSemantics(isEnabled: false, hasEnabledState: true),
      );
      handle.dispose();
    });

    testWidgets('Tab reaches a switch and Space flips it; the state is '
        'announced', (tester) async {
      final handle = tester.ensureSemantics();
      final log = <bool>[];
      await pumpLg(
        tester,
        SizedBox(
          width: 272,
          child: LgCmPermissions(title: '允许对方', items: items(log)),
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('键盘和鼠标')),
        isSemantics(
          label: '键盘和鼠标',
          hasToggledState: true,
          isToggled: true,
          isEnabled: true,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(log, [false]);
      handle.dispose();
    });

    testWidgets('an odd number of items and long words lay out', (
      tester,
    ) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 272,
          child: LgCmPermissions(
            title: 'Allow the visitor to',
            items: [
              LgCmPermission(
                label: 'Use the keyboard and the mouse of this computer',
                value: true,
                onChanged: (_) {},
              ),
              LgCmPermission(label: 'Audio', value: false, onChanged: (_) {}),
              LgCmPermission(
                label: 'Block local input',
                value: false,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('actions', () {
    testWidgets('each button runs its own callback; one is as wide as the '
        'panel, two share it by flex', (tester) async {
      final log = <String>[];
      await pumpLg(
        tester,
        SizedBox(
          width: 272,
          child: LgCmActions(
            children: [
              LgCmActionRow(
                actions: [
                  LgCmAction(
                    label: '接受',
                    kind: LgCmActionKind.primary,
                    onPressed: () => log.add('accept'),
                  ),
                ],
              ),
              LgCmActionRow(
                flex: const [2, 1],
                actions: [
                  LgCmAction(
                    label: '接受并提升权限',
                    icon: LgIcons.shield,
                    onPressed: () => log.add('elevate'),
                  ),
                  LgCmAction(label: '拒绝', onPressed: () => log.add('refuse')),
                ],
              ),
            ],
          ),
        ),
      );
      expect(tester.getSize(find.widgetWithText(LgButton, '接受')).width, 272);
      final wide = tester
          .getSize(find.widgetWithText(LgButton, '接受并提升权限'))
          .width;
      final narrow = tester.getSize(find.widgetWithText(LgButton, '拒绝')).width;
      expect(wide / narrow, closeTo(2, .3));
      await tester.tap(find.widgetWithText(LgButton, '接受'));
      await tester.tap(find.widgetWithText(LgButton, '接受并提升权限'));
      await tester.tap(find.widgetWithText(LgButton, '拒绝'));
      expect(log, ['accept', 'elevate', 'refuse']);
    });

    testWidgets('a button without a callback does not respond', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        const SizedBox(
          width: 272,
          child: LgCmActionRow(
            actions: [LgCmAction(label: '断开', onPressed: null)],
          ),
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('断开')),
        isSemantics(isEnabled: false, hasEnabledState: true),
      );
      handle.dispose();
    });

    testWidgets('the refusal bubble is drawn above the button, keeps the '
        'button as wide as before and takes no clicks', (tester) async {
      var disconnected = 0;
      Widget row(String? tip) => SizedBox(
        width: 272,
        child: LgCmActionRow(
          actions: [
            LgCmAction(
              label: '断开',
              kind: LgCmActionKind.danger,
              tip: tip,
              onPressed: () => disconnected++,
            ),
          ],
        ),
      );
      await pumpLg(
        tester,
        Padding(padding: const EdgeInsets.only(top: 80), child: row(null)),
      );
      final plain = tester.getRect(find.widgetWithText(LgButton, '断开'));
      await pumpLg(
        tester,
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: row('无法远程执行此操作'),
        ),
      );
      expect(tester.getRect(find.widgetWithText(LgButton, '断开')), plain);
      final bubble = tester.getRect(find.text('无法远程执行此操作'));
      expect(bubble.bottom, lessThan(plain.top));
      await tester.tapAt(bubble.center);
      expect(disconnected, 0);
      await tester.tap(find.widgetWithText(LgButton, '断开'));
      expect(disconnected, 1);
    });

    testWidgets('the waiting note is announced as one line', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        const SizedBox(width: 272, child: LgCmNote(text: '对方正在输入密码…')),
      );
      expect(find.bySemanticsLabel('对方正在输入密码…'), findsOneWidget);
      handle.dispose();
    });
  });

  group('LgCmMicRow', () {
    LgCmMicRow row({
      List<LgSelectItem<String>> devices = const [
        LgSelectItem('default', '默认麦克风'),
        LgSelectItem('usb', 'USB 麦克风'),
      ],
      String? device = 'default',
      ValueChanged<String>? onChanged,
      VoidCallback? onHangUp,
      VoidCallback? onNoDevices,
      String? tip,
    }) => LgCmMicRow(
      microphoneLabel: '麦克风',
      placeholder: '选择麦克风',
      devices: devices,
      device: device,
      onDeviceChanged: onChanged ?? (_) {},
      onNoDevices: onNoDevices,
      hangUpLabel: '挂断',
      onHangUp: onHangUp ?? () {},
      tip: tip,
    );

    testWidgets('picks a device from the menu and hangs up', (tester) async {
      final picked = <String>[];
      var hung = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 272,
          child: row(onChanged: picked.add, onHangUp: () => hung++),
        ),
      );
      expect(find.text('默认麦克风'), findsOneWidget);
      await tester.tap(find.text('默认麦克风'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USB 麦克风'));
      await tester.pumpAndSettle();
      expect(picked, ['usb']);
      await tester.tap(find.text('挂断'));
      expect(hung, 1);
    });

    testWidgets('with no device the field reports it instead of opening a '
        'menu, and the placeholder and the bubble show', (tester) async {
      var none = 0;
      await pumpLg(
        tester,
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: SizedBox(
            width: 272,
            child: row(
              devices: const [],
              device: null,
              onNoDevices: () => none++,
              tip: '未找到音频输入设备',
            ),
          ),
        ),
      );
      expect(find.text('选择麦克风'), findsOneWidget);
      expect(find.text('未找到音频输入设备'), findsOneWidget);
      await tester.tap(find.text('选择麦克风'));
      await tester.pumpAndSettle();
      expect(none, 1);
      expect(find.byType(MenuItemButton), findsNothing);
    });

    testWidgets('the field and the hang-up button are named and focusable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var hung = 0;
      await pumpLg(
        tester,
        SizedBox(width: 272, child: row(onHangUp: () => hung++)),
      );
      expect(find.bySemanticsLabel('麦克风: 默认麦克风'), findsOneWidget);
      expect(find.bySemanticsLabel('挂断'), findsOneWidget);
      // Field first, hang up second.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(hung, 1);
      handle.dispose();
    });
  });

  group('LgCmPill', () {
    const person = LgCmPillPerson(letter: '李', identity: 1);

    Widget single({
      VoidCallback? onAction,
      VoidCallback? onRestore,
      VoidCallback? onStartDrag,
      String? blocked,
    }) => SizedBox(
      width: kLgCmWidth,
      child: LgCmPill.single(
        person: person,
        title: '李四 正在远程控制本机',
        time: '00:12:34',
        blockedHint: blocked,
        actionLabel: '断开',
        onAction: onAction ?? () {},
        onRestore: onRestore,
        onStartDrag: onStartDrag,
      ),
    );

    testWidgets('disconnect does not restore; the title and the empty part '
        'do', (tester) async {
      var disconnected = 0, restored = 0;
      await pumpLg(
        tester,
        single(onAction: () => disconnected++, onRestore: () => restored++),
      );
      expect(tester.getSize(find.byType(LgCmPill)).height, kLgCmPillHeight);
      await tester.tap(find.widgetWithText(LgButton, '断开'));
      expect((disconnected, restored), (1, 0));
      await tester.tap(find.text('李四 正在远程控制本机'));
      expect(restored, 1);
      // Left of the avatar: the empty padding.
      await tester.tapAt(
        tester.getTopLeft(find.byType(LgCmPill)) + const Offset(4, 24),
      );
      expect(restored, 2);
      expect(disconnected, 1);
    });

    testWidgets('the title is a button of the keyboard too', (tester) async {
      var restored = 0;
      await pumpLg(tester, single(onRestore: () => restored++));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(restored, 1);
    });

    testWidgets('dragging the empty part moves the strip', (tester) async {
      var drags = 0;
      await pumpLg(tester, single(onStartDrag: () => drags++));
      await tester.dragFrom(
        tester.getTopLeft(find.byType(LgCmPill)) + const Offset(4, 24),
        const Offset(60, 0),
      );
      expect(drags, 1);
    });

    testWidgets('the hint replaces the time while a click is refused', (
      tester,
    ) async {
      await pumpLg(tester, single());
      expect(find.text('00:12:34'), findsOneWidget);
      await pumpLg(tester, single(blocked: '无法远程执行此操作'));
      expect(find.text('无法远程执行此操作'), findsOneWidget);
      expect(find.text('00:12:34'), findsNothing);
    });

    testWidgets('a group shows its avatars, says how many, and expands', (
      tester,
    ) async {
      var expanded = 0, restored = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: kLgCmWidth,
          child: LgCmPill.group(
            people: const [
              person,
              LgCmPillPerson(letter: '王', identity: 5),
              LgCmPillPerson(letter: '赵', identity: 3),
              LgCmPillPerson(letter: '孙', identity: 0),
            ],
            title: '4 个会话进行中',
            actionLabel: '展开',
            onAction: () => expanded++,
            onRestore: () => restored++,
          ),
        ),
      );
      // Three avatars at most.
      expect(find.text('李'), findsOneWidget);
      expect(find.text('王'), findsOneWidget);
      expect(find.text('赵'), findsOneWidget);
      expect(find.text('孙'), findsNothing);
      expect(find.widgetWithText(LgButton, '断开'), findsNothing);
      await tester.tap(find.widgetWithText(LgButton, '展开'));
      expect((expanded, restored), (1, 0));
    });
  });

  group('LgCmFileLog', () {
    testWidgets('lists the records with their results', (tester) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 372,
          height: 400,
          child: LgCmFileLog(
            emptyText: '暂无文件传输记录',
            entries: [
              LgCmFileEntry(
                action: LgCmFileAction.toHere,
                actionLabel: '上传到本机',
                name: '旅行照片.zip',
                size: '48.6 MB',
                state: LgCmFileState.running,
                resultLabel: '62%',
                progress: .62,
              ),
              LgCmFileEntry(
                action: LgCmFileAction.fromHere,
                actionLabel: '从本机下载',
                name: '旧备份.zip',
                size: '640 MB',
                state: LgCmFileState.failed,
                resultLabel: '失败',
              ),
              LgCmFileEntry(
                action: LgCmFileAction.rename,
                actionLabel: '重命名',
                name: '说明.txt → 说明-新.txt',
                state: LgCmFileState.done,
                resultLabel: '已完成',
              ),
            ],
          ),
        ),
      );
      expect(find.text('旅行照片.zip'), findsOneWidget);
      expect(find.text('62%'), findsOneWidget);
      expect(find.text('失败'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('暂无文件传输记录'), findsNothing);
      final bar = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(bar.widthFactor, .62);
    });

    testWidgets('no record shows the empty state', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        const SizedBox(
          width: 372,
          height: 400,
          child: LgCmFileLog(entries: [], emptyText: '暂无文件传输记录'),
        ),
      );
      expect(find.text('暂无文件传输记录'), findsOneWidget);
      expect(find.bySemanticsLabel('暂无文件传输记录'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a record is one stop for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        const SizedBox(
          width: 372,
          height: 400,
          child: LgCmFileLog(
            emptyText: '空',
            entries: [
              LgCmFileEntry(
                action: LgCmFileAction.delete,
                actionLabel: '删除',
                name: '草稿.docx',
                size: '86 KB',
                state: LgCmFileState.done,
                resultLabel: '已完成',
              ),
            ],
          ),
        ),
      );
      expect(find.bySemanticsLabel('草稿.docx, 删除, 86 KB, 已完成'), findsOneWidget);
      handle.dispose();
    });
  });

  group('LgCmCloseConfirm', () {
    Widget confirm({required List<String> log, bool cancelIsDefault = true}) =>
        SizedBox(
          width: kLgCmWidth,
          height: kLgCmHeight,
          child: Stack(
            children: [
              LgCmCloseConfirm(
                title: '断开全部会话？',
                onEscape: () => log.add('escape'),
                actions: [
                  LgDialogAction(
                    label: '取消',
                    isDefault: cancelIsDefault,
                    onPressed: () => log.add('cancel'),
                  ),
                  LgDialogAction(
                    label: '断开',
                    kind: LgButtonKind.danger,
                    onPressed: () => log.add('disconnect'),
                  ),
                ],
              ),
            ],
          ),
        );

    testWidgets('both buttons call back and the card is announced', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final log = <String>[];
      await pumpLg(tester, confirm(log: log));
      expect(find.bySemanticsLabel('断开全部会话？'), findsWidgets);
      expect(
        tester.getSize(find.byType(LgCmCloseConfirm)),
        const Size(320, 500),
      );
      await tester.tap(find.widgetWithText(LgButton, '断开'));
      await tester.tap(find.widgetWithText(LgButton, '取消'));
      expect(log, ['disconnect', 'cancel']);
      handle.dispose();
    });

    testWidgets('Esc leaves, Enter is the default button and nothing behind '
        'the card gets the click', (tester) async {
      final log = <String>[];
      var behind = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: kLgCmWidth,
          height: kLgCmHeight,
          child: Stack(
            children: [
              GestureDetector(onTap: () => behind++),
              confirm(log: log),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(log, ['cancel', 'escape']);
      await tester.tapAt(
        tester.getTopLeft(find.byType(LgCmCloseConfirm)) + const Offset(4, 4),
      );
      expect(behind, 0);
    });

    testWidgets('inside the frame it covers the whole window', (tester) async {
      final log = <String>[];
      await pumpLg(
        tester,
        _window(
          overlay: LgCmCloseConfirm(
            title: '断开全部会话？',
            actions: [
              LgDialogAction(label: '取消', onPressed: () => log.add('c')),
            ],
          ),
        ),
      );
      await tester.tap(_icon(LgIcons.x), warnIfMissed: false);
      expect(
        tester.getRect(find.byType(LgCmCloseConfirm)),
        tester.getRect(find.byType(LgCmFrame)),
      );
    });
  });

  group('themes and modes', () {
    testWidgets('a window builds in every theme and mode', (tester) async {
      for (final b in Brightness.values) {
        for (final m in [LgMode.compact, LgMode.detail]) {
          await pumpLg(
            tester,
            _window(
              body: LgCmPermissions(
                title: '允许对方',
                items: [
                  for (final l in ['A', 'B', 'C', 'D'])
                    LgCmPermission(label: l, value: true, onChanged: (_) {}),
                ],
              ),
              actions: const LgCmActions(
                children: [
                  LgCmActionRow(
                    actions: [LgCmAction(label: '断开', onPressed: null)],
                  ),
                ],
              ),
            ),
            brightness: b,
            mode: m,
          );
          expect(tester.takeException(), isNull, reason: '${b.name} ${m.name}');
        }
      }
    });
  });
}
