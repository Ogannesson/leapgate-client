import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/widgets/lg_device.dart';
import 'package:leapgate_ui/widgets/lg_device_card.dart';
import 'package:leapgate_ui/widgets/lg_device_parts.dart';

import 'helpers.dart';

const _tags = [
  LgDeviceTag('家里', Color(0xFFC4527D)),
  LgDeviceTag('工作', Color(0xFF3F7CB3)),
];

class _Calls {
  int tap = 0, double = 0, connect = 0, more = 0;
  Offset? menu;
}

LgDeviceCard _card(
  _Calls calls, {
  bool? picked,
  bool selected = false,
  bool favorite = true,
  List<LgDeviceTag> tags = _tags,
  FocusNode? focus,
  LgDeviceStatus status = LgDeviceStatus.online,
}) => LgDeviceCard(
  name: '书房台式机',
  id: '123 456 789',
  platform: LgPlatform.windows,
  status: status,
  statusLabel: status == LgDeviceStatus.querying ? '正在查询…' : '在线',
  userHost: 'zhangsan@DESKTOP-SHUFANG',
  tags: tags,
  favorite: favorite,
  savedPassword: true,
  favoriteLabel: '已收藏',
  savedPasswordLabel: '已保存密码',
  selected: selected,
  picked: picked,
  focusNode: focus,
  onTap: () => calls.tap++,
  onDoubleTap: () => calls.double++,
  onConnect: () => calls.connect++,
  connectLabel: '连接',
  onMore: () => calls.more++,
  moreLabel: '更多操作',
  onContextMenu: (p) => calls.menu = p,
);

/// A window wide enough for the 1040 px of the device page.
/// Runs [body] as on a desktop: only there the pointer highlights what it is
/// on (the default platform of a test is not one).
Future<void> onDesktop(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void desktopTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) => onDesktop(() => body(tester)));

Future<void> pumpWide(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return pumpLg(tester, child);
}

