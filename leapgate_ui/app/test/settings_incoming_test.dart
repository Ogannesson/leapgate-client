import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/incoming_sessions.dart'
    show wallpaperSupported;
import 'package:flutter_hbb/leapgate/settings/settings_api.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/pages/settings/sections/during_sessions.dart';
import 'package:leapgate_ui/pages/settings/sections/remote_printing.dart';
import 'package:leapgate_ui/pages/settings/sections/restrictions.dart';
import 'package:leapgate_ui/pages/settings/sections/sessions.dart';
import 'package:leapgate_ui/pages/settings/sections/two_factor.dart';
import 'package:leapgate_ui/pages/settings/settings_registry.dart';
import 'package:leapgate_ui/pages/settings/settings_section_state.dart';
import 'package:leapgate_ui/shell/tab_overlays.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';

import 'home_fakes.dart';
import 'settings_fakes.dart';

// Coder C's settings sections (02 §1.3.3~§1.3.5, §1.3.7, §1.4.3) and dialogs (§1.6.3~§1.6.5),
// one test per state of 02 §1.10, over FakeSettingsApi and a bridge that keeps Config. The 2FA
// link carries a made-up key; addresses are from the documentation ranges.

const _link =
    'otpauth://totp/Leapgate:100200300?secret=ABCDEFGHIJKLMNOPQRSTUVWXYZ234567&issuer=Leapgate';

/// Rust's answers for these sections.
class _Bind extends FakeBind {
  bool twoFactor = false;
  bool bot = false;
  List<Map<String, dynamic>> trusted = const [];

  /// The trusted devices stay as they were: the service did not take the change.
  bool serviceDown = false;

  /// Empty when Rust could not make a secret.
  String twoFactorLink = _link;
  bool loopback = true;
  List<String> inputs = const ['Microphone'];
  String privacyImpls = '[]';
  bool wallpaper = true;
  bool rdp = true;

  /// What UAC lets through for RDP session sharing.
  bool rdpAllowed = true;
  String printerInstalled = 'false';
  String recordingFolder = r'C:\Leapgate-test-folder-that-does-not-exist';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      case #mainHasValid2FaSync:
        return twoFactor;
      case #mainHasValidBotSync:
        return bot;
      case #mainGenerate2Fa:
        return Future.value(twoFactorLink);
      case #mainGetTrustedDevices:
        return Future.value(jsonEncode(trusted));
      case #mainRemoveTrustedDevices:
        calls.add(invocation);
        final gone = {
          for (final h in jsonDecode(args[#json] as String) as List)
            jsonEncode(h),
        };
        if (!serviceDown) {
          trusted = [
            for (final d in trusted)
              if (!gone.contains(jsonEncode(d['hwid']))) d,
          ];
        }
        return Future<void>.value();
      case #mainClearTrustedDevices:
        calls.add(invocation);
        if (!serviceDown) trusted = const [];
        return Future<void>.value();
      case #mainTestWallpaper:
      case #mainSetCommon:
        calls.add(invocation);
        return Future<void>.value();
      case #mainAudioSupportLoopback:
        return loopback;
      case #mainGetSoundInputs:
        return Future.value(inputs);
      case #mainSupportedPrivacyModeImpls:
        return privacyImpls;
      case #mainDefaultPrivacyModeImpl:
        return 'privacy_mode_impl_exclude_from_capture';
      case #mainSupportRemoveWallpaper:
        return Future.value(wallpaper);
      case #mainIsShareRdp:
        return rdp;
      case #mainSetShareRdp:
        calls.add(invocation);
        if (rdpAllowed) rdp = args[#enable] as bool;
        return Future<void>.value();
      case #mainGetCommonSync when args[#key] == 'is-printer-installed':
        return printerInstalled;
      case #mainVideoSaveDirectory:
        return recordingFolder;
    }
    return super.noSuchMethod(invocation);
  }
}

late _Bind _bind;
late FakeSettingsApi _api;
late FakeNavigation _nav;

Finder _switch(String label) => find.byWidgetPredicate(
    (w) => w is LgSwitch && w.semanticLabel == label);

Finder _button(String label) => find.widgetWithText(LgButton, label);

/// The trusted devices list's two delete buttons, by what a screen reader hears.
final _deletePicked = find.bySemanticsLabel('删除所选受信设备');
final _deleteAll = find.bySemanticsLabel('删除全部受信设备');

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// [make]'s section in Chinese over a section state it returns, with the home tab's overlay.
Future<SettingsSectionState> _pump(WidgetTester tester,
    SettingsSection Function(AppLocalizations l10n) make,
    {bool locked = false}) async {
  tester.view.physicalSize = const Size(1280, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final overlays = TabOverlays();
  final state = SettingsSectionState(
      overlays: overlays, saveFailedText: '无法保存设置', locked: locked);
  addTearDown(state.dispose);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
    home: Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: Builder(builder: (context) {
            final section = make(AppLocalizations.of(context)!);
            return ListenableBuilder(
              listenable: state,
              builder: (context, _) => SingleChildScrollView(
                  child: section.build(context, state)),
            );
          }),
        ),
        Positioned.fill(child: Overlay(key: overlays.keyOf(null))),
      ]),
    ),
  ));
  await _settle(tester);
  return state;
}

