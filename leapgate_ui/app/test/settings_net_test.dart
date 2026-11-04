import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/server_config.dart'
    show ServerConfig, kOptionRelayServer;
import 'package:flutter_hbb/leapgate/settings/settings_api.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/main.dart' show LeapgateApp;
import 'package:leapgate_ui/pages/settings/sections/account.dart';
import 'package:leapgate_ui/pages/settings/sections/appearance.dart';
import 'package:leapgate_ui/pages/settings/sections/connection.dart';
import 'package:leapgate_ui/pages/settings/sections/exit_node.dart';
import 'package:leapgate_ui/pages/settings/sections/network.dart';
import 'package:leapgate_ui/pages/settings/settings_registry.dart';
import 'package:leapgate_ui/pages/settings/settings_section_state.dart';
import 'package:leapgate_ui/shell/tab_overlays.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';

import '../../core/test/account_fakes.dart';
import 'home_fakes.dart';
import 'settings_fakes.dart';

// Coder B's settings sections (02 §1.3.6, §1.4.1, §1.5.1~§1.5.3, §1.6.6, §1.6.8, §1.6.9), one
// test per state of 02 §1.10, over FakeSettingsApi and a bridge that keeps Config. Servers are
// example.com names and addresses from the documentation ranges.

/// Keeps Config, the proxy and Rust's answers to the server checks.
class _Bind extends FakeBind {
  final config = <String, String>{};
  List<String> socks = const [];

  /// `mainTestIfValidServer`'s answer by address; others are fine.
  final unresolvable = <String, String>{};
  bool fixedSet = false;

