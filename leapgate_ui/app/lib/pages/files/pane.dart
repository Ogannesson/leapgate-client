// One pane of the file transfer view (02 §2.2 blocks B to F): the header, the navigation row
// with the path, the action row with the search, the banner of a folder that did not open, the
// list and its states, the status line, and what a drag over it would do.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/file_model.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_banner.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_device.dart';
import '../../widgets/lg_menu.dart';
import '../../widgets/lg_status.dart';
import '../../widgets/lg_text_field.dart';
import '../../widgets/lg_tooltip.dart';
import '../session/session_names.dart';
import 'breadcrumb.dart';
import 'drag_drop.dart';
import 'file_list.dart';
import 'formats.dart';
import 'pane_menus.dart';

/// "正在读取…" shows once a read takes longer than this (02 §2.2 block E).
const kFileReadingAfter = Duration(milliseconds: 500);

/// Narrower than this, the search field folds into its icon (02 §2.2 block D).
const kFileSearchFoldBelow = 600.0;

/// [entries] whose names hold [query], any case (02 §2.2 block D).
List<Entry> filterEntries(List<Entry> entries, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return entries;
  return entries.where((e) => e.name.toLowerCase().contains(q)).toList();
}

/// The status line: "‹N› 个项目", or what is selected (02 §2.2 block E). A link counts as what
/// it points to.
String statusLine(
  AppLocalizations l10n,
  List<Entry> shown,
  List<Entry> selection,
) {
  if (selection.isEmpty) return l10n.filesItems(shown.length);
  final folders = selection.where((e) => e.isDirectory).length;
  if (folders > 0) {
    return l10n.filesSelectedFolders(selection.length, folders);
  }
  final size = selection.fold<int>(0, (a, e) => a + e.size);
  return l10n.filesSelectedSize(selection.length, formatFileSize(l10n, size));
}

class FilePaneView extends StatefulWidget {
  const FilePaneView({
    super.key,
    required this.ffi,
    required this.pane,
    required this.other,
    required this.area,
    required this.listFocus,
    required this.otherListFocus,
  });

  /// The session, for the remote device's name and platform in the header.
  final FFI ffi;
  final FilePane pane;
  final FilePane other;
  final PaneDropArea area;
  final FocusNode listFocus;
  final FocusNode otherListFocus;

  @override
  State<FilePaneView> createState() => _FilePaneViewState();
}

