import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_banner.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';
import 'package:leapgate_ui/widgets/lg_settings_layout.dart';
import 'package:leapgate_ui/widgets/lg_settings_rows.dart';
import 'package:leapgate_ui/widgets/lg_text_field.dart';

import 'helpers.dart';

Widget _block(List<Widget> rows, {bool narrow = false, double width = 632}) =>
    SizedBox(
      width: width,
      child: LgSettingsMetrics(
        narrow: narrow,
        child: LgSettingsBlock(children: rows),
      ),
    );

void main() {
  group('LgSettingsRow', () {
    testWidgets('shows the name and the description, and the switch works', (
      tester,
    ) async {
      var value = false;
      await pumpLg(
        tester,
        StatefulBuilder(
          builder: (context, set) => _block([
            LgSettingsRow.toggle(
              name: '自适应码率',
              description: '根据网络状况自动调整画面码率',
              value: value,
              onChanged: (v) => set(() => value = v),
            ),
          ]),
        ),
      );
      expect(find.text('自适应码率'), findsOneWidget);
      expect(find.text('根据网络状况自动调整画面码率'), findsOneWidget);
      await tester.tap(find.byType(LgSwitch));
      await tester.pump();
      expect(value, isTrue);
    });

    testWidgets('the switch is named by the row, for a reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        _block([
          LgSettingsRow.toggle(name: '自适应码率', value: true, onChanged: (_) {}),
        ]),
      );
      final s = tester.getSemantics(find.bySemanticsLabel('自适应码率').last);
      expect(s.flagsCollection.isToggled.name, 'isTrue');
      handle.dispose();
    });

    testWidgets(
      'disabled: the control does not respond and the reason is told',
      (tester) async {
        var n = 0;
        await pumpLg(
          tester,
          _block([
            LgSettingsRow(
              name: '一次性密码',
              disabled: true,
              disabledReason: '密码方式为“仅固定密码”时不使用',
              control: LgSwitch(value: false, onChanged: (_) => n++),
            ),
          ]),
        );
        expect(find.text('密码方式为“仅固定密码”时不使用'), findsOneWidget);
        await tester.tap(find.byType(LgSwitch), warnIfMissed: false);
        expect(n, 0);
      },
    );

    testWidgets('the reason is only told while the row is disabled', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _block([
          const LgSettingsRow(
            name: '一次性密码',
            disabledReason: '密码方式为“仅固定密码”时不使用',
          ),
        ]),
      );
      expect(find.text('密码方式为“仅固定密码”时不使用'), findsNothing);
    });

    testWidgets('an error line shows under the row, at the end when asked', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _block([
          const LgSettingsRow(
            name: '端口',
            error: '端口 21118 已被其他应用占用',
            errorAtEnd: true,
          ),
        ]),
      );
      final block = tester.getRect(find.byType(LgSettingsBlock));
      final line = tester.getRect(find.text('端口 21118 已被其他应用占用'));
      expect(line.top, greaterThan(tester.getRect(find.text('端口')).bottom));
      // Right aligned: the end of the line is the end of the row's content.
      expect(line.right, closeTo(block.right - 16, 1));

      await pumpLg(
        tester,
        _block([const LgSettingsRow(name: '端口', error: '无法保存设置')]),
      );
      // Otherwise it starts at the left, under the name.
      expect(
        tester.getRect(find.text('无法保存设置')).left -
            tester.getRect(find.byType(LgSettingsBlock)).left,
        closeTo(16 + 16 + 8, 1), // the row's padding, the icon, the gap
      );
    });

    testWidgets('the control sits at the end of the row, level with the name', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _block([
          LgSettingsRow(
            name: '固定密码',
            control: LgSettingsValueActions(
              value: '未设置',
              actions: [LgSettingsAction(label: '设置固定密码', onPressed: () {})],
            ),
          ),
        ]),
      );
      final button = tester.getRect(find.byType(LgButton));
      expect(
        button.right,
        closeTo(tester.getRect(find.byType(LgSettingsBlock)).right - 16, 1),
      );
      expect(
        button.center.dy,
        closeTo(tester.getCenter(find.text('固定密码')).dy, 1),
      );
    });

    testWidgets('a line of text with 12 above and under, 8 in detail', (
      tester,
    ) async {
      Future<double> height(LgMode mode) async {
        await pumpLg(
          tester,
          _block([const LgSettingsRow(name: '长度')]),
          mode: mode,
        );
        return tester.getSize(find.byType(LgSettingsRow)).height;
      }

      expect(await height(LgMode.compact), LgSizes.compact.lh + 24);
      expect(await height(LgMode.detail), LgSizes.detail.lh + 16);
    });

    testWidgets('never lower than the row height of the mode', (tester) async {
      await pumpLg(
        tester,
        _block([
          LgSettingsRow(
            name: '长度',
            control: LgSwitch(value: false, onChanged: (_) {}),
          ),
        ]),
        mode: LgMode.detail,
      );
      expect(
        tester.getSize(find.byType(LgSettingsRow)).height,
        greaterThanOrEqualTo(LgSizes.detail.row),
      );
    });

    testWidgets(
      'narrow: a wide control moves under the name, a switch does not',
      (tester) async {
        await pumpLg(
          tester,
          _block(narrow: true, width: 508, [
            LgSettingsRow(
              name: '长度',
              wide: true,
              control: LgSegmented<int>(
                segments: const [LgSegment(6, '6'), LgSegment(8, '8')],
                selected: 6,
                onChanged: (_) {},
              ),
            ),
            LgSettingsRow.toggle(
              name: '仅使用数字',
              value: false,
              onChanged: (_) {},
            ),
          ]),
        );
        expect(
          tester.getRect(find.byType(LgSegmented<int>)).top,
          greaterThanOrEqualTo(tester.getRect(find.text('长度')).bottom),
        );
        expect(
          tester.getCenter(find.byType(LgSwitch)).dy,
          closeTo(tester.getCenter(find.text('仅使用数字')).dy, 1),
        );
      },
    );

    testWidgets('indented goes in by 24', (tester) async {
      await pumpLg(
        tester,
        _block([
          const LgSettingsRow(name: '开关'),
          const LgSettingsRow(name: '端口', indented: true),
        ]),
      );
      expect(
        tester.getTopLeft(find.text('端口')).dx -
            tester.getTopLeft(find.text('开关')).dx,
        24,
      );
    });

    testWidgets(
      'marked: the ring is in the accent colour, and it fades when unmarked',
      (tester) async {
        Widget page(bool marked) =>
            _block([LgSettingsRow(name: '自适应码率', marked: marked)]);
        Color? ring() {
          final box =
              tester
                      .widget<AnimatedContainer>(
                        find
                            .descendant(
                              of: find.byType(LgSettingsRowFrame),
                              matching: find.byType(AnimatedContainer),
                            )
                            .first,
                      )
                      .foregroundDecoration
                  as BoxDecoration?;
          return (box?.border as Border?)?.top.color;
        }

        final accent = LgColors.light.accent;
        await pumpLg(tester, page(true));
        await tester.pumpAndSettle();
        expect(ring(), accent);
        await pumpLg(tester, page(false));
        await tester.pumpAndSettle();
        expect(ring()!.a, 0);
      },
    );

    testWidgets('keeps its height whether marked or not (nothing jumps)', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _block([
          const LgSettingsRow(name: 'a'),
          const LgSettingsRow(name: 'b'),
        ]),
      );
      final before = tester.getSize(find.byType(LgSettingsBlock)).height;
      await pumpLg(
        tester,
        _block([
          const LgSettingsRow(name: 'a'),
          const LgSettingsRow(name: 'b', marked: true),
        ]),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(LgSettingsBlock)).height, before);
    });
  });

  group('LgSettingsBlock', () {
    testWidgets('disabled: rows are dimmed to 60 % and cannot be used', (
      tester,
    ) async {
      var n = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 632,
          child: LgSettingsBlock(
            disabled: true,
            children: [
              LgSettingsRow(
                name: '长度',
                control: LgSwitch(value: false, onChanged: (_) => n++),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.byType(LgSwitch), warnIfMissed: false);
      expect(n, 0);
      expect(
        tester
            .widgetList<Opacity>(find.byType(Opacity))
            .any((o) => (o.opacity - .6).abs() < 1e-9),
        isTrue,
      );
    });
  });

  group('LgSettingsValueActions', () {
    testWidgets('shows the state and runs the buttons', (tester) async {
      final log = <String>[];
      await pumpLg(
        tester,
        LgSettingsValueActions(
          value: '已设置',
          emphasized: true,
          actions: [
            LgSettingsAction(label: '修改', onPressed: () => log.add('修改')),
            LgSettingsAction(label: '移除', onPressed: () => log.add('移除')),
          ],
        ),
      );
      expect(find.text('已设置'), findsOneWidget);
      await tester.tap(find.text('移除'));
      await tester.tap(find.text('修改'));
      expect(log, ['移除', '修改']);
    });

    testWidgets(
      'an action asking for administrator permission carries the shield',
      (tester) async {
        await pumpLg(
          tester,
          LgSettingsValueActions(
            actions: [
              LgSettingsAction(
                label: '启动服务',
                icon: LgIcons.uac,
                onPressed: () {},
              ),
            ],
          ),
        );
        expect(find.byType(LgIcon), findsOneWidget);
        expect(tester.widget<LgIcon>(find.byType(LgIcon)).icon, LgIcons.uac);
      },
    );

    testWidgets('a busy action does not respond', (tester) async {
      var n = 0;
      await pumpLg(
        tester,
        LgSettingsValueActions(
          actions: [
            LgSettingsAction(label: '安装', busy: true, onPressed: () => n++),
          ],
        ),
      );
      await tester.tap(find.text('安装'));
      expect(n, 0);
    });
  });

  group('LgSettingsStatusRow', () {
    Widget row({
      LgTone tone = LgTone.warning,
      bool narrow = false,
      double width = 632,
      VoidCallback? onFix,
    }) => _block(narrow: narrow, width: width, [
      LgSettingsStatusRow(
        tone: tone,
        text: '固定密码：未设置',
        toneLabel: tone == LgTone.success ? '已满足' : '需要注意',
        actions: onFix == null
            ? const []
            : [LgSettingsAction(label: '设置', onPressed: onFix)],
      ),
    ]);

    testWidgets(
      'the tone is told by an icon and in words, and the fix is a button',
      (tester) async {
        final handle = tester.ensureSemantics();
        var n = 0;
        await pumpLg(tester, row(onFix: () => n++));
        expect(find.byType(LgIcon), findsOneWidget);
        expect(tester.widget<LgIcon>(find.byType(LgIcon)).icon, LgIcons.warn);
        expect(find.bySemanticsLabel('需要注意'), findsOneWidget);
        await tester.tap(find.text('设置'));
        expect(n, 1);
        handle.dispose();
      },
    );

    testWidgets('met and failed have their own icons', (tester) async {
      await pumpLg(tester, row(tone: LgTone.success));
      expect(
        tester.widget<LgIcon>(find.byType(LgIcon)).icon,
        LgIcons.checkCircle,
      );
      await pumpLg(tester, row(tone: LgTone.error));
      expect(tester.widget<LgIcon>(find.byType(LgIcon)).icon, LgIcons.err);
    });

    testWidgets('the button is at the end, level with the text', (
      tester,
    ) async {
      await pumpLg(tester, row(onFix: () {}));
      final b = tester.getRect(find.byType(LgButton));
      expect(
        b.right,
        closeTo(tester.getRect(find.byType(LgSettingsBlock)).right - 16, 1),
      );
      expect(
        b.center.dy,
        closeTo(tester.getCenter(find.text('固定密码：未设置')).dy, 1),
      );
    });

    testWidgets('narrow: the button goes under the sentence', (tester) async {
      await pumpLg(tester, row(onFix: () {}, narrow: true, width: 508));
      expect(
        tester.getRect(find.byType(LgButton)).top,
        greaterThanOrEqualTo(tester.getRect(find.text('固定密码：未设置')).bottom),
      );
    });
  });

  group('LgSettingsNumberField', () {
    Widget field({
      String text = '2.5',
      required List<String> log,
      String? error,
      VoidCallback? onReverted,
      ValueChanged<String>? onChanged,
      bool enabled = true,
    }) => LgSettingsNumberField(
      text: text,
      unit: '秒',
      semanticLabel: '等待直连的时间（秒）',
      errorText: error,
      enabled: enabled,
      onSubmitted: log.add,
      onReverted: onReverted,
      onChanged: onChanged,
    );

    testWidgets('shows the value and the unit', (tester) async {
      await pumpLg(tester, field(log: []));
      expect(find.text('2.5'), findsOneWidget);
      expect(find.text('秒'), findsOneWidget);
    });

    testWidgets(
      'Enter hands over what was typed once; the focus leaving after it adds nothing',
      (tester) async {
        final log = <String>[];
        await pumpLg(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              field(log: log),
              const TextField(),
            ],
          ),
        );
        await tester.enterText(find.byType(TextField).first, '3');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(log, ['3']);
        // Focus moves away.
        await tester.tap(find.byType(TextField).last);
        await tester.pump();
        expect(log, ['3']);
      },
    );

    testWidgets('the focus leaving hands the typing over', (tester) async {
      final log = <String>[];
      await pumpLg(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field(log: log),
            const TextField(),
          ],
        ),
      );
      await tester.tap(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, '4');
      await tester.tap(find.byType(TextField).last);
      await tester.pump();
      expect(log, ['4']);
    });

    testWidgets('an unchanged value is not handed over', (tester) async {
      final log = <String>[];
      await pumpLg(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field(log: log),
            const TextField(),
          ],
        ),
      );
      await tester.tap(find.byType(TextField).first);
      await tester.tap(find.byType(TextField).last);
      await tester.pump();
      expect(log, isEmpty);
    });

    testWidgets('Esc puts the saved value back and says so', (tester) async {
      var reverted = 0;
      await pumpLg(tester, field(log: [], onReverted: () => reverted++));
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '99');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('99'), findsNothing);
      expect(find.text('2.5'), findsOneWidget);
      expect(reverted, 1);
    });

    testWidgets('Esc with nothing to put back is left to others', (
      tester,
    ) async {
      var reverted = 0;
      await pumpLg(tester, field(log: [], onReverted: () => reverted++));
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(reverted, 0);
    });

    testWidgets('a refused value shows a red frame, not a line of its own', (
      tester,
    ) async {
      await pumpLg(tester, field(log: [], error: '请输入 0.1 到 99.9 之间的数'));
      // The section shows the words in the row; here only the frame and the name.
      expect(find.text('请输入 0.1 到 99.9 之间的数'), findsNothing);
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp(r'等待直连的时间[\s\S]*请输入 0\.1')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a new saved value from outside replaces the text', (
      tester,
    ) async {
      await pumpLg(tester, field(log: [], text: '2.5'));
      await pumpLg(tester, field(log: [], text: '3.0'));
      expect(find.text('3.0'), findsOneWidget);
    });

    testWidgets('is as high as a button and 96 wide', (tester) async {
      await pumpLg(tester, field(log: []));
      final size = tester.getSize(find.byType(LgTextField));
      expect(size.height, LgSizes.compact.button);
      expect(size.width, 96);
    });

    testWidgets('disabled takes no typing', (tester) async {
      await pumpLg(tester, field(log: [], enabled: false));
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });
  });

  group('LgSettingsInfoRow', () {
    testWidgets('label, value and caption; the copy button copies', (
      tester,
    ) async {
      var n = 0;
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        _block([
          LgSettingsInfoRow(
            label: '版本',
            value: '0.4.0',
            caption: '基于 RustDesk 1.5.1',
            copyLabel: '复制',
            copySemanticLabel: '复制版本',
            onCopy: () => n++,
          ),
        ]),
      );
      expect(find.text('版本'), findsOneWidget);
      expect(find.text('基于 RustDesk 1.5.1'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('复制版本'));
      expect(n, 1);
      handle.dispose();
    });

    testWidgets(
      'without onCopy there is no button; a child can stand for the value',
      (tester) async {
        await pumpLg(
          tester,
          _block([
            LgSettingsInfoRow(
              label: '链接',
              child: LgTextLink(label: '源代码', onPressed: () {}),
            ),
          ]),
        );
        expect(find.byType(LgButton), findsNothing);
        expect(find.text('源代码'), findsOneWidget);
      },
    );

    testWidgets('the label is 96 wide, the value starts after it', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _block([const LgSettingsInfoRow(label: '本机 ID', value: '135 792 468')]),
      );
      expect(
        tester.getTopLeft(find.text('135 792 468')).dx -
            tester.getTopLeft(find.text('本机 ID')).dx,
        96 + 16,
      );
    });
  });

  group('LgTextLink', () {
    testWidgets('click and the keyboard open it; it is a button for a reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var n = 0;
      await pumpLg(tester, LgTextLink(label: '隐私声明', onPressed: () => n++));
      await tester.tap(find.text('隐私声明'));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(n, 2);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('隐私声明'))
            .flagsCollection
            .isButton,
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('is underlined and bold', (tester) async {
      await pumpLg(tester, LgTextLink(label: '网站', onPressed: () {}));
      final style = tester.widget<Text>(find.text('网站')).style!;
      expect(style.decoration, TextDecoration.underline);
      expect(style.fontWeight, FontWeight.w700);
    });
  });

  group('the small parts', () {
    testWidgets('subtitle and note read as what they are', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [LgSettingsSubtitle('高级'), LgSettingsNote('由访问模式决定')],
        ),
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('高级'))
            .flagsCollection
            .isHeader,
        isTrue,
      );
      expect(find.text('由访问模式决定'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the list header puts its buttons at the end', (tester) async {
      var n = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 500,
          child: LgSettingsListHeader(
            title: '受信设备',
            trailing: [LgButton(label: '全部删除', onPressed: () => n++)],
          ),
        ),
      );
      expect(
        tester.getRect(find.byType(LgButton)).right,
        tester.getRect(find.byType(LgSettingsListHeader)).right,
      );
      await tester.tap(find.text('全部删除'));
      expect(n, 1);
    });

    testWidgets('the about header and the footnote draw', (tester) async {
      await pumpLg(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LgSettingsAboutHeader(name: 'Leapgate（跃门）', subtitle: '0.4.0'),
            LgSettingsFootnote('Copyright © 2026 Purslane Tech Pte. Ltd.'),
          ],
        ),
      );
      expect(find.text('Leapgate（跃门）'), findsOneWidget);
      expect(find.textContaining('Copyright'), findsOneWidget);
    });
  });

  group('the changes to older components', () {
    testWidgets('the banner of the settings page has 8 above and under', (
      tester,
    ) async {
      Future<double> height({required bool dense}) async {
        await pumpLg(
          tester,
          SizedBox(
            width: 600,
            child: LgBanner(
              tone: LgTone.warning,
              slim: true,
              dense: dense,
              text: '已设置代理',
            ),
          ),
        );
        return tester.getSize(find.byType(LgBanner)).height;
      }

      final normal = await height(dense: false);
      final dense = await height(dense: true);
      expect(normal - dense, 8);
    });
  });
}
