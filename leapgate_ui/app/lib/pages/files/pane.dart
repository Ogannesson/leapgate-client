// One pane of the file transfer view (02 §2.2 blocks B to F): the header, the navigation row
// with the path, the action row with the search, the banner of a folder that did not open, the
// list and its states, the status line, and what a drag over it would do.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/file_transfer/errors.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/file_model.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_banner.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_device.dart';
import '../../widgets/lg_file_pane.dart';
import '../../widgets/lg_list_chrome.dart';
import '../../widgets/lg_menu.dart';
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
  // A file link has no size (its column is empty): it adds none, and only links say none.
  final files = selection.where((e) => e.entryType != 5);
  if (files.isEmpty) return l10n.filesSelected(selection.length);
  final size = files.fold<int>(0, (a, e) => a + e.size);
  return l10n.filesSelectedSize(selection.length, formatFileSize(l10n, size));
}

class FilePaneView extends StatefulWidget {
  const FilePaneView({
    super.key,
    required this.ffi,
    required this.pane,
    required this.other,
    required this.area,
    required this.otherArea,
    required this.listFocus,
    required this.otherListFocus,
    this.compact = false,
  });

  /// The session, for the remote device's name and platform in the header.
  final FFI ffi;
  final FilePane pane;
  final FilePane other;
  final PaneDropArea area;

  /// The other pane's, for the label that follows rows dragged out of this one.
  final PaneDropArea otherArea;
  final FocusNode listFocus;
  final FocusNode otherListFocus;

  /// The smallest window's rows (`FileView`).
  final bool compact;

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

  Widget _header(AppLocalizations l10n) {
    final ffi = widget.ffi;
    if (_pane.isLocal) {
      return LgFilePaneHeader(
        title: l10n.filesThisDevice,
        subtitle: Platform.localHostname,
        platform: _localPlatform(),
        compact: widget.compact,
      );
    }
    final platform = platformText(ffi.ffiModel.pi.platform);
    return LgFilePaneHeader(
      title: l10n.filesRemoteDevice,
      subtitle: platform.isEmpty
          ? deviceName(ffi)
          : l10n.filesDeviceAndPlatform(deviceName(ffi), platform),
      platform: platform.isEmpty ? null : platformOf(ffi),
      remoteId: ffi.id,
      compact: widget.compact,
    );
  }

  static LgPlatform _localPlatform() {
    if (Platform.isWindows) return LgPlatform.windows;
    if (Platform.isMacOS) return LgPlatform.macos;
    if (Platform.isLinux) return LgPlatform.linux;
    if (Platform.isAndroid) return LgPlatform.android;
    return LgPlatform.unknown;
  }

  Widget _navRow(AppLocalizations l10n) {
    String keyed(String name, String keys) =>
        l10n.filesWithShortcut(name, keys);
    return LgFileNavRow(
      compact: widget.compact,
      back: LgFileNavButton(
        icon: LgIcons.arrowL,
        label: keyed(l10n.filesBack, 'Alt+←'),
        onPressed: _pane.canGoBack ? _pane.goBack : null,
      ),
      up: LgFileNavButton(
        icon: LgIcons.arrowU,
        label: keyed(l10n.filesUp, 'Alt+↑'),
        onPressed: _pane.canGoUp ? _pane.goUp : null,
      ),
      home: LgFileNavButton(
        icon: LgIcons.home,
        label: l10n.filesHome,
        onPressed: _pane.goHome,
      ),
      refresh: LgFileNavButton(
        icon: LgIcons.refresh,
        label: keyed(l10n.filesRefresh, 'F5'),
        onPressed: _pane.path.isEmpty ? null : _pane.refresh,
      ),
      path: FileBreadcrumb(pane: _pane, editing: _editingPath),
    );
  }

  Widget _actionRow(AppLocalizations l10n, List<Entry> shown) {
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _clearSearch,
      },
      child: LgFileOpRow(
        compact: widget.compact,
        collapseBelow: kFileSearchFoldBelow,
        actions: [
          tip.isEmpty ? transfer : LgTooltip(message: tip, child: transfer),
          LgListToolButton(
            icon: LgIcons.folderPlus,
            label: l10n.filesNewFolder,
            onPressed: _pane.isThisPc || _pane.path.isEmpty
                ? null
                : _pane.newFolder,
          ),
          LgListToolButton(
            icon: LgIcons.trash,
            label: l10n.filesDelete,
            onPressed: selection.isEmpty ? null : () => _pane.delete(selection),
          ),
          LgMenuAnchor(
            items: moreMenuItems(l10n, pane: _pane, visible: shown),
            builder: (context, controller) => LgIconButton(
              icon: LgIcons.more,
              label: l10n.filesMore,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
        ],
        searchController: _search,
        searchFocusNode: _searchFocus,
        searchPlaceholder: l10n.filesSearch,
        searchClearLabel: l10n.filesClearSearch,
        searchOpenLabel: l10n.filesSearch,
        searchActiveLabel: l10n.filesSearchFiltering,
        searchOpen: _searchOpen,
        onSearchOpenChanged: (open) => setState(() => _searchOpen = open),
        onSearchChanged: (_) => _searchChanged(),
      ),
    );
  }

