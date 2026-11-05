// The file list of a pane (02 §2.2 block E; `.lh`, `.fr`, `.fi`, `.lm` in A-P7-文件传输.html): the
// column header with the sort arrow and the handles that set the widths, and the rows with the
// states a file can be in on screen (selected, keyboard focus, drop target, hidden, a link, a
// leftover of an unfinished transfer). The rows draw and report clicks; selecting, sorting and
// opening are the caller's.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';
import 'lg_tooltip.dart';

enum LgFileKind { folder, file, drive }

enum LgFileColumn { name, modified, type, size }

/// The widths of the three columns after the name, which takes what is left (`--fc`: 140, 104 and
/// 76 to begin with; the handles of the header change them, and the caller keeps them).
@immutable
class LgFileColumns {
  const LgFileColumns({this.modified = 140, this.type = 104, this.size = 76});

  final double modified;
  final double type;
  final double size;

  static const double minModified = 96;
  static const double minType = 64;
  static const double minSize = 56;

  /// The width of [column] after dragging its handle by [delta] to the left (a column grows when
  /// its left edge moves left), within the smallest that still shows a text.
  LgFileColumns resized(LgFileColumn column, double delta) => switch (column) {
    LgFileColumn.modified => LgFileColumns(
      modified: (modified + delta).clamp(minModified, 400),
      type: type,
      size: size,
    ),
    LgFileColumn.type => LgFileColumns(
      modified: modified,
      type: (type + delta).clamp(minType, 400),
      size: size,
    ),
    LgFileColumn.size => LgFileColumns(
      modified: modified,
      type: type,
      size: (size + delta).clamp(minSize, 400),
    ),
    LgFileColumn.name => this,
  };

  @override
  bool operator ==(Object other) =>
      other is LgFileColumns &&
      other.modified == modified &&
      other.type == type &&
      other.size == size;

  @override
  int get hashCode => Object.hash(modified, type, size);
}

const double _gap = LgSpace.s3;

/// The texts of the header besides the column names: what a screen reader says of the column the
/// list is sorted by.
class LgFileHeaderLabels {
  const LgFileHeaderLabels({
    required this.name,
    required this.modified,
    required this.type,
    required this.size,
    required this.ascending,
    required this.descending,
  });

  final String name;
  final String modified;
  final String type;
  final String size;

  /// "升序" / "降序".
  final String ascending;
  final String descending;

  String of(LgFileColumn c) => switch (c) {
    LgFileColumn.name => name,
    LgFileColumn.modified => modified,
    LgFileColumn.type => type,
    LgFileColumn.size => size,
  };
}

/// The header of the list (`.lh`): the four column names, the arrow on the one the list is
/// sorted by, a line under it. A click on a name is [onSort]; the thin handle at the left edge of
/// each column after the name drags its width ([onResize] gets the change to the left, in
/// pixels). With [showType] false the type column is left out (a pane narrower than about 520).
class LgFileListHeader extends StatelessWidget {
  const LgFileListHeader({
    super.key,
    required this.labels,
    required this.sortColumn,
    required this.ascending,
    required this.onSort,
    this.columns = const LgFileColumns(),
    this.showType = true,
    this.onResize,
  });

