import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';

import '../l10n/app_localizations.dart';
import '../theme/lg_tokens.dart';

/// Toast keys of the app's own messages; the models' keys are upstream's translation keys.
const kToastDirectEstablished = 'leapgate-direct-established';
const kToastRelayEstablished = 'leapgate-relay-established';

/// The global toast (01 §4.5 level 3) at the bottom of the window. Placeholder look until the
/// designer's `LgToast` replaces it.
class ToastView extends StatelessWidget {
  const ToastView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    return ListenableBuilder(
      listenable: appCore.toasts,
      builder: (context, _) {
        final toast = appCore.toasts.current;
        if (toast == null) return const SizedBox.shrink();
        // Keys without copy here (the models' relative mouse ones) keep upstream's text.
        final text = switch (toast.key) {
          'Copied' => l10n.sessionToastCopied,
          kToastDirectEstablished => l10n.sessionDirectEstablished,
          kToastRelayEstablished => l10n.sessionRelayEstablished,
          _ => translate(toast.key),
        };
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: LgSpace.s4, vertical: LgSpace.s2),
          decoration: BoxDecoration(
            color: t.colors.float,
            borderRadius: BorderRadius.circular(LgRadius.r10),
          ),
          child: Semantics(
            liveRegion: true,
            child: Text(text, style: t.text.copyWith(color: t.colors.text)),
          ),
        );
      },
    );
  }
}
