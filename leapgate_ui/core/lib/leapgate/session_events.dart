import 'dart:async';

import 'bridge.dart';

typedef SessionEventHandler = FutureOr<void> Function(Map<String, dynamic> evt);

/// Events from Rust, dispatched by `name` through a table (03 §3.3 item 8), replacing
/// upstream's if/else (`models/model.dart:331-482`). There are two streams: each session's own
/// (one table per session object) and the global one (`startGlobalEventStream`, one table on
/// [AppCore]), which carries the connection manager's, the address book's and the URL scheme's
/// events. Each model that handles events registers its handlers on the table of its stream.
class SessionEvents {
  SessionEvents({this.stream = 'session'});

  /// Names the stream in the log.
  final String stream;

  final _handlers = <String, SessionEventHandler>{};

  void on(String name, SessionEventHandler handler) {
    assert(!_handlers.containsKey(name), 'two handlers for $stream event $name');
    _handlers[name] = handler;
  }

  Future<void> dispatch(Map<String, dynamic> evt) async {
    final name = '${evt['name']}';
    final handler = _handlers[name];
    if (handler == null) {
      _logUnhandled(stream, name);
      return;
    }
    await handler(evt);
  }
}

// Upstream's last else only `debugPrint`s, so an event that a merge from upstream adds and
// nothing here handles goes unnoticed; this puts each such name into the log file once per run
// and stream. Only the name: events can carry passwords and file paths.
final _unhandled = <String>{};

void _logUnhandled(String stream, String name) {
  if (_unhandled.add('$stream $name')) {
    lgBind.leapgateLog(
        level: 2, msg: 'leapgate ui: $stream event not handled: $name');
  }
}
