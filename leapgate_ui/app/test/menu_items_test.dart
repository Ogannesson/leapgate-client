import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_menu_items.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';
import 'package:leapgate_ui/widgets/lg_slider.dart';

import 'helpers.dart';

/// A button that opens [items] as a dropdown, to see what a row does to the menu.
Widget _dropdown(List<Widget> items) => LgMenuAnchor(
  items: items,
  builder: (context, c) =>
      LgButton(label: '打开', onPressed: () => c.isOpen ? c.close() : c.open()),
);

void main() {
  group('LgMenuItem additions', () {
    testWidgets('the shortcut, the count and a trailing control show', (
      tester,
    ) async {
      await pumpLg(
        tester,
        const LgMenuPanel(
          items: [
            LgMenuItem(
              label: '截图',
              shortcut: 'Ctrl+Alt+Shift+P',
              onPressed: null,
            ),
            LgSubmenu(
              label: '聊天',
              badge: 2,
              value: '1920×1080',
              items: [LgMenuItem(label: '文字聊天', onPressed: null)],
            ),
          ],
          width: 380,
        ),
      );
      expect(find.text('Ctrl+Alt+Shift+P'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1920×1080'), findsOneWidget);
    });

    testWidgets('a greyed row says why on hover and to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        const LgMenuPanel(
          items: [
            LgMenuItem(
              label: '锁定远程设备',
              onPressed: null,
              disabledNote: '仅查看模式下不可用',
            ),
          ],
        ),
      );
      expect(find.text('仅查看模式下不可用'), findsNothing);
      await hover(tester, find.text('锁定远程设备'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('仅查看模式下不可用'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an enabled row never shows the note', (tester) async {
      await pumpLg(
        tester,
        LgMenuPanel(
          items: [
            LgMenuItem(
              label: '锁定远程设备',
              onPressed: () {},
              disabledNote: '仅查看模式下不可用',
            ),
          ],
        ),
      );
      await hover(tester, find.text('锁定远程设备'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('仅查看模式下不可用'), findsNothing);
    });

    testWidgets('a group title can carry a note at its end', (tester) async {
      await pumpLg(
        tester,
        const LgMenuPanel(items: [LgMenuGroup('地址簿', note: '此地址簿为只读')]),
      );
      expect(find.text('地址簿'), findsOneWidget);
      expect(find.text('此地址簿为只读'), findsOneWidget);
    });

    testWidgets('keepOpen leaves the menu open after the row is used', (
      tester,
    ) async {
      var n = 0;
      await pumpLg(
        tester,
        _dropdown([
          LgMenuItem(label: '留着', keepOpen: true, onPressed: () => n++),
          LgMenuItem(label: '关上', onPressed: () => n += 10),
        ]),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('留着'));
      await tester.pumpAndSettle();
      expect(find.text('关上'), findsOneWidget);
      await tester.tap(find.text('关上'));
      await tester.pumpAndSettle();
      expect(n, 11);
      expect(find.text('关上'), findsNothing);
    });
  });

  group('LgMenuSwitchItem', () {
    Widget host(ValueNotifier<bool> value, {String? shortcut}) =>
        ValueListenableBuilder<bool>(
          valueListenable: value,
          builder: (context, v, _) => _dropdown([
            LgMenuSwitchItem(
              label: '同步剪贴板',
              shortcut: shortcut,
              value: v,
              onChanged: (next) => value.value = next,
            ),
            const LgMenuSwitchItem(label: '静音', value: true, onChanged: null),
          ]),
        );

    testWidgets('a click anywhere on the row turns it and the menu stays', (
      tester,
    ) async {
      final value = ValueNotifier(false);
      await pumpLg(tester, host(value, shortcut: 'Ctrl+Alt+Shift+S'));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<LgSwitchGlyph>(find.byType(LgSwitchGlyph).first).value,
        isFalse,
      );
      await tester.tap(find.text('同步剪贴板'));
      await tester.pumpAndSettle();
      expect(value.value, isTrue);
      expect(find.text('同步剪贴板'), findsOneWidget);
      expect(
        tester.widget<LgSwitchGlyph>(find.byType(LgSwitchGlyph).first).value,
        isTrue,
      );
      await tester.tap(find.text('同步剪贴板'));
      await tester.pumpAndSettle();
      expect(value.value, isFalse);
    });

    testWidgets('a greyed row does not react', (tester) async {
      final value = ValueNotifier(false);
      await pumpLg(tester, host(value));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('静音'));
      await tester.pumpAndSettle();
      expect(value.value, isFalse);
    });

    testWidgets('Enter on the focused row turns it', (tester) async {
      bool? got;
      await pumpLg(
        tester,
        LgMenuPanel(
          items: [
            LgMenuSwitchItem(
              label: '同步剪贴板',
              value: false,
              onChanged: (v) => got = v,
            ),
          ],
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(got, isTrue);
    });

    testWidgets('it tells a screen reader its value and its shortcut', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        LgMenuPanel(
          width: 380,
          items: [
            LgMenuSwitchItem(
              label: '静音',
              shortcut: 'Ctrl+Alt+Shift+S',
              value: true,
              onChanged: (_) {},
            ),
          ],
        ),
      );
      final node = tester.getSemantics(
        find.bySemanticsLabel('静音, Ctrl+Alt+Shift+S'),
      );
      expect(node.getSemanticsData().flagsCollection.isToggled.name, 'isTrue');
      handle.dispose();
    });
  });

  group('LgMenuCheckItem and the other rows', () {
    testWidgets('a check row turns on a click', (tester) async {
      bool? got;
      await pumpLg(
        tester,
        LgMenuPanel(
          items: [
            LgMenuCheckItem(
              label: '始终经中继连接',
              value: false,
              onChanged: (v) => got = v,
            ),
          ],
        ),
      );
      await tester.tap(find.text('始终经中继连接'));
      expect(got, isTrue);
    });

    testWidgets('the expand row and the segmented row call back', (
      tester,
    ) async {
      var open = false;
      int? mode;
      await pumpLg(
        tester,
        LgMenuPanel(
          items: [
            LgMenuExpandRow(
              label: '调整显示的分类和顺序',
              expanded: false,
              onToggle: () => open = true,
            ),
            LgMenuSegmentedItem<int>(
              segments: const [LgSegment(0, '简洁'), LgSegment(1, '详细')],
              selected: 0,
              onChanged: (v) => mode = v,
            ),
          ],
        ),
      );
      await tester.tap(find.text('调整显示的分类和顺序'));
      await tester.tap(find.text('详细'));
      expect((open, mode), (true, 1));
    });

    testWidgets('the display map picks a display by its tile', (tester) async {
      int? picked;
      await pumpLg(
        tester,
        LgMenuPanel(
          items: [
            LgDisplayMap(
              current: 0,
              onSelect: (i) => picked = i,
              tiles: const [
                LgDisplayTile(
                  rect: Rect.fromLTWH(0, 0, 1920, 1080),
                  label: '1',
                  semanticLabel: '显示器 1',
                ),
                LgDisplayTile(
                  rect: Rect.fromLTWH(1920, 0, 1280, 800),
                  label: '2',
                  semanticLabel: '显示器 2',
                ),
              ],
            ),
          ],
        ),
      );
      await tester.tap(find.text('2'));
      expect(picked, 1);
    });

    testWidgets('the stepper counts and greys the button at the end', (
      tester,
    ) async {
      final seen = <int>[];
      Widget stepper(int value) => LgMenuPanel(
        items: [
          LgMenuStepperItem(
            value: value,
            min: 0,
            max: 2,
            decreaseLabel: '减少',
            increaseLabel: '增加',
            valueLabel: '数量',
            onChanged: seen.add,
          ),
        ],
      );
      await pumpLg(tester, stepper(1));
      await tester.tap(find.bySemanticsLabel('增加'));
      await tester.tap(find.bySemanticsLabel('减少'));
      expect(seen, [2, 0]);
      seen.clear();
      await pumpLg(tester, stepper(0));
      await tester.tap(find.bySemanticsLabel('减少'));
      await pumpLg(tester, stepper(2));
      await tester.tap(find.bySemanticsLabel('增加'));
      expect(seen, isEmpty);
    });

    testWidgets('showLgMenuAt opens at a point, an item closes it', (
      tester,
    ) async {
      var picked = 0;
      await pumpLg(
        tester,
        Builder(
          builder: (context) => LgButton(
            label: '右键',
            onPressed: () => showLgMenuAt(
              context,
              globalPosition: const Offset(200, 150),
              width: 240,
              items: [LgMenuItem(label: '复制设备 ID', onPressed: () => picked++)],
            ),
          ),
        ),
      );
      await tester.tap(find.text('右键'));
      await tester.pumpAndSettle();
      expect(find.text('复制设备 ID'), findsOneWidget);
      final at = tester.getTopLeft(
        find.byType(LgMenuPanel).evaluate().isEmpty
            ? find.text('复制设备 ID')
            : find.byType(LgMenuPanel),
      );
      expect(at.dx, greaterThanOrEqualTo(190));
      await tester.tap(find.text('复制设备 ID'));
      await tester.pumpAndSettle();
      expect(picked, 1);
      expect(find.text('复制设备 ID'), findsNothing);
    });
  });

  group('LgSlider', () {
    Widget slider({
      required ValueNotifier<double> value,
      double min = 0,
      double max = 10,
      double? step = 1,
      FocusNode? focus,
      bool vertical = true,
      bool enabled = true,
    }) => SizedBox(
      width: 220,
      child: ValueListenableBuilder<double>(
        valueListenable: value,
        builder: (context, v, _) => LgSlider(
          value: v,
          min: min,
          max: max,
          step: step,
          focusNode: focus,
          verticalArrows: vertical,
          semanticLabel: '缩放',
          format: (x) => '${x.round()}%',
          onChanged: enabled ? (x) => value.value = x : null,
        ),
      ),
    );

    testWidgets('a click on the track moves the knob there, on a step', (
      tester,
    ) async {
      final value = ValueNotifier(0.0);
      await pumpLg(tester, slider(value: value));
      final box = tester.getRect(find.byType(LgSlider));
      await tester.tapAt(Offset(box.center.dx, box.center.dy));
      expect(value.value, 5);
      await tester.tapAt(Offset(box.right - 1, box.center.dy));
      expect(value.value, 10);
    });

    testWidgets('dragging follows the pointer', (tester) async {
      final value = ValueNotifier(0.0);
      await pumpLg(tester, slider(value: value));
      final box = tester.getRect(find.byType(LgSlider));
      await tester.dragFrom(
        Offset(box.left + 12, box.center.dy),
        Offset(box.width / 2, 0),
      );
      expect(value.value, inInclusiveRange(4, 6));
    });

    testWidgets('arrows, page keys, Home and End move it', (tester) async {
      final value = ValueNotifier(3.0);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pumpLg(tester, slider(value: value, focus: focus));
      focus.requestFocus();
      await tester.pump();
      Future<double> press(LogicalKeyboardKey k) async {
        await tester.sendKeyEvent(k);
        await tester.pump();
        return value.value;
      }

      expect(await press(LogicalKeyboardKey.arrowRight), 4);
      expect(await press(LogicalKeyboardKey.arrowLeft), 3);
      expect(await press(LogicalKeyboardKey.arrowLeft), 2);
      expect(await press(LogicalKeyboardKey.arrowUp), 3);
      expect(await press(LogicalKeyboardKey.end), 10);
      expect(await press(LogicalKeyboardKey.home), 0);
      expect(await press(LogicalKeyboardKey.pageUp), 10);
    });

    testWidgets('inside a menu Up and Down are left to the menu', (
      tester,
    ) async {
      final value = ValueNotifier(3.0);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pumpLg(tester, slider(value: value, focus: focus, vertical: false));
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(value.value, 3);
    });

    testWidgets('a disabled slider does not move', (tester) async {
      final value = ValueNotifier(3.0);
      await pumpLg(tester, slider(value: value, enabled: false));
      await tester.tap(find.byType(LgSlider));
      expect(value.value, 3);
    });

    testWidgets('a screen reader gets the value and can step it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final value = ValueNotifier(5.0);
      await pumpLg(tester, slider(value: value, min: 0, max: 100));
      final node = tester.getSemantics(find.bySemanticsLabel('缩放'));
      expect(node.getSemanticsData().value, '5%');
      expect(node.getSemanticsData().increasedValue, '6%');
      tester.semantics.performAction(
        find.semantics.byLabel('缩放'),
        SemanticsAction.increase,
      );
      expect(value.value, 6);
      handle.dispose();
    });

    testWidgets('the menu row writes the value with the caller\'s format', (
      tester,
    ) async {
      await pumpLg(
        tester,
        LgMenuPanel(
          items: [
            LgMenuSliderItem(
              value: 100,
              min: 5,
              max: 1000,
              format: (v) => '${v.round()}%',
              semanticLabel: '自定义缩放',
              onChanged: (_) {},
            ),
          ],
        ),
      );
      expect(find.text('100%'), findsOneWidget);
    });
  });
}
