import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/exit_api.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/widgets/lg_device_card.dart';

import '../../core/test/exit_fakes.dart' show FakeExitApi;
import 'home_fakes.dart';

// "Use as exit node" in the device menu (01 P1 block F, 08 M5-9): only for a Windows device, and
// it goes to the exit page with the card. Device IDs and names are made up.

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(kDoubleTapTimeout);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _openMenu(WidgetTester tester, Map<String, String> peer) async {
  await pumpHome(tester, id: '135792468', status: ServiceStatus.ready);
  await loadRecent([peer]);
  await tester.pump();
  await tester.tap(
    find.byType(LgDeviceCard),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await _settle(tester);
}

void main() {
  late FakeExitApi api;

  setUp(() {
    installHomeFakes();
    // The card stops at once, so no exit session is started here.
    api = FakeExitApi()..addError = const ExitAddError('already');
    exitApi = api;
  });

  testWidgets('a Windows device: the card on the exit page', (tester) async {
    await _openMenu(tester, {
      'id': '123456789',
      'alias': '书房台式机',
      'platform': 'Windows',
    });
    await tester.tap(find.text('用作出口'), kind: PointerDeviceKind.mouse);
    await _settle(tester);
    expect(api.callsTo('sessionAdd').single[1], '123456789');
    expect(find.text('书房台式机'), findsOneWidget);
    expect(
      find.textContaining('已停止：本机已有连接此设备的出口或 TCP 隧道', findRichText: true),
      findsOneWidget,
    );
    expect(appCore.exitNodes.cards.single.id, '123456789');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a Linux device: not offered', (tester) async {
    await _openMenu(tester, {
      'id': '456789123',
      'alias': '客厅迷你主机',
      'platform': 'Linux',
    });
    expect(find.text('远程桌面'), findsOneWidget);
    expect(find.text('用作出口'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the connect box: for an ID, not for a name or a Linux device', (
    tester,
  ) async {
    await pumpHome(tester, id: '135792468', status: ServiceStatus.ready);
    await loadRecent([
      {'id': '456789123', 'alias': '客厅迷你主机', 'platform': 'Linux'},
    ]);
    await tester.pump();
    Future<void> open(String menu) async {
      await tester.tap(find.bySemanticsLabel(menu));
      await _settle(tester);
    }

    Future<void> close() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
    }

    // A name: the current row is the Linux device, and "Connect to 客厅" is not an ID.
    await tester.enterText(find.byType(EditableText), '客厅');
    await tester.pump();
    await open('连接方式');
    expect(find.text('远程桌面'), findsOneWidget);
    expect(find.text('用作出口'), findsNothing);
    await close();
    await open('其他连接方式');
    expect(find.text('用作出口'), findsNothing);
    await close();

    await tester.enterText(find.byType(EditableText), '123456789');
    await tester.pump();
    await open('其他连接方式');
    expect(find.text('用作出口'), findsOneWidget);
    await close();
    await open('连接方式');
    await tester.tap(find.text('用作出口'), kind: PointerDeviceKind.mouse);
    await _settle(tester);
    expect(api.callsTo('sessionAdd').single[1], '123456789');
    await tester.pumpWidget(const SizedBox());
  });
}
