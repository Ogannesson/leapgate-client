import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/server_model.dart';

import '../l10n/app_localizations.dart';
import '../theme/lg_tokens.dart';
import '../widgets/lg_button.dart';
import 'cm_parts.dart';

/// The collapsed CM: the same window as a strip along the top of the primary display
/// (01 §3.3 "贴边小条", A-P3.html `p3-pill-*`). One visitor: what they are doing, the time and
/// the main button of their state; several: how many and "展开". A click on its blank space
/// expands it; dragging moves it along the top edge.
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
  /// coordinates, which move with the window.
  final VoidCallback onDragStart;
  final VoidCallback onDrag;
  final VoidCallback onDragEnd;

  /// The single visitor's button, already guarded against remote clicks.
  final VoidCallback onButton;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final c = t.colors;
    final single = clients.length == 1 ? clients.single : null;
    // What the visitor is doing only once they are connected; while waiting or after leaving,
    // the second line says which.
    final String first;
    if (single == null) {
      first = l10n.cmPillSessions(
        clients.where((c) => c.authorized && !c.disconnected).length,
      );
    } else if (single.authorized && !single.disconnected) {
      first = cmStripLabel(l10n, single);
    } else {
      first = single.name;
    }
    String? second;
    if (single != null) {
      if (blocked) {
        second = l10n.cmBlockedRemotely;
      } else if (!single.authorized) {
        second = l10n.cmStatusRequesting;
      } else if (single.disconnected) {
        second = l10n.cmStatusDisconnected;
      } else {
        second = cmDuration(seconds[single.id] ?? 0);
      }
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onExpand,
      onHorizontalDragStart: (_) => onDragStart(),
      onHorizontalDragUpdate: (_) => onDrag(),
      onHorizontalDragEnd: (_) => onDragEnd(),
      child: Container(
        color: c.surface,
        padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
        child: Row(
          children: [
            for (final client in clients.take(2)) ...[
              CmAvatar(client: client, size: 28),
              const SizedBox(width: LgSpace.s1),
            ],
            const SizedBox(width: LgSpace.s1),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textS.copyWith(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (second != null)
                    Text(
                      second,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textS.copyWith(color: c.text2),
                    ),
                ],
              ),
            ),
            if (single == null)
              LgButton(label: l10n.cmExpand, onPressed: onExpand)
            else if (single.disconnected)
              LgButton(label: l10n.cmClose, onPressed: onButton)
            else if (!single.authorized)
              LgButton(label: l10n.cmDecline, onPressed: onButton)
            else
              LgButton(
                label: l10n.cmDisconnect,
                kind: LgButtonKind.danger,
                onPressed: onButton,
              ),
          ],
        ),
      ),
    );
  }
}
