import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/widgets/lg_banner.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_feedback.dart';
import 'package:leapgate_ui/widgets/lg_password_row.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';
import 'package:leapgate_ui/widgets/lg_tab_tip.dart';
import 'package:leapgate_ui/widgets/lg_text_field.dart';

import 'helpers.dart';

LgNotice _notice(String id, {List<LgNoticeAction> actions = const []}) =>
    LgNotice(id: id, text: '通知 $id', actions: actions);

void main() {
  group('LgNoticeStack', () {
    testWidgets('draws three, the rest wait', (tester) async {
      await pumpLg(
        tester,
        LgNoticeStack(
          notices: [for (final id in 'abcde'.split('')) _notice(id)],
          dismissLabel: '关闭',
          onDismiss: (_) {},
        ),
      );
      for (final id in 'abc'.split('')) {
        expect(find.text('通知 $id'), findsOneWidget);
      }
      for (final id in 'de'.split('')) {
        expect(find.text('通知 $id'), findsNothing);
      }
      // Newest at the bottom.
      expect(
        tester.getTopLeft(find.text('通知 a')).dy,
        lessThan(tester.getTopLeft(find.text('通知 c')).dy),
      );
    });

    testWidgets('the close button reports which notice it belongs to', (
      tester,
    ) async {
      final closed = <String>[];
      await pumpLg(
        tester,
        LgNoticeStack(
          notices: [_notice('a'), _notice('b')],
          dismissLabel: '关闭',
          onDismiss: closed.add,
        ),
      );
      final buttons = find.byWidgetPredicate(
        (w) => w is LgIconButton && w.icon == LgIcons.x,
      );
      expect(buttons, findsNWidgets(2));
      await tester.tap(buttons.last);
      await tester.tap(buttons.first);
      expect(closed, ['b', 'a']);
    });

    testWidgets('a notice without the close button does not show it', (
      tester,
    ) async {
      await pumpLg(
        tester,
        LgNoticeStack(
          notices: const [
            LgNotice(id: 'a', text: '无法关闭的通知', dismissible: false),
          ],
          dismissLabel: '关闭',
          onDismiss: (_) {},
        ),
      );
      expect(find.byType(LgIconButton), findsNothing);
    });

    testWidgets('buttons of a notice run, and can be named apart', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var saved = 0, copied = 0;
      await pumpLg(
        tester,
        LgNoticeStack(
          notices: [
            _notice(
              'shot',
              actions: [
                LgNoticeAction('另存为', () => saved++),
                LgNoticeAction('复制', () => copied++, semanticLabel: '复制到剪贴板'),
              ],
            ),
          ],
          dismissLabel: '关闭',
          onDismiss: (_) {},
        ),
      );
      await tester.tap(find.text('另存为'));
      await tester.tap(find.text('复制'));
      expect((saved, copied), (1, 1));
      expect(find.bySemanticsLabel('复制到剪贴板'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('title, tone icon and an icon of its own', (tester) async {
      await pumpLg(
        tester,
        LgNoticeStack(
          notices: const [
            LgNotice(
              id: 'a',
              title: '截图失败',
              text: '请先切换到单个显示器',
              tone: LgTone.error,
            ),
          ],
          dismissLabel: '关闭',
          onDismiss: (_) {},
        ),
      );
      expect(find.textContaining('截图失败'), findsOneWidget);
      expect(find.textContaining('请先切换到单个显示器'), findsOneWidget);
    });
  });

  group('LgToastHost', () {
    testWidgets('shows the text, replaces it, and goes away', (tester) async {
      Future<void> show(String? text) async {
        await pumpLg(
          tester,
          SizedBox(
            width: 600,
            height: 400,
            child: LgToastHost(text: text, child: const SizedBox.expand()),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(null);
      expect(find.byType(LgToast), findsNothing);
      await show('已复制');
      expect(find.text('已复制'), findsOneWidget);
      await show('已建立直连');
      expect(find.text('已复制'), findsNothing);
      expect(find.text('已建立直连'), findsOneWidget);
      await show(null);
      expect(find.byType(LgToast), findsNothing);
    });

    testWidgets('does not take clicks from the window under it', (
      tester,
    ) async {
      var taps = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 600,
          height: 400,
          child: LgToastHost(
            text: '已复制',
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: LgButton(label: '下面的按钮', onPressed: () => taps++),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('下面的按钮'));
      expect(taps, 1);
    });

    testWidgets('is announced to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, const LgToast('已复制'));
      expect(find.bySemanticsLabel('已复制'), findsOneWidget);
      handle.dispose();
    });
  });

  group('LgConfirmDialog', () {
    Widget host({
      required VoidCallback onBehind,
      required List<LgDialogAction> actions,
      VoidCallback? onEscape,
      List<Widget> children = const [],
    }) => SizedBox(
      width: 800,
      height: 500,
      child: Stack(
        children: [
          Center(
            child: LgButton(label: '后面的按钮', onPressed: onBehind),
          ),
          Positioned.fill(
            child: LgDialogScrim(
              onEscape: onEscape,
              child: LgConfirmDialog(
                title: '断开全部 2 个会话并关闭窗口？',
                actions: actions,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );

    testWidgets('covers what is under it', (tester) async {
      var behind = 0, cancels = 0;
      await pumpLg(
        tester,
        host(
          onBehind: () => behind++,
          actions: [LgDialogAction(label: '取消', onPressed: () => cancels++)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byType(Stack).first));
      await tester.tap(find.text('取消'));
      expect((behind, cancels), (0, 1));
    });

    testWidgets('Esc calls onEscape', (tester) async {
      var escapes = 0;
      await pumpLg(
        tester,
        host(
          onBehind: () {},
          onEscape: () => escapes++,
          actions: [LgDialogAction(label: '取消', onPressed: () {})],
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(escapes, 1);
    });

    testWidgets('Enter does the default button; none marked: nothing', (
      tester,
    ) async {
      var cancels = 0, ends = 0;
      await pumpLg(
        tester,
        host(
          onBehind: () {},
          actions: [
            LgDialogAction(
              label: '取消',
              isDefault: true,
              onPressed: () => cancels++,
            ),
            LgDialogAction(
              label: '断开',
              kind: LgButtonKind.dangerSolid,
              onPressed: () => ends++,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect((cancels, ends), (1, 0));

      cancels = 0;
      // A new tree: the old one would keep its focused button.
      await pumpLg(tester, const SizedBox());
      await pumpLg(
        tester,
        host(
          onBehind: () {},
          actions: [
            LgDialogAction(label: '取消', onPressed: () => cancels++),
            LgDialogAction(label: '断开', onPressed: () => ends++),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect((cancels, ends), (0, 0));
    });

    testWidgets('Tab to another button, then Enter, is that button', (
      tester,
    ) async {
      var cancels = 0, ends = 0;
      await pumpLg(
        tester,
        host(
          onBehind: () {},
          actions: [
            LgDialogAction(
              label: '取消',
              isDefault: true,
              onPressed: () => cancels++,
            ),
            LgDialogAction(
              label: '断开',
              kind: LgButtonKind.dangerSolid,
              onPressed: () => ends++,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect((cancels, ends), (0, 1));
    });

    testWidgets('Enter in a field of the dialog runs the default button', (
      tester,
    ) async {
      var ok = 0;
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpLg(
        tester,
        host(
          onBehind: () {},
          children: [LgTextField(controller: controller)],
          actions: [
            LgDialogAction(
              label: '确定',
              kind: LgButtonKind.primary,
              isDefault: true,
              onPressed: () => ok++,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(ok, 1);
    });

    testWidgets('a check box takes Enter itself and does not confirm', (
      tester,
    ) async {
      var ok = 0;
      var checked = false;
      await pumpLg(
        tester,
        StatefulBuilder(
          builder: (context, setState) => host(
            onBehind: () {},
            children: [
              LgCheckbox(
                value: checked,
                label: '不再提示',
                onChanged: (v) => setState(() => checked = v),
              ),
            ],
            actions: [
              LgDialogAction(
                label: '断开',
                kind: LgButtonKind.primary,
                isDefault: true,
                onPressed: () => ok++,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The default button has the focus; Shift+Tab goes back to the box.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect((checked, ok), (true, 0));
    });

    testWidgets('title, subtitle, body with icon and options are shown', (
      tester,
    ) async {
      await pumpLg(
        tester,
        LgConfirmDialog(
          title: '断开与此设备的 2 个会话？',
          subtitle: '妈妈的笔记本',
          body: '1 个出口将在后台继续运行。',
          bodyIcon: LgIcons.exit,
          actions: [LgDialogAction(label: '取消', onPressed: () {})],
          children: [
            LgRadio<int>(
              value: 0,
              groupValue: 0,
              label: '退出 Leapgate',
              description: '本机将无法接受远程连接。',
              onChanged: (_) {},
            ),
          ],
        ),
      );
      for (final text in [
        '断开与此设备的 2 个会话？',
        '妈妈的笔记本',
        '1 个出口将在后台继续运行。',
        '退出 Leapgate',
        '本机将无法接受远程连接。',
        '取消',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });

    testWidgets('names the dialog and hides what is behind it', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        host(
          onBehind: () {},
          actions: [LgDialogAction(label: '取消', onPressed: () {})],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('断开全部 2 个会话并关闭窗口？'), findsWidgets);
      expect(find.bySemanticsLabel('后面的按钮'), findsNothing);
      handle.dispose();
    });

    testWidgets('two buttons that read alike are named apart', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LgButton(label: '复制', semanticLabel: '复制 ID', onPressed: () {}),
            LgPasswordRow(
              label: '一次性密码',
              value: 'a1b2c3',
              onCopy: () {},
              copyLabel: '复制',
              copySemanticLabel: '复制密码',
            ),
          ],
        ),
      );
      expect(find.bySemanticsLabel('复制 ID'), findsOneWidget);
      expect(find.bySemanticsLabel('复制密码'), findsOneWidget);
      expect(find.text('复制'), findsNWidgets(2));
      handle.dispose();
    });
  });

  testWidgets('LgTabTip lists the views or the lines it is given', (
    tester,
  ) async {
    await pumpLg(
      tester,
      const LgTabTip(
        name: '客厅迷你主机',
        id: '456 789 123',
        lines: ['连接超时', '4 秒后重试（第 3 次）'],
      ),
    );
    for (final text in ['客厅迷你主机', '456 789 123', '连接超时', '4 秒后重试（第 3 次）']) {
      expect(find.text(text), findsOneWidget);
    }
  });
}
