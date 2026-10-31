import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/widgets/lg_device.dart';
import 'package:leapgate_ui/widgets/lg_device_card.dart';

import 'home_fakes.dart';

// The device list of the devices page in M2b (01 P1 block F): categories, views, sorting, the
// device menu, multiple selection, and the search across categories (block E). Sample devices
// as in 01 §7.4.

const _shufang = {
  'id': '123456789',
  'alias': '书房台式机',
  'username': 'zhangsan',
  'hostname': 'DESKTOP-SHUFANG',
  'platform': 'Windows',
};
const _mama = {
  'id': '234567891',
  'alias': '妈妈的笔记本',
  'username': 'mama',
  'hostname': 'LAPTOP-MAMA',
  'platform': 'Windows',
};
const _office = {
  'id': '345678912',
  'alias': '办公室电脑',
  'username': 'zhangsan',
  'hostname': 'OFFICE-PC01',
  'platform': 'Windows',
};
const _mini = {
  'id': '456789123',
  'alias': '客厅迷你主机',
  'username': 'media',
  'hostname': 'minipc',
  'platform': 'Linux',
};

final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

late FakeBind bind;
late FakeNavigation nav;

Future<void> pumpPeers(
  WidgetTester tester, {
  List<Map<String, String>> recent = const [_shufang, _mama],
  List<Map<String, String>> fav = const [],
  List<Map<String, String>> lan = const [],
}) async {
  await pumpHome(tester, id: '135792468', status: ServiceStatus.ready);
  await loadRecent(recent);
  await loadCategory('load_fav_peers', fav);
  await loadCategory('load_lan_peers', lan);
  await tester.pump();
}

/// After a click: a card waits for a second click before it lets a click inside it through,
/// and menus and dialogs fade in. Not `pumpAndSettle`: the "checking" state of a row spins.
Future<void> settle(WidgetTester tester) async {
  await tester.pump(kDoubleTapTimeout);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Clicks with the mouse, as on the desktop: a touch would turn hover effects off (the "⋯" of a
/// card shows on hover).
Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last, kind: PointerDeviceKind.mouse);
  await settle(tester);
}

/// Opens the device menu of the only device on screen with a right click.
Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(
    find.byType(LgDeviceCard),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await settle(tester);
}

/// Opens it with the "⋯" the card shows while the pointer is on it. Only before any other click
/// of the test (the test's clicks are the same mouse).
Future<void> openMenuWithMore(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(find.byType(LgDeviceCard)));
  await tester.pump();
  await tester.tap(find.bySemanticsLabel(RegExp('^设备菜单 ')));
  await settle(tester);
}

/// The names of the cards in the order shown.
List<String> cardNames(WidgetTester tester) => [
  for (final card in tester.widgetList<LgDeviceCard>(
    find.byType(LgDeviceCard),
  ))
    card.name,
];

