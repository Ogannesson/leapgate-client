// The address book switcher above the device list (01 §3.1 block G; `.bk`,
// `.bksw`, `.bkp` and the drop-down of `p1-ab-switch` in A-P1.html): a button
// with the name of the book on show and a chevron, and beside it, in words, what
// the person may do with this book and whose it is. The drop-down has a search
// field, the books (name, and under it the permission and the owner) and one
// line of explanation at its end.
//
// Only drawing: the books, the texts and what a choice does are the caller's.
// Filtering the list by what is typed in the field is done here, by name.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_menu.dart';
import 'lg_pressable.dart';
import 'lg_text_field.dart';

/// One address book in the drop-down.
@immutable
class LgBook {
  const LgBook({required this.id, required this.name, required this.detail});

  /// What [LgBookSwitcher.onSelect] gets back.
  final String id;
  final String name;

  /// Under the name: "完全控制", "可编辑 · 所有者：张三", "只读 · 所有者：李四".
  final String detail;
}

const double _panelWidth = 340;

// What the drop-down wants under its button before it looks over it: the search
// field, two books and the line at the end; the gap it keeps to the window's
// edge; and the height it has when it cannot tell (the button is not laid out).
const double _wantedRoom = 260;
const double _edge = LgSpace.s2;
const double _tallest = 600;

/// The panel of the drop-down: search field, books, explanation. [LgBookSwitcher]
/// shows it under its button; the gallery draws it in place.
///
/// With [maxHeight] the panel is at most that high: the search field above and
/// the line at the end stay, and the books between them scroll.
class LgBookPanel extends StatefulWidget {
  const LgBookPanel({
    super.key,
    required this.books,
    required this.selectedId,
    required this.onSelect,
    required this.searchController,
    required this.searchPlaceholder,
    required this.noMatchLabel,
    required this.hint,
    this.onSearchChanged,
    this.autofocusSearch = false,
    this.maxHeight,
    this.width = _panelWidth,
  });

  /// The search field takes the keyboard when the panel appears.
  final bool autofocusSearch;

  /// The books to list, already filtered by what is in the search field.
  final List<LgBook> books;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final TextEditingController searchController;
  final ValueChanged<String>? onSearchChanged;
  final String searchPlaceholder;

  /// What the list says when the search finds no book.
  final String noMatchLabel;

  /// The line at the end ("共享地址簿的成员和权限由管理员设置").
  final String hint;

  /// The most the whole panel may take up; null lets it be as high as its books.
  final double? maxHeight;
  final double width;

  @override
  State<LgBookPanel> createState() => _LgBookPanelState();
}

// The panel has 8 px of padding above and under its rows (`.menu`).
const double _panelPadding = LgSpace.s2 * 2;

class _LgBookPanelState extends State<LgBookPanel> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final w = widget;
    final search = Padding(
      padding: const EdgeInsets.fromLTRB(LgSpace.s3, 0, LgSpace.s3, LgSpace.s2),
      child: LgTextField(
        controller: w.searchController,
        placeholder: w.searchPlaceholder,
        semanticLabel: w.searchPlaceholder,
        dense: true,
        autofocus: w.autofocusSearch,
        leading: LgIcon(LgIcons.search, size: 20, color: c.text2),
        onChanged: w.onSearchChanged,
      ),
    );
    final rows = [
      if (w.books.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LgSpace.s4,
            vertical: LgSpace.s3,
          ),
          child: Text(w.noMatchLabel, style: t.text.copyWith(color: c.text2)),
        ),
      for (final book in w.books)
        LgMenuItem(
          label: book.name,
          description: book.detail,
          checked: book.id == w.selectedId,
          // The keyboard stays in the search field while the mouse passes
          // over the rows.
          requestFocusOnHover: false,
          onPressed: () => w.onSelect(book.id),
        ),
    ];
    final hint = Padding(
      // Lined up with the names: the check column (20) and its gap.
      padding: const EdgeInsets.fromLTRB(
        LgSpace.s4 + 20 + LgSpace.s3,
        LgSpace.s2,
        LgSpace.s4,
        LgSpace.s1,
      ),
      child: Text(w.hint, style: t.textS.copyWith(color: c.text2)),
    );
    final max = w.maxHeight;
    if (max == null) {
      return LgMenuPanel(width: w.width, items: [search, ...rows, hint]);
    }
    return LgMenuPanel(
      width: w.width,
      items: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(0, max - _panelPadding),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              Flexible(
                child: Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: rows,
                    ),
                  ),
                ),
              ),
              hint,
            ],
          ),
        ),
      ],
    );
  }
}

