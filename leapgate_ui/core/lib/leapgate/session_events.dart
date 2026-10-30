import 'dart:async';

import 'bridge.dart';

typedef SessionEventHandler = FutureOr<void> Function(Map<String, dynamic> evt);

/// One session's events from Rust, dispatched by `name` through a table (03 §3.3 item 8),
/// replacing upstream's if/else (`models/model.dart:331-482`). Each model that handles events
/// registers its handlers on its session's table.
class SessionEvents {
  final _handlers = <String, SessionEventHandler>{};

  void on(String name, SessionEventHandler handler) {
    assert(!_handlers.containsKey(name), 'two handlers for session event $name');
    _handlers[name] = handler;
  }

  Future<void> dispatch(Map<String, dynamic> evt) async {
    final name = '${evt['name']}';
    final handler = _handlers[name];
    if (handler == null) {
      _logUnhandled(name);
      return;
    }
    await handler(evt);
  }
}

// Upstream's last else only `debugPrint`s, so an event that a merge from upstream adds and
// nothing here handles goes unnoticed; this puts each such name into the log file once per run.
// Only the name: events can carry passwords and file paths.
final _unhandled = <String>{};

void _logUnhandled(String name) {
  if (_unhandled.add(name)) {
    lgBind.leapgateLog(
        level: 2, msg: 'leapgate ui: session event not handled: $name');
  }
}
