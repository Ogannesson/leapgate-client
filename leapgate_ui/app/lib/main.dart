import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/ui_error_log.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:uni_links/uni_links.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'shell/app_window.dart';
import 'shell/main_window.dart';
import 'theme/lg_theme.dart';
import 'theme/lg_tokens.dart';

// Startup follows upstream's desktop paths (flutter/lib/main.dart `main`, `runMainApp`,
// `runConnectionManagerScreen`), keeping only what the main window needs to show this device's ID
// and service status.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  _logUncaughtErrors();

  if (args.isNotEmpty && args.first == '--cm') {
    // The connection manager is M3; until then the process only shows an empty window.
    desktopType = DesktopType.cm;
    await windowManager.ensureInitialized();
    runApp(const LeapgateApp(home: Scaffold()));
    windowManager.waitUntilReadyToShow(null, () => windowManager.show());
  } else if (args.contains('--install')) {
    // The install page is round 3.
    lgBind.leapgateLog(
        level: 2, msg: 'leapgate ui: --install is not supported yet');
    exit(0);
  } else {
    desktopType = DesktopType.main;
    await windowManager.ensureInitialized();
    appCore = AppCore(window: const LgAppWindow());
    await platformFFI.init(kAppTypeMain);
    // Starts syncing options and the connection status with the service.
    await bind.mainCheckConnectStatus();
    final version = lgBind.leapgateVersion();
    lgBind.leapgateLog(level: 3, msg: 'leapgate ui: version $version');
    _logLinks();
    runApp(LeapgateApp(home: MainWindow(status: LocalStatusModel()..start())));
    // The top bar is drawn by the app (docs/新界面/01-内容与逻辑说明.md §2.1). The runner already
    // sized and centered the window.
    windowManager.waitUntilReadyToShow(
        const WindowOptions(titleBarStyle: TitleBarStyle.hidden), () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}

/// L1: uncaught Dart errors go into the log file as well as to the default debug output.
void _logUncaughtErrors() {
  final log = UiErrorLog((line) => lgBind.leapgateLog(level: 1, msg: line));
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    log.report(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.report(error, stack);
    // Not handled: the engine still prints it.
    return false;
  };
}

/// Links and `--connect` that a later launch hands to this window (the Rust core sends them as
/// WM_USER + 2). Opening them comes with the session pages; for now the log shows they arrived.
void _logLinks() {
  uriLinkStream.listen((uri) {
    if (uri == null) return;
    // The query may carry a password (`--password`), so it stays out of the log.
    lgBind.leapgateLog(
        level: 3,
        msg: 'leapgate ui: link received ${uri.scheme}://${uri.host}${uri.path}');
  });
}

class LeapgateApp extends StatelessWidget {
  const LeapgateApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    // Light / dark follow the system and the mode is compact until the settings page (M6) stores
    // the user's choice.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
      darkTheme: buildLgTheme(brightness: Brightness.dark, mode: LgMode.compact),
      // The tokens switch mode halfway through a theme animation; switch at once instead.
      themeAnimationDuration: Duration.zero,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appName,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // English first: any other system language falls back to it.
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );
  }
}
