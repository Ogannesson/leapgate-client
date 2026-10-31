import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/permanent_password.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Bind implements RustdeskImpl {
  final saved = <String>[];
  bool saves = true;
  String passwordSet = 'false';
  bool twoFactor = false;
  String trusted = '[]';

  @override
  Future<bool> mainSetPermanentPasswordWithResult(
      {required String password, dynamic hint}) async {
    saved.add(password);
    return saves;
  }

  @override
  Future<String> mainGetCommon({required String key, dynamic hint}) async =>
      key == 'local-permanent-password-set' ? passwordSet : '';

  @override
  bool mainHasValid2FaSync({dynamic hint}) => twoFactor;

  @override
  Future<String> mainGetTrustedDevices({dynamic hint}) async => trusted;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Bind bind;
  setUp(() {
    bind = _Bind();
    platformFFI.setBindingForTesting(bind);
  });

  test('the four rules', () {
    bool met(PasswordRule r, String p) => passwordRuleMet(r, p);
    expect(met(PasswordRule.digit, 'abc1'), isTrue);
    expect(met(PasswordRule.digit, 'abc'), isFalse);
    expect(met(PasswordRule.uppercase, 'aBc'), isTrue);
    expect(met(PasswordRule.uppercase, 'abc1'), isFalse);
    expect(met(PasswordRule.lowercase, 'ABc'), isTrue);
    expect(met(PasswordRule.lowercase, 'ABC1'), isFalse);
    expect(met(PasswordRule.length8, '1234567'), isFalse);
    expect(met(PasswordRule.length8, '12345678'), isTrue);
  });

  test('strength: no bar while empty, then one to four', () {
    expect(passwordStrengthBars(''), 0);
    expect(passwordStrengthBars('abc'), 1);
    expect(passwordStrengthBars('Tr0ub4dour&3-xkcd-Horse'), 4);
  });

  group('saving (desktop_home_page.dart:921-958)', () {
    test('rules first, then the confirmation, both trimmed', () async {
      expect(
          await savePermanentPassword('abc', 'abc'), PasswordSaveError.rules);
      expect(await savePermanentPassword('Abcdefg1', 'Abcdefg2'),
          PasswordSaveError.mismatch);
      expect(bind.saved, isEmpty);
      expect(await savePermanentPassword(' Abcdefg1 ', 'Abcdefg1'), isNull);
      expect(bind.saved, ['Abcdefg1']);
    });

    test('Rust refusing it is "failed", for removing as well', () async {
      bind.saves = false;
      expect(await savePermanentPassword('Abcdefg1', 'Abcdefg1'),
          PasswordSaveError.failed);
      expect(await removePermanentPassword(), PasswordSaveError.failed);
      expect(bind.saved.last, '');
    });
  });

  test(
      'trusted devices are cleared only with 2FA on and some trusted (02 §1.6.2)',
      () async {
    bind.passwordSet = 'true';
    bind.trusted = '[{"hwid":"x"}]';
    var state = await readPermanentPasswordState();
    expect(state.isSet, isTrue);
    expect(state.clearsTrustedDevices, isFalse);

    bind.twoFactor = true;
    state = await readPermanentPasswordState();
    expect(state.clearsTrustedDevices, isTrue);

    bind.trusted = '[]';
    state = await readPermanentPasswordState();
    expect(state.clearsTrustedDevices, isFalse);
  });
}