  final LgFileHeaderLabels labels;
  final LgFileColumn? sortColumn;
  final bool ascending;
  final ValueChanged<LgFileColumn> onSort;
  final LgFileColumns columns;
  final bool showType;
  final void Function(LgFileColumn column, double delta)? onResize;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final shown = <(LgFileColumn, double)>[
      (LgFileColumn.modified, columns.modified),
      if (showType) (LgFileColumn.type, columns.type),
      (LgFileColumn.size, columns.size),
    ];
    Widget cell(LgFileColumn col, {bool end = false}) {
      final sorted = sortColumn == col;
      final name = labels.of(col);
      final text = Text(
        name,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: t.textS.copyWith(color: c.text2, fontWeight: FontWeight.w700),
      );
      return Semantics(
        hint: sorted
            ? (ascending ? labels.ascending : labels.descending)
            : null,
        child: LgPressable(
          onPressed: () => onSort(col),
          semanticLabel: name,
          selected: sorted ? true : null,
          builder: (context, states) {
            const radius = BorderRadius.all(Radius.circular(LgRadius.r6));
            return LgFocusRing(
              show: states.contains(WidgetState.focused),
              radius: radius,
              inset: true,
              child: Container(
                height: t.sizes.menuGroup - 4,
                decoration: BoxDecoration(
                  color: lgStateOverlay(c, states),
                  borderRadius: radius,
                ),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: end
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: [
                      Flexible(child: text),
                      if (sorted) ...[
                        const SizedBox(width: LgSpace.s1),
                        LgIcon(
                          ascending ? LgIcons.chevU : LgIcons.chevD,
                          size: 16,
                          color: c.text2,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    // Right edge of each column's left handle, counted from the right padding.
    var fromRight = LgSpace.s4;
    final handles = <Widget>[];
    for (final (col, w) in shown.reversed) {
      final left = fromRight + w + _gap / 2;
      handles.add(
        Positioned(
          right: left - 6,
          top: 0,
          bottom: 0,
          width: 12,
          child: _ResizeHandle(
            onDelta: onResize == null ? null : (d) => onResize!(col, d),
          ),
        ),
      );
      fromRight += w + _gap;
    }
    return Container(
      height: t.sizes.menuGroup,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: cell(LgFileColumn.name),
                  ),
                ),
                for (final (col, w) in shown) ...[
                  const SizedBox(width: _gap),
                  SizedBox(
                    width: w,
                    child: Align(
                      alignment: col == LgFileColumn.size
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: cell(col, end: col == LgFileColumn.size),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onResize != null) ...handles,
        ],
      ),
    );
  }
}

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.onDelta});

  final ValueChanged<double>? onDelta;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return ExcludeSemantics(
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hot = true),
        onExit: (_) => setState(() => _hot = false),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // A column grows when its left edge moves left: the drag to the left is positive.
          onHorizontalDragUpdate: (d) => widget.onDelta?.call(-d.delta.dx),
          child: Center(
            child: Container(
              width: 1,
              margin: const EdgeInsets.symmetric(vertical: LgSpace.s2),
              color: _hot ? c.borderStrong : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

/// One row (`.fr`). The cells after the name are the formatted texts of the caller. A [link] gets
/// the small chain on its icon; a [hidden] item is drawn at 70 % ("显示隐藏的项目" is on); a row
/// that is [selected] is tinted, one that has the keyboard ([focused]) has the accent frame inside
/// it, and a folder row over which files are dragged ([dropTarget]) has both.
///
/// The row does not handle the pointer. Presses, the Ctrl and Shift keys, double clicks, the
/// right button and drags are the page's, taken once for the whole list (a selection must not
/// wait to see whether a second click follows, and the rows must not each keep a clock of their
/// own). What the row keeps is the hover tint, which is drawing, and the one action a screen
/// reader has for it: [onSemanticTap], "activate", which the page treats as a click on this row.
class LgFileRow extends StatefulWidget {
  const LgFileRow({
    super.key,
    required this.kind,
    required this.name,
    this.modified = '',
    this.type = '',
    this.size = '',
    this.columns = const LgFileColumns(),
    this.showType = true,
    this.link = false,
    this.hidden = false,
    this.selected = false,
    this.focused = false,
    this.dropTarget = false,
    this.topDivider = false,
    this.onSemanticTap,
    this.semanticLabel,
  });

  final LgFileKind kind;
  final String name;
  final String modified;
  final String type;
  final String size;
  final LgFileColumns columns;
  final bool showType;
  final bool link;
  final bool hidden;
  final bool selected;
  final bool focused;
  final bool dropTarget;

  /// The thin line between this row and the one above: drawn where neither row is tinted (the
  /// caller knows its neighbour; a row that is hovered or tinted leaves it out itself).
  final bool topDivider;

  /// The "activate" action of a screen reader (the semantics' tap); null leaves the row with
  /// none.
  final VoidCallback? onSemanticTap;

  /// What a screen reader says; the name, the date modified, the type and the size, one per
  /// line (the ones that are there), when null.
  final String? semanticLabel;

  @override
  State<LgFileRow> createState() => _LgFileRowState();
}

class _LgFileRowState extends State<LgFileRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final w = widget;
    final drop = w.dropTarget;
    final tinted = w.selected || drop;
    // The gallery shows hover with the state forced.
    final hovered =
        _hovered || LgStateOverride.of(context).contains(WidgetState.hovered);
    final bg = tinted ? c.active : (hovered ? c.hover : null);
    final radius = BorderRadius.circular(LgRadius.r10);
    final cells = TextStyle(
      fontSize: t.sizes.fsM,
      height: t.sizes.lhM / t.sizes.fsM,
      color: c.text2,
    );
    Widget cell(String text, double width, {bool end = false}) => SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: end ? TextAlign.right : TextAlign.left,
        style: cells,
      ),
    );
    final iconColor = w.kind == LgFileKind.folder ? c.accent : c.text2;
    final icon = switch (w.kind) {
      LgFileKind.folder => LgIcons.folder,
      LgFileKind.file => LgIcons.file,
      LgFileKind.drive => LgIcons.drive,
    };
    final glyph = SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          LgIcon(icon, size: 20, color: iconColor),
          if (w.link)
            Positioned(
              right: -3,
              bottom: -2,
              child: Container(
                width: 14,
                height: 14,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: w.selected ? c.bg : c.surface,
                  border: Border.all(color: c.text2),
                ),
                child: LgIcon(LgIcons.link, size: 10, color: c.text),
              ),
            ),
        ],
      ),
    );
    final name = Opacity(
      opacity: w.hidden ? .7 : 1,
      child: Row(
        children: [
          glyph,
          const SizedBox(width: _gap),
          Expanded(
            child: LgEllipsisText(
              w.name,
              style: t.text.copyWith(color: c.text),
            ),
          ),
        ],
      ),
    );
    final label =
        w.semanticLabel ??
        [
          w.name,
          w.modified,
          w.type,
          w.size,
        ].where((s) => s.isNotEmpty).join('\n');
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: label,
      button: true,
      selected: w.selected,
      onTap: w.onSemanticTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Container(
          height: t.sizes.tableRow,
          padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
          decoration: BoxDecoration(color: bg, borderRadius: radius),
          foregroundDecoration: w.focused || drop
              ? BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: c.accent, width: 2),
                )
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (w.topDivider && !tinted && !hovered)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 1,
                  child: ColoredBox(color: c.border),
                ),
              Center(
                child: Row(
                  children: [
                    Expanded(child: name),
                    const SizedBox(width: _gap),
                    cell(w.modified, w.columns.modified),
                    if (w.showType) ...[
                      const SizedBox(width: _gap),
                      cell(w.type, w.columns.type),
                    ],
                    const SizedBox(width: _gap),
                    cell(w.size, w.columns.size, end: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
