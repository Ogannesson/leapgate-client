import 'dart:ui';

/// The window operations the models need (03 §3.3 item 6). Upstream calls them on its own
/// window objects; here there is one main window, and the app implements this with
/// `window_manager` and hands it to [AppCore].
abstract interface class AppWindow {
  /// The window's outer frame in physical screen pixels, as upstream's
  /// `WindowController.getFrame` returns it on Windows. Upstream:
  /// `models/input_model.dart:1954` (`fillRemoteCoordsAndGetCurFrame`) and
  /// `models/relative_mouse_model.dart:779` (the cursor clip region of relative mouse mode).
  Future<Rect> getFrame();

  /// Upstream: `models/state_model.dart:109` (`StateGlobal.procFullscreenNative`).
  Future<void> setFullscreen(bool fullscreen);

  /// Restores the window if it is minimized, shows it and gives it focus, as upstream's
  /// `windowOnTop(null)` (`common.dart:733`) does for the main window. Upstream callers in the
  /// models: `models/model.dart:760` (`FfiModel.onUrlSchemeReceived`),
  /// `models/chat_model.dart:415`, `:434`.
  Future<void> bringToFront();
}
