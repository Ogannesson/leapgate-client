// The permissions of a visitor in the connection manager (CM): a switch with
// its words, two to a row (01 §3.3; `.perm-t`, `.perm`, `.pm` in A-P3.html).
// The upstream window shows icons only and hides the names in tooltips.

import 'package:flutter/material.dart';

import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';

// The words are 13 px in both modes and sit 6 px from their switch (the mockup
// has 14 px in the simple mode and 8 px). The window is 320 wide but its
// client area is 304 to 311 once Windows takes its invisible resize border
// (309 at 150 %), which leaves a column 122 to 125 wide: a switch (36), the
// gap and six Chinese characters ("文件复制粘贴", "阻止本地输入") need 36 + 8 + 84
// = 128 at 14 px, so they broke into two lines. At 13 px with a 6 px gap they
// need 36 + 6 + 78 = 120. The 12 px between the columns stays: it has to be
// wider than the gap inside a cell, or a word reads as belonging to the next
// switch.
const double _labelSize = 13;
const double _labelGap = 6;

/// One permission: the words, whether it is granted, and what flips it. A null
/// [onChanged] makes this one item inert.
class LgCmPermission {
  const LgCmPermission({
    required this.label,
    required this.value,
    this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
}

/// "允许对方" and the permission switches in two columns. With [readOnly] (a
/// built-in option forbids changing them here) the whole block is inert and
/// drawn at 60 % like the other disabled controls; the values still show.
class LgCmPermissions extends StatelessWidget {
  const LgCmPermissions({
    super.key,
    required this.title,
    required this.items,
    this.readOnly = false,
  });

  final String title;
  final List<LgCmPermission> items;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final rows = <List<LgCmPermission>>[
      for (var i = 0; i < items.length; i += 2)
        items.sublist(i, i + 2 > items.length ? items.length : i + 2),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: SizedBox(
            height: 18,
            child: Text(
              title,
              style: t.textS.copyWith(
                color: c.text2,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
        for (final row in rows)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _PermissionCell(row[0], readOnly: readOnly)),
                const SizedBox(width: LgSpace.s3),
                Expanded(
                  child: row.length > 1
                      ? _PermissionCell(row[1], readOnly: readOnly)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PermissionCell extends StatelessWidget {
  const _PermissionCell(this.item, {required this.readOnly});

  final LgCmPermission item;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    const radius = BorderRadius.all(Radius.circular(11));
    final onChanged = readOnly ? null : item.onChanged;
    return LgPressable(
      onPressed: onChanged == null ? null : () => onChanged(!item.value),
      semanticLabel: item.label,
      toggled: item.value,
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        final track = item.value ? c.accent : null;
        final cell = ConstrainedBox(
          constraints: BoxConstraints(minHeight: t.sizes.permission),
          child: Row(
            children: [
              LgFocusRing(
                show: states.contains(WidgetState.focused),
                radius: radius,
                child: Container(
                  width: 36,
                  height: 22,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: overlay == null
                        ? track
                        : Color.alphaBlend(
                            overlay,
                            track ?? Colors.transparent,
                          ),
                    borderRadius: radius,
                  ),
                  foregroundDecoration: item.value
                      ? null
                      : BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(color: c.borderStrong, width: 1.5),
                        ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 120),
                    alignment: item.value
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: item.value ? c.onAccent : c.borderStrong,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: _labelGap),
              Expanded(
                child: ExcludeSemantics(
                  // Words that do not fit one line (other languages) go to a
                  // second one; the row grows with them.
                  child: Text(
                    item.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LgTokens.style(
                      _labelSize,
                      t.sizes.lhM,
                    ).copyWith(color: c.text),
                  ),
                ),
              ),
            ],
          ),
        );
        return states.contains(WidgetState.disabled)
            ? Opacity(opacity: .6, child: cell)
            : cell;
      },
    );
  }
}
