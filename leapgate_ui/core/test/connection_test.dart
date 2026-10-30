import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

// Replays of session events against the connection state (03 §3.7 item 1): one test or more
// per behavior of 03 §3.4, named with the upstream place it keeps. Upstream lines are
// `flutter/lib/models/model.dart@bd9262397` unless named otherwise.

typedef _Fakes = ({FakeBind bind, FakeLeapgate lg});

const _id = '100200300';

Map<String, dynamic> _msgbox(String type, String title, String text,
        {bool hasRetry = false}) =>
    {
      'name': 'msgbox',
      'type': type,
      'title': title,
      'text': text,
      'link': '',
      'hasRetry': hasRetry ? 'true' : '',
    };

final _connectionReady = {
  'name': 'connection_ready',
  'secure': 'true',
  'direct': 'false',
  'stream_type': 'TCP',
};

final _peerInfo = {
  'name': 'peer_info',
  'version': '1.4.6',
  'username': 'user',
  'hostname': 'host',
  'platform': 'Windows',
  'sas_enabled': 'false',
  'current_display': '0',
  'displays': jsonEncode([
    {'x': 0, 'y': 0, 'width': 1920, 'height': 1080, 'cursor_embedded': 0},
  ]),
  'features': jsonEncode({'privacy_mode': false}),
  'resolutions': jsonEncode([]),
  'platform_additions': '',
};

final _waitingForImage =
    _msgbox('success', 'Successful', 'Connected, waiting for image...');

void _emit(FakeAsync async, _Fakes fakes, FFI s, Map<String, dynamic> evt) {
  fakes.bind.streams[s.sessionId]!.add(EventToUI.event(jsonEncode(evt)));
  async.flushMicrotasks();
}

void _frame(FakeAsync async, _Fakes fakes, FFI s) {
  fakes.bind.streams[s.sessionId]!.add(const EventToUI.texture(0, false));
  async.flushMicrotasks();
}

