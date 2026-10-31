import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/server_model.dart';

import '../l10n/app_localizations.dart';
import '../widgets/lg_cm_pill.dart';
import 'cm_parts.dart';

/// The collapsed CM: the same window as a strip along the top of the primary display
/// (01 §3.3 "贴边小条", A-P3.html `p3-pill-*`). One visitor: what they are doing once connected
/// (the name alone while waiting or after leaving), the time or the state, and the main button
/// of their state; several: how many are connected and "展开".
class CmStrip extends StatelessWidget {
  const CmStrip({
    super.key,
    required this.clients,
    required this.seconds,
    required this.blocked,
    required this.onExpand,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.onButton,
  });

  final List<Client> clients;

  /// Connected time by connection.
  final Map<int, int> seconds;

  /// A click of the remote user on the button was dropped: the hint replaces the time.
  final bool blocked;
  final VoidCallback onExpand;

  /// The drag follows the cursor on the screen: the pointer's own deltas are in window
  /// coordinates, which move with the window, so the window places the strip itself.
  final VoidCallback onDragStart;
  final VoidCallback onDrag;
  final VoidCallback onDragEnd;

  /// The single visitor's button, already guarded against remote clicks.
  final VoidCallback onButton;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (clients.length == 1) {
      final client = clients.single;
      final connected = client.authorized && !client.disconnected;
      return LgCmPill.single(
        person: cmPillPerson(client),
        title: connected ? cmStripLabel(l10n, client) : client.name,
        time: connected
            ? cmDuration(seconds[client.id] ?? 0)
            : client.disconnected
            ? l10n.cmStatusDisconnected
            : l10n.cmStatusRequesting,
        blockedHint: blocked ? l10n.cmBlockedRemotely : null,
        actionLabel: client.disconnected
            ? l10n.cmClose
            : client.authorized
            ? l10n.cmDisconnect
            : l10n.cmDecline,
        // Only "断开" is the danger kind, as in the full window.
        danger: connected,
        onAction: onButton,
        onRestore: onExpand,
        onStartDrag: onDragStart,
        onDrag: (_) => onDrag(),
        onDragEnd: onDragEnd,
      );
    }
    return LgCmPill.group(
      people: [for (final c in clients) cmPillPerson(c)],
      title: l10n.cmPillSessions(
        clients.where((c) => c.authorized && !c.disconnected).length,
      ),
      actionLabel: l10n.cmExpand,
      onAction: onExpand,
      onRestore: onExpand,
      onStartDrag: onDragStart,
      onDrag: (_) => onDrag(),
      onDragEnd: onDragEnd,
    );
  }
}
