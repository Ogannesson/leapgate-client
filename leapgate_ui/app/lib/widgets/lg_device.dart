// Devices in lists: the platform avatar, the list row, the "connect to" row of
// the connection box and the states of the list (empty, loading, no result).
// `.tile`, `.tr`, `.rrow`, `.box` and `.sk` in A-基础.html and A-P1.html.
//
// The components only draw: all text comes from the caller (localised) and
// nothing here knows the session or the peer model (docs LEAPGATE.md §10.8).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_hbb/leapgate/identity_color.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_device_parts.dart';
import 'lg_pressable.dart';
import 'lg_status.dart';
import 'lg_tooltip.dart';

/// Platforms a device can have in the list (01 §3.1 block F: iOS cannot be
/// controlled, so it never appears).
enum LgPlatform { windows, macos, linux, android, unknown }

LgIcons lgPlatformIcon(LgPlatform platform) => switch (platform) {
  LgPlatform.windows => LgIcons.windows,
  LgPlatform.macos => LgIcons.macos,
  LgPlatform.linux => LgIcons.linux,
  LgPlatform.android => LgIcons.android,
  LgPlatform.unknown => LgIcons.monitor,
};

/// The platform icon of a device on its identity colour (01 §2.4): a tile of
/// the identity tint with the icon in the identity ink, or with [tile] false
/// only the icon (the list row of the mockups, `.tr .pf`).
///
/// [id] may be formatted ("123 456 789") or as stored; the colour is the same.
class LgDeviceAvatar extends StatelessWidget {
  const LgDeviceAvatar({
    super.key,
    required this.id,
    required this.platform,
    this.size = 44,
    this.tile = true,
  });

  final String id;
  final LgPlatform platform;

  /// Edge of the tile; with [tile] false the size of the icon.
  final double size;
  final bool tile;

  @override
  Widget build(BuildContext context) {
    final identity = LgTokens.of(
      context,
    ).colors.identity[identityGroup(id.replaceAll(' ', ''))];
    final icon = lgPlatformIcon(platform);
    if (!tile) return LgIcon(icon, size: size, color: identity.ink);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: identity.tint,
        borderRadius: BorderRadius.circular(
          size >= 40 ? LgRadius.r12 : LgRadius.r10,
        ),
      ),
      child: LgIcon(icon, size: size >= 40 ? 24 : 20, color: identity.ink),
    );
  }
}

/// Online state of a device in a list. `querying` is the neutral "still
/// asking" state shown while the first answer is on its way (01 §3.1).
enum LgDeviceStatus { online, offline, querying }

// Column widths of the list: the header and the rows must agree.
const double _statusWidth = 104;
const double _idWidth = 124;
const double _actionWidth = 112;

/// With the "⋯" button after "connect" (the device menu of the device page).
const double _actionWidthMore = 160;

/// The pick box of multi-select in front of the row.
const double _pickWidth = 24;
const double _columnGap = LgSpace.s3;
const int _nameFlex = 16;
const int _hostFlex = 15;
const int _noteFlex = 12;
const int _sourceFlex = 10;

/// Surface the rows (`.tbl`) sit on.
class LgListSurface extends StatelessWidget {
  const LgListSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        LgSpace.s2,
        LgSpace.s1,
        LgSpace.s2,
        LgSpace.s2,
      ),
      decoration: BoxDecoration(
        color: LgTokens.of(context).colors.surface,
        borderRadius: BorderRadius.circular(LgRadius.r16),
      ),
      child: child,
    );
  }
}

/// Column titles above the rows (`.tr.th`). [source] is only passed when the
/// rows carry a source category (search results).
class LgDeviceListHeader extends StatelessWidget {
  const LgDeviceListHeader({
    super.key,
    required this.status,
    required this.name,
    required this.id,
    required this.userHost,
    this.source,
  });

  final String status;
  final String name;
  final String id;
  final String userHost;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final style = t.textS.copyWith(
      color: t.colors.text2,
      fontWeight: FontWeight.w700,
    );
    Widget cell(String text) =>
        Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Container(
      height: t.sizes.button,
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
      child: Row(
        children: [
          SizedBox(width: _statusWidth, child: cell(status)),
          const SizedBox(width: _columnGap),
          Expanded(flex: _nameFlex, child: cell(name)),
          const SizedBox(width: _columnGap),
          SizedBox(width: _idWidth, child: cell(id)),
          const SizedBox(width: _columnGap),
          Expanded(flex: _hostFlex, child: cell(userHost)),
          if (source != null) ...[
            const SizedBox(width: _columnGap),
            Expanded(flex: _sourceFlex, child: cell(source!)),
          ],
          const SizedBox(width: _columnGap),
          const SizedBox(width: _actionWidth),
        ],
      ),
    );
  }
}

