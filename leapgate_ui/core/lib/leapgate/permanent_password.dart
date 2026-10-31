import 'dart:convert';

import 'package:password_strength/password_strength.dart';

import '../models/platform_model.dart';

/// The rules under the password field of "Set permanent password" (01 P1 block K), upstream's
/// four (`desktop_home_page.dart:902-908`, `common/widgets/custom_password.dart`).
enum PasswordRule { digit, uppercase, lowercase, length8 }

bool passwordRuleMet(PasswordRule rule, String password) => switch (rule) {
      PasswordRule.digit => password.contains(RegExp(r'[0-9]')),
      PasswordRule.uppercase => password.runes.any((r) {
          final c = String.fromCharCode(r);
          return c.toUpperCase() == c && c.toLowerCase() != c;
        }),
      PasswordRule.lowercase => password.runes.any((r) {
          final c = String.fromCharCode(r);
          return c.toLowerCase() == c && c.toUpperCase() != c;
        }),
      PasswordRule.length8 => password.length >= 8,
    };

enum PasswordStrength { weak, medium, strong }

/// The strength bar, upstream's thresholds (`PasswordStrengthIndicator`); null while empty.
PasswordStrength? passwordStrength(String password) {
  if (password.isEmpty) return null;
  final s = estimatePasswordStrength(password);
  return s < 0.33
      ? PasswordStrength.weak
      : s < 0.67
          ? PasswordStrength.medium
          : PasswordStrength.strong;
}

/// Why "OK" or "Remove" did not save.
enum PasswordSaveError {
  /// The password misses one of the [PasswordRule]s.
  rules,

  /// The confirmation differs.
  mismatch,

  /// Rust did not save it.
  failed,
}

/// What the dialog shows when it opens.
typedef PermanentPasswordState = ({bool isSet, bool clearsTrustedDevices});

/// Whether a permanent password is set on this device (then the dialog says it is not shown
/// and offers "Remove"), and whether saving or removing it clears the trusted devices (02
/// §1.6.2: two-factor authentication is on and the list is not empty;
/// `libs/hbb_common/src/config.rs:1304-1334` clears it on any change).
Future<PermanentPasswordState> readPermanentPasswordState() async {
  final isSet =
      await bind.mainGetCommon(key: 'local-permanent-password-set') == 'true';
  var trusted = false;
  if (bind.mainHasValid2FaSync()) {
    // Empty when there are none (upstream `TrustedDevice.get`).
    final json = await bind.mainGetTrustedDevices();
    final list = json.isEmpty ? null : jsonDecode(json);
    trusted = list is List && list.isNotEmpty;
  }
  return (isSet: isSet, clearsTrustedDevices: trusted);
}

/// "OK" (upstream `setPasswordDialog` `submit`): the rules first, then the confirmation, then
/// Rust. Both fields are trimmed. Null when it was saved.
Future<PasswordSaveError?> savePermanentPassword(
    String password, String confirmation) async {
  final pass = password.trim();
  if (pass.isNotEmpty &&
      PasswordRule.values.any((r) => !passwordRuleMet(r, pass))) {
    return PasswordSaveError.rules;
  }
  if (confirmation.trim() != pass) return PasswordSaveError.mismatch;
  return await bind.mainSetPermanentPasswordWithResult(password: pass)
      ? null
      : PasswordSaveError.failed;
}

/// "Remove". Null when it was removed.
Future<PasswordSaveError?> removePermanentPassword() async =>
    await bind.mainSetPermanentPasswordWithResult(password: '')
        ? null
        : PasswordSaveError.failed;
