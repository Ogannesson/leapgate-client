// Small parts that the device card and the device list row share: the tag chip
// (`.tg`), the mark of a favourite or of a saved password, and the box that
// shows a device is picked in multi-select (`.pick`). They only draw.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_tooltip.dart';

/// A tag of a device: its name and the colour the owner gave it.
@immutable
class LgDeviceTag {
  const LgDeviceTag(this.label, this.color);

  final String label;
  final Color color;
}

/// One tag (`.tg`): a small square of its colour, then the name on a tint of
/// the same colour. The text keeps the body colour, so the contrast does not
/// depend on what colour the owner picked (01 §2.4).
class LgTagChip extends StatelessWidget {
  const LgTagChip(this.tag, {super.key});

  final LgDeviceTag tag;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(
        t.detail ? 5 : 7,
        t.detail ? 0 : 1,
        t.detail ? 6 : 8,
        t.detail ? 0 : 1,
      ),
      decoration: BoxDecoration(
        color: c.tagTint(tag.color),
        borderRadius: BorderRadius.circular(LgRadius.r6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: tag.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            tag.label,
            maxLines: 1,
            softWrap: false,
            style: t.textS.copyWith(color: c.text),
          ),
        ],
      ),
    );
  }
}

/// The tags of a device side by side. What does not fit is cut off at the end
/// (the full list is in the device menu), so a device with many tags never
/// pushes the rest of the row aside.
class LgTagChips extends StatelessWidget {
  const LgTagChips(this.tags, {super.key, this.spacing, this.alignEnd = false});

  final List<LgDeviceTag> tags;

  /// Between two chips; the card uses 10, the list 8 (detail mode 4).
  final double? spacing;

  /// Right aligned, as on a card.
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final gap = spacing ?? (t.detail ? LgSpace.s1 : LgSpace.s2);
    return ClipRect(
      child: Align(
        alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          reverse: alignEnd,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, tag) in tags.indexed) ...[
                if (i > 0) SizedBox(width: gap),
                LgTagChip(tag),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The marks after a device name: a star for a favourite, a key for a saved
/// password. Icons alone say nothing to a screen reader, so the labels also go
/// into the label of the card or row that holds them.
class LgDeviceMarks extends StatelessWidget {
  const LgDeviceMarks({
    super.key,
    required this.favorite,
    required this.savedPassword,
    this.favoriteLabel,
    this.savedPasswordLabel,
  });

  final bool favorite;
  final bool savedPassword;
  final String? favoriteLabel;
  final String? savedPasswordLabel;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    Widget mark(LgIcons icon, String? label) {
      final glyph = LgIcon(icon, size: 16, color: c.text2);
      return label == null ? glyph : LgTooltip(message: label, child: glyph);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (favorite) ...[
          const SizedBox(width: 6),
          mark(LgIcons.star, favoriteLabel),
        ],
        if (savedPassword) ...[
          const SizedBox(width: 6),
          mark(LgIcons.key, savedPasswordLabel),
        ],
      ],
    );
  }
}

/// The 24 px box at the corner of a card or at the start of a row in
/// multi-select (`.pick`): empty ring, or filled with a check mark. The card
/// or row takes the clicks and the focus.
class LgPickBox extends StatelessWidget {
  const LgPickBox({super.key, required this.picked});

  final bool picked;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    const radius = BorderRadius.all(Radius.circular(LgRadius.r6));
    return ExcludeSemantics(
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: picked ? c.accent : null,
          borderRadius: radius,
        ),
        foregroundDecoration: picked
            ? null
            : BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: c.borderStrong, width: 1.5),
              ),
        child: picked
            ? LgIcon(LgIcons.check, size: 16, color: c.onAccent)
            : null,
      ),
    );
  }
}

/// The words a screen reader gets for a device: name, state, ID, user and host,
/// source, tags, marks.
String lgDeviceLabel({
  required String name,
  required String statusLabel,
  required String id,
  String? userHost,
  String? source,
  List<LgDeviceTag> tags = const [],
  bool favorite = false,
  String? favoriteLabel,
  bool savedPassword = false,
  String? savedPasswordLabel,
}) {
  return [
    name,
    if (favorite && favoriteLabel != null) favoriteLabel,
    if (savedPassword && savedPasswordLabel != null) savedPasswordLabel,
    statusLabel,
    id,
    ?userHost,
    ?source,
    for (final tag in tags) tag.label,
  ].join(', ');
}
