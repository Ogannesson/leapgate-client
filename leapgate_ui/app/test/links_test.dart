import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart' show ConnType;
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/shell/links.dart';
import 'package:leapgate_ui/shell/navigation.dart';

import 'session_fakes.dart';

// `--connect` and `leapgate://` links, parsed as upstream `common.dart:2256-2523`. IDs and
// passwords here are made up.

class _Navigation implements MainNavigation {
  final connected = <String>[];

  @override
  void connect(String id,
      {String password = '',
      bool isSharedPassword = false,
      bool forceRelay = false,
      String switchUuid = ''}) =>
      connected.add('$id|$password|$forceRelay|$switchUuid');

  @override
  void showHome({bool focusConnectBox = false, String? connectBoxText}) {}

  @override
  void showSettings(SettingsSectionId section, {String? item}) {}

  final fileTransfers = <String>[];

  @override
  void openFileTransfer(String id,
          {String password = '',
          bool isSharedPassword = false,
          bool forceRelay = false}) =>
      fileTransfers.add('$id|$password|$forceRelay');

  final views = <String>[];

  @override
  void openView(String id, ConnType kind,
          {bool terminalAdmin = false,
          String password = '',
          bool isSharedPassword = false,
          bool forceRelay = false}) =>
      views.add('$id|${kind.name}|$terminalAdmin|$password|$forceRelay');
}

void main() {
  late _Navigation navigation;

  setUp(() {
    installAppFakes();
    mainNavigation = navigation = _Navigation();
  });

  test('a link as the Rust core hands it over (core_main.rs)', () {
    expect(
        linkToArgs(Uri.parse(
            'leapgate://connect/100200300?password=pw-1&relay=true')),
        ['--connect', '100200300', '--password', 'pw-1', '--relay']);
    expect(handleLink(Uri.parse('leapgate://connect/100200300?password=pw-1&relay=true')),
        true);
    expect(navigation.connected, ['100200300|pw-1|true|']);
  });

  test('leapgate://<id> forms, with /r and a key', () {
    expect(linkToArgs(Uri.parse('leapgate://100200300')), ['--connect', '100200300']);
    expect(linkToArgs(Uri.parse('leapgate://100200300/r')),
        ['--connect', '100200300/r']);
    expect(linkToArgs(Uri.parse('leapgate://connection/new/100200300?key=abc')),
        ['--connect', '100200300?key=abc']);
    // A bare link only brings the window up.
    expect(linkToArgs(Uri.parse('leapgate://')), isEmpty);
  });

  test('the launch command line, with --connect or a link first', () {
    expect(
        handleLaunchArgs(
            ['--connect', '100200300', '--password', 'pw-1'], 'leapgate://'),
        true);
    expect(handleLaunchArgs(['leapgate://400500600/r'], 'leapgate://'), true);
    expect(handleLaunchArgs(const [], 'leapgate://'), false);
    expect(navigation.connected, ['100200300|pw-1|false|', '400500600/r||false|']);
  });

  test('a file transfer opens its view, with the password and the relay', () {
    expect(
        handleLaunchArgs(
            ['--file-transfer', '100200300', '--password', 'pw-1'], 'leapgate://'),
        true);
    expect(
        handleLink(Uri.parse('leapgate://file-transfer/400500600?relay=true')),
        true);
    expect(navigation.fileTransfers, ['100200300|pw-1|false', '400500600||true']);
    expect(navigation.connected, isEmpty);
  });

  test('the last kind given counts', () {
    expect(
        handleLaunchArgs(['--file-transfer', '100200300', '--connect', '400500600'],
            'leapgate://'),
        true);
    expect(navigation.connected, ['400500600||false|']);
    expect(navigation.fileTransfers, isEmpty);
  });

  test('a kind without an ID opens nothing and shows no toast', () {
    expect(handleLaunchArgs(['--terminal'], 'leapgate://'), false);
    expect(appCore.toasts.current, isNull);
    expect(navigation.views, isEmpty);
  });

  test('the TCP tunnel and RDP open nothing and say so in a toast', () {
    for (final (kind, toast) in [
      ('port-forward', 'linkUnsupportedPortForward'),
      ('rdp', 'linkUnsupportedRdp'),
    ]) {
      expect(handleLink(Uri.parse('leapgate://$kind/100200300')), false);
      expect(appCore.toasts.current?.key, toast);
    }
    expect(navigation.connected, isEmpty);
    expect(navigation.fileTransfers, isEmpty);
    expect(navigation.views, isEmpty);
  });

  test('the terminals and the camera open their views with the password and the relay '
      '(13 §2.1.1, §3.1.1)', () {
    expect(handleLink(Uri.parse('leapgate://terminal/100200300')), true);
    expect(
        handleLink(Uri.parse(
            'leapgate://terminal-admin/400500600?password=pw-1&relay=true')),
        true);
    expect(
        handleLaunchArgs(['--view-camera', '700800900', '--password', 'pw-2'],
            'leapgate://'),
        true);
    expect(navigation.views, [
      '100200300|terminal|false||false',
      '400500600|terminal|true|pw-1|true',
      '700800900|viewCamera|false|pw-2|false',
    ]);
    expect(appCore.toasts.current, isNull);
  });

  test('the third round\'s kinds take the ID, the password and the relay (LEAPGATE.md §10.18)',
      () {
    expect(
        connectLinkOf(linkToArgs(Uri.parse(
            'leapgate://terminal-admin/100200300?password=pw-1&relay=true'))!),
        (
          id: '100200300',
          password: 'pw-1',
          switchUuid: '',
          forceRelay: true,
          kind: LinkKind.terminalAdmin,
        ));
    for (final (option, kind) in [
      ('--terminal', LinkKind.terminal),
      ('--view-camera', LinkKind.camera),
      ('--port-forward', LinkKind.tcpTunnel),
      ('--rdp', LinkKind.rdp),
    ]) {
      expect(connectLinkOf([option, '400500600', '--password', 'pw-2']),
          (
            id: '400500600',
            password: 'pw-2',
            switchUuid: '',
            forceRelay: false,
            kind: kind,
          ));
    }
  });

  test('config and password links open nothing, and the log keeps only scheme and host', () {
    final fakes = installAppFakes();
    expect(handleLink(Uri.parse('leapgate://password')), false);
    expect(handleLink(Uri.parse('leapgate://password/secret-1')), false);
    expect(handleLink(Uri.parse('leapgate://config/abc')), false);
    expect(navigation.connected, isEmpty);
    expect(fakes.lg.logged.join('\n'), isNot(contains('secret-1')));
  });
}
