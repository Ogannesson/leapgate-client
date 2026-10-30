import 'app_window.dart';
import 'notices.dart';
import 'options.dart';
import 'prompts.dart';
import 'session_registry.dart';

/// What exists once per process (03 §3.3 item 2). Upstream built the global models inside
/// every session object (`models/model.dart:4068-4097`), timers included; here the app holds
/// them. The service, account and address book models join it with M3 and M4.
class AppCore {
  AppCore({required this.window, bool singleSession = false})
      : sessions = SessionRegistry(singleSession: singleSession);

  final AppWindow window;
  final SessionRegistry sessions;
  final toasts = Toasts();
  final options = OptionsModel();

  /// Set by the app once it can show dialogs (the session pages, M2a).
  late Prompter prompter;
}

/// Set once by the app's `main`; tests set their own.
late AppCore appCore;
