import 'dart:io';

import 'package:win32/win32.dart';

/// Keeps this device's screen on while a session tab is open, as upstream's remote pages do
/// with `WakelockManager` (`flutter/lib/common.dart:2747`), and lets it sleep again when the
/// last one closes. The state belongs to the calling thread, the UI thread here, which lives as
/// long as the app.
void keepDisplayOn(bool on) {
  if (!Platform.isWindows) return;
  SetThreadExecutionState(
      on ? ES_CONTINUOUS | ES_DISPLAY_REQUIRED : ES_CONTINUOUS);
}
