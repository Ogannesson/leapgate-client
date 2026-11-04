import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/shell/main_window.dart';
import 'package:leapgate_ui/shell/navigation.dart';

import 'session_fakes.dart';

// "传出会话期间保持屏幕常亮" (02 §1.4.3, `待调.md` 2026-10-31): the screen is kept on while a
// session tab is open, unless the setting is off, and a change applies to the open session at
// once. The device ID is made up.

void main() {
  late List<bool> kept;

  setUp(() {
    installAppFakes();
    kept = [];
    displayKeeper = kept.add;
    addTearDown(() => displayKeeper = (_) {});
  });

  testMainWindow('a session keeps the screen on as the setting says',
      (tester) async {
    await pumpMainWindow(tester);
    mainNavigation.connect('100200300');
    await tester.pump();
    await tester.pump();
    expect(kept, [true]);

    final local = appCore.options.local;
    await local.setBool(kOptionKeepAwakeDuringOutgoingSessions, false);
    expect(kept, [true, false]);
    await local.setBool(kOptionKeepAwakeDuringOutgoingSessions, true);
    expect(kept, [true, false, true]);

    for (final d in appCore.sessions.devices) {
      await appCore.sessions.closeDevice(d);
    }
    await tester.pump();
    expect(kept, [true, false, true, false]);

    // Off: a new session leaves the screen alone.
    await local.setBool(kOptionKeepAwakeDuringOutgoingSessions, false);
    mainNavigation.connect('100200300');
    await tester.pump();
    await tester.pump();
    expect(kept, [true, false, true, false]);
  });
}
