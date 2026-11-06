// The list of a pane (02 §2.2 blocks E, F, "键盘"): the column headers (sort, drag the width),
// the rows, selecting with the mouse and the keys (over the filtered list), double click and
// Enter, typing to jump, and rows dragged to the other pane.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/models/file_model.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_file_list.dart';
import '../../widgets/lg_file_pane.dart';
import '../../widgets/lg_menu_items.dart';
import 'drag_drop.dart';
import 'formats.dart';
import 'pane_menus.dart';

/// The type column goes first when the pane is narrower than this (02 §2.2 block E).
const kFileTypeColumnMinPane = 520.0;

/// Typed letters within this long make one prefix (upstream `list_search_action_listener.dart`).
const kTypeAheadWindow = Duration(milliseconds: 1500);

/// "名称" keeps at least this much when the other columns are wide.
const kFileNameColumnMin = 120.0;

/// A row besides its columns: the list's and the row's side padding, the icon and the gap after
/// it (`LgFileRow`).
const _kRowChrome = LgSpace.s2 * 4 + 20 + LgSpace.s3;

/// The gap in front of each column after the name.
const _kColumnGap = LgSpace.s3;

/// The least width of the date, type and size columns, and the most of any.
const _kColumnMins = [
  LgFileColumns.minModified,
  LgFileColumns.minType,
  LgFileColumns.minSize,
];
const _kColumnMax = 400.0;

/// [widths] as they show in a list [width] wide: the date, type (when shown) and size columns
/// shrink together so that "名称" keeps [kFileNameColumnMin]. What is saved stays as it was.
List<double> fitColumns(
  List<double> widths,
  double width, {
  required bool withType,
}) {
  final fixed = widths[0] + (withType ? widths[1] : 0) + widths[2];
  final room =
      width -
      _kRowChrome -
      _kColumnGap * (withType ? 3 : 2) -
      kFileNameColumnMin;
  if (fixed <= room) return widths;
  final scale = room <= 0 ? 0.0 : room / fixed;
  return [for (final w in widths) w * scale];
}

/// The date, type and size columns' widths, from LocalConfig or the defaults.
List<double> _columnWidths() {
  const fallback = LgFileColumns();
  final saved = appCore.options.local
      .get(kOptionFtColumns)
      .split(',')
      .map(double.tryParse)
      .toList();
  if (saved.length != 3 || saved.contains(null)) {
    return [fallback.modified, fallback.type, fallback.size];
  }
  return [
    for (final (i, w) in saved.indexed) w!.clamp(_kColumnMins[i], _kColumnMax),
  ];
}

LgFileColumn _columnOf(FileSortField field) => switch (field) {
  FileSortField.name => LgFileColumn.name,
  FileSortField.modified => LgFileColumn.modified,
  FileSortField.type => LgFileColumn.type,
  FileSortField.size => LgFileColumn.size,
};

FileSortField _fieldOf(LgFileColumn column) => switch (column) {
  LgFileColumn.name => FileSortField.name,
  LgFileColumn.modified => FileSortField.modified,
  LgFileColumn.type => FileSortField.type,
  LgFileColumn.size => FileSortField.size,
};

class FileList extends StatefulWidget {
  const FileList({
    super.key,
    required this.pane,
    required this.other,
    required this.entries,
    required this.focusNode,
    required this.area,
    required this.otherArea,
    required this.onEditPath,
    required this.onFocusSearch,
    required this.onSwitchPane,
    this.placeholder,
  });

  final FilePane pane;
  final FilePane other;

  /// What shows: the pane's entries after the search.
  final List<Entry> entries;
  final FocusNode focusNode;
  final PaneDropArea area;

  /// The other pane's: where rows dragged out of this list would land, for their label.
  final PaneDropArea otherArea;
  final VoidCallback onEditPath;
  final VoidCallback onFocusSearch;

