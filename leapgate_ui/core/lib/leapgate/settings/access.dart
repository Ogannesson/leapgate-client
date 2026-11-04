// The calls of the access, permissions and service sections that are not options (`LEAPGATE.md`
// §10.7 接入办法 4); the one-time password and the service are `LocalStatusModel`'s.
import '../../models/platform_model.dart';

/// "允许隐私模式" is shown when this device has a privacy mode (upstream
/// `desktop_setting_page.dart:1265`).
bool privacyModeSupported() => bind.mainSupportedPrivacyModeImpls() != '[]';
