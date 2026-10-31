import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/latency.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/leapgate/session_requests.dart';
import 'package:flutter_hbb/leapgate/session_route.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// [FakeBind] plus what chat, screenshots, print jobs and LocalConfig call.
class _Bind extends FakeBind {
  final local = <String, String>{};
  var screenshotAnswer = '';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      case #sessionSendChat:
      case #sessionPrinterResponse:
      case #sessionSwitchSides:
      case #sessionTakeScreenshot:
        calls.add(invocation);
        return Future<void>.value();
      case #sessionHandleScreenshot:
        calls.add(invocation);
        return Future.value(screenshotAnswer);
      case #mainGetLocalOption:
        return local[args[#key]] ?? '';
      case #mainSetLocalOption:
        local[args[#key]] = args[#value];
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

({_Bind bind, FFI s}) _session() {
  installFakes();
  final bind = _Bind();
  platformFFI.setBindingForTesting(bind);
  final s = appCore.sessions.open('100200300', ConnType.defaultConn);
  return (bind: bind, s: s);
}

Future<void> _emit(_Bind bind, FFI s, Map<String, dynamic> evt) async {
  bind.streams[s.sessionId]!.add(EventToUI.event(jsonEncode(evt)));
  await settle();
}

void main() {
  group('latency', () {
    test('lowest, average and highest since the session started', () {
      final stats = LatencyStats();
      for (final ms in [40, 20, 60]) {
        stats.onQualityStatus({'delay': '$ms'});
      }
      // A status without a delay (speed and fps only) does not count.
      stats.onQualityStatus({'delay': '', 'speed': '1.2kB/s'});

      expect(stats.current, 60);
      expect(stats.min, 20);
      expect(stats.average, 40);
      expect(stats.max, 60);
    });

    test('a point every 2 s over the last 60 s; the statistics keep everything',
        () {
      fakeAsync((async) {
        final stats = LatencyStats();
        // Rust reports about once a second.
        for (var i = 0; i < 90; i++) {
          stats.add(i < 30 ? 100 : 10);
          async.elapse(const Duration(seconds: 1));
        }

        final points = stats.points;
        expect(points.length, 30);
        expect(points.map((p) => p.ms).toSet(), {10});
        expect(clock.now().difference(points.first.at),
            lessThanOrEqualTo(LatencyStats.window));
        expect(stats.max, 100);
      });
    });

    test('a session counts the delays of its quality status', () async {
      final (:bind, :s) = _session();
      await _emit(bind, s, {'name': 'update_quality_status', 'delay': '45'});
      await _emit(bind, s, {'name': 'update_quality_status', 'delay': '41'});

      expect(s.latency.current, 41);
      expect(s.latency.min, 41);
      expect(s.latency.max, 45);
    });
  });

  group('chat', () {
    test('messages are kept in order; sending trims and skips blank text',
        () async {
      final (:bind, :s) = _session();
      await _emit(bind, s, {'name': 'chat_client_mode', 'text': '你好'});
      expect(s.chatModel.send('  好的  '), true);
      expect(s.chatModel.send('   '), false);

      expect(s.chatModel.messages.map((m) => (m.isOut, m.text)),
          [(false, '你好'), (true, '好的')]);
      expect(bind.callsTo(#sessionSendChat).single.namedArguments[#text], '好的');
    });

    test('a message opens the panel; it is unread only while the tab is hidden',
        () async {
      final (:bind, :s) = _session();
      await _emit(bind, s, {'name': 'chat_client_mode', 'text': 'a'});
      expect(s.chatModel.open, true);
      expect(s.chatModel.unread, 0);

      s.setVisible(false);
      await _emit(bind, s, {'name': 'chat_client_mode', 'text': 'b'});
      await _emit(bind, s, {'name': 'chat_client_mode', 'text': 'c'});
      expect(s.chatModel.unread, 2);

      s.setVisible(true);
      s.chatModel.markRead();
      expect(s.chatModel.unread, 0);
    });

    test('voice call states follow Rust', () async {
      final (:bind, :s) = _session();
      await _emit(bind, s, {'name': 'on_voice_call_waiting'});
      expect(s.chatModel.voiceCallStatus, VoiceCallStatus.waitingForResponse);
      await _emit(bind, s, {'name': 'on_voice_call_started'});
      expect(s.chatModel.voiceCallStatus, VoiceCallStatus.connected);
      await _emit(bind, s, {'name': 'on_voice_call_closed', 'reason': ''});
      expect(s.chatModel.voiceCallStatus, VoiceCallStatus.notStarted);
    });
  });

  group('notices with buttons', () {
    test('a screenshot asks until answered; closing it drops the image',
        () async {
      final (:bind, :s) = _session();
      s.requests.takeScreenshot();
      expect(s.requests.screenshotPending.value, true);

      await _emit(bind, s, {'name': 'screenshot', 'msg': ''});
      expect(s.requests.screenshotPending.value, false);
      expect(s.notices.items.single.tag, kNoticeTagScreenshot);

      await s.requests.discardScreenshot();
      expect(s.notices.items, isEmpty);
      expect(
          bind.callsTo(#sessionHandleScreenshot).single.namedArguments[#action],
          '2');
    });

    test('saving a screenshot that fails tells why', () async {
      final (:bind, :s) = _session();
      await _emit(bind, s, {'name': 'screenshot', 'msg': ''});
      bind.screenshotAnswer = 'Access denied';

      await s.requests.saveScreenshot(r'C:\a.png');

      expect(
          bind.callsTo(#sessionHandleScreenshot).single.namedArguments[#action],
          r'0:C:\a.png');
      expect(s.notices.items.single.key, 'Access denied');
      expect(s.notices.items.single.tag, kNoticeTagScreenshotFailed);
    });

    test(
        'a print job remembered with the default printer prints by itself next time',
        () async {
      final (:bind, :s) = _session();
      await _emit(
          bind, s, {'name': 'printer_request', 'id': 7, 'path': 'job.xps'});
      final notice = s.notices.items.single;

      await s.requests.answerPrintJob(notice, remember: true);

      final res = bind.callsTo(#sessionPrinterResponse).single.namedArguments;
      expect((res[#id], res[#path], res[#printerName]), (7, 'job.xps', ''));
      expect(bind.local[kKeyPrinterAllowAutoPrint], 'Y');
      expect(bind.local[kKeyPrinterIncomingJobAction], '');
      expect(s.notices.items, isEmpty);
    });

    test('"不打印" remembered dismisses the next jobs without asking', () async {
      final (:bind, :s) = _session();
      await _emit(
          bind, s, {'name': 'printer_request', 'id': 8, 'path': 'job.xps'});

      await s.requests
          .answerPrintJob(s.notices.items.single, print: false, remember: true);

      expect(bind.callsTo(#sessionPrinterResponse), isEmpty);
      expect(bind.local[kKeyPrinterIncomingJobAction], 'dismiss');
    });

    test('a permission taken away during the session gets a notice', () async {
      final (:bind, :s) = _session();
      await _emit(bind, s,
          {'name': 'permission', 'keyboard': 'true', 'clipboard': 'true'});
      expect(s.notices.items, isEmpty);

      await _emit(bind, s, {'name': 'permission', 'clipboard': 'false'});
      expect(s.notices.items.single.args['permission'], 'clipboard');

      await _emit(bind, s, {'name': 'permission', 'clipboard': 'true'});
      expect(s.notices.items, isEmpty);
    });

    test('a recording started by itself gets a notice that goes with it',
        () async {
      final (:bind, :s) = _session();
      bind.local[kOptionAllowAutoRecordOutgoing] = 'Y';

      await _emit(bind, s, {'name': 'record_status', 'start': 'true'});
      expect(s.notices.items.single.tag, kNoticeTagAutoRecord);

      await _emit(bind, s, {'name': 'record_status', 'start': 'false'});
      expect(s.notices.items, isEmpty);
    });

    test('switching back ends the session', () async {
      final (:bind, :s) = _session();
      await _emit(bind, s, {'name': 'switch_back', 'peer_id': '100200300'});

      expect(bind.callsTo(#sessionSwitchSides), hasLength(1));
      expect(appCore.sessions.devices, isEmpty);
    });
  });

  group('connection route', () {
    test('Q3 answers the path, the transport and the relay', () {
      final r = SessionRoute.parse(
          '{"path":"relay","transport":"tcp","relay":"relay-1.example.com"}');
      expect((r.path, r.transport, r.relay, r.refused),
          ('relay', 'tcp', 'relay-1.example.com', null));
    });

    test('{} says nothing', () {
      final r = SessionRoute.parse('{}');
      expect(
          (r.path, r.transport, r.relay, r.refused), (null, null, null, null));
    });

    test('a refusal comes from the same export', () {
      expect(SessionRoute.parse('{"refused":"Banned"}').refused, 'Banned');
    });
  });
}
