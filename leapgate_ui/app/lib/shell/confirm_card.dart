import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/lg_tokens.dart';
import '../widgets/lg_button.dart';

/// A button of [ConfirmCard].
class ConfirmAction {
  const ConfirmAction(this.label, this.onPressed,
      {this.kind = LgButtonKind.secondary});

  final String label;
  final VoidCallback onPressed;
  final LgButtonKind kind;
}

/// Placeholder for the small confirmation dialog (`LgConfirmDialog`, `p1-close-sessions`,
/// `g-close`) until the designer's component replaces it: a question, optional text and
/// controls, and buttons. Enter runs [defaultAction], Esc runs [onCancel].
class ConfirmCard extends StatelessWidget {
  const ConfirmCard({
    super.key,
    required this.title,
    this.body,
    this.controls = const [],
    required this.actions,
    required this.defaultAction,
    required this.onCancel,
  });

  final String title;
  final String? body;
  final List<Widget> controls;
  final List<ConfirmAction> actions;
  final ConfirmAction defaultAction;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter):
            defaultAction.onPressed,
        const SingleActivator(LogicalKeyboardKey.escape): onCancel,
      },
      child: FocusScope(
        autofocus: true,
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(LgSpace.s6),
          decoration: BoxDecoration(
            color: t.colors.surface,
            borderRadius: BorderRadius.circular(LgRadius.r10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title,
                    style: t.text.copyWith(
                        color: t.colors.text, fontWeight: FontWeight.w700)),
              ),
              if (body != null) ...[
                const SizedBox(height: LgSpace.s3),
                Text(body!, style: t.text.copyWith(color: t.colors.text2)),
              ],
              for (final c in controls) ...[
                const SizedBox(height: LgSpace.s3),
                c,
              ],
              const SizedBox(height: LgSpace.s6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final (i, a) in actions.indexed) ...[
                    if (i > 0) const SizedBox(width: LgSpace.s2),
                    LgButton(label: a.label, kind: a.kind, onPressed: a.onPressed),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
