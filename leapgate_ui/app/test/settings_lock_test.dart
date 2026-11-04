import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/settings/unlock.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/shell/main_window.dart';
import 'package:leapgate_ui/shell/navigation.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';

import 'session_fakes.dart';

// The settings lock in the main window (02 §1.2.6): a session tab or hiding the window locks
// again; and "启动服务" asks first while a session is open (02 §1.3.8). The device ID is made up.

/// The installed version: no unlock PIN, UAC lets the user through, the service does not start.
class _Bind extends AppFakeBind {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #mainGetUnlockPin:
        return '';
      case #mainCheckSuperUserPermission:
        return Future.value(true);
      case #mainSetOption:
        calls.add(invocation);
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

final _lockBar = find.text('已锁定。修改这些设置需要管理员权限。');

Future<void> _turns(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, {ServiceStatus? status}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final model = LocalStatusModel();
  if (status != null) model.status = status;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
      home: MainWindow(status: model),
    ),
  );
  mainNavigation.showSettings(SettingsSectionId.service);
  await _turns(tester);
}

Future<void> _unlock(WidgetTester tester) async {
  expect(_lockBar, findsOneWidget);
  await tester.tap(find.text('解锁'));
  await _turns(tester);
  expect(_lockBar, findsNothing);
}

void main() {
  late _Bind bind;

  setUp(() {
    installAppFakes();
    bind = _Bind()..installed = true;
    platformFFI.setBindingForTesting(bind);
    addTearDown(settingsUnlock.lock);
  });

  testMainWindow('a session tab locks the settings again', (tester) async {
    await _pump(tester);
    await _unlock(tester);

    mainNavigation.connect('100200300');
    await _turns(tester);
    mainNavigation.showHome();
    await _turns(tester);
    expect(_lockBar, findsOneWidget);
  });

  testMainWindow('hiding the window locks the settings again', (tester) async {
    await _pump(tester);
    await _unlock(tester);

    await windowEvent(tester, 'hide');
    await _turns(tester);
    expect(_lockBar, findsOneWidget);
  });

  testMainWindow('installed, "启动服务" with a session open asks first', (
    tester,
  ) async {
    await _pump(tester, status: ServiceStatus.stopped);
    mainNavigation.connect('100200300');
    await _turns(tester);
    mainNavigation.showHome();
    await _turns(tester);

    // The home page has its own; the section's is the last.
    await tester.tap(find.text('启动服务').last);
    await _turns(tester);
    expect(find.text('启动服务？'), findsOneWidget);
    expect(find.text('Leapgate 将关闭并重新打开，所有会话和正在使用的出口都将断开。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await _turns(tester);
    expect(bind.calls.where((c) => c.memberName == #mainSetOption), isEmpty);
  });
}
