import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/app_window.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/settings/settings_api.dart';
import 'package:flutter_hbb/leapgate/settings/unlock.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/pages/home/home_page.dart';
import 'package:leapgate_ui/shell/navigation.dart';
import 'package:leapgate_ui/shell/tab_overlays.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';

import '../../core/test/fakes.dart' show FakeLeapgate;
import 'settings_fakes.dart';

export '../../core/test/fakes.dart' show FakeLeapgate;

/// Records the bridge calls the home page makes, and keeps the options it reads and writes the
/// way Rust does.
class FakeBind implements RustdeskImpl {
  final calls = <Invocation>[];

  /// LocalConfig, its Flutter table, and the remote devices' options.
  final local = <String, String>{};
  final flutter = <String, String>{};
  final peerOptions = <String, Map<String, String>>{};
  final favs = <String>[];
  bool installed = false;
  bool hasPassword = false;

  /// What saving the permanent password returns.
  bool passwordSaves = true;
  bool passwordSet = false;

  /// The remote user's access to the home page (upstream `canBeBlocked`) and the time Rust last
  /// saw remote input.
  String accessMode = 'full';
  DateTime lastRemoteInput = DateTime(2000);

  /// `#isDisableAccount`, `#isDisableAb`, `#isDisableGroupPanel` that answer true.
  final disabledOptions = <Symbol>{};

  /// Config, as `mainGetOptionSync` reads it; `mainSetOption` writes it ('' removes).
  final config = <String, String>{};

  /// The unlock PIN, whether UAC lets the user through, and what saving a PIN answers (M6a).
  String unlockPin = '';
  bool superUser = true;
  String setPinError = '';

  List<Invocation> callsTo(Symbol name) =>
      calls.where((c) => c.memberName == name).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      case #mainSetOption:
        final key = args[#key] as String;
        final value = args[#value] as String;
        value.isEmpty ? config.remove(key) : config[key] = value;
        return Future<void>.value();
      case #mainGetOptionSync:
        return config[args[#key]] ?? '';
      case #mainGetUnlockPin:
        return unlockPin;
      case #mainCheckSuperUserPermission:
        return Future.value(superUser);
      case #mainSetUnlockPin:
        if (setPinError.isEmpty) unlockPin = (args[#pin] as String).trim();
        return setPinError;
      case #mainSupportedPrivacyModeImpls:
        return '[]';
      // No proxy (the connection notes, M6-4).
      case #mainGetSocks:
        return Future.value(const <String>[]);
      case #mainLoadRecentPeers:
      case #mainLoadFavPeers:
      case #mainLoadLanPeers:
      case #mainDiscover:
      case #queryOnlines:
      case #mainRemovePeer:
      case #mainRemoveDiscovered:
      case #mainSetPeerAlias:
      case #mainForgetPassword:
      case #mainWol:
      case #mainCreateShortcut:
      case #mainUpdateTemporaryPassword:
      case #mainCheckMouseTime:
        return Future<void>.value();
      case #mainGetLocalOption:
        return local[args[#key]] ?? '';
      case #mainSetLocalOption:
        local[args[#key]] = args[#value];
        return Future<void>.value();
      case #getLocalFlutterOption:
        return flutter[args[#k]] ?? '';
      case #setLocalFlutterOption:
        flutter[args[#k]] = args[#v];
        return Future<void>.value();
      case #mainGetPeerOptionSync:
        return peerOptions[args[#id]]?[args[#key]] ?? '';
      case #mainSetPeerOption:
        (peerOptions[args[#id]] ??= {})[args[#key]] = args[#value];
        return Future<void>.value();
      case #mainIsOptionFixed:
        return false;
      case #mainIsInstalled:
        return installed;
      case #mainGetFav:
        return Future.value(favs.toList());
      case #mainStoreFav:
        favs
          ..clear()
          ..addAll(args[#favs]);
        return Future<void>.value();
      case #mainPeerHasPassword:
        return Future.value(hasPassword);
      case #mainGetCommon:
        return Future.value(
            args[#key] == 'local-permanent-password-set' && passwordSet
                ? 'true'
                : '');
      case #mainHasValid2FaSync:
        return false;
      // The built-in options of the account, address book and team devices (M4).
      case #isDisableAccount:
      case #isDisableAb:
      case #isDisableGroupPanel:
        return disabledOptions.contains(invocation.memberName);
      case #mainMaxEncryptLen:
        return 128;
      case #mainSetPermanentPasswordWithResult:
        return Future.value(passwordSaves);
      case #mainGetOption:
        return Future.value(
            args[#key] == 'access-mode' ? accessMode : config[args[#key]] ?? '');
      case #mainGetMouseTime:
        return Future.value(lastRemoteInput.millisecondsSinceEpoch.toDouble());
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

  final settings = <({SettingsSectionId section, String? item})>[];

  @override
  void showSettings(SettingsSectionId section, {String? item}) =>
      settings.add((section: section, item: item));
}

/// Fresh fakes behind `bind`, `appCore` and `mainNavigation` for one test.
({FakeBind bind, FakeLeapgate lg, FakeNavigation nav}) installHomeFakes() {
  final bind = FakeBind();
  platformFFI.setBindingForTesting(bind);
  final leapgate = FakeLeapgate();
  setLgBindForTesting(leapgate);
  appCore = AppCore(window: FakeWindow());
  // Config saves go through S9 (`LEAPGATE.md` §10.13); this one hands them to the fake bridge.
  settingsApi = FakeSettingsApi()..writeThrough = true;
  // The settings lock is one for the app; a test unlocking it leaves it to the next.
  addTearDown(settingsUnlock.lock);
  // Their event handlers are registered by name; the next test's AppCore needs the names free.
  addTearDown(appCore.recentPeers.dispose);
  addTearDown(appCore.favPeers.dispose);
  addTearDown(appCore.lanPeers.dispose);
  final nav = FakeNavigation();
  mainNavigation = nav;
  return (bind: bind, lg: leapgate, nav: nav);
}

/// Rust pushing the recent list.
Future<void> loadRecent(List<Map<String, String>> peers) =>
    loadCategory('load_recent_peers', peers);

/// Rust pushing a category's list (`load_recent_peers`, `load_fav_peers`, `load_lan_peers`).
Future<void> loadCategory(String event, List<Map<String, String>> peers) =>
    platformFFI.tryHandle({
      'name': event,
      'peers': peers.isEmpty ? '' : jsonEncode(peers),
    });

/// The home page in Chinese at [size], over a status model it returns. [overlays] gets the home
/// tab's dialogs, as the main window gives them.
Future<LocalStatusModel> pumpHome(
  WidgetTester tester, {
  String id = '',
  ServiceStatus status = ServiceStatus.connecting,
  Size size = const Size(1280, 760),
  TabOverlays? overlays,
  void Function(LocalStatusModel model)? setUp,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final model = LocalStatusModel()
    ..id = id
    ..status = status;
  setUp?.call(model);
  addTearDown(model.dispose);
  overlays ??= TabOverlays();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
                child: HomePage(status: model, overlays: overlays)),
            Positioned.fill(child: Overlay(key: overlays.keyOf(null))),
          ],
        ),
      ),
    ),
  );
  return model;
}

/// Takes the page down so its timers stop before the test ends.
Future<void> unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

/// Lets a toast's own timer run out ([unmount] does not stop it).
Future<void> toastGone(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 3));
