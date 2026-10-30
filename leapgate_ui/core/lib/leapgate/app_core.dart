import '../models/platform_model.dart';
import 'app_window.dart';
import 'notices.dart';
import 'options.dart';
import 'prompts.dart';
import 'session_events.dart';
import 'session_registry.dart';

/// What exists once per process (03 §3.3 item 2). Upstream built the global models inside
/// every session object (`models/model.dart:4068-4097`), timers included; here the app holds
/// them. The service, account and address book models join it with M3 and M4.
class AppCore {
  /// Made before `platformFFI.init` starts the global event stream, so none of its events is
  /// missed.
  AppCore({required this.window, bool singleSession = false})
      : sessions = SessionRegistry(singleSession: singleSession) {
    // What `PlatformFFI.tryHandle` does not take (`models/native_model.dart:274-277`).
    platformFFI.setEventCallback(events.dispatch);
  }

  final AppWindow window;
  final SessionRegistry sessions;
  final toasts = Toasts();
  final options = OptionsModel();

  /// The global event stream's table. The connection manager (M3) and the address book (M4)
  /// register their events here, not on a session's.
  final events = SessionEvents(stream: 'global');

  /// Set by the app once it can show dialogs (the session pages, M2a).
  late Prompter prompter;
}

/// Set once by the app's `main`; tests set their own.
late AppCore appCore;