/// A column of the list view, in the order the list shows them. [note] is the
/// column of the address book and the team devices, between the user and host
/// and the tags.
enum LgDeviceColumn { status, name, id, userHost, note, tags, source }

/// A column title of [LgDeviceTable]; [sortable] makes it a button.
class LgTableColumn {
  const LgTableColumn(this.column, this.label, {this.sortable = false});

  final LgDeviceColumn column;
  final String label;
  final bool sortable;
}

/// Which column the list is ordered by, and which way.
class LgTableSort {
  const LgTableSort(this.column, {this.ascending = true});

  final LgDeviceColumn column;
  final bool ascending;
}

/// Column titles of the list view (`.tr.th`). The columns are the ones the rows
/// have: [pickColumn] when the rows show the pick box, [moreColumn] when they
/// have a "⋯". A [sortable] title is a button: it calls [onSort] with its
/// column; the sorted one shows an arrow, and its accessible value says which
/// way ([ascendingLabel] / [descendingLabel]).
class LgDeviceTableHeader extends StatelessWidget {
  const LgDeviceTableHeader({
    super.key,
    required this.columns,
    this.sort,
    this.onSort,
    this.pickColumn = false,
    this.moreColumn = false,
    this.ascendingLabel,
    this.descendingLabel,
  });

  final List<LgTableColumn> columns;
  final LgTableSort? sort;
  final ValueChanged<LgDeviceColumn>? onSort;
  final bool pickColumn;
  final bool moreColumn;
  final String? ascendingLabel;
  final String? descendingLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final style = t.textS.copyWith(color: c.text2, fontWeight: FontWeight.w700);
    LgTableColumn? find(LgDeviceColumn column) =>
        columns.where((e) => e.column == column).firstOrNull;

    Widget title(LgTableColumn col) {
      final sorted = sort?.column == col.column;
      final text = Text(
        col.label,
        style: sorted ? style.copyWith(color: c.text) : style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      if (!col.sortable || onSort == null) return text;
      final radius = BorderRadius.circular(LgRadius.r6);
      return Align(
        alignment: Alignment.centerLeft,
        child: LgPressable(
          onPressed: () => onSort!(col.column),
          semanticLabel: col.label,
          builder: (context, states) => Semantics(
            value: !sorted
                ? null
                : (sort!.ascending ? ascendingLabel : descendingLabel),
            child: LgFocusRing(
              show: states.contains(WidgetState.focused),
              radius: radius,
              child: Container(
                height: t.sizes.button - 8,
                padding: const EdgeInsets.symmetric(horizontal: LgSpace.s1),
                decoration: BoxDecoration(
                  color: lgStateOverlay(c, states),
                  borderRadius: radius,
                ),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: text),
                      if (sorted) ...[
                        const SizedBox(width: LgSpace.s1),
                        LgIcon(
                          sort!.ascending ? LgIcons.chevU : LgIcons.chevD,
                          size: 16,
                          color: c.accent,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget cell(LgDeviceColumn column, {double? width, int? flex}) {
      final col = find(column);
      final child = col == null ? const SizedBox.shrink() : title(col);
      return width != null
          ? SizedBox(width: width, child: child)
          : Expanded(flex: flex!, child: child);
    }

    final tail = find(LgDeviceColumn.tags) != null
        ? LgDeviceColumn.tags
        : LgDeviceColumn.source;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        height: t.sizes.button,
        padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
        child: Row(
          children: [
            if (pickColumn) const SizedBox(width: _pickWidth + _columnGap),
            cell(LgDeviceColumn.status, width: _statusWidth),
            const SizedBox(width: _columnGap),
            cell(LgDeviceColumn.name, flex: _nameFlex),
            const SizedBox(width: _columnGap),
            cell(LgDeviceColumn.id, width: _idWidth),
            const SizedBox(width: _columnGap),
            cell(LgDeviceColumn.userHost, flex: _hostFlex),
            if (find(LgDeviceColumn.note) != null) ...[
              const SizedBox(width: _columnGap),
              cell(LgDeviceColumn.note, flex: _noteFlex),
            ],
            if (find(tail) != null) ...[
              const SizedBox(width: _columnGap),
              cell(tail, flex: _sourceFlex),
            ],
            const SizedBox(width: _columnGap),
            SizedBox(width: moreColumn ? _actionWidthMore : _actionWidth),
          ],
        ),
      ),
    );
  }
}

/// The list view of the device page (`.tbl`): the title row and the rows on
/// one surface. The [rows] are `LgDeviceRow`s of the same columns as
/// [columns]; give every row but the first `topDivider: true`, and the first
/// `false`. [footer] goes under the rows ("仅显示前 1000 台设备…").
class LgDeviceTable extends StatelessWidget {
  const LgDeviceTable({
    super.key,
    required this.columns,
    required this.rows,
    this.sort,
    this.onSort,
    this.pickColumn = false,
    this.moreColumn = false,
    this.ascendingLabel,
    this.descendingLabel,
    this.semanticLabel,
  });

  final List<LgTableColumn> columns;
  final List<Widget> rows;
  final LgTableSort? sort;
  final ValueChanged<LgDeviceColumn>? onSort;
  final bool pickColumn;
  final bool moreColumn;
  final String? ascendingLabel;
  final String? descendingLabel;

  /// Name of the list for a screen reader ("最近连接的设备").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: LgListSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LgDeviceTableHeader(
              columns: columns,
              sort: sort,
              onSort: onSort,
              pickColumn: pickColumn,
              moreColumn: moreColumn,
              ascendingLabel: ascendingLabel,
              descendingLabel: descendingLabel,
            ),
            ...rows,
          ],
        ),
      ),
    );
  }
}

