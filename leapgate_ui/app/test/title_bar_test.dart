import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';
import 'package:leapgate_ui/widgets/lg_title_bar.dart';

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

class _Log {
  final events = <String>[];
}

Widget _bar(
  _Log log, {
  int sessions = 2,
  int selected = 0,
  bool maximized = false,
  double width = 1280,
}) => SizedBox(
  width: width,
  child: LgTitleBar(
    labels: _labels,
    sessions: [
      for (var i = 0; i < sessions; i++)
        LgSessionTab(
          name: '设备$i',
          identity: i % 7,
          status: const LgRouteMark(route: LgRoute.direct, label: '直连'),
          unread: i == 1 ? 3 : 0,
        ),
    ],
    selected: selected,
    homeBadge: 1,
    maximized: maximized,
    onSelect: (i) => log.events.add('select $i'),
    onCloseTab: (i) => log.events.add('close $i'),
    onNewTab: () => log.events.add('new'),
    onMinimize: () => log.events.add('min'),
    onToggleMaximize: () => log.events.add('max'),
    onClose: () => log.events.add('close window'),
    onStartDrag: () => log.events.add('drag'),
    onStartResize: (e) => log.events.add('resize ${e.name}'),
  ),
);

Finder _icon(LgIcons icon) =>
    find.byWidgetPredicate((w) => w is LgIcon && w.icon == icon);

void main() {
  testWidgets(
    'home tab has a badge and no close button; session tabs can be closed',
    (tester) async {
      final log = _Log();
      await pumpLg(tester, _bar(log));
      expect(find.text('主页'), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // home badge
      expect(find.text('3'), findsOneWidget); // unread on session 2
      expect(_icon(LgIcons.x), findsNWidgets(2));

      await tester.tap(find.text('设备1'));
      await tester.tap(_icon(LgIcons.x).first);
      expect(log.events, ['select 2', 'close 1']);
    },
  );

  testWidgets('tabs, new tab and caption buttons call back', (tester) async {
    final log = _Log();
    await pumpLg(tester, _bar(log));
    await tester.tap(find.text('主页'));
    await tester.tap(_icon(LgIcons.plus));
    await tester.tap(_icon(LgIcons.windowMin));
    await tester.tap(_icon(LgIcons.windowMax));
    await tester.tap(_icon(LgIcons.windowClose));
    expect(log.events, ['select 0', 'new', 'min', 'max', 'close window']);
  });

  testWidgets('blank space drags the window and double click maximizes', (
    tester,
  ) async {
    final log = _Log();
    await pumpLg(tester, _bar(log));
    final bar = tester.getRect(find.byType(LgTitleBar));
    // Between the new-tab button and the caption buttons.
    final blank = Offset(bar.right - 3 * 46 - 20, bar.center.dy);
    await tester.dragFrom(blank, const Offset(40, 0));
    expect(log.events, ['drag']);
    log.events.clear();
    await tester.tapAt(blank);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(blank);
    await tester.pumpAndSettle();
    expect(log.events, ['max']);
  });

  testWidgets(
    'top edge resizes only when not maximized; maximized shows restore',
    (tester) async {
      final log = _Log();
      await pumpLg(tester, _bar(log));
      final bar = tester.getRect(find.byType(LgTitleBar));
      await tester.dragFrom(
        Offset(bar.center.dx, bar.top + 1),
        const Offset(0, -20),
      );
      await tester.dragFrom(
        Offset(bar.left + 2, bar.top + 1),
        const Offset(-20, -20),
      );
      expect(log.events, ['resize top', 'resize topLeft']);

      await pumpLg(tester, _bar(log, maximized: true));
      expect(_icon(LgIcons.windowRestore), findsOneWidget);
      expect(_icon(LgIcons.windowMax), findsNothing);
      log.events.clear();
      await tester.dragFrom(
        Offset(bar.center.dx, bar.top + 1),
        const Offset(0, 40),
      );
      expect(log.events, ['drag']);
      await tester.pumpAndSettle(); // let the double-click timer run out
    },
  );

  testWidgets('the tab list dropdown appears only when tabs overflow', (
    tester,
  ) async {
    final log = _Log();
    await pumpLg(tester, _bar(log));
    await tester.pumpAndSettle();
    expect(_icon(LgIcons.chevD), findsNothing);

    await pumpLg(tester, _bar(log, sessions: 12, width: 900));
    await tester.pumpAndSettle();
    expect(_icon(LgIcons.chevD), findsOneWidget);
    await tester.tap(_icon(LgIcons.chevD));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设备11').last);
    await tester.pumpAndSettle();
    expect(log.events, ['select 12']);
  });

  testWidgets('tabs are reachable with Tab and selected with Enter', (
    tester,
  ) async {
    final log = _Log();
    await pumpLg(tester, _bar(log));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(log.events, ['select 1']);
  });
}