/// Holds an answer of the settings API until the test completes it.
class _HeldApi extends FakeSettingsApi {
  final twoFactorAnswer = Completer<TwoFactorCheck>();
  final botAnswer = Completer<BotCheck>();

  @override
  Future<TwoFactorCheck> verify2fa(String code) => twoFactorAnswer.future;

  @override
  Future<BotCheck> verifyBot(String token) => botAnswer.future;
}

Map<String, dynamic> _device(String id, String name, int daysAgo, int hwid) => {
      'hwid': [hwid],
      'time': DateTime.now()
          .subtract(Duration(days: daysAgo, hours: 1))
          .millisecondsSinceEpoch,
      'id': id,
      'name': name,
      'platform': 'Windows',
    };

void main() {
  setUp(() {
    final fakes = installHomeFakes();
    _nav = fakes.nav;
    _bind = _Bind();
    platformFFI.setBindingForTesting(_bind);
    settingsApi = _api = FakeSettingsApi()..writeThrough = true;
    wallpaperSupported = null;
  });

  group('二次验证 (02 §1.3.3, §1.6.3)', () {
    testWidgets('off: no trusted devices or bot; turning it on with the code',
        (tester) async {
      await _pump(tester, twoFactorSection);
      expect(find.text('未开启'), findsOneWidget);
      expect(find.text('受信设备'), findsNothing);
      expect(find.text('Telegram 机器人'), findsNothing);

      await tester.tap(_button('开启'));
      await _settle(tester);
      expect(find.text('开启二次验证'), findsOneWidget);
      expect(find.text('ABCD EFGH IJKL MNOP\nQRST UVWX YZ23 4567'),
          findsOneWidget);
      expect(find.bySemanticsLabel('二维码'), findsOneWidget);

      _api.twoFactor = 'wrong_code';
      await tester.enterText(find.byType(EditableText), '123456');
      await _settle(tester);
      expect(find.text('验证码错误或已过期'), findsOneWidget);

      _api.twoFactor = 'ok';
      _bind.twoFactor = true;
      await tester.enterText(find.byType(EditableText), '654321');
      await _settle(tester);
      expect(find.text('开启二次验证'), findsNothing);
      expect(appCore.toasts.current?.key, 'settingsTwoFactorEnabled');
      expect(find.text('已开启'), findsOneWidget);
      expect(find.text('受信设备'), findsOneWidget);
      expect(find.text('Telegram 机器人'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('the dialog while verifying, and a secret the service lost',
        (tester) async {
      final held = _HeldApi();
      settingsApi = held;
      await _pump(tester, twoFactorSection);
      await tester.tap(_button('开启'));
      await _settle(tester);
      await tester.enterText(find.byType(EditableText), '123456');
      await _settle(tester);
      expect(find.text('正在验证…'), findsOneWidget);
      expect(tester.widget<LgButton>(_button('取消')).onPressed, isNull);
      held.twoFactorAnswer.complete('not_saved');
      await _settle(tester);
      expect(find.text('无法保存设置'), findsOneWidget);
      expect(find.text('开启二次验证'), findsWidgets);
    });

    testWidgets('on with three trusted devices: pick two and delete them',
        (tester) async {
      _bind
        ..twoFactor = true
        ..trusted = [
          _device('912345678', '李四的台式机', 67, 1),
          _device('147258369', '王五的笔记本', 9, 2),
          _device('678912345', '备用手机', 89, 3),
        ];
      await _pump(tester, twoFactorSection);
      expect(find.text('已开启'), findsOneWidget);
      expect(find.text('剩余 22 天'), findsOneWidget);
      expect(find.text('剩余 80 天'), findsOneWidget);
      expect(find.text('今天到期'), findsOneWidget);
      expect(find.text('912 345 678'), findsOneWidget);

      await tester.tap(find.text('李四的台式机'));
      await tester.tap(find.text('备用手机'));
      await tester.pump();
      expect(find.text('已选择 2 台'), findsOneWidget);
      await tester.tap(_deletePicked);
      await _settle(tester);
      expect(find.text('删除所选的 2 台受信设备？'), findsOneWidget);
      await tester.tap(_button('删除').last);
      await _settle(tester);
      final removed = _bind.callsTo(#mainRemoveTrustedDevices).single;
      expect(jsonDecode(removed.namedArguments[#json] as String), [
        [1],
        [3],
      ]);
    });

    testWidgets('one ID trusted on two machines: each row is its own',
        (tester) async {
      _bind
        ..twoFactor = true
        ..trusted = [
          _device('912345678', '李四的台式机', 3, 1),
          _device('912345678', '李四的笔记本', 5, 2),
          _device('147258369', '王五的笔记本', 9, 3),
        ];
      await _pump(tester, twoFactorSection);
      await tester.tap(find.text('李四的笔记本'));
      await tester.pump();
      expect(find.text('已选择 1 台'), findsOneWidget);
      await tester.tap(_deletePicked);
      await _settle(tester);
      expect(find.text('删除所选的 1 台受信设备？'), findsOneWidget);
      await tester.tap(_button('删除').last);
      await _settle(tester);
      final removed = _bind.callsTo(#mainRemoveTrustedDevices).single;
      expect(jsonDecode(removed.namedArguments[#json] as String), [
        [2],
      ]);
    });

    testWidgets('no secret from Rust: no dialog, the row says so',
        (tester) async {
      _bind.twoFactorLink = '';
      await _pump(tester, twoFactorSection);
      await tester.tap(_button('开启'));
      await _settle(tester);
      expect(find.text('开启二次验证'), findsNothing);
      expect(find.text('无法开启二次验证'), findsOneWidget);
    });

    testWidgets('a delete the service did not take says so', (tester) async {
      _bind
        ..twoFactor = true
        ..serviceDown = true
        ..trusted = [
          _device('912345678', '李四的台式机', 3, 1),
          _device('147258369', '王五的笔记本', 9, 2),
        ];
      await _pump(tester, twoFactorSection);
      await tester.tap(find.text('李四的台式机'));
      await tester.pump();
      await tester.tap(_deletePicked);
      await _settle(tester);
      await tester.tap(_button('删除').last);
      await _settle(tester);
      expect(find.text('无法保存设置'), findsOneWidget);
      expect(find.text('李四的台式机'), findsOneWidget);
    });

    testWidgets('none trusted; deleting all asks first', (tester) async {
      _bind.twoFactor = true;
      await _pump(tester, twoFactorSection);
      expect(find.text('暂无受信设备'), findsOneWidget);
      expect(_deleteAll, findsNothing);

      _bind.trusted = [_device('912345678', '李四的台式机', 1, 1)];
      await _pump(tester, twoFactorSection);
      await tester.tap(_deleteAll);
      await _settle(tester);
      expect(find.text('删除全部受信设备？'), findsOneWidget);
      await tester.tap(_button('删除'));
      await _settle(tester);
      expect(_bind.callsTo(#mainClearTrustedDevices), hasLength(1));
    });

    testWidgets('turning it off asks, then clears the secret and the devices',
        (tester) async {
      _bind.twoFactor = true;
      await _pump(tester, twoFactorSection);
      await tester.tap(_button('关闭'));
      await _settle(tester);
      expect(find.text('关闭二次验证？'), findsOneWidget);
      expect(find.text('全部受信设备将同时被清除。'), findsOneWidget);
      await tester.tap(_button('关闭').last);
      await _settle(tester);
      expect(_api.saved.last, {'2fa': ''});
      expect(_bind.callsTo(#mainClearTrustedDevices), hasLength(1));
    });

    testWidgets('a turn-off the service did not take says so', (tester) async {
      _bind.twoFactor = true;
      _api.saveResult = SaveResult.failed;
      await _pump(tester, twoFactorSection);
      await tester.tap(_button('关闭'));
      await _settle(tester);
      await tester.tap(_button('关闭').last);
      await _settle(tester);
      expect(find.text('无法保存设置'), findsOneWidget);
      expect(_bind.callsTo(#mainClearTrustedDevices), isEmpty);
    });

    testWidgets('locked: nothing can be changed', (tester) async {
      _bind.twoFactor = true;
      await _pump(tester, twoFactorSection, locked: true);
      expect(tester.widget<LgButton>(_button('关闭')).onPressed, isNull);
      expect(tester.widget<LgButton>(_button('设置')).onPressed, isNull);
      expect(tester.widget<LgSwitch>(_switch('允许受信设备免输验证码')).onChanged,
          isNull);
    });
  });

  group('Telegram 机器人 (02 §1.6.4)', () {
    testWidgets('not set: the three errors, then set', (tester) async {
      _bind.twoFactor = true;
      await _pump(tester, twoFactorSection);
      expect(find.text('未设置'), findsOneWidget);
      await tester.tap(_button('设置'));
      await _settle(tester);
      expect(find.text('设置 Telegram 机器人'), findsWidgets);
      expect(
          find.text('验证码、本机 ID 和对方设备的 IP 地址将通过 Telegram 发送。机器人收到过一条消息后才能完成设置。'),
          findsOneWidget);
      expect(tester.widget<LgButton>(_button('确定')).onPressed, isNull);

      await tester.enterText(find.byType(EditableText), 'made-up');
      await tester.pump();
      for (final (result, text) in [
        ('network', '无法连接 Telegram。请检查网络连接。'),
        ('no_chat', '未找到与机器人的对话。请先向机器人发送一条消息（例如 /start）。'),
        ('invalid_token', 'Token 无效'),
        ('other', '无法保存设置'),
      ]) {
        _api.bot = (result: result, text: '');
        await tester.tap(_button('确定'));
        await _settle(tester);
        expect(find.text(text), findsOneWidget);
      }

      _api.bot = (result: 'ok', text: '');
      _bind.bot = true;
      await tester.tap(_button('确定'));
      await _settle(tester);
      expect(find.text('设置 Telegram 机器人'), findsNothing);
      expect(find.text('已设置'), findsOneWidget);
    });

    testWidgets('while verifying it can\'t be sent twice', (tester) async {
      _bind.twoFactor = true;
      final held = _HeldApi();
      settingsApi = held;
      await _pump(tester, twoFactorSection);
      await tester.tap(_button('设置'));
      await _settle(tester);
      await tester.enterText(find.byType(EditableText), 'made-up');
      await tester.pump();
      await tester.tap(_button('确定'));
      await _settle(tester);
      expect(find.text('正在验证…'), findsOneWidget);
      expect(tester.widget<LgButton>(_button('取消')).onPressed, isNull);
      held.botAnswer.complete((result: 'ok', text: ''));
      await _settle(tester);
      expect(find.text('正在验证…'), findsNothing);
    });

    testWidgets('removing it asks first', (tester) async {
      _bind
        ..twoFactor = true
        ..bot = true;
      await _pump(tester, twoFactorSection);
      await tester.tap(_button('移除'));
      await _settle(tester);
      expect(find.text('移除 Telegram 机器人？'), findsOneWidget);
      await tester.tap(_button('移除').last);
      await _settle(tester);
      expect(_api.saved.last, {'bot': ''});
    });
  });

  group('访问限制 (02 §1.3.4, §1.6.5)', () {
    testWidgets('lists off and on; the installed-only rows', (tester) async {
      _bind.config[kOptionIdWhitelist] = '123456789,12345*,1234?6789';
      await _pump(tester, restrictionsSection);
      expect(find.text('未启用'), findsOneWidget);
      expect(find.text('已启用 · 3 条'), findsOneWidget);
      expect(find.text('仅在 Leapgate 运行时允许连接'), findsNothing);
      expect(find.text('允许局域网中的设备发现本机'), findsNothing);

      _bind
        ..installed = true
        ..config[kOptionWhitelist] = ',';
      await _pump(tester, restrictionsSection);
      expect(find.text('未启用'), findsOneWidget);
      expect(find.text('仅在 Leapgate 运行时允许连接'), findsOneWidget);
      expect(find.text('允许局域网中的设备发现本机'), findsOneWidget);
    });

    testWidgets('IP allow list: a wrong line stops OK; saved one a comma',
        (tester) async {
      _bind.config[kOptionWhitelist] = '192.0.2.10,198.51.100.0/24,2001:db8::/32';
      await _pump(tester, restrictionsSection);
      expect(find.text('已启用 · 3 条'), findsOneWidget);
      await tester.tap(_button('编辑').first);
      await _settle(tester);
      expect(find.text('每行一个 IP 地址或网段，例如 192.0.2.10、198.51.100.0/24、2001:db8::/32'),
          findsOneWidget);
      expect(find.text('共 3 条'), findsOneWidget);

      final area = find.byType(EditableText).last;
      await tester.enterText(area, '192.0.2.10\n192.0.2.300\n2001:db8::/32');
      await tester.pump();
      expect(find.text('第 2 行格式不正确'), findsOneWidget);
      expect(tester.widget<LgButton>(_button('确定')).onPressed, isNull);

      await tester.enterText(area, '192.0.2.10\n198.51.100.7, 2001:db8::/32');
      await tester.pump();
      await tester.tap(_button('确定'));
      await _settle(tester);
      expect(_bind.config[kOptionWhitelist],
          '192.0.2.10,198.51.100.7,2001:db8::/32');
    });

    testWidgets('clearing a list asks first and stores none', (tester) async {
      _bind.config[kOptionIdWhitelist] = '123456789';
      await _pump(tester, restrictionsSection);
      await tester.tap(_button('编辑').last);
      await _settle(tester);
      expect(find.text('每行一个 ID，可使用 * 和 ? 作为通配符'), findsOneWidget);
      await tester.tap(_button('清除'));
      await _settle(tester);
      expect(find.text('清除全部条目并停用 ID 白名单？'), findsOneWidget);
      await tester.tap(_button('清除').last);
      await _settle(tester);
      expect(_bind.config[kOptionIdWhitelist], ',');
      expect(find.text('已启用 · 1 条'), findsNothing);
    });

    testWidgets('direct IP access: port, this device\'s addresses, port in use',
        (tester) async {
      _api
        ..adapters = const [
          LocalAdapter(name: 'Ethernet', ipv4: ['192.0.2.10'], ipv6: ['2001:db8::10']),
        ]
        // The record from before it was switched off.
        ..listen = const DirectListen(state: 'listening', port: 21118);
      await _pump(tester, restrictionsSection);
      expect(find.text('端口'), findsNothing);
      await tester.tap(_switch('允许直接 IP 访问'));
      await _settle(tester);
      expect(_bind.config[kOptionDirectServer], 'Y');
      expect(find.text('本机地址：192.0.2.10、2001:db8::10'), findsOneWidget);
      // The service listens again a second later, and fails.
      _api.listen =
          const DirectListen(state: 'failed', port: 21118, error: 'in_use');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('端口 21118 已被其他应用占用'), findsOneWidget);

      _api.listen = const DirectListen(state: 'listening', port: 21118);
      await _pump(tester, restrictionsSection);
      expect(find.text('端口 21118 已被其他应用占用'), findsNothing);

      _api.listen = const DirectListen(state: 'failed', port: 21118, error: 'in_use');
      await _pump(tester, restrictionsSection);
      expect(find.text('端口 21118 已被其他应用占用'), findsOneWidget);
    });

    testWidgets('a port out of range is not saved', (tester) async {
      _bind.config[kOptionDirectServer] = 'Y';
      await _pump(tester, restrictionsSection);
      final field = find.byType(EditableText);
      await tester.enterText(field, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(find.text('须为 1~65535 之间的整数'), findsOneWidget);
      expect(_bind.config[kOptionDirectAccessPort], isNull);

      await tester.enterText(field, '21119');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(find.text('须为 1~65535 之间的整数'), findsNothing);
      expect(_bind.config[kOptionDirectAccessPort], '21119');
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('会话 (02 §1.3.5)', () {
    testWidgets('idle disconnect: the minutes box and its range', (tester) async {
      await _pump(tester, sessionsSection);
      expect(find.text('时长'), findsNothing);
      await tester.tap(_switch('无操作时自动断开'));
      await _settle(tester);
      expect(find.text('分钟'), findsOneWidget);
      final field = find.byType(EditableText);
      await tester.enterText(field, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(find.text('须为 1~65535 之间的整数'), findsOneWidget);
      await tester.enterText(field, '30');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(_bind.config[kOptionAutoDisconnectTimeout], '30');
    });

    testWidgets('wallpaper preview counts down; hidden where unsupported',
        (tester) async {
      _bind.config[kOptionAllowRemoveWallpaper] = 'Y';
      await _pump(tester, sessionsSection);
      await tester.tap(_button('预览'));
      await tester.pump();
      expect(find.text('正在预览…（5）'), findsOneWidget);
      expect(_bind.callsTo(#mainTestWallpaper).single.namedArguments[#second], 5);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('正在预览…（3）'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('预览'), findsOneWidget);

      wallpaperSupported = null;
      _bind.wallpaper = false;
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, sessionsSection);
      expect(find.text('传入会话期间移除桌面壁纸'), findsNothing);
    });

    testWidgets('RDP session sharing, not under the lock; UAC cancelled',
        (tester) async {
      if (!Platform.isWindows) return;
      _bind
        ..installed = true
        ..rdpAllowed = false;
      await _pump(tester, sessionsSection, locked: true);
      await tester.tap(_switch('允许 RDP 会话共享'));
      await _settle(tester);
      expect(find.text('未获得管理员权限，设置未修改'), findsOneWidget);
      expect(tester.widget<LgSwitch>(_switch('允许 RDP 会话共享')).value, isTrue);

      _bind.rdpAllowed = true;
      await tester.tap(_switch('允许 RDP 会话共享'));
      await _settle(tester);
      expect(find.text('未获得管理员权限，设置未修改'), findsNothing);
      expect(_bind.rdp, isFalse);
    });

    testWidgets('sound source and privacy mode method; no source hides the row',
        (tester) async {
      _bind.privacyImpls = jsonEncode([
        ['privacy_mode_impl_exclude_from_capture', 'privacy_mode_impl_mag_tip'],
        ['privacy_mode_impl_virtual_display', 'privacy_mode_impl_virtual_display_tip'],
      ]);
      await _pump(tester, sessionsSection);
      expect(find.text('声音来源'), findsOneWidget);
      expect(find.text('系统声音'), findsOneWidget);
      expect(find.text('隐私模式的实现方式'), findsOneWidget);
      await tester.tap(find.text('使用虚拟显示器'));
      await _settle(tester);
      expect(_bind.config[kOptionPrivacyModeImpl], 'privacy_mode_impl_virtual_display');

      _bind
        ..loopback = false
        ..inputs = const []
        ..privacyImpls = '[]';
      await _pump(tester, sessionsSection);
      expect(find.text('声音来源'), findsNothing);
      expect(find.text('隐私模式的实现方式'), findsNothing);
    });

    testWidgets('recording location: portable and installed', (tester) async {
      await _pump(tester, sessionsSection);
      expect(find.text(_bind.recordingFolder), findsOneWidget);
      expect(find.text('与传出会话的录制文件使用同一位置'), findsOneWidget);
      // The folder does not exist yet.
      expect(tester.widget<LgButton>(_button('打开')).onPressed, isNull);
      expect(_button('修改'), findsOneWidget);

      if (!Platform.isWindows) return;
      _bind.installed = true;
      await _pump(tester, sessionsSection);
      expect(find.text('由 Leapgate 服务保存，位置不可修改'), findsOneWidget);
      expect(_button('修改'), findsNothing);
    });
  });

  group('远程打印 (02 §1.3.7)', () {
    testWidgets('portable', (tester) async {
      await _pump(tester, remotePrintingSection);
      expect(find.text('仅安装版支持远程打印'), findsOneWidget);
      expect(_button('安装打印机'), findsNothing);
    });

    testWidgets('install, fail, retry, ready; the permission links to 权限',
        (tester) async {
      _bind.installed = true;
      await _pump(tester, remotePrintingSection);
      expect(find.text('未安装 Leapgate 打印机'), findsOneWidget);
      await tester.tap(_button('安装打印机'));
      await tester.pump();
      expect(find.text('正在安装…'), findsOneWidget);
      expect(find.byType(LgButton), findsNothing);
      expect(_bind.callsTo(#mainSetCommon).single.namedArguments[#key],
          'install-printer');

      await platformFFI.tryHandle(
          {'name': 'install-printer-res', 'success': false, 'msg': 'driver error'});
      await tester.pump();
      expect(find.text('无法安装 Leapgate 打印机。'), findsOneWidget);
      expect(_button('重试'), findsOneWidget);

      await tester.tap(_button('重试'));
      await tester.pump();
      _bind.printerInstalled = 'true';
      await platformFFI.tryHandle({'name': 'install-printer-res', 'success': true, 'msg': ''});
      await tester.pump();
      expect(find.text('已安装'), findsOneWidget);
      expect(find.text('允许远程打印：已允许'), findsOneWidget);
      await tester.tap(_button('修改'));
      expect(_nav.settings.single, (
        section: SettingsSectionId.permissions,
        item: kOptionEnableRemotePrinter,
      ));
    });

    testWidgets('screen sharing only: not allowed, change the access mode',
        (tester) async {
      _bind
        ..installed = true
        ..printerInstalled = 'true'
        ..config[kOptionAccessMode] = 'view';
      await _pump(tester, remotePrintingSection);
      expect(find.text('允许远程打印：未允许'), findsOneWidget);
      await tester.tap(_button('修改'));
      expect(_nav.settings.single.item, kOptionAccessMode);
    });
  });

  group('会话期间 (02 §1.4.3)', () {
    testWidgets('terminal clipboard: ask, allow, deny; keep the screen on',
        (tester) async {
      await _pump(tester, duringSessionsSection);
      expect(
          tester.widget<LgSegmented<String>>(find.byType(LgSegmented<String>)).selected,
          '');
      await tester.tap(find.text('允许'));
      await _settle(tester);
      expect(_bind.local[kOptionAllowTerminalClipboardWrite], 'Y');
      await tester.tap(find.text('拒绝'));
      await _settle(tester);
      expect(_bind.local[kOptionAllowTerminalClipboardWrite], 'N');
      await tester.tap(find.text('每次询问'));
      await _settle(tester);
      expect(_bind.local[kOptionAllowTerminalClipboardWrite], '');

      expect(tester.widget<LgSwitch>(_switch('传出会话期间保持屏幕常亮')).value, isTrue);
      await tester.tap(_switch('传出会话期间保持屏幕常亮'));
      await _settle(tester);
      expect(_bind.local[kOptionKeepAwakeDuringOutgoingSessions], 'N');
      expect(find.text('与传入会话的录制文件使用同一位置'), findsOneWidget);
    });
  });
}
