// Behaviour of the M5 components (docs LEAPGATE.md §10.12): the exit card with
// its password, code, port, notes and help, the card grid, the flash, the
// directory and its rows, the by-ID row, the loading bar, and the count with
// the reminder mark on the navigation and the home tab. Callbacks are called,
// a disabled part does not respond, the keyboard reaches the buttons, the
// names a screen reader gets are there. Nothing here compares pixels.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_device.dart';
import 'package:leapgate_ui/widgets/lg_exit_card.dart';
import 'package:leapgate_ui/widgets/lg_exit_page.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';
import 'package:leapgate_ui/widgets/lg_title_bar.dart';

import 'helpers.dart';

// ---- helpers -------------------------------------------------------------------

const _relay = LgExitStatus(
  LgExitStatusKind.relay,
  '可用 · 经中继',
  note: '流量由中继服务器转发，速度可能较慢',
);

LgExitCard _card({
  Key? key,
  LgExitStatus status = _relay,
  LgExitPasswordArea? password,
  LgExitCodeArea? code,
  List<LgExitAddress> addresses = const [],
  List<LgExitNotice> notices = const [],
  LgExitPortEdit? portEdit,
  List<LgExitAction> leading = const [],
  List<LgExitAction> actions = const [],
  LgExitHelp? help,
  String name = '李四的台式机',
}) => LgExitCard(
  key: key,
  name: name,
  id: '912 345 678',
  platform: LgPlatform.windows,
  status: status,
  password: password,
  code: code,
  addresses: addresses,
  notices: notices,
  portEdit: portEdit,
  leadingActions: leading,
  actions: actions,
  help: help,
);

Widget _sized(Widget child, {double width = 498}) => Align(
  alignment: Alignment.topLeft,
  child: SingleChildScrollView(child: SizedBox(width: width, child: child)),
);

bool _hasWarnIcon(WidgetTester tester) => tester
    .widgetList<LgIcon>(find.byType(LgIcon))
    .any((i) => i.icon == LgIcons.warn);

DecoratedBox _flashBox(WidgetTester tester) => tester.widget<DecoratedBox>(
  find.descendant(
    of: find.byType(LgFlash),
    matching: find.byType(DecoratedBox),
  ).first,
);

/// A test that runs with the semantics tree on and switches it off at the end
/// (a handle left on fails the test).
void semanticsTest(
  String name,
  Future<void> Function(WidgetTester tester) body,
) => testWidgets(name, (tester) async {
  final handle = tester.ensureSemantics();
  try {
    await body(tester);
  } finally {
    handle.dispose();
  }
});