  /// Tab: the other pane's list takes the focus; false when it has none to take it (its first
  /// folder did not open), and the key goes on.
  final bool Function() onSwitchPane;

  /// Under the column headers instead of rows (an empty folder, no match).
  final Widget? placeholder;

  @override
  State<FileList> createState() => _FileListState();
}

class _FileListState extends State<FileList> {
  final _scroll = ScrollController();
  final _body = GlobalKey(debugLabel: 'file rows');
  String? _anchor;
  String? _lead;
  String _shownPath = '';

  // A press on a row of a selection of several: it becomes the only one on release, unless the
  // press started a drag.
  String? _collapseTo;
  var _dragging = false;
  ({String path, DateTime at})? _lastPress;
  var _typed = '';
  DateTime _typedAt = DateTime(0);
  late List<double> _widths = _columnWidths();

  /// A column's width was dragged since the press on the header: saved on its release.
  var _resized = false;

  FilePane get _pane => widget.pane;
  List<Entry> get _entries => widget.entries;

  @override
  void initState() {
    super.initState();
    _shownPath = _pane.path;
    widget.area.rowAt = _rowAt;
    appCore.options.local.listenable(kOptionFtColumns).addListener(_onWidths);
  }

  @override
  void didUpdateWidget(FileList old) {
    super.didUpdateWidget(old);
    if (!identical(old.area, widget.area)) widget.area.rowAt = _rowAt;
    if (_pane.path != _shownPath) {
      _shownPath = _pane.path;
      _anchor = _lead = null;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    if (widget.area.rowAt == _rowAt) widget.area.rowAt = null;
    appCore.options.local
        .listenable(kOptionFtColumns)
        .removeListener(_onWidths);
    _scroll.dispose();
    super.dispose();
  }

  void _onWidths() => setState(() => _widths = _columnWidths());

  double get _rowHeight => LgTokens.of(context).sizes.tableRow;

  Entry? _rowAt(Offset global) {
    final box = _body.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !mounted) return null;
    final local = box.globalToLocal(global);
    if (!(Offset.zero & box.size).contains(local)) return null;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final i = ((local.dy + offset) / _rowHeight).floor();
    return i >= 0 && i < _entries.length ? _entries[i] : null;
  }

  bool _selected(Entry e) => _pane.selection.any((s) => s.path == e.path);

  int _indexOf(String? path) =>
      path == null ? -1 : _entries.indexWhere((e) => e.path == path);

  void _selectRange(int from, int to) {
    final lo = from < to ? from : to, hi = from < to ? to : from;
    _pane.select(_entries.sublist(lo, hi + 1));
  }

  void _ensureVisible(int i) {
    if (!_scroll.hasClients) return;
    final top = i * _rowHeight, bottom = top + _rowHeight;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (bottom > _scroll.offset + view) {
      _scroll.jumpTo(bottom - view);
    }
  }

