// The count on the navigation item "出口与隧道" (docs 14 §2.6 first row, `p8-nav-*`): 4 px from
// the name, 6 px either side of the reminder mark, and a name that does not fit ends in an
// ellipsis instead of pushing the number out. The nav item is private to the home page, so it
// is looked at through the main window with one exit running.

import 'dart:convert';

import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/exit_api.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/pages/home/home_page.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';

import '../../core/test/exit_fakes.dart' show FakeExitApi;
import 'session_fakes.dart';

const _id = '100200300';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeExitApi api;

  setUp(() {
    installAppFakes();
    api = FakeExitApi();
    exitApi = api;
  });

  Finder inNav(Finder f) =>
      find.descendant(of: find.byType(HomePage), matching: f);

  testMainWindow('the number stands 4 px after the name', (tester) async {
    await pumpMainWindow(tester);
    appCore.exitNodes.use(_id);
    await _settle(tester);

    final name = tester.getRect(inNav(find.text('出口与隧道')));
    final badge = tester.getRect(inNav(find.byType(LgBadge)));
    expect(badge.left - name.right, 4);
    expect(inNav(find.byType(LgBadge)), findsOneWidget);
  });

  testMainWindow('the reminder mark has 6 px on both sides', (tester) async {
    await pumpMainWindow(tester);
    appCore.exitNodes.use(_id);
    await _settle(tester);
    final card = appCore.exitNodes.cardOf(_id)!;
    (bind as FakeBind).streams[card.sessionId]!.add(
      EventToUI.event(jsonEncode(msgbox('wait-remote-accept-nook', '', ''))),
    );
    await _settle(tester);

    final name = tester.getRect(inNav(find.text('出口与隧道')));
    final badge = tester.getRect(inNav(find.byType(LgBadge)));
    // 6, the 16 px triangle, 6, then the number.
    expect(badge.left - name.right, 6 + 16 + 6);
  });
}
