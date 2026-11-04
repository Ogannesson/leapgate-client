// The access restrictions section (02 §1.3.4, §1.6.5): the IP and ID allow lists and the port of
// direct IP access. Upstream: `common/widgets/dialog.dart` `changeWhiteList`,
// `changeIdWhiteList`; `desktop_setting_page.dart` `directIp`.
import 'dart:io';

/// What an empty list is stored as: upstream writes "," for a custom client, which Leapgate
/// always is, so that an empty value does not fall back to a built-in one
/// (`common.dart` `defaultOptionWhitelist`).
const kWhitelistNone = ',';

/// Direct IP access listens here when the port is empty (`src/rendezvous_mediator.rs`).
const kDefaultDirectPort = 21118;

/// The entries of a stored list (`whitelist`, `id-whitelist`): Rust splits on commas.
List<String> whitelistEntries(String stored) =>
    stored.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

/// The stored list as the dialog shows it, one entry a line.
String whitelistText(String stored) => whitelistEntries(stored).join('\n');

enum WhitelistKind { ip, id }

/// The dialog's text checked line by line (02 §1.6.5). Entries may also be separated by commas,
/// semicolons and spaces within a line.
class WhitelistCheck {
  const WhitelistCheck(
      {required this.entries, required this.invalidLines});

  final List<String> entries;

  /// 1-based, as typed.
  final List<int> invalidLines;

  bool get valid => invalidLines.isEmpty;

  /// What to store: one entry after another, or [kWhitelistNone] for none.
  String get value => entries.isEmpty ? kWhitelistNone : entries.join(',');
}

WhitelistCheck checkWhitelist(WhitelistKind kind, String text) {
  final entries = <String>[];
  final invalid = <int>[];
  for (final (i, line) in text.split('\n').indexed) {
    final items =
        line.split(RegExp(r'[\s,;]+')).where((e) => e.isNotEmpty).toList();
    if (items.any((e) => !_entryValid(kind, e))) invalid.add(i + 1);
    entries.addAll(items);
  }
  return WhitelistCheck(entries: entries, invalidLines: invalid);
}

bool _entryValid(WhitelistKind kind, String entry) => switch (kind) {
      WhitelistKind.ip => _ipOrNetwork(entry),
      // Upstream allows anything but control characters (the separators are gone already).
      WhitelistKind.id =>
        !entry.runes.any((c) => c <= 0x1f || (c >= 0x7f && c <= 0x9f)),
    };

final _ipv4 = RegExp(
    r'^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$');

/// What Rust's `IpCidr::from_str` (cidr-utils 0.5) takes for a whole address: an address, or an
/// address with a prefix length; bits past the prefix are ignored there. `0.0.0.0` lets everyone
/// in (`connection.rs` `check_whitelist`) and is an address like any other here.
bool _ipOrNetwork(String entry) {
  final slash = entry.indexOf('/');
  final address = slash < 0 ? entry : entry.substring(0, slash);
  final bits = slash < 0 ? null : entry.substring(slash + 1);
  final int max;
  if (_ipv4.hasMatch(address)) {
    max = 32;
  } else if (address.contains(':') &&
      InternetAddress.tryParse(address)?.type == InternetAddressType.IPv6) {
    max = 128;
  } else {
    return false;
  }
  if (bits == null) return true;
  if (!RegExp(r'^(0|[1-9]\d{0,2})$').hasMatch(bits)) return false;
  return int.parse(bits) <= max;
}

/// The port box as typed: the value to store ('' for [kDefaultDirectPort]), or null when it is
/// not 1 to 65535 (upstream also took 0 for the default, 02 §1.3.4).
String? parseDirectPort(String text) {
  final t = text.trim();
  if (t.isEmpty) return '';
  if (!RegExp(r'^[1-9]\d{0,4}$').hasMatch(t)) return null;
  return int.parse(t) <= 65535 ? t : null;
}

/// The port direct IP access listens on for the stored value: Rust's `get_direct_port` takes
/// anything not above 0 for the default (an old '0' included).
int directPort(String stored) {
  final p = int.tryParse(stored) ?? 0;
  return p > 0 ? p : kDefaultDirectPort;
}
