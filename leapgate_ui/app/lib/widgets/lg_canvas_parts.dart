// What floats over the remote picture besides the toolbar and the notices
// (01 §3.2 block C; `det-session`, `x-rel` in A-P2.html): the quality figures
// at the top left, the hint of relative mouse mode at the top centre, and the
// navigation bar of an Android device. They only draw; the caller places them
// (each as a `Positioned` of its own, with no ground around it, so that the
// rest of the picture still gets the pointer).

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';
import 'lg_tooltip.dart';

/// The quality figures over the picture (`.qd`): a name and its value on each
/// line, the values right aligned. Rows are the caller's, already written with
/// their units ("速度", "1.2 MB/s").
class LgQualityOverlay extends StatelessWidget {
  const LgQualityOverlay({super.key, required this.rows, this.semanticLabel});

  final List<(String, String)> rows;

  /// Name of the figures for a screen reader ("质量数据").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LgSpace.s4,
          vertical: LgSpace.s3,
        ),
        decoration: BoxDecoration(
          color: c.float,
          borderRadius: BorderRadius.circular(LgRadius.r12),
          boxShadow: c.shadow,
        ),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          columnWidths: const {1: IntrinsicColumnWidth()},
          children: [
            for (final (name, value) in rows)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: LgSpace.s5),
                    child: Text(name, style: t.textS.copyWith(color: c.text2)),
                  ),
                  Text(
                    value,
                    textAlign: TextAlign.right,
                    style: t.textS.copyWith(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A short instruction as a pill over the picture (`.lock`): an icon and one
/// line in bold ("按 Ctrl+Alt 退出鼠标锁定" in relative mouse mode, while the
/// toolbar is hidden). Announced to a screen reader when it shows.
class LgCanvasHint extends StatelessWidget {
  const LgCanvasHint({super.key, required this.text, this.icon = LgIcons.mouse});

  final String text;
  final LgIcons icon;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: Container(
          height: t.sizes.button,
          padding: const EdgeInsets.symmetric(horizontal: LgSpace.s5),
          decoration: BoxDecoration(
            color: c.float,
            borderRadius: BorderRadius.circular(LgRadius.r20),
            boxShadow: c.shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LgIcon(icon, size: t.sizes.icon, color: c.accent),
              const SizedBox(width: LgSpace.s3),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: t.text.copyWith(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three navigation keys of an Android device (back, home, recent tasks) on
/// a bar that floats over the picture. The grip at its start moves it: [onDrag]
/// gets how far the pointer moved.
class LgAndroidNavBar extends StatelessWidget {
  const LgAndroidNavBar({
    super.key,
    required this.backLabel,
    required this.homeLabel,
    required this.recentsLabel,
    required this.dragLabel,
    required this.onBack,
    required this.onHome,
    required this.onRecents,
    this.onDrag,
  });

  final String backLabel;
  final String homeLabel;
  final String recentsLabel;

  /// Name of the grip ("移动导航键").
  final String dragLabel;
  final VoidCallback? onBack;
  final VoidCallback? onHome;
  final VoidCallback? onRecents;
  final ValueChanged<Offset>? onDrag;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    Widget key(LgIcons icon, String label, VoidCallback? onPressed) {
      final radius = BorderRadius.circular(LgRadius.r12);
      return LgTooltip(
        message: label,
        child: LgPressable(
          onPressed: onPressed,
          semanticLabel: label,
          builder: (context, states) => LgFocusRing(
            show: states.contains(WidgetState.focused),
            radius: radius,
            child: Container(
              width: t.sizes.tool,
              height: t.sizes.tool,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: lgStateOverlay(c, states),
                borderRadius: radius,
              ),
              child: ExcludeSemantics(
                child: LgIcon(icon, size: t.sizes.icon, color: c.text),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.all(LgSpace.s1),
        decoration: BoxDecoration(
          color: c.float,
          borderRadius: BorderRadius.circular(LgRadius.r16),
          boxShadow: c.shadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LgTooltip(
              message: dragLabel,
              child: Semantics(
                label: dragLabel,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: onDrag == null ? null : (d) => onDrag!(d.delta),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: Container(
                      width: t.sizes.tool - LgSpace.s2,
                      height: t.sizes.tool,
                      alignment: Alignment.center,
                      child: ExcludeSemantics(
                        child: LgIcon(
                          LgIcons.grip,
                          size: t.sizes.icon,
                          color: c.text2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            key(LgIcons.navBack, backLabel, onBack),
            const SizedBox(width: 2),
            key(LgIcons.navHome, homeLabel, onHome),
            const SizedBox(width: 2),
            key(LgIcons.navRecents, recentsLabel, onRecents),
          ],
        ),
      ),
    );
  }
}
