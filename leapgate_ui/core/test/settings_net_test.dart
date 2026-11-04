import 'dart:convert';

import 'package:flutter/material.dart' show Locale, ThemeMode;
import 'package:flutter_hbb/leapgate/settings/appearance.dart';
import 'package:flutter_hbb/leapgate/settings/connection_settings.dart';
import 'package:flutter_hbb/leapgate/settings/exit_settings.dart';
import 'package:flutter_hbb/leapgate/settings/server_config.dart';
import 'package:flutter_hbb/leapgate/settings/settings_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'settings_fakes.dart';

// The rules of coder B's settings sections (`LEAPGATE.md` §10.13): exit node prerequisites, the
// server summary, the server configuration codec, the language shown, the wait for a direct
// connection. Server names are example.com ones.

void main() {
  group('exit node prerequisites (02 §1.3.6)', () {
    ExitPrerequisites p(
            {bool set = true,
            String method = '',
            String approve = '',
            String access = '',
            String tunnel = ''}) =>
        exitPrerequisites(
            passwordSet: set,
            verificationMethod: method,
            approveMode: approve,
            accessMode: access,
            enableTunnel: tunnel);

    test('the permanent password: set, not set, set but one-time only', () {
      expect(p().fixedPassword, FixedPassword.set);
      expect(p(method: 'use-permanent-password').fixedPassword,
          FixedPassword.set);
      expect(p(set: false).fixedPassword, FixedPassword.notSet);
      expect(p(set: false, method: 'use-temporary-password').fixedPassword,
          FixedPassword.notSet);
      expect(p(method: 'use-temporary-password').fixedPassword,
          FixedPassword.oneTimeOnly);
    });

    test('the approval mode: empty is both', () {
      expect(p(approve: 'password').approval, Approval.password);
      expect(p().approval, Approval.both);
      expect(p(approve: 'click').approval, Approval.click);
    });

    test('TCP tunnels as the access mode has them', () {
      expect(p().tunnelAllowed, isTrue);
      expect(p(tunnel: 'N').tunnelAllowed, isFalse);
      expect(p(access: 'full', tunnel: 'N').tunnelAllowed, isTrue);
      expect(p(access: 'view', tunnel: 'Y').tunnelAllowed, isFalse);
    });
  });

  group('allowed networks', () {
    late FakeSettingsApi api;
    setUp(() => settingsApi = api = FakeSettingsApi());

    test('stored value one a line, counted by Rust; unreadable counts none', () {
      expect(allowNetsText('10.0.0.0/24, 10.0.0.5 198.18.0.0/15'),
          '10.0.0.0/24\n10.0.0.5\n198.18.0.0/15');
      api.onAllowNets = (text) =>
          AllowNetsCheck(valid: !text.contains('/33'), count: 3);
      expect(allowedNetCount('10.0.0.0/24,10.0.0.5,198.18.0.0/15'), 3);
      expect(allowedNetCount('198.51.100.0/33'), 0);
      expect(allowedNetCount(''), 0);
    });
  });

  group('server summary (02 §1.5.2)', () {
    test('marks by source', () {
      expect(idServerMark(ServerSource.byDefault), ServerMark.byDefault);
      expect(idServerMark(ServerSource.cacheDefault), ServerMark.byDefault);
      expect(idServerMark(ServerSource.cacheLast), ServerMark.lastUsed);
      expect(idServerMark(ServerSource.user), ServerMark.none);
      expect(apiServerMark(ServerSource.derived), ServerMark.derived);
      expect(apiServerMark(ServerSource.byDefault), ServerMark.byDefault);
      expect(apiServerMark(ServerSource.user), ServerMark.none);
      expect(keyState(ServerSource.byDefault), KeyState.setByDefault);
      expect(keyState(ServerSource.user), KeyState.set);
      expect(keyState(ServerSource.none), KeyState.notSet);
    });

    test('the built-in ID server only when the summary shows it', () {
      expect(
          defaultIdServer(const ServerSummary(
              id: 'leapgate.example.com', idSource: ServerSource.byDefault)),
          'leapgate.example.com');
      expect(
          defaultIdServer(const ServerSummary(
              id: 'home.example.com', idSource: ServerSource.user)),
          '');
    });

    test('plain HTTP warns unless it is this device', () {
      expect(isPlainHttpApi('http://home.example.com:21114'), isTrue);
      expect(isPlainHttpApi('https://home.example.com'), isFalse);
      expect(isPlainHttpApi('http://127.0.0.1:21114'), isFalse);
      expect(isPlainHttpApi('http://localhost'), isFalse);
      expect(isPlainHttpApi(''), isFalse);
    });
  });

  group('server configuration codec (upstream ServerConfig)', () {
    test('encode and decode give the same servers back', () {
      final c = ServerConfig(
          idServer: 'home.example.com',
          relayServer: 'relay-2.example.com',
          apiServer: 'https://home.example.com',
          key: 'abc=');
      final d = ServerConfig.tryDecode(c.encode())!;
      expect(d.toOptions(), c.toOptions());
    });

    test('the shared form is reversed base64 of JSON; plain JSON is read too', () {
      final json = jsonEncode({'host': 'home.example.com', 'key': 'k'});
      final shared = base64Url.encode(utf8.encode(json)).split('').reversed.join();
      expect(ServerConfig.tryDecode(shared)!.idServer, 'home.example.com');
      expect(ServerConfig.tryDecode(json)!.key, 'k');
      expect(ServerConfig.tryDecode('not a configuration'), isNull);
      expect(ServerConfig.tryDecode('42'), isNull);
    });

    test('import: empty, invalid without an ID server, ok', () {
      expect(importServerConfig(null).result, ImportResult.empty);
      expect(importServerConfig('  ').result, ImportResult.empty);
      expect(importServerConfig('xyz').result, ImportResult.invalid);
      expect(
          importServerConfig(ServerConfig(apiServer: 'https://a.example.com')
                  .encode())
              .result,
          ImportResult.invalid);
      final ok = importServerConfig(
          ServerConfig(idServer: 'home.example.com').encode());
      expect(ok.result, ImportResult.ok);
      expect(ok.config!.idServer, 'home.example.com');
    });

    test('saving drops a slash at the end of the addresses', () {
      final c = ServerConfig(
              idServer: 'home.example.com/',
              apiServer: 'https://home.example.com/ ',
              key: ' k ')
          .normalized();
      expect(c.idServer, 'home.example.com');
      expect(c.apiServer, 'https://home.example.com');
      expect(c.key, 'k');
    });
  });

  group('appearance (02 §1.5.1)', () {
    test('a language the new UI lacks follows the system', () {
      expect(uiLangChoice('zh-cn'), 'zh-cn');
      expect(uiLangChoice('ja'), '');
      expect(resolveUiLang('en', const Locale('zh', 'CN')), 'en');
      expect(resolveUiLang('ja', const Locale('zh', 'TW')), 'zh-cn');
      expect(resolveUiLang('', const Locale('de')), 'en');
      expect(localeOfUiLang('zh-cn'), const Locale('zh'));
    });

    test('theme values', () {
      expect(themeModeOf('dark'), ThemeMode.dark);
      expect(themeModeOf('light'), ThemeMode.light);
      expect(themeModeOf(kThemeSystem), ThemeMode.system);
      expect(themeModeOf(''), ThemeMode.system);
    });
  });

  test('wait for a direct connection: 0.1 to 99.9, one decimal, empty is the default', () {
    expect(parseFallbackDelay(''), '');
    expect(parseFallbackDelay(' 2.5 '), '2.5');
    expect(parseFallbackDelay('99.9'), '99.9');
    expect(parseFallbackDelay('0.1'), '0.1');
    expect(parseFallbackDelay('0'), isNull);
    expect(parseFallbackDelay('0.0'), isNull);
    expect(parseFallbackDelay('100'), isNull);
    expect(parseFallbackDelay('2.55'), isNull);
    expect(parseFallbackDelay('abc'), isNull);
  });
}
