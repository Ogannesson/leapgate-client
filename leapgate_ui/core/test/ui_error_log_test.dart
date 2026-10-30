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

  test('errors that differ every time are capped per window', () {
    fakeAsync((async) {
      final lines = <String>[];
      final log = UiErrorLog(lines.add);
      for (var i = 0; i < 20; i++) {
        log.report('index $i out of range', null);
      }
      expect(lines, hasLength(UiErrorLog.maxLines));
      async.elapse(const Duration(seconds: 10));
      expect(lines.last,
          'leapgate ui: 15 more errors in the last 10 s were not written');
      log.report('index 20 out of range', null);
      expect(lines.last,
          'leapgate ui: uncaught error, session=: index 20 out of range');
    });
  });

  test('long error text and stack traces are cut', () {
    fakeAsync((async) {
      final lines = <String>[];
      UiErrorLog(lines.add)
          .report('x' * 5000, StackTrace.fromString('y' * 50000));
      final parts = lines.single.split('\n');
      expect(parts[0], endsWith(': ${'x' * UiErrorLog.maxText}…'));
      expect(parts[1], '${'y' * UiErrorLog.maxStack}…');
    });
  });
}
