import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/cm_chat.dart';
import 'package:flutter_hbb/leapgate/cm_core.dart';
import 'package:flutter_hbb/leapgate/ui_mode.dart';
import 'package:flutter_hbb/models/cm_file_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../main.dart' show LeapgateApp;
import 'cm_page.dart';
import 'cm_window.dart';

/// The `--cm` process, as upstream's `runConnectionManagerScreen` (`flutter/lib/main.dart:285-302`)
/// without `hide_cm` (03 §5.2 M3): the platform interface starts as the connection manager,
/// which runs Rust's `cm_init`, then the CM's events are registered on the global stream.
/// The theme, the language (02 §1.5.1) and the interface mode (S7) follow the main window's.
Future<void> runConnectionManager() async {
  desktopType = DesktopType.cm;
  await windowManager.ensureInitialized();
  final window = LgCmWindow();
  appCore = AppCore(window: window);
  await platformFFI.init(kAppTypeConnectionManager);
  final model = ServerModel(window);
  final chat = CmChatModel(model);
  final files = CmFileModel(model);
  registerCmEvents(model, chat, files);
  final local = appCore.options.local;
  final detailMode = ValueNotifier(isDetailMode(local));
  listenToMainWindow(model, detailMode);
  // Upstream `main.dart` `_registerEventHandler`: the theme comes with the event; Rust has stored
  // the language in this process's LocalConfig before it sends `language`.
  final theme = ValueNotifier(local.get(kCommConfKeyTheme));
  final language = ValueNotifier(local.get(kCommConfKeyLang));
  appCore.events
    ..on('theme', (evt) => theme.value = evt['dark'] as String? ?? '')
    ..on('language', (_) => language.value = local.get(kCommConfKeyLang));
  runApp(
    LeapgateApp(
      detailMode: detailMode,
      theme: theme,
      language: language,
      home: CmPage(model: model, chat: chat, files: files, window: window),
    ),
  );
  await window.start();
}
