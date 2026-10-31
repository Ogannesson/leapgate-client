import 'dart:convert';

import 'package:flutter_hbb/common.dart';

import 'bridge.dart';
import 'session.dart';

/// What Q3's export says about a session's connection (`LEAPGATE.md` §10.4 "Q3 挂钩方案"):
/// the path, the transport and the relay server once connected, or the server's own refusal
/// after a failed attempt. All null for `{}` (not connected yet, reconnecting, or Q3 not there).
class SessionRoute {
  const SessionRoute({this.path, this.transport, this.relay, this.refused});

  factory SessionRoute.parse(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return SessionRoute(
      path: m['path'] as String?,
      transport: m['transport'] as String?,
      relay: m['relay'] as String?,
      refused: m['refused'] as String?,
    );
  }

  /// `lan`, `direct_ip`, `punch_v4`, `punch_v6`, `relay` or `relay_ws`.
  final String? path;

  /// `tcp` or `udp`.
  final String? transport;

  /// The relay server as the server gave it, without the default port.
  final String? relay;

  /// The server's own reason for refusing the connection, as it sent it.
  final String? refused;
}

/// Block 2's `leapgate_session_connection(session_id)`; tests set their own.
String Function(SessionID sessionId) readSessionConnection =
    (id) => lgBind.leapgateSessionConnection(sessionId: id);

/// Block 2's `leapgate_local_display_name()`, the name the remote user sees for this device;
/// tests set their own.
String Function() readLocalDisplayName = () => lgBind.leapgateLocalDisplayName();

/// Read each time it is shown, so a reconnect's new path shows once it is connected again.
SessionRoute sessionRoute(FFI ffi) =>
    SessionRoute.parse(readSessionConnection(ffi.sessionId));

/// Upstream's session toggle for the quality data over the image.
const kToggleShowQualityMonitor = 'show-quality-monitor';

/// Set once the user switched the quality data for this device in the connection details; until
/// then the UI mode decides (02 R2-Q11: on in detail mode).
const kOptionQualityMonitorChosen = 'leapgate-quality-monitor-chosen';

/// Whether the quality data shows over the image (01 §4.2, 02 R2-Q11): the device's own choice
/// once made in the details, before that on in detail mode, or where upstream's toggle is on (set
/// by the old UI).
bool showsQualityMonitor(FFI ffi, {required bool detailMode}) {
  final shown = ffi.qualityMonitorModel.show;
  if (ffi.options.getToggle(kOptionQualityMonitorChosen)) return shown;
  return detailMode || shown;
}

/// The switch in the connection details: keeps upstream's toggle, marks the choice as made.
Future<void> setShowsQualityMonitor(FFI ffi, bool show) async {
  if (ffi.qualityMonitorModel.show != show) {
    await ffi.options.toggle(kToggleShowQualityMonitor);
  }
  await ffi.options.set(kOptionQualityMonitorChosen, 'Y');
  await ffi.qualityMonitorModel.checkShowQualityMonitor(ffi.sessionId);
}
