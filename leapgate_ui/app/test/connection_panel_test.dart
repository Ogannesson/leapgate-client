import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_banner.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_connection_panel.dart';
import 'package:leapgate_ui/widgets/lg_device.dart';
import 'package:leapgate_ui/widgets/lg_panel_inputs.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';

import 'helpers.dart';

const _steps = [
  LgPanelStep('建立连接', LgStepState.done),
  LgPanelStep('验证身份', LgStepState.current),
];

Widget _panel({
  List<LgPanelStep>? steps = _steps,
  LgPanelTone tone = LgPanelTone.normal,
  String? message = '输入密码',
  String? detail,
  bool busy = false,
  String? secondary,
  String? notice,
  String? hint,
  LgPanelCountdown? countdown,
  List<Widget> inputs = const [],
  List<LgPanelAction> actions = const [],
  bool dimBackdrop = false,
  double width = 440,
}) => SizedBox(
  width: 960,
  height: 600,
  child: LgConnectionPanel(
    title: '客厅迷你主机',
    subtitle: '456 789 123',
    platform: LgPlatform.linux,
    steps: steps,
    tone: tone,
    message: message,
    detail: detail,
    busy: busy,
    secondary: secondary,
    notice: notice,
    hint: hint,
    countdown: countdown,
    inputs: inputs,
    actions: actions,
    dimBackdrop: dimBackdrop,
    width: width,
    semanticLabel: '连接过程 · 要密码',
  ),
);

/// Presses Tab round the card: the focus visits the same controls again and
/// again and never reaches [outside].
Future<void> _expectTabLoop(WidgetTester tester, FocusNode outside) async {
  final visited = <FocusNode>[];
  for (var i = 0; i < 16; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final node = FocusManager.instance.primaryFocus!;
    expect(outside.hasFocus, isFalse, reason: 'Tab $i left the card');
    visited.add(node);
  }
  // A whole round brings back the node the round began with.
  expect(visited.toSet().length, lessThan(visited.length));
  expect(visited.first, visited[visited.indexOf(visited.first, 1)]);
}

