// Switch, checkbox, radio and segmented control. Disabled controls are drawn
// at 60 % opacity like the settings rows of A-P6-设置.html.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';

const _disabledOpacity = .6;

/// On/off switch (`.sw`): 36×22 pill, 14 px knob.
class LgSwitch extends StatelessWidget {
  const LgSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    const radius = BorderRadius.all(Radius.circular(11));
    return LgPressable(
      onPressed: onChanged == null ? null : () => onChanged!(!value),
      semanticLabel: semanticLabel,
      toggled: value,
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        final track = value ? c.accent : null;
        return Opacity(
          opacity: states.contains(WidgetState.disabled) ? _disabledOpacity : 1,
          child: LgFocusRing(
            show: states.contains(WidgetState.focused),
            radius: radius,
            child: Container(
              width: 36,
              height: 22,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: overlay == null
                    ? track
                    : Color.alphaBlend(overlay, track ?? Colors.transparent),
                borderRadius: radius,
              ),
              foregroundDecoration: value
                  ? null
                  : BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(color: c.borderStrong, width: 1.5),
                    ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 120),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value ? c.onAccent : c.borderStrong,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Checkbox with its label (`.s-ck`, `.cbx`): 20 px box, the label toggles too.
class LgCheckbox extends StatelessWidget {
  const LgCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    const radius = BorderRadius.all(Radius.circular(LgRadius.r6));
    return LgPressable(
      onPressed: onChanged == null ? null : () => onChanged!(!value),
      semanticLabel: label,
      toggled: value,
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        final fill = value ? c.accent : null;
        return Opacity(
          opacity: states.contains(WidgetState.disabled) ? _disabledOpacity : 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LgFocusRing(
                  show: states.contains(WidgetState.focused),
                  radius: radius,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: overlay == null
                          ? fill
                          : Color.alphaBlend(
                              overlay,
                              fill ?? Colors.transparent,
                            ),
                      borderRadius: radius,
                    ),
                    foregroundDecoration: value
                        ? null
                        : BoxDecoration(
                            borderRadius: radius,
                            border: Border.all(
                              color: c.borderStrong,
                              width: 1.5,
                            ),
                          ),
                    child: value
                        ? LgIcon(LgIcons.check, size: 14, color: c.onAccent)
                        : null,
                  ),
                ),
                const SizedBox(width: LgSpace.s3),
                Flexible(
                  child: ExcludeSemantics(
                    child: Text(label, style: t.text.copyWith(color: c.text)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Radio option with its label (`.s-o` / `.s-rb`): 20 px ring; the selected
/// option has a 2 px accent ring, a 10 px dot and a bold label.
class LgRadio<T> extends StatelessWidget {
  const LgRadio({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.label,
    this.description,
  });

  final T value;
  final T? groupValue;
  final ValueChanged<T>? onChanged;
  final String label;

  /// Small explanation under the label (the "quit" choice of the close
  /// question, 01 §8 Q6); read together with the label.
  final String? description;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final on = value == groupValue;
    return LgPressable(
      onPressed: onChanged == null ? null : () => onChanged!(value),
      semanticLabel: description == null ? label : '$label. $description',
      selected: on,
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        return Opacity(
          opacity: states.contains(WidgetState.disabled) ? _disabledOpacity : 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: t.sizes.button),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: description == null
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Padding(
                  // With a description the row is top aligned: centre the
                  // ring on the first line of the label.
                  padding: EdgeInsets.only(
                    top: description == null
                        ? 0
                        : LgSpace.s1 + (t.sizes.lh - 20) / 2,
                  ),
                  child: LgFocusRing(
                    show: states.contains(WidgetState.focused),
                    radius: const BorderRadius.all(Radius.circular(10)),
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: overlay,
                        border: Border.all(
                          color: on ? c.accent : c.borderStrong,
                          width: on ? 2 : 1.5,
                        ),
                      ),
                      child: on
                          ? Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c.accent,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: LgSpace.s3),
                Flexible(
                  child: Padding(
                    padding: description == null
                        ? EdgeInsets.zero
                        : const EdgeInsets.symmetric(vertical: LgSpace.s1),
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: t.text.copyWith(
                              color: c.text,
                              fontWeight: on
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          if (description != null)
                            Text(
                              description!,
                              style: t.textS.copyWith(color: c.text2),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One option of [LgSegmented].
class LgSegment<T> {
  const LgSegment(this.value, this.label);

  final T value;
  final String label;
}

/// Segmented control (`.seg`): options on a surface2 track, the selected one
/// raised on surface in accent bold.
class LgSegmented<T> extends StatelessWidget {
  const LgSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<LgSegment<T>> segments;
  final T selected;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final segRadius = BorderRadius.circular(LgRadius.r10);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(LgRadius.r12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, s) in segments.indexed) ...[
            if (i > 0) const SizedBox(width: 2),
            LgPressable(
              onPressed: onChanged == null ? null : () => onChanged!(s.value),
              semanticLabel: s.label,
              selected: s.value == selected,
              builder: (context, states) {
                final on = s.value == selected;
                final overlay = lgStateOverlay(c, states);
                final bg = on ? c.surface : null;
                final fg = on ? c.accent : c.text2;
                return Opacity(
                  opacity: states.contains(WidgetState.disabled)
                      ? _disabledOpacity
                      : 1,
                  child: LgFocusRing(
                    show: states.contains(WidgetState.focused),
                    radius: segRadius,
                    child: Container(
                      height: t.sizes.button - 4,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: overlay == null
                            ? bg
                            : Color.alphaBlend(
                                overlay,
                                bg ?? Colors.transparent,
                              ),
                        borderRadius: segRadius,
                      ),
                      alignment: Alignment.center,
                      child: ExcludeSemantics(
                        child: Text(
                          s.label,
                          maxLines: 1,
                          softWrap: false,
                          style: t.text.copyWith(
                            color: fg,
                            fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
