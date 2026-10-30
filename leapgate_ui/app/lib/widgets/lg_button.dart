import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';
import 'lg_tooltip.dart';

/// Button kinds of `.btn` in A-基础.html: primary (`.pri`), secondary
/// (`.out`), text (`.txt`) and danger (`.dng`). [dangerSolid] is the filled
/// destructive button of a confirmation (`.btn.dngf` in A-P2.html).
enum LgButtonKind { primary, secondary, text, danger, dangerSolid }

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
    this.horizontalPadding,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final LgButtonKind kind;
  final LgIcons? icon;
  final bool large;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Side padding when the 14 px (text buttons 10 px) of `.btn` is not right,
  /// e.g. the 24 px of the buttons in dialogs and panels (`.sheet .btn.h48`).
  final double? horizontalPadding;

  /// The accessible name when it must differ from [label]: two buttons that
  /// both read "复制" next to each other are "复制 ID" and "复制密码" to a
  /// screen reader and to a UI Automation script.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(large ? LgRadius.r12 : LgRadius.r10);
    return LgPressable(
      onPressed: onPressed,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel ?? label,
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
          case LgButtonKind.dangerSolid:
            bg = c.error;
            fg = c.onAccent;
        }
        // Disabled: `.btn.dis` fills primary with the disabled ground; outlined
        // buttons keep the strong border (`.btn.out.dis`) and, like text
        // buttons (`.btn.txt.dis`), drop to 60 % opacity.
        var opacity = 1.0;
        if (disabled) {
          fg = c.text2;
          if (kind == LgButtonKind.primary ||
              kind == LgButtonKind.dangerSolid) {
            bg = c.disabled;
          } else {
            opacity = .6;
            if (border != null) border = c.borderStrong;
          }
        }
        final overlay = lgStateOverlay(c, states);
        final button = LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            height: large ? t.sizes.main : t.sizes.button,
            padding: EdgeInsets.symmetric(
              horizontal:
                  horizontalPadding ?? (kind == LgButtonKind.text ? 10 : 14),
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
              overflow: TextOverflow.ellipsis,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    LgIcon(icon!, size: 20),
                    const SizedBox(width: LgSpace.s2),
                  ],
                  // The name comes from the pressable; the text would read it twice.
                  Flexible(child: ExcludeSemantics(child: Text(label))),
                ],
              ),
            ),
          ),
        );
        return opacity == 1 ? button : Opacity(opacity: opacity, child: button);
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
    this.iconSize,
    this.focusable = true,
    this.insetFocusRing = false,
  });

  final LgIcons icon;

  /// Accessible name, also shown as the hover tooltip.
  final String label;
  final VoidCallback? onPressed;

  /// Defaults to `--lg-h-btn`.
  final double? size;

  /// Defaults to the inline icon size of the mode (20, detail 18).
  final double? iconSize;
  final bool focusable;

  /// See [LgFocusRing.inset].
  final bool insetFocusRing;

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
          inset: insetFocusRing,
          child: Container(
            width: side,
            height: side,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: lgStateOverlay(c, states),
              borderRadius: radius,
            ),
            child: Opacity(
              // `.ib.off`
              opacity: disabled ? .45 : 1,
              child: LgIcon(
                icon,
                size: iconSize ?? t.sizes.icon,
                color: c.text2,
              ),
            ),
          ),
        );
      },
    );
    return LgTooltip(message: label, child: button);
  }
}
