import 'package:flutter/foundation.dart';

import '../../models/platform_model.dart';

/// What the "输入解锁 PIN" dialog answered: the right PIN, or "改用管理员权限解锁". Closing it
/// answers null.
enum PinAnswer { correct, useAdministrator }

/// Whether [typed] is the unlock PIN. Rust stores the PIN trimmed and upstream compares the
/// trimmed input (`common/widgets/dialog.dart` `checkUnlockPinDialog`); compared here with no
/// limit on tries (M6-3).
bool unlockPinMatches(String typed, String pin) => typed.trim() == pin;

/// Why a new unlock PIN can't be saved yet (02 §1.6.7).
enum NewPinError { tooShort, tooLong, mismatch }

/// Rust refuses a shorter PIN (`ipc::set_unlock_pin`).
const kUnlockPinMinLength = 4;

/// The checks Rust makes on a new PIN, made first here so the dialog can say which one failed;
/// both fields are trimmed, as Rust trims.
NewPinError? checkNewUnlockPin(String pin, String confirmation, int maxLength) {
  pin = pin.trim();
  final length = pin.runes.length;
  if (length > maxLength) return NewPinError.tooLong;
  if (length < kUnlockPinMinLength) return NewPinError.tooShort;
  if (confirmation.trim() != pin) return NewPinError.mismatch;
  return null;
}

/// The lock on the installed version's settings (02 §1.2.6, R2-Q3, R2-Q31): one unlock covers
/// every locked section until the user leaves the settings page; the portable version is never
/// locked. Only a gate in the UI: the IPC that writes the options does not check it.
class SettingsUnlock extends ChangeNotifier {
  bool _unlocked = false;
  bool _denied = false;
  bool? _pinSet;

  bool get locked => !_unlocked && bind.mainIsInstalled();

  /// The last unlock ended without administrator permission (UAC cancelled or failed; the two
  /// can't be told apart, 09 §4.4).
  bool get denied => _denied;

  /// Whether an unlock PIN is set, as last read; null before the first read.
  bool? get pinSet => _pinSet;

  /// "解锁": with a PIN set, [askPin] shows the PIN dialog; otherwise, or when the user picks
  /// administrator permission there, UAC asks. `mainGetUnlockPin` goes to the service over IPC
  /// (up to 1 s), so it is read here, on the click, and not while building (09 §4.3).
  Future<bool> unlock(Future<PinAnswer?> Function(String pin) askPin) async {
    if (!locked) return true;
    final pin = bind.mainGetUnlockPin();
    _pinSet = pin.isNotEmpty;
    if (pin.isNotEmpty) {
      final answer = await askPin(pin);
      if (answer == null) return false;
      if (answer == PinAnswer.correct) return _unlockedBy(true);
    }
    return _unlockedBy(await bind.mainCheckSuperUserPermission());
  }

  bool _unlockedBy(bool ok) {
    _unlocked = ok;
    _denied = !ok;
    notifyListeners();
    return ok;
  }

  /// Leaving the settings page: another home page, a session tab, the window hidden.
  void lock() {
    if (!_unlocked && !_denied) return;
    _unlocked = false;
    _denied = false;
    notifyListeners();
  }

  /// Reads [pinSet] for the unlock PIN row; an IPC round trip, see [unlock].
  void readPinSet() {
    _pinSet = bind.mainGetUnlockPin().isNotEmpty;
    notifyListeners();
  }

  /// The longest PIN Rust keeps (`mainMaxEncryptLen`).
  int get pinMaxLength => bind.mainMaxEncryptLen();

  /// Saves a new PIN, or removes it with ''. False when Rust refused it; [checkNewUnlockPin]
  /// has made Rust's own checks, so that means the service did not take it.
  bool savePin(String pin) {
    if (bind.mainSetUnlockPin(pin: pin).isNotEmpty) return false;
    _pinSet = pin.trim().isNotEmpty;
    notifyListeners();
    return true;
  }
}

/// The one lock of the main window: the settings page, the home page's password row ("修改",
/// R2-Q31) and the main window (leaving the home tab, hiding) share it.
final settingsUnlock = SettingsUnlock();