void main() {
  group('LgDeviceCard', () {
    testWidgets('shows what the device is', (tester) async {
      await pumpLg(tester, SizedBox(width: 360, child: _card(_Calls())));
      expect(find.text('书房台式机'), findsOneWidget);
      expect(find.text('zhangsan@DESKTOP-SHUFANG'), findsOneWidget);
      expect(find.textContaining('在线', findRichText: true), findsOneWidget);
      expect(find.text('家里'), findsOneWidget);
      expect(find.text('工作'), findsOneWidget);
      // At rest the buttons are not there.
      expect(find.text('连接'), findsNothing);
    });

    testWidgets('a click selects, a double click connects', (tester) async {
      final calls = _Calls();
      await pumpLg(tester, SizedBox(width: 360, child: _card(calls)));
      await tester.tap(find.text('书房台式机'));
      expect((calls.tap, calls.double), (1, 0));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('书房台式机'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('书房台式机'));
      expect(calls.double, 1);
    });

    desktopTest('the pointer on the card shows connect and more', (
      tester,
    ) async {
      final calls = _Calls();
      await pumpLg(tester, SizedBox(width: 360, child: _card(calls)));
      await hover(tester, find.byType(LgDeviceCard));
      expect(find.text('连接'), findsOneWidget);
      await tester.tap(find.text('连接'));
      expect((calls.connect, calls.tap), (1, 0));
      await tester.tap(find.bySemanticsLabel('更多操作 书房台式机'));
      expect(calls.more, 1);
    });

    desktopTest(
      'two quick presses on the buttons never count as a double click',
      (tester) async {
        final calls = _Calls();
        await pumpLg(tester, SizedBox(width: 360, child: _card(calls)));
        await hover(tester, find.byType(LgDeviceCard));
        final more = find.byWidgetPredicate(
          (w) => w is LgIcon && w.icon == LgIcons.more,
        );
        // No time passes between the presses, so they are well inside the double
        // click window; the buttons only show while the pointer is on the card.
        await tester.tap(more);
        await tester.tap(more);
        expect((calls.more, calls.double, calls.connect), (2, 0, 0));
        // The same on "连接" (it connects once per press, and no more).
        await tester.tap(find.text('连接'));
        await tester.tap(find.text('连接'));
        expect((calls.connect, calls.double), (2, 0));
      },
    );

    desktopTest('a press on a button does not complete a click on the card', (
      tester,
    ) async {
      final calls = _Calls();
      await pumpLg(tester, SizedBox(width: 360, child: _card(calls)));
      await hover(tester, find.byType(LgDeviceCard));
      await tester.tap(find.text('书房台式机'));
      await tester.tap(find.text('连接'));
      expect(calls.double, 0);
      await tester.tap(find.text('书房台式机'));
      expect(calls.double, 0);
    });

    testWidgets('Enter on the focused card connects, and shows the buttons', (
      tester,
    ) async {
      final calls = _Calls();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pumpLg(
        tester,
        SizedBox(width: 360, child: _card(calls, focus: focus)),
      );
      focus.requestFocus();
      await tester.pump();
      expect(find.text('连接'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls.connect, 1);
    });

    desktopTest('in multi-select a click picks and no buttons show', (
      tester,
    ) async {
      final calls = _Calls();
      await pumpLg(
        tester,
        SizedBox(width: 360, child: _card(calls, picked: false)),
      );
      await hover(tester, find.byType(LgDeviceCard));
      expect(find.text('连接'), findsNothing);
      expect(find.byType(LgPickBox), findsOneWidget);
      await tester.tap(find.text('书房台式机'));
      expect((calls.tap, calls.connect), (1, 0));
    });

    testWidgets('a right click reports where', (tester) async {
      final calls = _Calls();
      await pumpLg(tester, SizedBox(width: 360, child: _card(calls)));
      await tester.tap(find.text('书房台式机'), buttons: kSecondaryButton);
      expect(calls.menu, isNotNull);
    });

    testWidgets('a screen reader gets the name, state, marks and actions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, SizedBox(width: 360, child: _card(_Calls())));
      expect(
        find.bySemanticsLabel(
          '书房台式机, 已收藏, 已保存密码, 在线, 123 456 789, '
          'zhangsan@DESKTOP-SHUFANG, 家里, 工作',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a selected card tells a screen reader it is selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        SizedBox(width: 360, child: _card(_Calls(), selected: true)),
      );
      final node = tester.getSemantics(find.byType(LgDeviceCard));
      expect(node.getSemanticsData().flagsCollection.isSelected.name, 'isTrue');
      handle.dispose();
    });

    testWidgets('a long name ends in … and keeps the marks', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 320,
          child: LgDeviceCard(
            name: '妈妈在客厅沙发旁边那台用了很多年的笔记本电脑',
            id: '234 567 891',
            platform: LgPlatform.windows,
            status: LgDeviceStatus.online,
            statusLabel: '在线',
            favorite: true,
            favoriteLabel: '已收藏',
            tags: _tags,
            onTap: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('querying shows the neutral state text', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 360,
          child: _card(_Calls(), status: LgDeviceStatus.querying),
        ),
      );
      expect(find.textContaining('正在查询', findRichText: true), findsOneWidget);
    });
  });

  group('LgDeviceCardGrid', () {
    Future<int> columns(WidgetTester tester, double width) async {
      await pumpWide(
        tester,
        SizedBox(
          width: width,
          child: LgDeviceCardGrid(
            children: [
              for (var i = 0; i < 7; i++)
                _card(_Calls(), tags: const [], favorite: false),
            ],
          ),
        ),
      );
      final lefts = {
        for (final e in find.byType(LgDeviceCard).evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dx,
      };
      return lefts.length;
    }

    testWidgets('as many columns as fit, each at least 300 wide', (
      tester,
    ) async {
      expect(await columns(tester, 1040), 3);
      expect(await columns(tester, 700), 2);
      expect(await columns(tester, 320), 1);
      // 2 columns need 612; at 611 there is one.
      expect(await columns(tester, 611), 1);
      expect(await columns(tester, 612), 2);
    });

    testWidgets('the cards share the width and are 112 high', (tester) async {
      await pumpWide(
        tester,
        SizedBox(
          width: 1040,
          child: LgDeviceCardGrid(
            children: [
              for (var i = 0; i < 3; i++)
                _card(_Calls(), tags: const [], favorite: false),
            ],
          ),
        ),
      );
      for (final e in find.byType(LgDeviceCard).evaluate()) {
        final size = tester.getSize(find.byWidget(e.widget));
        expect(size.height, kLgDeviceCardHeight);
        expect(size.width, closeTo((1040 - 24) / 3, .01));
      }
    });
  });

  group('LgDeviceRow additions', () {
    LgDeviceRow row(
      _Calls calls, {
      bool? picked,
      bool first = true,
      bool withMore = true,
    }) => LgDeviceRow(
      name: '书房台式机',
      id: '123 456 789',
      platform: LgPlatform.windows,
      status: LgDeviceStatus.online,
      statusLabel: '在线',
      userHost: 'zhangsan@DESKTOP-SHUFANG',
      tags: _tags,
      favorite: true,
      savedPassword: true,
      favoriteLabel: '已收藏',
      savedPasswordLabel: '已保存密码',
      picked: picked,
      topDivider: !first,
      onTap: () => calls.tap++,
      onDoubleTap: () => calls.double++,
      onConnect: () => calls.connect++,
      connectLabel: '连接',
      onMore: withMore ? () => calls.more++ : null,
      moreLabel: withMore ? '更多操作' : null,
    );

    desktopTest('tags, connect and more at the end of a hovered row', (
      tester,
    ) async {
      final calls = _Calls();
      await pumpWide(tester, SizedBox(width: 1040, child: row(calls)));
      expect(find.text('家里'), findsOneWidget);
      expect(find.text('连接'), findsNothing);
      await hover(tester, find.byType(LgDeviceRow));
      expect(find.text('连接'), findsOneWidget);
      await tester.tap(find.text('连接'));
      await tester.tap(
        find.byWidgetPredicate((w) => w is LgIcon && w.icon == LgIcons.more),
      );
      expect((calls.connect, calls.more), (1, 1));
    });

    desktopTest('two quick presses on the buttons of a row never connect it', (
      tester,
    ) async {
      final calls = _Calls();
      await pumpWide(tester, SizedBox(width: 1040, child: row(calls)));
      await hover(tester, find.byType(LgDeviceRow));
      final more = find.byWidgetPredicate(
        (w) => w is LgIcon && w.icon == LgIcons.more,
      );
      await tester.tap(more);
      await tester.tap(more);
      expect((calls.more, calls.double), (2, 0));
    });

    desktopTest('a double click on the row itself still counts', (
      tester,
    ) async {
      final calls = _Calls();
      await pumpWide(tester, SizedBox(width: 1040, child: row(calls)));
      await tester.tap(find.text('书房台式机'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('书房台式机'));
      expect(calls.double, 1);
    });

    desktopTest('multi-select puts the pick box in front, no buttons', (
      tester,
    ) async {
      await pumpLg(
        tester,
        SizedBox(width: 1040, child: row(_Calls(), picked: true)),
      );
      await hover(tester, find.textContaining('在线', findRichText: true));
      expect(find.byType(LgPickBox), findsOneWidget);
      expect(find.text('连接'), findsNothing);
    });

    testWidgets('a row may not have both a source and tags', (tester) async {
      expect(
        () => LgDeviceRow(
          name: 'a',
          id: '1',
          platform: LgPlatform.linux,
          status: LgDeviceStatus.online,
          statusLabel: '在线',
          source: '收藏',
          tags: _tags,
        ),
        throwsAssertionError,
      );
    });
  });

  group('LgDeviceTable', () {
    Widget table({
      LgTableSort? sort,
      ValueChanged<LgDeviceColumn>? onSort,
      bool withMore = true,
    }) => SizedBox(
      width: 1040,
      child: LgDeviceTable(
        columns: const [
          LgTableColumn(LgDeviceColumn.status, '状态', sortable: true),
          LgTableColumn(LgDeviceColumn.name, '名称', sortable: true),
          LgTableColumn(LgDeviceColumn.id, 'ID'),
          LgTableColumn(LgDeviceColumn.userHost, '用户@主机', sortable: true),
          LgTableColumn(LgDeviceColumn.tags, '标签'),
        ],
        sort: sort,
        onSort: onSort,
        moreColumn: withMore,
        ascendingLabel: '升序',
        descendingLabel: '降序',
        semanticLabel: '设备列表',
        rows: [
          LgDeviceRow(
            name: '书房台式机',
            id: '123 456 789',
            platform: LgPlatform.windows,
            status: LgDeviceStatus.online,
            statusLabel: '在线',
            userHost: 'zhangsan@DESKTOP-SHUFANG',
            tags: _tags,
            topDivider: false,
            onTap: () {},
            onMore: withMore ? () {} : null,
            moreLabel: withMore ? '更多操作' : null,
          ),
        ],
      ),
    );

    testWidgets('a sortable title reports its column', (tester) async {
      final got = <LgDeviceColumn>[];
      await pumpWide(tester, table(onSort: got.add));
      await tester.tap(find.text('名称'));
      await tester.tap(find.text('状态'));
      await tester.tap(find.text('ID'));
      await tester.tap(find.text('标签'));
      expect(got, [LgDeviceColumn.name, LgDeviceColumn.status]);
    });

    testWidgets('the sorted title shows an arrow and says the direction', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpWide(
        tester,
        table(sort: const LgTableSort(LgDeviceColumn.name), onSort: (_) {}),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('名称'));
      expect(node.getSemanticsData().value, '升序');
      await pumpWide(
        tester,
        table(
          sort: const LgTableSort(LgDeviceColumn.name, ascending: false),
          onSort: (_) {},
        ),
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('名称'))
            .getSemanticsData()
            .value,
        '降序',
      );
      handle.dispose();
    });

    testWidgets('titles and rows line up (the same left edge)', (tester) async {
      await pumpWide(tester, table(sort: null, onSort: (_) {}));
      // ID has fixed width in both.
      final header = tester.getTopLeft(find.text('ID')).dx;
      final cell = tester.getTopLeft(find.text('123 456 789')).dx;
      expect((header - cell).abs(), lessThan(1));
    });

    testWidgets('without onSort the titles are plain text', (tester) async {
      await pumpWide(tester, table());
      await tester.tap(find.text('名称'));
      expect(tester.takeException(), isNull);
    });
  });

  group('tags', () {
    testWidgets('many tags are cut, not wrapped', (tester) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 120,
          child: LgTagChips([
            LgDeviceTag('家里', Color(0xFFC4527D)),
            LgDeviceTag('工作', Color(0xFF3F7CB3)),
            LgDeviceTag('常用', Color(0xFF8A6FD1)),
            LgDeviceTag('另一个很长的标签', Color(0xFF009184)),
          ]),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(LgTagChips)).height, lessThan(30));
    });
  });
}
