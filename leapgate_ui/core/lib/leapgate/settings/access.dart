// The calls of the access, permissions and service sections that are not options (`LEAPGATE.md`
// §10.7 接入办法 4).
import '../../models/platform_model.dart';

/// After the one-time password's length or "仅使用数字" changed: Rust makes a new one at once
/// (02 §1.3.1; upstream waited for the next refresh after "仅使用数字").
Future<void> refreshOneTimePassword() => bind.mainUpdateTemporaryPassword();

/// "允许隐私模式" is shown when this device has a privacy mode (upstream
/// `desktop_setting_page.dart:1265`).
bool privacyModeSupported() => bind.mainSupportedPrivacyModeImpls() != '[]';
