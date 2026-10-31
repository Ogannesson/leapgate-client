import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/cm_core.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../theme/lg_theme.dart';
import '../theme/lg_tokens.dart';
import 'cm_page.dart';
import 'cm_window.dart';

/// The `--cm` process, as upstream's `runConnectionManagerScreen` (`flutter/lib/main.dart:285-302`)
/// without `hide_cm` (03 §5.2 M3): the platform interface starts as the connection manager,
/// which runs Rust's `cm_init`, then the CM's events are registered on the global stream.
Future<void> runConnectionManager() async {
  desktopType = DesktopType.cm;
  await windowManager.ensureInitialized();
  final window = LgCmWindow();
  appCore = AppCore(window: window);
  await platformFFI.init(kAppTypeConnectionManager);
  final model = ServerModel(window);
  final appearance = CmAppearance(appCore.options.local);
  registerCmEvents(model, appearance);
  runApp(CmApp(model: model, window: window, appearance: appearance));
  await window.start();
}

class CmApp extends StatelessWidget {
  const CmApp({
    super.key,
    required this.model,
    required this.window,
    required this.appearance,
  });

  final ServerModel model;
  final CmShellWindow window;
  final CmAppearance appearance;

  @override
  Widget build(BuildContext context) {
    // Same as the main window's app (main.dart `LeapgateApp`), with the main window's light /
    // dark mode and language.
    return ListenableBuilder(
      listenable: appearance,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
        darkTheme: buildLgTheme(
          brightness: Brightness.dark,
          mode: LgMode.compact,
        ),
        themeMode: appearance.themeMode,
        themeAnimationDuration: Duration.zero,
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appName,
        locale: appearance.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        // English first: any other system language falls back to it.
        supportedLocales: AppLocalizations.supportedLocales,
        home: CmPage(model: model, window: window),
      ),
    );
  }
}