  /// Double click and Enter: a folder or drive opens, a file goes to the other pane's folder
  /// (R2-Q27).
  void _activate(List<Entry> items) {
    if (items.length == 1 &&
        (items.single.isDirectory || items.single.isDrive)) {
      _pane.openDirectory(items.single.path);
      return;
    }
    final files = items.where((e) => e.isFile).toList();
    if (files.isNotEmpty &&
        files.length == items.length &&
        transferBlocked(AppLocalizations.of(context)!, widget.other) == null) {
      _pane.transfer(files);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _dragging = false;
    _collapseTo = null;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    widget.focusNode.requestFocus();
    final row = _rowAt(event.position);
    final keys = HardwareKeyboard.instance;
    if (row == null) {
      if (!keys.isControlPressed && !keys.isShiftPressed) {
        _pane.select(const []);
      }
      return;
    }
    final now = DateTime.now();
    final last = _lastPress;
    final plain = !keys.isControlPressed && !keys.isShiftPressed;
    _lastPress = plain ? (path: row.path, at: now) : null;
    if (plain &&
        last != null &&
        last.path == row.path &&
        now.difference(last.at) < kDoubleTapTimeout) {
      _lastPress = null;
      _activate([row]);
      return;
    }
    final anchor = _indexOf(_anchor);
    if (keys.isShiftPressed && anchor >= 0) {
      _selectRange(anchor, _indexOf(row.path));
      _lead = row.path;
    } else if (keys.isControlPressed) {
      _pane.select(
        _selected(row)
            ? _pane.selection.where((s) => s.path != row.path)
            : [..._pane.selection, row],
      );
      _anchor = _lead = row.path;
    } else if (_selected(row) && _pane.selection.length > 1) {
      _collapseTo = row.path;
      _anchor = _lead = row.path;
    } else {
      _pane.select([row]);
      _anchor = _lead = row.path;
    }
    setState(() {});
  }

  void _onPointerUp(PointerUpEvent event) {
    final to = _collapseTo;
    _collapseTo = null;
    if (to == null || _dragging) return;
    final i = _indexOf(to);
    if (i >= 0) _pane.select([_entries[i]]);
  }

  void _showMenu(Offset global) {
    final l10n = AppLocalizations.of(context)!;
    final row = _rowAt(global);
    List<Widget> items;
    if (row == null) {
      items = blankMenuItems(l10n, pane: _pane, visible: _entries);
    } else {
      if (!_selected(row)) {
        _pane.select([row]);
        _anchor = _lead = row.path;
      }
      items = entryMenuItems(
        l10n,
        pane: _pane,
        other: widget.other,
        clicked: row,
        selection: _pane.selection,
      );
    }
    showLgMenuAt(context, globalPosition: global, items: items);
  }

  void _move(int to, {required bool extend}) {
    if (_entries.isEmpty) return;
    final next = to.clamp(0, _entries.length - 1);
    final anchor = _indexOf(_anchor);
    if (extend && anchor >= 0) {
      _selectRange(anchor, next);
    } else {
      _pane.select([_entries[next]]);
      _anchor = _entries[next].path;
    }
    _lead = _entries[next].path;
    _ensureVisible(next);
    setState(() {});
  }

  bool _typeAhead(String char) {
    final now = DateTime.now();
    if (now.difference(_typedAt) > kTypeAheadWindow) _typed = '';
    _typedAt = now;
    _typed += char.toLowerCase();
    bool starts(Entry e, String p) => e.name.toLowerCase().startsWith(p);
    final repeated =
        _typed.length > 1 && _typed.split('').every((c) => c == _typed[0]);
    var found = -1;
    if (repeated) {
      final from = _indexOf(_lead);
      for (var k = 1; k <= _entries.length; k++) {
        final i = (from + k) % _entries.length;
        if (starts(_entries[i], _typed[0])) {
          found = i;
          break;
        }
      }
    } else {
      found = _entries.indexWhere((e) => starts(e, _typed));
    }
    if (found < 0) return false;
    _move(found, extend: false);
    return true;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed,
        shift = keys.isShiftPressed,
        alt = keys.isAltPressed,
        meta = keys.isMetaPressed;
    // Each key takes only its own modifiers: anything else (Ctrl+Tab for the tabs, Alt+F4)
    // goes on up.
    final plain = !ctrl && !shift && !alt && !meta;
    final shiftOnly = !ctrl && !alt && !meta;
    final altOnly = alt && !ctrl && !shift && !meta;
    final ctrlOnly = ctrl && !shift && !alt && !meta;
    final key = event.logicalKey;
    final lead = _indexOf(_lead);
    final page = _scroll.hasClients
        ? (_scroll.position.viewportDimension / _rowHeight).floor() - 1
        : 10;
    final step = page < 1 ? 1 : page;
    switch (key) {
      case LogicalKeyboardKey.arrowDown when shiftOnly:
        _move(lead + 1, extend: shift);
      case LogicalKeyboardKey.arrowUp when altOnly:
        if (_pane.canGoUp) _pane.goUp();
      case LogicalKeyboardKey.arrowUp when shiftOnly:
        _move(lead < 0 ? _entries.length - 1 : lead - 1, extend: shift);
      case LogicalKeyboardKey.pageDown when shiftOnly:
        _move(lead + step, extend: shift);
      case LogicalKeyboardKey.pageUp when shiftOnly:
        _move(lead - step, extend: shift);
      case LogicalKeyboardKey.home when shiftOnly:
        _move(0, extend: shift);
      case LogicalKeyboardKey.end when shiftOnly:
        _move(_entries.length - 1, extend: shift);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter
          when plain:
        final sel = _pane.selection;
        if (sel.isNotEmpty) {
          _activate(sel);
        } else if (lead >= 0) {
          _activate([_entries[lead]]);
        }
      case LogicalKeyboardKey.backspace when plain:
        if (_pane.canGoBack) _pane.goBack();
      case LogicalKeyboardKey.arrowLeft when altOnly:
        if (_pane.canGoBack) _pane.goBack();
      // Kept here, as upstream does, so the focus doesn't move to the other pane.
      case LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowRight
          when shiftOnly:
        break;
      case LogicalKeyboardKey.f5 when plain:
        _pane.refresh();
      case LogicalKeyboardKey.keyL when ctrlOnly:
        widget.onEditPath();
      case LogicalKeyboardKey.keyF when ctrlOnly:
        widget.onFocusSearch();
      case LogicalKeyboardKey.keyA when ctrlOnly:
        _pane.select(_entries);
      case LogicalKeyboardKey.keyN when ctrl && shift && !alt && !meta:
        if (!_pane.isThisPc && _pane.path.isNotEmpty) _pane.newFolder();
      case LogicalKeyboardKey.f2 when plain:
        if (_pane.canRename && _pane.selection.length == 1) {
          _pane.rename(_pane.selection.single);
        }
      case LogicalKeyboardKey.delete when plain:
        if (_pane.selection.isNotEmpty) _pane.delete(_pane.selection);
      case LogicalKeyboardKey.tab when shiftOnly:
        return widget.onSwitchPane()
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      default:
        final char = event.character;
        if (ctrl || alt || meta || char == null || char.trim().isEmpty) {
          return KeyEventResult.ignored;
        }
        return _typeAhead(char)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// [delta] is how far the column's left edge moved to the left: it grows by that much.
  void _resize(LgFileColumn column, double delta) {
    final i = switch (column) {
      LgFileColumn.modified => 0,
      LgFileColumn.type => 1,
      LgFileColumn.size => 2,
      LgFileColumn.name => -1,
    };
    if (i < 0) return;
    _resized = true;
    setState(() {
      _widths = [..._widths];
      _widths[i] = (_widths[i] + delta).clamp(_kColumnMins[i], _kColumnMax);
    });
  }

  void _saveWidths() {
    if (!_resized) return;
    _resized = false;
    appCore.options.local.set(
      kOptionFtColumns,
      _widths.map((w) => w.round()).join(','),
    );
  }

  void _sortBy(FileSortField field) {
    final s = _pane.sort;
    _pane.setSort(
      s.field == field
          ? (field: field, ascending: !s.ascending)
          : (field: field, ascending: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final withType = constraints.maxWidth >= kFileTypeColumnMinPane;
        final widths = fitColumns(
          _widths,
          constraints.maxWidth,
          withType: withType,
        );
        final columns = LgFileColumns(
          modified: widths[0],
          type: widths[1],
          size: widths[2],
        );
        final names = {for (final e in _pane.entries) e.name};
        return Focus(
          focusNode: widget.focusNode,
          onKeyEvent: _onKey,
          child: Column(
            children: [
              // The header has no end of a drag: the width is saved when the button goes up.
              Listener(
                onPointerUp: (_) => _saveWidths(),
                onPointerCancel: (_) => _saveWidths(),
                child: LgFileListHeader(
                  labels: LgFileHeaderLabels(
                    name: l10n.filesColName,
                    modified: l10n.filesColModified,
                    type: l10n.filesColType,
                    size: l10n.filesColSize,
                    ascending: l10n.filesSortAscending,
                    descending: l10n.filesSortDescending,
                  ),
                  sortColumn: _columnOf(_pane.sort.field),
                  ascending: _pane.sort.ascending,
                  onSort: (c) => _sortBy(_fieldOf(c)),
                  columns: columns,
                  showType: withType,
                  onResize: _resize,
                ),
              ),
              Expanded(
                child: Listener(
                  onPointerDown: _onPointerDown,
                  onPointerUp: _onPointerUp,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapUp: (d) => _showMenu(d.globalPosition),
                    child: SizedBox.expand(
                      key: _body,
                      child:
                          widget.placeholder ??
                          ValueListenableBuilder<FileDropSpot?>(
                            valueListenable: widget.area.hover,
                            builder: (context, hover, _) => ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.symmetric(
                                horizontal: LgSpace.s2,
                              ),
                              itemExtent: t.sizes.tableRow,
                              itemCount: _entries.length,
                              itemBuilder: (context, i) {
                                final e = _entries[i];
                                bool tinted(Entry x) =>
                                    _selected(x) || hover?.to == x.path;
                                return _row(
                                  l10n,
                                  e,
                                  selected: _selected(e),
                                  lead:
                                      _lead == e.path &&
                                      widget.focusNode.hasFocus,
                                  target: hover?.to == e.path,
                                  partial: isPartialTransfer(e, names),
                                  divider:
                                      i > 0 &&
                                      !tinted(e) &&
                                      !tinted(_entries[i - 1]),
                                  columns: columns,
                                  withType: withType,
                                );
                              },
                            ),
                          ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(
    AppLocalizations l10n,
    Entry e, {
    required bool selected,
    required bool lead,
    required bool target,
    required bool partial,
    required bool divider,
    required LgFileColumns columns,
    required bool withType,
  }) {
    final row = LgFileRow(
      key: e.isDrive ? ValueKey(e.path) : null,
      kind: e.isDrive
          ? LgFileKind.drive
          : e.isDirectory
          ? LgFileKind.folder
          : LgFileKind.file,
      name: e.name,
      modified: e.isDrive ? '' : formatFileDate(e),
      type: fileTypeText(l10n, e, partial: partial),
      size: e.isFile && !e.isLink ? formatFileSize(l10n, e.size) : '',
      columns: columns,
      showType: withType,
      link: e.isLink,
      hidden: e.isHidden,
      selected: selected,
      focused: lead,
      dropTarget: target,
      topDivider: divider,
      // What a click does: this row alone is selected.
      onSemanticTap: () {
        _pane.select([e]);
        _anchor = _lead = e.path;
        setState(() {});
      },
    );
    if (e.isDrive) return row;
    final items = selected ? _pane.selection : [e];
    final upload = _pane.isLocal;
    return Draggable<FileDrag>(
      key: ValueKey(e.path),
      data: FileDrag(_pane, items),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => _dragging = true,
      // The first item's name, the folder it would go into over a folder row, crossed out where
      // it can't land (this pane, "此电脑").
      feedback: ListenableBuilder(
        listenable: Listenable.merge([
          widget.area.hover,
          widget.otherArea.hover,
        ]),
        builder: (context, _) {
          final spot = widget.otherArea.hover.value ?? widget.area.hover.value;
          final into = spot != null && spot.accepted && spot.to != null;
          return LgDragChip(
            label: !into
                ? items.first.name
                : upload
                ? l10n.filesUploadTo(spot.folder)
                : l10n.filesDownloadTo(spot.folder),
            count: items.length,
            rejected: spot != null && !spot.accepted,
          );
        },
      ),
      child: row,
    );
  }
}
