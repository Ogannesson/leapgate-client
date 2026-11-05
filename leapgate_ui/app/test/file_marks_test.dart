// Behaviour of the marks and the bar of the file transfer view (docs LEAPGATE.md §10.15): the ring
// and the reminder mark on a tab and on the view switch, the tail of the switch's menu row, the
// view bar, the counting note and the loading row. Nothing here compares pixels.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_file_marks.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_session_toolbar.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';
import 'package:leapgate_ui/widgets/lg_title_bar.dart';
import 'package:leapgate_ui/widgets/lg_view_bar.dart';

import 'helpers.dart';

const _labels = LgTitleBarLabels(
  home: '主页',
  newTab: '新建连接',
  allTabs: '全部标签',
  closeTab: '关闭标签',
  minimize: '最小化',
  maximize: '最大化',
  restore: '还原',
  close: '关闭',
);

Widget _tabs(List<LgSessionTab> sessions) => SizedBox(
  width: 900,
  child: LgTitleBar(
    labels: _labels,
    sessions: sessions,
    selected: 1,
    onSelect: (_) {},
    onCloseTab: (_) {},
    onNewTab: () {},
    maximized: false,
    onMinimize: () {},
    onToggleMaximize: () {},
    onClose: () {},
    onStartDrag: () {},
    onStartResize: (_) {},
  ),
);

LgSessionTab _tab({double? progress, bool alert = false, String? markLabel}) =>
    LgSessionTab(
      name: '书房台式机',
      identity: 5,
      status: const LgRouteMark(route: LgRoute.direct, label: '直连'),
      progress: progress,
      alert: alert,
      markLabel: markLabel,
    );

