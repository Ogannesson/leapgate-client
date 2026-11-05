import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/shell/navigation.dart';

import 'session_fakes.dart';

// "打开网络设置" under the two session errors that come from this device's server settings
// (01 §4.3, 02 §1.2.1). The device ID is made up.

const _id = '100200300';

/// The main window's navigation, recording the links to settings.
class _Recorder implements MainNavigation {
  _Recorder(this.real);

  final MainNavigation real;
  final settings = <SettingsSectionId>[];

  @override
  void connect(String id,
          {String password = '',
          bool isSharedPassword = false,
          bool forceRelay = false,
          String switchUuid = ''}) =>
      real.connect(id,
          password: password,
          isSharedPassword: isSharedPassword,
          forceRelay: forceRelay,
          switchUuid: switchUuid);

  @override
  void showHome({bool focusConnectBox = false, String? connectBoxText}) =>
      real.showHome(
          focusConnectBox: focusConnectBox, connectBoxText: connectBoxText);

  @override
  void showSettings(SettingsSectionId section, {String? item}) =>
      settings.add(section);

  @override
  void openFileTransfer(String id,
          {String password = '',
          bool isSharedPassword = false,
          bool forceRelay = false}) =>
      real.openFileTransfer(id,
          password: password,
          isSharedPassword: isSharedPassword,
          forceRelay: forceRelay);
}

void main() {
  late AppFakes fakes;

  setUp(() => fakes = installAppFakes());

  testMainWindow('key mismatch and a failed handshake open the network settings',
      (tester) async {
    fakes.lg.reasons
      ..['Key mismatch'] = 'key_mismatch'
      ..['Failed to secure tcp: x'] = 'secure_tcp_failed';
    await pumpMainWindow(tester);
    final nav = _Recorder(mainNavigation);
    mainNavigation = nav;

    mainNavigation.connect(_id);
    await tester.pump();
    await tester.pump();
    final s = appCore.sessions.sessionsOf(_id).single;
    await emit(tester, fakes, s, msgbox('error', 'Connection Error', 'Key mismatch'));
    expect(find.text('本机与服务器的密钥（Key）不一致，无法连接服务器。'), findsOneWidget);
    expect(find.text('关闭标签'), findsNothing);
    await tester.tap(find.text('打开网络设置'));
    expect(nav.settings, [SettingsSectionId.network]);

    await emit(tester, fakes, s,
        msgbox('error', 'Connection Error', 'Failed to secure tcp: x'));
    expect(find.text('与服务器的加密握手失败。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('打开网络设置'), findsOneWidget);
  });
}
