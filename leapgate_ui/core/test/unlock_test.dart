import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/settings/unlock.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// The calls the lock makes: installed or not, the PIN the service keeps, and UAC's answer.
class _Bind implements RustdeskImpl {
  bool installed = true;
  String pin = '';
  bool admin = true;
  int adminAsked = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #mainIsInstalled:
        return installed;
      case #mainGetUnlockPin:
        return pin;
      case #mainCheckSuperUserPermission:
        adminAsked++;
        return Future.value(admin);
      case #mainSetUnlockPin:
        pin = (invocation.namedArguments[#pin] as String).trim();
        return '';
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  late _Bind bind;
  late SettingsUnlock lock;

  setUp(() {
    bind = _Bind();
    platformFFI.setBindingForTesting(bind);
    lock = SettingsUnlock();
  });

  Future<PinAnswer?> neverAsked(String pin) =>
      fail('no PIN dialog without a PIN');

  test('the portable version is never locked and asks nothing', () async {
    bind.installed = false;
    expect(lock.locked, isFalse);
    expect(await lock.unlock(neverAsked), isTrue);
    expect(bind.adminAsked, 0);
  });

  test('without a PIN, UAC decides; refused, it says so until the page is left',
      () async {
    bind.admin = false;
    expect(await lock.unlock(neverAsked), isFalse);
    expect(lock.locked, isTrue);
    expect(lock.denied, isTrue);
    lock.lock();
    expect(lock.denied, isFalse);

    bind.admin = true;
    expect(await lock.unlock(neverAsked), isTrue);
    expect(lock.locked, isFalse);
    // Leaving the settings page.
    lock.lock();
    expect(lock.locked, isTrue);
  });

  test('with a PIN: the dialog decides, or hands over to UAC; closed, nothing',
      () async {
    bind.pin = '2468';
    String? asked;
    expect(await lock.unlock((pin) async => null), isFalse);
    expect(lock.locked, isTrue);
    expect(lock.denied, isFalse);

    expect(
        await lock.unlock((pin) async {
          asked = pin;
          return PinAnswer.correct;
        }),
        isTrue);
    expect(asked, '2468');
    expect(bind.adminAsked, 0);

    lock.lock();
    expect(
        await lock.unlock((pin) async => PinAnswer.useAdministrator), isTrue);
    expect(bind.adminAsked, 1);
    expect(lock.pinSet, isTrue);
    // Locked again, it is not known until the next unlock reads it.
    lock.lock();
    expect(lock.pinSet, isNull);
  });

  test('the typed PIN is trimmed, as Rust stores it', () {
    expect(unlockPinMatches(' 2468 ', '2468'), isTrue);
    expect(unlockPinMatches('2469', '2468'), isFalse);
  });

  test('a new PIN: at least 4, at most what Rust keeps, typed twice alike', () {
    expect(checkNewUnlockPin('123', '123', 128), NewPinError.tooShort);
    expect(checkNewUnlockPin('1' * 129, '1' * 129, 128), NewPinError.tooLong);
    expect(checkNewUnlockPin('1234', '1235', 128), NewPinError.mismatch);
    expect(checkNewUnlockPin(' 1234 ', '1234', 128), isNull);
  });

  test('saving and removing a PIN updates whether one is set', () {
    expect(lock.savePin('2468'), isTrue);
    expect(lock.pinSet, isTrue);
    expect(lock.savePin(''), isTrue);
    expect(lock.pinSet, isFalse);
  });
}
