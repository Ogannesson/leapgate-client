import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
