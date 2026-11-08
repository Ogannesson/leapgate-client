import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show PeerCategory;
import 'package:flutter_hbb/leapgate/tunnel_api.dart' show TunnelKind;

/// "TCP 隧道" and "RDP" in a device menu, the connect box or a link (13 §1.1.2;
/// `LEAPGATE.md` §10.18): as `useAsExit`, a device with a card of [kind] already is only shown,
/// marked; otherwise the card is made, logs in at once and the exit page shows it. [category]
/// is where the device is listed (the address book's shared password), [password] one given by
/// a link.
// TODO(M9c): coder T builds it as `useAsExit`.
void openTunnel(
  String id,
  TunnelKind kind, {
  String? name,
  PeerCategory? category,
  String password = '',
  bool forceRelay = false,
}) {
  lgBind.leapgateLog(
    level: 3,
    msg: 'leapgate ui: tunnel not opened yet: ${kind.name}',
  );
}
