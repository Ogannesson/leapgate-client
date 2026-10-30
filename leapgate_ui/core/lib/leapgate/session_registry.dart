import 'dart:async';

import 'package:flutter/foundation.dart';

import 'session.dart';

/// Creates and closes the sessions; upstream's pages did that themselves
/// (`desktop/pages/remote_page.dart:151`, `:180`, `:690`). One tab per device, one session per
/// view in it (03 §3.3 item 1, 01 §2.1). Tabs are in the order they opened.
class SessionRegistry extends ChangeNotifier {
  /// [singleSession]: at most one session at a time, as on phones (01 §8 Q8); opening another
  /// closes the open one. The app asks the user first.
  SessionRegistry({this.singleSession = false});

  final bool singleSession;
  final _tabs = <String, List<FFI>>{};

  /// Device IDs of the open tabs.
  List<String> get devices => List.unmodifiable(_tabs.keys);

  /// The views open in the tab of device [id], in the order they opened.
  List<FFI> sessionsOf(String id) => List.unmodifiable(_tabs[id] ?? const []);

  /// Opens [view] of device [id], or returns it when it is already open. Another view of a
  /// device whose tab is open logs in with that tab's connection token, without the password
  /// (upstream `connectWithToken`, `common/widgets/toolbar.dart:580-610`).
  FFI open(String id, ConnType view, {bool forceRelay = false}) {
    final views = _tabs[id] ?? const <FFI>[];
    for (final s in views) {
      if (s.connType == view) return s;
    }
    final token = views.map((s) => s.connToken).nonNulls.firstOrNull;
    if (singleSession) {
      final open = _tabs.values.expand((v) => v).toList();
      _tabs.clear();
      for (final s in open) {
        unawaited(s.close());
      }
    }
    final session = FFI(id, view);
    (_tabs[id] ??= []).add(session);
    session.start(forceRelay: forceRelay, connToken: token);
    notifyListeners();
    return session;
  }

  /// Closes one view; the tab goes with its last view.
  Future<void> close(FFI session) async {
    final views = _tabs[session.id];
    if (views == null || !views.remove(session)) return;
    if (views.isEmpty) _tabs.remove(session.id);
    notifyListeners();
    await session.close();
  }

  /// Closes the tab of device [id] with all its views.
  Future<void> closeDevice(String id) async {
    final views = _tabs.remove(id);
    if (views == null) return;
    notifyListeners();
    await Future.wait(views.map((s) => s.close()));
  }
}
