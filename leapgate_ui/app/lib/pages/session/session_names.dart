import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/session.dart';

/// "直连 / 经中继" shows from "已连接，正在等待画面…" on; before that, password and verifying
/// included, the tab says "正在连接…" (01 P2 block A, §4.1 stage 6).
bool showsRoute(ConnectionModel c) =>
    c.direct != null &&
    (c.stage == ConnStage.waitingForImage || c.stage == ConnStage.connected);

/// Upstream `formatID` (`flutter/lib/common/formatter/id_formatter.dart:36-56`): a numeric ID in
/// groups of three, a `/r` suffix kept.
String formatId(String id) {
  String id2 = id.replaceAll(' ', '');
  String suffix = '';
  if (id2.endsWith(r'\r') || id2.endsWith(r'/r')) {
    suffix = id2.substring(id2.length - 2, id2.length);
    id2 = id2.substring(0, id2.length - 2);
  }
  if (int.tryParse(id2) == null) return id;
  String newID = '';
  if (id2.length <= 3) {
    newID = id2;
  } else {
    var n = id2.length;
    var a = n % 3 != 0 ? n % 3 : 3;
    newID = id2.substring(0, a);
    for (var i = a; i < n; i += 3) {
      newID += " ${id2.substring(i, i + 3)}";
    }
  }
  return newID + suffix;
}

/// The device's name on its tab, the window title and the connection panel: the alias, the
/// host name once the peer info arrived, or the ID, whichever comes first (as the device list
/// names a device, 01 P1 block F).
String deviceName(FFI ffi) {
  final alias = appCore.options.peer(ffi.id).get('alias');
  if (alias.isNotEmpty) return alias;
  final host = ffi.ffiModel.pi.hostname;
  if (host.isNotEmpty) return host;
  return formatId(ffi.id);
}
