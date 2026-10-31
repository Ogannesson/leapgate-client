import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

// The copied models wired to a session object: the events reach them and they keep the state
// the pages read.

Map<String, dynamic> _display(double x, int width, int height) => {
      'x': x,
      'y': 0,
      'width': width,
      'height': height,
      'cursor_embedded': 0,
    };

String _peerInfo({int currentDisplay = 0}) => jsonEncode({
      'name': 'peer_info',
      'version': '1.4.6',
      'username': 'user',
      'hostname': 'host',
      'platform': 'Windows',
      'sas_enabled': 'false',
      'current_display': '$currentDisplay',
      'displays': jsonEncode([
        _display(0, 1920, 1080),
        _display(1920, 2560, 1440),
      ]),
      'features': jsonEncode({'privacy_mode': true}),
      'resolutions': jsonEncode([
        {'width': 1280, 'height': 720},
        {'width': 1920, 'height': 1080},
      ]),
      'platform_additions': '',
    });

void main() {
  test('peer info fills the peer, the displays and the current display', () async {
    final fakes = installFakes();
    final s = appCore.sessions.open('100200300', ConnType.defaultConn);

    fakes.bind.streams[s.sessionId]!.add(EventToUI.event(_peerInfo()));
    await settle();

    final pi = s.ffiModel.pi;
    expect(pi.isSet.value, true);
    expect(pi.platform, 'Windows');
    expect(pi.hostname, 'host');
    expect(pi.displays.map((d) => (d.x, d.width, d.height)),
        [(0.0, 1920, 1080), (1920.0, 2560, 1440)]);
    expect(pi.features.privacyMode, true);
    // Sorted largest first, as the toolbar lists them.
    expect(pi.resolutions.map((r) => r.width), [1920, 1280]);
    expect(pi.currentDisplay, 0);
    expect(s.currentDisplay.value, 0);
    expect(s.ffiModel.rect, const Rect.fromLTWH(0, 0, 1920, 1080));
    expect(s.ffiModel.waitForFirstImage.value, true);
  });

  test('switching to another display tells Rust and moves the session to it', () async {
    final fakes = installFakes();
    final s = appCore.sessions.open('100200300', ConnType.defaultConn);
    fakes.bind.streams[s.sessionId]!.add(EventToUI.event(_peerInfo()));
    await settle();

    openMonitorInTheSameTab(1, s, s.ffiModel.pi);
    await settle();

    final switched = fakes.bind.callsTo(#sessionSwitchDisplay).last;
    expect(switched.namedArguments[#value], Int32List.fromList([1]));
    expect(s.ffiModel.pi.currentDisplay, 1);
    expect(s.currentDisplay.value, 1);
    expect(s.ffiModel.lastUserDisplay, 1);
    expect(s.ffiModel.rect, const Rect.fromLTWH(1920, 0, 2560, 1440));
  });

  test('events of the copied models reach them', () async {
    final fakes = installFakes();
    final s = appCore.sessions.open('100200300', ConnType.defaultConn);
    final stream = fakes.bind.streams[s.sessionId]!;

    stream.add(EventToUI.event(jsonEncode({
      'name': 'update_quality_status',
      'speed': '1.2 MB/s',
      'fps': '',
    })));
    stream.add(EventToUI.event(
        jsonEncode({'name': 'record_status', 'start': 'true'})));
    stream.add(EventToUI.event(jsonEncode(
        {'name': 'update_block_input_state', 'input_state': 'on'})));
    await settle();

    expect(s.qualityMonitorModel.data.speed, '1.2 MB/s');
    expect(s.recordingModel.start, true);
    expect(s.ffiModel.inputBlocked, true);
    expect(s.blockInput.value, true);
    expect(fakes.lg.logged, isEmpty);
  });
}