/// One device in a list (`.tr`): state, name with the platform icon, ID,
/// `user@host`, and with [source] the category it came from. A click selects
/// ([onTap]), a double click or Enter connects ([onDoubleTap], [onConnect]);
/// while the pointer or the keyboard is on the row the "connect" button of
/// [onConnect] shows at its end. [highlighted] is the row the arrow keys of
/// the connection box moved to.
///
/// The device page's list view adds [tags] (in the column [source] has; give
/// one of them), the marks of a [favorite] and a [savedPassword], the "⋯" of
/// the device menu ([onMore]) and, in multi-select, [picked] (the pick box in
/// front of the row). Every row of one list gives the same optional columns,
/// and the header ([LgDeviceTableHeader]) lists the same ones.
class LgDeviceRow extends StatefulWidget {
  const LgDeviceRow({
    super.key,
    required this.name,
    required this.id,
    required this.platform,
    required this.status,
    required this.statusLabel,
    this.userHost,
    this.note,
    this.source,
    this.tags,
    this.favorite = false,
    this.savedPassword = false,
    this.favoriteLabel,
    this.savedPasswordLabel,
    this.selected = false,
    this.highlighted = false,
    this.picked,
    this.topDivider = true,
    this.onTap,
    this.onDoubleTap,
    this.onConnect,
    this.connectLabel,
    this.onMore,
    this.moreLabel,
    this.onContextMenu,
    this.focusNode,
  }) : assert(onConnect == null || connectLabel != null),
       assert(onMore == null || moreLabel != null),
       assert(source == null || tags == null);

  final String name;

  /// Formatted ID ("123 456 789").
  final String id;
  final LgPlatform platform;
  final LgDeviceStatus status;

  /// "在线", "离线", "正在查询…".
  final String statusLabel;
  final String? userHost;

  /// The cell of the note column. Null means the list has no such column; a
  /// list that has it gives every row a string, empty when the device has no
  /// note.
  final String? note;
  final String? source;
  final List<LgDeviceTag>? tags;
  final bool favorite;
  final bool savedPassword;
  final String? favoriteLabel;
  final String? savedPasswordLabel;
  final bool selected;
  final bool highlighted;

  /// Null outside multi-select.
  final bool? picked;

  /// The 1 px line between rows; the first row of a list leaves it out.
  final bool topDivider;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onConnect;
  final String? connectLabel;
  final VoidCallback? onMore;
  final String? moreLabel;
  final ValueChanged<Offset>? onContextMenu;
  final FocusNode? focusNode;

  @override
  State<LgDeviceRow> createState() => _LgDeviceRowState();
}

class _LgDeviceRowState extends State<LgDeviceRow> {
  static const _doubleClick = Duration(milliseconds: 300);
  Duration? _lastDown;

  // Set by the buttons at the end of the row, which hear the press before the
  // row does: a press on them is not a click on the row.
  bool _onButtons = false;

