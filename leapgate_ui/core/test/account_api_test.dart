import 'dart:convert';

import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge_leapgate.dart' as lg;
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers the H1 exports with fixed JSON and keeps what was sent.
class _AccountExports implements lg.Leapgate {
  String local = '{}';
  String groupCache = '{}';
  final sent = <String>[];

  @override
  String leapgateAccountLocal({dynamic hint}) => local;

  @override
  Future<String> leapgateAccountLogin(
          {required String username,
          required String password,
          dynamic hint}) async =>
      '{"error":"wrong_credentials","text":"Wrong credentials"}';

  @override
  Future<String> leapgateAbCache({dynamic hint}) async =>
      '{"entries":[{"guid":"p1","name":"My address book","peers":[]}]}';

  @override
  Future<String> leapgateGroupCache({dynamic hint}) async => groupCache;

  @override
  Future<String> leapgateAbUpdatePeer(
      {required String guid, required String peer, dynamic hint}) async {
    sent.add(peer);
    return '{}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('RustAccountApi reads the exports as §10.11 shapes them', () async {
    final exports = _AccountExports();
    setLgBindForTesting(exports);
    const api = RustAccountApi();
    expect(api.localUser(), isNull);
    exports.local = '{"user":{"name":"alice","display_name":"","status":1}}';
    expect(api.localUser()!.displayNameOrName, 'alice');
    expect((await api.login('alice', 'x')).error!.kind,
        ApiErrorKind.wrongCredentials);
    expect((await api.abCache()).single['guid'], 'p1');
    expect(await api.groupCache(), isNull);
    exports.groupCache = '{"users":[],"peers":[]}';
    expect(await api.groupCache(), {'users': [], 'peers': []});
    expect((await api.updatePeer('g', '123', {'alias': 'a'})).ok, isTrue);
    expect(jsonDecode(exports.sent.single), {'alias': 'a', 'id': '123'});
  });

  test(
      'an export error becomes its kind and text; a kind not known here is a server error',
      () {
    ApiError? errorOf(String json) => parseApiResult(json, (m) => m).error;
    expect(
        errorOf('{"error":"wrong_credentials","text":"Wrong credentials"}'),
        isA<ApiError>()
            .having((e) => e.kind, 'kind', ApiErrorKind.wrongCredentials)
            .having((e) => e.text, 'text', 'Wrong credentials'));
    expect(errorOf('{"error":"verification_required"}')!.kind,
        ApiErrorKind.verificationRequired);
    expect(errorOf('{"error":"something_new","text":"x"}')!.kind,
        ApiErrorKind.server);
    expect(parseApiResult('{}', (m) => m).ok, isTrue);
  });

  test('an answer of the wrong shape is a server error, not a throw', () {
    final error = parseApiResult(
      '{"users":[{"name":5}],"peers":[]}',
      GroupData.fromJson,
    ).error;
    expect(error?.kind, ApiErrorKind.server);
    expect(error?.text, 'HTTP 200');
  });

  test(
      'a team device takes its owner and platform as upstream PeerPayload.toPeer',
      () {
    final data = parseApiResult(
      '{"users":[{"name":"alice","display_name":"Alice"}],'
      '"peers":[{"id":"123456789","user_name":"alice","note":"desk",'
      '"info":{"username":"al","os":"Windows / 11","device_name":"PC"}}]}',
      GroupData.fromJson,
    ).value;
    expect(data.users.single.displayNameOrName, 'Alice');
    final peer = data.peers.single;
    expect(peer.loginName, 'alice');
    expect(peer.platform, kPeerPlatformWindows);
    expect(peer.hostname, 'PC');
    expect(peer.note, 'desk');
  });
}