void main() {
  group('LgExitCard', () {
    testWidgets('the address buttons, the actions and the help toggle call back', (
      tester,
    ) async {
      final calls = <String>[];
      var open = false;
      late StateSetter set;
      await pumpLg(
        tester,
        _sized(
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return _card(
                addresses: [
                  LgExitAddress(
                    address: 'socks5h://127.0.0.1:21180',
                    copyLabel: '复制 SOCKS5 地址',
                    onCopy: () => calls.add('socks'),
                  ),
                  LgExitAddress(
                    address: 'http://127.0.0.1:21180',
                    copyLabel: '复制 HTTP 地址',
                    onCopy: () => calls.add('http'),
                  ),
                ],
                leading: [
                  LgExitAction(
                    label: '修改端口',
                    icon: LgIcons.edit,
                    onPressed: () => calls.add('port'),
                  ),
                  LgExitAction(
                    label: '浏览器设置说明',
                    expanded: open,
                    onPressed: () => set(() {
                      open = !open;
                      calls.add('help');
                    }),
                  ),
                ],
                actions: [
                  LgExitAction(
                    label: '停止',
                    kind: LgButtonKind.secondary,
                    icon: LgIcons.square,
                    onPressed: () => calls.add('stop'),
                  ),
                ],
                help: open
                    ? const LgExitHelp(
                        title: '浏览器设置说明',
                        items: [LgExitHelpItem('仅支持 TCP。')],
                      )
                    : null,
              );
            },
          ),
        ),
      );
      expect(find.text('仅支持 TCP。'), findsNothing);
      await tester.tap(find.text('复制 SOCKS5 地址'));
      await tester.tap(find.text('复制 HTTP 地址'));
      await tester.tap(find.text('修改端口'));
      await tester.tap(find.text('停止'));
      expect(calls, ['socks', 'http', 'port', 'stop']);

      await tester.tap(find.text('浏览器设置说明').first);
      await tester.pumpAndSettle();
      expect(calls.last, 'help');
      expect(find.text('仅支持 TCP。'), findsOneWidget);
      await tester.tap(find.text('浏览器设置说明').first);
      await tester.pumpAndSettle();
      expect(find.text('仅支持 TCP。'), findsNothing);
    });

    testWidgets('an action without a callback does not respond and is skipped by Tab', (
      tester,
    ) async {
      final calls = <String>[];
      await pumpLg(
        tester,
        _sized(
          _card(
            leading: const [LgExitAction(label: '修改端口', onPressed: null)],
            actions: [
              LgExitAction(
                label: '停止',
                kind: LgButtonKind.secondary,
                onPressed: () => calls.add('stop'),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('修改端口'));
      // The first Tab goes past the disabled button, to "停止".
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, ['stop']);
    });

    testWidgets('Tab goes through the buttons in the order of the card', (
      tester,
    ) async {
      final calls = <String>[];
      await pumpLg(
        tester,
        _sized(
          _card(
            addresses: [
              LgExitAddress(
                address: 'socks5h://127.0.0.1:21180',
                copyLabel: '复制 SOCKS5 地址',
                onCopy: () => calls.add('socks'),
              ),
              LgExitAddress(
                address: 'http://127.0.0.1:21180',
                copyLabel: '复制 HTTP 地址',
                onCopy: () => calls.add('http'),
              ),
            ],
            leading: [
              LgExitAction(label: '修改端口', onPressed: () => calls.add('port')),
            ],
            actions: [
              LgExitAction(
                label: '停止',
                kind: LgButtonKind.secondary,
                onPressed: () => calls.add('stop'),
              ),
            ],
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
      }
      expect(calls, ['socks', 'http', 'port', 'stop']);
    });

    semanticsTest('a screen reader gets the card, the status and the buttons by name', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _sized(
          _card(
            addresses: [
              LgExitAddress(
                address: 'socks5h://127.0.0.1:21180',
                copyLabel: '复制 SOCKS5 地址',
                onCopy: () {},
              ),
            ],
            leading: [
              LgExitAction(
                label: '浏览器设置说明',
                expanded: false,
                onPressed: () {},
              ),
            ],
            actions: [
              LgExitAction(
                label: '停止',
                kind: LgButtonKind.secondary,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      expect(find.bySemanticsLabel('李四的台式机 912 345 678'), findsOneWidget);
      expect(find.bySemanticsLabel('复制 SOCKS5 地址'), findsOneWidget);
      expect(find.bySemanticsLabel('停止'), findsOneWidget);
      expect(find.text('socks5h://127.0.0.1:21180'), findsOneWidget);
      // The button that unfolds says whether it is open.
      expect(
        tester.getSemantics(find.bySemanticsLabel('浏览器设置说明')),
        isSemantics(
          label: '浏览器设置说明',
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      // The status is announced when it changes.
      final status = tester.getSemantics(find.textContaining('可用 · 经中继'));
      expect(status.flagsCollection.isLiveRegion, isTrue);
    });

    testWidgets('the status line shows the label, the reason and the note', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _sized(
          _card(
            status: const LgExitStatus(
              LgExitStatusKind.error,
              '已停止：',
              reason: '远程设备未开启“允许作为出口”',
            ),
          ),
        ),
      );
      expect(find.textContaining('已停止：', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('远程设备未开启', findRichText: true),
        findsOneWidget,
      );
      await pumpLg(tester, _sized(_card()));
      expect(find.text('流量由中继服务器转发，速度可能较慢'), findsOneWidget);
    });

    testWidgets('the password area: typing, Enter, the check box and the error', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final submitted = <String>[];
      var remember = false;
      late StateSetter set;
      await pumpLg(
        tester,
        _sized(
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return _card(
                status: const LgExitStatus(LgExitStatusKind.password, '输入密码'),
                password: LgExitPasswordArea(
                  controller: controller,
                  semanticLabel: '密码',
                  placeholder: '密码',
                  showLabel: '显示密码',
                  hideLabel: '隐藏密码',
                  rememberLabel: '记住密码',
                  remember: remember,
                  onRememberChanged: (v) => set(() => remember = v),
                  onSubmitted: submitted.add,
                  errorText: controller.text == 'bad' ? '密码错误' : null,
                ),
                actions: const [
                  LgExitAction(
                    label: '连接',
                    kind: LgButtonKind.primary,
                    onPressed: null,
                  ),
                ],
              );
            },
          ),
        ),
      );
      // The field has the keyboard as soon as the card shows it.
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'secret');
      expect(controller.text, 'secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, ['secret']);

      await tester.tap(find.text('记住密码'));
      await tester.pump();
      expect(remember, isTrue);

      expect(find.text('密码错误'), findsNothing);
      await tester.enterText(find.byType(TextField), 'bad');
      set(() {});
      await tester.pump();
      expect(find.text('密码错误'), findsOneWidget);

      // The show button names what it will do.
      await tester.tap(find.byWidgetPredicate(
        (w) => w is LgIconButton && w.label == '显示密码',
      ));
      await tester.pump();
      expect(
        find.byWidgetPredicate((w) => w is LgIconButton && w.label == '隐藏密码'),
        findsOneWidget,
      );
    });

    testWidgets('the code area calls back once the last digit is typed', (
      tester,
    ) async {
      final done = <String>[];
      var trust = false;
      late StateSetter set;
      await pumpLg(
        tester,
        _sized(
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return _card(
                status: const LgExitStatus(LgExitStatusKind.code, '输入验证码'),
                code: LgExitCodeArea(
                  semanticLabel: '验证码',
                  trustLabel: '信任此设备',
                  trust: trust,
                  onTrustChanged: (v) => set(() => trust = v),
                  onCompleted: done.add,
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), '482');
      expect(done, isEmpty);
      await tester.enterText(find.byType(TextField), '482915');
      expect(done, ['482915']);
      // Not digits: left out.
      await tester.enterText(find.byType(TextField), '12ab');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '12',
      );
      await tester.tap(find.text('信任此设备'));
      await tester.pump();
      expect(trust, isTrue);
    });

    semanticsTest('each note has its own close button and keeps its place', (
      tester,
    ) async {
      final closed = <String>[];
      var showFirst = true;
      late StateSetter set;
      await pumpLg(
        tester,
        _sized(
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return _card(
                notices: [
                  if (showFirst)
                    LgExitNotice(
                      id: 'blocked',
                      text: '远程设备已阻止一次访问',
                      dismissLabel: '关闭',
                      onDismiss: () {
                        closed.add('blocked');
                        set(() => showFirst = false);
                      },
                    ),
                  LgExitNotice(
                    id: 'fake-ip',
                    text: '目标是本机代理应用分配的虚拟地址',
                    dismissLabel: '关闭',
                    onDismiss: () => closed.add('fake-ip'),
                  ),
                ],
              );
            },
          ),
        ),
      );
      expect(find.text('远程设备已阻止一次访问'), findsOneWidget);
      expect(find.text('目标是本机代理应用分配的虚拟地址'), findsOneWidget);
      expect(find.bySemanticsLabel('关闭'), findsNWidgets(2));
      await tester.tap(find.bySemanticsLabel('关闭').first);
      await tester.pump();
      expect(closed, ['blocked']);
      expect(find.text('远程设备已阻止一次访问'), findsNothing);
      expect(find.text('目标是本机代理应用分配的虚拟地址'), findsOneWidget);
    });

    group('port edit', () {
      Future<List<String>> pumpEdit(
        WidgetTester tester, {
        VoidCallback? onConfirm,
        String? error,
        TextEditingController? controller,
        List<String>? calls,
      }) async {
        final log = calls ?? <String>[];
        await pumpLg(
          tester,
          _sized(
            _card(
              leading: [LgExitAction(label: '修改端口', onPressed: () {})],
              actions: [
                LgExitAction(
                  label: '停止',
                  kind: LgButtonKind.secondary,
                  onPressed: () {},
                ),
              ],
              portEdit: LgExitPortEdit(
                controller: controller ?? TextEditingController(text: '21181'),
                semanticLabel: '端口',
                confirmLabel: '确定',
                cancelLabel: '取消',
                onConfirm: onConfirm ?? () => log.add('confirm'),
                onCancel: () => log.add('cancel'),
                hint: '代理地址将改为新端口，需同步修改应用中的代理设置。',
                errorText: error,
              ),
            ),
          ),
        );
        await tester.pump();
        return log;
      }

      testWidgets('replaces the buttons; OK, Cancel, Enter and Esc work', (
        tester,
      ) async {
        final log = await pumpEdit(tester);
        // The card's own buttons give way to the field's.
        expect(find.text('停止'), findsNothing);
        expect(find.text('修改端口'), findsNothing);
        // The field has the keyboard: Esc cancels, Enter confirms.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        expect(log, ['cancel']);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        expect(log, ['cancel', 'confirm']);
        await tester.tap(find.text('确定'));
        await tester.tap(find.text('取消'));
        expect(log, ['cancel', 'confirm', 'confirm', 'cancel']);
        expect(
          find.text('代理地址将改为新端口，需同步修改应用中的代理设置。'),
          findsOneWidget,
        );
      });

      testWidgets('takes digits only and at most five', (tester) async {
        final controller = TextEditingController(text: '');
        addTearDown(controller.dispose);
        await pumpEdit(tester, controller: controller);
        await tester.enterText(find.byType(TextField), '2a1b8x');
        expect(controller.text, '218');
        await tester.enterText(find.byType(TextField), '1234567');
        expect(controller.text, '12345');
      });

      testWidgets('without a callback "确定" does not respond and Enter does nothing', (
        tester,
      ) async {
        final log = <String>[];
        await pumpLg(
          tester,
          _sized(
            _card(
              portEdit: LgExitPortEdit(
                controller: TextEditingController(),
                semanticLabel: '端口',
                confirmLabel: '确定',
                cancelLabel: '取消',
                onConfirm: null,
                onCancel: () => log.add('cancel'),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('确定'));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        expect(log, isEmpty);
      });

      semanticsTest('an error replaces the hint and is part of the field\'s name', (
        tester,
      ) async {
        await pumpEdit(tester, error: '此端口已被另一个出口使用');
        expect(find.text('此端口已被另一个出口使用'), findsOneWidget);
        expect(find.textContaining('代理地址将改为新端口'), findsNothing);
        final node = tester.getSemantics(find.byType(EditableText));
        expect(node.label, contains('端口'));
        expect(node.label, contains('此端口已被另一个出口使用'));
      });
    });

    testWidgets('the help block shows its lines and sets the start parameter in a monospace face', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _sized(
          _card(
            help: const LgExitHelp(
              title: '浏览器设置说明',
              items: [
                LgExitHelpItem('仅支持 TCP。'),
                LgExitHelpItem(
                  'Chrome、Edge：使用代理扩展，或添加启动参数 ',
                  code: '--proxy-server=socks5://127.0.0.1:21180',
                  after: '。',
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('浏览器设置说明'), findsOneWidget);
      expect(find.text('仅支持 TCP。'), findsOneWidget);
      final rich = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((r) => r.text.toPlainText().contains('--proxy-server'));
      String? family;
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text?.startsWith('--proxy') == true) {
          family = span.style?.fontFamily;
        }
        return true;
      });
      expect(family, 'Consolas');
      // Everything in it can be selected by hand.
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('the card follows the mode: names, tokens and a long name that ends in …', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _sized(
          _card(
            name: '工作室二楼靠窗那台一直开着的绘图工作站（备用）工作室二楼靠窗那台一直开着的绘图工作站',
          ),
          width: 440,
        ),
        mode: LgMode.detail,
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(LgExitCard)).width, 440);
    });
  });

  group('LgExitCardGrid', () {
    Future<List<Rect>> layout(WidgetTester tester, double width, int n) async {
      tester.view.physicalSize = Size(width + 100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpLg(
        tester,
        _sized(
          LgExitCardGrid(
            children: [
              for (var i = 0; i < n; i++)
                _card(
                  name: 'd$i',
                  status: i.isEven ? _relay : const LgExitStatus(LgExitStatusKind.busy, '…'),
                  actions: i.isEven
                      ? [LgExitAction(label: '停止', onPressed: () {})]
                      : const [],
                ),
            ],
          ),
          width: width,
        ),
      );
      return [
        for (var i = 0; i < n; i++) tester.getRect(find.byType(LgExitCard).at(i)),
      ];
    }

    testWidgets('makes as many columns as fit at least 440 wide, with 12 between', (
      tester,
    ) async {
      var rects = await layout(tester, 440, 4);
      expect(rects.map((r) => r.left).toSet().length, 1);
      rects = await layout(tester, 891, 4);
      expect(rects.map((r) => r.left).toSet().length, 1);
      rects = await layout(tester, 892, 4);
      expect(rects.map((r) => r.left).toSet().length, 2);
      expect(rects[1].left - rects[0].right, 12);
      expect(rects[0].width, 440);
      rects = await layout(tester, 1344, 4);
      expect(rects.map((r) => r.left).toSet().length, 3);
      expect(rects[0].width, 440);
    });

    testWidgets('keeps the order, and the cards of a row are as tall as the tallest', (
      tester,
    ) async {
      final rects = await layout(tester, 1040, 4);
      // Two columns: 0 and 1 in the first row, 2 and 3 under them.
      expect(rects[1].left, greaterThan(rects[0].left));
      expect(rects[1].top, rects[0].top);
      expect(rects[2].left, rects[0].left);
      expect(rects[2].top, greaterThan(rects[0].bottom));
      expect(rects[3].top, rects[2].top);
      // The odd cards are the short ones (no buttons), and are stretched.
      expect(rects[1].height, rects[0].height);
      expect(rects[3].height, rects[2].height);
      await pumpLg(
        tester,
        _sized(
          _card(status: const LgExitStatus(LgExitStatusKind.busy, '…')),
          width: 498,
        ),
      );
      expect(
        tester.getSize(find.byType(LgExitCard)).height,
        lessThan(rects[1].height),
      );
    });

    testWidgets('a card that grows lifts its neighbour with it', (tester) async {
      tester.view.physicalSize = const Size(1140, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var open = false;
      late StateSetter set;
      await pumpLg(
        tester,
        _sized(
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return LgExitCardGrid(
                children: [
                  _card(
                    name: 'a',
                    help: open
                        ? const LgExitHelp(
                            title: '说明',
                            items: [
                              LgExitHelpItem('一'),
                              LgExitHelpItem('二'),
                              LgExitHelpItem('三'),
                            ],
                          )
                        : null,
                  ),
                  _card(name: 'b'),
                ],
              );
            },
          ),
          width: 1040,
        ),
      );
      final before = tester.getSize(find.byType(LgExitCard).at(1)).height;
      set(() => open = true);
      await tester.pumpAndSettle();
      final a = tester.getSize(find.byType(LgExitCard).at(0)).height;
      final b = tester.getSize(find.byType(LgExitCard).at(1)).height;
      expect(a, greaterThan(before));
      expect(b, a);
    });

    testWidgets('an empty grid has no height', (tester) async {
      await pumpLg(tester, _sized(const LgExitCardGrid(children: [])));
      expect(tester.getSize(find.byType(LgExitCardGrid)).height, 0);
    });
  });

  group('LgFlash', () {
    testWidgets('frames the child for a moment each time the count goes up', (
      tester,
    ) async {
      var count = 0;
      late StateSetter set;
      await pumpLg(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return LgFlash(
              count: count,
              child: const SizedBox(width: 200, height: 100),
            );
          },
        ),
      );
      expect((_flashBox(tester).decoration as BoxDecoration).border, isNull);
      set(() => count++);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final border = (_flashBox(tester).decoration as BoxDecoration).border!;
      expect(border.top.width, 2);
      await tester.pump(const Duration(milliseconds: 2000));
      expect((_flashBox(tester).decoration as BoxDecoration).border, isNull);
      // Again.
      set(() => count++);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect((_flashBox(tester).decoration as BoxDecoration).border, isNotNull);
      await tester.pump(const Duration(milliseconds: 2000));
    });

    testWidgets('without motion it does not fade, and it still goes away', (
      tester,
    ) async {
      var count = 0;
      late StateSetter set;
      await pumpLg(
        tester,
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return LgFlash(
                count: count,
                child: const SizedBox(width: 200, height: 100),
              );
            },
          ),
        ),
      );
      set(() => count++);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      final border = (_flashBox(tester).decoration as BoxDecoration).border!;
      expect(border.top.color.a, 1);
      await tester.pump(const Duration(milliseconds: 600));
      expect((_flashBox(tester).decoration as BoxDecoration).border, isNull);
    });

    testWidgets('showing holds it on', (tester) async {
      await pumpLg(
        tester,
        const LgFlash(showing: true, child: SizedBox(width: 50, height: 50)),
      );
      expect((_flashBox(tester).decoration as BoxDecoration).border, isNotNull);
    });
  });

  group('the directory', () {
    List<LgExitEntry> entries(List<String> calls, {bool firstInUse = false}) => [
      LgExitEntry(
        name: '李四的台式机',
        id: '912 345 678',
        platform: LgPlatform.windows,
        owner: '所有者：李四',
        actionLabel: firstInUse ? '使用中' : '使用',
        inUse: firstInUse,
        onPressed: () => calls.add('li'),
      ),
      LgExitEntry(
        name: '书房台式机',
        id: '123 456 789',
        platform: LgPlatform.windows,
        owner: '我的',
        actionLabel: '使用',
        onPressed: () => calls.add('study'),
      ),
    ];

    semanticsTest('a row names the exit; "使用" and "使用中" call back', (
      tester,
    ) async {
      final calls = <String>[];
      await pumpLg(
        tester,
        _sized(
          LgExitDirectory.rows(entries: entries(calls, firstInUse: true)),
          width: 900,
        ),
      );
      expect(find.text('李四的台式机'), findsOneWidget);
      expect(find.text('所有者：李四'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);
      expect(find.text('912 345 678'), findsOneWidget);
      expect(find.text('使用中'), findsOneWidget);
      // Told apart by device for a screen reader.
      expect(find.bySemanticsLabel('使用中 李四的台式机'), findsOneWidget);
      expect(find.bySemanticsLabel('使用 书房台式机'), findsOneWidget);
      await tester.tap(find.text('使用中'));
      await tester.tap(find.text('使用'));
      expect(calls, ['li', 'study']);
    });

    testWidgets('the keyboard reaches the buttons of the rows', (tester) async {
      final calls = <String>[];
      await pumpLg(
        tester,
        _sized(LgExitDirectory.rows(entries: entries(calls)), width: 900),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, ['study']);
    });

    testWidgets('the five other states say what they say', (tester) async {
      final calls = <String>[];
      await pumpLg(
        tester,
        _sized(
          const LgExitDirectory.unsupported(
            text: '当前服务器不提供出口目录。仍可按 ID 指定出口。',
          ),
          width: 900,
        ),
      );
      expect(find.textContaining('不提供出口目录'), findsOneWidget);

      await pumpLg(
        tester,
        _sized(
          LgExitDirectory.notLoggedIn(
            text: '登录后可查看出口目录',
            actionLabel: '登录',
            onAction: () => calls.add('login'),
          ),
          width: 900,
        ),
      );
      expect(find.text('登录后可查看出口目录'), findsOneWidget);
      await tester.tap(find.text('登录'));
      expect(calls, ['login']);

      await pumpLg(
        tester,
        _sized(const LgExitDirectory.empty(text: '暂无可用的出口。'), width: 900),
      );
      expect(find.text('暂无可用的出口。'), findsOneWidget);

      await pumpLg(
        tester,
        _sized(
          LgExitDirectory.error(
            text: '无法加载出口目录',
            actionLabel: '重试',
            onAction: () => calls.add('retry'),
          ),
          width: 900,
        ),
      );
      expect(find.text('无法加载出口目录'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(calls, ['login', 'retry']);
    });

    semanticsTest('loading shows the bar, which is named and moves', (tester) async {
      await pumpLg(
        tester,
        _sized(
          const LgExitDirectory.loading(semanticLabel: '正在加载出口目录'),
          width: 900,
        ),
      );
      expect(find.byType(LgIndeterminateBar), findsOneWidget);
      expect(find.bySemanticsLabel('正在加载出口目录'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('正在加载出口目录')).flagsCollection.isLiveRegion,
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 100));
      // Still running.
      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('without motion the bar stands still', (tester) async {
      await pumpLg(
        tester,
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _sized(
            const LgIndeterminateBar(semanticLabel: '正在加载出口目录'),
            width: 400,
          ),
        ),
      );
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.getSize(find.byType(LgIndeterminateBar)).height, 4);
    });
  });

  group('LgExitByIdRow', () {
    testWidgets('"使用" waits for something to be typed; Enter does what it does', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final calls = <String>[];
      late StateSetter set;
      await pumpLg(
        tester,
        _sized(
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return LgExitByIdRow(
                controller: controller,
                placeholder: '输入设备 ID',
                semanticLabel: '设备 ID',
                useLabel: '使用',
                onUse: controller.text.isEmpty ? null : () => calls.add('use'),
                onChanged: (_) => set(() {}),
              );
            },
          ),
          width: 800,
        ),
      );
      await tester.tap(find.text('使用'));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(calls, isEmpty);

      await tester.enterText(find.byType(TextField), '135792468');
      await tester.pump();
      await tester.tap(find.text('使用'));
      expect(calls, ['use']);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(calls, ['use', 'use']);
    });

    testWidgets('the error is shown under the field, the field stops at 520 and the button follows', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _sized(
          LgExitByIdRow(
            controller: TextEditingController(text: '12345'),
            placeholder: '输入设备 ID',
            semanticLabel: '设备 ID',
            useLabel: '使用',
            onUse: () {},
            errorText: 'ID 格式不正确',
          ),
          width: 900,
        ),
      );
      expect(find.text('ID 格式不正确'), findsOneWidget);
      final field = tester.getRect(find.byType(TextField));
      expect(
        tester.getRect(find.text('ID 格式不正确')).top,
        greaterThan(field.bottom),
      );
      final button = tester.getRect(find.byType(LgButton));
      expect(button.left, closeTo(520 + 8, 1));
      // The button is as high as the field, at its top.
      expect(button.top, closeTo(tester.getRect(find.byType(LgExitByIdRow)).top, 1));
    });

    testWidgets('a disabled row refuses focus and presses', (tester) async {
      final calls = <String>[];
      await pumpLg(
        tester,
        _sized(
          LgExitByIdRow(
            controller: TextEditingController(text: '135792468'),
            placeholder: '输入设备 ID',
            semanticLabel: '设备 ID',
            useLabel: '使用',
            onUse: () => calls.add('use'),
            enabled: false,
          ),
          width: 800,
        ),
      );
      await tester.tap(find.text('使用'));
      expect(calls, isEmpty);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });
  });

  group('the page', () {
    semanticsTest('three sections under titles, refresh disabled while loading, the page scrolls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1100, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final calls = <String>[];
      final key = GlobalKey();
      Widget page({VoidCallback? onRefresh}) => LgExitPage(
        controller: controller,
        lede: '通过其他设备的网络访问互联网。',
        inUseTitle: '正在使用',
        inUse: LgExitCardGrid(
          children: [
            _card(key: key, status: _relay),
          ],
        ),
        directoryTitle: '可用的出口',
        refreshLabel: '刷新',
        onRefresh: onRefresh,
        directory: LgExitDirectory.rows(
          entries: [
            LgExitEntry(
              name: '书房台式机',
              id: '123 456 789',
              platform: LgPlatform.windows,
              owner: '我的',
              actionLabel: '使用',
              onPressed: () => calls.add('use'),
            ),
          ],
        ),
        byIdTitle: '按 ID 指定出口',
        byId: LgExitByIdRow(
          controller: TextEditingController(),
          placeholder: '输入设备 ID',
          semanticLabel: '设备 ID',
          useLabel: '使用',
          onUse: null,
        ),
      );
      await pumpLg(tester, SizedBox(width: 1000, height: 380, child: page()));
      expect(find.text('正在使用'), findsOneWidget);
      expect(find.text('可用的出口'), findsOneWidget);
      // The sections are headings for a screen reader.
      expect(
        tester.getSemantics(find.text('可用的出口')).flagsCollection.isHeader,
        isTrue,
      );
      // Disabled while loading: no response.
      await tester.tap(find.text('刷新'));
      expect(calls, isEmpty);

      // The last section is further down than the window shows.
      expect(controller.position.maxScrollExtent, greaterThan(0));
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -2000));
      await tester.pump();
      expect(find.text('按 ID 指定出口'), findsOneWidget);
      expect(tester.getRect(find.text('按 ID 指定出口')).bottom, lessThanOrEqualTo(380));
      // And back to the card by its key.
      await tester.pump();
      Scrollable.ensureVisible(key.currentContext!);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(LgExitCard)).top, greaterThanOrEqualTo(0));
    });

    testWidgets('refresh calls back when it is allowed', (tester) async {
      var refreshed = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 1000,
          height: 600,
          child: LgExitPage(
            lede: '说明',
            inUseTitle: '正在使用',
            inUse: const LgExitEmptyNote('暂无正在使用的出口'),
            directoryTitle: '可用的出口',
            refreshLabel: '刷新',
            onRefresh: () => refreshed++,
            directory: const LgExitDirectory.empty(text: '暂无可用的出口。'),
            byIdTitle: '按 ID 指定出口',
            byId: const SizedBox.shrink(),
          ),
        ),
      );
      expect(find.text('暂无正在使用的出口'), findsOneWidget);
      await tester.tap(find.text('刷新'));
      expect(refreshed, 1);
    });
  });

  group('the count and the reminder mark', () {
    testWidgets('the mark stands before the number and only when asked for', (
      tester,
    ) async {
      await pumpLg(tester, const LgCountMark(2));
      expect(find.text('2'), findsOneWidget);
      expect(_hasWarnIcon(tester), isFalse);
      await pumpLg(tester, const LgCountMark(2, alert: true));
      expect(_hasWarnIcon(tester), isTrue);
      expect(
        tester.getRect(find.byType(LgIcon).first).right,
        lessThan(tester.getRect(find.text('2')).left),
      );
    });

    semanticsTest('mark and number are no nodes of their own for a screen reader', (
      tester,
    ) async {
      await pumpLg(tester, const LgCountMark(2, alert: true));
      expect(find.bySemanticsLabel('2'), findsNothing);
    });

    semanticsTest('the home tab shows the mark and is named by the caller', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Widget bar({bool alert = false, String? label}) => LgTitleBar(
        labels: const LgTitleBarLabels(
          home: '主页',
          newTab: '新建连接',
          allTabs: '全部标签',
          closeTab: '关闭标签',
          minimize: '最小化',
          maximize: '最大化',
          restore: '还原',
          close: '关闭',
        ),
        sessions: const [],
        selected: 0,
        homeBadge: 1,
        homeAlert: alert,
        homeSemanticLabel: label,
        maximized: false,
        onSelect: (_) {},
        onCloseTab: (_) {},
        onNewTab: () {},
        onMinimize: () {},
        onToggleMaximize: () {},
        onClose: () {},
        onStartDrag: () {},
        onStartResize: (_) {},
      );
      await pumpLg(tester, bar());
      expect(_hasWarnIcon(tester), isFalse);
      // Without a name of its own the tab says its label and the number.
      expect(find.bySemanticsLabel('主页 1'), findsOneWidget);

      await pumpLg(tester, bar(alert: true, label: '主页，1 个出口正在使用，需要处理'));
      expect(_hasWarnIcon(tester), isTrue);
      expect(find.bySemanticsLabel('主页，1 个出口正在使用，需要处理'), findsOneWidget);
    });
  });
}
