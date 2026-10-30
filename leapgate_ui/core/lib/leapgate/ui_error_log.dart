import 'dart:async';

/// Writes uncaught UI errors into the log file (L1). Rust does not throttle `leapgate_log`
/// (LEAPGATE.md §10.4), so it is bounded here, per [window] starting with the first error:
/// - the same error text as the one written last is only counted, and the count goes out as one
///   line when a different error is written or the window ends;
/// - at most [maxLines] errors are written in full; the rest are counted and summed up in one line
///   when the window ends;
/// - error text and stack trace are cut to [maxText] and [maxStack] characters.
class UiErrorLog {
  UiErrorLog(this._write,
      {this.sessionId, this.window = const Duration(seconds: 10)});

  static const maxLines = 5;
  static const maxText = 1000;
  static const maxStack = 4000;

  final void Function(String line) _write;

  /// ID of the session the error happened in; empty while there are no sessions (M0).
  final String Function()? sessionId;
  final Duration window;

  String? _last;
  int _repeats = 0;
  int _written = 0;
  int _dropped = 0;
  Timer? _timer;

  void report(Object error, StackTrace? stack) {
    final text = _cut(error.toString(), maxText);
    if (_timer == null) {
      _timer = Timer(window, _endWindow);
    } else if (text == _last) {
      _repeats++;
      return;
    } else if (_written >= maxLines) {
      _dropped++;
      return;
    } else {
      _flushRepeats();
    }
    _last = text;
    _written++;
    final session = sessionId?.call() ?? '';
    _write('leapgate ui: uncaught error, session=$session: $text'
        '${stack == null ? '' : '\n${_cut(stack.toString(), maxStack)}'}');
  }

  void _flushRepeats() {
    if (_repeats > 0) {
      _write('leapgate ui: the same error repeated $_repeats more times: $_last');
      _repeats = 0;
    }
  }

  void _endWindow() {
    _timer = null;
    _flushRepeats();
    if (_dropped > 0) {
      _write('leapgate ui: $_dropped more errors in the last '
          '${window.inSeconds} s were not written');
      _dropped = 0;
    }
    _written = 0;
  }

  static String _cut(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}
