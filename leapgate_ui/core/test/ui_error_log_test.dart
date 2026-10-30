import 'package:fake_async/fake_async.dart';
import 'package:flutter_hbb/leapgate/ui_error_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repeats within the window are counted, then written as one line', () {
    fakeAsync((async) {
      final lines = <String>[];
      final log = UiErrorLog(lines.add);
      for (var i = 0; i < 5; i++) {
        log.report(StateError('boom'), null);
        async.elapse(const Duration(seconds: 1));
      }
      expect(lines, ['leapgate ui: uncaught error, session=: Bad state: boom']);
      async.elapse(const Duration(seconds: 10));
      expect(lines, [
        'leapgate ui: uncaught error, session=: Bad state: boom',
        'leapgate ui: the same error repeated 4 more times: Bad state: boom',
      ]);
      // After the window the error is written in full again.
      log.report(StateError('boom'), null);
      expect(lines, hasLength(3));
    });
  });

  test('a different error ends the run and is written at once', () {
    fakeAsync((async) {
      final lines = <String>[];
      final log = UiErrorLog(lines.add, sessionId: () => 's1');
      log.report('a', StackTrace.fromString('#0 f'));
      log.report('a', null);
      log.report('b', null);
      expect(lines, [
        'leapgate ui: uncaught error, session=s1: a\n#0 f',
        'leapgate ui: the same error repeated 1 more times: a',
        'leapgate ui: uncaught error, session=s1: b',
      ]);
      async.elapse(const Duration(seconds: 10));
      expect(lines, hasLength(3));
    });
  });
}
