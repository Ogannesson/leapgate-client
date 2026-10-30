import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/shell/navigation.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';

import 'home_fakes.dart';

// Documentation-style sample devices (01 §7.4), most recent first.
const _recent = [
  {
    'id': '123456789',
    'alias': '书房台式机',
    'username': 'zhangsan',
    'hostname': 'DESKTOP-SHUFANG',
  },
  {'id': '234567891', 'username': 'mama', 'hostname': 'LAPTOP-MAMA'},
  {'id': '345678912', 'alias': '书房笔记本'},
  {'id': '456789123'},
];

// Focus and clicks behave as on the desktop the app ships for.
final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

late FakeBind bind;
late FakeNavigation nav;

Future<void> pumpDevices(
  WidgetTester tester, {
  ServiceStatus status = ServiceStatus.ready,
}) async {
  await pumpHome(tester, id: '135792468', status: status);
  await loadRecent(_recent);
  await tester.pump();
}

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText), text);
  await tester.pump();
}

/// Whether the row showing [text] is the current one (highlighted or selected).
bool isCurrent(WidgetTester tester, String text) =>
    tester.getSemantics(find.text(text)).flagsCollection.isSelected ==
    Tristate.isTrue;

/// The "连接" button next to the box (rows show their own "连接" only while hovered).
bool connectEnabled(WidgetTester tester) =>
    tester
        .widget<LgButton>(
          find.byWidgetPredicate((w) => w is LgButton && w.label == '连接'),
        )
        .onPressed !=
    null;