/// The switcher: the button, the permission text beside it, [trailing] at the
/// far end (the "更多" menu of the book), and the drop-down.
class LgBookSwitcher extends StatefulWidget {
  const LgBookSwitcher({
    super.key,
    required this.books,
    required this.selectedId,
    required this.onSelect,
    required this.searchPlaceholder,
    required this.noMatchLabel,
    required this.hint,
    this.trailing,
    this.semanticLabel,
    this.focusNode,
  });

  /// Every book, in the order of the list: yours first, the shared ones by name.
  final List<LgBook> books;

  /// The book on show.
  final String selectedId;

  /// A book was picked; the drop-down closes.
  final ValueChanged<String> onSelect;
  final String searchPlaceholder;
  final String noMatchLabel;
  final String hint;

  /// Tools at the end of the row.
  final Widget? trailing;

  /// Name of the button for a screen reader and for a script ("切换地址簿");
  /// the book's own name follows it.
  final String? semanticLabel;
  final FocusNode? focusNode;

  @override
  State<LgBookSwitcher> createState() => _LgBookSwitcherState();
}

class _LgBookSwitcherState extends State<LgBookSwitcher> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _search = TextEditingController();
  FocusNode? _ownNode;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void dispose() {
    _search.dispose();
    _ownNode?.dispose();
    super.dispose();
  }

  void _open() {
    _search.clear();
    setState(_portal.show);
  }

  void _close({bool refocus = true}) {
    if (!_portal.isShowing) return;
    setState(_portal.hide);
    if (refocus) _node.requestFocus();
  }

  void _pick(String id) {
    _close();
    widget.onSelect(id);
  }

  LgBook? get _current =>
      widget.books.where((b) => b.id == widget.selectedId).firstOrNull;

  /// Where the drop-down goes and how high it may be: under the button while
  /// there is room for the search field and a few books, else over it if there
  /// is more room there. Asked again when the window changes size.
  ///
  /// [overlayHeight] is the height the overlay has now, from the constraints
  /// of the layout: the render box of the overlay still has the old height
  /// when the window has just changed.
  ({bool up, double height}) _room(
    BuildContext overlayContext,
    double overlayHeight,
  ) {
    final box = context.findRenderObject();
    final overlay = Overlay.of(overlayContext).context.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        overlay is! RenderBox ||
        !overlayHeight.isFinite) {
      return (up: false, height: _tallest);
    }
    final top = box.localToGlobal(Offset.zero, ancestor: overlay).dy;
    final bottom = top + box.size.height;
    final below = overlayHeight - bottom - LgSpace.s1 - _edge;
    final above = top - LgSpace.s1 - _edge;
    if (below >= _wantedRoom || below >= above) {
      return (up: false, height: math.max(below, 0));
    }
    return (up: true, height: math.max(above, 0));
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final current = _current;
    final radius = BorderRadius.circular(LgRadius.r10);
    final trigger = LgPressable(
      onPressed: () => _portal.isShowing ? _close() : _open(),
      focusNode: _node,
      semanticLabel: [?widget.semanticLabel, ?current?.name].join(': '),
      expanded: _portal.isShowing,
      builder: (context, states) {
        final open = _portal.isShowing || states.contains(WidgetState.selected);
        final fg = open ? c.accent : c.text;
        final overlay = open ? null : lgStateOverlay(c, states);
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            height: t.sizes.button,
            padding: const EdgeInsets.fromLTRB(LgSpace.s4, 0, LgSpace.s3, 0),
            decoration: BoxDecoration(
              color: open
                  ? c.active
                  : overlay == null
                  ? c.surface
                  : Color.alphaBlend(overlay, c.surface),
              borderRadius: radius,
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: open
                  ? Border.all(color: c.accent, width: 2)
                  : Border.all(color: c.borderStrong, width: 1.5),
            ),
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LgIcon(LgIcons.book, size: t.sizes.icon, color: fg),
                  const SizedBox(width: LgSpace.s2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(
                      current?.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: LgSpace.s2),
                  LgIcon(LgIcons.chevD, size: t.sizes.icon, color: fg),
                ],
              ),
            ),
          ),
        );
      },
    );
    return Row(
      children: [
        TapRegion(
          groupId: this,
          onTapOutside: (_) => _close(refocus: false),
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (overlayContext) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final room = _room(overlayContext, constraints.maxHeight);
                  return TapRegion(
                    groupId: this,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: CompositedTransformFollower(
                        link: _link,
                        showWhenUnlinked: false,
                        targetAnchor: room.up
                            ? Alignment.topLeft
                            : Alignment.bottomLeft,
                        followerAnchor: room.up
                            ? Alignment.bottomLeft
                            : Alignment.topLeft,
                        offset: Offset(0, room.up ? -LgSpace.s1 : LgSpace.s1),
                        child: _Drop(
                          switcher: widget,
                          search: _search,
                          onPick: _pick,
                          onClose: _close,
                          maxHeight: room.height,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
            child: CompositedTransformTarget(link: _link, child: trigger),
          ),
        ),
        const SizedBox(width: LgSpace.s3),
        Expanded(
          child: current == null
              ? const SizedBox.shrink()
              : Text(
                  current.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textM.copyWith(color: c.text2),
                ),
        ),
        if (widget.trailing != null) widget.trailing!,
      ],
    );
  }
}

