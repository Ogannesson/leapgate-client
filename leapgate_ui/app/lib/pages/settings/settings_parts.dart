// Placeholder rows of the access, permissions and service sections until designer's settings
// row, small title and choice components replace them at integration (`LEAPGATE.md` §10.13).
// Plain, but found by their text and semantics.

import 'package:flutter/material.dart';

import '../../icons/lg_icon.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_pressable.dart';
import 'settings_registry.dart';

/// One item (02 §1.2.2): name, description, the control beside or [below] them, then the red
/// line of [SettingsSectionContext.errorOf]. Drawn at 60 % when not [enabled]; marked for a
/// while after search or a link opened it.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.ctx,
    required this.id,
    required this.name,
    this.description,
    this.control,
    this.below,
    this.enabled = true,
  });

  final SettingsSectionContext ctx;
  final String id;
  final String name;
  final String? description;
  final Widget? control;
  final Widget? below;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final error = ctx.errorOf(id);
    final marked = ctx.isMarked(id);
    return KeyedSubtree(
      key: ctx.keyOf(id),
      child: Container(
        margin: const EdgeInsets.only(bottom: LgSpace.s2),
        padding: const EdgeInsets.all(LgSpace.s2),
        decoration: BoxDecoration(
          color: marked ? c.accent.withValues(alpha: .08) : null,
          border: Border.all(color: marked ? c.accent : Colors.transparent),
          borderRadius: BorderRadius.circular(LgRadius.r12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: enabled ? 1 : .6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: t.text.copyWith(color: c.text)),
                            if (description != null)
                              Text(
                                description!,
                                style: t.textS.copyWith(color: c.text2),
                              ),
                          ],
                        ),
                      ),
                      if (control != null) ...[
                        const SizedBox(width: LgSpace.s3),
                        control!,
                      ],
                    ],
                  ),
                  if (below != null) ...[
                    const SizedBox(height: LgSpace.s2),
                    below!,
                  ],
                ],
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: LgSpace.s1),
                child: Text(error, style: t.textS.copyWith(color: c.error)),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small title inside a section ("一次性密码"), or the line that says why the items under it
/// don't apply now.
class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {super.key, this.title = false});

  final String text;
  final bool title;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LgSpace.s2,
        LgSpace.s2,
        LgSpace.s2,
        LgSpace.s1,
      ),
      child: Semantics(
        header: title,
        child: Text(
          text,
          style: title
              ? t.textS.copyWith(
                  color: t.colors.text2,
                  fontWeight: FontWeight.w700,
                )
              : t.textS.copyWith(color: t.colors.text2),
        ),
      ),
    );
  }
}

/// Mutually exclusive options (02 §1.2.5: radio or segmented): one row each, or side by side.
/// [onChanged] null greys them.
class SettingsChoice<T> extends StatelessWidget {
  const SettingsChoice({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.horizontal = false,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T>? onChanged;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    final items = [
      for (final (v, label) in options)
        LgPressable(
          onPressed: onChanged == null
              ? null
              : () {
                  if (v != value) onChanged!(v);
                },
          selected: v == value,
          semanticLabel: label,
          builder: (context, states) => Padding(
            padding: const EdgeInsets.symmetric(
              vertical: LgSpace.s1,
              horizontal: LgSpace.s1,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LgIcon(
                  v == value ? LgIcons.markDot : LgIcons.markRing,
                  size: 14,
                  color: v == value ? c.accent : c.text2,
                ),
                const SizedBox(width: LgSpace.s2),
                Text(label, style: TextStyle(color: c.text)),
              ],
            ),
          ),
        ),
    ];
    return horizontal
        ? Wrap(spacing: LgSpace.s3, children: items)
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: items);
  }
}
