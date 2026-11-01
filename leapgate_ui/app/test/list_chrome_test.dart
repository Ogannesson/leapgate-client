import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/widgets/lg_banner.dart';
import 'package:leapgate_ui/widgets/lg_feedback.dart';
import 'package:leapgate_ui/widgets/lg_list_chrome.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';

import 'helpers.dart';

void main() {
  group('LgCategoryTabs', () {
    Widget tabs(List<int> picked, {int selected = 0}) => LgCategoryTabs<int>(
      categories: const [
        LgCategory(0, '最近'),
        LgCategory(1, '收藏'),
        LgCategory(2, '局域网'),
      ],
      selected: selected,
      onSelect: picked.add,
      semanticLabel: '设备分类',
    );

    testWidgets('a tab selects its category', (tester) async {
      final picked = <int>[];
      await pumpLg(tester, tabs(picked));
      await tester.tap(find.text('收藏'));
      await tester.tap(find.text('局域网'));
      expect(picked, [1, 2]);
    });

    testWidgets('the chosen tab tells a screen reader it is selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, tabs([], selected: 1));
      Future<bool> selected(String label) async =>
          tester
              .getSemantics(find.bySemanticsLabel(label))
              .getSemanticsData()
              .flagsCollection
              .isSelected
              .name ==
          'isTrue';
      expect(await selected('收藏'), isTrue);
      expect(await selected('最近'), isFalse);
      handle.dispose();
    });
  });

  group('list tools', () {
    testWidgets('a tool button runs and shows its active state', (
      tester,
    ) async {
      var n = 0;
      await pumpLg(
        tester,
        LgListToolButton(
          icon: LgIcons.select,
          label: '多选',
          onPressed: () => n++,
          active: true,
        ),
      );
      await tester.tap(find.text('多选'));
      expect(n, 1);
    });

    testWidgets('a tool with a menu opens it under its right edge', (
      tester,
    ) async {
      var picked = '';
      await pumpLg(
        tester,
        Align(
          alignment: Alignment.topRight,
          child: LgListToolMenu(
            icon: LgIcons.sort,
            label: '排序',
            width: 240,
            items: [
              LgMenuItem(
                label: '名称',
                checked: true,
                onPressed: () => picked = '名称',
              ),
              LgMenuItem(
                label: 'ID',
                checked: false,
                onPressed: () => picked = 'ID',
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('排序'));
      await tester.pumpAndSettle();
      expect(find.text('ID'), findsOneWidget);
      // The right edges of the menu and of the tool meet.
      final tool = tester.getRect(find.text('排序'));
      final item = tester.getRect(find.text('ID'));
      expect(item.left, lessThan(tool.left));
      await tester.tap(find.text('ID'));
      await tester.pumpAndSettle();
      expect(picked, 'ID');
      expect(find.text('ID'), findsNothing);
    });

    testWidgets('a disabled tool does not react', (tester) async {
      await pumpLg(
        tester,
        const LgListToolButton(
          icon: LgIcons.sort,
          label: '排序',
          onPressed: null,
        ),
      );
      await tester.tap(find.text('排序'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the toolbar keeps the tools in a narrow window', (
      tester,
    ) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 360,
          child: LgListToolbar(
            tabs: LgCategoryTabs<int>(
              categories: const [
                LgCategory(0, '最近'),
                LgCategory(1, '收藏'),
                LgCategory(2, '局域网'),
                LgCategory(3, '地址簿'),
                LgCategory(4, '同组设备'),
              ],
              selected: 0,
              onSelect: (_) {},
            ),
            tools: const [
              LgListToolButton(
                icon: LgIcons.grid,
                label: '视图',
                onPressed: null,
              ),
              LgListToolButton(
                icon: LgIcons.select,
                label: '多选',
                onPressed: null,
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.text('多选')).right,
        lessThanOrEqualTo(360 + 400),
      );
    });
  });

  group('LgSelectionBar', () {
    Widget bar(List<String> log, {bool enabled = true}) => LgSelectionBar(
      actions: [
        LgSelectionAction(
          label: '删除',
          icon: LgIcons.trash,
          danger: true,
          onPressed: enabled ? () => log.add('delete') : null,
        ),
        LgSelectionAction(
          label: '加入收藏',
          icon: LgIcons.star,
          onPressed: enabled ? () => log.add('favorite') : null,
        ),
      ],
      countText: '已选择 3 台',
      selectAllLabel: '全选',
      onSelectAll: () => log.add('all'),
      doneLabel: '完成',
      onDone: () => log.add('done'),
    );

    testWidgets('its buttons call back', (tester) async {
      final log = <String>[];
      await pumpLg(tester, SizedBox(width: 800, child: bar(log)));
      await tester.tap(find.text('删除'));
      await tester.tap(find.text('加入收藏'));
      await tester.tap(find.text('全选'));
      await tester.tap(find.text('完成'));
      expect(log, ['delete', 'favorite', 'all', 'done']);
      expect(find.text('已选择 3 台'), findsOneWidget);
    });

    testWidgets('with nothing picked the actions are greyed', (tester) async {
      final log = <String>[];
      await pumpLg(
        tester,
        SizedBox(width: 800, child: bar(log, enabled: false)),
      );
      await tester.tap(find.text('删除'));
      await tester.tap(find.text('加入收藏'));
      expect(log, isEmpty);
      await tester.tap(find.text('完成'));
      expect(log, ['done']);
    });

    testWidgets('the count is announced when it changes', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, SizedBox(width: 800, child: bar([])));
      final node = tester.getSemantics(find.bySemanticsLabel('已选择 3 台'));
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('a narrow bar wraps its buttons, no overflow', (tester) async {
      await pumpLg(tester, SizedBox(width: 380, child: bar([])));
      expect(tester.takeException(), isNull);
    });
  });

  group('the local area', () {
    testWidgets('a notice may carry one button', (tester) async {
      var n = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 240,
          child: LgLocalNotice(
            tone: LgTone.warning,
            text: '服务已停止，无法接受连接。',
            actionLabel: '启动服务',
            onAction: () => n++,
          ),
        ),
      );
      await tester.tap(find.text('启动服务'));
      expect(n, 1);
    });

    testWidgets('an error notice is announced', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        const SizedBox(
          width: 240,
          child: LgLocalNotice(tone: LgTone.error, text: '无法写入配置文件'),
        ),
      );
      expect(find.text('无法写入配置文件'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('"查看" shows only when there is something to open', (
      tester,
    ) async {
      var n = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 240,
          child: LgControlledNote(
            text: '正在被远程控制\n（2 个会话）',
            viewLabel: '查看',
            onView: () => n++,
          ),
        ),
      );
      await tester.tap(find.text('查看'));
      expect(n, 1);
      await pumpLg(
        tester,
        const SizedBox(
          width: 240,
          child: LgControlledNote(text: '正在被远程控制\n（1 个会话）'),
        ),
      );
      expect(find.text('查看'), findsNothing);
    });
  });

  group('LgBlockedOverlay', () {
    Widget page(bool blocked, List<String> log) => SizedBox(
      width: 400,
      height: 300,
      child: LgBlockedOverlay(
        blocked: blocked,
        message: '远程控制期间无法修改设置',
        child: Center(
          child: TextButton(
            onPressed: () => log.add('tap'),
            child: const Text('设置'),
          ),
        ),
      ),
    );

    testWidgets('blocked: the page gets no clicks and no focus', (
      tester,
    ) async {
      final log = <String>[];
      await pumpLg(tester, page(true, log));
      expect(find.text('远程控制期间无法修改设置'), findsOneWidget);
      await tester.tap(find.text('设置'), warnIfMissed: false);
      expect(log, isEmpty);
      expect(
        find.descendant(
          of: find.byType(LgBlockedOverlay),
          matching: find.byType(ExcludeFocus),
        ),
        findsWidgets,
      );
    });

    testWidgets('free: the page works and nothing covers it', (tester) async {
      final log = <String>[];
      await pumpLg(tester, page(false, log));
      expect(find.text('远程控制期间无法修改设置'), findsNothing);
      await tester.tap(find.text('设置'));
      expect(log, ['tap']);
    });
  });

  group('notices with buttons', () {
    testWidgets('a secondary action, a check box and the close button', (
      tester,
    ) async {
      final log = <String>[];
      var checked = false;
      await pumpLg(
        tester,
        StatefulBuilder(
          builder: (context, set) => LgNoticeStack(
            dismissLabel: '关闭',
            onDismiss: (id) => log.add('dismiss $id'),
            notices: [
              LgNotice(
                id: 'print',
                text: '收到来自远程设备的打印任务',
                actions: [
                  LgNoticeAction('使用默认打印机', () => log.add('default')),
                  LgNoticeAction('不打印', () => log.add('no'), secondary: true),
                ],
                check: LgNoticeCheck(
                  label: '记住此选择',
                  value: checked,
                  onChanged: (v) => set(() => checked = v),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('使用默认打印机'));
      await tester.tap(find.text('不打印'));
      await tester.tap(find.text('记住此选择'));
      await tester.pump();
      expect(checked, isTrue);
      await tester.tap(find.bySemanticsLabel('关闭'));
      expect(log, ['default', 'no', 'dismiss print']);
    });

    testWidgets('three buttons keep their line when they fit', (tester) async {
      await pumpLg(
        tester,
        LgNoticeStack(
          dismissLabel: '关闭',
          onDismiss: (_) {},
          notices: [
            LgNotice(
              id: 'p',
              text: '收到来自远程设备的打印任务',
              actions: [
                LgNoticeAction('使用默认打印机', () {}),
                LgNoticeAction('选择打印机', () {}),
                LgNoticeAction('不打印', () {}, secondary: true),
              ],
            ),
          ],
        ),
      );
      final a = tester.getTopLeft(find.text('使用默认打印机')).dy;
      final c = tester.getTopLeft(find.text('不打印')).dy;
      expect((a - c).abs(), lessThan(2));
    });
  });
}
