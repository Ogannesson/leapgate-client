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
/// Light / dark and the language follow the system, as the main window's do until the settings
/// page (M6) stores a choice; the interface mode follows the main window's (S7).
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
  final detailMode = ValueNotifier(isDetailMode(appCore.options.local));
  listenToMainWindow(model, detailMode);
  runApp(
    LeapgateApp(
      detailMode: detailMode,
      home: CmPage(model: model, chat: chat, files: files, window: window),
    ),
  );
  await window.start();
}
