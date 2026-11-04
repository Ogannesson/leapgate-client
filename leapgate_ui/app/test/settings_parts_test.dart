import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_device.dart';
import 'package:leapgate_ui/widgets/lg_feedback.dart';
import 'package:leapgate_ui/widgets/lg_form_dialog.dart';
import 'package:leapgate_ui/widgets/lg_panel_inputs.dart';
import 'package:leapgate_ui/widgets/lg_qr_code.dart';
import 'package:leapgate_ui/widgets/lg_settings_layout.dart';
import 'package:leapgate_ui/widgets/lg_settings_rows.dart';
import 'package:leapgate_ui/widgets/lg_settings_search.dart';
import 'package:leapgate_ui/widgets/lg_shortcuts.dart';
import 'package:leapgate_ui/widgets/lg_text_field.dart';
import 'package:leapgate_ui/widgets/lg_trusted_devices.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'helpers.dart';

const _hits = [
  LgSettingsSearchResult(
    path: '传入连接 › 访问与密码',
    name: '审批方式',
    description: '输入密码 · 在本机接受',
  ),
  LgSettingsSearchResult(path: '传入连接 › 访问与密码', name: '固定密码'),
  LgSettingsSearchResult(path: '传入连接 › 权限', name: '允许建立 TCP 隧道'),
];

Widget _results({
  List<LgSettingsSearchResult> results = _hits,
  String query = '密码',
  int selected = -1,
  ValueChanged<int>? onOpen,
}) => SizedBox(
  width: 600,
  height: 300,
  child: LgSettingsContent(
    children: [
      LgSettingsSearchResults(
        results: results,
        query: query,
        selectedIndex: selected,
        onOpen: onOpen ?? (_) {},
        emptyText: '未找到匹配的设置',
      ),
    ],
  ),
);

/// The spans of the line that reads [text] with the parts that have a ground behind them.
List<String> _marked(WidgetTester tester, Finder text) {
  final rich = tester.widget<RichText>(
    find.descendant(of: text, matching: find.byType(RichText)).first,
  );
  final out = <String>[];
  rich.text.visitChildren((span) {
    if (span is TextSpan &&
        span.text != null &&
        span.style?.backgroundColor != null) {
      out.add(span.text!);
    }
    return true;
  });
  return out;
}

List<LgTrustedDevice> _devices() => const [
  LgTrustedDevice(
    id: '912345678',
    name: '李四的台式机',
    formattedId: '912 345 678',
    platform: LgPlatform.windows,
    remaining: '剩余 23 天',
  ),
  LgTrustedDevice(
    id: '147258369',
    name: '王五的笔记本',
    formattedId: '147 258 369',
    platform: LgPlatform.windows,
    remaining: '剩余 81 天',
  ),
  LgTrustedDevice(
    id: '678912345',
    name: '备用手机',
    formattedId: '678 912 345',
    platform: LgPlatform.android,
    remaining: '今天到期',
  ),
];

Widget _trusted({
  List<LgTrustedDevice>? devices,
  Set<String> picked = const {},
  ValueChanged<String>? onToggle,
  VoidCallback? onDeleteAll,
  VoidCallback? onDeleteSelected,
}) => SizedBox(
  width: 520,
  child: LgTrustedDevices(
    title: '受信设备',
    devices: devices ?? _devices(),
    picked: picked,
    onToggle: onToggle ?? (_) {},
    deleteAllLabel: '全部删除',
    onDeleteAll: onDeleteAll,
    emptyText: '暂无受信设备',
    pickedCountLabel: '已选择 ${picked.length} 台',
    deleteLabel: '删除',
    onDeleteSelected: onDeleteSelected,
  ),
);

LgShortcutRow _shortcut({
  List<String> keys = const ['Ctrl', 'Alt', 'Shift', 'R'],
  VoidCallback? onEdit,
  VoidCallback? onClear,
}) => LgShortcutRow(
  action: '刷新画面',
  keys: keys,
  unsetLabel: '未设置',
  editLabel: '修改',
  onEdit: onEdit,
  clearLabel: '清除',
  onClear: onClear,
  editSemanticLabel: '修改快捷键：刷新画面',
  clearSemanticLabel: '清除快捷键：刷新画面',
);

Widget _record(
  LgShortcutRecordState state, {
  List<String> keys = const [],
  String? status,
  VoidCallback? onCancel,
  VoidCallback? onConfirm,
}) => LgShortcutRecordDialog(
  title: '设置快捷键：刷新画面',
  state: state,
  keys: keys,
  statusText: status,
  cancelLabel: '取消',
  confirmLabel: state == LgShortcutRecordState.conflict ? '替换' : '保存',
  onCancel: onCancel,
  onConfirm: onConfirm,
);

