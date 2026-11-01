import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_canvas_parts.dart';
import 'package:leapgate_ui/widgets/lg_chat.dart';
import 'package:leapgate_ui/widgets/lg_password_dialog.dart';
import 'package:leapgate_ui/widgets/lg_route_details.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';

import 'helpers.dart';

const _pwLabels = LgPasswordDialogLabels(
  title: '设置固定密码',
  passwordLabel: '新密码',
  passwordPlaceholder: '输入新密码',
  confirmLabel: '确认密码',
  confirmPlaceholder: '再输入一次',
  showPassword: '显示密码',
  hidePassword: '隐藏密码',
  strength: '密码强度',
  ruleMet: '已满足',
  ruleUnmet: '未满足',
  cancel: '取消',
  confirm: '确定',
  remove: '移除',
);

void main() {
  group('LgPasswordDialog', () {
    Widget dialog({
      required TextEditingController password,
      required TextEditingController confirm,
      required List<String> log,
      bool ok = true,
      bool withRemove = false,
      String? error,
      String? confirmError,
      int strength = 2,
    }) => LgPasswordDialog(
      labels: _pwLabels,
      passwordController: password,
      confirmController: confirm,
      rules: const [
        LgPasswordRule('至少 8 个字符', true),
        LgPasswordRule('包含数字', false),
        LgPasswordRule('包含字母', true),
        LgPasswordRule('不是常见密码', false),
      ],
      strength: strength,
      note: '已设置的密码不会显示',
      error: error,
      confirmError: confirmError,
      onCancel: () => log.add('cancel'),
      onConfirm: ok ? () => log.add('confirm') : null,
      onRemove: withRemove ? () => log.add('remove') : null,
    );

    testWidgets('its buttons call back', (tester) async {
      final log = <String>[];
      await pumpLg(
        tester,
        dialog(
          password: TextEditingController(),
          confirm: TextEditingController(),
          log: log,
          withRemove: true,
        ),
      );
      await tester.tap(find.text('取消'));
      await tester.tap(find.text('移除'));
      await tester.tap(find.text('确定'));
      expect(log, ['cancel', 'remove', 'confirm']);
    });

    testWidgets('"确定" is greyed while the rules are not met', (tester) async {
      final log = <String>[];
      await pumpLg(
        tester,
        dialog(
          password: TextEditingController(),
          confirm: TextEditingController(),
          log: log,
          ok: false,
        ),
      );
      await tester.tap(find.text('确定'));
      expect(log, isEmpty);
      await tester.tap(find.text('取消'));
      expect(log, ['cancel']);
    });

    testWidgets('Enter in a field confirms, and not when it is greyed', (
      tester,
    ) async {
      final log = <String>[];
      final password = TextEditingController();
      await pumpLg(
        tester,
        dialog(password: password, confirm: TextEditingController(), log: log),
      );
      await tester.pump();
      await tester.enterText(find.byType(EditableText).first, 'abc12345');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(log, ['confirm']);
      expect(password.text, 'abc12345');
      log.clear();
      await pumpLg(
        tester,
        dialog(
          password: password,
          confirm: TextEditingController(),
          log: log,
          ok: false,
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(EditableText).first);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(log, isEmpty);
    });

    testWidgets('the first field has the focus when it opens', (tester) async {
      await pumpLg(
        tester,
        dialog(
          password: TextEditingController(),
          confirm: TextEditingController(),
          log: [],
        ),
      );
      await tester.pump();
      final first = tester.state<EditableTextState>(
        find.byType(EditableText).first,
      );
      expect(first.widget.focusNode.hasFocus, isTrue);
    });

    testWidgets('an error and the second field\'s error show in words', (
      tester,
    ) async {
      await pumpLg(
        tester,
        dialog(
          password: TextEditingController(),
          confirm: TextEditingController(),
          log: [],
          error: '无法保存密码',
          confirmError: '两次输入的密码不一致',
        ),
      );
      expect(find.text('无法保存密码'), findsOneWidget);
      expect(find.text('两次输入的密码不一致'), findsOneWidget);
    });

    testWidgets('rules and strength are told in words to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        dialog(
          password: TextEditingController(),
          confirm: TextEditingController(),
          log: [],
          strength: 3,
        ),
      );
      expect(find.bySemanticsLabel('至少 8 个字符, 已满足'), findsOneWidget);
      expect(find.bySemanticsLabel('包含数字, 未满足'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('密码强度')).value, '3 / 4');
      handle.dispose();
    });

    testWidgets('the eye button shows what was typed', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        dialog(
          password: TextEditingController(text: 'secret99'),
          confirm: TextEditingController(),
          log: [],
        ),
      );
      EditableText first() =>
          tester.widget<EditableText>(find.byType(EditableText).first);
      expect(first().obscureText, isTrue);
      await tester.tap(find.bySemanticsLabel('显示密码').first);
      await tester.pump();
      expect(first().obscureText, isFalse);
      expect(find.bySemanticsLabel('隐藏密码'), findsWidgets);
      handle.dispose();
    });

    testWidgets('"移除" without its label is caught while building', (
      tester,
    ) async {
      await pumpLg(
        tester,
        LgPasswordDialog(
          labels: const LgPasswordDialogLabels(
            title: '设置固定密码',
            passwordLabel: '新密码',
            passwordPlaceholder: '输入新密码',
            confirmLabel: '确认密码',
            confirmPlaceholder: '再输入一次',
            showPassword: '显示密码',
            hidePassword: '隐藏密码',
            strength: '密码强度',
            ruleMet: '已满足',
            ruleUnmet: '未满足',
            cancel: '取消',
            confirm: '确定',
          ),
          passwordController: TextEditingController(),
          confirmController: TextEditingController(),
          rules: const [],
          strength: 0,
          onCancel: () {},
          onConfirm: () {},
          onRemove: () {},
        ),
      );
      expect(tester.takeException(), isA<AssertionError>());
    });

    testWidgets('a narrow window does not overflow', (tester) async {
      tester.view.physicalSize = const Size(420, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpLg(
        tester,
        dialog(
          password: TextEditingController(),
          confirm: TextEditingController(),
          log: [],
          withRemove: true,
          error: '无法保存密码',
          confirmError: '两次输入的密码不一致',
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('LgSparkline', () {
    Widget chart(List<LgSparkSeries> series) => SizedBox(
      width: 340,
      child: LgSparkline(
        series: series,
        unit: 'ms',
        timeLabels: const ['60 秒前', '30 秒前', '现在'],
        semanticLabel: '近 60 秒端到端延迟，最近 12 ms',
      ),
    );

    testWidgets('gaps, a single point and nothing at all all draw', (
      tester,
    ) async {
      for (final series in [
        [
          const LgSparkSeries([
            10,
            null,
            12,
            null,
            null,
            14,
            15,
          ], LgLineStyle.primary),
          const LgSparkSeries([4, 5, null, 6, 7, 5, 4], LgLineStyle.accent),
          const LgSparkSeries([6, 6, 6, 6, 6, 6, 6], LgLineStyle.relay),
        ],
        [
          const LgSparkSeries([12], LgLineStyle.primary),
        ],
        [
          const LgSparkSeries([null, null, null], LgLineStyle.primary),
        ],
        [const LgSparkSeries([], LgLineStyle.primary)],
        <LgSparkSeries>[],
      ]) {
        await pumpLg(tester, chart(series));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('it is one picture with a name for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        chart([
          const LgSparkSeries([10, 11, 12], LgLineStyle.primary),
        ]),
      );
      expect(find.bySemanticsLabel('近 60 秒端到端延迟，最近 12 ms'), findsOneWidget);
      handle.dispose();
    });
  });

  group('LgRouteDetails', () {
    LgRouteDetails card({
      List<String>? log,
      bool quality = false,
      double? maxHeight,
      int groups = 2,
    }) => LgRouteDetails(
      route: LgRoute.relay,
      title: '经中继',
      semanticLabel: '连接方式',
      why: '流量由中继服务器转发，速度可能较慢',
      maxHeight: maxHeight,
      groups: [
        for (var i = 0; i < groups; i++)
          LgKeyValueGroup('分组 $i', [
            LgKeyValue(
              '指纹 $i',
              'AB:CD:EF:01:23:45:67:89',
              copyLabel: '复制指纹 $i',
              onCopy: () => log?.add('copy $i'),
            ),
            LgKeyValue('地址 $i', '203.0.113.9:21117', icon: LgIcons.globe),
          ]),
      ],
      latency: const LgLatencySection(
        title: '延迟',
        note: '统计自本次会话开始，折线为近 60 秒',
        currentLabel: '当前',
        minLabel: '最低',
        averageLabel: '平均',
        maxLabel: '最高',
        rows: [
          LgLatencyRow(
            name: '端到端',
            line: LgLineStyle.primary,
            current: '128 ms',
            min: '96 ms',
            average: '121 ms',
            max: '204 ms',
          ),
          LgLatencyRow(
            name: '其余',
            line: LgLineStyle.relay,
            current: '12 ms',
            min: '9 ms',
            average: '11 ms',
            max: '31 ms',
            indent: true,
          ),
        ],
        chart: LgSparkline(
          series: [
            LgSparkSeries([100, 120, null, 130, 128], LgLineStyle.primary),
          ],
          unit: 'ms',
          timeLabels: ['60 秒前', '现在'],
          semanticLabel: '近 60 秒端到端延迟',
        ),
      ),
      qualitySwitch: quality
          ? LgDetailsSwitch(
              label: '显示质量数据',
              value: false,
              onChanged: (v) => log?.add('quality $v'),
            )
          : null,
    );

    testWidgets('the copy buttons copy their own row', (tester) async {
      final handle = tester.ensureSemantics();
      final log = <String>[];
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpLg(tester, card(log: log));
      await tester.tap(find.bySemanticsLabel('复制指纹 1'));
      await tester.tap(find.bySemanticsLabel('复制指纹 0'));
      expect(log, ['copy 1', 'copy 0']);
      handle.dispose();
    });

    testWidgets('the quality switch asks for the opposite value', (
      tester,
    ) async {
      final log = <String>[];
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpLg(tester, card(log: log, quality: true));
      await tester.tap(find.byType(LgSwitch));
      expect(log, ['quality true']);
    });

    testWidgets('a rows says its label and value together', (tester) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpLg(tester, card());
      expect(find.bySemanticsLabel('地址 0: 203.0.113.9:21117'), findsOneWidget);
      expect(find.bySemanticsLabel('连接方式'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a low window makes the card scroll instead of overflow', (
      tester,
    ) async {
      final log = <String>[];
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpLg(tester, card(log: log, maxHeight: 360, groups: 4));
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(LgRouteDetails)).height,
        lessThanOrEqualTo(360),
      );
      // The last group is below the fold until the card is scrolled.
      final last = find.text('分组 3');
      expect(tester.getRect(last).bottom, greaterThan(360 + 100));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2000),
      );
      await tester.pump();
      expect(tester.getRect(last).bottom, lessThan(700));
    });

    testWidgets('without a limit it is as tall as its content', (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpLg(tester, card(groups: 4));
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('LgChatPanel', () {
    Widget panel(
      TextEditingController controller,
      List<String> log, {
      List<LgChatMessage> messages = const [],
      List<Offset>? drags,
    }) => LgChatPanel(
      title: '聊天',
      messages: messages,
      controller: controller,
      placeholder: '输入消息',
      sendLabel: '发送',
      closeLabel: '关闭聊天',
      mineLabel: '我',
      theirsLabel: '对方',
      emptyText: '还没有消息',
      onSend: (text) {
        log.add('send $text');
        controller.clear();
      },
      onClose: () => log.add('close'),
      onDrag: drags?.add,
    );

    testWidgets('"发送" is greyed while there is nothing to send', (
      tester,
    ) async {
      final log = <String>[];
      final controller = TextEditingController();
      await pumpLg(tester, panel(controller, log));
      await tester.tap(find.text('发送'));
      expect(log, isEmpty);
      await tester.enterText(find.byType(EditableText), '   ');
      await tester.pump();
      await tester.tap(find.text('发送'));
      expect(log, isEmpty);
    });

    testWidgets('it sends the trimmed text and the caller clears the field', (
      tester,
    ) async {
      final log = <String>[];
      final controller = TextEditingController();
      await pumpLg(tester, panel(controller, log));
      await tester.enterText(find.byType(EditableText), '  你好  ');
      await tester.pump();
      await tester.tap(find.text('发送'));
      await tester.pump();
      expect(log, ['send 你好']);
      expect(controller.text, isEmpty);
    });

    testWidgets('Enter in the field sends too', (tester) async {
      final log = <String>[];
      final controller = TextEditingController();
      await pumpLg(tester, panel(controller, log));
      await tester.enterText(find.byType(EditableText), '收到');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(log, ['send 收到']);
      // The field keeps the focus for the next message.
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        true,
      );
    });

    testWidgets('the close button and the drag of the title call back', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final log = <String>[];
      final drags = <Offset>[];
      await pumpLg(tester, panel(TextEditingController(), log, drags: drags));
      await tester.tap(find.byType(LgIconButton));
      expect(log, ['close']);
      await tester.drag(find.text('聊天'), const Offset(60, 30));
      final total = drags.fold(Offset.zero, (a, b) => a + b);
      expect(total.dx, closeTo(60, 25)); // less the touch slop
      expect(total.dy, closeTo(30, 25));
      handle.dispose();
    });

    testWidgets('an empty list says so, a full one shows who wrote what', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, panel(TextEditingController(), []));
      expect(find.text('还没有消息'), findsOneWidget);
      await pumpLg(
        tester,
        panel(
          TextEditingController(),
          [],
          messages: const [
            LgChatMessage(text: '在吗', time: '10:24', mine: false),
            LgChatMessage(text: '在', time: '10:25', mine: true),
          ],
        ),
      );
      expect(find.text('还没有消息'), findsNothing);
      expect(find.bySemanticsLabel('对方, 10:24: 在吗'), findsOneWidget);
      expect(find.bySemanticsLabel('我, 10:25: 在'), findsOneWidget);
      handle.dispose();
    });

    List<LgChatMessage> numbered(int from, int to) => [
      for (var i = from; i < to; i++)
        LgChatMessage(text: '消息 $i', time: '10:${10 + i % 40}', mine: i.isEven),
    ];

    bool atBottom(WidgetTester tester, String text) {
      final list = tester.getRect(find.byType(ListView));
      final last = tester.getRect(find.text(text));
      return last.bottom <= list.bottom && last.top >= list.top;
    }

    testWidgets('it opens on the newest message, not the oldest', (
      tester,
    ) async {
      await pumpLg(
        tester,
        panel(TextEditingController(), [], messages: numbered(0, 40)),
      );
      await tester.pump();
      await tester.pump();
      expect(atBottom(tester, '消息 39'), isTrue);
      expect(find.text('消息 0'), findsNothing);
    });

    testWidgets('a list that keeps only the last N still follows the end', (
      tester,
    ) async {
      final controller = TextEditingController();
      await pumpLg(tester, panel(controller, [], messages: numbered(0, 40)));
      await tester.pump();
      await tester.pump();
      // The user reads upwards.
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pump();
      expect(find.text('消息 39'), findsNothing);
      // The model drops the oldest and appends one: the count is the same.
      await pumpLg(tester, panel(controller, [], messages: numbered(1, 41)));
      await tester.pump();
      await tester.pump();
      expect(atBottom(tester, '消息 40'), isTrue);
    });

    testWidgets('a new message scrolls the list to the end', (tester) async {
      final controller = TextEditingController();
      List<LgChatMessage> messages(int n) => [
        for (var i = 0; i < n; i++)
          LgChatMessage(text: '消息 $i', time: '10:${10 + i}', mine: i.isEven),
      ];
      await pumpLg(tester, panel(controller, [], messages: messages(30)));
      await pumpLg(tester, panel(controller, [], messages: messages(31)));
      await tester.pump();
      await tester.pump();
      final list = tester.getRect(find.byType(ListView));
      final last = tester.getRect(find.text('消息 30'));
      expect(last.bottom, lessThanOrEqualTo(list.bottom));
      expect(last.top, greaterThanOrEqualTo(list.top));
    });
  });

  group('over the picture', () {
    testWidgets('the quality figures show every row', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        const LgQualityOverlay(
          semanticLabel: '质量数据',
          rows: [('速度', '1.2 MB/s'), ('帧率', '58 fps'), ('延迟', '24 ms')],
        ),
      );
      for (final text in ['速度', '1.2 MB/s', '帧率', '58 fps', '延迟', '24 ms']) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.bySemanticsLabel(RegExp('质量数据')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the hint is announced when it shows', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, const LgCanvasHint(text: '按 Ctrl+Alt 退出鼠标锁定'));
      final node = tester.getSemantics(
        find.bySemanticsLabel('按 Ctrl+Alt 退出鼠标锁定'),
      );
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('a long hint is cut, not overflowing a narrow picture', (
      tester,
    ) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 200,
          child: LgCanvasHint(text: '按 Ctrl+Alt 退出鼠标锁定，再按一次回到远程设备的画面'),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    Widget nav(List<String> log, {bool enabled = true, List<Offset>? drags}) =>
        LgAndroidNavBar(
          backLabel: '返回',
          homeLabel: '主屏幕',
          recentsLabel: '最近任务',
          dragLabel: '移动导航键',
          onBack: enabled ? () => log.add('back') : null,
          onHome: enabled ? () => log.add('home') : null,
          onRecents: enabled ? () => log.add('recents') : null,
          onDrag: drags?.add,
        );

    testWidgets('the three keys call back, the grip drags', (tester) async {
      final handle = tester.ensureSemantics();
      final log = <String>[];
      final drags = <Offset>[];
      await pumpLg(tester, nav(log, drags: drags));
      await tester.tap(find.bySemanticsLabel('返回'));
      await tester.tap(find.bySemanticsLabel('主屏幕'));
      await tester.tap(find.bySemanticsLabel('最近任务'));
      expect(log, ['back', 'home', 'recents']);
      await tester.drag(find.bySemanticsLabel('移动导航键'), const Offset(40, 0));
      expect(drags, isNotEmpty);
      handle.dispose();
    });

    testWidgets('without handlers the keys do not react', (tester) async {
      final log = <String>[];
      await pumpLg(tester, nav(log, enabled: false));
      await tester.tap(find.byType(LgAndroidNavBar));
      expect(log, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
