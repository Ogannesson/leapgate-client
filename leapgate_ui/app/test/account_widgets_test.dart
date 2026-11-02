import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_account.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_feedback.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_people_list.dart';

import 'helpers.dart';

/// The area as the home page has it: at the bottom of a column.
Widget _atBottom(Widget area) => SizedBox(
  width: 224,
  height: 500,
  child: Align(alignment: Alignment.bottomCenter, child: area),
);

LgAccountArea _signedIn(
  List<String> calls, {
  String initial = '张',
  String name = '张三',
}) => LgAccountArea.signedIn(
  initial: initial,
  name: name,
  handle: '@zhangsan',
  semanticLabel: '账号：$name @zhangsan',
  menuItems: [
    const LgAccountMenuInfo(label: '账号信息', handle: '@zhangsan'),
    LgMenuItem(label: '退出登录', onPressed: () => calls.add('out')),
  ],
);

void main() {
  group('LgAccountArea signed out', () {
    testWidgets('the button logs in, the hint is under it', (tester) async {
      var logins = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 224,
          child: LgAccountArea.signedOut(
            loginLabel: '登录',
            hint: '登录后可使用地址簿、同组设备和出口目录',
            onLogin: () => logins++,
          ),
        ),
      );
      expect(find.text('登录后可使用地址簿、同组设备和出口目录'), findsOneWidget);
      final button = find.widgetWithText(LgButton, '登录');
      // It fills the width of the column.
      expect(tester.getSize(button).width, 224);
      await tester.tap(button);
      expect(logins, 1);
    });

    testWidgets('is named by its button', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        LgAccountArea.signedOut(
          loginLabel: '登录',
          hint: '登录后可使用地址簿',
          onLogin: () {},
        ),
      );
      expect(find.bySemanticsLabel('登录'), findsOneWidget);
      handle.dispose();
    });
  });

  group('LgAccountArea signed in', () {
    testWidgets('shows the letter, the name and the account', (tester) async {
      await pumpLg(tester, SizedBox(width: 224, child: _signedIn([])));
      expect(find.text('张'), findsOneWidget);
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('@zhangsan'), findsOneWidget);
    });

    testWidgets('is one named button that tells whether its menu is open', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, SizedBox(width: 224, child: _signedIn([])));
      final node = find.bySemanticsLabel('账号：张三 @zhangsan');
      expect(node, findsOneWidget);
      expect(
        tester.getSemantics(node),
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: false),
      );
      await tester.tap(node);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel('账号：张三 @zhangsan')),
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: true),
      );
      handle.dispose();
    });

    testWidgets('the menu opens above the row at the bottom and runs an item', (
      tester,
    ) async {
      final calls = <String>[];
      await pumpLg(tester, _atBottom(_signedIn(calls)));
      final row = tester.getRect(find.text('张三'));
      await tester.tap(find.text('张三'));
      await tester.pumpAndSettle();
      expect(find.text('账号信息'), findsOneWidget);
      expect(find.text('退出登录'), findsOneWidget);
      // Above the row, and as wide as the column.
      expect(tester.getRect(find.text('退出登录')).bottom, lessThan(row.top));
      await tester.tap(find.text('退出登录'));
      await tester.pumpAndSettle();
      expect(calls, ['out']);
      expect(find.text('账号信息'), findsNothing);
    });

    testWidgets('the info row is read as a whole and does nothing', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, _atBottom(_signedIn([])));
      await tester.tap(find.text('张三'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('账号信息, @zhangsan'), findsOneWidget);
      await tester.tap(find.text('账号信息'));
      await tester.pumpAndSettle();
      // Still open: the row is no button.
      expect(find.text('退出登录'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a long name is cut, not overflowing', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 224,
          child: _signedIn(
            [],
            initial: 'A',
            name: 'Alexandra Konstantinopoulos-Wang the third',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits in the detail mode too', (tester) async {
      await pumpLg(
        tester,
        _atBottom(_signedIn([])),
        mode: LgMode.detail,
        brightness: Brightness.dark,
      );
      await tester.tap(find.text('张三'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('账号信息'), findsOneWidget);
    });
  });

  group('LgAccountConfirm', () {
    Widget confirm(List<String> calls) => SizedBox(
      width: 224,
      child: LgAccountConfirm(
        title: '退出登录？',
        body: '退出后，地址簿、同组设备和出口目录将不可用。',
        onEscape: () => calls.add('esc'),
        actions: [
          LgDialogAction(
            label: '退出登录',
            kind: LgButtonKind.primary,
            isDefault: true,
            onPressed: () => calls.add('out'),
          ),
          LgDialogAction(label: '取消', onPressed: () => calls.add('cancel')),
        ],
      ),
    );

    testWidgets('asks, and each button answers', (tester) async {
      final calls = <String>[];
      await pumpLg(tester, confirm(calls));
      expect(find.text('退出登录？'), findsOneWidget);
      expect(find.text('退出后，地址簿、同组设备和出口目录将不可用。'), findsOneWidget);
      await tester.tap(find.widgetWithText(LgButton, '取消'));
      await tester.tap(find.widgetWithText(LgButton, '退出登录'));
      expect(calls, ['cancel', 'out']);
    });

    testWidgets('the default button has the keyboard: Enter answers it, '
        'Esc leaves', (tester) async {
      final calls = <String>[];
      await pumpLg(tester, confirm(calls));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(calls, ['out', 'esc']);
    });

    testWidgets('names the card by its question', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, confirm([]));
      expect(find.bySemanticsLabel('退出登录？'), findsWidgets);
      handle.dispose();
    });
  });

  group('LgPeopleList', () {
    const people = [
      LgPerson(id: 'zhangsan', initial: '张', name: '张三', isMe: true),
      LgPerson(id: 'lisi', initial: '李', name: '李四'),
      LgPerson(id: 'wangwu', initial: '王', name: '王五'),
    ];

    Widget list(
      List<String> calls, {
      String? selected,
      TextEditingController? search,
    }) => LgPeopleList(
      people: people,
      selectedId: selected,
      onSelect: (id) => calls.add('select $id'),
      onClear: () => calls.add('clear'),
      searchController: search ?? TextEditingController(),
      onSearchChanged: (v) => calls.add('search $v'),
      searchPlaceholder: '搜索人员',
      meLabel: '（我）',
      clearLabel: '取消筛选',
      semanticLabel: '人员',
    );

    testWidgets('lists the people, you marked', (tester) async {
      await pumpLg(tester, list([]));
      for (final n in ['张三', '李四', '王五', '（我）']) {
        expect(find.text(n), findsOneWidget);
      }
      // The first row is you.
      expect(
        tester.getTopLeft(find.text('张三')).dy,
        lessThan(tester.getTopLeft(find.text('李四')).dy),
      );
      // Nobody is chosen: no "×".
      expect(
        find.byWidgetPredicate((w) => w is LgIcon && w.icon == LgIcons.x),
        findsNothing,
      );
    });

    testWidgets('a click on a person selects, on the chosen one clears', (
      tester,
    ) async {
      final calls = <String>[];
      await pumpLg(tester, list(calls));
      await tester.tap(find.text('李四'));
      expect(calls, ['select lisi']);
      calls.clear();
      await pumpLg(tester, list(calls, selected: 'lisi'));
      await tester.tap(find.text('李四'));
      expect(calls, ['clear']);
    });

    testWidgets('the chosen row has an "×" with its own name', (tester) async {
      final handle = tester.ensureSemantics();
      final calls = <String>[];
      await pumpLg(tester, list(calls, selected: 'lisi'));
      final x = find.bySemanticsLabel('取消筛选');
      expect(x, findsOneWidget);
      await tester.tap(x);
      expect(calls, ['clear']);
      handle.dispose();
    });

    testWidgets('rows are named by the person, with the mark for you and '
        'selected when chosen', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, list([], selected: 'lisi'));
      expect(find.bySemanticsLabel('张三 （我）'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('李四')),
        isSemantics(isButton: true, hasSelectedState: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('王五')),
        isSemantics(isButton: true, hasSelectedState: true, isSelected: false),
      );
      handle.dispose();
    });

    testWidgets('typing in the search field is reported', (tester) async {
      final calls = <String>[];
      await pumpLg(tester, list(calls));
      await tester.enterText(find.byType(TextField), '李');
      expect(calls, ['search 李']);
    });

    testWidgets('Tab reaches the rows and Enter chooses', (tester) async {
      final calls = <String>[];
      await pumpLg(tester, list(calls));
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, ['select lisi']);
    });

    testWidgets('long names do not overflow', (tester) async {
      await pumpLg(
        tester,
        LgPeopleList(
          people: const [
            LgPerson(
              id: 'x',
              initial: 'K',
              name: 'Konstantinopoulos-Wang Alexandra Maria',
              isMe: true,
            ),
          ],
          selectedId: 'x',
          onSelect: (_) {},
          onClear: () {},
          searchController: TextEditingController(),
          searchPlaceholder: 'Search people',
          meLabel: '(me)',
          clearLabel: 'Clear filter',
        ),
        mode: LgMode.detail,
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the person avatar shows its letter in a circle', (tester) async {
    await pumpLg(tester, const LgPersonAvatar(initial: '张'));
    expect(find.text('张'), findsOneWidget);
    expect(tester.getSize(find.byType(LgPersonAvatar)), const Size(32, 32));
    // An icon of the app is not used for a person.
    expect(find.byType(LgIcon), findsNothing);
  });
}
