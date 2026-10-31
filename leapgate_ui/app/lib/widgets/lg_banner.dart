// Tones and the banner (`.bnr` in A-基础.html). A state is never told by the
// colour alone: every tone has its own icon and the text says it too (01 §7.1).

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';

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
/// [text]. Used in the connection panel; the lists and the settings use it
/// later.
class LgBanner extends StatelessWidget {
  const LgBanner({
    super.key,
    required this.tone,
    this.title,
    this.text,
    this.icon,
  }) : assert(title != null || text != null);

  final LgTone tone;

  /// Bold first line ("未加密").
  final String? title;

  /// What follows the title, or the whole message.
  final String? text;

  /// Overrides the icon of the tone (a crossed-out signal for a lost
  /// connection).
  final LgIcons? icon;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final bg = switch (tone) {
      LgTone.warning => c.warningBg,
      LgTone.error => c.errorBg,
      _ => c.surface2,
    };
    return Semantics(
      container: true,
      liveRegion: tone == LgTone.error || tone == LgTone.warning,
      child: Container(
        padding: const EdgeInsets.all(LgSpace.s4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(LgRadius.r12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: LgIcon(
                icon ?? lgToneIcon(tone),
                size: 22,
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
                style: t.text.copyWith(color: c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
