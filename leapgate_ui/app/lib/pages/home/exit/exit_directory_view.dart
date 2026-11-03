import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/exit_api.dart';
import 'package:flutter_hbb/leapgate/exit_directory.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;

import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_device.dart';
import '../../../widgets/lg_exit_page.dart';
import '../account/account.dart' show showLoginDialog;

// "Available exit nodes" (01 P1 block I): the directory's states and rows, drawn by
// [LgExitDirectory] (`LEAPGATE.md` §10.12 "组件接口").

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
        ExitDirectoryState.loading => LgExitDirectory.loading(
          semanticLabel: l10n.exitDirLoading,
        ),
        ExitDirectoryState.unsupported => LgExitDirectory.unsupported(
          text: l10n.exitDirUnsupported,
        ),
        ExitDirectoryState.notLoggedIn => LgExitDirectory.notLoggedIn(
          text: l10n.exitDirSignedOut,
          actionLabel: l10n.abSignIn,
          onAction: () => showLoginDialog(overlays),
        ),
        ExitDirectoryState.empty => LgExitDirectory.empty(
          text: l10n.exitDirEmpty,
        ),
        ExitDirectoryState.error => LgExitDirectory.error(
          text: l10n.exitDirError,
          actionLabel: l10n.connRetry,
          onAction: directory.load,
        ),
        ExitDirectoryState.ok => LgExitDirectory.rows(
          entries: [for (final node in directory.exits) _entry(l10n, node)],
        ),
      },
    );
  }

  LgExitEntry _entry(AppLocalizations l10n, ExitNode node) {
    // Whatever state its card is in (08 §8).
    final inUse = appCore.exitNodes.cardOf(node.id) != null;
    return LgExitEntry(
      name: node.hostname.isEmpty ? formatPeerId(node.id) : node.hostname,
      id: formatPeerId(node.id),
      // The directory lists exit nodes, which are Windows devices.
      platform: LgPlatform.windows,
      owner: node.own
          ? l10n.exitMine
          : node.owner.isEmpty
          ? ''
          : l10n.exitOwner(node.owner),
      actionLabel: inUse ? l10n.exitUsing : l10n.exitUse,
      inUse: inUse,
      onPressed: () => inUse ? onShow(node.id) : onUse(node),
    );
  }
}
