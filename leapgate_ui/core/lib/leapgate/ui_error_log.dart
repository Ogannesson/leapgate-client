import 'dart:async';

/// Writes uncaught UI errors into the log file (L1). Rust does not throttle `leapgate_log`
/// (LEAPGATE.md §10.4), so repeats are collapsed here: the same error text arriving again within
/// [window] of the line that was written is only counted, and the count goes out as one line when
/// the window ends or a different error arrives.
class UiErrorLog {
  UiErrorLog(this._write,
      {this.sessionId, this.window = const Duration(seconds: 10)});

  final void Function(String line) _write;

  /// ID of the session the error happened in; empty while there are no sessions (M0).
  final String Function()? sessionId;
  final Duration window;

  String? _last;
  int _repeats = 0;
  Timer? _timer;

  void report(Object error, StackTrace? stack) {
    final text = error.toString();
    if (text == _last && _timer != null) {
      _repeats++;
      return;
    }
    _flush();
    _last = text;
    final session = sessionId?.call() ?? '';
    _write('leapgate ui: uncaught error, session=$session: $text'
        '${stack == null ? '' : '\n$stack'}');
    _timer = Timer(window, _flush);
  }

  void _flush() {
    _timer?.cancel();
    _timer = null;
    if (_repeats > 0) {
      _write('leapgate ui: the same error repeated $_repeats more times: $_last');
      _repeats = 0;
    }
  }
}
