import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/shell/main_window.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';

// core's fakes (the bridge, block 2, the window) with what the session pages call on top.
import '../../core/test/fakes.dart';

export '../../core/test/fakes.dart';

class AppFakeBind extends FakeBind {
  bool installed = false;
  final localOptions = <String, String>{};
  final flutterOptions = <String, String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      case #hostStopSystemKeyPropagate:
      case #setCurSessionId:
      case #sessionRestartRemoteDevice:
      case #sessionCtrlAltDel:
      case #sessionSetViewStyle:
      case #sessionSetImageQuality:
      case #sessionToggleOption:
      case #mainOnMainWindowClose:
        calls.add(invocation);
        return Future<void>.value();
      case #sessionEnterOrLeave:
        calls.add(invocation);
        return null;
      case #mainSetLocalOption:
        calls.add(invocation);
        localOptions[args[#key]] = args[#value];
        return Future<void>.value();
      case #mainGetLocalOption:
        return localOptions[args[#key]] ?? '';
      case #getLocalFlutterOption:
        return flutterOptions[args[#k]] ?? '';
      case #setLocalFlutterOption:
        flutterOptions[args[#k]] = args[#v];
        return Future<void>.value();
      // Rust's `handle_relay_id`: a `/r` suffix comes off.
      case #mainHandleRelayId:
        final id = args[#id] as String;
        return Future.value(
            id.endsWith('/r') ? id.substring(0, id.length - 2) : id);
      case #mainUriPrefixSync:
        return 'leapgate://';
      case #sessionGetImageQuality:
        return Future<String?>.value('balanced');
      case #mainGetPeerOptionSync:
        return '';
      case #mainIsInstalled:
        return installed;
    }
    return super.noSuchMethod(invocation);
  }
}

typedef AppFakes = ({AppFakeBind bind, FakeLeapgate lg, List<String> window});

/// Fresh fakes behind `bind`, `lgBind`, `appCore` and the window plugin, which records the
/// window calls by method name.
AppFakes installAppFakes() {
  final bind = AppFakeBind();
  final leapgate = FakeLeapgate();
  final window = <String>[];
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      const MethodChannel('texture_rgba_renderer'),
      (call) async => call.method == 'createTexture' ? -1 : null);
  messenger.setMockMethodCallHandler(const MethodChannel('window_manager'),
      (call) async {
    window.add(call.method);
    return switch (call.method) {
      'isMaximized' || 'isFullScreen' || 'isMinimized' => false,
      _ => null,
    };
  });
  platformFFI.setBindingForTesting(bind);
  setLgBindForTesting(leapgate);
  appCore = AppCore(window: FakeWindow());
  return (bind: bind, lg: leapgate, window: window);
}

/// The main window in Chinese at 1280×800.
Future<void> pumpMainWindow(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
    home: MainWindow(status: LocalStatusModel()),
  ));
}

/// A widget test of the main window: [body], then the pages and sessions closed and their
/// timers (toasts, retries, texture teardown) run out, so nothing leaks into the next test.
void testMainWindow(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      for (final d in appCore.sessions.devices) {
        await appCore.sessions.closeDevice(d);
      }
      await tester.pump(const Duration(seconds: 10));
    }
  });
}

/// A session event from Rust.
Future<void> emit(WidgetTester tester, AppFakes fakes, FFI s,
    Map<String, dynamic> evt) async {
  fakes.bind.streams[s.sessionId]!.add(EventToUI.event(jsonEncode(evt)));
  await tester.pump();
  await tester.pump();
}

/// A window event from the plugin (`blur`, `focus`, `close`, ...).
Future<void> windowEvent(WidgetTester tester, String name) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'window_manager',
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('onEvent', {'eventName': name})),
      (_) {});
  await tester.pump();
}

Map<String, dynamic> msgbox(String type, String title, String text,
        {bool hasRetry = false}) =>
    {
      'name': 'msgbox',
      'type': type,
      'title': title,
      'text': text,
      'link': '',
      'hasRetry': hasRetry ? 'true' : '',
    };

Map<String, dynamic> connectionReady({bool direct = false}) => {
      'name': 'connection_ready',
      'secure': 'true',
      'direct': direct ? 'true' : 'false',
      'stream_type': 'TCP',
    };

Map<String, dynamic> peerInfo(
        {String platform = 'Windows', bool sas = true, int displays = 1}) =>
    {
      'name': 'peer_info',
      'version': '1.4.6',
      'username': 'user',
      'hostname': 'host',
      'platform': platform,
      'sas_enabled': sas ? 'true' : 'false',
      'current_display': '0',
      'displays': jsonEncode([
        for (var i = 0; i < displays; i++)
          {
            'x': 1920 * i,
            'y': 0,
            'width': 1920,
            'height': 1080,
            'cursor_embedded': 0
          },
      ]),
      'features': jsonEncode({'privacy_mode': false}),
      'resolutions': jsonEncode([]),
      'platform_additions': '',
    };

/// The bridge calls named [name], their named arguments.
List<Map<Symbol, dynamic>> callsTo(AppFakes fakes, Symbol name) =>
    [for (final c in fakes.bind.callsTo(name)) c.namedArguments];
