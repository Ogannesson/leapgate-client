import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_banner.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';
import 'package:leapgate_ui/widgets/lg_settings_layout.dart';
import 'package:leapgate_ui/widgets/lg_settings_rows.dart';

import 'helpers.dart';

Widget _nav({
  required List<String> log,
  String selected = '权限',
  List<String> locked = const [],
  TextEditingController? search,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  ValueChanged<int>? onMove,
}) => SizedBox(
  width: kLgSettingsNavWidth,
  height: 400,
  child: LgSettingsNav(
    semanticLabel: '设置分区',
    search: LgSettingsSearchField(
      controller: search ?? TextEditingController(),
      placeholder: '搜索设置',
      clearLabel: '清除搜索',
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onMove: onMove,
    ),
    children: [
      LgSettingsNavGroup(
        title: '传入连接',
        items: [
          for (final label in ['访问与密码', '权限', '二次验证'])
            LgSettingsNavItem(
              label: label,
              selected: label == selected,
              locked: locked.contains(label),
              lockedLabel: '已锁定',
              onPressed: () => log.add(label),
            ),
        ],
      ),
    ],
  ),
);

void main() {
  group('LgSettingsNav', () {
    testWidgets(
      'a click on a section reports it; the group name is not a button',
      (tester) async {
        final log = <String>[];
        await pumpLg(tester, _nav(log: log));
        await tester.tap(find.text('二次验证'));
        await tester.tap(find.text('传入连接'));
        expect(log, ['二次验证']);
      },
    );

    testWidgets('the selected one and the locked ones say so to a reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        _nav(log: [], selected: '权限', locked: ['访问与密码', '权限']),
      );
      final selected = tester.getSemantics(find.bySemanticsLabel('权限, 已锁定'));
      expect(selected.flagsCollection.isSelected.name, 'isTrue');
      final other = tester.getSemantics(find.bySemanticsLabel('访问与密码, 已锁定'));
      expect(other.flagsCollection.isSelected.name, 'isFalse');
      // Not locked: the name alone.
      expect(find.bySemanticsLabel('二次验证'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('keyboard: Tab reaches a section and Enter opens it', (
      tester,
    ) async {
      final log = <String>[];
      await pumpLg(tester, _nav(log: log));
      // The search box takes the first Tab, the sections follow.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(log, ['访问与密码']);
    });

    testWidgets(
      'item height follows the mode: lh + 8 (30), the row height in detail',
      (tester) async {
        Future<double> height(LgMode mode) async {
          await pumpLg(tester, _nav(log: []), mode: mode);
          return tester
              .getSize(
                find
                    .ancestor(
                      of: find.text('权限'),
                      matching: find.byType(Container),
                    )
                    .first,
              )
              .height;
        }

        expect(await height(LgMode.compact), LgSizes.compact.lh + 8);
        expect(await height(LgMode.detail), LgSizes.detail.row);
      },
    );
  });

  testWidgets('a name too long for a line goes on to a second one', (
    tester,
  ) async {
    Future<double> height(String label) async {
      await pumpLg(
        tester,
        SizedBox(
          width: kLgSettingsNavWidth,
          child: LgSettingsNavItem(label: label, onPressed: () {}),
        ),
      );
      return tester.getSize(find.byType(LgSettingsNavItem)).height;
    }

    expect(await height('权限'), LgSizes.compact.lh + 8);
    // The test font is a square per letter, so 16 of them are two lines.
    expect(await height('Access passwords'), 2 * LgSizes.compact.lh + 8);
  });

  group('LgSettingsSearchField', () {
    testWidgets(
      'typing is reported; the clear button shows only with text and clears',
      (tester) async {
        final changes = <String>[];
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpLg(
          tester,
          _nav(log: [], search: controller, onChanged: changes.add),
        );
        expect(find.bySemanticsLabel('清除搜索'), findsNothing);
        await tester.enterText(find.byType(TextField), '密码');
        await tester.pump();
        expect(changes.last, '密码');
        await tester.tap(find.byTooltip('清除搜索'));
        await tester.pump();
        expect(controller.text, '');
        expect(changes.last, '');
      },
    );

    testWidgets(
      'Up and Down move, Enter submits, Esc clears; the focus stays in the box',
      (tester) async {
        final moves = <int>[];
        final submits = <String>[];
        final changes = <String>[];
        final controller = TextEditingController(text: '密码');
        addTearDown(controller.dispose);
        await pumpLg(
          tester,
          _nav(
            log: [],
            search: controller,
            onMove: moves.add,
            onSubmitted: submits.add,
            onChanged: changes.add,
          ),
        );
        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        expect(moves, [1, 1, -1]);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(submits, ['密码']);
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<EditableText>(),
          isNotNull,
          reason: 'Enter keeps the focus in the box',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(controller.text, '');
        expect(changes.last, '');
      },
    );

    testWidgets('Esc in an empty box is left alone', (tester) async {
      final changes = <String>[];
      await pumpLg(tester, _nav(log: [], onChanged: changes.add));
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(changes, isEmpty);
    });
  });

  group('LgSettingsContent', () {
    Widget content(
      double width, {
      List<Widget>? children,
      bool locked = false,
    }) => SizedBox(
      width: width,
      height: 600,
      child: LgSettingsContent(
        title: '访问与密码',
        lockBar: locked
            ? LgSettingsLockBar(text: '已锁定', unlockLabel: '解锁', onUnlock: () {})
            : null,
        locked: locked,
        children:
            children ??
            [
              LgSettingsBlock(
                children: [
                  LgSettingsRow(
                    name: '长度',
                    wide: true,
                    control: LgSegmented<int>(
                      segments: const [LgSegment(6, '6'), LgSegment(8, '8')],
                      selected: 6,
                      onChanged: (_) {},
                    ),
                  ),
                ],
              ),
            ],
      ),
    );

    testWidgets(
      'is at most 640 wide, on the left, and the blocks are 8 short of it',
      (tester) async {
        await pumpLg(tester, content(1000));
        expect(tester.getTopLeft(find.byType(LgSettingsBlock)).dx, 0);
        expect(tester.getSize(find.byType(LgSettingsBlock)).width, 632);
      },
    );

    testWidgets(
      'narrower than 560 a wide control goes under the name; wider it stays beside it',
      (tester) async {
        await pumpLg(tester, content(508 + LgSpace.s2));
        var name = tester.getRect(find.text('长度'));
        var control = tester.getRect(find.byType(LgSegmented<int>));
        expect(control.top, greaterThanOrEqualTo(name.bottom));
        expect(control.left, name.left);

        await pumpLg(tester, content(700));
        name = tester.getRect(find.text('长度'));
        control = tester.getRect(find.byType(LgSegmented<int>));
        expect(control.center.dy, closeTo(name.center.dy, 1));
        expect(control.left, greaterThan(name.right));
      },
    );

    testWidgets('the 560 line is a line: 559 is narrow, 560 is not', (
      tester,
    ) async {
      // The content box is 8 less than the column (the scroll padding).
      await pumpLg(tester, content(559 + 8));
      expect(
        tester.getRect(find.byType(LgSegmented<int>)).top,
        greaterThan(tester.getRect(find.text('长度')).bottom - 1),
      );
      await pumpLg(tester, content(560 + 8));
      expect(
        tester.getRect(find.byType(LgSegmented<int>)).center.dy,
        closeTo(tester.getRect(find.text('长度')).center.dy, 1),
      );
    });

    testWidgets('locked: the lock bar works, what is under it cannot be used', (
      tester,
    ) async {
      var on = false;
      await pumpLg(
        tester,
        content(
          700,
          locked: true,
          children: [
            LgSettingsBlock(
              children: [
                LgSettingsRow.toggle(
                  name: '仅使用数字',
                  value: on,
                  onChanged: (v) => on = v,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.tap(find.byType(LgSwitch), warnIfMissed: false);
      expect(on, isFalse);
      // Tab does not go into it either.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(on, isFalse);
      // The controls are still in the tree for a reader.
      expect(find.byType(LgSwitch), findsOneWidget);
    });

    testWidgets('unlocking keeps what was typed in the controls under it', (
      tester,
    ) async {
      final controller = TextEditingController(text: '21118');
      addTearDown(controller.dispose);
      Widget page(bool locked) => content(
        700,
        locked: locked,
        children: [
          LgSettingsBlock(
            children: [
              LgSettingsRow(
                name: '端口',
                control: SizedBox(
                  width: 96,
                  child: TextField(controller: controller),
                ),
              ),
            ],
          ),
        ],
      );
      await pumpLg(tester, page(true));
      await pumpLg(tester, page(false));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller,
        controller,
      );
      expect(find.text('21118'), findsOneWidget);
    });

    testWidgets('scrolls by itself and a long section is reachable', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpLg(
        tester,
        SizedBox(
          width: 700,
          height: 200,
          child: LgSettingsContent(
            title: '会话',
            controller: controller,
            children: [
              for (var i = 0; i < 12; i++)
                LgSettingsBlock(
                  children: [
                    LgSettingsRow.toggle(
                      name: '项 $i',
                      value: false,
                      onChanged: (_) {},
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
      expect(controller.position.maxScrollExtent, greaterThan(0));
      await tester.scrollUntilVisible(find.text('项 11'), 200);
      expect(find.text('项 11'), findsOneWidget);
    });
  });

  group('LgSettingsContent.gapBetween (the margins of the mockup)', () {
    const block = LgSettingsBlock(children: []);
    const gapped = LgSettingsBlock(gap: true, children: []);
    const sub = LgSettingsSubtitle('高级');
    const note = LgSettingsNote('原因');

    test('the first child sits 16 under the title', () {
      expect(LgSettingsContent.gapBetween(null, block), 16);
      expect(LgSettingsContent.gapBetween(null, sub), 16);
    });

    test('blocks are 12 apart, a gapped one 24', () {
      expect(LgSettingsContent.gapBetween(block, block), 12);
      expect(LgSettingsContent.gapBetween(block, gapped), 24);
    });

    test('a small title is 24 above and 8 over what it titles', () {
      expect(LgSettingsContent.gapBetween(block, sub), 24);
      expect(LgSettingsContent.gapBetween(sub, block), 8);
    });

    test(
      'a note is 16 under the block it explains and 8 over the dimmed one',
      () {
        expect(LgSettingsContent.gapBetween(block, note), 16);
        expect(LgSettingsContent.gapBetween(note, block), 8);
      },
    );

    test('other widgets get 12', () {
      expect(
        LgSettingsContent.gapBetween(const SizedBox(), const SizedBox()),
        12,
      );
      expect(
        LgSettingsContent.gapBetween(
          const LgBanner(tone: LgTone.info, text: 'x'),
          block,
        ),
        12,
      );
    });
  });

  group('LgSettingsLockBar', () {
    Widget bar({VoidCallback? onUnlock, String? error, bool busy = false}) =>
        SizedBox(
          width: 600,
          child: LgSettingsLockBar(
            text: '已锁定。修改这些设置需要管理员权限。',
            unlockLabel: '解锁',
            onUnlock: onUnlock,
            error: error,
            busy: busy,
          ),
        );

    testWidgets('the unlock button runs the callback', (tester) async {
      var n = 0;
      await pumpLg(tester, bar(onUnlock: () => n++));
      expect(find.text('已锁定。修改这些设置需要管理员权限。'), findsOneWidget);
      await tester.tap(find.text('解锁'));
      expect(n, 1);
    });

    testWidgets('while it is asked for the button does not respond', (
      tester,
    ) async {
      var n = 0;
      await pumpLg(tester, bar(onUnlock: () => n++, busy: true));
      await tester.tap(find.text('解锁'));
      expect(n, 0);
    });

    testWidgets('the line that says it failed is under the bar', (
      tester,
    ) async {
      await pumpLg(tester, bar(error: '未获得管理员权限，设置仍处于锁定状态'));
      final line = tester.getRect(find.text('未获得管理员权限，设置仍处于锁定状态'));
      final text = tester.getRect(find.text('已锁定。修改这些设置需要管理员权限。'));
      expect(line.top, greaterThan(text.bottom));
    });

    testWidgets('the button is a button with its name', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, bar(onUnlock: () {}));
      final s = tester.getSemantics(find.bySemanticsLabel('解锁'));
      expect(s.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });
}
