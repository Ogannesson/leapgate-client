import 'package:flutter_hbb/common.dart';

import '../l10n/app_localizations.dart';

/// Toast keys of the app's own messages; the models' keys are upstream's translation keys.
const kToastDirectEstablished = 'leapgate-direct-established';
const kToastRelayEstablished = 'leapgate-relay-established';

/// The text of the global toast (01 §4.5 level 3) for [key]; null when there is none. Keys
/// without copy here (the models' relative mouse ones) keep upstream's text.
String? toastText(AppLocalizations l10n, String? key) => switch (key) {
      null => null,
      'Copied' => l10n.sessionToastCopied,
      kToastDirectEstablished => l10n.sessionDirectEstablished,
      kToastRelayEstablished => l10n.sessionRelayEstablished,
      // The device actions of the home page; the keys are the ARB keys.
      'peersToastAddedFavorites' => l10n.peersToastAddedFavorites,
      'peersToastRemovedFavorites' => l10n.peersToastRemovedFavorites,
      'peersToastDeleted' => l10n.peersToastDeleted,
      'peersToastRemoved' => l10n.peersToastRemoved,
      'peerMenuToastRenamed' => l10n.peerMenuToastRenamed,
      'peerMenuToastPasswordCleared' => l10n.peerMenuToastPasswordCleared,
      'peerMenuToastShortcutCreated' => l10n.peerMenuToastShortcutCreated,
      // The session toolbar's.
      'menuToastWaylandReset' => l10n.menuToastWaylandReset,
      'menuToastWaylandResetFailed' => l10n.menuToastWaylandResetFailed,
      _ => translate(key),
    };
