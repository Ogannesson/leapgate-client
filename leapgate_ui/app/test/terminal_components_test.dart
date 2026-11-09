// Behaviour of the M9b terminal components (docs LEAPGATE.md §10.18, 14 §2.6): the bar of the
// terminal view with its middle part and "⋯", the tab strip of the terminals, the theme and the
// ground of the terminal area, the clipboard request, and the system account in the connection
// panel. Callbacks are called, a greyed part does not respond, the keyboard reaches the parts,
// the names a screen reader gets are there. Nothing here compares pixels.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_term_tabs.dart';
import 'package:leapgate_ui/widgets/lg_terminal_parts.dart';
import 'package:leapgate_ui/widgets/lg_terminal_theme.dart';
import 'package:leapgate_ui/widgets/lg_view_bar.dart';
import 'package:xterm/xterm.dart' as xterm;

import 'helpers.dart';

List<LgTermTabItem> _tabs(int n) => [
  for (var i = 1; i <= n; i++)
    LgTermTabItem(label: '终端 $i', closeLabel: '关闭终端 $i'),
];

Widget _strip({
  int count = 3,
  int selected = 1,
  double width = 900,
  List<String>? log,
  bool canNew = true,
}) => SizedBox(
  width: width,
  height: 52,
  child: LgTermTabs(
    tabs: _tabs(count),
    selected: selected,
    onSelect: (i) => log?.add('select $i'),
    onClose: (i) => log?.add('close $i'),
    onNew: canNew ? () => log?.add('new') : null,
    semanticLabel: '终端',
    newLabel: '新建终端',
    newTooltip: '新建终端（Ctrl+Shift+T）',
    allLabel: '全部终端',
  ),
);

Finder _barButton(LgIcons icon) => find.byWidgetPredicate(
  (w) => w is LgBarIconButton && w.icon == icon,
  description: 'LgBarIconButton ${icon.name}',
);