  /// Holds every server check until completed.
  Completer<String>? held;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      case #mainGetOptionSync:
        return config[args[#key]] ?? '';
      case #mainSetOption:
        calls.add(invocation);
        config[args[#key]] = args[#value];
        return Future<void>.value();
      case #mainGetSocks:
        return Future.value(socks);
      case #mainGetCommon
          when args[#key] == 'local-permanent-${'pass'}word-set':
        return Future.value(fixedSet ? 'true' : '');
      case #mainGetCommonSync:
        // Rust's `get_api_server`: typed API, else derived from a typed ID server, else default.
        final [api, id] =
            jsonDecode((args[#key] as String).split(':').skip(1).join(':'))
                as List;
        final url = api != ''
            ? api
            : id != ''
                ? 'http://$id:21114'
                : 'https://leapgate.example.com';
        return jsonEncode({'url': url});
      case #mainTestIfValidServer:
        calls.add(invocation);
        return held?.future ?? Future.value(unresolvable[args[#server]] ?? '');
      case #mainChangeTheme:
      case #mainChangeLanguage:
        calls.add(invocation);
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

const _defaultSummary = ServerSummary(
  id: 'leapgate.example.com',
  idSource: ServerSource.byDefault,
  api: 'https://leapgate.example.com',
  apiSource: ServerSource.byDefault,
  keySource: ServerSource.byDefault,
);

late _Bind _bind;
late FakeSettingsApi _api;
late FakeNavigation _nav;
late FakeLeapgate _lg;
late FakeAccountApi _account;

Finder _switch(String label) => find.byWidgetPredicate(
    (w) => w is LgSwitch && w.semanticLabel == label);

Finder _button(String label) => find.widgetWithText(LgButton, label);

/// A status line: the label after its mark.
Finder _status(String label) => find.textContaining(
    RegExp('^￼+${RegExp.escape(label)}\$'),
    findRichText: true);

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

/// The clipboard as the page sets and reads it.
class _Clipboard {
  String? text;
}

_Clipboard _mockClipboard(WidgetTester tester) {
  final clipboard = _Clipboard();
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    switch (call.method) {
      case 'Clipboard.setData':
        clipboard.text = (call.arguments as Map)['text'] as String;
      case 'Clipboard.getData':
        return clipboard.text == null ? null : {'text': clipboard.text};
    }
    return null;
  });
  return clipboard;
}

void main() {
  setUp(() {
    final fakes = installHomeFakes();
    _nav = fakes.nav;
    _lg = fakes.lg;
    _bind = _Bind();
    platformFFI.setBindingForTesting(_bind);
    settingsApi = _api = FakeSettingsApi()..summary = _defaultSummary;
    accountApi = _account = FakeAccountApi();
  });

  group('exit node', () {
    void exitOn() => _bind.config[kOptionLeapgateAllowExit] = 'Y';

    testWidgets('off: the switch alone; turning it on writes Y', (tester) async {
      await _pump(tester, exitNodeSection);
      expect(find.text('允许作为出口'), findsOneWidget);
      expect(find.text('无人值守'), findsNothing);
      await tester.tap(_switch('允许作为出口'));
      await _settle(tester);
      expect(_bind.config[kOptionLeapgateAllowExit], 'Y');
      expect(find.text('无人值守'), findsOneWidget);
    });

    testWidgets('on, everything met', (tester) async {
      exitOn();
      _bind
        ..fixedSet = true
        ..config['approve-mode'] = 'password'
        ..config[kOptionEnableTunnel] = 'N';
      await _pump(tester, exitNodeSection);
      expect(_status('固定密码：已设置'), findsOneWidget);
      expect(_status('审批方式：输入密码'), findsOneWidget);
      expect(_status('TCP 隧道：已禁止'), findsOneWidget);
      expect(find.text('未放行任何网段'), findsOneWidget);
      expect(_button('修改'), findsNothing);
    });

    testWidgets('three not met: each links where it is fixed', (tester) async {
      exitOn();
      _bind.config['approve-mode'] = 'click';
      await _pump(tester, exitNodeSection);
      expect(_status('固定密码：未设置'), findsOneWidget);
      expect(_button('设置'), findsOneWidget);
      expect(_status('审批方式：在本机接受，需有人在本机接受连接'), findsOneWidget);
      expect(_status('TCP 隧道：已允许，知道访问密码的人可通过 TCP 隧道访问本机所在局域网中的设备'),
          findsOneWidget);
      await tester.tap(_button('修改').first);
      await tester.tap(_button('修改').last);
      expect(_nav.settings, [
        (section: SettingsSectionId.access, item: 'approve-mode'),
        (section: SettingsSectionId.permissions, item: kOptionEnableTunnel),
      ]);
    });

    testWidgets('a permanent password the one-time method never asks for', (tester) async {
      exitOn();
      _bind
        ..fixedSet = true
        ..config['verification-method'] = 'use-temporary-password';
      await _pump(tester, exitNodeSection);
      expect(_status('固定密码：已设置，但密码方式为“仅一次性密码”'), findsOneWidget);
      await tester.tap(_button('修改').first);
      expect(_nav.settings.single,
          (section: SettingsSectionId.access, item: 'verification-method'));
    });

    testWidgets('three networks allowed, counted by Rust', (tester) async {
      exitOn();
      _bind.config['leapgate-exit-allow-nets'] =
          '10.0.0.0/24,10.0.0.5,198.18.0.0/15';
      _api.onAllowNets = (text) => AllowNetsCheck(
          valid: true, count: text.split('\n').length, value: text);
      await _pump(tester, exitNodeSection);
      expect(find.text('已放行 3 个网段'), findsOneWidget);
    });

    testWidgets('turning it off asks with the number of exit sessions', (tester) async {
      exitOn();
      _lg.incomingCounts = '{"remote":1,"exit":2}';
      await _pump(tester, exitNodeSection);
      await tester.tap(_switch('允许作为出口'));
      await _settle(tester);
      expect(find.text('关闭“允许作为出口”？'), findsOneWidget);
      expect(find.text('正在使用本机作为出口的 2 个会话将断开。'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await _settle(tester);
      expect(_bind.config[kOptionLeapgateAllowExit], 'Y');

      await tester.tap(_switch('允许作为出口'));
      await _settle(tester);
      await tester.tap(_button('关闭'));
      await _settle(tester);
      expect(_bind.config[kOptionLeapgateAllowExit], 'N');

      // No session uses it: nothing to ask.
      exitOn();
      _lg.incomingCounts = '{"remote":1,"exit":0}';
      await _pump(tester, exitNodeSection);
      await tester.tap(_switch('允许作为出口'));
      await _settle(tester);
      expect(find.text('关闭“允许作为出口”？'), findsNothing);
      expect(_bind.config[kOptionLeapgateAllowExit], 'N');
    });

    testWidgets('allowed networks dialog: a wrong line stops OK, a blocked one warns', (tester) async {
      exitOn();
      _api.onAllowNets = (text) {
        final lines = text.split('\n');
        return AllowNetsCheck(
          valid: !lines.contains('198.51.100.0/33'),
          count: lines.length,
          lines: {
            for (final (i, l) in lines.indexed)
              if (l == '198.51.100.0/33')
                i + 1: NetLineState.invalid
              else if (l == '169.254.169.254')
                i + 1: NetLineState.blocked,
          },
          value: lines.join(','),
        );
      };
      await _pump(tester, exitNodeSection);
      await tester.tap(_button('编辑'));
      await _settle(tester);
      expect(find.text('每行一个 IP 地址或网段，例如 10.0.0.0/24、10.0.0.5、198.18.0.0/15（虚拟地址）'),
          findsOneWidget);

      final area = find.byType(EditableText).last;
      await tester.enterText(area, '10.0.0.0/24\n198.51.100.0/33');
      await tester.pump();
      expect(find.text('第 2 行格式不正确'), findsOneWidget);
      expect(tester.widget<LgButton>(_button('确定')).onPressed, isNull);

      await tester.enterText(area, '10.0.0.0/24\n169.254.169.254');
      await tester.pump();
      expect(find.text('第 2 行属于始终禁止访问的地址，不会生效'), findsOneWidget);
      await tester.tap(_button('确定'));
      await _settle(tester);
      expect(_bind.config['leapgate-exit-allow-nets'],
          '10.0.0.0/24,169.254.169.254');

      await tester.tap(_button('编辑'));
      await _settle(tester);
      await tester.tap(_button('清除'));
      await _settle(tester);
      expect(find.text('清除全部放行的网段？'), findsOneWidget);
      await tester.tap(_button('清除').last);
      await _settle(tester);
      expect(_bind.config['leapgate-exit-allow-nets'], '');
    });

    testWidgets('locked: the switch and "编辑" do nothing, the links still go', (tester) async {
      exitOn();
      await _pump(tester, exitNodeSection, locked: true);
      expect(tester.widget<LgSwitch>(_switch('允许作为出口')).onChanged, isNull);
      expect(tester.widget<LgButton>(_button('编辑')).onPressed, isNull);
      expect(tester.widget<LgButton>(_button('修改')).onPressed, isNotNull);
    });
  });

  group('connection methods', () {
    testWidgets('punch on by default; off greys TCP as on and writes both N', (tester) async {
      _bind.local
        ..[kOptionEnableIpv6Punch] = 'Y'
        ..[kOptionEnableUdpPunch] = 'N';
      await _pump(tester, connectionSection);
      expect(tester.widget<LgSwitch>(_switch('打洞直连')).value, isTrue);
      expect(find.text('关闭“打洞直连”时始终启用'), findsNothing);

      await tester.tap(_switch('打洞直连'));
      await _settle(tester);
      expect(_bind.local[kOptionEnableIpv6Punch], 'N');
      expect(_bind.local[kOptionEnableUdpPunch], 'N');
      final tcp = tester.widget<LgSwitch>(_switch('局域网直连和 TCP 打洞'));
      expect(tcp.value, isTrue);
      expect(tcp.onChanged, isNull);
      expect(find.text('关闭“打洞直连”时始终启用'), findsOneWidget);

      await tester.tap(_switch('打洞直连'));
      await _settle(tester);
      expect(_bind.local[kOptionEnableIpv6Punch], 'Y');
      expect(_bind.local[kOptionEnableUdpPunch], 'N');
    });

    testWidgets('wait time: a wrong value says so and is not saved', (tester) async {
      await _pump(tester, connectionSection);
      final field = find.byType(EditableText);
      await tester.enterText(field, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(find.text('须为 0.1~99.9 之间的数，最多一位小数'), findsOneWidget);
      expect(_bind.local[kOptionRelayFallbackDelay], isNull);

      await tester.enterText(field, '4.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(find.text('须为 0.1~99.9 之间的数，最多一位小数'), findsNothing);
      expect(_bind.local[kOptionRelayFallbackDelay], '4.5');
    });

    testWidgets('the notes on what keeps direct connections from being tried', (tester) async {
      _bind
        ..socks = ['socks5://198.51.100.20:1080', '', '']
        ..config[kOptionAllowWebSocket] = 'Y'
        ..config[kOptionDisableUdp] = 'Y'
        ..config['key'] = 'not a key';
      _api
        ..onKey = ((_) => KeyCheck.invalid)
        ..kind = ServerKind.compat;
      await _pump(tester, connectionSection);
      for (final text in [
        '已设置代理，传出连接将始终经中继',
        '已使用 WebSocket，传出连接将始终经中继',
        '已禁用 UDP，部分直连方式不可用',
        'Key 未设置或格式不正确，部分直连方式不可用',
        '当前服务器不支持部分直连方式',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      await tester.tap(find.text('网络和服务器').first);
      expect(_nav.settings.single.section, SettingsSectionId.network);
    });

    testWidgets('no key and none built in: the key note too', (tester) async {
      _api.summary = const ServerSummary(keySource: ServerSource.none);
      await _pump(tester, connectionSection);
      expect(find.text('Key 未设置或格式不正确，部分直连方式不可用'), findsOneWidget);
      expect(find.text('已设置代理，传出连接将始终经中继'), findsNothing);
    });
  });

  group('appearance', () {
    testWidgets('theme, interface mode and language are written and announced', (tester) async {
      _bind.local[kCommConfKeyLang] = 'ja';
      await _pump(tester, appearanceSection);
      // A language the new UI lacks shows as following the system.
      expect(find.bySemanticsLabel('语言: 跟随系统'), findsOneWidget);

      await tester.tap(find.text('深色'));
      await _settle(tester);
      expect(_bind.local[kCommConfKeyTheme], 'dark');
      expect(_bind.callsTo(#mainChangeTheme).single.namedArguments[#dark],
          'dark');

      await tester.tap(find.text('详细'));
      await _settle(tester);
      expect(_bind.local['leapgate-ui-mode'], 'detail');

      await tester.tap(find.bySemanticsLabel('语言: 跟随系统'));
      await _settle(tester);
      await tester.tap(find.text('English').last);
      await _settle(tester);
      expect(_bind.local[kCommConfKeyLang], 'en');
      expect(_bind.callsTo(#mainChangeLanguage).single.namedArguments[#lang],
          'en');
      expect(_api.saved.last, {'leapgate-ui-lang': 'en'});
    });

    testWidgets('the app follows the theme and language as they are written', (tester) async {
      late BuildContext seen;
      await tester.pumpWidget(LeapgateApp(
        local: appCore.options.local,
        home: Builder(builder: (context) {
          seen = context;
          return const SizedBox();
        }),
      ));
      await appCore.options.local.set(kCommConfKeyTheme, 'dark');
      await appCore.options.local.set(kCommConfKeyLang, 'zh-cn');
      await tester.pump();
      expect(Theme.of(seen).brightness, Brightness.dark);
      expect(Localizations.localeOf(seen), const Locale('zh'));

      await appCore.options.local.set(kCommConfKeyLang, 'en');
      await tester.pump();
      expect(Localizations.localeOf(seen), const Locale('en'));
    });

    testWidgets('the CM follows what the main window announces', (tester) async {
      late BuildContext seen;
      final theme = ValueNotifier('light');
      final language = ValueNotifier('zh-cn');
      await tester.pumpWidget(LeapgateApp(
        detailMode: ValueNotifier(false),
        theme: theme,
        language: language,
        home: Builder(builder: (context) {
          seen = context;
          return const SizedBox();
        }),
      ));
      expect(Theme.of(seen).brightness, Brightness.light);
      expect(Localizations.localeOf(seen), const Locale('zh'));
      theme.value = 'dark';
      language.value = 'en';
      await tester.pump();
      expect(Theme.of(seen).brightness, Brightness.dark);
      expect(Localizations.localeOf(seen), const Locale('en'));
    });
  });

  group('network and server', () {
    testWidgets('the built-in server', (tester) async {
      await _pump(tester, networkSection);
      expect(find.text('leapgate.example.com（默认）'), findsOneWidget);
      expect(find.text('https://leapgate.example.com（默认）'), findsOneWidget);
      expect(find.text('已设置（默认）'), findsOneWidget);
      expect(find.text('Leapgate'), findsOneWidget);
      expect(find.text('中继服务器'), findsNothing);
      expect(find.text('未使用'), findsOneWidget);
      expect(find.textContaining('未加密的 HTTP'), findsNothing);
    });

    testWidgets('a typed server with a relay', (tester) async {
      _api.summary = const ServerSummary(
        id: 'home.example.com',
        idSource: ServerSource.user,
        api: 'https://home.example.com',
        apiSource: ServerSource.user,
        keySource: ServerSource.user,
        relay: 'relay-2.example.com',
      );
      await _pump(tester, networkSection);
      expect(find.text('home.example.com'), findsOneWidget);
      expect(find.text('https://home.example.com'), findsOneWidget);
      expect(find.text('已设置'), findsOneWidget);
      expect(find.text('relay-2.example.com'), findsOneWidget);
    });

    testWidgets('a typed ID server and no API server: derived, plain HTTP warned', (tester) async {
      _api.summary = const ServerSummary(
        id: 'home.example.com',
        idSource: ServerSource.user,
        api: 'http://home.example.com:21114',
        apiSource: ServerSource.derived,
        keySource: ServerSource.byDefault,
      );
      await _pump(tester, networkSection);
      expect(find.text('http://home.example.com:21114（由 ID 服务器推出）'),
          findsOneWidget);
      expect(find.text('API 服务器使用未加密的 HTTP 连接，账号密码和地址簿内容可能被第三方读取。'),
          findsOneWidget);
    });

    testWidgets('no ID server: said, "修改" is the main button', (tester) async {
      _api.summary = const ServerSummary();
      await _pump(tester, networkSection);
      expect(find.text('未设置 ID 服务器，本机无法连接服务器'), findsOneWidget);
      expect(find.text('未设置'), findsNWidgets(2));
      expect(tester.widget<LgButton>(_button('修改')).kind, LgButtonKind.primary);
    });

    testWidgets('server type: compatible and checking', (tester) async {
      _api.kind = ServerKind.compat;
      await _pump(tester, networkSection);
      expect(find.text('兼容服务器：出口目录和部分直连方式不可用'), findsOneWidget);
      _api.kind = ServerKind.checking;
      await _pump(tester, networkSection);
      expect(find.text('正在确认…'), findsOneWidget);
    });

    testWidgets('a proxy in use', (tester) async {
      _bind.socks = ['socks5://198.51.100.20:1080', '', ''];
      await _pump(tester, networkSection);
      expect(find.text('socks5://198.51.100.20:1080'), findsOneWidget);
    });

    testWidgets('WebSocket and disabling UDP are asked first', (tester) async {
      await _pump(tester, networkSection);
      await tester.tap(_switch('使用 WebSocket'));
      await _settle(tester);
      expect(find.text('使用 WebSocket？'), findsOneWidget);
      expect(find.text('开启后，本机无法被其他设备连接，传出连接将始终经中继。'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await _settle(tester);
      expect(_bind.config[kOptionAllowWebSocket], isNull);

      await tester.tap(_switch('禁用 UDP'));
      await _settle(tester);
      expect(find.text('开启后，本机无法被其他设备连接，传出连接更可能经中继。'), findsOneWidget);
      await tester.tap(_button('禁用'));
      await _settle(tester);
      expect(_bind.config[kOptionDisableUdp], 'Y');

      // Turning one off is not asked.
      await tester.tap(_switch('禁用 UDP'));
      await _settle(tester);
      expect(_bind.config[kOptionDisableUdp], 'N');
    });

    testWidgets('export copies the configuration in effect; import fills the dialog', (tester) async {
      final clipboard = _mockClipboard(tester);
      _bind.config[kOptionRelayServer] = 'relay-2.example.com';
      await _pump(tester, networkSection);
      await tester.tap(_button('导入'));
      await _settle(tester);
      expect(appCore.toasts.current?.key, 'settingsNetClipboardEmpty');

      await tester.tap(_button('导出'));
      await _settle(tester);
      expect(appCore.toasts.current?.key, 'settingsNetExported');
      // The servers in effect, though the user typed none; the relay as typed.
      final exported = ServerConfig.tryDecode(clipboard.text!)!;
      expect(exported.idServer, 'leapgate.example.com');
      expect(exported.apiServer, 'https://leapgate.example.com');
      expect(exported.relayServer, 'relay-2.example.com');
      expect(exported.key, '');

      clipboard.text = 'something else';
      await tester.tap(_button('导入'));
      await _settle(tester);
      expect(appCore.toasts.current?.key, 'settingsNetInvalidConfig');

      // Exported from another device: only prefilled until "确定".
      clipboard.text = _shared('home.example.com');
      await tester.tap(_button('导入'));
      await _settle(tester);
      expect(find.text('home.example.com'), findsOneWidget);
      expect(_api.saved, isEmpty);
      await tester.tap(_button('取消'));
      await _settle(tester);
      expect(_api.saved, isEmpty);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('server dialog: the defaults, a typed ID server and its hints', (tester) async {
      await _pump(tester, networkSection);
      await tester.tap(_button('修改'));
      await _settle(tester);
      expect(find.text('留空时使用默认值 leapgate.example.com'), findsOneWidget);
      expect(find.text('留空时使用默认值 https://leapgate.example.com'), findsOneWidget);
      expect(find.text('留空时使用内置的 Key'), findsOneWidget);
      expect(find.text('服务器类型为 Leapgate 时，以服务器选择的中继服务器为准'), findsOneWidget);

      await tester.enterText(find.byType(EditableText).first, 'home.example.com');
      await tester.pump();
      expect(find.text('留空时使用 http://home.example.com:21114'), findsOneWidget);
      expect(find.text('API 服务器使用未加密的 HTTP 连接，账号密码和地址簿内容可能被第三方读取。'),
          findsOneWidget);
      expect(find.text('留空时使用内置的 Key。ID 服务器不是默认值时，通常需要填写该服务器的 Key。'),
          findsOneWidget);

      await tester.tap(_button('全部恢复默认'));
      await tester.pump();
      expect(find.text('留空时使用默认值 https://leapgate.example.com'), findsOneWidget);
    });

    testWidgets('server dialog: an address that does not resolve, a wrong key', (tester) async {
      _bind.unresolvable['nowhere.example.com'] = 'No such host is known.';
      _api.onKey = (key) => key.isEmpty ? KeyCheck.empty : KeyCheck.invalid;
      await _pump(tester, networkSection);
      await tester.tap(_button('修改'));
      await _settle(tester);
      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), 'nowhere.example.com');
      await tester.enterText(fields.at(1), 'home.example.com');
      await tester.enterText(fields.at(2), 'bad');
      await tester.tap(_button('确定'));
      await _settle(tester);
      expect(find.text('无法解析此地址'), findsOneWidget);
      expect(find.text('API 服务器地址须以 http:// 或 https:// 开头'), findsOneWidget);
      expect(find.text('Key 格式不正确'), findsOneWidget);
      expect(find.text('No such host is known.'), findsNothing);
      await tester.tap(_button('技术细节'));
      await tester.pump();
      expect(find.text('No such host is known.'), findsOneWidget);
      expect(_api.saved, isEmpty);
    });

    testWidgets('server dialog: signed in, a new API server signs out first, then saves', (tester) async {
      final order = <String>[];
      accountApi = _account = _OrderedAccount(order)
        ..loginResult = const ApiResult.ok(AccountUser(name: 'zhangsan'));
      settingsApi = _api = _OrderedSettings(order)..summary = _defaultSummary;
      await appCore.account.login('zhangsan', 'x');
      await _pump(tester, networkSection);
      await tester.tap(_button('修改'));
      await _settle(tester);
      expect(find.text('修改 API 服务器将退出当前账号'), findsNothing);
      await tester.enterText(find.byType(EditableText).first, 'home.example.com/');
      await tester.pump();
      expect(find.text('修改 API 服务器将退出当前账号'), findsOneWidget);

      await tester.tap(_button('确定'));
      await _settle(tester);
      // Signed out of the old server before the new one is stored (09 §4.5).
      expect(order, ['logout', 'save']);
      expect(_api.saved.single, {
        'custom-rendezvous-server': 'home.example.com',
        'relay-server': '',
        'api-server': '',
        'key': '',
      });
      expect(find.text('全部恢复默认'), findsNothing);
      expect(appCore.toasts.current?.key, 'settingsNetSaved');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('server dialog: signed in, an address that fails does not sign out', (tester) async {
      _bind.unresolvable['nowhere.example.com'] = 'No such host is known.';
      _account.loginResult = const ApiResult.ok(AccountUser(name: 'zhangsan'));
      await appCore.account.login('zhangsan', 'x');
      await _pump(tester, networkSection);
      await tester.tap(_button('修改'));
      await _settle(tester);
      await tester.enterText(find.byType(EditableText).first, 'nowhere.example.com');
      await tester.tap(_button('确定'));
      await _settle(tester);
      expect(find.text('无法解析此地址'), findsOneWidget);
      expect(_account.callsTo('logout'), isEmpty);
      expect(_api.saved, isEmpty);
      expect(appCore.account.loggedIn, isTrue);
    });

    testWidgets('server dialog: while it checks, "取消" and Esc do not close it', (tester) async {
      final check = Completer<String>();
      _bind.held = check;
      await _pump(tester, networkSection);
      await tester.tap(_button('修改'));
      await _settle(tester);
      await tester.enterText(find.byType(EditableText).first, 'home.example.com');
      await tester.tap(_button('确定'));
      await tester.pump();
      expect(find.text('正在验证服务器地址…'), findsOneWidget);
      expect(tester.widget<LgButton>(_button('取消')).onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('全部恢复默认'), findsOneWidget);

      check.complete('');
      await _settle(tester);
      expect(_api.saved, hasLength(1));
      expect(find.text('全部恢复默认'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('server dialog: the service did not save it', (tester) async {
      _api.saveResult = SaveResult.failed;
      await _pump(tester, networkSection);
      await tester.tap(_button('修改'));
      await _settle(tester);
      await tester.tap(_button('确定'));
      await _settle(tester);
      expect(find.text('无法保存设置'), findsOneWidget);
      expect(find.text('全部恢复默认'), findsOneWidget);
    });

    testWidgets('proxy dialog: a new proxy warns, a bad address stops, then saves', (tester) async {
      _bind.unresolvable['nowhere.example.com:1080'] = 'No such host is known.';
      await _pump(tester, networkSection);
      await tester.tap(_button('设置'));
      await _settle(tester);
      expect(find.text('未写协议时按 SOCKS5，端口默认 1080'), findsOneWidget);
      expect(find.text('移除代理'), findsNothing);
      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), 'socks5://nowhere.example.com:1080');
      await tester.pump();
      expect(find.text('使用代理时，本机无法被其他设备连接，传出连接将始终经中继。'), findsOneWidget);
      await tester.tap(_button('确定'));
      await _settle(tester);
      expect(find.text('无法解析此地址'), findsOneWidget);
      expect(_api.socks, isEmpty);

      await tester.enterText(fields.at(0), 'socks5://198.51.100.20:1080');
      await tester.enterText(fields.at(1), 'zhangsan');
      await tester.tap(_button('确定'));
      await _settle(tester);
      expect(_api.socks.single.proxy, 'socks5://198.51.100.20:1080');
      expect(_api.socks.single.username, 'zhangsan');
    });

    testWidgets('proxy dialog: while it checks, "取消" and Esc do not close it', (tester) async {
      final check = Completer<String>();
      _bind.held = check;
      await _pump(tester, networkSection);
      await tester.tap(_button('设置'));
      await _settle(tester);
      await tester.enterText(
          find.byType(EditableText).first, 'socks5://198.51.100.20:1080');
      await tester.tap(_button('确定'));
      await tester.pump();
      expect(tester.widget<LgButton>(_button('取消')).onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('未写协议时按 SOCKS5，端口默认 1080'), findsOneWidget);

      check.complete('');
      await _settle(tester);
      expect(_api.socks.single.proxy, 'socks5://198.51.100.20:1080');
      expect(find.text('未写协议时按 SOCKS5，端口默认 1080'), findsNothing);
    });

    testWidgets('proxy dialog: removing a proxy, too long a secret', (tester) async {
      _bind.socks = ['socks5://198.51.100.20:1080', '', ''];
      await _pump(tester, networkSection);
      await tester.tap(_button('修改').last);
      await _settle(tester);
      expect(find.text('使用代理时，本机无法被其他设备连接，传出连接将始终经中继。'), findsNothing);
      await tester.enterText(find.byType(EditableText).at(2), 'x' * 129);
      await tester.tap(_button('确定'));
      await _settle(tester);
      expect(find.text('密码过长'), findsOneWidget);
      expect(_api.socks, isEmpty);

      await tester.tap(_button('移除代理'));
      await _settle(tester);
      expect(_api.socks.single.proxy, '');
    });

    testWidgets('locked: changes wait for the unlock, export does not', (tester) async {
      await _pump(tester, networkSection, locked: true);
      expect(tester.widget<LgButton>(_button('修改')).onPressed, isNull);
      expect(tester.widget<LgButton>(_button('导入')).onPressed, isNull);
      expect(tester.widget<LgButton>(_button('导出')).onPressed, isNotNull);
      expect(tester.widget<LgSwitch>(_switch('使用 WebSocket')).onChanged, isNull);
    });
  });

  group('account', () {
    testWidgets('signed out: the note and "登录"', (tester) async {
      await _pump(tester, accountSection);
      expect(find.text('未登录'), findsOneWidget);
      expect(find.text('登录后可使用地址簿、同组设备和出口目录'), findsOneWidget);
      await tester.tap(_button('登录'));
      await _settle(tester);
      expect(find.text('用户名'), findsOneWidget);
    });

    testWidgets('signed in: who, on which server; signing out is asked', (tester) async {
      _account.loginResult = const ApiResult.ok(
          AccountUser(name: 'zhangsan', displayName: '张三'));
      final out = _SlowLogout();
      accountApi = out..loginResult = _account.loginResult;
      await appCore.account.login('zhangsan', 'x');
      await _pump(tester, accountSection);
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('@zhangsan'), findsOneWidget);
      expect(find.text('服务器：https://leapgate.example.com'), findsOneWidget);

      await tester.tap(_button('退出登录'));
      await _settle(tester);
      expect(find.text('退出登录？'), findsOneWidget);
      expect(find.text('退出后，地址簿、同组设备和出口目录将不可用。'), findsOneWidget);
      await tester.tap(_button('退出登录').last);
      await _settle(tester);
      expect(find.text('正在退出登录…'), findsOneWidget);
      out.done();
      await _settle(tester);
      expect(find.text('未登录'), findsOneWidget);
    });
  });
}

/// The shared form of a server configuration with [host], as another device exports it.
String _shared(String host) => base64Url
    .encode(utf8.encode(jsonEncode({'host': host, 'relay': '', 'api': '', 'key': ''})))
    .split('')
    .reversed
    .join();

/// Writes "logout" into the shared [order].
class _OrderedAccount extends FakeAccountApi {
  _OrderedAccount(this.order);

  final List<String> order;

  @override
  Future<void> logout() async {
    order.add('logout');
    await super.logout();
  }
}

/// Writes "save" into the shared [order].
class _OrderedSettings extends FakeSettingsApi {
  _OrderedSettings(this.order);

  final List<String> order;

  @override
  Future<SaveResult> setOptions(Map<String, String> changes) {
    order.add('save');
    return super.setOptions(changes);
  }
}

/// Holds the sign-out request until [done].
class _SlowLogout extends FakeAccountApi {
  final _request = Completer<void>();

  void done() => _request.complete();

  @override
  Future<void> logout() => _request.future;
}
