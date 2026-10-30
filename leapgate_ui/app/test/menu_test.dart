import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';

import 'helpers.dart';

const _long = '这是一个很长很长的菜单项名称放不下时省略并在悬停时显示全文这是一个很长很长的菜单项名称';

void main() {
  late List<String> picked;

  List<Widget> items() => [
    const LgMenuGroup('显示'),
    LgMenuItem(
      label: '适应窗口',
      checked: true,
      onPressed: () => picked.add('fit'),
    ),
    LgMenuItem(
      label: '原始大小',
      checked: false,
      onPressed: () => picked.add('original'),
    ),
    LgMenuItem(label: _long, onPressed: () => picked.add('long')),
    const LgMenuItem(label: '交换控制方向', onPressed: null),
    LgSubmenu(
      label: '显示器',
      items: [LgMenuItem(label: '显示器 2', onPressed: () => picked.add('m2'))],
    ),
    LgMenuItem(
      label: '断开',
      danger: true,
      onPressed: () => picked.add('disconnect'),
    ),
  ];

  Widget dropdown() => LgMenuAnchor(
    items: items(),
    builder: (context, c) =>
        LgButton(label: '视图', onPressed: () => c.isOpen ? c.close() : c.open()),
  );

  setUp(() => picked = []);

  testWidgets('dropdown opens, an item runs and the menu closes', (
    tester,
  ) async {
    await pumpLg(tester, dropdown());
    expect(find.text('适应窗口'), findsNothing);
    await tester.tap(find.text('视图'));
    await tester.pumpAndSettle();
    expect(find.text('显示'), findsOneWidget);
    await tester.tap(find.text('原始大小'));
    await tester.pumpAndSettle();
    expect(picked, ['original']);
    expect(find.text('适应窗口'), findsNothing);
  });

  testWidgets('disabled item does nothing', (tester) async {
    await pumpLg(tester, dropdown());
    await tester.tap(find.text('视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('交换控制方向'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
  });

  testWidgets('arrow keys and Enter choose an item, Escape closes', (
    tester,
  ) async {
    await pumpLg(tester, dropdown());
    await tester.tap(find.text('视图'));
    await tester.pumpAndSettle();
    // The first Down enters the menu, the next ones move between items.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, ['original']);

    await tester.tap(find.text('视图'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('适应窗口'), findsNothing);
  });

  testWidgets(
    'a label that does not fit ends in an ellipsis and shows in full on hover',
    (tester) async {
      await pumpLg(tester, dropdown());
      await tester.tap(find.text('视图'));
      await tester.pumpAndSettle();
      expect(find.text(_long), findsOneWidget);
      expect(tester.getSize(find.text(_long)).width, lessThan(kLgMenuWidth));

      final mouse = await hover(tester, find.text(_long));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(_long), findsNWidgets(2)); // the item and the tooltip

      // A label that fits gets no tooltip.
      await mouse.moveTo(tester.getCenter(find.text('适应窗口')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('适应窗口'), findsOneWidget);
    },
  );

  testWidgets('submenu opens and its item runs', (tester) async {
    await pumpLg(tester, dropdown());
    await tester.tap(find.text('视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示器 2'));
    await tester.pumpAndSettle();
    expect(picked, ['m2']);
  });

  testWidgets('context menu opens on right click', (tester) async {
    await pumpLg(
      tester,
      LgContextMenuRegion(
        items: items(),
        child: const SizedBox(width: 200, height: 100, child: Text('region')),
      ),
    );
    await tester.tap(find.text('region'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('断开'));
    await tester.pumpAndSettle();
    expect(picked, ['disconnect']);
  });
}