  // A click selects at once; a second click inside the window is a double
  // click. GestureDetector.onDoubleTap would delay the selection.
  void _onPointerDown(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    if (_onButtons) {
      _onButtons = false;
      _lastDown = null;
      return;
    }
    final last = _lastDown;
    if (last != null && e.timeStamp - last <= _doubleClick) {
      _lastDown = null;
      widget.onDoubleTap?.call();
    } else {
      _lastDown = e.timeStamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r10);
    final label = lgDeviceLabel(
      name: w.name,
      statusLabel: w.statusLabel,
      id: w.id,
      userHost: w.userHost,
      note: w.note,
      source: w.source,
      tags: w.tags ?? const [],
      favorite: w.favorite,
      favoriteLabel: w.favoriteLabel,
      savedPassword: w.savedPassword,
      savedPasswordLabel: w.savedPasswordLabel,
    );
    final row = LgPressable(
      onPressed: w.onTap ?? w.onConnect,
      onActivate: w.onConnect ?? w.onTap,
      onSecondaryTapUp: w.onContextMenu == null
          ? null
          : (d) => w.onContextMenu!(d.globalPosition),
      focusNode: w.focusNode,
      // The row the arrow keys moved to is "selected" for a screen reader too.
      selected: w.selected || w.highlighted || w.picked == true,
      semanticLabel: label,
      builder: (context, states) {
        final hot =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        final focused = states.contains(WidgetState.focused);
        final on = w.selected || w.highlighted || w.picked == true;
        final Color? bg = on ? c.active : (hot ? c.surface2 : null);
        final showButtons = w.picked == null && (hot || focused || on);
        final showConnect = w.onConnect != null && showButtons;
        final showMore = w.onMore != null && showButtons;
        final cellStyle = t.text.copyWith(color: c.text);
        final status = switch (w.status) {
          LgDeviceStatus.online => LgStatus.online,
          LgDeviceStatus.offline => LgStatus.offline,
          LgDeviceStatus.querying => LgStatus.querying,
        };
        return LgFocusRing(
          show: focused,
          radius: radius,
          inset: true,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: t.sizes.tableRow,
                padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
                decoration: BoxDecoration(color: bg, borderRadius: radius),
                foregroundDecoration: w.highlighted
                    ? BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(color: c.accent, width: 2),
                      )
                    : null,
                child: ExcludeSemantics(
                  child: DefaultTextStyle(
                    style: cellStyle,
                    maxLines: 1,
                    child: Row(
                      children: [
                        if (w.picked != null) ...[
                          LgPickBox(picked: w.picked!),
                          const SizedBox(width: _columnGap),
                        ],
                        SizedBox(
                          width: _statusWidth,
                          child: LgStatusText(status, w.statusLabel),
                        ),
                        const SizedBox(width: _columnGap),
                        Expanded(
                          flex: _nameFlex,
                          child: Row(
                            children: [
                              LgDeviceAvatar(
                                id: w.id,
                                platform: w.platform,
                                size: t.sizes.icon,
                                tile: false,
                              ),
                              const SizedBox(width: LgSpace.s2),
                              Flexible(
                                child: LgEllipsisText(
                                  w.name,
                                  style: cellStyle.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              LgDeviceMarks(
                                favorite: w.favorite,
                                savedPassword: w.savedPassword,
                                favoriteLabel: w.favoriteLabel,
                                savedPasswordLabel: w.savedPasswordLabel,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: _columnGap),
                        SizedBox(
                          width: _idWidth,
                          child: Text(
                            w.id,
                            style: cellStyle.copyWith(color: c.text2),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: _columnGap),
                        Expanded(
                          flex: _hostFlex,
                          child: w.userHost == null
                              ? const SizedBox.shrink()
                              : LgEllipsisText(
                                  w.userHost!,
                                  style: cellStyle.copyWith(color: c.text2),
                                ),
                        ),
                        if (w.note != null) ...[
                          const SizedBox(width: _columnGap),
                          Expanded(
                            flex: _noteFlex,
                            child: w.note!.isEmpty
                                ? const SizedBox.shrink()
                                : LgEllipsisText(
                                    w.note!,
                                    style: cellStyle.copyWith(color: c.text2),
                                  ),
                          ),
                        ],
                        if (w.source != null) ...[
                          const SizedBox(width: _columnGap),
                          Expanded(
                            flex: _sourceFlex,
                            child: Text(
                              w.source!,
                              style: cellStyle.copyWith(color: c.text2),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        if (w.tags != null) ...[
                          const SizedBox(width: _columnGap),
                          Expanded(
                            flex: _sourceFlex,
                            child: LgTagChips(w.tags!),
                          ),
                        ],
                        const SizedBox(width: _columnGap),
                        SizedBox(
                          width: w.onMore == null
                              ? _actionWidth
                              : _actionWidthMore,
                          child: showConnect || showMore
                              ? Listener(
                                  onPointerDown: (e) {
                                    if (e.buttons == kPrimaryButton) {
                                      _onButtons = true;
                                    }
                                  },
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (showConnect)
                                        _ConnectButton(
                                          label: w.connectLabel!,
                                          name: w.name,
                                          onPressed: w.onConnect!,
                                        ),
                                      if (showConnect && showMore)
                                        const SizedBox(width: 4),
                                      if (showMore)
                                        _MoreButton(
                                          label: w.moreLabel!,
                                          name: w.name,
                                          onPressed: w.onMore!,
                                        ),
                                    ],
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (w.topDivider && bg == null && !w.highlighted)
                Positioned(
                  left: LgSpace.s2,
                  right: LgSpace.s2,
                  top: -1,
                  height: 1,
                  child: ColoredBox(color: c.border),
                ),
            ],
          ),
        );
      },
    );
    return Listener(
      onPointerDown: _onPointerDown,
      child: w.onConnect == null && w.onMore == null
          ? row
          : Semantics(
              customSemanticsActions: {
                if (w.onConnect != null)
                  CustomSemanticsAction(label: w.connectLabel!): w.onConnect!,
                if (w.onMore != null)
                  CustomSemanticsAction(label: w.moreLabel!): w.onMore!,
              },
              child: row,
            ),
    );
  }
}

/// The "connect" button at the end of a hovered row (`.tr .ra .btn`): out of
/// the Tab order, the row itself takes the keyboard.
class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.label,
    required this.name,
    required this.onPressed,
  });

  final String label;
  final String name;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r10);
    return LgPressable(
      onPressed: onPressed,
      focusable: false,
      semanticLabel: '$label $name',
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        return Container(
          height: t.sizes.tableRow - 4,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: overlay == null
                ? c.accent
                : Color.alphaBlend(overlay, c.accent),
            borderRadius: radius,
          ),
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: t.text.copyWith(
              color: c.onAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}

/// The "⋯" at the end of a hovered row (`.tr .ra .ib`): the device menu.
class _MoreButton extends StatelessWidget {
  const _MoreButton({
    required this.label,
    required this.name,
    required this.onPressed,
  });

  final String label;
  final String name;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r10);
    return LgPressable(
      onPressed: onPressed,
      semanticLabel: '$label $name',
      builder: (context, states) {
        final side = t.sizes.tableRow - 4;
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
            child: LgIcon(LgIcons.more, size: t.sizes.icon, color: c.text2),
          ),
        );
      },
    );
  }
}

/// The first row of the search results, "连接到 ‹输入›" (`.rrow`): connects
/// to what was typed. [text] is the whole line; [emphasis] is the part of it
/// shown bold (the typed input).
class LgConnectToRow extends StatelessWidget {
  const LgConnectToRow({
    super.key,
    required this.text,
    required this.onTap,
    this.emphasis,
    this.highlighted = false,
    this.focusNode,
  });

  final String text;
  final String? emphasis;
  final bool highlighted;
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r12);
    final style = t.text.copyWith(color: c.text);
    final at = emphasis == null || emphasis!.isEmpty
        ? -1
        : text.lastIndexOf(emphasis!);
    return LgPressable(
      onPressed: onTap,
      focusNode: focusNode,
      selected: highlighted,
      semanticLabel: text,
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        final base = highlighted
            ? Color.alphaBlend(c.active, c.surface)
            : c.surface;
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            height: t.sizes.row,
            padding: const EdgeInsets.only(left: LgSpace.s4, right: LgSpace.s2),
            decoration: BoxDecoration(
              color: overlay == null ? base : Color.alphaBlend(overlay, base),
              borderRadius: radius,
            ),
            foregroundDecoration: highlighted
                ? BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: c.accent, width: 2),
                  )
                : null,
            child: ExcludeSemantics(
              child: Row(
                children: [
                  LgIcon(LgIcons.login, size: 20, color: c.accent),
                  const SizedBox(width: LgSpace.s3),
                  Expanded(
                    child: Text.rich(
                      at < 0
                          ? TextSpan(text: text)
                          : TextSpan(
                              children: [
                                TextSpan(text: text.substring(0, at)),
                                TextSpan(
                                  text: emphasis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text: text.substring(at + emphasis!.length),
                                ),
                              ],
                            ),
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Title above a list ("搜索结果", `.rtit`).
class LgSectionTitle extends StatelessWidget {
  const LgSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return SizedBox(
      height: t.sizes.nav,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          header: true,
          child: Text(
            text,
            style: t.text.copyWith(
              color: t.colors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// "未找到匹配的设备" under the "connect to" row (`.nores`).
class LgNoResultsNote extends StatelessWidget {
  const LgNoResultsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
      child: Text(text, style: t.text.copyWith(color: t.colors.text2)),
    );
  }
}

/// A list with nothing in it (`.box`): an icon tile and one sentence. A state
/// that has a way out puts one button under the sentence ([actionLabel], "登录"
/// when the address book needs an account, "重试" when the server could not
/// be reached); [iconColor] tints the tile's icon (the error colour for the
/// network error).
class LgEmptyState extends StatelessWidget {
  const LgEmptyState(
    this.text, {
    super.key,
    this.icon = LgIcons.monitor,
    this.iconColor,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.iconBackground,
  }) : assert(actionLabel == null || onAction != null),
       assert(secondaryActionLabel == null || onSecondaryAction != null),
       assert(secondaryActionLabel == null || actionLabel != null);

  final String text;
  final LgIcons icon;
  final Color? iconColor;

  /// The ground of the icon's tile; the neutral one by default (the error tint for the pane of
  /// a file list that could not be opened).
  final Color? iconBackground;
  final String? actionLabel;
  final LgIcons? actionIcon;
  final VoidCallback? onAction;

  /// A second way out, an outlined button before the main one ("转到主文件夹" before "重试").
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final body = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: LgSpace.s8,
        horizontal: LgSpace.s6,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(LgRadius.r16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBackground ?? c.surface2,
              borderRadius: BorderRadius.circular(LgRadius.r12),
            ),
            child: LgIcon(icon, size: 24, color: iconColor ?? c.text2),
          ),
          const SizedBox(height: LgSpace.s3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: t.text.copyWith(color: c.text),
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: LgSpace.s3),
            // One way out stands in the column as it always did (a label wider than the box is
            // cut by the button). Two share a row, and each may be cut.
            if (secondaryActionLabel == null)
              LgButton(
                label: actionLabel!,
                icon: actionIcon,
                kind: LgButtonKind.primary,
                onPressed: onAction,
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: LgButton(
                      label: secondaryActionLabel!,
                      onPressed: onSecondaryAction,
                    ),
                  ),
                  const SizedBox(width: LgSpace.s2),
                  Flexible(
                    child: LgButton(
                      label: actionLabel!,
                      icon: actionIcon,
                      kind: LgButtonKind.primary,
                      onPressed: onAction,
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
    if (actionLabel != null) {
      // The sentence and the button are two nodes: the button can be found and
      // pressed by its name.
      return Semantics(container: true, explicitChildNodes: true, child: body);
    }
    return Semantics(
      container: true,
      label: text,
      child: ExcludeSemantics(child: body),
    );
  }
}

/// Placeholder rows while the first answer is on its way (`.sk`). Still, so
/// that it does not ask for attention; [semanticLabel] tells a screen reader
/// that the list is loading.
class LgDeviceSkeleton extends StatelessWidget {
  const LgDeviceSkeleton({
    super.key,
    required this.semanticLabel,
    this.rows = 5,
  });

  final String semanticLabel;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    Widget bar(double? width, {double height = 12}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(LgRadius.r6),
      ),
    );
    return Semantics(
      container: true,
      label: semanticLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: LgListSurface(
          child: Column(
            children: [
              for (var i = 0; i < rows; i++)
                Container(
                  height: t.sizes.tableRow,
                  padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: _statusWidth,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: bar(56),
                        ),
                      ),
                      const SizedBox(width: _columnGap),
                      Expanded(
                        flex: _nameFlex,
                        child: Row(
                          children: [
                            bar(t.sizes.icon, height: t.sizes.icon),
                            const SizedBox(width: LgSpace.s2),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: bar(96),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: _columnGap),
                      SizedBox(
                        width: _idWidth,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: bar(84),
                        ),
                      ),
                      const SizedBox(width: _columnGap),
                      Expanded(
                        flex: _hostFlex,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: bar(120),
                        ),
                      ),
                      const SizedBox(width: _columnGap),
                      const SizedBox(width: _actionWidth),
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
