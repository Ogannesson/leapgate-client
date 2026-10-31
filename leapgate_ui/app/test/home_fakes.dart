import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/app_window.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/pages/home/home_page.dart';
import 'package:leapgate_ui/shell/navigation.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';

/// Records the bridge calls the home page makes.
class FakeBind implements RustdeskImpl {
  final calls = <Invocation>[];

  List<Invocation> callsTo(Symbol name) =>
      calls.where((c) => c.memberName == name).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    switch (invocation.memberName) {
      case #mainLoadRecentPeers:
      case #queryOnlines:
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeWindow implements AppWindow {
  @override
  Future<void> bringToFront() async {}

  @override
  Future<Rect> getFrame() async => Rect.zero;

  @override
  Future<void> setFullscreen(bool fullscreen) async {}
}

class FakeNavigation implements MainNavigation {
  final connects = <({String id, bool forceRelay})>[];

  @override
  void connect(
    String id, {
    String password = '',
    bool isSharedPassword = false,
    bool forceRelay = false,
    String switchUuid = '',
  }) => connects.add((id: id, forceRelay: forceRelay));

  @override
  void showHome({bool focusConnectBox = false, String? connectBoxText}) {}
}

/// Fresh fakes behind `bind`, `appCore` and `mainNavigation` for one test.
({FakeBind bind, FakeNavigation nav}) installHomeFakes() {
  final bind = FakeBind();
  platformFFI.setBindingForTesting(bind);
  appCore = AppCore(window: FakeWindow());
  // Its event handlers are registered by name; the next test's AppCore needs the names free.
  addTearDown(appCore.recentPeers.dispose);
  final nav = FakeNavigation();
  mainNavigation = nav;
  return (bind: bind, nav: nav);
}

/// Rust pushing the recent list.
Future<void> loadRecent(List<Map<String, String>> peers) =>
    platformFFI.tryHandle({
      'name': 'load_recent_peers',
      'peers': peers.isEmpty ? '' : jsonEncode(peers),
    });

/// The home page in Chinese at [size], over a status model it returns.
Future<LocalStatusModel> pumpHome(
  WidgetTester tester, {
  String id = '',
  ServiceStatus status = ServiceStatus.connecting,
  Size size = const Size(1280, 760),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final model = LocalStatusModel()
    ..id = id
    ..status = status;
  addTearDown(model.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
      home: Scaffold(body: HomePage(status: model)),
    ),
  );
  return model;
}

/// Takes the page down so its timers stop before the test ends.
Future<void> unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());
