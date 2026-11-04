// The two-factor authentication section (02 §1.3.3, §1.6.3, §1.6.4): whether it is on, the
// Telegram bot, the trusted devices. Upstream: `desktop_setting_page.dart` `tfa`,
// `common/widgets/dialog.dart` `change2fa`, `changeBot`, `TrustedDevice`.
import 'dart:convert';

import '../../models/platform_model.dart';
import '../options.dart';
import 'settings_api.dart';

/// Config: the TOTP secret, encrypted, and the Telegram bot; written by Rust when a code or a
/// token checks out, removed here.
const _kOption2fa = '2fa';
const _kOptionBot = 'bot';

bool twoFactorOn() => bind.mainHasValid2FaSync();

bool botSet() => bind.mainHasValidBotSync();

/// A new secret as an `otpauth://` link; Rust keeps it until a code checks out. Empty when Rust
/// could not make one.
Future<String> newTwoFactorLink() => bind.mainGenerate2Fa();

/// The secret of an `otpauth://` link as the dialog shows it: groups of four, four groups a line.
String twoFactorSecretText(String link) {
  final plain = twoFactorSecret(link);
  final groups = [
    for (var i = 0; i < plain.length; i += 4)
      plain.substring(i, i + 4 > plain.length ? plain.length : i + 4),
  ];
  return [
    for (var i = 0; i < groups.length; i += 4)
      groups.skip(i).take(4).join(' '),
  ].join('\n');
}

/// The plain secret, for "复制".
String twoFactorSecret(String link) =>
    RegExp(r'secret=([^&]+)').firstMatch(link)?.group(1) ?? '';

/// Off: the secret goes, and with it every trusted device (upstream does it silently, 02 §1.3.3
/// says so in the confirmation). False when the service did not take it.
Future<bool> turnOffTwoFactor(OptionScope config) async {
  if (!await config.set(_kOption2fa, '')) return false;
  await bind.mainClearTrustedDevices();
  return true;
}

Future<bool> removeBot(OptionScope config) => config.set(_kOptionBot, '');

/// How long a device stays trusted (`hbb_common` `TrustedDevice::outdate`).
const _trustedFor = Duration(days: 90);

/// A device that need not type a code (Rust's `TrustedDevice`).
class TrustedDevice {
  const TrustedDevice(
      {required this.hwid,
      required this.time,
      required this.id,
      required this.name,
      required this.platform});

  factory TrustedDevice.fromJson(Map<String, dynamic> m) => TrustedDevice(
        hwid: [for (final b in m['hwid'] as List) b as int],
        time: DateTime.fromMillisecondsSinceEpoch((m['time'] as num).toInt()),
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        platform: m['platform'] as String? ?? '',
      );

  /// What Rust removes it by; one ID can have more than one (`add_trusted_device` keeps one
  /// per hwid).
  final List<int> hwid;

  /// [hwid] in hex, to tell the rows apart.
  String get hwidHex =>
      hwid.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// When it was trusted.
  final DateTime time;
  final String id;
  final String name;
  final String platform;

  /// Whole days left; 0 on the last day ("今天到期").
  int daysLeft(DateTime now) {
    final left = time.add(_trustedFor).difference(now);
    return left.isNegative ? 0 : left.inDays;
  }
}

/// Rust's JSON, the most recently trusted first (upstream `TrustedDevice.get`). Rust already
/// drops the outdated ones.
List<TrustedDevice> parseTrustedDevices(String json) {
  if (json.isEmpty) return const [];
  return [
    for (final d in jsonDecode(json) as List)
      TrustedDevice.fromJson(d as Map<String, dynamic>),
  ]..sort((a, b) => b.time.compareTo(a.time));
}

Future<List<TrustedDevice>> readTrustedDevices() async =>
    parseTrustedDevices(await bind.mainGetTrustedDevices());

/// Removes [devices]; all of them clears the list, as upstream does.
Future<void> removeTrustedDevices(
    List<TrustedDevice> devices, int total) async {
  if (devices.length == total) return bind.mainClearTrustedDevices();
  await bind.mainRemoveTrustedDevices(
      json: jsonEncode([for (final d in devices) d.hwid]));
}

Future<void> clearTrustedDevices() => bind.mainClearTrustedDevices();

/// The code typed in "开启二次验证": six digits, as Rust's TOTP has them.
bool twoFactorCodeComplete(String code) => RegExp(r'^\d{6}$').hasMatch(code);

Future<TwoFactorCheck> verifyTwoFactor(String code) =>
    settingsApi.verify2fa(code);