void main() {
  group('LgViewBar', () {
    Widget bar({Widget? middle, Widget? more}) => SizedBox(
      width: 1000,
      child: LgViewBar(
        viewSwitch: const Text('终端'),
        route: const Text('直连'),
        middle: middle,
        more: more,
        disconnectLabel: '断开',
        onDisconnect: () {},
      ),
    );

    testWidgets('without the new slots the bar is what it was', (tester) async {
      await pumpLg(tester, bar());
      final box = tester.getRect(find.byType(LgViewBar));
      // "断开" at the far end, 12 px from the edge; nothing between but empty space.
      expect(
        tester.getRect(find.byType(LgButton)).right,
        box.right - LgSpace.s3,
      );
      expect(find.byType(LgTermTabs), findsNothing);
    });

    testWidgets('the middle part gets the width that is left, after a rule', (
      tester,
    ) async {
      await pumpLg(
        tester,
        bar(
          middle: const SizedBox.expand(key: ValueKey('mid')),
          more: const SizedBox(key: ValueKey('more'), width: 36, height: 36),
        ),
      );
      final mid = tester.getRect(find.byKey(const ValueKey('mid')));
      final route = tester.getRect(find.text('直连'));
      final more = tester.getRect(find.byKey(const ValueKey('more')));
      final disconnect = tester.getRect(find.byType(LgButton));
      // 12 px on either side of a 1 px rule, then the middle, which runs up to "⋯".
      expect(mid.left, route.right + LgSpace.s3 + 1 + LgSpace.s3);
      expect(mid.right, more.left);
      expect(more.right + LgSpace.s2, disconnect.left);
    });
  });

  group('LgTermTabs', () {
    testWidgets('select, close and new call back with what was meant', (
      tester,
    ) async {
      final log = <String>[];
      await pumpLg(tester, _strip(log: log));
      await tester.tap(find.text('终端 1'));
      await tester.tap(find.text('终端 3'));
      expect(log, ['select 0', 'select 2']);

      final handle = tester.ensureSemantics();
      await tester.tap(find.bySemanticsLabel('关闭终端 2'));
      await tester.tap(_barButton(LgIcons.plus));
      expect(log, ['select 0', 'select 2', 'close 1', 'new']);
      handle.dispose();
    });

    testWidgets('a greyed "+" does not respond', (tester) async {
      final log = <String>[];
      await pumpLg(tester, _strip(log: log, canNew: false));
      await tester.tap(_barButton(LgIcons.plus), warnIfMissed: false);
      expect(log, isEmpty);
    });

    testWidgets('no tabs: only "+" is left', (tester) async {
      await pumpLg(tester, _strip(count: 0, selected: 0, canNew: false));
      expect(find.text('终端 1'), findsNothing);
      expect(_barButton(LgIcons.plus), findsOneWidget);
    });

    testWidgets('the tabs and the buttons have names of their own', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, _strip());
      expect(
        tester.getSemantics(find.bySemanticsLabel('终端 2')),
        isSemantics(
          label: '终端 2',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('终端 1')),
        isSemantics(
          label: '终端 1',
          isButton: true,
          hasSelectedState: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      for (final name in ['关闭终端 1', '关闭终端 2', '关闭终端 3', '新建终端']) {
        expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
      }
      // The strip is a group named for what it holds.
      expect(find.bySemanticsLabel('终端'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('"+" shows its tooltip, with the shortcut', (tester) async {
      await pumpLg(tester, _strip());
      await hover(tester, _barButton(LgIcons.plus));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('新建终端（Ctrl+Shift+T）'), findsOneWidget);
    });

    testWidgets('the keyboard reaches a tab and Enter selects it', (
      tester,
    ) async {
      final log = <String>[];
      await pumpLg(tester, _strip(log: log, selected: 0));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(log, ['select 0']);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab); // its close button
      await tester.sendKeyEvent(LogicalKeyboardKey.tab); // the next tab
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(log, ['select 0', 'select 1']);
    });

    testWidgets('every tab fits: no list of all tabs', (tester) async {
      await pumpLg(tester, _strip());
      await tester.pump();
      expect(_barButton(LgIcons.chevD), findsNothing);
    });

    testWidgets('too many tabs: they scroll and the list of all appears', (
      tester,
    ) async {
      final log = <String>[];
      // The test font is as wide as it is tall: a tab is 108 px, six of them do not fit in 480.
      await pumpLg(tester, _strip(count: 6, selected: 0, width: 480, log: log));
      await tester.pump();
      await tester.pump();
      expect(_barButton(LgIcons.chevD), findsOneWidget);
      // The last tabs are beyond the strip's end, cut off.
      final all = tester.getRect(_barButton(LgIcons.chevD));
      expect(tester.getRect(find.text('终端 6')).left, greaterThan(all.left));

      // The list holds every tab, the current one checked.
      await tester.tap(_barButton(LgIcons.chevD));
      await tester.pumpAndSettle();
      for (var i = 1; i <= 6; i++) {
        expect(find.text('终端 $i'), findsWidgets);
      }
      await tester.tap(find.widgetWithText(LgMenuItem, '终端 5'));
      await tester.pumpAndSettle();
      expect(log, ['select 4']);
    });

    testWidgets('the selected tab is brought into view when it changes', (
      tester,
    ) async {
      Widget strip(int selected) =>
          _strip(count: 6, selected: selected, width: 480);
      await pumpLg(tester, strip(0));
      await tester.pump();
      await tester.pump();
      final viewport = tester.getRect(find.byType(SingleChildScrollView));

      await pumpLg(tester, strip(5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final tab = tester.getRect(find.text('终端 6'));
      expect(tab.right, lessThanOrEqualTo(viewport.right));
      expect(tab.left, greaterThanOrEqualTo(viewport.left));
    });

    testWidgets('the wheel scrolls the strip sideways', (tester) async {
      await pumpLg(tester, _strip(count: 6, selected: 0, width: 480));
      await tester.pump();
      await tester.pump();
      final before = tester.getRect(find.text('终端 1')).left;
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final at = tester.getCenter(find.text('终端 2'));
      await gesture.addPointer(location: at);
      addTearDown(gesture.removePointer);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: at,
          kind: PointerDeviceKind.mouse,
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pump();
      expect(tester.getRect(find.text('终端 1')).left, lessThan(before));
    });
  });

  group('LgViewMoreButton', () {
    testWidgets('opens its menu and the items call back', (tester) async {
      final log = <String>[];
      await pumpLg(
        tester,
        Align(
          alignment: Alignment.topRight,
          child: LgViewMoreButton(
            label: '更多',
            items: [
              LgMenuItem(label: '新建终端', onPressed: () => log.add('new')),
              LgMenuItem(
                label: '断开连接后保持终端会话',
                checked: true,
                onPressed: () => log.add('keep'),
              ),
            ],
          ),
        ),
      );
      await tester.tap(_barButton(LgIcons.more));
      await tester.pumpAndSettle();
      await tester.tap(find.text('断开连接后保持终端会话'));
      await tester.pumpAndSettle();
      expect(log, ['keep']);
    });

    testWidgets('the menu hangs from the button\'s right edge', (tester) async {
      await pumpLg(
        tester,
        Align(
          alignment: Alignment.topRight,
          child: LgViewMoreButton(
            label: '更多',
            items: [LgMenuItem(label: '新建终端', onPressed: () {})],
          ),
        ),
      );
      final button = tester.getRect(_barButton(LgIcons.more));
      await tester.tap(_barButton(LgIcons.more));
      await tester.pumpAndSettle();
      final menu = tester.getRect(
        find.ancestor(
          of: find.text('新建终端'),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(menu.right, closeTo(button.right, 20));
      expect(menu.width, closeTo(320, 40));
    });

    testWidgets('names the button and says whether the menu is open', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        LgViewMoreButton(
          label: '更多',
          items: [LgMenuItem(label: '新建终端', onPressed: () {})],
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('更多')),
        isSemantics(
          label: '更多',
          isButton: true,
          hasExpandedState: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      handle.dispose();
    });
  });

  group('the terminal theme', () {
    test('is made of the tokens', () {
      const term = LgTermColors.standard;
      final theme = lgTerminalTheme();
      expect(theme.background, term.bg);
      expect(theme.foreground, term.fg);
      expect(theme.cursor, term.cursor);
      expect(
        theme.selection,
        term.cursor.withValues(alpha: kLgTermSelectionAlpha),
      );
      expect(theme.black, term.black);
      expect(theme.red, term.red);
      expect(theme.white, term.white);
      expect(theme.brightBlack, term.brightBlack);
      expect(theme.brightWhite, term.brightWhite);
      expect(theme.brightCyan, term.brightCyan);
    });

    test('the values are the mockup\'s', () {
      const term = LgTermColors.standard;
      expect(term.bg, const Color(0xFF0D1A1D));
      expect(term.fg, const Color(0xFFD8E4E4));
      expect(term.fg2, const Color(0xFF8FA6A9));
      expect(term.cursor, const Color(0xFF86C9D4));
      expect(term.sel, const Color(0xFF337483));
      expect(term.green, const Color(0xFF5FD38D));
      expect(term.brightWhite, const Color(0xFFF3FAFA));
    });

    testWidgets('both themes carry the same terminal colours', (tester) async {
      late LgTokens light;
      late LgTokens dark;
      await pumpLg(
        tester,
        Builder(
          builder: (context) {
            light = LgTokens.of(context);
            return const SizedBox();
          },
        ),
      );
      await pumpLg(
        tester,
        Builder(
          builder: (context) {
            dark = LgTokens.of(context);
            return const SizedBox();
          },
        ),
        brightness: Brightness.dark,
      );
      expect(light.term, same(dark.term));
      expect(light.colors.bg, isNot(dark.colors.bg));
    });

    test('text stays readable under the selection (4.5:1 or better)', () {
      // The selection is painted over the text, so what is seen is the text and the ground each
      // under the same layer.
      const term = LgTermColors.standard;
      final layer = lgTerminalTheme().selection;
      double lum(Color c) => c.computeLuminance();
      double ratio(Color a, Color b) {
        final hi = lum(a) > lum(b) ? a : b;
        final lo = identical(hi, a) ? b : a;
        return (lum(hi) + .05) / (lum(lo) + .05);
      }

      final ground = Color.alphaBlend(layer, term.bg);
      for (final text in [
        term.fg,
        term.fg2,
        term.red,
        term.green,
        term.yellow,
        term.blue,
        term.cyan,
        term.brightBlue,
      ]) {
        expect(
          ratio(Color.alphaBlend(layer, text), ground),
          greaterThanOrEqualTo(4.5),
          reason: '$text',
        );
      }
      // The ground is clearly lifted from the unselected one.
      expect(ratio(ground, term.bg), greaterThan(1.4));
    });

    test('the face and the size', () {
      final style = lgTerminalStyle();
      expect(style.fontSize, 13);
      expect(style.height, 1.2);
      expect(style.fontFamily, 'Cascadia Mono');
      expect(style.fontFamilyFallback, contains('Consolas'));
      expect(lgTerminalStyle(fontSize: 16).fontSize, 16);
    });

    test('a note is written in the second colour and ends it', () {
      expect(
        lgTerminalNote('无法打开终端'),
        '\u001b[38;2;143;166;169m无法打开终端\u001b[0m',
      );
    });

    test('a terminal takes the note and keeps what it writes', () {
      final terminal = xterm.Terminal()..write(lgTerminalNote('note'));
      expect(terminal.buffer.lines[0].toString().trimRight(), 'note');
    });
  });

  group('the terminal area', () {
    testWidgets('is dark in both themes and may be dimmed', (tester) async {
      for (final b in Brightness.values) {
        await pumpLg(
          tester,
          const SizedBox(
            width: 300,
            height: 100,
            child: LgTerminalSurface(child: SizedBox(key: ValueKey('in'))),
          ),
          brightness: b,
        );
        final fill = tester.widget<ColoredBox>(
          find
              .descendant(
                of: find.byType(LgTerminalSurface),
                matching: find.byType(ColoredBox),
              )
              .first,
        );
        expect(fill.color, LgTermColors.standard.bg, reason: b.name);
        // 5 px at each side.
        expect(tester.getSize(find.byKey(const ValueKey('in'))).width, 290);
      }

      await pumpLg(
        tester,
        const SizedBox(
          width: 300,
          height: 100,
          child: LgTerminalSurface(dimmed: true, child: SizedBox()),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(LgTerminalSurface),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
    });

    testWidgets('the scroll bar is always there, in the area\'s colours', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpLg(
        tester,
        SizedBox(
          width: 300,
          height: 100,
          child: LgTerminalScrollbar(
            controller: controller,
            child: ListView(
              controller: controller,
              children: [for (var i = 0; i < 30; i++) Text('line $i')],
            ),
          ),
        ),
      );
      await tester.pump();
      final bar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
      expect(bar.thumbVisibility, isTrue);
      expect(bar.trackVisibility, isTrue);
      expect(bar.thickness, 10);
      expect(bar.thumbColor, LgTermColors.standard.thumb);
      expect(bar.trackColor, LgTermColors.standard.track);
    });

    testWidgets('a real terminal view takes the theme and the style', (
      tester,
    ) async {
      final terminal = xterm.Terminal()..write('hello \u001b[31mred\u001b[0m');
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpLg(
        tester,
        SizedBox(
          width: 400,
          height: 160,
          child: LgTerminalSurface(
            child: LgTerminalScrollbar(
              controller: scroll,
              child: xterm.TerminalView(
                terminal,
                scrollController: scroll,
                theme: lgTerminalTheme(),
                textStyle: lgTerminalStyle(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(xterm.TerminalView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('LgClipboardRequest', () {
    Widget request({List<String>? log, double width = 1000}) => SizedBox(
      width: width,
      child: LgClipboardRequest(
        text: '远程终端中的应用请求写入本机剪贴板。允许后，所有远程终端中的应用均可写入本机剪贴板。',
        allowLabel: '允许',
        denyLabel: '拒绝',
        onAllow: () => log?.add('allow'),
        onDeny: () => log?.add('deny'),
        semanticLabel: '剪贴板写入请求',
      ),
    );

    testWidgets('allow and deny call back', (tester) async {
      final log = <String>[];
      await pumpLg(tester, request(log: log));
      await tester.tap(find.text('允许'));
      await tester.tap(find.text('拒绝'));
      expect(log, ['allow', 'deny']);
    });

    testWidgets('stands 12 px in from the area it lies over', (tester) async {
      await pumpLg(tester, request());
      final area = tester.getRect(find.byType(LgClipboardRequest));
      final card = tester.getRect(
        find
            .descendant(
              of: find.byType(LgClipboardRequest),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(card.left - area.left, 12);
      expect(card.top - area.top, 12);
      expect(area.right - card.right, 12);
    });

    testWidgets('the dark theme draws a ring instead of the shadow', (
      tester,
    ) async {
      BoxDecoration decoration() =>
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(LgClipboardRequest),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      await pumpLg(tester, request());
      expect(decoration().boxShadow, LgColors.light.shadow);
      await pumpLg(tester, request(), brightness: Brightness.dark);
      expect(decoration().boxShadow, hasLength(1));
      expect(decoration().boxShadow!.single.spreadRadius, 1);
    });

    testWidgets('is a named group, said when it appears, with its buttons', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, request());
      expect(find.bySemanticsLabel('剪贴板写入请求'), findsOneWidget);
      expect(find.bySemanticsLabel('允许'), findsOneWidget);
      expect(find.bySemanticsLabel('拒绝'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a narrow window gives the text two lines, not an overflow', (
      tester,
    ) async {
      await pumpLg(tester, request(width: 520));
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(LgClipboardRequest)).height,
        greaterThan(60),
      );
    });
  });

  group('LgAdminAccountInputs', () {
    Widget inputs({
      bool withRule = false,
      bool autofocus = false,
      TextEditingController? user,
      TextEditingController? password,
      FocusNode? userNode,
      FocusNode? passwordNode,
      List<String>? log,
    }) => SizedBox(
      width: 384,
      child: LgAdminAccountInputs(
        title: '远程设备上的管理员账户',
        description: '终端将以 SYSTEM 账户运行',
        userController: user ?? TextEditingController(),
        passwordController: password ?? TextEditingController(),
        userLabel: '系统用户名',
        passwordLabel: '系统密码',
        showLabel: '显示密码',
        hideLabel: '隐藏密码',
        withRule: withRule,
        autofocus: autofocus,
        userFocusNode: userNode,
        passwordFocusNode: passwordNode,
        onSubmitted: (v) => log?.add('submit $v'),
      ),
    );

    testWidgets('the heading, its line and the two fields are there', (
      tester,
    ) async {
      await pumpLg(tester, inputs());
      expect(find.text('远程设备上的管理员账户'), findsOneWidget);
      expect(find.text('终端将以 SYSTEM 账户运行'), findsOneWidget);
      expect(find.byType(EditableText), findsNWidgets(2));
      expect(find.text('系统用户名'), findsOneWidget);
      expect(find.text('系统密码'), findsOneWidget);
    });

    testWidgets('what is typed reaches the controllers', (tester) async {
      final user = TextEditingController();
      final password = TextEditingController();
      addTearDown(user.dispose);
      addTearDown(password.dispose);
      await pumpLg(tester, inputs(user: user, password: password));
      await tester.enterText(find.byType(EditableText).first, 'zhangsan');
      await tester.enterText(find.byType(EditableText).last, 'secret');
      expect(user.text, 'zhangsan');
      expect(password.text, 'secret');
    });

    testWidgets('the password is hidden until shown', (tester) async {
      await pumpLg(tester, inputs());
      expect(
        tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
        isTrue,
      );
      await tester.tap(
        find.byWidgetPredicate((w) => w is LgIcon && w.icon == LgIcons.eye),
      );
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
        isFalse,
      );
    });

    testWidgets('autofocus gives the user name the keyboard', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpLg(tester, inputs(autofocus: true, userNode: node));
      await tester.pump();
      expect(node.hasPrimaryFocus, isTrue);
    });

    testWidgets('Enter in the user name moves on, in the password it submits', (
      tester,
    ) async {
      final user = FocusNode();
      final password = FocusNode();
      final log = <String>[];
      addTearDown(user.dispose);
      addTearDown(password.dispose);
      await pumpLg(
        tester,
        inputs(
          autofocus: true,
          userNode: user,
          passwordNode: password,
          log: log,
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(EditableText).first, 'zhangsan');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(password.hasPrimaryFocus, isTrue);
      expect(log, isEmpty);
      await tester.enterText(find.byType(EditableText).last, 'secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(log, ['submit secret']);
    });

    testWidgets('a rule sets the account off from what is above it', (
      tester,
    ) async {
      Finder rule() => find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxHeight == 1,
      );
      await pumpLg(tester, inputs());
      expect(rule(), findsNothing);
      await pumpLg(tester, inputs(withRule: true));
      expect(rule(), findsOneWidget);
    });

    testWidgets('the fields and the group have names', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, inputs());
      expect(find.bySemanticsLabel('远程设备上的管理员账户'), findsOneWidget);
      expect(find.bySemanticsLabel('系统用户名'), findsOneWidget);
      expect(find.bySemanticsLabel('系统密码'), findsOneWidget);
      handle.dispose();
    });
  });
}
