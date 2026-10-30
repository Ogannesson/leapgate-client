import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';
import 'package:leapgate_ui/widgets/lg_text_field.dart';

import 'helpers.dart';

void main() {
  group('LgButton', () {
    testWidgets('click and keyboard (Tab, Enter, Space) trigger it', (
      tester,
    ) async {
      var count = 0;
      await pumpLg(tester, LgButton(label: '连接', onPressed: () => count++));
      await tester.tap(find.textContaining('连接'));
      expect(count, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(count, 3);
    });

    testWidgets('disabled ignores click and keyboard and cannot take focus', (
      tester,
    ) async {
      var count = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pumpLg(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LgButton(label: '连接', onPressed: null),
            LgButton(label: '其他', onPressed: () => count++, focusNode: focus),
          ],
        ),
      );
      await tester.tap(find.textContaining('连接'));
      // The first Tab skips the disabled button.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(count, 0);
    });

    testWidgets('height follows the mode tokens', (tester) async {
      Future<double> height(LgMode mode, {bool large = false}) async {
        await pumpLg(
          tester,
          LgButton(label: 'x', onPressed: () {}, large: large),
          mode: mode,
        );
        return tester.getSize(find.byType(LgButton)).height;
      }

      expect(await height(LgMode.compact), LgSizes.compact.button);
      expect(await height(LgMode.detail), LgSizes.detail.button);
      expect(await height(LgMode.compact, large: true), LgSizes.compact.main);
      expect(await height(LgMode.detail, large: true), LgSizes.detail.main);
    });
  });

  testWidgets('LgIconButton shows its label as a tooltip on hover', (
    tester,
  ) async {
    await pumpLg(
      tester,
      LgIconButton(icon: LgIcons.copy, label: '复制', onPressed: () {}),
    );
    expect(find.textContaining('复制'), findsNothing);
    await hover(tester, find.byType(LgIconButton));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('复制'), findsOneWidget);
  });

  group('LgTextField', () {
    testWidgets('error text appears under the field', (tester) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 300,
          child: LgTextField(errorText: '密码错误', obscureText: true),
        ),
      );
      expect(find.textContaining('密码错误'), findsOneWidget);
      final field = tester.getRect(find.byType(TextField));
      expect(
        tester.getRect(find.textContaining('密码错误')).top,
        greaterThan(field.bottom),
      );
      // Screen readers get the error with the text field itself.
      final node = tester.getSemantics(find.byType(EditableText));
      expect(node.flagsCollection.isTextField, isTrue);
      expect(node.label, contains('密码错误'));
    });

    testWidgets('typing reaches the controller; disabled refuses focus', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpLg(
        tester,
        SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LgTextField(controller: controller, placeholder: '输入 ID 或搜索设备'),
              const LgTextField(placeholder: 'off', enabled: false),
            ],
          ),
        ),
      );
      expect(find.textContaining('输入 ID 或搜索设备'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '123456789');
      expect(controller.text, '123456789');
      await tester.tap(find.byType(TextField).last);
      await tester.pump();
      final editable = tester.widget<EditableText>(
        find.byType(EditableText).last,
      );
      expect(editable.focusNode.hasFocus, isFalse);
    });
  });

  group('selection controls', () {
    testWidgets('switch, checkbox, radio and segmented report changes', (
      tester,
    ) async {
      bool? sw;
      bool? cb;
      int? radio;
      int? seg;
      await pumpLg(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LgSwitch(
              value: false,
              onChanged: (v) => sw = v,
              semanticLabel: 'sw',
            ),
            LgCheckbox(value: true, label: '记住密码', onChanged: (v) => cb = v),
            LgRadio(
              value: 2,
              groupValue: 1,
              label: '在本机接受',
              onChanged: (v) => radio = v,
            ),
            LgSegmented(
              segments: const [LgSegment(0, '鼠标模式'), LgSegment(1, '触控模式')],
              selected: 0,
              onChanged: (v) => seg = v,
            ),
          ],
        ),
      );
      await tester.tap(find.byType(LgSwitch));
      await tester.tap(find.textContaining('记住密码')); // the label toggles too
      await tester.tap(find.textContaining('在本机接受'));
      await tester.tap(find.textContaining('触控模式'));
      expect((sw, cb, radio, seg), (true, false, 2, 1));
    });

    testWidgets('disabled controls do not respond', (tester) async {
      await pumpLg(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LgSwitch(value: false, onChanged: null),
            LgCheckbox(value: false, label: 'cb', onChanged: null),
            LgRadio<int>(
              value: 1,
              groupValue: 0,
              label: 'radio',
              onChanged: null,
            ),
          ],
        ),
      );
      await tester.tap(find.byType(LgSwitch));
      await tester.tap(find.textContaining('cb'));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(focused?.findAncestorWidgetOfExactType<LgSwitch>(), isNull);
      expect(focused?.findAncestorWidgetOfExactType<LgCheckbox>(), isNull);
      expect(focused?.findAncestorWidgetOfExactType<LgRadio<int>>(), isNull);
      expect(
        find.byWidgetPredicate((w) => w is LgIcon && w.icon == LgIcons.check),
        findsNothing,
      );
    });

    testWidgets('checkbox toggles with Space after Tab', (tester) async {
      var value = false;
      await pumpLg(
        tester,
        StatefulBuilder(
          builder: (context, setState) => LgCheckbox(
            value: value,
            label: '不再提示',
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(value, isTrue);
      expect(
        find.byWidgetPredicate((w) => w is LgIcon && w.icon == LgIcons.check),
        findsOneWidget,
      );
    });
  });

  group('status and route markers', () {
    bool hasIcon(LgIcons icon) => find
        .byWidgetPredicate((w) => w is LgIcon && w.icon == icon)
        .evaluate()
        .isNotEmpty;

    testWidgets('status text always carries a shape and a label', (
      tester,
    ) async {
      await pumpLg(tester, const LgStatusText(LgStatus.warning, '已中断'));
      expect(find.textContaining('已中断', findRichText: true), findsOneWidget);
      expect(hasIcon(LgIcons.markTri), isTrue);
    });

    testWidgets('compact draws shapes, detail draws paths', (tester) async {
      const mark = LgRouteMark(route: LgRoute.relay, label: '经中继');
      await pumpLg(tester, mark);
      expect(hasIcon(LgIcons.markHalf), isTrue);
      await pumpLg(tester, mark, mode: LgMode.detail);
      expect(hasIcon(LgIcons.routeRelay), isTrue);
      expect(hasIcon(LgIcons.markHalf), isFalse);
    });

    testWidgets('unencrypted: route plus warning, or the worst only', (
      tester,
    ) async {
      await pumpLg(
        tester,
        const LgRouteMark(
          route: LgRoute.direct,
          label: '直连',
          encrypted: false,
          unencryptedLabel: '未加密',
        ),
        mode: LgMode.detail,
      );
      expect(find.textContaining('直连', findRichText: true), findsOneWidget);
      expect(find.textContaining('未加密', findRichText: true), findsOneWidget);
      expect(hasIcon(LgIcons.routeDirectU), isTrue);

      await pumpLg(
        tester,
        const LgRouteMark(
          route: LgRoute.direct,
          label: '直连',
          encrypted: false,
          unencryptedLabel: '未加密',
          worstOnly: true,
        ),
      );
      expect(find.textContaining('直连', findRichText: true), findsNothing);
      expect(find.textContaining('未加密', findRichText: true), findsOneWidget);
      expect(hasIcon(LgIcons.markTri), isTrue);
    });
  });
}