class _FilePaneViewState extends State<FilePaneView> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'file search');
  final _editingPath = ValueNotifier(false);
  var _searchOpen = false;
  var _shownPath = '';
  Timer? _readingTimer;

  /// The read whose timer ran out (the clock is not read again then).
  DateTime? _readingDue;

  FilePane get _pane => widget.pane;

  @override
  void initState() {
    super.initState();
    _shownPath = _pane.path;
    _pane.addListener(_onPane);
    widget.other.addListener(_onPane);
    _scheduleReading();
  }

  @override
  void didUpdateWidget(FilePaneView old) {
    super.didUpdateWidget(old);
    if (!identical(old.pane, widget.pane)) {
      old.pane.removeListener(_onPane);
      widget.pane.addListener(_onPane);
    }
    if (!identical(old.other, widget.other)) {
      old.other.removeListener(_onPane);
      widget.other.addListener(_onPane);
    }
  }

  @override
  void dispose() {
    _pane.removeListener(_onPane);
    widget.other.removeListener(_onPane);
    _readingTimer?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _editingPath.dispose();
    super.dispose();
  }

  void _onPane() {
    // Another folder clears the search (02 §2.2 block D).
    if (_pane.path != _shownPath) {
      _shownPath = _pane.path;
      _search.clear();
    }
    _scheduleReading();
    setState(() {});
  }

  /// A rebuild when "正在读取…" is due.
  void _scheduleReading() {
    _readingTimer?.cancel();
    final reading = _pane.reading;
    if (reading != null) {
      final left = kFileReadingAfter - DateTime.now().difference(reading.since);
      if (left > Duration.zero) {
        _readingTimer = Timer(left, () {
          if (mounted) setState(() => _readingDue = reading.since);
        });
      }
    }
  }

  bool get _readingShown {
    final r = _pane.reading;
    return r != null &&
        (_readingDue == r.since ||
            DateTime.now().difference(r.since) >= kFileReadingAfter);
  }

  void _focusSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  void _clearSearch() {
    _search.clear();
    _searchOpen = false;
    _searchChanged();
    widget.listFocus.requestFocus();
  }

  /// What is selected may no longer show, and Delete or a drag would act on it unseen.
  void _searchChanged() {
    if (_pane.selection.isNotEmpty) _pane.select(const []);
    setState(() {});
  }

  Widget _header(AppLocalizations l10n, LgTokens t) {
    final ffi = widget.ffi;
    final String title, detail;
    final Widget icon;
    if (_pane.isLocal) {
      title = l10n.filesThisDevice;
      detail = Platform.localHostname;
      icon = LgIcon(LgIcons.monitor, size: 20, color: t.colors.text2);
    } else {
      title = l10n.filesRemoteDevice;
      final platform = platformText(ffi.ffiModel.pi.platform);
      detail = platform.isEmpty
          ? deviceName(ffi)
          : l10n.filesDeviceAndPlatform(deviceName(ffi), platform);
      icon = platform.isEmpty
          ? const SizedBox(width: 20)
          : LgDeviceAvatar(id: ffi.id, platform: platformOf(ffi), size: 20);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LgSpace.s3,
        LgSpace.s2,
        LgSpace.s3,
        LgSpace.s1,
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: LgSpace.s2),
          Semantics(
            header: true,
            child: Text(
              title,
              style: t.text.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: LgSpace.s2),
          Expanded(
            child: LgEllipsisText(
              detail,
              style: t.text.copyWith(color: t.colors.text2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navRow(AppLocalizations l10n) {
    String keyed(String name, String keys) =>
        l10n.filesWithShortcut(name, keys);
    return Row(
      children: [
        LgIconButton(
          icon: LgIcons.arrowL,
          label: keyed(l10n.filesBack, 'Alt+←'),
          onPressed: _pane.canGoBack ? _pane.goBack : null,
        ),
        LgIconButton(
          icon: LgIcons.arrowU,
          label: keyed(l10n.filesUp, 'Alt+↑'),
          onPressed: _pane.canGoUp ? _pane.goUp : null,
        ),
        LgIconButton(
          icon: LgIcons.home,
          label: l10n.filesHome,
          onPressed: _pane.goHome,
        ),
        const SizedBox(width: LgSpace.s1),
        Expanded(
          child: FileBreadcrumb(pane: _pane, editing: _editingPath),
        ),
        LgIconButton(
          icon: LgIcons.refresh,
          label: keyed(l10n.filesRefresh, 'F5'),
          onPressed: _pane.path.isEmpty ? null : _pane.refresh,
        ),
      ],
    );
  }

  Widget _actionRow(AppLocalizations l10n, List<Entry> shown, double width) {
    final blocked = transferBlocked(l10n, widget.other);
    final selection = _pane.selection;
    final target = folderName(l10n, widget.other.path, widget.other.isWindows);
    final upload = _pane.isLocal;
    final transfer = LgButton(
      label: transferLabel(l10n, _pane),
      kind: LgButtonKind.primary,
      icon: upload ? null : LgIcons.arrowL,
      trailingIcon: upload ? LgIcons.arrowR : null,
      onPressed: selection.isEmpty || blocked != null
          ? null
          : () => _pane.transfer(selection),
    );
    final tip =
        blocked ??
        (upload ? l10n.filesUploadTo(target) : l10n.filesDownloadTo(target));
    final fold =
        width < kFileSearchFoldBelow && !_searchOpen && _search.text.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
      child: Row(
        children: [
          // A pane dragged very narrow clips its buttons instead of overflowing.
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  tip.isEmpty
                      ? transfer
                      : LgTooltip(message: tip, child: transfer),
                  const SizedBox(width: LgSpace.s2),
                  LgButton(
                    label: l10n.filesNewFolder,
                    icon: LgIcons.folderPlus,
                    onPressed: _pane.isThisPc || _pane.path.isEmpty
                        ? null
                        : _pane.newFolder,
                  ),
                  const SizedBox(width: LgSpace.s2),
                  LgButton(
                    label: l10n.filesDelete,
                    icon: LgIcons.trash,
                    onPressed: selection.isEmpty
                        ? null
                        : () => _pane.delete(selection),
                  ),
                  LgMenuAnchor(
                    items: moreMenuItems(l10n, pane: _pane, visible: shown),
                    builder: (context, controller) => LgIconButton(
                      icon: LgIcons.more,
                      label: l10n.filesMore,
                      onPressed: () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: LgSpace.s2),
          if (fold)
            LgIconButton(
              icon: LgIcons.search,
              label: l10n.filesSearch,
              onPressed: _focusSearch,
            )
          else
            SizedBox(
              width: 200,
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape):
                      _clearSearch,
                },
                child: LgTextField(
                  controller: _search,
                  focusNode: _searchFocus,
                  dense: true,
                  placeholder: l10n.filesSearch,
                  semanticLabel: l10n.filesSearch,
                  leading: const LgIcon(LgIcons.search, size: 16),
                  trailing: _search.text.isEmpty
                      ? null
                      : LgIconButton(
                          icon: LgIcons.x,
                          label: l10n.filesClearSearch,
                          onPressed: _clearSearch,
                          focusable: false,
                        ),
                  onChanged: (_) => _searchChanged(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The list area: the rows, or what stands in for them.
  Widget _listArea(AppLocalizations l10n, LgTokens t, List<Entry> shown) {
    final error = _pane.openError;
    final reading = _readingShown;
    Widget centered(Widget child) => Center(
      child: Padding(padding: const EdgeInsets.all(LgSpace.s4), child: child),
    );
    final readingNote = centered(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LgSpinner(size: 16),
          const SizedBox(width: LgSpace.s2),
          Text(
            l10n.filesReading,
            style: t.text.copyWith(color: t.colors.text2),
          ),
        ],
      ),
    );
    if (_pane.path.isEmpty) {
      if (error != null) {
        // The first folder did not open: nothing to go back to (02 §2.2 block E).
        return centered(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                openErrorText(l10n, error.path, error.error, _pane.isWindows),
                textAlign: TextAlign.center,
                style: t.text,
              ),
              const SizedBox(height: LgSpace.s3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LgButton(label: l10n.filesGoHome, onPressed: _pane.goHome),
                  const SizedBox(width: LgSpace.s2),
                  LgButton(
                    label: l10n.filesRetry,
                    onPressed: () => _pane.openDirectory(error.path),
                  ),
                ],
              ),
            ],
          ),
        );
      }
      return reading ? readingNote : const SizedBox.expand();
    }
    Widget? placeholder;
    if (shown.isEmpty && !reading) {
      placeholder = centered(
        Text(
          _search.text.trim().isNotEmpty
              ? l10n.filesNoMatch
              : l10n.filesEmptyFolder,
          style: t.text.copyWith(color: t.colors.text2),
        ),
      );
    }
    final elsewhere = reading && _pane.reading!.path != _pane.path;
    final list = FileList(
      pane: _pane,
      other: widget.other,
      entries: shown,
      focusNode: widget.listFocus,
      area: widget.area,
      onEditPath: () => _editingPath.value = true,
      onFocusSearch: _focusSearch,
      onSwitchPane: () {
        // No list there until a folder opened in it.
        if (widget.other.path.isEmpty) return false;
        widget.otherListFocus.requestFocus();
        return true;
      },
      placeholder: placeholder,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: elsewhere,
            child: Opacity(opacity: elsewhere ? 0.4 : 1, child: list),
          ),
        ),
        if (reading) Positioned.fill(child: IgnorePointer(child: readingNote)),
      ],
    );
  }

  Widget _dropOverlay(AppLocalizations l10n, LgTokens t) {
    return ValueListenableBuilder<FileDropSpot?>(
      valueListenable: widget.area.hover,
      builder: (context, spot, _) {
        if (spot == null) return const SizedBox.shrink();
        final c = t.colors;
        final message = !spot.accepted
            ? l10n.filesDropRefused
            : _pane.isLocal
            ? l10n.filesDownloadTo(spot.folder)
            : l10n.filesUploadTo(spot.folder);
        return IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              color: spot.accepted && spot.to == null
                  ? c.accent.withValues(alpha: 0.06)
                  : null,
              border: Border.all(
                color: spot.accepted ? c.accent : c.borderStrong,
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LgSpace.s3,
                vertical: LgSpace.s2,
              ),
              decoration: BoxDecoration(
                color: c.float,
                borderRadius: BorderRadius.circular(LgRadius.r6),
                border: Border.all(color: c.border),
              ),
              child: Text(message, style: t.text),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final shown = filterEntries(_pane.entries, _search.text);
    final error = _pane.openError;
    return ListenableBuilder(
      listenable: widget.ffi.ffiModel,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) => PaneDragTarget(
          area: widget.area,
          child: KeyedSubtree(
            key: widget.area.key,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(l10n, t),
                    _navRow(l10n),
                    const SizedBox(height: LgSpace.s1),
                    _actionRow(l10n, shown, constraints.maxWidth),
                    if (error != null && _pane.path.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          LgSpace.s2,
                          LgSpace.s2,
                          LgSpace.s2,
                          0,
                        ),
                        child: LgBanner(
                          tone: LgTone.error,
                          dense: true,
                          text: openErrorText(
                            l10n,
                            error.path,
                            error.error,
                            _pane.isWindows,
                          ),
                          dismissLabel: l10n.filesDismiss,
                          onDismiss: _pane.dismissOpenError,
                        ),
                      ),
                    const SizedBox(height: LgSpace.s1),
                    Expanded(child: _listArea(l10n, t, shown)),
                    Container(height: 1, color: t.colors.border),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LgSpace.s3,
                        vertical: LgSpace.s1,
                      ),
                      child: Text(
                        statusLine(l10n, shown, _pane.selection),
                        style: t.textS.copyWith(color: t.colors.text2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Positioned.fill(child: _dropOverlay(l10n, t)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