void main() {
  setUp(() {
    final fakes = installHomeFakes();
    bind = fakes.bind;
    nav = fakes.nav;
  });

  group('recent list (01 P1 block F)', () {
    testWidgets('loading until Rust answers, then empty', (tester) async {
      await pumpHome(tester, id: '135792468');
      expect(bind.callsTo(#mainLoadRecentPeers), hasLength(1));
      expect(find.bySemanticsLabel('正在加载…'), findsOneWidget);

      await loadRecent([]);
      await tester.pump();
      expect(find.bySemanticsLabel('正在加载…'), findsNothing);
      expect(find.text('暂无最近连接的设备'), findsOneWidget);
      await unmount(tester);
    }, variant: _windows);

    testWidgets('names, IDs and online state', (tester) async {
      await pumpDevices(tester);
      expect(find.text('最近'), findsOneWidget);
      // Alias, else host name, else the formatted ID.
      expect(find.text('书房台式机'), findsOneWidget);
      expect(find.text('LAPTOP-MAMA'), findsOneWidget);
      expect(find.text('456 789 123'), findsNWidgets(2));
      expect(
        find.text('123 456 789  zhangsan@DESKTOP-SHUFANG'),
        findsOneWidget,
      );
      expect(
        find.textContaining('正在查询…', findRichText: true),
        findsNWidgets(4),
      );

      // The rows on screen are asked about once they stood for a second.
      await tester.pump(const Duration(milliseconds: 1500));
      final asked = bind.callsTo(#queryOnlines).single.namedArguments[#ids];
      expect(asked, unorderedEquals(_recent.map((p) => p['id'])));
      await platformFFI.tryHandle({
        'name': 'callback_query_onlines',
        'onlines': '123456789,234567891',
        'offlines': '345678912,456789123',
      });
      await tester.pump();
      expect(find.textContaining('在线', findRichText: true), findsNWidgets(2));
      expect(find.textContaining('离线', findRichText: true), findsNWidgets(2));
      await unmount(tester);
    }, variant: _windows);

    testWidgets('without the server nothing answers: offline, not checking', (
      tester,
    ) async {
      await pumpDevices(tester, status: ServiceStatus.notReady);
      expect(
        find.textContaining('正在查询…', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('离线', findRichText: true), findsNWidgets(4));
      await unmount(tester);
    }, variant: _windows);

    testWidgets('a click selects, a double click connects', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpDevices(tester);
      await tester.tap(find.text('LAPTOP-MAMA'));
      await tester.pump(kDoubleTapTimeout);
      expect(isCurrent(tester, 'LAPTOP-MAMA'), isTrue);
      expect(nav.connects, isEmpty);

      await tester.tap(find.text('书房台式机'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('书房台式机'));
      await tester.pump(kDoubleTapTimeout);
      expect(nav.connects, [(id: '123456789', forceRelay: false)]);
      await unmount(tester);
      semantics.dispose();
    }, variant: _windows);

    testWidgets('Enter after a click connects the clicked device', (
      tester,
    ) async {
      await pumpDevices(tester);
      await tester.tap(find.text('LAPTOP-MAMA'));
      await tester.pump(kDoubleTapTimeout);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(nav.connects, [(id: '234567891', forceRelay: false)]);
      await unmount(tester);
    }, variant: _windows);

    testWidgets('arrow keys from the empty box, then Enter, connect a row', (
      tester,
    ) async {
      await pumpDevices(tester);
      await tester.tap(find.byType(EditableText));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(nav.connects, isEmpty, reason: 'nothing is current yet');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(nav.connects, [(id: '234567891', forceRelay: false)]);
      await unmount(tester);
    }, variant: _windows);

    testWidgets('the current device stays when Rust pushes the list again', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpDevices(tester);
      await tester.tap(find.byType(EditableText));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(isCurrent(tester, 'LAPTOP-MAMA'), isTrue);

      // A session in another tab reconnected: its device moved to the top.
      await loadRecent([_recent[3], _recent[0], _recent[1], _recent[2]]);
      await tester.pump();
      expect(isCurrent(tester, 'LAPTOP-MAMA'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(nav.connects, [(id: '234567891', forceRelay: false)]);
      await unmount(tester);
      semantics.dispose();
    }, variant: _windows);
  });

  group('connect box (01 P1 block E, Q2)', () {
    testWidgets('"Connect" is disabled while the box is empty', (tester) async {
      await pumpDevices(tester);
      expect(connectEnabled(tester), isFalse);
      await type(tester, '6789');
      expect(connectEnabled(tester), isTrue);
      await type(tester, '   ');
      expect(connectEnabled(tester), isFalse);
      await unmount(tester);
    }, variant: _windows);

    testWidgets('typing turns the list into search results', (tester) async {
      await pumpDevices(tester);
      await type(tester, '书房');
      expect(find.text('搜索结果'), findsOneWidget);
      expect(find.text('连接到 书房'), findsOneWidget);
      expect(find.text('书房台式机'), findsOneWidget);
      expect(find.text('书房笔记本'), findsOneWidget);
      expect(find.text('LAPTOP-MAMA'), findsNothing);

      await type(tester, '办公桌');
      expect(find.text('连接到 办公桌'), findsOneWidget);
      expect(find.text('未找到匹配的设备'), findsOneWidget);

      await type(tester, '');
      expect(find.text('最近'), findsOneWidget);
      expect(find.text('LAPTOP-MAMA'), findsOneWidget);
      await unmount(tester);
    }, variant: _windows);

    testWidgets('the default row', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpDevices(tester);

      // Looks like an address: "Connect to".
      await type(tester, '6789');
      expect(isCurrent(tester, '连接到 6789'), isTrue);
      expect(isCurrent(tester, '书房台式机'), isFalse);

      // A name: the first matching device.
      await type(tester, '书房');
      expect(isCurrent(tester, '连接到 书房'), isFalse);
      expect(isCurrent(tester, '书房台式机'), isTrue);

      // A device's own ID: that device.
      await type(tester, '345 678 912');
      expect(isCurrent(tester, '书房笔记本'), isTrue);
      expect(isCurrent(tester, '连接到 345 678 912'), isFalse);

      // Its whole user@host, copied from the row: that device.
      await type(tester, 'mama@LAPTOP-MAMA');
      expect(isCurrent(tester, 'LAPTOP-MAMA'), isTrue);

      // Nothing matches: "Connect to".
      await type(tester, '办公桌');
      expect(isCurrent(tester, '连接到 办公桌'), isTrue);
      await unmount(tester);
      semantics.dispose();
    }, variant: _windows);

    testWidgets('Enter runs the current row', (tester) async {
      await pumpDevices(tester);
      await type(tester, '书房');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      // By name: the device, not "书房" as an ID.
      expect(nav.connects.last, (id: '123456789', forceRelay: false));

      await type(tester, '6789/r');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      // As typed; navigation turns /r into a relay.
      expect(nav.connects.last, (id: '6789/r', forceRelay: false));
      await unmount(tester);
    }, variant: _windows);

    testWidgets('Enter on the help button opens the help, not a connection', (
      tester,
    ) async {
      await pumpDevices(tester);
      await type(tester, '6789');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
        find.ancestor(
          of: find.byElementPredicate((e) => e == focused),
          matching: find.bySemanticsLabel('帮助'),
        ),
        findsOneWidget,
        reason: 'Tab leaves the box for the help button',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(nav.connects, isEmpty);
      expect(find.text('可输入'), findsOneWidget);
      await unmount(tester);
    }, variant: _windows);

    testWidgets('arrow keys move, Esc goes back to the default', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpDevices(tester);
      await type(tester, '6789');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(isCurrent(tester, '书房台式机'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(isCurrent(tester, '书房台式机'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(isCurrent(tester, '连接到 6789'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(nav.connects.last, (id: '123456789', forceRelay: false));
      await unmount(tester);
      semantics.dispose();
    }, variant: _windows);

    testWidgets('"Connect via relay" in the menu', (tester) async {
      await pumpDevices(tester);
      await type(tester, '246813579');
      await tester.tap(find.bySemanticsLabel('连接方式'));
      await tester.pump();
      expect(find.text('远程桌面'), findsOneWidget);
      expect(
        find.text('今后连接此设备将始终经中继。可在设备菜单中取消“始终经中继连接”。'),
        findsOneWidget,
      );
      await tester.tap(find.text('经中继连接'));
      await tester.pump();
      expect(nav.connects, [(id: '246813579', forceRelay: true)]);
      await unmount(tester);
    }, variant: _windows);

    testWidgets('the help', (tester) async {
      await pumpDevices(tester);
      await tester.tap(find.bySemanticsLabel('帮助'));
      await tester.pump();
      expect(find.text('可输入'), findsOneWidget);
      expect(find.text('IP 地址（直连）'), findsOneWidget);
      expect(find.text('192.0.2.10'), findsOneWidget);
      await unmount(tester);
    }, variant: _windows);

    testWidgets('a focus request puts the text in, all selected', (
      tester,
    ) async {
      await pumpDevices(tester);
      // From another page of the home tab.
      await tester.tap(find.text('设置'));
      await tester.pump();
      expect(find.byType(EditableText), findsNothing);

      connectBoxFocusRequests.request(text: '987654321');
      await tester.pump();
      await tester.pump();
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
      expect(field.controller.text, '987654321');
      expect(
        field.controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 9),
      );
      await unmount(tester);
    }, variant: _windows);
  });
}