/// The drop-down as the overlay shows it: the panel, with the keys of a list
/// (Up and Down move between the field and the books, Esc closes).
class _Drop extends StatefulWidget {
  const _Drop({
    required this.switcher,
    required this.search,
    required this.onPick,
    required this.onClose,
    required this.maxHeight,
  });

  final LgBookSwitcher switcher;
  final TextEditingController search;
  final ValueChanged<String> onPick;
  final VoidCallback onClose;
  final double maxHeight;

  @override
  State<_Drop> createState() => _DropState();
}

class _DropState extends State<_Drop> {
  // The drop-down's own scope: Up and Down move inside it, never out to the
  // page behind.
  final _scope = FocusScopeNode(debugLabel: 'book switcher');

  @override
  void initState() {
    super.initState();
    widget.search.addListener(_changed);
  }

  @override
  void dispose() {
    widget.search.removeListener(_changed);
    _scope.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final s = widget.switcher;
    final needle = widget.search.text.trim().toLowerCase();
    final shown = [
      for (final b in s.books)
        if (needle.isEmpty || b.name.toLowerCase().contains(needle)) b,
    ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
        const SingleActivator(LogicalKeyboardKey.arrowDown): _scope.nextFocus,
        const SingleActivator(LogicalKeyboardKey.arrowUp): _scope.previousFocus,
      },
      child: FocusScope(
        node: _scope,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: s.semanticLabel,
          child: LgBookPanel(
            books: shown,
            selectedId: s.selectedId,
            onSelect: widget.onPick,
            searchController: widget.search,
            searchPlaceholder: s.searchPlaceholder,
            noMatchLabel: s.noMatchLabel,
            hint: s.hint,
            autofocusSearch: true,
            maxHeight: widget.maxHeight,
          ),
        ),
      ),
    );
  }
}