void main() {
  group('tab', () {
    testWidgets('no mark without progress and without a reminder', (
      tester,
    ) async {
      await pumpLg(tester, _tabs([_tab()]));
      expect(find.byType(LgProgressRing), findsNothing);
      expect(find.byType(LgReminderMark), findsNothing);
    });

    testWidgets(
      'a ring while files move, the reminder mark instead when a question waits',
      (tester) async {
        await pumpLg(tester, _tabs([_tab(progress: .45)]));
        expect(find.byType(LgProgressRing), findsOneWidget);
        expect(find.byType(LgReminderMark), findsNothing);
        await pumpLg(tester, _tabs([_tab(progress: .45, alert: true)]));
        expect(find.byType(LgProgressRing), findsNothing);
        expect(find.byType(LgReminderMark), findsOneWidget);
      },
    );

    testWidgets('the mark is named for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, _tabs([_tab(progress: .45, markLabel: '文件传输 45%')]));
      expect(find.bySemanticsLabel(RegExp('文件传输 45%')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the ring and the close button both stay usable', (
      tester,
    ) async {
      final closed = <int>[];
      await pumpLg(
        tester,
        SizedBox(
          width: 900,
          child: LgTitleBar(
            labels: _labels,
            sessions: [_tab(progress: .3)],
            selected: 1,
            onSelect: (_) {},
            onCloseTab: closed.add,
            onNewTab: () {},
            maximized: false,
            onMinimize: () {},
            onToggleMaximize: () {},
            onClose: () {},
            onStartDrag: () {},
            onStartResize: (_) {},
          ),
        ),
      );
      await tester.tap(find.byTooltip('关闭标签'));
      expect(closed, [1]);
    });
  });

  group('view switch', () {
    Widget button({
      double? progress,
      bool alert = false,
      bool highlighted = false,
    }) => LgToolbarMenuButton(
      label: '文件传输',
      icon: LgIcons.folder,
      progress: progress,
      alert: alert,
      highlighted: highlighted,
      semanticLabel: '文件传输，45%',
      items: [LgMenuItem(label: '远程桌面', onPressed: () {})],
    );

    testWidgets('the ring follows the name, the reminder mark replaces it', (
      tester,
    ) async {
      await pumpLg(tester, button(progress: .45));
      expect(find.byType(LgProgressRing), findsOneWidget);
      await pumpLg(tester, button(progress: .45, alert: true));
      expect(find.byType(LgProgressRing), findsNothing);
      expect(find.byType(LgReminderMark), findsOneWidget);
    });

    testWidgets('without them it is the old button', (tester) async {
      await pumpLg(tester, button());
      expect(find.byType(LgProgressRing), findsNothing);
      expect(find.byType(LgReminderMark), findsNothing);
    });

    testWidgets('the accessible name can say more than the label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, button(progress: .45));
      expect(find.bySemanticsLabel('文件传输，45%'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('highlighted tints the closed button like an open one', (
      tester,
    ) async {
      await pumpLg(tester, button(highlighted: true));
      final text = tester.widget<Text>(find.text('文件传输'));
      expect(text.style!.fontWeight, FontWeight.w700);
      await pumpLg(tester, button());
      final plain = tester.widget<Text>(find.text('文件传输'));
      expect(plain.style!.fontWeight, FontWeight.w400);
    });

    testWidgets('the view that is shown is "selected" to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, button(highlighted: true));
      expect(
        tester.getSemantics(find.bySemanticsLabel('文件传输，45%')),
        isSemantics(isSelected: true, hasSelectedState: true),
      );
      await pumpLg(tester, button());
      expect(
        tester.getSemantics(find.bySemanticsLabel('文件传输，45%')),
        isSemantics(hasSelectedState: false, isSelected: false),
      );
      handle.dispose();
    });

    testWidgets(
      'a highlighted button still answers the pointer with the hover tint',
      (tester) async {
        Color? ground() {
          final box = tester.widget<Container>(
            find
                .descendant(
                  of: find.byType(LgToolbarMenuButton),
                  matching: find.byWidgetPredicate(
                    (w) => w is Container && w.decoration is BoxDecoration,
                  ),
                )
                .first,
          );
          return (box.decoration! as BoxDecoration).color;
        }

        // Only on a desktop does the pointer highlight what it is on (the default platform of a
        // test is not one).
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          await pumpLg(tester, button(highlighted: true));
          final resting = ground();
          expect(resting, isNotNull);
          final gesture = await hover(tester, find.text('文件传输'));
          expect(ground(), isNot(resting));
          await gesture.moveTo(const Offset(1, 1));
          await tester.pump();
          expect(ground(), resting);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets(
      'on a view\'s own bar the ring stands 4 px further from the name',
      (tester) async {
        double gap() =>
            tester.getTopLeft(find.byType(LgProgressRing)).dx -
            tester.getRect(find.text('文件传输')).right;
        await pumpLg(tester, button(progress: .45));
        final plain = gap();
        await pumpLg(tester, button(progress: .45, highlighted: true));
        expect(gap(), plain + 4);
      },
    );

    testWidgets('the menu opens from it', (tester) async {
      await pumpLg(tester, button(progress: .45));
      await tester.tap(find.text('文件传输'));
      await tester.pumpAndSettle();
      expect(find.text('远程桌面'), findsOneWidget);
    });
  });

  group('menu row tail', () {
    testWidgets('ring, percentage and the connection method, in that order', (
      tester,
    ) async {
      await pumpLg(
        tester,
        const LgViewMenuTail(
          progress: .45,
          percentText: '45%',
          status: LgRouteMark(route: LgRoute.direct, label: '直连'),
        ),
      );
      final ring = tester.getTopLeft(find.byType(LgProgressRing)).dx;
      final pct = tester.getTopLeft(find.text('45%')).dx;
      final route = tester.getTopLeft(find.textContaining('直连')).dx;
      expect(ring < pct && pct < route, isTrue);
    });

    testWidgets('12 between the parts, 24 before the connection method', (
      tester,
    ) async {
      await pumpLg(
        tester,
        const LgViewMenuTail(
          progress: .45,
          percentText: '45%',
          status: LgRouteMark(route: LgRoute.direct, label: '直连'),
        ),
      );
      final ring = tester.getRect(find.byType(LgProgressRing));
      final pct = tester.getRect(find.text('45%'));
      final route = tester.getRect(find.byType(LgRouteMark));
      expect(pct.left - ring.right, 12);
      expect(route.left - pct.right, 24);
      await pumpLg(
        tester,
        const LgViewMenuTail(
          alert: true,
          status: LgRouteMark(route: LgRoute.direct, label: '直连'),
        ),
      );
      final mark = tester.getRect(find.byType(LgReminderMark));
      expect(tester.getRect(find.byType(LgRouteMark)).left - mark.right, 12);
    });

    testWidgets('a reminder takes the ring and the percentage away', (
      tester,
    ) async {
      await pumpLg(
        tester,
        const LgViewMenuTail(progress: .45, percentText: '45%', alert: true),
      );
      expect(find.byType(LgProgressRing), findsNothing);
      expect(find.text('45%'), findsNothing);
      expect(find.byType(LgReminderMark), findsOneWidget);
    });

    testWidgets('it sits at the end of a menu row', (tester) async {
      await pumpLg(
        tester,
        const LgMenuPanel(
          items: [
            LgMenuItem(
              label: '文件传输',
              icon: LgIcons.folder,
              trailing: LgViewMenuTail(progress: .45, percentText: '45%'),
              onPressed: _noop,
            ),
          ],
        ),
      );
      expect(find.text('文件传输'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
    });
  });

  group('view bar', () {
    testWidgets('the parts stand in order and "断开" disconnects', (
      tester,
    ) async {
      var disconnected = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 900,
          child: LgViewBar(
            viewSwitch: const Text('切换'),
            route: const Text('路径'),
            disconnectLabel: '断开',
            onDisconnect: () => disconnected++,
          ),
        ),
      );
      final switchX = tester.getTopLeft(find.text('切换')).dx;
      final routeX = tester.getTopLeft(find.text('路径')).dx;
      final bye = tester.getTopLeft(find.text('断开')).dx;
      expect(switchX < routeX && routeX < bye, isTrue);
      await tester.tap(find.text('断开'));
      expect(disconnected, 1);
    });

    testWidgets('without a route there is only the switch and the button', (
      tester,
    ) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 900,
          child: LgViewBar(
            viewSwitch: const Text('切换'),
            disconnectLabel: '断开',
            onDisconnect: () {},
          ),
        ),
      );
      expect(find.text('路径'), findsNothing);
      expect(find.byType(LgButton), findsOneWidget);
    });

    testWidgets(
      'the smallest window\'s bar is lower, and the default is as before',
      (tester) async {
        Widget bar({bool compact = false}) => SizedBox(
          width: 900,
          child: LgViewBar(
            viewSwitch: const Text('切换'),
            disconnectLabel: '断开',
            onDisconnect: () {},
            compact: compact,
          ),
        );
        await pumpLg(tester, bar());
        final normal = tester.getSize(find.byType(LgViewBar)).height;
        expect(normal, 52);
        await pumpLg(tester, bar(compact: true));
        expect(tester.getSize(find.byType(LgViewBar)).height, 44);
        // The detail mode is low enough already: the bar does not get lower than it was.
        await pumpLg(tester, bar(), mode: LgMode.detail);
        final detail = tester.getSize(find.byType(LgViewBar)).height;
        await pumpLg(tester, bar(compact: true), mode: LgMode.detail);
        expect(tester.getSize(find.byType(LgViewBar)).height, detail);
      },
    );
  });

  group('small parts', () {
    testWidgets('the ring clamps its value', (tester) async {
      await pumpLg(tester, const LgProgressRing(value: 3));
      expect(tester.takeException(), isNull);
      await pumpLg(tester, const LgProgressRing(value: -1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the counting note is a live region with its text', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        const SizedBox(width: 400, child: LgCountingNote('正在统计要删除的项目…')),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('正在统计要删除的项目…'));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('the loading row of the drive list is a note, not a button', (
      tester,
    ) async {
      await pumpLg(
        tester,
        const SizedBox(width: 300, child: LgMenuLoadingRow('正在读取…')),
      );
      expect(find.text('正在读取…'), findsOneWidget);
      expect(find.byType(LgButton), findsNothing);
    });
  });
}

void _noop() {}