List<bool> _reconnects(_Fakes fakes) => [
      for (final c in fakes.bind.callsTo(#sessionReconnect))
        c.namedArguments[#forceRelay] as bool
    ];

/// A session connected and showing a frame.
FFI _connected(FakeAsync async, _Fakes fakes, {String id = _id}) {
  final s = appCore.sessions.open(id, ConnType.defaultConn);
  _emit(async, fakes, s, _connectionReady);
  _emit(async, fakes, s, _peerInfo);
  _emit(async, fakes, s, _waitingForImage);
  _frame(async, fakes, s);
  return s;
}

void main() {
  test(
      'connecting -> password -> wrong password -> password -> connected -> interrupted -> '
      'reconnect (03 §3.7 item 1)', () {
    fakeAsync((async) {
      final fakes = installFakes();
      fakes.bind.remember = true;
      fakes.lg.reasons['Do you want to enter again?'] = 'wrong_password';
      fakes.lg.reasons['Reset by the peer'] = 'reset_by_peer';
      final s = appCore.sessions.open(_id, ConnType.defaultConn);
      final c = s.connection;
      expect(c.stage, ConnStage.connecting);

      _emit(async, fakes, s, _connectionReady);
      expect((c.stage, c.secure, c.direct, c.streamType),
          (ConnStage.verifying, true, false, 'TCP'));

      _emit(
          async, fakes, s, _msgbox('input-password', 'Password Required', ''));
      expect((c.stage, c.input, c.reason),
          (ConnStage.verifying, ConnInput.password, null));
      expect(c.rememberPassword, true);

      // An empty password does nothing, as upstream's dialog.
      c.login(password: '', remember: true);
      expect(fakes.bind.callsTo(#sessionLogin), isEmpty);
      c.login(password: 'wrong', remember: true);
      expect(fakes.bind.callsTo(#sessionLogin).single.namedArguments,
          containsPair(#password, 'wrong'));
      expect((c.stage, c.input), (ConnStage.verifying, ConnInput.none));

      _emit(
          async,
          fakes,
          s,
          _msgbox('re-input-password', 'Wrong Password',
              'Do you want to enter again?'));
      expect((c.input, c.reason?.code), (ConnInput.password, 'wrong_password'));

      c.login(password: 'right', remember: false);
      _emit(async, fakes, s, _peerInfo);
      _emit(async, fakes, s, _waitingForImage);
      expect(c.stage, ConnStage.waitingForImage);
      _frame(async, fakes, s);
      expect(c.stage, ConnStage.connected);

      _emit(
          async,
          fakes,
          s,
          _msgbox('error', 'Connection Error', 'Reset by the peer',
              hasRetry: true));
      expect((c.stage, c.reason?.code, c.reason?.text, c.retryCountdown),
          (ConnStage.failed, 'reset_by_peer', 'Reset by the peer', 1));
      async.elapse(const Duration(seconds: 1));
      expect(_reconnects(fakes), [false]);
      expect((c.stage, c.retryCountdown), (ConnStage.connecting, null));
    });
  });

  test(
      'network errors retry after 1 s, doubling each time without a cap; a connection with '
      'displays starts again at 1 s (model.dart:123, :1093-1102, :1454)', () {
    fakeAsync((async) {
      final fakes = installFakes();
      final s = _connected(async, fakes);
      final c = s.connection;
      final timeout =
          _msgbox('error', 'Connection Error', 'Timeout', hasRetry: true);

      for (final (attempt, seconds) in [
        (1, 1),
        (2, 2),
        (3, 4),
        (4, 8),
        (5, 16),
        (6, 32),
        (7, 64)
      ]) {
        _emit(async, fakes, s, timeout);
        expect((c.retryAttempt, c.retryCountdown), (attempt, seconds));
        async.elapse(
            Duration(seconds: seconds) - const Duration(milliseconds: 1));
        expect(_reconnects(fakes).length, attempt - 1);
        async.elapse(const Duration(milliseconds: 1));
        expect(_reconnects(fakes).length, attempt);
      }

      _emit(async, fakes, s, _peerInfo);
      _emit(async, fakes, s, timeout);
      expect((c.retryAttempt, c.retryCountdown), (1, 1));
    });
  });

  test('the countdown ticks each second and "Retry" does not wait for it', () {
    fakeAsync((async) {
      final fakes = installFakes();
      final s = _connected(async, fakes);
      final c = s.connection;
      final timeout =
          _msgbox('error', 'Connection Error', 'Timeout', hasRetry: true);
      _emit(async, fakes, s, timeout);
      async.elapse(const Duration(seconds: 1));
      _emit(async, fakes, s, timeout);
      expect(c.retryCountdown, 2);
      async.elapse(const Duration(seconds: 1));
      expect(c.retryCountdown, 1);

      c.retry();
      async.elapse(const Duration(seconds: 10));
      expect(_reconnects(fakes), [false, false]);
    });
  });

  group('"Remote desktop is offline" (model.dart:1002-1030)', () {
    final offline =
        _msgbox('error', 'Connection Error', 'Remote desktop is offline');

    test('is not retried on the first connection', () {
      fakeAsync((async) {
        final fakes = installFakes();
        fakes.lg.reasons['Remote desktop is offline'] = 'peer_offline';
        final s = appCore.sessions.open(_id, ConnType.defaultConn);

        _emit(async, fakes, s, offline);
        async.elapse(const Duration(minutes: 1));

        expect((
          s.connection.stage,
          s.connection.reason?.code,
          s.connection.retryCountdown
        ), (
          ConnStage.failed,
          'peer_offline',
          null
        ));
        expect(_reconnects(fakes), isEmpty);
      });
    });

    test('is retried for 30 s once this session has connected', () {
      fakeAsync((async) {
        final fakes = installFakes();
        final s = _connected(async, fakes);

        // Offline at 0 s, then again after each retry: at 1, 3, 7, 15 and 31 s.
        for (final seconds in [1, 2, 4, 8, 16]) {
          _emit(async, fakes, s, offline);
          expect(s.connection.retryCountdown, seconds);
          async.elapse(Duration(seconds: seconds));
        }
        expect(_reconnects(fakes).length, 5);

        _emit(async, fakes, s, offline);
        async.elapse(const Duration(minutes: 1));
        expect(s.connection.retryCountdown, null);
        expect(_reconnects(fakes).length, 5);
      });
    });

    test(
        'the 30 s start again once a retry got displays (model.dart:1454-1456)',
        () {
      fakeAsync((async) {
        final fakes = installFakes();
        final s = _connected(async, fakes);
        _emit(async, fakes, s, offline);
        async.elapse(const Duration(seconds: 1));
        _emit(async, fakes, s, _peerInfo);

        async.elapse(const Duration(seconds: 40));
        _emit(async, fakes, s, offline);

        expect(s.connection.retryCountdown, 1);
      });
    });
  });

  test(
      'a restarting remote device reconnects silently, last frame dimmed (model.dart:929-948)',
      () {
    fakeAsync((async) {
      final fakes = installFakes();
      final s = _connected(async, fakes);
      final c = s.connection;
      final restarting = _msgbox('restarting', 'Restarting remote device',
          'Connection in progress. Please wait.');

      _emit(async, fakes, s, restarting);
      expect((c.stage, c.dimLastFrame), (ConnStage.restarting, true));
      expect(_reconnects(fakes), [false]);
      // More of them within the silent window do nothing more.
      _emit(async, fakes, s, restarting);
      expect(_reconnects(fakes), [false]);

      async.elapse(const Duration(seconds: 5));
      expect(_reconnects(fakes), [false, false]);
      expect(c.stage, ConnStage.restarting);

      _emit(
          async,
          fakes,
          s,
          _msgbox('restarting-show', 'Restarting remote device',
              'Connection in progress. Please wait.'));
      expect(_reconnects(fakes), [false, false, false]);
      expect(c.stage, ConnStage.restarting);

      _emit(async, fakes, s, restarting);
      _emit(async, fakes, s, _connectionReady);
      expect((c.stage, c.dimLastFrame), (ConnStage.verifying, false));
      // Connected again before the silent window ended: no further reconnect.
      async.elapse(const Duration(seconds: 10));
      expect(_reconnects(fakes).length, 4);
    });
  });

  test(
      'a silent peer reconnects as restarting only while it restarts (io_loop.rs:335, :361)',
      () {
    fakeAsync((async) {
      final fakes = installFakes();
      final s = _connected(async, fakes);

      _emit(
          async,
          fakes,
          s,
          _msgbox('restarting-show', 'Connecting...',
              'Connection in progress. Please wait.'));
      expect((s.connection.stage, s.connection.dimLastFrame),
          (ConnStage.connecting, false));

      final restarted = _connected(async, fakes, id: '400500600');
      _emit(
          async,
          fakes,
          restarted,
          _msgbox('restarting-show', 'Restarting remote device',
              'Connection in progress. Please wait.'));
      expect((restarted.connection.stage, restarted.connection.dimLastFrame),
          (ConnStage.restarting, true));
      expect(_reconnects(fakes), [false, false]);
    });
  });

  group(
      '1.5 s without a frame sends an empty OS password to wake a locked screen '
      '(model.dart:1201-1205)', () {
    void connect(FakeAsync async, _Fakes fakes, FFI s) {
      _emit(async, fakes, s, _connectionReady);
      _emit(async, fakes, s, _peerInfo);
      _emit(async, fakes, s, _waitingForImage);
    }

    List<String> wakes(_Fakes fakes) => [
          for (final c in fakes.bind.callsTo(#sessionInputOsPassword))
            c.namedArguments[#value] as String
        ];

    test('when no frame came', () {
      fakeAsync((async) {
        final fakes = installFakes();
        final s = appCore.sessions.open(_id, ConnType.defaultConn);
        connect(async, fakes, s);
        expect(s.connection.stage, ConnStage.waitingForImage);
        expect(fakes.bind.callsTo(#sessionOnWaitingForImageDialogShow),
            hasLength(1));

        async.elapse(const Duration(milliseconds: 1499));
        expect(wakes(fakes), isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(wakes(fakes), ['']);
      });
    });

    test('not when a frame came first', () {
      fakeAsync((async) {
        final fakes = installFakes();
        final s = appCore.sessions.open(_id, ConnType.defaultConn);
        connect(async, fakes, s);
        async.elapse(const Duration(seconds: 1));
        _frame(async, fakes, s);
        async.elapse(const Duration(seconds: 5));

        expect(s.connection.stage, ConnStage.connected);
        expect(wakes(fakes), isEmpty);
      });
    });

    test('not after a switch of the render (model.dart:724-731)', () {
      fakeAsync((async) {
        final fakes = installFakes();
        final s = _connected(async, fakes);

        _emit(async, fakes, s, {'name': 'use_texture_render', 'v': 'Y'});
        expect(s.connection.stage, ConnStage.waitingForImage);
        async.elapse(const Duration(seconds: 5));

        expect(wakes(fakes), isEmpty);
      });
    });
  });

  test(
      'a render switch reaches every session but changes only a connected one: a password '
      'prompt and a retry countdown stay (model.dart:724-731, flutter_ffi.rs:1259-1273)',
      () {
    fakeAsync((async) {
      final fakes = installFakes();
      final asking = appCore.sessions.open(_id, ConnType.defaultConn);
      _emit(async, fakes, asking,
          _msgbox('input-password', 'Password Required', ''));
      final failed = _connected(async, fakes, id: '400500600');
      _emit(async, fakes, failed,
          _msgbox('error', 'Connection Error', 'Timeout', hasRetry: true));
      final connected = _connected(async, fakes, id: '700800900');

      for (final s in [asking, failed, connected]) {
        _emit(async, fakes, s, {'name': 'use_texture_render', 'v': 'Y'});
      }

      expect((asking.connection.stage, asking.connection.input),
          (ConnStage.verifying, ConnInput.password));
      expect((failed.connection.stage, failed.connection.retryCountdown),
          (ConnStage.failed, 1));
      expect(connected.connection.stage, ConnStage.waitingForImage);
      async.elapse(const Duration(seconds: 1));
      expect(_reconnects(fakes), [false]);
    });
  });

  test('a first frame ends the silent restart window (model.dart:4330)', () {
    fakeAsync((async) {
      final fakes = installFakes();
      final s = _connected(async, fakes);
      // A render switch makes the next frame a first frame again.
      _emit(async, fakes, s, {'name': 'use_texture_render', 'v': 'Y'});
      _emit(
          async,
          fakes,
          s,
          _msgbox('restarting', 'Restarting remote device',
              'Connection in progress. Please wait.'));
      _frame(async, fakes, s);

      async.elapse(const Duration(seconds: 10));

      expect(_reconnects(fakes), [false]);
      expect(s.connection.stage, ConnStage.connected);
    });
  });

  test(
      'no displays ends the connection (model.dart:1713, ui_session_interface.rs:1845)',
      () {
    fakeAsync((async) {
      final fakes = installFakes();
      fakes.lg.reasons['No displays'] = 'no_displays';
      final s = _connected(async, fakes);

      _emit(async, fakes, s, {'name': 'sync_peer_info', 'displays': '[]'});

      expect((s.connection.stage, s.connection.reason?.code),
          (ConnStage.failed, 'no_displays'));
    });
  });

  test(
      'the password is trimmed, and sent once (common/widgets/dialog.dart:1000-1002)',
      () {
    fakeAsync((async) {
      final fakes = installFakes();
      final s = appCore.sessions.open(_id, ConnType.defaultConn);
      _emit(
          async, fakes, s, _msgbox('input-password', 'Password Required', ''));

      s.connection.login(password: '   ');
      expect(fakes.bind.callsTo(#sessionLogin), isEmpty);
      s.connection.login(password: ' secret ');
      // A second Enter while verifying.
      s.connection.login(password: ' secret ');

      expect(fakes.bind.callsTo(#sessionLogin).single.namedArguments,
          containsPair(#password, 'secret'));
    });
  });

  group(
      'an insecure connection waits for the user (io_loop.rs:220-222, common.dart:1186-1219)',
      () {
    final insecure = _msgbox('insecure-connection-nocancel-hasclose',
        'Insecure Connection', 'conn-e2ee-unavailable-tip');

    List<String> answers(_Fakes fakes) => [
          for (final c in fakes.bind.callsTo(#sessionSetCommon))
            '${c.namedArguments[#key]}=${c.namedArguments[#value]}'
        ];

    test('continue', () {
      fakeAsync((async) {
        final fakes = installFakes();
        final s = appCore.sessions.open(_id, ConnType.defaultConn);
        _emit(async, fakes, s, _connectionReady);
        _emit(async, fakes, s, insecure);
        expect(s.connection.stage, ConnStage.insecure);

        s.connection.continueInsecure();

        expect(answers(fakes), ['continue-insecure-connection=Y']);
        expect(s.connection.stage, ConnStage.verifying);
      });
    });

    test('disconnect, also the default action, closes the view', () {
      fakeAsync((async) {
        final fakes = installFakes();
        final s = appCore.sessions.open(_id, ConnType.defaultConn);
        _emit(async, fakes, s, _connectionReady);
        _emit(async, fakes, s, insecure);

        s.connection.rejectInsecure();
        async.flushMicrotasks();

        expect(answers(fakes), ['continue-insecure-connection=N']);
        expect(fakes.bind.callsTo(#sessionClose), hasLength(1));
        expect(appCore.sessions.devices, isEmpty);
      });
    });
  });

  test(
      '"Use relay" reconnects with force relay, which Rust saves for the device '
      '(ui_session_interface.rs:1329-1336)', () {
    fakeAsync((async) {
      final fakes = installFakes();
      fakes.lg.reasons['Connection reset by peer (os error 10054)'] =
          'direct_reset';
      final s = appCore.sessions.open(_id, ConnType.defaultConn);

      _emit(
          async,
          fakes,
          s,
          _msgbox('relay-hint2', 'Connection Error',
              'Connection reset by peer (os error 10054)'));
      expect((
        s.connection.stage,
        s.connection.reason?.code,
        s.connection.retryCountdown
      ), (
        ConnStage.failed,
        'direct_reset',
        null
      ));

      s.connection.useRelay();

      expect(_reconnects(fakes), [true]);
      expect(s.connection.stage, ConnStage.connecting);
    });
  });

  test('whether to retry by itself is hasRetry from Rust (client.rs:5192-5210)',
      () {
    fakeAsync((async) {
      final fakes = installFakes();
      final s = _connected(async, fakes);

      // Rust's rule would retry this text; the event says no, and no is what happens.
      _emit(async, fakes, s, _msgbox('error', 'Connection Error', 'Timeout'));
      async.elapse(const Duration(minutes: 1));
      expect(s.connection.retryCountdown, null);
      expect(_reconnects(fakes), isEmpty);

      _emit(
          async,
          fakes,
          s,
          _msgbox('error', 'Login Error', 'Connection not allowed',
              hasRetry: true));
      expect(s.connection.retryCountdown, 1);
    });
  });

  test(
      '2FA: asked for the first time or the code was wrong (model.dart:919, C4)',
      () {
    fakeAsync((async) {
      final fakes = installFakes();
      fakes.lg.reasons[''] = 'other';
      final s = appCore.sessions.open(_id, ConnType.defaultConn);
      final c = s.connection;

      _emit(async, fakes, s, _msgbox('input-2fa', '2FA Required', ''));
      expect((c.input, c.reason), (ConnInput.twoFactor, null));

      c.submit2fa(' 123456 ', trustThisDevice: true);
      expect(
          fakes.bind.callsTo(#sessionSend2Fa).single.namedArguments,
          allOf(containsPair(#code, '123456'),
              containsPair(#trustThisDevice, true)));
      expect((c.stage, c.input), (ConnStage.verifying, ConnInput.none));

      fakes.lg.reasons[''] = 'wrong_2fa';
      _emit(async, fakes, s, _msgbox('input-2fa', 'Wrong 2FA Code', ''));
      expect((c.input, c.reason?.code), (ConnInput.twoFactor, 'wrong_2fa'));
    });
  });

  test('waiting for the remote side to accept, then choosing a Windows session',
      () {
    fakeAsync((async) {
      final fakes = installFakes();
      final s = appCore.sessions.open(_id, ConnType.defaultConn);
      final c = s.connection;

      _emit(
          async,
          fakes,
          s,
          _msgbox('wait-remote-accept-nook', 'Prompt',
              'Please wait for the remote side to accept your session request...'));
      expect((c.stage, c.input), (ConnStage.verifying, ConnInput.remoteAccept));

      _emit(async, fakes, s, {
        'name': 'set_multiple_windows_session',
        'windows_sessions': jsonEncode([
          {'sid': '1', 'name': 'Alice'},
          {'sid': '2', 'name': 'Bob'},
        ]),
      });
      expect(c.input, ConnInput.windowsSession);
      expect(c.windowsSessions,
          [(sid: '1', name: 'Alice'), (sid: '2', name: 'Bob')]);

      c.selectWindowsSession('2');
      expect(
          fakes.bind
              .callsTo(#sessionSendSelectedSessionId)
              .single
              .namedArguments,
          containsPair(#sid, '2'));
    });
  });

  test(
      'message boxes that only inform become session notices and leave the connection alone',
      () {
    fakeAsync((async) {
      final fakes = installFakes();
      final s = _connected(async, fakes);

      _emit(async, fakes, s,
          _msgbox('custom-nocancel', 'Privacy mode', 'Enter privacy mode'));
      _emit(async, fakes, s,
          _msgbox('custom-error', 'Block user input', 'Failed'));
      _emit(async, fakes, s,
          _msgbox('nook-nocancel-hasclose', 'Virtual display', 'Done'));
      _emit(
          async,
          fakes,
          s,
          _msgbox(
              'on-uac', 'Prompt', 'Please wait for confirmation of UAC...'));

      expect(s.connection.stage, ConnStage.connected);
      expect(s.notices.items.map((n) => (n.key, n.args['title'], n.tag)), [
        (
          'Enter privacy mode',
          'Privacy mode',
          'custom-nocancel-Privacy mode-Enter privacy mode-'
        ),
        ('Failed', 'Block user input', 'custom-error-Block user input-Failed-'),
        (
          'Done',
          'Virtual display',
          'nook-nocancel-hasclose-Virtual display-Done-'
        ),
        ('Please wait for confirmation of UAC...', 'Prompt', 'on-uac'),
      ]);

      // Rust takes the UAC one back by its type.
      _emit(async, fakes, s, {'name': 'cancel_msgbox', 'tag': 'on-uac'});
      expect(s.notices.items.map((n) => n.tag), isNot(contains('on-uac')));
    });
  });

  test('"Cancel" closes the view', () {
    fakeAsync((async) {
      final fakes = installFakes();
      final s = appCore.sessions.open(_id, ConnType.defaultConn);
      _emit(
          async, fakes, s, _msgbox('input-password', 'Password Required', ''));

      s.connection.cancel();
      async.flushMicrotasks();

      expect(fakes.bind.callsTo(#sessionClose), hasLength(1));
      expect(appCore.sessions.devices, isEmpty);
    });
  });
}
