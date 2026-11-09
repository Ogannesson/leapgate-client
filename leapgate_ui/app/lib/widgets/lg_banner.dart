// Tones and the banner (`.bnr` in A-基础.html). A state is never told by the
// colour alone: every tone has its own icon and the text says it too (01 §7.1).

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_pressable.dart';
import 'lg_tooltip.dart';

/// What a message is about: information, success, a warning or an error.
enum LgTone { info, success, warning, error }

/// The icon colour of a tone (`.bnr > .ic`, `.toast.ok > .ic`).
Color lgToneColor(LgColors c, LgTone tone) => switch (tone) {
  LgTone.info => c.accent,
  LgTone.success => c.online,
  LgTone.warning => c.warning,
  LgTone.error => c.error,
};

/// The icon of a tone when the message does not bring its own.
LgIcons lgToneIcon(LgTone tone) => switch (tone) {
  LgTone.info => LgIcons.info,
  LgTone.success => LgIcons.checkCircle,
  LgTone.warning => LgIcons.warn,
  LgTone.error => LgIcons.err,
};

/// A message on a tinted ground: an icon, an optional bold [title] and the
/// [text]. Used in the connection panel, the dialogs and above the device
/// list; it may carry one text button ([actionLabel], "重试") and a close
/// button ([onDismiss]).
class LgBanner extends StatelessWidget {
  const LgBanner({
    super.key,
    required this.tone,
    this.title,
    this.text,
    this.icon,
    this.slim = false,
    this.dense = false,
    this.medium = false,
    this.compact = false,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.dismissLabel,
    this.onDismiss,
  }) : assert(title != null || text != null),
       assert(actionLabel == null || onAction != null),
       assert(onDismiss == null || dismissLabel != null);

  final LgTone tone;

  /// Bold first line ("未加密").
  final String? title;

  /// What follows the title, or the whole message.
  final String? text;

  /// Overrides the icon of the tone (a crossed-out signal for a lost
  /// connection).
  final LgIcons? icon;

  /// The `.bnr` of the page and its dialogs: 12 px above and under, the icon
  /// and the text centred on each other. Without it the banner is the roomy
  /// `.bnr.big` of the connection panel (16 px, icon on the first line).
  final bool slim;

  /// The banner of the settings page (`.bnr` in A-P6-设置.html): 8 px above and
  /// under and the medium text, with [slim].
  final bool dense;

  /// The medium text (14/20) without [dense]'s tighter padding: the banners inside the install
  /// dialog (`.ibody .bnr`, `A-P11-安装.html`).
  final bool medium;

  /// The note under one forward of a tunnel card (`.fl-n .bnr`, `A-P8-隧道.html`): 8 px above and
  /// under, 12 at the sides, a 20 px icon and the body text, with [slim].
  final bool compact;

  /// The button at the end ("重试"); [actionIcon] goes before its label.
  final String? actionLabel;
  final VoidCallback? onAction;
  final LgIcons? actionIcon;

  /// The close button at the very end; [dismissLabel] names it ("关闭").
  final String? dismissLabel;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final bg = switch (tone) {
      LgTone.warning => c.warningBg,
      LgTone.error => c.errorBg,
      _ => c.surface2,
    };
    final hasButtons = actionLabel != null || onDismiss != null;
    return Semantics(
      container: true,
      explicitChildNodes: hasButtons,
      liveRegion: tone == LgTone.error || tone == LgTone.warning,
      child: Container(
        padding: slim
            ? EdgeInsets.symmetric(
                horizontal: compact ? LgSpace.s3 : LgSpace.s4,
                vertical: dense || compact ? LgSpace.s2 : LgSpace.s3,
              )
            : const EdgeInsets.all(LgSpace.s4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(LgRadius.r12),
        ),
        child: Row(
          crossAxisAlignment: slim
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: slim ? 0 : 1),
              child: LgIcon(
                icon ?? lgToneIcon(tone),
                size: compact ? 20 : 22,
                color: lgToneColor(c, tone),
              ),
            ),
            const SizedBox(width: LgSpace.s3),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (title != null)
                      TextSpan(
                        text: title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    if (title != null && text != null)
                      const TextSpan(text: '\n'),
                    if (text != null) TextSpan(text: text),
                  ],
                ),
                style: (dense || medium ? t.textM : t.text).copyWith(
                  color: c.text,
                ),
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(width: LgSpace.s3),
              LgButton(
                label: actionLabel!,
                icon: actionIcon,
                kind: LgButtonKind.text,
                horizontalPadding: LgSpace.s2,
                onPressed: onAction,
              ),
            ],
            if (onDismiss != null) ...[
              SizedBox(width: actionLabel != null ? LgSpace.s1 : LgSpace.s3),
              // `.xi`: 28 px, sitting 4 px into the banner's padding.
              Transform.translate(
                offset: const Offset(LgSpace.s1, 0),
                child: _DismissButton(
                  label: dismissLabel!,
                  onPressed: onDismiss!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    const radius = BorderRadius.all(Radius.circular(LgRadius.r6));
    return LgTooltip(
      message: label,
      child: LgPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, states) => LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: lgStateOverlay(c, states),
              borderRadius: radius,
            ),
            child: LgIcon(LgIcons.x, size: 20, color: c.text2),
          ),
        ),
      ),
    );
  }
}
