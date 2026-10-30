import 'dart:async';

import 'package:flutter/foundation.dart';

// Feedback the models give without waiting for an answer (03 §3.3 item 4, 01 §4.5). Messages
// carry a key and arguments, not text: the copy lives in the app. Keys from upstream are
// upstream's translation keys (`translate(...)` arguments and Rust's message texts).

/// A message on one session's tab: a bar that does not interrupt (01 §3.2 block E). The app
/// hides one without actions after a few seconds; one with actions stays until handled or
/// closed.
class SessionNotice {
  SessionNotice(this.key,
      {this.args = const {}, this.tag, this.actions = const []});

  final String key;
  final Map<String, String> args;

  /// A later notice with the same tag replaces this one in place, and [SessionNotices.dismissTag]
  /// removes it; for a status that changes (elevation) and for Rust's `cancel_msgbox`.
  final String? tag;

  final List<NoticeAction> actions;
}

/// A button on a notice. [onPressed] dismisses the notice itself when it is done with it.
class NoticeAction {
  const NoticeAction(this.key, this.onPressed);

  final String key;
  final VoidCallback onPressed;
}

/// The notices of one session, oldest first. Unlike upstream's dialogs, a new one does not
/// clear the others (upstream `common.dart:1178`).
class SessionNotices extends ChangeNotifier {
  final _items = <SessionNotice>[];

  List<SessionNotice> get items => List.unmodifiable(_items);

  void add(SessionNotice notice) {
    final i = notice.tag == null
        ? -1
        : _items.indexWhere((n) => n.tag == notice.tag);
    if (i < 0) {
      _items.add(notice);
    } else {
      _items[i] = notice;
    }
    notifyListeners();
  }

  void dismiss(SessionNotice notice) {
    if (_items.remove(notice)) notifyListeners();
  }

  void dismissTag(String tag) {
    final before = _items.length;
    _items.removeWhere((n) => n.tag == tag);
    if (_items.length != before) notifyListeners();
  }
}

/// The one kind of short global message ("Copied"), replacing upstream's two
/// (`common.dart:1023` `showToast`, `models/model.dart:1032` `handleToast`). One shows at a
/// time; a new one replaces it.
class Toasts extends ChangeNotifier {
  ({String key, Map<String, String> args})? current;
  Timer? _timer;

  void show(String key,
      {Map<String, String> args = const {},
      Duration duration = const Duration(seconds: 3)}) {
    _timer?.cancel();
    current = (key: key, args: args);
    _timer = Timer(duration, () {
      current = null;
      notifyListeners();
    });
    notifyListeners();
  }
}
