import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../../l10n/app_localizations.dart';
import '../../shell/tab_overlays.dart';
import '../../widgets/lg_session_toolbar.dart';
import '../../widgets/lg_status.dart';
import '../../widgets/lg_tooltip.dart';
import 'session_names.dart';

/// The toolbar's connection mark (01 P2 block B, item 10), or null until the connection is
/// ready. The toolbar only places it; the connection details (01 §4.2) open from it (M2b,
/// `LEAPGATE.md` §10.9).
Widget? sessionRouteMark(BuildContext context, FFI ffi, TabOverlays overlays) {
  final conn = ffi.connection;
  if (!showsRoute(conn)) return null;
  final l10n = AppLocalizations.of(context)!;
  final direct = conn.direct == true;
  final encrypted = conn.secure != false;
  final routeLabel = direct ? l10n.sessionDirect : l10n.sessionRelayed;
  final routeTip = direct ? l10n.sessionDirectTip : l10n.sessionRelayedTip;
  return LgTooltip(
    message: encrypted ? routeTip : '$routeTip\n${l10n.sessionUnencryptedTip}',
    child: LgToolbarStatus(
      child: LgRouteMark(
        route: direct ? LgRoute.direct : LgRoute.relay,
        label: routeLabel,
        encrypted: encrypted,
        unencryptedLabel: l10n.sessionUnencrypted,
      ),
    ),
  );
}
