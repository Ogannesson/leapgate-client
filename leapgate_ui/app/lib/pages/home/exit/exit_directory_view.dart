import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/exit_api.dart';
import 'package:flutter_hbb/leapgate/exit_directory.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_device.dart';
import '../account/account.dart' show showLoginDialog;

// "Available exit nodes" (01 P1 block I): the directory's five states and its rows. Placeholder
// layout until designer's rows and loading bar (`LEAPGATE.md` §10.12 "组件").

class ExitDirectoryView extends StatelessWidget {
  const ExitDirectoryView({
    super.key,
    required this.overlays,
    required this.onUse,
    required this.onShow,
  });

  final TabOverlays overlays;

  /// "Use" on a row.
  final void Function(ExitNode node) onUse;

  /// "In use" on a row: scroll to its card.
  final void Function(String id) onShow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final directory = appCore.exitDirectory;
    return ListenableBuilder(
      listenable: Listenable.merge([
        directory,
        appCore.account,
        appCore.exitNodes,
      ]),
      builder: (context, _) => switch (directory.state) {
        ExitDirectoryState.loading => const LinearProgressIndicator(),
        ExitDirectoryState.unsupported => LgEmptyState(
          l10n.exitDirUnsupported,
          icon: LgIcons.exit,
        ),
        ExitDirectoryState.notLoggedIn => LgEmptyState(
          l10n.exitDirSignedOut,
          icon: LgIcons.exit,
          actionLabel: l10n.abSignIn,
          actionIcon: LgIcons.login,
          onAction: () => showLoginDialog(overlays),
        ),
        ExitDirectoryState.empty => LgEmptyState(
          l10n.exitDirEmpty,
          icon: LgIcons.exit,
        ),
        ExitDirectoryState.error => LgEmptyState(
          l10n.exitDirError,
          icon: LgIcons.exit,
          actionLabel: l10n.connRetry,
          onAction: directory.load,
        ),
        ExitDirectoryState.ok => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final node in directory.exits) _row(context, l10n, node),
          ],
        ),
      },
    );
  }

  Widget _row(BuildContext context, AppLocalizations l10n, ExitNode node) {
    final t = LgTokens.of(context);
    // Whatever state its card is in (08 §8).
    final inUse = appCore.exitNodes.cardOf(node.id) != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LgSpace.s1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              node.hostname.isEmpty ? node.id : node.hostname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.text,
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(formatPeerId(node.id), style: t.textS),
          ),
          SizedBox(
            width: 160,
            child: Text(
              node.own
                  ? l10n.exitMine
                  : node.owner.isEmpty
                  ? ''
                  : l10n.exitOwner(node.owner),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textS,
            ),
          ),
          LgButton(
            label: inUse ? l10n.exitUsing : l10n.exitUse,
            kind: inUse ? LgButtonKind.secondary : LgButtonKind.primary,
            onPressed: () => inUse ? onShow(node.id) : onUse(node),
          ),
        ],
      ),
    );
  }
}
