import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/remote_block.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// The permission inputs and the time Rust last saw remote input.
class _Bind implements RustdeskImpl {
  final options = <String, String>{kOptionAccessMode: 'view'};
  String controlPermission = '';
  double mouseTime = 0;

  @override
  Future<String> mainGetCommon({required String key, dynamic hint}) async =>
      key == 'is-remote-modify-enabled-by-control-permissions'
          ? controlPermission
          : '';

  @override
  Future<String> mainGetOption({required String key, dynamic hint}) async =>
      options[key] ?? '';

  @override
  Future<void> mainCheckMouseTime({dynamic hint}) async {}

  @override
  Future<double> mainGetMouseTime({dynamic hint}) async => mouseTime;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('blockedForRemote (upstream common.dart canBeBlocked)', () {
    bool blocked(String control, String access, [String allow = '']) =>
        blockedForRemote(
            controlPermission: control,
            accessMode: access,
            allowRemoteConfig: allow);

    test('the control permission wins', () {
      expect(blocked('true', 'view'), isFalse);
      expect(blocked('false', 'full'), isTrue);
    });

    test('otherwise by access mode and "allow remote configuration"', () {
      expect(blocked('', 'full'), isFalse);
      expect(blocked('', 'view'), isTrue);
      expect(blocked('', 'custom'), isTrue);
      expect(blocked('', 'custom', 'Y'), isFalse);
      expect(blocked('', ''), isTrue);
    });
  });

  group('RemoteBlock', () {
    late _Bind bind;
    setUp(() {
      bind = _Bind();
      platformFFI.setBindingForTesting(bind);
    });

    test('blocks when remote input came within 120 ms of entering', () {
      fakeAsync((async) {
        final block = RemoteBlock();
        bind.mouseTime = clock.now().millisecondsSinceEpoch.toDouble();
        block.check();
        async.elapse(const Duration(milliseconds: 119));
        expect(block.blocked, isFalse);
        async.elapse(const Duration(milliseconds: 2));
        expect(block.blocked, isTrue);
        block.leave();
        expect(block.blocked, isFalse);
      });
    });

    test('local input does not block', () {
      fakeAsync((async) {
        final block = RemoteBlock();
        bind.mouseTime = clock.now().millisecondsSinceEpoch.toDouble() - 5000;
        block.check();
        async.elapse(const Duration(milliseconds: 200));
        expect(block.blocked, isFalse);
      });
    });

    test('never blocks when the remote user may use the page', () {
      fakeAsync((async) {
        bind.options[kOptionAccessMode] = 'full';
        final block = RemoteBlock();
        bind.mouseTime = clock.now().millisecondsSinceEpoch.toDouble();
        block.check();
        async.elapse(const Duration(milliseconds: 200));
        expect(block.blocked, isFalse);
      });
    });
  });
}