void main() {
  Future<void> bigSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('LgConnectionPanel', () {
    testWidgets('shows the device, the steps and what it is given', (
      tester,
    ) async {
      await bigSurface(tester);
      await pumpLg(
        tester,
        _panel(
          busy: true,
          message: '正在等待对方接受…',
          secondary: '已等待 0:12',
          notice: '显示给对方的名称：张三',
          hint: '可在设备菜单中取消“始终经中继连接”。',
        ),
      );
      for (final text in [
        '客厅迷你主机',
        '456 789 123',
        '建立连接',
        '验证身份',
        '正在等待对方接受…',
        '已等待 0:12',
        '显示给对方的名称：张三',
        '可在设备菜单中取消“始终经中继连接”。',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });

    testWidgets('a warning or error puts the message in a banner', (
      tester,
    ) async {
      await bigSurface(tester);
      await pumpLg(
        tester,
        _panel(
          tone: LgPanelTone.error,
          message: '远程设备不在线。',
          detail: '请确认该设备已开机且 Leapgate 正在运行。',
        ),
      );
      final banner = tester.widget<LgBanner>(find.byType(LgBanner));
      expect(banner.tone, LgTone.error);
      expect(banner.title, '远程设备不在线。');
      expect(banner.text, contains('Leapgate'));

      await pumpLg(tester, _panel(tone: LgPanelTone.warning));
      expect(
        tester.widget<LgBanner>(find.byType(LgBanner)).tone,
        LgTone.warning,
      );
      await pumpLg(tester, _panel());
      expect(find.byType(LgBanner), findsNothing);
    });

    testWidgets('buttons call back, a disabled one does not', (tester) async {
      await bigSurface(tester);
      var cancels = 0, connects = 0;
      await pumpLg(
        tester,
        _panel(
          actions: [
            LgPanelAction(label: '取消', onPressed: () => cancels++),
            const LgPanelAction(label: '连接', primary: true, onPressed: null),
          ],
        ),
      );
      await tester.tap(find.text('取消'));
      await tester.tap(find.text('连接'));
      expect((cancels, connects), (1, 0));

      await pumpLg(
        tester,
        _panel(
          actions: [
            LgPanelAction(
              label: '连接',
              primary: true,
              onPressed: () => connects++,
            ),
          ],
        ),
      );
      await tester.tap(find.text('连接'));
      expect(connects, 1);
    });

    testWidgets('the primary button fills the row, the others fit their text', (
      tester,
    ) async {
      await bigSurface(tester);
      await pumpLg(
        tester,
        _panel(
          actions: [
            LgPanelAction(label: '关闭标签', onPressed: () {}),
            LgPanelAction(label: '重试', onPressed: () {}),
            LgPanelAction(label: '改用中继', primary: true, onPressed: () {}),
          ],
        ),
      );
      double width(String label) => tester
          .getSize(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(LgButton),
            ),
          )
          .width;
      expect(width('改用中继'), greaterThan(width('关闭标签')));
      expect(width('关闭标签'), greaterThan(width('重试')));
      // Left to right in the order given.
      expect(
        tester.getTopLeft(find.text('关闭标签')).dx,
        lessThan(tester.getTopLeft(find.text('改用中继')).dx),
      );
    });

    testWidgets(
      'labels that do not fit stack, primary first, without overflowing',
      (tester) async {
        await bigSurface(tester);
        await pumpLg(
          tester,
          _panel(
            width: 360,
            actions: [
              LgPanelAction(label: 'Close tab', onPressed: () {}),
              LgPanelAction(label: 'Retry now', onPressed: () {}),
              LgPanelAction(
                label: 'Switch to the relay server',
                primary: true,
                onPressed: () {},
              ),
            ],
          ),
        );
        expect(tester.takeException(), isNull);
        final primary = tester.getTopLeft(
          find.text('Switch to the relay server'),
        );
        expect(
          primary.dy,
          lessThan(tester.getTopLeft(find.text('Close tab')).dy),
        );
        expect(
          tester.getTopLeft(find.text('Close tab')).dy,
          lessThan(tester.getTopLeft(find.text('Retry now')).dy),
        );
      },
    );

    testWidgets('Enter does the default button when there are no inputs', (
      tester,
    ) async {
      await bigSurface(tester);
      var carry = 0, stop = 0;
      await pumpLg(
        tester,
        _panel(
          message: '未加密',
          detail: '此连接未使用端到端加密。',
          tone: LgPanelTone.warning,
          steps: null,
          actions: [
            LgPanelAction(label: '继续', onPressed: () => carry++),
            LgPanelAction(
              label: '断开',
              primary: true,
              isDefault: true,
              onPressed: () => stop++,
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect((carry, stop), (0, 1));
    });

    testWidgets('with the focus on another button Enter is that button\'s', (
      tester,
    ) async {
      await bigSurface(tester);
      var cancels = 0, connects = 0;
      await pumpLg(
        tester,
        _panel(
          actions: [
            LgPanelAction(
              label: '连接',
              primary: true,
              isDefault: true,
              onPressed: () => connects++,
            ),
            LgPanelAction(label: '取消', onPressed: () => cancels++),
          ],
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect((cancels, connects), (1, 0));
    });

    testWidgets('no default button: Enter does nothing', (tester) async {
      await bigSurface(tester);
      var retries = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpLg(
        tester,
        _panel(
          tone: LgPanelTone.error,
          message: '远程设备不在线。',
          // Even with a field in the card (and the focus in it).
          inputs: [
            LgPasswordField(
              controller: controller,
              placeholder: '密码',
              showLabel: '显示密码',
              hideLabel: '隐藏密码',
            ),
          ],
          actions: [
            LgPanelAction(
              label: '重试',
              primary: true,
              onPressed: () => retries++,
            ),
          ],
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(retries, 0);

      await pumpLg(
        tester,
        _panel(
          tone: LgPanelTone.error,
          message: '远程设备不在线。',
          actions: [
            LgPanelAction(
              label: '重试',
              primary: true,
              onPressed: () => retries++,
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(retries, 0);
    });

    testWidgets('Enter in an input runs the default button once', (
      tester,
    ) async {
      await bigSurface(tester);
      var connects = 0, submits = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpLg(
        tester,
        _panel(
          inputs: [
            LgPasswordField(
              controller: controller,
              placeholder: '密码',
              showLabel: '显示密码',
              hideLabel: '隐藏密码',
              onSubmitted: (_) => submits++,
            ),
          ],
          actions: [
            LgPanelAction(
              label: '连接',
              primary: true,
              isDefault: true,
              onPressed: () => connects++,
            ),
          ],
        ),
      );
      await tester.tap(find.byType(TextField));
      // The key is reported as handled, so the field does not submit as well.
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
      await tester.pump();
      expect((connects, submits), (1, 0));
    });

    testWidgets(
      'Enter on an option of the drop-down picks it, not the default',
      (tester) async {
        await bigSurface(tester);
        String? picked;
        var connects = 0;
        await pumpLg(
          tester,
          _panel(
            inputs: [
              LgSelectField<String>(
                semanticLabel: 'Windows 用户',
                value: 'zhangsan',
                items: const [
                  LgSelectItem('zhangsan', 'zhangsan'),
                  LgSelectItem('lisi', 'lisi'),
                ],
                onChanged: (v) => picked = v,
              ),
            ],
            actions: [
              LgPanelAction(
                label: '连接',
                primary: true,
                isDefault: true,
                onPressed: () => connects++,
              ),
            ],
          ),
        );
        await tester.pump();
        // Tab to the drop-down, Enter opens it, Down enters the menu and moves
        // to the second option, Enter picks it.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('lisi'), findsOneWidget);
        expect(connects, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(picked, 'lisi');
        expect(connects, 0);
      },
    );

    testWidgets('Tab goes round the card and never out of it', (tester) async {
      await bigSurface(tester);
      final outside = FocusNode();
      addTearDown(outside.dispose);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpLg(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LgButton(label: '标题栏上的按钮', focusNode: outside, onPressed: () {}),
            _panel(
              inputs: [
                LgPasswordField(
                  controller: controller,
                  placeholder: '密码',
                  showLabel: '显示密码',
                  hideLabel: '隐藏密码',
                ),
                LgCheckbox(value: false, label: '记住密码', onChanged: (_) {}),
              ],
              actions: [
                LgPanelAction(label: '取消', onPressed: () {}),
                LgPanelAction(
                  label: '连接',
                  primary: true,
                  isDefault: true,
                  onPressed: () {},
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pump();
      await _expectTabLoop(tester, outside);
    });

    testWidgets('with inputs the default button does not take the focus', (
      tester,
    ) async {
      await bigSurface(tester);
      var connects = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpLg(
        tester,
        _panel(
          inputs: [
            LgPasswordField(
              controller: controller,
              placeholder: '密码',
              showLabel: '显示密码',
              hideLabel: '隐藏密码',
            ),
          ],
          actions: [
            LgPanelAction(
              label: '连接',
              primary: true,
              isDefault: true,
              onPressed: () => connects++,
            ),
          ],
        ),
      );
      await tester.pump();
      // Nothing has the focus yet: Enter reaches neither the card nor a button.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(connects, 0);
    });

    testWidgets('Enter on the show button of a field shows the text only', (
      tester,
    ) async {
      await bigSurface(tester);
      var connects = 0;
      final controller = TextEditingController(text: 'secret');
      addTearDown(controller.dispose);
      await pumpLg(
        tester,
        _panel(
          inputs: [
            LgPasswordField(
              controller: controller,
              placeholder: '密码',
              showLabel: '显示密码',
              hideLabel: '隐藏密码',
            ),
          ],
          actions: [
            LgPanelAction(
              label: '连接',
              primary: true,
              isDefault: true,
              onPressed: () => connects++,
            ),
          ],
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(connects, 0);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isFalse,
      );
    });

    testWidgets('a button can be named differently from what it shows', (
      tester,
    ) async {
      await bigSurface(tester);
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        _panel(
          actions: [
            LgPanelAction(label: '复制', semanticLabel: '复制密码', onPressed: () {}),
            LgPanelAction(label: '取消', onPressed: () {}),
          ],
        ),
      );
      expect(find.bySemanticsLabel('复制密码'), findsOneWidget);
      expect(find.bySemanticsLabel('复制'), findsNothing);
      expect(find.bySemanticsLabel('取消'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the retry bar follows the progress it is given', (
      tester,
    ) async {
      await bigSurface(tester);
      Future<double> factor(double progress) async {
        await pumpLg(
          tester,
          _panel(
            tone: LgPanelTone.warning,
            message: '连接超时。',
            countdown: LgPanelCountdown(
              text: '4 秒后重试（第 3 次）',
              progress: progress,
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        return tester
            .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
            .widthFactor!;
      }

      expect(await factor(.25), closeTo(.25, .001));
      expect(await factor(1.5), 1.0);
      expect(find.text('4 秒后重试（第 3 次）'), findsOneWidget);
    });

    testWidgets('a dimmed backdrop shows the scrim colour behind the card', (
      tester,
    ) async {
      await bigSurface(tester);
      bool scrim(Widget w) =>
          w is ColoredBox && w.color == LgColors.light.scrim;
      await pumpLg(tester, _panel(dimBackdrop: true));
      expect(find.byWidgetPredicate(scrim), findsOneWidget);
      await pumpLg(tester, _panel());
      expect(find.byWidgetPredicate(scrim), findsNothing);
    });

    testWidgets('the panel, its message and its buttons have names', (
      tester,
    ) async {
      await bigSurface(tester);
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        _panel(
          actions: [LgPanelAction(label: '取消', onPressed: () {})],
        ),
      );
      expect(find.bySemanticsLabel('连接过程 · 要密码'), findsOneWidget);
      expect(find.bySemanticsLabel('取消'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('works when animations are off', (tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLgTheme(
            brightness: Brightness.light,
            mode: LgMode.compact,
          ),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Scaffold(body: _panel(busy: true, message: '正在验证…')),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('正在验证…'), findsOneWidget);
    });
  });

  group('LgPasswordField', () {
    testWidgets('hidden to begin with, the button shows and hides it', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'secret');
      addTearDown(controller.dispose);
      await pumpLg(
        tester,
        SizedBox(
          width: 400,
          child: LgPasswordField(
            controller: controller,
            placeholder: '密码',
            showLabel: '显示密码',
            hideLabel: '隐藏密码',
          ),
        ),
      );
      bool obscured() =>
          tester.widget<EditableText>(find.byType(EditableText)).obscureText;
      expect(obscured(), isTrue);
      Finder eye(String label) =>
          find.byWidgetPredicate((w) => w is LgIconButton && w.label == label);
      await tester.tap(eye('显示密码'));
      await tester.pump();
      expect(obscured(), isFalse);
      expect(eye('隐藏密码'), findsOneWidget);
      await tester.tap(eye('隐藏密码'));
      await tester.pump();
      expect(obscured(), isTrue);
    });

    testWidgets('disabled: no typing, the eye does nothing', (tester) async {
      final controller = TextEditingController(text: 'secret');
      addTearDown(controller.dispose);
      await pumpLg(
        tester,
        SizedBox(
          width: 400,
          child: LgPasswordField(
            controller: controller,
            enabled: false,
            showLabel: '显示密码',
            hideLabel: '隐藏密码',
          ),
        ),
      );
      await tester.tap(find.byType(LgIconButton));
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isTrue,
      );
    });

    testWidgets('shows the error under the field', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpLg(
        tester,
        SizedBox(
          width: 400,
          child: LgPasswordField(
            controller: controller,
            errorText: '密码错误',
            showLabel: '显示密码',
            hideLabel: '隐藏密码',
          ),
        ),
      );
      expect(find.text('密码错误'), findsOneWidget);
    });
  });

  group('LgCodeField', () {
    Widget field({
      ValueChanged<String>? onCompleted,
      String? error,
      bool enabled = true,
      TextEditingController? controller,
    }) => SizedBox(
      width: 400,
      child: LgCodeField(
        semanticLabel: '验证码',
        controller: controller,
        errorText: error,
        enabled: enabled,
        onCompleted: onCompleted,
      ),
    );

    testWidgets('calls onCompleted each time the sixth digit is typed', (
      tester,
    ) async {
      final done = <String>[];
      await pumpLg(tester, field(onCompleted: done.add));
      await tester.enterText(find.byType(TextField), '12345');
      await tester.pump();
      expect(done, isEmpty);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      expect(done, ['123456']);
      await tester.enterText(find.byType(TextField), '12345');
      await tester.enterText(find.byType(TextField), '654321');
      await tester.pump();
      expect(done, ['123456', '654321']);
    });

    testWidgets('only digits, at most six', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpLg(tester, field(controller: controller));
      await tester.enterText(find.byType(TextField), '12ab34');
      expect(controller.text, '1234');
      await tester.enterText(find.byType(TextField), '12345678');
      expect(controller.text, '123456');
    });

    testWidgets('the typed digits show in their boxes', (tester) async {
      await pumpLg(tester, field());
      await tester.enterText(find.byType(TextField), '481');
      await tester.pump();
      for (final digit in ['4', '8', '1']) {
        expect(find.text(digit), findsOneWidget);
      }
    });

    testWidgets('error text shows; a disabled field takes no input', (
      tester,
    ) async {
      await pumpLg(tester, field(error: '验证码错误或已过期'));
      expect(find.text('验证码错误或已过期'), findsOneWidget);

      final done = <String>[];
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpLg(
        tester,
        field(enabled: false, controller: controller, onCompleted: done.add),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    testWidgets('has a name for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, field());
      expect(find.bySemanticsLabel('验证码'), findsOneWidget);
      handle.dispose();
    });
  });

  group('LgSelectField', () {
    testWidgets('opens, picks, and shows the chosen label', (tester) async {
      String? picked;
      await pumpLg(
        tester,
        SizedBox(
          width: 400,
          child: LgSelectField<String>(
            semanticLabel: 'Windows 用户',
            value: 'zhangsan',
            items: const [
              LgSelectItem('zhangsan', 'zhangsan'),
              LgSelectItem('lisi', 'lisi'),
            ],
            onChanged: (v) => picked = v,
          ),
        ),
      );
      expect(find.text('zhangsan'), findsOneWidget);
      expect(find.text('lisi'), findsNothing);
      await tester.tap(find.byType(LgSelectField<String>));
      await tester.pumpAndSettle();
      expect(find.text('lisi'), findsOneWidget);
      await tester.tap(find.text('lisi'));
      await tester.pumpAndSettle();
      expect(picked, 'lisi');
      expect(find.text('lisi'), findsNothing);
    });

    testWidgets('disabled: does not open', (tester) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 400,
          child: LgSelectField<String>(
            value: 'a',
            items: [LgSelectItem('a', 'a'), LgSelectItem('b', 'b')],
            onChanged: null,
          ),
        ),
      );
      await tester.tap(find.byType(LgSelectField<String>));
      await tester.pumpAndSettle();
      expect(find.text('b'), findsNothing);
    });

    testWidgets('is read as "name: chosen label"', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        SizedBox(
          width: 400,
          child: LgSelectField<String>(
            semanticLabel: 'Windows 用户',
            value: 'zhangsan',
            items: const [LgSelectItem('zhangsan', 'zhangsan')],
            onChanged: (_) {},
          ),
        ),
      );
      expect(find.bySemanticsLabel('Windows 用户: zhangsan'), findsOneWidget);
      handle.dispose();
    });
  });

  testWidgets('LgRadio with a description reads label and description', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var picked = 0;
    await pumpLg(
      tester,
      SizedBox(
        width: 400,
        child: LgRadio<int>(
          value: 1,
          groupValue: 0,
          label: '退出 Leapgate',
          description: '本机将无法接受远程连接。',
          onChanged: (v) => picked = v,
        ),
      ),
    );
    expect(find.text('本机将无法接受远程连接。'), findsOneWidget);
    expect(find.bySemanticsLabel('退出 Leapgate. 本机将无法接受远程连接。'), findsOneWidget);
    await tester.tap(find.text('退出 Leapgate'));
    expect(picked, 1);
    handle.dispose();
  });
}
