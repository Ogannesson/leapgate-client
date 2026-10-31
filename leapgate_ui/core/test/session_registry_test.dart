import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

// Device IDs here are made up.
void main() {
  test('opening a device opens a tab and starts its session', () {
    final fakes = installFakes();
    final registry = appCore.sessions;

    final s = registry.open('100200300', ConnType.defaultConn, forceRelay: true);

    expect(registry.devices, ['100200300']);
    expect(registry.sessionsOf('100200300'), [s]);
    final add = fakes.bind.callsTo(#sessionAddSync).single.namedArguments;
    expect(add[#sessionId], s.sessionId);
    expect(add[#id], '100200300');
    expect(add[#isFileTransfer], false);
    expect(add[#forceRelay], true);
    expect(add[#connToken], null);
    expect(fakes.bind.callsTo(#sessionStart).single.namedArguments[#sessionId],
        s.sessionId);
  });

  test('the password, a shared password and switch sides reach Rust (--connect --password)',
      () {
    final fakes = installFakes();
    final registry = appCore.sessions;

    registry.open('100200300', ConnType.defaultConn,
        password: 'pw-1', isSharedPassword: true, switchUuid: 'uuid-1');

    final add = fakes.bind.callsTo(#sessionAddSync).single.namedArguments;
    expect(add[#password], 'pw-1');
    expect(add[#isSharedPassword], true);
    expect(add[#switchUuid], 'uuid-1');
  });

  test('without them, they go as empty as upstream sends them', () {
    final fakes = installFakes();

    appCore.sessions.open('100200300', ConnType.defaultConn);

    final add = fakes.bind.callsTo(#sessionAddSync).single.namedArguments;
    expect(add[#password], '');
    expect(add[#isSharedPassword], false);
    expect(add[#switchUuid], '');
  });

  test('another view of an open device joins its tab with its connection token '
      '(upstream toolbar.dart:580-610)', () {
    final fakes = installFakes();
    final registry = appCore.sessions;
    final desktop = registry.open('100200300', ConnType.defaultConn);
    fakes.bind.tokens[desktop.sessionId] = 'token-1';

    final files = registry.open('100200300', ConnType.fileTransfer);

    expect(registry.devices, ['100200300']);
    expect(registry.sessionsOf('100200300'), [desktop, files]);
    final add = fakes.bind.callsTo(#sessionAddSync).last.namedArguments;
    expect(add[#isFileTransfer], true);
    expect(add[#connToken], 'token-1');
  });

  test('a view that is already open is returned, not opened again', () {
    final fakes = installFakes();
    final registry = appCore.sessions;
    final first = registry.open('100200300', ConnType.defaultConn);

    expect(registry.open('100200300', ConnType.defaultConn), same(first));
    expect(fakes.bind.callsTo(#sessionAddSync), hasLength(1));
  });

  test('closing views: the tab stays until its last view closes', () async {
    final fakes = installFakes();
    final registry = appCore.sessions;
    final desktop = registry.open('100200300', ConnType.defaultConn);
    final files = registry.open('100200300', ConnType.fileTransfer);
    final other = registry.open('400500600', ConnType.defaultConn);

    await registry.close(desktop);
    expect(registry.devices, ['100200300', '400500600']);
    expect(registry.sessionsOf('100200300'), [files]);
    expect(desktop.closed, true);

    await registry.close(files);
    expect(registry.devices, ['400500600']);

    await registry.closeDevice('400500600');
    expect(registry.devices, isEmpty);
    expect(other.closed, true);
    expect(
        fakes.bind
            .callsTo(#sessionClose)
            .map((c) => c.namedArguments[#sessionId]),
        [desktop.sessionId, files.sessionId, other.sessionId]);
  });

  test('closeDevice closes every view of the tab', () async {
    final fakes = installFakes();
    final registry = appCore.sessions;
    final desktop = registry.open('100200300', ConnType.defaultConn);
    final files = registry.open('100200300', ConnType.fileTransfer);

    await registry.closeDevice('100200300');

    expect(registry.devices, isEmpty);
    expect(fakes.bind.callsTo(#sessionClose).map((c) => c.namedArguments[#sessionId]),
        unorderedEquals([desktop.sessionId, files.sessionId]));
  });

  test('with one session at a time, opening another closes the open one', () async {
    final fakes = installFakes(singleSession: true);
    final registry = appCore.sessions;
    final first = registry.open('100200300', ConnType.defaultConn);

    final second = registry.open('400500600', ConnType.defaultConn);
    await settle();

    expect(registry.devices, ['400500600']);
    expect(registry.sessionsOf('400500600'), [second]);
    expect(first.closed, true);
    expect(fakes.bind.callsTo(#sessionClose).single.namedArguments[#sessionId],
        first.sessionId);
  });

  test('state upstream kept per device ID is per session', () async {
    installFakes();
    final registry = appCore.sessions;
    final desktop = registry.open('100200300', ConnType.defaultConn);
    final files = registry.open('100200300', ConnType.fileTransfer);

    desktop.currentDisplay.value = 2;
    desktop.privacyMode.value = 'privacy_mode_impl_mag';
    await registry.close(desktop);

    expect(files.currentDisplay.value, 0);
    expect(files.privacyMode.value, '');
  });
}
