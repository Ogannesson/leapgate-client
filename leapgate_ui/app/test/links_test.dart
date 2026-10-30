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

  test('other kinds are left for their blocks', () {
    expect(handleLaunchArgs(['--file-transfer', '100200300'], 'leapgate://'), false);
    expect(navigation.connected, isEmpty);
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
