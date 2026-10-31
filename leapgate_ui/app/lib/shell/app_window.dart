import 'dart:ui';

import 'package:flutter_hbb/leapgate/app_window.dart';
import 'package:window_manager/window_manager.dart';

/// The main window for the models, through `window_manager`.
class LgAppWindow implements AppWindow {
  const LgAppWindow();

  // Physical pixels like upstream's `WindowController.getFrame`; without the flag the plugin
  // divides by the device pixel ratio.
  @override
  Future<Rect> getFrame() =>
      windowManager.getBounds(ignoreDevicePixelRatio: true);

  @override
  Future<void> setFullscreen(bool fullscreen) =>
      windowManager.setFullScreen(fullscreen);

  // Upstream `windowOnTop(null)` (flutter/lib/common.dart:733).
  @override
  Future<void> bringToFront() async {
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }
}
