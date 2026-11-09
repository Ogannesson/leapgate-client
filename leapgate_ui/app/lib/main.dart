import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/options.dart';
import 'package:flutter_hbb/leapgate/file_transfer/file_transfer_api.dart';
import 'package:flutter_hbb/leapgate/settings/appearance.dart';
import 'package:flutter_hbb/leapgate/ui_error_log.dart';
import 'package:flutter_hbb/leapgate/ui_mode.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:uni_links/uni_links.dart';
import 'package:window_manager/window_manager.dart';

import 'cm/cm_main.dart';
import 'l10n/app_localizations.dart';
import 'shell/app_window.dart';
import 'shell/links.dart';
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
    await runConnectionManager();
  } else if (args.contains('--install')) {
    // Not an entry: the install page is a dialog on the home tab (R3-Q21, R3-Q22), so a
    // process started with --install (or as ...install.exe) only says so and exits.
    lgBind.leapgateLog(
        level: 2,
        msg: 'leapgate ui: --install is not supported, '
            'install from the home page of the portable version');
    exit(0);
  } else {
    desktopType = DesktopType.main;
    await windowManager.ensureInitialized();
    // Closing goes through the main window's close flow (01 §2.1), as upstream's main.dart:112.
    await windowManager.setPreventClose(true);
    appCore = AppCore(window: const LgAppWindow());
    await platformFFI.init(kAppTypeMain);
    // M7b's handling in Rust, on before any transfer starts (LEAPGATE.md §10.17).
    fileTransferApi.turnOnEvents();
    // Starts syncing options and the connection status with the service.
    await bind.mainCheckConnectStatus();
    // The stored sign-in, then the address book and the team devices (`LEAPGATE.md` §10.11).
    appCore.account.start();
    final version = lgBind.leapgateVersion();
    lgBind.leapgateLog(level: 3, msg: 'leapgate ui: version $version');
    runApp(LeapgateApp(
        home: MainWindow(status: LocalStatusModel()..start()),
        local: appCore.options.local));
    // A launch that found no main window keeps its `--connect` or link on its own command
    // line (M0 acceptance, LEAPGATE.md §10.5). Both need the navigation the main window sets
    // in its first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenLinks();
      handleLaunchArgs(args, bind.mainUriPrefixSync());
    });
    // The language shown, for the texts the service writes (S11).
    unawaited(syncUiLang(appCore.options.local, appCore.options.config,
        PlatformDispatcher.instance.locale));
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
/// WM_USER + 2).
void _listenLinks() {
  uriLinkStream.listen((uri) {
    if (uri == null) return;
    // The path and the query may carry a password, so only the scheme and host are logged.
    lgBind.leapgateLog(
        level: 3, msg: 'leapgate ui: link received ${uri.scheme}://${uri.host}');
    handleLink(uri);
  });
}

class LeapgateApp extends StatelessWidget {
  const LeapgateApp(
      {super.key,
      required this.home,
      this.local,
      this.detailMode,
      this.theme,
      this.language});

  final Widget home;

  /// LocalConfig, for the interface mode (01 §2.3), the theme and the language (02 §1.5.1); the
  /// settings page and the home page's "View" menu write them through the same scope, so a
  /// change applies at once. Without it, or the three listenables below, the app is in the
  /// simple mode and follows the system.
  final OptionScope? local;

  /// The connection manager's interface mode, which follows the main window's (S7).
  final ValueListenable<bool>? detailMode;

  /// The connection manager's theme and language values, which follow the main window's
  /// (upstream `main.dart` `_registerEventHandler`).
  final ValueListenable<String>? theme;
  final ValueListenable<String>? language;

  @override
  Widget build(BuildContext context) {
    final local = this.local;
    if (local != null) {
      return ListenableBuilder(
        listenable: Listenable.merge([
          local.listenable(kOptionLeapgateUiMode),
          local.listenable(kCommConfKeyTheme),
          local.listenable(kCommConfKeyLang),
        ]),
        builder: (context, _) => _app(isDetailMode(local),
            local.get(kCommConfKeyTheme), local.get(kCommConfKeyLang)),
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([detailMode, theme, language]),
      builder: (context, _) => _app(detailMode?.value ?? false,
          theme?.value ?? '', language?.value ?? ''),
    );
  }

  Widget _app(bool detail, String theme, String lang) {
    final mode = detail ? LgMode.detail : LgMode.compact;
    final choice = uiLangChoice(lang);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildLgTheme(brightness: Brightness.light, mode: mode),
      darkTheme: buildLgTheme(brightness: Brightness.dark, mode: mode),
      themeMode: themeModeOf(theme),
      // The tokens switch mode halfway through a theme animation; switch at once instead.
      themeAnimationDuration: Duration.zero,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appName,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: choice.isEmpty ? null : localeOfUiLang(choice),
      // Following the system: Chinese when its first language is, any other falls back to
      // English (02 §1.5.1), the language `leapgate-ui-lang` is given.
      localeListResolutionCallback: (locales, _) => localeOfUiLang(resolveUiLang(
          '',
          locales == null || locales.isEmpty
              ? const Locale('en')
              : locales.first)),
      home: home,
    );
  }
}
