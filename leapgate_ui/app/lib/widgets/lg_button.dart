import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';
import 'lg_tooltip.dart';

/// Button kinds of `.btn` in A-基础.html: primary (`.pri`), secondary
/// (`.out`), text (`.txt`) and danger (`.dng`).
enum LgButtonKind { primary, secondary, text, danger }

/// A text button, optionally with a leading icon.
///
/// Height is `--lg-h-btn`; [large] uses `--lg-h-main` (`.h48`, dialog and
/// connection panel buttons). Width follows the label: never fixed, because
/// English labels run 1.5-2.5 times longer (01 §7.1).
class LgButton extends StatelessWidget {
  const LgButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = LgButtonKind.secondary,
    this.icon,
    this.large = false,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final LgButtonKind kind;
  final LgIcons? icon;
  final bool large;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(large ? LgRadius.r12 : LgRadius.r10);
    return LgPressable(
      onPressed: onPressed,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: label,
      builder: (context, states) {
        final disabled = states.contains(WidgetState.disabled);
        Color? bg;
        Color fg;
        Color? border;
        switch (kind) {
          case LgButtonKind.primary:
            bg = c.accent;
            fg = c.onAccent;
          case LgButtonKind.secondary:
            fg = c.text;
            border = c.borderStrong;
          case LgButtonKind.text:
            fg = c.accent;
          case LgButtonKind.danger:
            fg = c.error;
            border = c.error;
        }
        if (disabled) {
          // `.btn.dis`; a disabled text button keeps no background.
          bg = kind == LgButtonKind.text ? null : c.disabled;
          fg = c.text2;
          border = null;
        }
        final overlay = lgStateOverlay(c, states);
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            height: large ? t.sizes.main : t.sizes.button,
            padding: EdgeInsets.symmetric(
              horizontal: kind == LgButtonKind.text ? 10 : 14,
            ),
            decoration: BoxDecoration(
              color: overlay == null
                  ? bg
                  : Color.alphaBlend(overlay, bg ?? Colors.transparent),
              borderRadius: radius,
            ),
            // The mockup border is an inset shadow: drawn inside, no layout effect.
            foregroundDecoration: border == null
                ? null
                : BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: border, width: 1.5),
                  ),
            child: DefaultTextStyle(
              style: t.text.copyWith(color: fg, fontWeight: FontWeight.w700),
              maxLines: 1,
              softWrap: false,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    LgIcon(icon!, size: 20),
                    const SizedBox(width: LgSpace.s2),
                  ],
                  Text(label),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Square icon-only button (`.ib`): `--lg-h-btn` square, text2 icon.
class LgIconButton extends StatelessWidget {
  const LgIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size,
    this.iconSize = 20,
    this.color,
    this.focusable = true,
  });

  final LgIcons icon;

  /// Accessible name, also shown as the hover tooltip.
  final String label;
  final VoidCallback? onPressed;

  /// Defaults to `--lg-h-btn`.
  final double? size;
  final double iconSize;
  final Color? color;
  final bool focusable;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final side = size ?? t.sizes.button;
    final radius = BorderRadius.circular(
      side <= 24 ? LgRadius.r6 : LgRadius.r10,
    );
    final button = LgPressable(
      onPressed: onPressed,
      focusable: focusable,
      semanticLabel: label,
      builder: (context, states) {
        final disabled = states.contains(WidgetState.disabled);
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            width: side,
            height: side,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: lgStateOverlay(c, states),
              borderRadius: radius,
            ),
            child: Opacity(
              opacity: disabled ? .6 : 1,
              child: LgIcon(icon, size: iconSize, color: color ?? c.text2),
            ),
          ),
        );
      },
    );
    return LgTooltip(message: label, child: button);
  }
}
