import 'package:flutter_hbb/generated_bridge_leapgate.dart' as lg;
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLeapgate implements lg.Leapgate {
  final logged = <(int, String)>[];

  @override
  void leapgateLog({required int level, required String msg, dynamic hint}) =>
      logged.add((level, msg));

  @override
  String leapgateVersion({dynamic hint}) => '9.9.9';

  @override
  FlutterRustBridgeTaskConstMeta get kLeapgateLogConstMeta =>
      throw UnimplementedError();

  @override
  FlutterRustBridgeTaskConstMeta get kLeapgateVersionConstMeta =>
      throw UnimplementedError();
}

void main() {
  test('an injected binding replaces the dll', () {
    final fake = _FakeLeapgate();
    setLgBindForTesting(fake);
    lgBind.leapgateLog(level: 1, msg: 'x');
    expect(lgBind.leapgateVersion(), '9.9.9');
    expect(fake.logged, [(1, 'x')]);
  });
}
