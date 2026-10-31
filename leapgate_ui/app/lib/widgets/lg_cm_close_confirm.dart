// The confirmation when the connection manager (CM) window is closed while
// more than one visitor is connected: "断开全部会话？" (01 §3.3, R2-Q16; `.scrim`
// and `.csheet` in A-P3.html). It covers only this window: give it to
// `LgCmFrame.overlay`. The question always appears; it does not follow the main
// window's "close confirmation" option.

import 'package:flutter/material.dart';

import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_default_enter.dart';
import 'lg_feedback.dart';

/// The small card (272 wide) on the dim ground. [actions] are laid in a row
/// the way the mockup does: the first keeps the width of its label, the last
/// takes the rest. Esc calls [onEscape].
class LgCmCloseConfirm extends StatelessWidget {
  const LgCmCloseConfirm({
    super.key,
    required this.title,
    required this.actions,
    this.onEscape,
  }) : assert(actions.length >= 1);

  final String title;
  final List<LgDialogAction> actions;
  final VoidCallback? onEscape;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final defaultAction = actions
        .where((a) => a.isDefault && a.onPressed != null)
        .firstOrNull;
    return LgDialogScrim(
      onEscape: onEscape,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: title,
        child: LgDefaultEnter(
          onEnter: defaultAction?.onPressed,
          child: FocusScope(
            autofocus: true,
            child: SizedBox(
              width: 272,
              child: Container(
                padding: const EdgeInsets.all(LgSpace.s5),
                decoration: BoxDecoration(
                  color: c.float,
                  borderRadius: BorderRadius.circular(LgRadius.r20),
                  boxShadow: c.shadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: t.textN.copyWith(
                          color: c.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: LgSpace.s5),
                    Row(
                      children: [
                        for (final (i, a) in actions.indexed) ...[
                          if (i > 0) const SizedBox(width: LgSpace.s3),
                          if (i == actions.length - 1 && actions.length > 1)
                            Expanded(child: _button(a, defaultAction))
                          else
                            Flexible(child: _button(a, defaultAction)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(LgDialogAction a, LgDialogAction? defaultAction) {
    return LgButton(
      label: a.label,
      semanticLabel: a.semanticLabel,
      kind: a.kind,
      large: true,
      horizontalPadding: LgSpace.s6,
      autofocus: a == defaultAction,
      onPressed: a.onPressed,
    );
  }
}
