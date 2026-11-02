import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_book_switcher.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_tag_chips.dart';

import 'helpers.dart';

const _books = [
  LgBook(id: 'me', name: '我的地址簿', detail: '完全控制'),
  LgBook(id: 'home', name: '家里的电脑', detail: '可编辑 · 所有者：张三'),
  LgBook(id: 'friends', name: '朋友们', detail: '只读 · 所有者：李四'),
];

Widget _switcher(
  List<String> calls, {
  String selected = 'home',
  Widget? trailing,
  List<LgBook> books = _books,
}) => SizedBox(
  width: 900,
  height: 500,
  child: Align(
    alignment: Alignment.topLeft,
    child: LgBookSwitcher(
      books: books,
      selectedId: selected,
      onSelect: (id) => calls.add(id),
      searchPlaceholder: '搜索地址簿',
      noMatchLabel: '未找到匹配的地址簿',
      hint: '共享地址簿的成员和权限由管理员设置',
      semanticLabel: '切换地址簿',
      trailing: trailing,
    ),
  ),
);

Finder get _trigger => find.bySemanticsLabel('切换地址簿: 家里的电脑');

void main() {
  group('LgBookSwitcher', () {
    testWidgets('shows the book and, beside it, what you may do with it', (
      tester,
    ) async {
      await pumpLg(tester, _switcher([]));
      expect(find.text('家里的电脑'), findsOneWidget);
      expect(find.text('可编辑 · 所有者：张三'), findsOneWidget);
      // The other books are not shown until it opens.
      expect(find.text('朋友们'), findsNothing);
    });

    testWidgets('the trailing tools sit at the far end of the row', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _switcher(
          [],
          trailing: const SizedBox(key: Key('tools'), width: 80, height: 36),
        ),
      );
      expect(
        tester.getTopRight(find.byKey(const Key('tools'))).dx,
        tester.getTopRight(find.byType(LgBookSwitcher)).dx,
      );
    });

    testWidgets('opens on a click: search, every book with its words, the '
        'line at the end', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, _switcher([]));
      expect(
        tester.getSemantics(_trigger),
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: false),
      );
      await tester.tap(_trigger);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(_trigger),
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: true),
      );
      for (final t in [
        '我的地址簿',
        '完全控制',
        '朋友们',
        '只读 · 所有者：李四',
        '共享地址簿的成员和权限由管理员设置',
      ]) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.byType(TextField), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the search field has the keyboard and filters by name', (
      tester,
    ) async {
      await pumpLg(tester, _switcher([]));
      await tester.tap(find.text('家里的电脑'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.enterText(find.byType(TextField), '朋友');
      await tester.pump();
      expect(find.text('朋友们'), findsOneWidget);
      expect(find.text('我的地址簿'), findsNothing);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('未找到匹配的地址簿'), findsOneWidget);
      expect(find.text('朋友们'), findsNothing);
    });

    testWidgets('picking a book reports it and closes the drop-down', (
      tester,
    ) async {
      final calls = <String>[];
      await pumpLg(tester, _switcher(calls));
      await tester.tap(find.text('家里的电脑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('朋友们'));
      await tester.pumpAndSettle();
      expect(calls, ['friends']);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('the chosen book has the check mark and is bold', (
      tester,
    ) async {
      await pumpLg(tester, _switcher([], selected: 'me'));
      await tester.tap(find.text('我的地址簿'));
      await tester.pumpAndSettle();
      LgMenuItem row(String name) =>
          tester.widget<LgMenuItem>(find.widgetWithText(LgMenuItem, name));
      expect(row('我的地址簿').checked, isTrue);
      expect(row('朋友们').checked, isFalse);
      expect(row('朋友们').description, '只读 · 所有者：李四');
    });

    testWidgets('Esc closes it and the button has the keyboard again', (
      tester,
    ) async {
      await pumpLg(tester, _switcher([]));
      await tester.tap(find.text('家里的电脑'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      // Enter on the button opens it again.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a click outside closes it without choosing', (tester) async {
      final calls = <String>[];
      await pumpLg(tester, _switcher(calls));
      await tester.tap(find.text('家里的电脑'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(780, 560));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(calls, isEmpty);
    });

    testWidgets('Down from the search field moves to the first book, Enter '
        'chooses it', (tester) async {
      final calls = <String>[];
      await pumpLg(tester, _switcher(calls));
      await tester.tap(find.text('家里的电脑'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, ['home']);
    });

    testWidgets('the drop-down stands under the button, at its left edge', (
      tester,
    ) async {
      await pumpLg(tester, _switcher([]));
      final button = tester.getRect(find.byType(LgBookSwitcher));
      await tester.tap(find.text('家里的电脑'));
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byType(LgBookPanel));
      expect(panel.left, closeTo(button.left, 1));
      expect(panel.top, greaterThan(button.top + 30));
      expect(panel.width, 340);
    });

    testWidgets('a long name is cut and the rest of the row stays', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _switcher(
          [],
          selected: 'long',
          books: const [
            LgBook(
              id: 'long',
              name: '家里所有的电脑、服务器、测试机和各个房间里的设备的地址簿，名字很长很长很长',
              detail: '可编辑 · 所有者：Alexandra Konstantinopoulos-Wang',
            ),
          ],
        ),
        mode: LgMode.detail,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('LgBookSwitcher with many books', () {
    final many = [
      for (var i = 1; i <= 20; i++)
        LgBook(id: 'b$i', name: '地址簿 $i', detail: '可编辑 · 所有者：张三'),
    ];

    // The switcher at the top or at the bottom of a 800 x 600 window.
    Widget placed(List<String> calls, {bool bottom = false}) => SizedBox(
      width: 780,
      height: 560,
      child: Align(
        alignment: bottom ? Alignment.bottomLeft : Alignment.topLeft,
        child: LgBookSwitcher(
          books: many,
          selectedId: 'b1',
          onSelect: calls.add,
          searchPlaceholder: '搜索地址簿',
          noMatchLabel: '未找到匹配的地址簿',
          hint: '共享地址簿的成员和权限由管理员设置',
          semanticLabel: '切换地址簿',
        ),
      ),
    );

    Rect panel(WidgetTester tester) => tester.getRect(find.byType(LgBookPanel));
    Rect window(WidgetTester tester) =>
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;

    testWidgets('the panel stays in the window, the books scroll between the '
        'search field and the line at the end', (tester) async {
      await pumpLg(tester, placed([]));
      await tester.tap(find.text('地址簿 1'));
      await tester.pumpAndSettle();
      final p = panel(tester);
      expect(p.bottom, lessThanOrEqualTo(window(tester).bottom));
      expect(p.height, greaterThan(300));
      // The last book is beyond the panel until the list is scrolled to it.
      expect(tester.getRect(find.text('地址簿 20')).top, greaterThan(p.bottom));
      final search = tester.getRect(find.byType(TextField));
      final hint = tester.getRect(find.text('共享地址簿的成员和权限由管理员设置'));
      expect(hint.bottom, lessThanOrEqualTo(p.bottom));
      // The wheel over the books scrolls them, the field and the line stay.
      final wheel = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        wheel.hover(tester.getCenter(find.text('地址簿 3'))),
      );
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 4000)));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(TextField)), search);
      expect(tester.getRect(find.text('共享地址簿的成员和权限由管理员设置')).top, hint.top);
      expect(
        tester.getRect(find.text('地址簿 20')).bottom,
        lessThanOrEqualTo(hint.top),
      );
    });

    testWidgets('moving down with the keys brings the focused book into '
        'view, the last one too', (tester) async {
      final calls = <String>[];
      await pumpLg(tester, placed(calls));
      await tester.tap(find.text('地址簿 1'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      final p = panel(tester);
      final last = tester.getRect(find.text('地址簿 20'));
      expect(last.top, greaterThanOrEqualTo(p.top));
      expect(last.bottom, lessThanOrEqualTo(p.bottom));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, ['b20']);
    });

    testWidgets('searching narrows the list and the panel with it', (
      tester,
    ) async {
      await pumpLg(tester, placed([]));
      await tester.tap(find.text('地址簿 1'));
      await tester.pumpAndSettle();
      final full = panel(tester).height;
      await tester.enterText(find.byType(TextField), '地址簿 2');
      await tester.pumpAndSettle();
      // 2, 20.
      expect(find.text('地址簿 20'), findsOneWidget);
      expect(find.text('地址簿 3'), findsNothing);
      expect(panel(tester).height, lessThan(full));
    });

    testWidgets('at the bottom of the window it opens above the button', (
      tester,
    ) async {
      await pumpLg(tester, placed([], bottom: true));
      final button = tester.getRect(find.byType(LgBookSwitcher));
      await tester.tap(find.text('地址簿 1'));
      await tester.pumpAndSettle();
      final p = panel(tester);
      expect(p.bottom, lessThanOrEqualTo(button.top));
      expect(p.top, greaterThanOrEqualTo(window(tester).top));
      // It scrolls there too.
      expect(tester.getRect(find.text('地址簿 20')).top, greaterThan(p.bottom));
      for (var i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(
        tester.getRect(find.text('地址簿 20')).bottom,
        lessThanOrEqualTo(p.bottom),
      );
    });

    testWidgets('the window getting smaller shortens the panel', (
      tester,
    ) async {
      await pumpLg(tester, placed([]));
      await tester.tap(find.text('地址簿 1'));
      await tester.pumpAndSettle();
      final before = panel(tester).height;
      tester.view.physicalSize = const Size(800, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();
      expect(panel(tester).height, lessThan(before));
      expect(panel(tester).bottom, lessThanOrEqualTo(420));
    });

    testWidgets('the mouse over the books does not take the keyboard from '
        'the search field', (tester) async {
      await pumpLg(tester, placed([]));
      await tester.tap(find.text('地址簿 1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '地址');
      await tester.pump();
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
      final mouse = await hover(tester, find.text('地址簿 5'));
      await mouse.moveTo(tester.getCenter(find.text('地址簿 7')));
      await tester.pump();
      expect(field.focusNode.hasFocus, isTrue);
      // What is typed after it is not lost.
      await tester.enterText(find.byType(TextField), '地址簿 1');
      await tester.pump();
      expect(find.text('地址簿 12'), findsOneWidget);
      expect(field.focusNode.hasFocus, isTrue);
    });

    testWidgets('a menu row takes the keyboard on hover by default, and not '
        'when it is told not to', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpLg(
        tester,
        LgMenuPanel(
          items: [
            TextField(focusNode: node, autofocus: true),
            LgMenuItem(label: '默认', onPressed: () {}),
            LgMenuItem(
              label: '不抢',
              requestFocusOnHover: false,
              onPressed: () {},
            ),
          ],
        ),
      );
      await tester.pump();
      expect(node.hasFocus, isTrue);
      final mouse = await hover(tester, find.text('不抢'));
      await tester.pump();
      expect(node.hasFocus, isTrue);
      await mouse.moveTo(tester.getCenter(find.text('默认')));
      await tester.pump();
      expect(node.hasFocus, isFalse);
    });
  });

  group('LgTagFilterBar', () {
    List<LgTagToggleItem> items({Set<String> on = const {}, int extra = 0}) => [
      LgTagToggleItem(id: 'none', label: '未标记', on: on.contains('none')),
      LgTagToggleItem(
        id: 'home',
        label: '家里',
        color: const Color(0xFFA65B80),
        on: on.contains('home'),
      ),
      LgTagToggleItem(
        id: 'work',
        label: '工作',
        color: const Color(0xFF2F7FB0),
        on: on.contains('work'),
      ),
      for (var i = 0; i < extra; i++)
        LgTagToggleItem(
          id: 'x$i',
          label: '另一个标签 $i',
          color: const Color(0xFF65873E),
        ),
    ];

    testWidgets('a click reports the id of the tag', (tester) async {
      final calls = <String>[];
      await pumpLg(tester, LgTagFilterBar(items: items(), onToggle: calls.add));
      await tester.tap(find.text('工作'));
      await tester.tap(find.text('未标记'));
      expect(calls, ['work', 'none']);
    });

    testWidgets('a right click reports id and place, except for "未标记"', (
      tester,
    ) async {
      final calls = <String>[];
      await pumpLg(
        tester,
        LgTagFilterBar(
          items: items(),
          onToggle: (_) {},
          onContextMenu: (id, p) => calls.add('$id@${p.dx.round()}'),
          noMenu: const {'none'},
        ),
      );
      final at = tester.getCenter(find.text('家里'));
      final g = await tester.startGesture(
        at,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await g.up();
      final none = await tester.startGesture(
        tester.getCenter(find.text('未标记')),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await none.up();
      expect(calls, ['home@${at.dx.round()}']);
    });

    testWidgets('a tag that is on says so, to the eye and to a reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        LgTagFilterBar(
          items: items(on: const {'home'}),
          onToggle: (_) {},
          semanticLabel: '标签筛选',
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('家里')),
        isSemantics(isButton: true, hasToggledState: true, isToggled: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('工作')),
        isSemantics(isButton: true, hasToggledState: true, isToggled: false),
      );
      expect(find.bySemanticsLabel('标签筛选'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('too many tags scroll sideways, and so does the wheel', (
      tester,
    ) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 300,
          child: LgTagFilterBar(items: items(extra: 6), onToggle: (_) {}),
        ),
      );
      final first = tester.getTopLeft(find.text('未标记')).dx;
      final wheel = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        wheel.hover(tester.getCenter(find.text('家里'))),
      );
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 120)));
      await tester.pump();
      expect(tester.getTopLeft(find.text('未标记')).dx, lessThan(first));
    });

    testWidgets('Tab goes from tag to tag and Enter switches one', (
      tester,
    ) async {
      final calls = <String>[];
      await pumpLg(tester, LgTagFilterBar(items: items(), onToggle: calls.add));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, ['home']);
    });

    testWidgets('without a handler the tags are grey and cannot be used', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, LgTagFilterBar(items: items(), onToggle: null));
      // Greyed to the eye ...
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(of: find.text('家里'), matching: find.byType(Opacity))
            .first,
      );
      expect(opacity.opacity, .6);
      // ... and to a reader: a button that is off.
      expect(
        tester.getSemantics(find.bySemanticsLabel('家里')),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
      // The keyboard does not stop on them.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<LgTagToggle>(),
        isNull,
      );
      handle.dispose();
    });

    testWidgets('the wheel is the bar\'s only when the bar can move that way', (
      tester,
    ) async {
      final page = ScrollController();
      addTearDown(page.dispose);
      Future<void> wheel(Finder at) async {
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(pointer.hover(tester.getCenter(at)));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 80)));
        await tester.pump();
      }

      // A bar that fits leaves the wheel to the page.
      await pumpLg(
        tester,
        SizedBox(
          height: 300,
          width: 600,
          child: SingleChildScrollView(
            controller: page,
            child: Column(
              children: [
                LgTagFilterBar(items: items(), onToggle: (_) {}),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      );
      await wheel(find.text('家里'));
      expect(page.offset, 80);

      // A bar that does not fit takes it, and gives it back at its end.
      await pumpLg(
        tester,
        SizedBox(
          height: 300,
          width: 300,
          child: SingleChildScrollView(
            controller: page,
            child: Column(
              children: [
                LgTagFilterBar(items: items(extra: 6), onToggle: (_) {}),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      );
      page.jumpTo(0);
      final first = tester.getTopLeft(find.text('未标记')).dx;
      await wheel(find.text('家里'));
      expect(tester.getTopLeft(find.text('未标记')).dx, lessThan(first));
      expect(page.offset, 0);
      // (The tags move away under the pointer: aim at the bar.)
      for (var i = 0; i < 20; i++) {
        await wheel(find.byType(LgTagFilterBar));
      }
      expect(page.offset, greaterThan(0));
    });

    testWidgets('the menu key and Shift+F10 open the menu of the tag that '
        'has the keyboard, under it', (tester) async {
      final calls = <String>[];
      await pumpLg(
        tester,
        LgTagFilterBar(
          items: items(),
          onToggle: (_) {},
          onContextMenu: (id, p) =>
              calls.add('$id@${p.dx.round()},${p.dy.round()}'),
          noMenu: const {'none'},
        ),
      );
      // "未标记" has the keyboard first: it has no menu.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      expect(calls, isEmpty);
      // Then "家里".
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      final chip = tester.getRect(
        find.ancestor(of: find.text('家里'), matching: find.byType(LgTagToggle)),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      expect(calls, ['home@${chip.left.round()},${chip.bottom.round()}']);
      // Shift+F10 does the same for "工作"; F10 alone does not.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      expect(calls, hasLength(1));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(calls, hasLength(2));
      expect(calls.last, startsWith('work@'));
    });
  });

  group('LgTagChooser', () {
    testWidgets('wraps onto more lines and toggles several', (tester) async {
      final calls = <String>[];
      await pumpLg(
        tester,
        SizedBox(
          width: 200,
          child: LgTagChooser(
            items: [
              for (var i = 0; i < 5; i++)
                LgTagToggleItem(
                  id: '$i',
                  label: '标签$i',
                  color: const Color(0xFFA65B80),
                  on: i == 1,
                ),
            ],
            onToggle: calls.add,
            semanticLabel: '标签',
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('标签4')).dy,
        greaterThan(tester.getTopLeft(find.text('标签0')).dy),
      );
      await tester.tap(find.text('标签0'));
      await tester.tap(find.text('标签1'));
      expect(calls, ['0', '1']);
    });
  });
}
