import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/settings/settings_api.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'settings_fakes.dart';

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

  bool installed = true;
  bool lowerVersion = false;

  @override
  bool mainIsInstalled({dynamic hint}) => installed;

  @override
  bool mainIsInstalledLowerVersion({dynamic hint}) => lowerVersion;

  @override
  Future<String> mainGetOption({required String key, dynamic hint}) async =>
      options[key] ?? '';

  @override
  String mainGetOptionSync({required String key, dynamic hint}) =>
      options[key] ?? '';

  /// The proxy, user and password; empty when none is set.
  List<String> socks = const [];

  /// The service did not answer the proxy question.
  bool socksFails = false;

  @override
  Future<List<String>> mainGetSocks({dynamic hint}) async {
    if (socksFails) throw StateError('no service');
    return socks;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('LocalStatusModel polling', () {
    late _StatusBind bind;
    late FakeLeapgate lg;
    setUp(() {
      // `appCore.options` for the connection notes, then this test's answers.
      installFakes();
      settingsApi = FakeSettingsApi();
      bind = _StatusBind();
      platformFFI.setBindingForTesting(bind);
      lg = FakeLeapgate();
      setLgBindForTesting(lg);
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

    test('the system error and the sessions into this device (C1, 06 M3-1)',
        () async {
      var model = await poll();
      expect(model.systemError, isEmpty);
      expect(model.incoming, IncomingSessions.none);

      bind.error = 'Failed to write the config file';
      lg.incomingCounts =
          '{"remote":0,"file_transfer":1,"port_forward":0,"exit":2,"camera":0,"terminal":0}';
      model = await poll();
      expect(model.systemError, 'Failed to write the config file');
      expect(model.incoming, const IncomingSessions(3, controlled: false));

      lg.incomingCounts =
          '{"remote":0,"file_transfer":1,"port_forward":0,"exit":0,"camera":0,"terminal":1}';
      model = await poll();
      expect(model.incoming, const IncomingSessions(2, controlled: true));
    });

    test('the install card (01 P1 block B): portable, older installed, error first', () async {
      expect((await poll()).installCard, isNull);
      bind.lowerVersion = true;
      expect((await poll()).installCard, InstallCard.upgrade);
      bind.installed = false;
      expect((await poll()).installCard, InstallCard.install);
      bind.error = 'Failed to write the config file';
      expect((await poll()).installCard, isNull);
    });
  });

  group('LocalStatusModel.networkWarning (M6-4)', () {
    late _StatusBind bind;
    setUp(() {
      installFakes();
      settingsApi = FakeSettingsApi();
      bind = _StatusBind();
      platformFFI.setBindingForTesting(bind);
    });

    Future<NetworkWarning?> poll() async {
      final model = LocalStatusModel()..start();
      await settle();
      model.dispose();
      return model.networkWarning;
    }

    test('none, then the first that is on: proxy, WebSocket, UDP off', () async {
      expect(await poll(), isNull);
      bind.options[kOptionDisableUdp] = 'Y';
      expect(await poll(), NetworkWarning.udpDisabled);
      bind.options[kOptionAllowWebSocket] = 'Y';
      expect(await poll(), NetworkWarning.webSocket);
      bind.socks = const ['socks5://198.51.100.20:1080', '', ''];
      expect(await poll(), NetworkWarning.proxy);
    });

    test('a failed proxy question leaves the ID and the service line alone', () async {
      bind
        ..socksFails = true
        ..options[kOptionDisableUdp] = 'Y';
      final model = LocalStatusModel()..start();
      await settle();
      model.dispose();
      expect(model.id, '135792468');
      expect(model.status, ServiceStatus.ready);
      expect(model.networkWarning, isNull);
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

  group('LocalStatusModel.toggleService (02 §1.3.8)', () {
    late _ServiceBind bind;
    setUp(() {
      bind = _ServiceBind();
      platformFFI.setBindingForTesting(bind);
    });

    test('portable: the option alone, and it is done', () async {
      final model = LocalStatusModel();
      expect(await model.toggleService(stop: true), isTrue);
      expect(bind.options[kOptionStopService], 'Y');
      expect(await model.toggleService(stop: false), isTrue);
      expect(bind.options[kOptionStopService], '');
    });

    test('installed: a call that returns did not happen', () async {
      bind.installed = true;
      final model = LocalStatusModel();
      expect(await model.toggleService(stop: true), isFalse);
      expect(await model.toggleService(stop: false), isFalse);
    });

    test('stopping always asks first', () {
      expect(LocalStatusModel().serviceAsksFirst(stop: true), isTrue);
    });
  });
}

/// `stop-service` as Rust receives it, on the portable or installed version.
class _ServiceBind implements RustdeskImpl {
  final options = <String, String>{};
  bool installed = false;

  @override
  Future<void> mainSetOption(
      {required String key, required String value, dynamic hint}) async {
    options[key] = value;
  }

  @override
  bool mainIsInstalled({dynamic hint}) => installed;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
