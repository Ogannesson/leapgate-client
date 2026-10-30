import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_connect_box.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_password_row.dart';
import 'package:leapgate_ui/widgets/lg_pressable.dart';

import 'helpers.dart';

const _help = LgHelpContent(
  title: '可输入',
  rows: [('设备 ID', '123 456 789'), ('IP 地址（直连）', '192.0.2.10')],
);

/// A connection box whose connect button follows the text, like the page's.
Widget _bar(
  TextEditingController controller, {
  VoidCallback? onConnect,
  VoidCallback? onRelay,
}) => SizedBox(
  width: 900,
  child: ListenableBuilder(
    listenable: controller,
    builder: (context, _) => LgConnectBar(
      controller: controller,
      placeholder: '输入 ID 或搜索设备',
      connectLabel: '连接',
      onConnect: controller.text.isEmpty ? null : (onConnect ?? () {}),
      menuLabel: '连接方式',
      menuItems: [
        const LgMenuItem(label: '远程桌面', checked: true, onPressed: null),
        LgMenuItem(label: '经中继连接', onPressed: onRelay ?? () {}),
      ],
      clearLabel: '清除',
      helpLabel: '输入说明',
      help: _help,
    ),
  ),
);

Finder _pressable(String label) =>
    find.byWidgetPredicate((w) => w is LgPressable && w.semanticLabel == label);

void main() {
  group('LgConnectBar', () {
    testWidgets('connect needs an input; the button and its arrow follow it', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var connects = 0;
      await pumpLg(tester, _bar(controller, onConnect: () => connects++));
      await tester.tap(find.text('连接'));
      await tester.tap(_pressable('连接方式'));
      await tester.pumpAndSettle();
      expect(connects, 0);
      expect(find.text('经中继连接'), findsNothing);

      await tester.enterText(find.byType(TextField), '123456789');
      await tester.pump();
      await tester.tap(find.text('连接'));
      expect(connects, 1);
    });

    testWidgets('the clear button appears with text and empties the input', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpLg(tester, _bar(controller));
      final clear = find.byWidgetPredicate(
        (w) => w is LgIconButton && w.icon == LgIcons.x,
      );
      expect(clear, findsNothing);
      await tester.enterText(find.byType(TextField), '6789');
      await tester.pump();
      expect(clear, findsOneWidget);
      await tester.tap(clear);
      await tester.pump();
      expect(controller.text, '');
      expect(clear, findsNothing);
    });

    testWidgets('the arrow opens the menu and a choice runs', (tester) async {
      final controller = TextEditingController(text: '1');
      addTearDown(controller.dispose);
      var relays = 0;
      await pumpLg(tester, _bar(controller, onRelay: () => relays++));
      await tester.tap(_pressable('连接方式'));
      await tester.pumpAndSettle();
      expect(find.text('远程桌面'), findsOneWidget);
      await tester.tap(find.text('经中继连接'));
      await tester.pumpAndSettle();
      expect(relays, 1);
      expect(find.text('经中继连接'), findsNothing);
    });

    testWidgets('the help button opens the popover and closes it again', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpLg(tester, _bar(controller));
      await tester.tap(find.byType(LgHelpButton));
      await tester.pumpAndSettle();
      expect(find.text('可输入'), findsOneWidget);
      expect(find.text('192.0.2.10'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('可输入'), findsNothing);
    });

    testWidgets('every control is named for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = TextEditingController(text: '1');
      addTearDown(controller.dispose);
      await pumpLg(tester, _bar(controller));
      for (final label in ['连接', '连接方式', '清除', '输入说明']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(find.bySemanticsLabel('输入 ID 或搜索设备'), findsWidgets);
      handle.dispose();
    });

    testWidgets('Tab goes from the input to the buttons, in order', (
      tester,
    ) async {
      final controller = TextEditingController(text: '1');
      final input = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(input.dispose);
      await pumpLg(
        tester,
        SizedBox(
          width: 900,
          child: LgConnectBar(
            controller: controller,
            focusNode: input,
            autofocus: true,
            placeholder: 'x',
            connectLabel: '连接',
            onConnect: () {},
            menuItems: const [],
            menuLabel: '连接方式',
            clearLabel: '清除',
            helpLabel: '输入说明',
            help: _help,
          ),
        ),
      );
      expect(input.hasFocus, isTrue);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      }
      await tester.pump();
      expect(input.hasFocus, isFalse);
      expect(FocusManager.instance.primaryFocus, isNotNull);
    });
  });

  group('LgSplitButton', () {
    testWidgets('disabled: neither part reacts', (tester) async {
      var taps = 0;
      await pumpLg(
        tester,
        LgSplitButton(
          label: '连接',
          onPressed: null,
          menuLabel: '连接方式',
          menuItems: [LgMenuItem(label: 'x', onPressed: () => taps++)],
        ),
      );
      await tester.tap(find.text('连接'));
      await tester.tap(_pressable('连接方式'));
      await tester.pumpAndSettle();
      expect(taps, 0);
      expect(find.text('x'), findsNothing);
    });
  });

  group('LgPasswordRow', () {
    testWidgets('copy shows only with a callback and calls it', (tester) async {
      var copies = 0;
      await pumpLg(
        tester,
        LgPasswordRow(
          label: '一次性密码',
          value: 'a1b2c3',
          style: LgPasswordValue.code,
          note: '也可使用固定密码',
          onCopy: () => copies++,
          copyLabel: '复制',
        ),
      );
      expect(find.text('一次性密码'), findsOneWidget);
      expect(find.text('a1b2c3'), findsOneWidget);
      expect(find.text('也可使用固定密码'), findsOneWidget);
      await tester.tap(find.text('复制'));
      expect(copies, 1);

      await pumpLg(
        tester,
        const LgPasswordRow(label: '审批方式', value: '需在本机接受连接请求'),
      );
      expect(find.byType(LgButton), findsNothing);
    });

    testWidgets('extra actions follow the copy button', (tester) async {
      var refreshes = 0;
      await pumpLg(
        tester,
        LgPasswordRow(
          label: '一次性密码',
          value: 'a1b2c3',
          onCopy: () {},
          copyLabel: '复制',
          actions: [
            LgButton(
              label: '刷新',
              kind: LgButtonKind.text,
              onPressed: () => refreshes++,
            ),
          ],
        ),
      );
      expect(
        tester.getTopLeft(find.text('复制')).dx,
        lessThan(tester.getTopLeft(find.text('刷新')).dx),
      );
      await tester.tap(find.text('刷新'));
      expect(refreshes, 1);
    });

    testWidgets('a dim value is the muted colour', (tester) async {
      Color? colourOf(WidgetTester t) =>
          t.widget<Text>(find.text('不可用')).style?.color;
      await pumpLg(
        tester,
        const LgPasswordRow(label: '一次性密码', value: '不可用', dim: true),
      );
      final dim = colourOf(tester);
      await pumpLg(tester, const LgPasswordRow(label: '一次性密码', value: '不可用'));
      expect(dim, isNot(colourOf(tester)));
    });
  });
}
