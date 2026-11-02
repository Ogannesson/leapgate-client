// The parts M4 added to components that already existed: the banner's
// buttons, the empty state's button, the busy button, the note of a device on a
// card and in the list view. What they were before is tested in the files of
// those components; here is what is new, and that nothing else moved.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_banner.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_device.dart';
import 'package:leapgate_ui/widgets/lg_device_card.dart';
import 'package:leapgate_ui/widgets/lg_device_parts.dart';
import 'package:leapgate_ui/widgets/lg_feedback.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';

import 'helpers.dart';

void main() {
  group('LgBanner buttons', () {
    testWidgets('a retry and a close, each with its own name and click', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final calls = <String>[];
      await pumpLg(
        tester,
        SizedBox(
          width: 600,
          child: LgBanner(
            tone: LgTone.error,
            slim: true,
            text: '无法加载地址簿。服务器返回：服务暂不可用。',
            actionLabel: '重试',
            actionIcon: LgIcons.refresh,
            onAction: () => calls.add('retry'),
            dismissLabel: '关闭',
            onDismiss: () => calls.add('close'),
          ),
        ),
      );
      expect(find.text('无法加载地址簿。服务器返回：服务暂不可用。'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('重试'));
      await tester.tap(find.bySemanticsLabel('关闭'));
      expect(calls, ['retry', 'close']);
      handle.dispose();
    });

    testWidgets('slim is 12 px above and under, the default keeps its 16', (
      tester,
    ) async {
      Future<double> height({required bool slim}) async {
        await pumpLg(
          tester,
          SizedBox(
            width: 600,
            child: LgBanner(tone: LgTone.error, slim: slim, text: '一行文字'),
          ),
        );
        return tester.getSize(find.byType(LgBanner)).height;
      }

      expect(await height(slim: true), 46);
      // 16 around a line of 22 and the icon's 1 px of lift.
      expect(await height(slim: false), 55);
    });

    testWidgets('a slim banner with a button is as high as the button needs', (
      tester,
    ) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 600,
          child: LgBanner(
            tone: LgTone.error,
            slim: true,
            text: '一行文字',
            actionLabel: '重试',
            onAction: () {},
          ),
        ),
      );
      // The 36 px button and 12 px of ground on each side.
      expect(tester.getSize(find.byType(LgBanner)).height, 60);
    });

    testWidgets('a banner without buttons has none of them', (tester) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 600,
          child: LgBanner(tone: LgTone.warning, text: '未加密'),
        ),
      );
      expect(find.byType(LgButton), findsNothing);
    });
  });

  group('LgEmptyState', () {
    testWidgets('a button under the sentence, named by its label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var logins = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 600,
          child: LgEmptyState(
            '登录后可查看地址簿',
            icon: LgIcons.book,
            actionLabel: '登录',
            actionIcon: LgIcons.login,
            onAction: () => logins++,
          ),
        ),
      );
      expect(find.bySemanticsLabel('登录后可查看地址簿'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('登录'));
      expect(logins, 1);
      handle.dispose();
    });

    testWidgets('without a button it is one node with the sentence', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        const SizedBox(
          width: 600,
          child: LgEmptyState('此地址簿中暂无设备', icon: LgIcons.book),
        ),
      );
      expect(find.bySemanticsLabel('此地址簿中暂无设备'), findsOneWidget);
      expect(find.byType(LgButton), findsNothing);
      handle.dispose();
    });

    testWidgets('the icon can take another colour', (tester) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 600,
          child: LgEmptyState(
            '无法连接服务器',
            icon: LgIcons.wifiOff,
            iconColor: Color(0xFFBE2B21),
          ),
        ),
      );
      final icon = tester.widget<LgIcon>(find.byType(LgIcon));
      expect(icon.color, const Color(0xFFBE2B21));
    });
  });

  group('LgButton busy', () {
    testWidgets('turns, greys, takes no click, and says what is going on', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var presses = 0;
      await pumpLg(
        tester,
        LgButton(
          label: '正在登录…',
          kind: LgButtonKind.primary,
          busy: true,
          onPressed: () => presses++,
        ),
      );
      expect(find.byType(LgSpinner), findsOneWidget);
      await tester.tap(find.text('正在登录…'));
      expect(presses, 0);
      expect(
        tester.getSemantics(find.bySemanticsLabel('正在登录…')),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
      handle.dispose();
    });

    testWidgets('the spinner takes the place of the icon', (tester) async {
      await pumpLg(
        tester,
        LgButton(
          label: '正在登录…',
          icon: LgIcons.login,
          busy: true,
          onPressed: () {},
        ),
      );
      expect(find.byType(LgSpinner), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is LgIcon && w.icon == LgIcons.login),
        findsNothing,
      );
    });

    testWidgets('not busy it is the button it was', (tester) async {
      var presses = 0;
      await pumpLg(tester, LgButton(label: '登录', onPressed: () => presses++));
      expect(find.byType(LgSpinner), findsNothing);
      await tester.tap(find.text('登录'));
      expect(presses, 1);
    });

    testWidgets('in a confirmation a busy default button is not run by Enter', (
      tester,
    ) async {
      final calls = <String>[];
      await pumpLg(
        tester,
        LgConfirmDialog(
          title: '确认？',
          actions: [
            LgDialogAction(label: '取消', onPressed: () => calls.add('cancel')),
            LgDialogAction(
              label: '正在保存…',
              kind: LgButtonKind.primary,
              isDefault: true,
              busy: true,
              onPressed: () => calls.add('ok'),
            ),
          ],
          children: const [
            SizedBox(width: 200, child: TextField(autofocus: true)),
          ],
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, isEmpty);
    });
  });

  group('the note of a device', () {
    LgDeviceCard card({String? note, List<LgDeviceTag> tags = const []}) =>
        LgDeviceCard(
          name: '工作室绘图电脑',
          id: '891 234 567',
          platform: LgPlatform.windows,
          status: LgDeviceStatus.online,
          statusLabel: '在线',
          userHost: 'studio@DESKTOP-STUDIO',
          note: note,
          tags: tags,
          onTap: () {},
        );

    testWidgets('the card shows it under user@host, at the same height', (
      tester,
    ) async {
      await pumpLg(tester, SizedBox(width: 340, child: card(note: '显卡驱动别升级')));
      expect(find.text('显卡驱动别升级'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('显卡驱动别升级')).dy,
        greaterThan(tester.getTopLeft(find.text('studio@DESKTOP-STUDIO')).dy),
      );
      expect(
        tester.getTopLeft(find.text('显卡驱动别升级')).dy,
        lessThan(
          tester.getTopLeft(find.textContaining('在线', findRichText: true)).dy,
        ),
      );
      expect(tester.getSize(find.byType(LgDeviceCard)).height, 112);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a card without a note, or with an empty one, has no such '
        'line', (tester) async {
      await pumpLg(tester, SizedBox(width: 340, child: card()));
      final plain = tester
          .getTopLeft(find.textContaining('在线', findRichText: true))
          .dy;
      await pumpLg(tester, SizedBox(width: 340, child: card(note: '')));
      expect(
        tester.getTopLeft(find.textContaining('在线', findRichText: true)).dy,
        plain,
      );
    });

    testWidgets('a long note is cut to one line', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 340,
          child: card(note: '显卡驱动别升级，系统更新也先别装，等设计组确认过再说，谢谢'),
        ),
        mode: LgMode.detail,
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(LgDeviceCard)).height, 112);
    });

    testWidgets('a reader gets the note with the rest', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, SizedBox(width: 340, child: card(note: '显卡驱动别升级')));
      expect(
        find.bySemanticsLabel(
          '工作室绘图电脑, 在线, 891 234 567, studio@DESKTOP-STUDIO, 显卡驱动别升级',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    LgDeviceRow row(String name, String? note) => LgDeviceRow(
      name: name,
      id: '123 456 789',
      platform: LgPlatform.windows,
      status: LgDeviceStatus.online,
      statusLabel: '在线',
      userHost: 'a@b',
      note: note,
      tags: const [LgDeviceTag('家里', Color(0xFFA65B80))],
      topDivider: false,
      onTap: () {},
    );

    testWidgets('the list view has a column for it, between user@host and '
        'the tags', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 1000,
          child: LgDeviceTable(
            columns: const [
              LgTableColumn(LgDeviceColumn.status, '状态'),
              LgTableColumn(LgDeviceColumn.name, '名称'),
              LgTableColumn(LgDeviceColumn.id, 'ID'),
              LgTableColumn(LgDeviceColumn.userHost, '用户@主机'),
              LgTableColumn(LgDeviceColumn.note, '备注'),
              LgTableColumn(LgDeviceColumn.tags, '标签'),
            ],
            rows: [row('一号', '放在阳台'), row('二号', ''), row('三号', '显卡驱动别升级')],
          ),
        ),
      );
      final header = tester.getTopLeft(find.text('备注')).dx;
      expect(header, greaterThan(tester.getTopLeft(find.text('用户@主机')).dx));
      expect(header, lessThan(tester.getTopLeft(find.text('标签')).dx));
      // The note starts under its title, and the tags of every row line up,
      // the one without a note too.
      expect(tester.getTopLeft(find.text('放在阳台')).dx, header);
      expect(tester.getTopLeft(find.text('显卡驱动别升级')).dx, header);
      final tags = tester.getTopLeft(find.text('家里').first).dx;
      for (final t in tester.widgetList(find.text('家里'))) {
        expect(tester.getTopLeft(find.byWidget(t)).dx, closeTo(tags, 14));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a list without the column is what it was', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 1000,
          child: LgDeviceTable(
            columns: const [
              LgTableColumn(LgDeviceColumn.status, '状态'),
              LgTableColumn(LgDeviceColumn.name, '名称'),
              LgTableColumn(LgDeviceColumn.id, 'ID'),
              LgTableColumn(LgDeviceColumn.userHost, '用户@主机'),
              LgTableColumn(LgDeviceColumn.tags, '标签'),
            ],
            rows: [row('一号', null), row('二号', null)],
          ),
        ),
      );
      expect(find.text('备注'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a row names its note for a reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, SizedBox(width: 1000, child: row('一号', '放在阳台')));
      expect(find.bySemanticsLabel(RegExp('放在阳台')), findsOneWidget);
      handle.dispose();
    });

    test('lgDeviceLabel leaves an empty note out', () {
      expect(
        lgDeviceLabel(name: 'a', statusLabel: '在线', id: '1', note: ''),
        'a, 在线, 1',
      );
      expect(
        lgDeviceLabel(name: 'a', statusLabel: '在线', id: '1', note: 'n'),
        'a, 在线, 1, n',
      );
    });
  });

  group('menus of a read-only book', () {
    testWidgets('the note of a group title ends at the right edge of the row', (
      tester,
    ) async {
      await pumpLg(
        tester,
        const LgMenuPanel(
          width: 300,
          items: [LgMenuGroup('管理', note: '此地址簿为只读')],
        ),
      );
      final row = tester.getRect(find.byType(LgMenuGroup));
      expect(tester.getTopRight(find.text('此地址簿为只读')).dx, row.right - 16);
      expect(tester.getTopLeft(find.text('管理')).dx, row.left + 16);
    });

    testWidgets('a long note leaves room for the title', (tester) async {
      await pumpLg(
        tester,
        const LgMenuPanel(
          width: 300,
          items: [
            LgMenuGroup(
              'Manage',
              note: 'This address book is read-only for you',
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Manage'), findsOneWidget);
    });

    testWidgets('a destructive row that cannot be used is plain and grey', (
      tester,
    ) async {
      FontWeight? weight(String label) => DefaultTextStyle.of(
        tester.element(find.text(label)),
      ).style.fontWeight;
      await pumpLg(
        tester,
        LgMenuPanel(
          items: [
            LgMenuItem(label: '从地址簿中删除', danger: true, onPressed: () {}),
            const LgMenuItem(
              label: '从另一本地址簿中删除',
              danger: true,
              onPressed: null,
            ),
          ],
        ),
      );
      expect(weight('从地址簿中删除'), FontWeight.w700);
      expect(weight('从另一本地址簿中删除'), FontWeight.w400);
    });
  });
}
