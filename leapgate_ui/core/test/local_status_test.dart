import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// What Rust answers for this device: the ID, the server connection and the options.
class _StatusBind implements RustdeskImpl {
  final options = <String, String>{};
  String connectStatus = '{"status_num":1}';
  String error = '';

  @override
  Future<String> mainGetMyId({dynamic hint}) async => '135792468';

  @override
  Future<String> mainGetConnectStatus({dynamic hint}) async => connectStatus;

  @override
  Future<String> mainGetError({dynamic hint}) async => error;

  @override
  Future<String> mainGetTemporaryPassword({dynamic hint}) async => 'a1b2c3';

  @override
  Future<String> mainGetOption({required String key, dynamic hint}) async =>
      options[key] ?? '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('LocalStatusModel polling', () {
    late _StatusBind bind;
    setUp(() {
      bind = _StatusBind();
      platformFFI.setBindingForTesting(bind);
      setLgBindForTesting(FakeLeapgate());
    });

    Future<LocalStatusModel> poll() async {
      final model = LocalStatusModel()..start();
      await settle();
      model.dispose();
      return model;
    }

    test('reads the password, approval and verification settings', () async {
      bind.options
        ..[kOptionApproveMode] = 'password'
        ..[kOptionVerificationMethod] = kUseTemporaryPassword;
      final model = await poll();
      expect(model.id, '135792468');
      expect(model.status, ServiceStatus.ready);
      expect(model.oneTimePassword, 'a1b2c3');
      expect(model.approveMode, 'password');
      expect(model.verificationMethod, kUseTemporaryPassword);
      expect(model.passwordRow, PasswordRow.oneTime);
    });

    test('a stopped service wins over the server connection', () async {
      bind.options
        ..[kOptionStopService] = 'Y'
        ..[kOptionApproveMode] = 'click'
        ..[kOptionVerificationMethod] = kUsePermanentPassword;
      final model = await poll();
      expect(model.status, ServiceStatus.stopped);
      expect(model.approveMode, 'click');
      expect(model.verificationMethod, kUsePermanentPassword);
      expect(model.passwordRow, PasswordRow.unavailable);
    });

    test('the system error and the remote desktop sessions into this device',
        () async {
      var model = await poll();
      expect(model.systemError, isEmpty);
      expect(model.remoteSessions, 0);

      bind
        ..error = 'Failed to write the config file'
        ..connectStatus = '{"status_num":1,"video_conn_count":2}';
      model = await poll();
      expect(model.systemError, 'Failed to write the config file');
      expect(model.remoteSessions, 2);
    });
  });

  group('LocalStatusModel.passwordRow (01 P1 block A)', () {
    PasswordRow row(
            {ServiceStatus status = ServiceStatus.ready,
            String approve = '',
            String method = ''}) =>
        (LocalStatusModel()
              ..status = status
              ..approveMode = approve
              ..verificationMethod = method)
            .passwordRow;

    test('the five kinds', () {
      expect(row(method: kUseTemporaryPassword), PasswordRow.oneTime);
      expect(row(approve: 'password', method: kUseBothPasswords),
          PasswordRow.both);
      expect(row(method: kUsePermanentPassword), PasswordRow.permanent);
      expect(row(approve: 'click', method: kUseTemporaryPassword),
          PasswordRow.acceptOnly);
      expect(
          row(
              status: ServiceStatus.stopped,
              approve: 'click',
              method: kUsePermanentPassword),
          PasswordRow.unavailable);
    });

    test('an unset or unknown method counts as both, as upstream', () {
      expect(row(), PasswordRow.both);
      expect(row(method: 'something-else'), PasswordRow.both);
    });
  });
}