void main() {
  setUp(() {
    final fakes = installHomeFakes();
    bind = fakes.bind;
    nav = fakes.nav;
  });

  testWidgets(
    'three categories; each empty one says so; LAN looks for devices',
    (tester) async {
      await pumpPeers(tester);
      expect(find.text('最近'), findsOneWidget);
      expect(find.text('书房台式机'), findsOneWidget);

      await tapText(tester, '收藏');
      expect(find.text('暂无收藏的设备'), findsOneWidget);
      expect(bind.callsTo(#mainLoadFavPeers), hasLength(2));

      await tapText(tester, '局域网');
      expect(find.text('未在局域网中发现设备'), findsOneWidget);
      expect(bind.callsTo(#mainDiscover), hasLength(1));
      expect(bind.flutter['peer-tab-index'], '2');
      await unmount(tester);
    },
    variant: _windows,
  );

  testWidgets(
    'cards in the simple mode, the list in the detail mode (01 §2.3)',
    (tester) async {
      await pumpPeers(tester);
      expect(find.byType(LgDeviceCard), findsNWidgets(2));
      expect(find.byType(LgDeviceRow), findsNothing);

      await tapText(tester, '视图');
      await tapText(tester, '详细');
      expect(bind.local['leapgate-ui-mode'], 'detail');
      expect(find.byType(LgDeviceRow), findsNWidgets(2));

      // A view picked by hand wins over the mode.
      await tapText(tester, '视图');
      await tapText(tester, '卡片');
      expect(bind.flutter['peer-card-ui-type'], '0');
      expect(find.byType(LgDeviceCard), findsNWidgets(2));
      await unmount(tester);
    },
    variant: _windows,
  );

  testWidgets(
    'sorting: not in "Recent"; online first holds the order it came in',
    (tester) async {
      await pumpPeers(tester, fav: [_shufang, _mama, _office]);
      expect(find.text('排序'), findsNothing);
      await tapText(tester, '收藏');
      expect(cardNames(tester), ['书房台式机', '妈妈的笔记本', '办公室电脑']);

      await tapText(tester, '排序');
      await tapText(tester, '名称');
      expect(bind.flutter['peer-sorting'], 'Remote Host');
      // Names compare by code point, not by pinyin.
      expect(cardNames(tester), ['书房台式机', '办公室电脑', '妈妈的笔记本']);
      await unmount(tester);
    },
    variant: _windows,
  );

  group('the device menu by category (01 P1 block F)', () {
    testWidgets('Recent: rename, favorites, saved password, delete', (
      tester,
    ) async {
      bind.hasPassword = true;
      await pumpPeers(tester, recent: [_shufang]);
      await openMenuWithMore(tester);
      for (final item in [
        '远程桌面',
        '经中继连接',
        '始终经中继连接',
        '创建桌面快捷方式',
        '重命名',
        '加入收藏',
        '清除保存的密码',
        '删除',
      ]) {
        expect(find.text(item), findsOneWidget, reason: item);
      }
      expect(find.text('网络唤醒'), findsNothing);
      await unmount(tester);
    }, variant: _windows);

    testWidgets('Favorites: "Remove from favorites", nothing to delete', (
      tester,
    ) async {
      await pumpPeers(tester, recent: [], fav: [_shufang]);
      await tapText(tester, '收藏');
      await openMenu(tester);
      expect(find.text('移出收藏'), findsOneWidget);
      expect(find.text('删除'), findsNothing);
      expect(find.text('危险操作'), findsNothing);
      expect(find.text('清除保存的密码'), findsNothing);
      await unmount(tester);
    }, variant: _windows);

    testWidgets('LAN: wake-on-LAN and remove, no rename', (tester) async {
      await pumpPeers(tester, recent: [], lan: [_mini]);
      await tapText(tester, '局域网');
      await openMenu(tester);
      expect(find.text('网络唤醒'), findsOneWidget);
      expect(find.text('移除'), findsOneWidget);
      expect(find.text('重命名'), findsNothing);
      await tapText(tester, '网络唤醒');
      expect(bind.callsTo(#mainWol).single.namedArguments[#id], '456789123');
      await unmount(tester);
    }, variant: _windows);
  });

  testWidgets('delete asks first, on the home tab', (tester) async {
    await pumpPeers(tester, recent: [_shufang]);
    await openMenu(tester);
    await tapText(tester, '删除');
    expect(find.text('删除“书房台式机”？'), findsOneWidget);
    await tapText(tester, '取消');
    expect(bind.callsTo(#mainRemovePeer), isEmpty);

    await openMenu(tester);
    await tapText(tester, '删除');
    await tapText(tester, '删除');
    expect(
      bind.callsTo(#mainRemovePeer).single.namedArguments[#id],
      '123456789',
    );
    // Its own toast, not upstream's "Successful".
    expect(appCore.toasts.current?.key, 'peersToastDeleted');
    await unmount(tester);
    await toastGone(tester);
  }, variant: _windows);

  testWidgets('multiple selection leaves the search results alone', (
    tester,
  ) async {
    await pumpPeers(tester, recent: [_shufang, _mama]);
    await tapText(tester, '多选');
    await tester.enterText(find.byType(EditableText), '书房');
    await tester.pump();
    await tester.tap(find.text('书房台式机'));
    await settle(tester);
    await tester.enterText(find.byType(EditableText), '');
    await tester.pump();
    expect(find.text('已选择 0 台'), findsOneWidget);
    await unmount(tester);
  }, variant: _windows);

  testWidgets('rename sets the alias, an always-relay tick saves', (
    tester,
  ) async {
    bind.peerOptions['123456789'] = {'alias': '书房台式机'};
    await pumpPeers(tester, recent: [_shufang]);
    await openMenu(tester);
    await tapText(tester, '重命名');
    await tester.enterText(find.byType(EditableText).last, ' 书房主机 ');
    await tapText(tester, '确定');
    expect(
      bind.callsTo(#mainSetPeerAlias).single.namedArguments[#alias],
      '书房主机',
    );

    await openMenu(tester);
    await tapText(tester, '始终经中继连接');
    expect(bind.peerOptions['123456789']!['force-always-relay'], 'Y');
    await unmount(tester);
    await toastGone(tester);
  }, variant: _windows);

  testWidgets(
    'multiple selection: pick, Shift for a run, select all, delete',
    (tester) async {
      await pumpPeers(tester, recent: [_shufang, _mama, _office, _mini]);
      await tapText(tester, '多选');
      expect(find.text('已选择 0 台'), findsOneWidget);
      expect(find.text('加入收藏'), findsOneWidget);

      await tester.tap(find.text('书房台式机'));
      await tester.pump(kDoubleTapTimeout);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('办公室电脑'));
      await tester.pump(kDoubleTapTimeout);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(find.text('已选择 3 台'), findsOneWidget);

      await tapText(tester, '全选');
      expect(find.text('已选择 4 台'), findsOneWidget);

      await tapText(tester, '删除');
      expect(find.text('删除 4 台设备？'), findsOneWidget);
      await tapText(tester, '删除');
      expect(bind.callsTo(#mainRemovePeer), hasLength(4));
      // Back to the category bar.
      expect(find.text('多选'), findsOneWidget);
      await unmount(tester);
      await toastGone(tester);
    },
    variant: _windows,
  );

  testWidgets(
    'multiple selection in favorites removes them without asking',
    (tester) async {
      await pumpPeers(tester, recent: [], fav: [_shufang, _mama]);
      await tapText(tester, '收藏');
      await tapText(tester, '多选');
      await tapText(tester, '全选');
      await tapText(tester, '移出收藏');

      expect(find.text('取消'), findsNothing);
      expect(appCore.toasts.current?.key, 'peersToastRemovedFavorites');
      await unmount(tester);
      await toastGone(tester);
    },
    variant: _windows,
  );

  testWidgets(
    'the search covers the three categories, each device once with its source',
    (tester) async {
      bind.flutter['peer-card-ui-type'] = '2';
      await pumpPeers(
        tester,
        recent: [_shufang],
        fav: [_shufang, _mama],
        lan: [_mini],
      );
      await tester.enterText(find.byType(EditableText), 'a');
      await tester.pump();
      final rows = tester.widgetList<LgDeviceRow>(find.byType(LgDeviceRow));
      expect(
        [for (final r in rows) (r.name, r.source)],
        [('书房台式机', '最近'), ('妈妈的笔记本', '收藏'), ('客厅迷你主机', '局域网')],
      );

      // "⋯" at the end of "Connect to".
      await tester.tap(find.bySemanticsLabel('其他连接方式'));
      await settle(tester);
      await tapText(tester, '经中继连接');
      expect(nav.connects, [(id: 'a', forceRelay: true)]);
      await unmount(tester);
    },
    variant: _windows,
  );

  testWidgets('more than 1000 devices: the first 1000 and a note', (
    tester,
  ) async {
    bind.flutter['peer-card-ui-type'] = '2';
    await pumpPeers(
      tester,
      recent: [
        for (var i = 0; i < 1001; i++) {'id': '${100000000 + i}'},
      ],
    );
    expect(find.text('仅显示前 1000 台设备，可使用搜索缩小范围'), findsOneWidget);
    await unmount(tester);
  }, variant: _windows);
}