void main() {
  group('LgSettingsSearchResults', () {
    testWidgets('one line per hit: path, name, description', (tester) async {
      await pumpLg(tester, _results());
      expect(find.text('传入连接 › 访问与密码'), findsNWidgets(2));
      expect(find.text('传入连接 › 权限'), findsOneWidget);
      expect(find.textContaining('审批方式'), findsOneWidget);
      expect(find.textContaining('在本机接受'), findsOneWidget);
    });

    testWidgets('a click on a hit tells which', (tester) async {
      final opened = <int>[];
      await pumpLg(tester, _results(onOpen: opened.add));
      await tester.tap(find.textContaining('TCP'));
      await tester.tap(find.textContaining('审批方式'));
      expect(opened, [2, 0]);
    });

    testWidgets('the typed words are marked, whatever their case', (
      tester,
    ) async {
      await pumpLg(tester, _results(query: '密码'));
      expect(
        _marked(
          tester,
          find.ancestor(
            of: find.textContaining('输入', findRichText: true),
            matching: find.byType(Text),
          ),
        ),
        ['密码'],
      );
      await pumpLg(
        tester,
        _results(
          query: 'tcp',
          results: const [
            LgSettingsSearchResult(path: '传入连接 › 权限', name: '允许建立 TCP 隧道'),
          ],
        ),
      );
      expect(
        _marked(
          tester,
          find.ancestor(
            of: find.textContaining('允许', findRichText: true),
            matching: find.byType(Text),
          ),
        ),
        ['TCP'],
      );
    });

    testWidgets('a hit the keyboard is on is selected for a reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, _results(selected: 1));
      final selected = tester.getSemantics(
        find.bySemanticsLabel('传入连接 › 访问与密码, 固定密码'),
      );
      expect(selected.flagsCollection.isSelected.name, 'isTrue');
      expect(selected.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('no hits: the line says so, as a live message', (tester) async {
      await pumpLg(tester, _results(results: const []));
      expect(find.text('未找到匹配的设置'), findsOneWidget);
    });

    testWidgets('the hit the keyboard moves to is scrolled into view', (
      tester,
    ) async {
      final many = [
        for (var i = 0; i < 30; i++)
          LgSettingsSearchResult(path: '传入连接 › 会话', name: '项 $i'),
      ];
      Widget page(int selected) =>
          _results(results: many, query: '项', selected: selected);
      await pumpLg(tester, page(0));
      expect(
        tester.getRect(find.text('项 25')).top,
        greaterThan(tester.getSize(find.byType(LgSettingsContent)).height),
      );
      await pumpLg(tester, page(25));
      await tester.pumpAndSettle();
      final window = tester.getRect(find.byType(LgSettingsContent));
      final line = tester.getRect(find.text('项 25'));
      expect(line.top, greaterThanOrEqualTo(window.top));
      expect(line.bottom, lessThanOrEqualTo(window.bottom));
    });
  });

  group('LgTrustedDevices', () {
    testWidgets('lists name, ID and the days left of each device', (
      tester,
    ) async {
      await pumpLg(tester, _trusted());
      expect(find.text('李四的台式机'), findsOneWidget);
      expect(find.text('912 345 678'), findsOneWidget);
      expect(find.text('剩余 23 天'), findsOneWidget);
      expect(find.text('今天到期'), findsOneWidget);
      expect(find.text('全部删除'), findsOneWidget);
      // Nothing picked: no count and no "删除" of the picked ones.
      expect(find.textContaining('已选择'), findsNothing);
      expect(find.widgetWithText(LgButton, '删除'), findsNothing);
    });

    testWidgets('the platform sits on the identity colour of the device', (
      tester,
    ) async {
      await pumpLg(tester, _trusted());
      final avatars = tester.widgetList<LgDeviceAvatar>(
        find.byType(LgDeviceAvatar),
      );
      expect(avatars.map((a) => a.id), ['912345678', '147258369', '678912345']);
      expect(avatars.map((a) => a.platform).last, LgPlatform.android);
      expect(avatars.first.size, 32);
    });

    testWidgets('a click and the keyboard pick a row', (tester) async {
      final toggled = <String>[];
      await pumpLg(tester, _trusted(onToggle: toggled.add));
      await tester.tap(find.text('王五的笔记本'));
      expect(toggled, ['147258369']);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(toggled.length, 2);
    });

    testWidgets('picked rows: the count and the delete button appear', (
      tester,
    ) async {
      var deleted = 0;
      var all = 0;
      await pumpLg(
        tester,
        _trusted(
          picked: {'912345678', '678912345'},
          onDeleteSelected: () => deleted++,
          onDeleteAll: () => all++,
        ),
      );
      expect(find.text('已选择 2 台'), findsOneWidget);
      await tester.tap(find.widgetWithText(LgButton, '删除'));
      await tester.tap(find.text('全部删除'));
      expect((deleted, all), (1, 1));
    });

    testWidgets(
      'picked rows are selected for a reader, with name, ID and days',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpLg(tester, _trusted(picked: {'912345678'}));
        final row = tester.getSemantics(
          find.bySemanticsLabel('李四的台式机, 912 345 678, 剩余 23 天'),
        );
        expect(row.flagsCollection.isSelected.name, 'isTrue');
        expect(
          tester
              .getSemantics(
                find.bySemanticsLabel('王五的笔记本, 147 258 369, 剩余 81 天'),
              )
              .flagsCollection
              .isSelected
              .name,
          'isFalse',
        );
        handle.dispose();
      },
    );

    testWidgets('empty: a line instead of rows, and no "全部删除"', (tester) async {
      await pumpLg(tester, _trusted(devices: const []));
      expect(find.text('暂无受信设备'), findsOneWidget);
      expect(find.text('全部删除'), findsNothing);
      expect(find.byType(LgDeviceAvatar), findsNothing);
    });

    testWidgets('a long name ends in "…" and the columns stay', (tester) async {
      await pumpLg(
        tester,
        _trusted(
          devices: const [
            LgTrustedDevice(
              id: '912345678',
              name: '李四在公司三楼会议室里的那台名字很长很长很长很长的台式机',
              formattedId: '912 345 678',
              platform: LgPlatform.windows,
              remaining: '剩余 23 天',
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('912 345 678'), findsOneWidget);
    });
  });

  group('LgShortcutRow', () {
    Widget row({
      List<String> keys = const ['Ctrl', 'Alt', 'Shift', 'R'],
      VoidCallback? onEdit,
      VoidCallback? onClear,
    }) => SizedBox(
      width: 632,
      child: LgSettingsBlock(
        children: [_shortcut(keys: keys, onEdit: onEdit, onClear: onClear)],
      ),
    );

    testWidgets('a binding shows its keys and both buttons', (tester) async {
      var edit = 0;
      var clear = 0;
      await pumpLg(tester, row(onEdit: () => edit++, onClear: () => clear++));
      for (final k in ['Ctrl', 'Alt', 'Shift', 'R']) {
        expect(find.text(k), findsOneWidget);
      }
      await tester.tap(find.text('修改'));
      await tester.tap(find.text('清除'));
      expect((edit, clear), (1, 1));
    });

    testWidgets('no binding: "未设置", no "清除"', (tester) async {
      await pumpLg(tester, row(keys: const []));
      expect(find.text('未设置'), findsOneWidget);
      expect(find.text('清除'), findsNothing);
      expect(find.text('修改'), findsOneWidget);
    });

    testWidgets(
      'the 修改 buttons of a bound and an unbound row stand in one column',
      (tester) async {
        await pumpLg(
          tester,
          SizedBox(
            width: 632,
            child: LgSettingsBlock(
              children: [
                _shortcut(),
                _shortcut(keys: const []),
              ],
            ),
          ),
        );
        final edits = tester
            .widgetList<LgButton>(find.widgetWithText(LgButton, '修改'))
            .length;
        expect(edits, 2);
        final lefts = [
          for (final e in find.widgetWithText(LgButton, '修改').evaluate())
            tester.getTopLeft(find.byWidget(e.widget)).dx,
        ];
        expect(lefts[0], closeTo(lefts[1], 1));
      },
    );

    testWidgets(
      'a reader hears the operation with its keys; the buttons are named for it',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpLg(tester, row(onEdit: () {}, onClear: () {}));
        expect(find.bySemanticsLabel('刷新画面, Ctrl+Alt+Shift+R'), findsOneWidget);
        expect(find.bySemanticsLabel('修改快捷键：刷新画面'), findsOneWidget);
        expect(find.bySemanticsLabel('清除快捷键：刷新画面'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('a group of rows can be paused: nothing in it responds', (
      tester,
    ) async {
      var edit = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 632,
          child: LgShortcutGroup(
            title: '画面',
            disabled: true,
            rows: [_shortcut(onEdit: () => edit++)],
          ),
        ),
      );
      expect(find.text('画面'), findsOneWidget);
      await tester.tap(find.text('修改'), warnIfMissed: false);
      expect(edit, 0);
    });

    testWidgets('the key caps are in the monospace face', (tester) async {
      await pumpLg(tester, row());
      expect(
        tester.widget<Text>(find.text('Ctrl')).style!.fontFamily,
        LgFixed.monoFamily,
      );
    });
  });

  group('LgShortcutRecordDialog', () {
    testWidgets('waiting: a dash, the line, "保存" is off', (tester) async {
      var saved = 0;
      await pumpLg(
        tester,
        _record(
          LgShortcutRecordState.waiting,
          status: '请按下组合键',
          onConfirm: () => saved++,
        ),
      );
      expect(find.text('—'), findsOneWidget);
      expect(find.text('请按下组合键'), findsOneWidget);
      await tester.tap(find.text('保存'));
      expect(saved, 0);
    });

    for (final (state, keys, status) in [
      (
        LgShortcutRecordState.unsupported,
        ['Ctrl', 'Caps Lock'],
        '“Caps Lock”不能用作快捷键',
      ),
      (LgShortcutRecordState.missingModifier, ['P'], '组合键须包含 Ctrl、Alt 或 Shift'),
    ]) {
      testWidgets('$state: the keys and the reason in red, "保存" is off', (
        tester,
      ) async {
        var saved = 0;
        await pumpLg(
          tester,
          _record(state, keys: keys, status: status, onConfirm: () => saved++),
        );
        for (final k in keys) {
          expect(find.text(k), findsOneWidget);
        }
        expect(find.text(status), findsOneWidget);
        expect(
          tester.widget<Text>(find.text(status)).style!.color,
          LgColors.light.error,
        );
        expect(
          tester.widgetList<LgIcon>(find.byType(LgIcon)).map((i) => i.icon),
          contains(LgIcons.err),
        );
        await tester.tap(find.text('保存'));
        expect(saved, 0);
      });
    }

    testWidgets(
      'conflict: the main button reads "替换" and works; the line warns',
      (tester) async {
        var done = 0;
        await pumpLg(
          tester,
          _record(
            LgShortcutRecordState.conflict,
            keys: const ['Ctrl', 'Alt', 'Shift', 'P'],
            status: '已用于“截图”，替换后该操作将没有快捷键',
            onConfirm: () => done++,
          ),
        );
        expect(find.text('保存'), findsNothing);
        expect(
          tester.widgetList<LgIcon>(find.byType(LgIcon)).map((i) => i.icon),
          contains(LgIcons.warn),
        );
        await tester.tap(find.text('替换'));
        expect(done, 1);
      },
    );

    testWidgets('valid: only the combination, no line, "保存" works', (
      tester,
    ) async {
      var done = 0;
      await pumpLg(
        tester,
        _record(
          LgShortcutRecordState.valid,
          keys: const ['Ctrl', 'Alt', 'Shift', 'R'],
          onConfirm: () => done++,
        ),
      );
      expect(find.text('+'), findsNWidgets(3));
      await tester.tap(find.text('保存'));
      expect(done, 1);
      expect(
        tester.widgetList<LgIcon>(find.byType(LgIcon)).map((i) => i.icon),
        isNot(anyOf(contains(LgIcons.err), contains(LgIcons.warn))),
      );
    });

    testWidgets('Enter is not an answer: it may be the key being recorded', (
      tester,
    ) async {
      var done = 0;
      await pumpLg(
        tester,
        _record(
          LgShortcutRecordState.valid,
          keys: const ['Ctrl', 'Enter'],
          onConfirm: () => done++,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(done, 0);
    });

    testWidgets('"取消" works', (tester) async {
      var cancelled = 0;
      await pumpLg(
        tester,
        _record(
          LgShortcutRecordState.waiting,
          status: '请按下组合键',
          onCancel: () => cancelled++,
        ),
      );
      await tester.tap(find.text('取消'));
      expect(cancelled, 1);
    });

    testWidgets(
      'the combination and the line are live regions, with the title as the name',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpLg(
          tester,
          _record(
            LgShortcutRecordState.valid,
            keys: const ['Ctrl', 'Alt', 'R'],
          ),
        );
        expect(find.bySemanticsLabel('Ctrl+Alt+R'), findsOneWidget);
        // The dialog is named by the title (the head text is the header).
        expect(find.bySemanticsLabel('设置快捷键：刷新画面'), findsWidgets);
        handle.dispose();
      },
    );
  });

  group('LgQrCode', () {
    testWidgets('draws the code of the data on a light card in both themes', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        await pumpLg(
          tester,
          const LgQrCode(
            data: 'otpauth://totp/Leapgate:135792468?secret=ABCDEFGH',
            semanticLabel: '二维码',
          ),
          brightness: brightness,
        );
        expect(find.byType(QrImageView), findsOneWidget);
        final card = tester.widget<Container>(
          find
              .ancestor(
                of: find.byType(QrImageView),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(
          (card.decoration! as BoxDecoration).color,
          LgColors.light.surface,
          reason: brightness.name,
        );
        expect(tester.getSize(find.byType(LgQrCode)), const Size(168, 168));
      }
    });

    testWidgets(
      'the picture has a name and the secret under it is read as text',
      (tester) async {
        final handle = tester.ensureSemantics();
        var copied = 0;
        await pumpLg(
          tester,
          SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LgQrCode(data: 'x', semanticLabel: '二维码'),
                LgQrKeyRow(
                  label: '密钥',
                  value: 'ABCD EFGH\nIJKL MNOP',
                  copyLabel: '复制',
                  copySemanticLabel: '复制密钥',
                  onCopy: () => copied++,
                ),
              ],
            ),
          ),
        );
        expect(find.bySemanticsLabel('二维码'), findsOneWidget);
        expect(find.textContaining('ABCD EFGH'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('复制密钥'));
        expect(copied, 1);
        handle.dispose();
      },
    );
  });

  group('the changes to older components', () {
    testWidgets(
      'a form dialog can carry something at the start of its buttons',
      (tester) async {
        var link = 0;
        var cancel = 0;
        var ok = 0;
        await pumpLg(
          tester,
          LgFormDialog(
            title: '输入解锁 PIN',
            icon: LgIcons.lock,
            leading: LgTextLink(label: '改用管理员权限解锁', onPressed: () => link++),
            actions: [
              LgDialogAction(label: '取消', onPressed: () => cancel++),
              LgDialogAction(
                label: '解锁',
                kind: LgButtonKind.primary,
                isDefault: true,
                onPressed: () => ok++,
              ),
            ],
            children: const [
              LgFormField(
                label: 'PIN',
                child: LgTextField(placeholder: 'PIN'),
              ),
            ],
          ),
        );
        final lead = tester.getRect(find.text('改用管理员权限解锁'));
        final cancelRect = tester.getRect(find.text('取消'));
        expect(lead.right, lessThan(cancelRect.left));
        expect(lead.center.dy, closeTo(cancelRect.center.dy, 2));
        await tester.tap(find.text('改用管理员权限解锁'));
        await tester.tap(find.text('取消'));
        await tester.tap(find.text('解锁'));
        expect((link, cancel, ok), (1, 1, 1));
      },
    );

    testWidgets(
      'Enter in a field runs the default answer, not the leading part',
      (tester) async {
        var link = 0;
        var ok = 0;
        await pumpLg(
          tester,
          LgFormDialog(
            title: '输入解锁 PIN',
            icon: LgIcons.lock,
            leading: LgTextLink(label: '改用管理员权限解锁', onPressed: () => link++),
            actions: [
              LgDialogAction(
                label: '解锁',
                kind: LgButtonKind.primary,
                isDefault: true,
                onPressed: () => ok++,
              ),
            ],
            children: const [
              LgFormField(
                label: 'PIN',
                child: LgTextField(placeholder: 'PIN', autofocus: true),
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect((link, ok), (0, 1));
      },
    );

    testWidgets('a form dialog without it is as before', (tester) async {
      await pumpLg(
        tester,
        LgFormDialog(
          title: '登录',
          icon: LgIcons.user,
          actions: [LgDialogAction(label: '取消', onPressed: () {})],
        ),
      );
      expect(find.text('取消'), findsOneWidget);
    });

    testWidgets('a dense select field is a button high and picks as before', (
      tester,
    ) async {
      var value = 0;
      await pumpLg(
        tester,
        StatefulBuilder(
          builder: (context, set) => SizedBox(
            width: 260,
            child: LgSelectField<int>(
              dense: true,
              semanticLabel: '声音来源',
              items: const [LgSelectItem(0, '系统声音'), LgSelectItem(1, '麦克风')],
              value: value,
              onChanged: (v) => set(() => value = v),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(LgSelectField<int>)).height,
        LgSizes.compact.button,
      );
      await tester.tap(find.text('系统声音'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('麦克风'));
      await tester.pumpAndSettle();
      expect(value, 1);
    });

    testWidgets('the select field without dense keeps its input height', (
      tester,
    ) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 260,
          child: LgSelectField<int>(
            items: const [LgSelectItem(0, 'a')],
            value: 0,
            onChanged: (_) {},
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(LgSelectField<int>)).height,
        LgSizes.compact.main,
      );
    });
  });
}
