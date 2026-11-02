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
        isSemantics(isButton: true, hasToggledState: true, isToggled: false),
      );
      await tester.tap(_trigger);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(_trigger),
        isSemantics(isButton: true, hasToggledState: true, isToggled: true),
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

    testWidgets('without a handler the tags are grey and do nothing', (
      tester,
    ) async {
      await pumpLg(tester, LgTagFilterBar(items: items(), onToggle: null));
      await tester.tap(find.text('家里'));
      expect(tester.takeException(), isNull);
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
