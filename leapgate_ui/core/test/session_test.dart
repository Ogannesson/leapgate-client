import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/notices.dart';
import 'package:flutter_hbb/leapgate/prompts.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('session events', () {
    test('go to the handler registered for their name', () async {
      final fakes = installFakes();
      final s = appCore.sessions.open('100200300', ConnType.defaultConn);
      final got = <Map<String, dynamic>>[];
      s.events.on('test_handled', got.add);

      fakes.bind.streams[s.sessionId]!
          .add(EventToUI.event(jsonEncode({'name': 'test_handled', 'x': '1'})));
      await settle();

      expect(got, [
        {'name': 'test_handled', 'x': '1'}
      ]);
      expect(fakes.lg.logged, isEmpty);
    });

    test('nothing is dispatched after Rust closes the session', () async {
      final fakes = installFakes();
      final s = appCore.sessions.open('100200300', ConnType.defaultConn);
      final got = <Map<String, dynamic>>[];
      s.events.on('test_after_close', got.add);

      final stream = fakes.bind.streams[s.sessionId]!;
      stream.add(const EventToUI.event('close'));
      stream.add(EventToUI.event(jsonEncode({'name': 'test_after_close'})));
      await settle();

      expect(s.closed, true);
      expect(got, isEmpty);
    });

    test('a name nobody handles goes into the log once per run', () async {
      final fakes = installFakes();
      final a = appCore.sessions.open('100200300', ConnType.defaultConn);
      final b = appCore.sessions.open('400500600', ConnType.defaultConn);

      for (final s in [a, b, a]) {
        fakes.bind.streams[s.sessionId]!.add(EventToUI.event(
            jsonEncode({'name': 'test_unhandled', 'secret': 'not logged'})));
      }
      fakes.bind.streams[a.sessionId]!
          .add(EventToUI.event(jsonEncode({'name': 'test_unhandled_2'})));
      await settle();

      expect(fakes.lg.logged, [
        'leapgate ui: session event not handled: test_unhandled',
        'leapgate ui: session event not handled: test_unhandled_2',
      ]);
    });
  });

  group('session notices', () {
    test('a later notice does not clear the earlier ones', () {
      final notices = SessionNotices();
      final first = SessionNotice('Take screenshot',
          actions: [NoticeAction('Save as', () {})]);
      notices.add(first);
      notices.add(SessionNotice('privacy_mode_impl_mag_tip'));

      expect(notices.items.map((n) => n.key),
          ['Take screenshot', 'privacy_mode_impl_mag_tip']);
      expect(notices.items.first, same(first));
    });

    test('a notice with the tag of an open one replaces it in place', () {
      final notices = SessionNotices();
      notices.add(SessionNotice('Waiting', tag: 'elevation'));
      notices.add(SessionNotice('Remote reboot'));
      notices.add(SessionNotice('Elevation successful', tag: 'elevation'));

      expect(notices.items.map((n) => n.key),
          ['Elevation successful', 'Remote reboot']);

      notices.dismissTag('elevation');
      expect(notices.items.map((n) => n.key), ['Remote reboot']);
    });

    test('belong to their session', () {
      installFakes();
      final desktop = appCore.sessions.open('100200300', ConnType.defaultConn);
      final files = appCore.sessions.open('100200300', ConnType.fileTransfer);

      desktop.notices.add(SessionNotice('Remote reboot'));

      expect(files.notices.items, isEmpty);
    });
  });

  test('one toast at a time, gone after its duration', () {
    fakeAsync((async) {
      final toasts = Toasts();
      toasts.show('Copied');
      toasts.show('Failed', duration: const Duration(seconds: 2));
      expect(toasts.current?.key, 'Failed');

      async.elapse(const Duration(seconds: 1));
      expect(toasts.current?.key, 'Failed');
      async.elapse(const Duration(seconds: 1));
      expect(toasts.current, null);
    });
  });

  test('a session asks over its own tab', () async {
    installFakes();
    final prompter =
        FakePrompter((choice: OverwriteChoice.skip, forAll: true));
    appCore.prompter = prompter;
    final files = appCore.sessions.open('100200300', ConnType.fileTransfer);

    final answer = await files
        .ask(const OverwritePrompt(path: 'C:\\a.txt', isIdentical: false));

    expect(answer, (choice: OverwriteChoice.skip, forAll: true));
    expect(prompter.asked.single.$2, same(files));
  });
}