  /// The list area: the rows, or what stands in for them.
  Widget _listArea(AppLocalizations l10n, LgTokens t, List<Entry> shown) {
    final error = _pane.openError;
    final reading = _readingShown;
    if (_pane.path.isEmpty) {
      if (error != null) {
        // The first folder did not open: nothing to go back to (02 §2.2 block E). The text of
        // an error that is not recognised is in the tooltip, as on the banner.
        final detail = openErrorDetail(error.error);
        final state = LgEmptyState(
          openErrorText(l10n, error.path, error.error, _pane.isWindows,
              brief: true),
          icon: LgIcons.err,
          iconColor: t.colors.error,
          iconBackground: t.colors.errorBg,
          secondaryActionLabel: l10n.filesGoHome,
          onSecondaryAction: _pane.goHome,
          actionLabel: l10n.filesRetry,
          onAction: () => _pane.openDirectory(error.path),
        );
        return Center(
          child: detail == null
              ? state
              : LgTooltip(message: detail, child: state),
        );
      }
      return LgReadingOverlay(
        reading: reading,
        label: l10n.filesReading,
        child: const SizedBox.expand(),
      );
    }
    Widget? placeholder;
    if (shown.isEmpty && !reading) {
      final none = _search.text.trim().isNotEmpty;
      placeholder = Center(
        child: LgEmptyState(
          none ? l10n.filesNoMatch : l10n.filesEmptyFolder,
          icon: none ? LgIcons.search : LgIcons.folder,
        ),
      );
    }
    return LgReadingOverlay(
      reading: reading,
      // The same folder read again keeps its rows as they are.
      dim: reading && _pane.reading!.path != _pane.path,
      label: l10n.filesReading,
      child: FileList(
        pane: _pane,
        other: widget.other,
        entries: shown,
        focusNode: widget.listFocus,
        area: widget.area,
        otherArea: widget.otherArea,
        onEditPath: () => _editingPath.value = true,
        onFocusSearch: _focusSearch,
        onSwitchPane: () {
          // No list there until a folder opened in it.
          if (widget.other.path.isEmpty) return false;
          widget.otherListFocus.requestFocus();
          return true;
        },
        placeholder: placeholder,
      ),
    );
  }

  /// What a drag over the pane draws: the pane tinted with where the items go when they land on
  /// its folder, a neutral frame when they can't land. Over a folder row the row is the target
  /// (`FileList`): rows from the other pane say it in the label that follows them, files from
  /// the system's file manager in the pane's card, without the frame.
  Widget _dropZone(AppLocalizations l10n, Widget child) {
    return ValueListenableBuilder<FileDropSpot?>(
      valueListenable: widget.area.hover,
      child: child,
      builder: (context, spot, child) {
        final row = spot != null && spot.to != null;
        return LgDropZone(
          state: spot == null || (row && !spot.fromSystem)
              ? LgDropState.none
              : spot.accepted
              ? LgDropState.accept
              : LgDropState.reject,
          framed: !row,
          message: spot == null || !spot.accepted
              ? null
              : _pane.isLocal
              ? l10n.filesDownloadTo(spot.folder)
              : l10n.filesUploadTo(spot.folder),
          messageIcon: _pane.isLocal ? LgIcons.download : LgIcons.upload,
          child: child!,
        );
      },
    );
  }

  /// The banner of a folder that did not open (02 §2.5): a read that timed out can be retried;
  /// the text of one that is not recognised is in the tooltip.
  Widget _openErrorBanner(
    AppLocalizations l10n,
    ({String path, FtError error}) error,
  ) {
    final timeout = error.error.reason == FtReason.timeout;
    final banner = LgBanner(
      tone: LgTone.error,
      slim: true,
      dense: true,
      text: openErrorText(
        l10n,
        error.path,
        error.error,
        _pane.isWindows,
        brief: true,
      ),
      actionLabel: timeout ? l10n.filesRetry : null,
      onAction: timeout ? () => _pane.openDirectory(error.path) : null,
      dismissLabel: l10n.filesDismiss,
      onDismiss: _pane.dismissOpenError,
    );
    final detail = openErrorDetail(error.error);
    return detail == null ? banner : LgTooltip(message: detail, child: banner);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final shown = filterEntries(_pane.entries, _search.text);
    final error = _pane.openError;
    final title = _pane.isLocal ? l10n.filesThisDevice : l10n.filesRemoteDevice;
    return ListenableBuilder(
      listenable: widget.ffi.ffiModel,
      builder: (context, _) => PaneDragTarget(
        area: widget.area,
        child: KeyedSubtree(
          key: widget.area.key,
          child: _dropZone(
            l10n,
            LgFilePaneFrame(
              semanticLabel: title,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(l10n),
                  _navRow(l10n),
                  if (error != null && _pane.path.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        LgSpace.s3,
                        0,
                        LgSpace.s3,
                        LgSpace.s2,
                      ),
                      child: _openErrorBanner(l10n, error),
                    ),
                  _actionRow(l10n, shown),
                  Expanded(child: _listArea(l10n, t, shown)),
                  LgFileStatusRow(statusLine(l10n, shown, _pane.selection)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
