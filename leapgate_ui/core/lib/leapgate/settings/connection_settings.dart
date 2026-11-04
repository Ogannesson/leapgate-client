// The connection methods section (02 §1.4.1): one switch over upstream's punch options, the wait
// for a direct connection, and the notes on what keeps direct connections from being tried.
import '../../consts.dart';
import '../options.dart';
import 'server_config.dart';
import 'settings_api.dart';

/// "打洞直连" is on when either punch Leapgate's ICE starts on is on (契约 05 F2). Rust gives an
/// unset key its default (`src/common.rs` `get_local_option`).
bool punchOn(OptionScope local) =>
    local.getBool(kOptionEnableIpv6Punch) ||
    local.getBool(kOptionEnableUdpPunch);

/// On writes only IPv6 punch (UDP punch loses the IPv6 address on an original hbbs,
/// architecture §3.8); off writes both.
Future<bool> setPunch(OptionScope local, bool on) async {
  if (on) return local.set(kOptionEnableIpv6Punch, 'Y');
  final ipv6 = await local.set(kOptionEnableIpv6Punch, 'N');
  final udp = await local.set(kOptionEnableUdpPunch, 'N');
  return ipv6 && udp;
}

/// "等待直连的时间" as typed: the value to store ('' for the default 2.5 s), or null when it is
/// not 0.1 to 99.9 with at most one decimal.
String? parseFallbackDelay(String text) {
  final t = text.trim();
  if (t.isEmpty) return '';
  if (!RegExp(r'^\d{1,2}(\.\d)?$').hasMatch(t)) return null;
  return double.parse(t) >= 0.1 ? t : null;
}

/// What keeps some or all direct connections from being tried (02 §1.4.1, the notes at the top
/// of the section).
class ConnectionNotes {
  const ConnectionNotes(
      {this.proxy = false,
      this.webSocket = false,
      this.udpDisabled = false,
      this.keyUnusable = false,
      this.compatServer = false});

  final bool proxy;
  final bool webSocket;
  final bool udpDisabled;

  /// No usable server key: ICE needs one (`src/leapgate_hooks.rs` `get_rs_pk`).
  final bool keyUnusable;

  /// The server doesn't announce `ice` (R2-Q14).
  final bool compatServer;
}

Future<ConnectionNotes> readConnectionNotes(OptionScope config) async {
  final key = settingsApi.keyCheck(config.get(kOptionKey));
  final keySource = key == KeyCheck.empty
      ? (await settingsApi.serverSummary()).keySource
      : null;
  return ConnectionNotes(
    proxy: (await readSocks()).proxy.isNotEmpty,
    webSocket: config.getBool(kOptionAllowWebSocket),
    udpDisabled: config.get(kOptionDisableUdp) == 'Y',
    keyUnusable: key == KeyCheck.invalid || keySource == ServerSource.none,
    compatServer: settingsApi.serverKind() == ServerKind.compat,
  );
}
