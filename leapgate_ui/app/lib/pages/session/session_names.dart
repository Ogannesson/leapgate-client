import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../../widgets/lg_device.dart';
import '../peer_platform.dart';

/// "直连 / 经中继" shows from "已连接，正在等待画面…" on; before that, password and verifying
/// included, the tab says "正在连接…" (01 P2 block A, §4.1 stage 6).
bool showsRoute(ConnectionModel c) =>
    c.direct != null &&
    (c.stage == ConnStage.waitingForImage || c.stage == ConnStage.connected);

/// The device's name on its tab, the window title and the connection panel: the alias, the
/// host name once the peer info arrived, or the ID, whichever comes first (as the device list
/// names a device, 01 P1 block F).
String deviceName(FFI ffi) {
  final alias = appCore.options.peer(ffi.id).get('alias');
  if (alias.isNotEmpty) return alias;
  final host = ffi.ffiModel.pi.hostname;
  if (host.isNotEmpty) return host;
  return formatPeerId(ffi.id);
}

/// The platform icon of the remote device, from its peer info; unknown before it arrives.
LgPlatform platformOf(FFI ffi) => lgPlatformOf(ffi.ffiModel.pi.platform);
