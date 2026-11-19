import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show PeerCategory;
import 'package:flutter_hbb/leapgate/tunnel_api.dart' show TunnelKind;

import '../../../shell/navigation.dart';

/// "TCP 隧道" and "RDP" in a device menu, the connect box or a link (13 §1.1.2;
/// `LEAPGATE.md` §10.18): as `useAsExit`, a device with a card of [kind] already is only shown,
/// marked; otherwise the card is made, logs in at once and the exit page shows it. [platform]
/// is the device list's for the card's icon until the remote says its own (empty for a link or
/// a typed ID). [category] is where the device is listed (the address book's shared password),
/// [password] one given by a link. [id] is as typed: spaces and a `/r` suffix (which turns into
/// [forceRelay]) are handled here, as [MainNavigation.connect] does.
void openTunnel(
  String id,
  TunnelKind kind, {
  String? name,
  String platform = '',
  PeerCategory? category,
  String password = '',
  bool forceRelay = false,
}) {
  id = id.replaceAll(' ', '');
  if (id.endsWith('/r')) {
    id = id.substring(0, id.length - 2);
    forceRelay = true;
  }
  if (id.isEmpty) return;
  final had = appCore.tunnels.cardOf(id, kind) != null;
  appCore.tunnels.open(
    id,
    kind,
    name: name,
    platform: platform,
    sharedPassword: category == PeerCategory.addressBook
        ? appCore.addressBook.sharedPasswordOf(id)
        : null,
    password: password,
    forceRelay: forceRelay,
  );
  mainNavigation.showHome();
  exitPageRequests.request(id, highlight: had, tunnel: kind);
}
