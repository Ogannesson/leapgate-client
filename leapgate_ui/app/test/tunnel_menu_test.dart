import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/tunnel_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/widgets/lg_device_card.dart';

import 'home_fakes.dart';
import 'tunnel_fakes.dart';

// "TCP 隧道" and "RDP" in the device menu (13 §1.1.2): the card on the exit page; the pencil of
// the "RDP" row only opens the RDP settings. Device IDs and names are made up.

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(kDoubleTapTimeout);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  late FakeTunnelApi api;

  setUp(() {
    installHomeFakes();
    // The card stops at once, so no session is started here.
    api = FakeTunnelApi()..addError = const TunnelAddError('already');
    tunnelApi = api;
  });

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(
      find.byType(LgDeviceCard),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await _settle(tester);
  }

  testWidgets(
    '"TCP 隧道" opens the card; the pencil of "RDP" only its settings',
    (tester) async {
      await pumpHome(tester, id: '135792468', status: ServiceStatus.ready);
      await loadRecent([
        {'id': '123456789', 'alias': '书房台式机', 'platform': 'Windows'},
      ]);
      await tester.pump();

      await openMenu(tester);
      expect(find.text('TCP 隧道'), findsOneWidget);
      expect(find.text('RDP'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('RDP 设置'));
      await _settle(tester);
      expect(find.text('RDP 设置'), findsOneWidget);
      expect(api.callsTo('sessionAdd'), isEmpty);
      await tester.tap(find.text('取消'));
      await _settle(tester);

      await openMenu(tester);
      await tester.tap(find.text('TCP 隧道'), kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(api.callsTo('sessionAdd').single.sublist(1, 3), [
        '123456789',
        TunnelKind.tcp,
      ]);
      expect(
        appCore.tunnels.cardOf('123456789', TunnelKind.tcp)!.name,
        '书房台式机',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('an Android device: no TCP tunnel, no RDP', (tester) async {
    await pumpHome(tester, id: '135792468', status: ServiceStatus.ready);
    await loadRecent([
      {'id': '456789123', 'alias': '手机', 'platform': 'Android'},
    ]);
    await tester.pump();
    await openMenu(tester);
    expect(find.text('远程桌面'), findsOneWidget);
    expect(find.text('TCP 隧道'), findsNothing);
    expect(find.text('RDP'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
