import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/shell/navigation.dart';
import 'package:leapgate_ui/widgets/lg_toolbar_dock.dart';

import 'session_fakes.dart';

// 工具栏与显示器 changed while a session is open: its toolbar follows at once, without
// reconnecting (02 §1.4.4, §3.3). The writes are the ones the section makes. The device ID is
// made up.

const _id = '100200300';

/// Keeps the defaults for new devices as Rust does.
class _Bind extends AppFakeBind {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #mainSetUserDefaultOption) {
      final args = invocation.namedArguments;
      userDefaults[args[#key]] = args[#value];
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  late AppFakes fakes;

  setUp(() {
    final installed = installAppFakes();
    final bind = _Bind();
    platformFFI.setBindingForTesting(bind);
    fakes = (bind: bind, lg: installed.lg, window: installed.window);
  });

  testMainWindow('an open session follows the toolbar settings', (tester) async {
    await pumpMainWindow(tester);
    mainNavigation.connect(_id);
    await tester.pump();
    await tester.pump();
    final s = appCore.sessions.sessionsOf(_id).single;
    await emit(tester, fakes, s, connectionReady(direct: true));
    await emit(tester, fakes, s, peerInfo(displays: 2));
    await tester.pumpAndSettle();
    expect(find.text('显示器'), findsOneWidget);
    expect(find.bySemanticsLabel('显示器 1'), findsNothing);
    expect(find.bySemanticsLabel('下一个显示器（1/2）'), findsNothing);
    LgToolbarPlacer placer() => tester.widget(find.byType(LgToolbarPlacer));
    expect(placer().anyEdge, isFalse);

    final options = appCore.options;
    await options.userDefault.set(kKeyShowMonitorsToolbar, 'Y');
    await options.local.setBool(kOptionAllowMonitorSwitchMainToolbar, true);
    await options.local.setBool(kOptionAllowMultiEdgeToolbarDock, true);
    await tester.pumpAndSettle();
    expect(find.text('显示器'), findsNothing);
    expect(find.bySemanticsLabel('显示器 1'), findsOneWidget);
    expect(find.bySemanticsLabel('显示器 2'), findsOneWidget);
    expect(find.bySemanticsLabel('下一个显示器（1/2）'), findsOneWidget);
    expect(placer().anyEdge, isTrue);
  });
}
