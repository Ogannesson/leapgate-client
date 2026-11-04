import 'dart:convert';

import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/options.dart';
import 'package:flutter_hbb/leapgate/settings/incoming_sessions.dart';
import 'package:flutter_hbb/leapgate/settings/restrictions.dart';
import 'package:flutter_hbb/leapgate/settings/two_factor.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

// The rules of coder C's settings sections (`LEAPGATE.md` §10.14): the trusted devices as Rust
// lists them, the sound sources, the allow lists checked line by line. Addresses are from the
// documentation ranges; the 2FA link carries a made-up key.

/// Rust's answers for the sound sources.
class _Bind implements RustdeskImpl {
  bool loopback = true;
  List<String> inputs = const [];
  final config = <String, String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #mainAudioSupportLoopback:
        return loopback;
      case #mainGetSoundInputs:
        return Future.value(inputs);
      case #mainGetOptionSync:
        return config[invocation.namedArguments[#key]] ?? '';
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  group('trusted devices', () {
    final now = DateTime(2026, 11, 4, 12);
    Map<String, dynamic> device(String id, DateTime time) => {
          'hwid': [1, 2, id.length],
          'time': time.millisecondsSinceEpoch,
          'id': id,
          'name': 'Device $id',
          'platform': 'Windows',
        };

    test('Rust\'s list, the most recently trusted first', () {
      final list = parseTrustedDevices(jsonEncode([
        device('111111111', now.subtract(const Duration(days: 10))),
        device('222222222', now.subtract(const Duration(days: 1))),
      ]));
      expect([for (final d in list) d.id], ['222222222', '111111111']);
      expect(list.first.hwid, [1, 2, 9]);
      expect(list.first.name, 'Device 222222222');
      expect(list.first.platform, 'Windows');
      expect(parseTrustedDevices(''), isEmpty);
      expect(parseTrustedDevices('[]'), isEmpty);
    });

    test('days left of the 90; the last day is 0 ("今天到期")', () {
      TrustedDevice at(Duration ago) => parseTrustedDevices(
          jsonEncode([device('111111111', now.subtract(ago))])).single;
      expect(at(Duration.zero).daysLeft(now), 90);
      expect(at(const Duration(days: 67, hours: 1)).daysLeft(now), 22);
      expect(at(const Duration(days: 89, hours: 2)).daysLeft(now), 0);
    });

    test('the key under the QR code: groups of four, four groups a line', () {
      const link =
          'otpauth://totp/Leapgate:100200300?secret=ABCDEFGHIJKLMNOPQRSTUVWXYZ234567&issuer=Leapgate';
      expect(twoFactorSecret(link), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567');
      expect(twoFactorSecretText(link),
          'ABCD EFGH IJKL MNOP\nQRST UVWX YZ23 4567');
      expect(twoFactorCodeComplete('123456'), isTrue);
      expect(twoFactorCodeComplete('12345'), isFalse);
    });
  });

  group('sound sources (upstream audio_input.dart)', () {
    late _Bind bind;
    setUp(() {
      bind = _Bind();
      platformFFI.setBindingForTesting(bind);
    });

    test('system sound and the inputs; nothing stored is the system sound',
        () async {
      bind.inputs = ['Microphone', 'Line in'];
      final s = await readSoundSources(OptionsModel().config);
      expect(s.loopback, isTrue);
      expect(s.devices, ['Microphone', 'Line in']);
      expect(s.current, '');
      expect(s.isEmpty, isFalse);
    });

    test('the stored input; no source at all hides the row', () async {
      bind
        ..config[kOptionAudioInput] = 'Line in'
        ..inputs = ['Line in'];
      expect((await readSoundSources(OptionsModel().config)).current,
          'Line in');
      bind
        ..loopback = false
        ..inputs = const [];
      expect((await readSoundSources(OptionsModel().config)).isEmpty, isTrue);
    });
  });

  group('allow lists (02 §1.6.5)', () {
    test('IP: addresses and networks of both families, wrong lines by number',
        () {
      final c = checkWhitelist(WhitelistKind.ip,
          '192.0.2.10\n198.51.100.0/24, 2001:db8::/32\n0.0.0.0/0\n\n2001:db8::1');
      expect(c.valid, isTrue);
      expect(c.entries, [
        '192.0.2.10',
        '198.51.100.0/24',
        '2001:db8::/32',
        '0.0.0.0/0',
        '2001:db8::1',
      ]);
      expect(c.value,
          '192.0.2.10,198.51.100.0/24,2001:db8::/32,0.0.0.0/0,2001:db8::1');

      final bad = checkWhitelist(WhitelistKind.ip,
          '192.0.2.10\n192.0.2.256\n198.51.100.0/33; 2001:db8::/129\nexample.com\n192.0.2.1;192.0.2.2');
      expect(bad.valid, isFalse);
      expect(bad.invalidLines, [2, 3, 4]);
    });

    test('ID: wildcards are fine, control characters are not', () {
      final c = checkWhitelist(WhitelistKind.id, '123456789\n12345*\n1234?6789');
      expect(c.invalidLines, isEmpty);
      expect(c.value, '123456789,12345*,1234?6789');
      expect(checkWhitelist(WhitelistKind.id, 'ok\nbad\u0007').invalidLines,
          [2]);
    });

    test('an empty list is stored as upstream\'s ","; stored lists read back',
        () {
      expect(checkWhitelist(WhitelistKind.ip, ' \n').value, kWhitelistNone);
      expect(whitelistEntries(kWhitelistNone), isEmpty);
      expect(whitelistEntries(''), isEmpty);
      expect(whitelistText('192.0.2.10,198.51.100.0/24'),
          '192.0.2.10\n198.51.100.0/24');
    });

    test('the direct access port and the idle minutes: 1 to 65535, empty is the default',
        () {
      expect(parseDirectPort(''), '');
      expect(parseDirectPort('21119'), '21119');
      expect(parseDirectPort('0'), isNull);
      expect(parseDirectPort('65536'), isNull);
      expect(directPort(''), kDefaultDirectPort);
      expect(directPort('21119'), 21119);
      // Upstream took 0 for the default; Rust still does.
      expect(directPort('0'), kDefaultDirectPort);
      expect(parseAutoDisconnectMinutes(''), '');
      expect(parseAutoDisconnectMinutes('30'), '30');
      expect(parseAutoDisconnectMinutes('0'), isNull);
      expect(parseAutoDisconnectMinutes('1.5'), isNull);
    });
  });
}
