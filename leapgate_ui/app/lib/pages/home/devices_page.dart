import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connect_box.dart';
import 'package:flutter_hbb/leapgate/exit_nodes.dart'
    show isExitId, offersExit;
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/peer_list.dart';
import 'package:flutter_hbb/leapgate/peer_tabs.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/leapgate/tunnel_api.dart' show TunnelKind;
import 'package:flutter_hbb/leapgate/ui_mode.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:window_manager/window_manager.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/navigation.dart' show useAsExit;
import '../../shell/tab_overlays.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_connect_box.dart';
import '../../widgets/lg_device.dart';
import '../../widgets/lg_device_card.dart';
import '../../widgets/lg_list_chrome.dart';
import '../../widgets/lg_menu.dart';
import '../../widgets/lg_menu_items.dart';
import '../../widgets/lg_selection.dart';
import 'account_category.dart';
import 'address_book/address_book.dart';
import 'exit/open_tunnel.dart';
import 'group/group.dart';
import 'home_dialogs.dart';
import 'peer_views.dart';

// Examples in the connect box help, from the documentation ranges (01 §7.1 "示例数据").
const _helpExamples = (
  id: '123 456 789',
  ip: '192.0.2.10',
  domain: 'pc.example.com:21118',
  server: '123456789@leapgate.example.com',
  relay: '123456789/r',
);

/// "Connect to ‹input›" as the current row; device IDs are never empty.
const _connectToRow = '';

/// The list view's column for each sort order (user name sorts the `user@host` column).
const _sortColumns = {
  PeerSort.status: LgDeviceColumn.status,
  PeerSort.name: LgDeviceColumn.name,
  PeerSort.id: LgDeviceColumn.id,
  PeerSort.username: LgDeviceColumn.userHost,
};

/// The devices page (01 P1 blocks E and F): the connect box, the category bar with its tools
/// (or the multiple selection bar), and the selected category's devices or, while there is
/// input, the search results across the categories, in the chosen view.
///
/// One current row stands for both the clicked device and the row the arrow keys moved to;
/// Enter and "Connect" run it. While searching and before the keys move, it is
/// [ConnectBoxSearch.defaultRow].
class DevicesPage extends StatefulWidget {
  const DevicesPage({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.status,
    required this.overlays,
  });

  /// Owned by the home page, which puts text and the cursor into the box on request.
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Whether the server, which answers the online queries, is out of reach.
  final LocalStatusModel status;

  /// The home tab's dialogs.
  final TabOverlays overlays;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> with WindowListener {
  final _tabs = PeerTabs(appCore.options);
  final _selection = PeerSelection();
  late final _onlines = OnlineQuery(appCore.recentPeers.queryOnlines);
  String _text = '';

  /// The current row's device ID, or [_connectToRow]; set by a click or the arrow keys, null
  /// follows the default. Kept by ID: Rust pushes the lists again whenever a session in another
  /// tab reconnects, and Enter must still run the device the user moved to.
  String? _current;
  bool _windowFocused = true;
  bool _onScreen = true;

  /// "Adjust the categories shown and their order" folded open in the "View" menu.
  bool _categoriesOpen = false;
  DateTime _restoredAt = DateTime(0);

  @override
  void initState() {
    super.initState();
    _text = widget.controller.text;
    widget.controller.addListener(_onText);
    windowManager.addListener(this);
    // All three, for the search across categories (01 P1 block E).
    for (final c in searchedCategories) {
      c.load();
    }
    if (_tabs.current == PeerCategory.lan) appCore.lanPeers.discover();
    _onlines.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onScreen = TickerMode.valuesOf(context).enabled;
    _updateActive();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    windowManager.removeListener(this);
    _onlines.dispose();
    _tabs.dispose();
    _selection.dispose();
    super.dispose();
  }

  // Asking stops while the window is out of focus (upstream `peers_view.dart` `onWindowBlur`)
  // and while another tab covers the home page (tickers off).
  void _updateActive() => _onlines.active = _windowFocused && _onScreen;

  @override
  void onWindowFocus() {
    _windowFocused = true;
    _updateActive();
  }

  // Restoring a window on Windows reports a blur as well (upstream `peers_view.dart:131-160`).
  @override
  void onWindowBlur() {
    if (DateTime.now().difference(_restoredAt) <
        const Duration(milliseconds: 300)) {
      return;
    }
    _windowFocused = false;
    _updateActive();
  }

  @override
  void onWindowRestore() {
    _restoredAt = DateTime.now();
    _windowFocused = true;
    _updateActive();
  }

  void _onText() {
    if (widget.controller.text == _text) return;
    setState(() {
      _text = widget.controller.text;
      _current = null;
    });
  }

  String get _input => _text.trim();

  List<CategoryPeers> get _searched =>
      [for (final c in searchedCategories) if (_tabs.isEnabled(c.category)) c];

  /// The search results with where each device came from.
  ({ConnectBoxSearch search, Map<String, PeerCategory> sources})? get _search {
    if (_input.isEmpty) return null;
    final sourced = withAccountPeers(searchablePeers(_searched));
    return (
      search: ConnectBoxSearch(_input, [for (final s in sourced) s.peer]),
      sources: {for (final s in sourced) s.peer.id: s.source},
    );
  }

  /// The selected category's devices: "Recent" in time order, the others sorted.
  List<Peer> _listed(PeerCategory category) {
    final peers = switch (category) {
      PeerCategory.addressBook => appCore.addressBook.shownPeers,
      PeerCategory.group => appCore.group.shownPeers,
      _ => categoryPeers(category).peers,
    };
    return category == PeerCategory.recent
        ? peers
        : sortPeers(peers, _tabs.sort);
  }

  bool _loaded(PeerCategory category) => switch (category) {
        PeerCategory.addressBook => appCore.addressBook.loaded,
        PeerCategory.group => appCore.group.loaded,
        _ => categoryPeers(category).loaded,
      };

  /// What the address book or the team devices put on the page (M4); null in the others.
  AccountCategoryView? _accountView(PeerCategory category) => switch (category) {
        PeerCategory.addressBook =>
          addressBookCategory(context, widget.overlays, _tabs.view),
        PeerCategory.group =>
          groupCategory(context, widget.overlays, _tabs.view),
        _ => null,
      };

  List<Peer> _capped(List<Peer> peers) =>
      peers.length > kMaxShownPeers ? peers.sublist(0, kMaxShownPeers) : peers;

  /// The rows in order: [_connectToRow] first while searching, then device IDs. None while the
  /// address book or the team devices show a state in place of the list.
  List<String> _rowIds(ConnectBoxSearch? search) {
    if (search != null) {
      return [_connectToRow, for (final p in _capped(search.matches)) p.id];
    }
    return [
      if (_loaded(_tabs.current) && _accountView(_tabs.current)?.state == null)
        for (final p in _capped(_listed(_tabs.current))) p.id,
    ];
  }

  /// Where the current row is now; the default once its device is no longer listed.
  int? _currentRow(ConnectBoxSearch? search) {
    final at = _current == null ? -1 : _rowIds(search).indexOf(_current!);
    return at >= 0 ? at : search?.defaultRow;
  }

  /// [category] is where the device is listed (the address book connects with its shared
  /// password); null for what was typed.
  void _connect(String id,
          {bool relay = false,
          PeerCategory? category,
          bool fileTransfer = false}) =>
      fileTransfer
          ? openFileTransferPeer(id, category: category)
          : connectPeer(id, category: category, relay: relay);

  /// Enter, "Connect" and its menu: the current row.
  void _runCurrent({bool relay = false, bool fileTransfer = false}) {
    final found = _search;
    final search = found?.search;
    final row = _currentRow(search);
    if (row == null) return;
    if (search == null) {
      _connect(_rowIds(null)[row],
          relay: relay, category: _tabs.current, fileTransfer: fileTransfer);
    } else if (row == 0) {
      _connect(_input, relay: relay, fileTransfer: fileTransfer);
    } else {
      final id = search.matches[row - 1].id;
      _connect(id,
          relay: relay,
          category: found!.sources[id],
          fileTransfer: fileTransfer);
    }
  }

  /// What "Use as exit node" in the "Connect" menu takes: the current row, as [_runCurrent]
  /// (08 M5-9). Null without one, for typed text that is not an ID, and for a device known not
  /// to run Windows (only Windows serves as an exit node).
  ({String id, PeerCategory? category})? _exitTarget() {
    final found = _search;
    final search = found?.search;
    final row = _currentRow(search);
    if (row == null) return null;
    final Peer peer;
    final PeerCategory? category;
    if (search == null) {
      peer = _capped(_listed(_tabs.current))[row];
      category = _tabs.current;
    } else if (row == 0) {
      return isExitId(_input) ? (id: _input, category: null) : null;
    } else {
      peer = search.matches[row - 1];
      category = found!.sources[peer.id];
    }
    return offersExit(peer.id, peer.platform)
        ? (id: peer.id, category: category)
        : null;
  }

  /// What "TCP 隧道" and "RDP" in the "Connect" menu open: the current row, as [_runCurrent]
  /// (13 §1.1.2); null without one.
  ({String id, PeerCategory? category})? _target() {
    final found = _search;
    final search = found?.search;
    final row = _currentRow(search);
    if (row == null) return null;
    if (search == null) {
      return (id: _rowIds(null)[row], category: _tabs.current);
    }
    if (row == 0) return (id: _input, category: null);
    final id = search.matches[row - 1].id;
    return (id: id, category: found!.sources[id]);
  }

  /// The platform of the current row's device, for the "Connect" menu ([connectMenu]); empty
  /// for typed text and without a row.
  String _currentPlatform() {
    final search = _search?.search;
    final row = _currentRow(search);
    if (row == null) return '';
    if (search == null) return _capped(_listed(_tabs.current))[row].platform;
    return row == 0 ? '' : search.matches[row - 1].platform;
  }

  void _move(int by) {
    final search = _search?.search;
    final ids = _rowIds(search);
    if (ids.isEmpty) return;
    final row = _currentRow(search);
    if (row == null && by < 0) return;
    setState(
      () =>
          _current = ids[row == null ? 0 : (row + by).clamp(0, ids.length - 1)],
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Keys of the clear and help buttons inside the box are their own, and so are the keys the
    // input method is composing with.
    if (!widget.focusNode.hasPrimaryFocus ||
        event is KeyUpEvent ||
        widget.controller.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (event is KeyDownEvent) _runCurrent();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        if (_current == null) return KeyEventResult.ignored;
        setState(() => _current = null);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _selectCategory(PeerCategory category) {
    _tabs.select(category);
    categoryPeers(category).load();
    if (category == PeerCategory.lan) appCore.lanPeers.discover();
    setState(() => _current = null);
  }

  String _categoryName(AppLocalizations l10n, PeerCategory category) =>
      switch (category) {
        PeerCategory.favorites => l10n.peersFavorites,
        PeerCategory.lan => l10n.peersLan,
        PeerCategory.addressBook => l10n.abCategory,
        PeerCategory.group => l10n.groupCategory,
        _ => l10n.recentCategory,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: Listenable.merge([
        ...searchedCategories,
        widget.status,
        _tabs,
        _selection,
        appCore.options.local.listenable(kOptionLeapgateUiMode),
        appCore.account,
        appCore.addressBook,
        appCore.group,
      ]),
      builder: (context, _) {
        final found = _search;
        final search = found?.search;
        final current = _currentRow(search);
        final account = _accountView(_tabs.current);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _connectBar(l10n),
            const SizedBox(height: LgSpace.s6),
            if (search != null)
              LgSectionTitle(l10n.connectBoxSearchResults)
            else if (_selection.active)
              _selectionBar(l10n)
            else
              _toolbar(l10n, account),
            const SizedBox(height: LgSpace.s2),
            Expanded(
              child: found == null
                  ? account == null
                      ? _categoryList(l10n, current)
                      : _accountList(l10n, account, current)
                  : _results(l10n, found.search, found.sources, current!),
            ),
          ],
        );
      },
    );
  }

  Widget _connectBar(AppLocalizations l10n) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: LgConnectBar(
        controller: widget.controller,
        focusNode: widget.focusNode,
        placeholder: l10n.connectBoxPlaceholder,
        connectLabel: l10n.connectBoxConnect,
        onConnect: _input.isEmpty ? null : _runCurrent,
        menuLabel: l10n.connectBoxConnectionType,
        menuItems: [
          for (final action in connectMenu(_currentPlatform()))
            ?switch (action) {
              PeerAction.remoteDesktop => LgMenuItem(
                label: l10n.connectBoxRemoteDesktop,
                checked: true,
                hint: l10n.connectBoxDefault,
                onPressed: _runCurrent,
              ),
              PeerAction.fileTransfer => LgMenuItem(
                label: l10n.ftFileTransfer,
                checked: false,
                onPressed: () => _runCurrent(fileTransfer: true),
              ),
              PeerAction.useAsExit => switch (_exitTarget()) {
                final exit? => LgMenuItem(
                  label: l10n.exitUseAsExit,
                  checked: false,
                  onPressed: () => useAsExit(exit.id, category: exit.category),
                ),
                null => null,
              },
              PeerAction.viaRelay => LgMenuItem(
                label: l10n.connectBoxViaRelay,
                checked: false,
                description: l10n.connectBoxViaRelayNote,
                onPressed: () => _runCurrent(relay: true),
              ),
              // TODO(M9b): terminal, camera (`LEAPGATE.md` §10.18).
              PeerAction.terminal => null,
              PeerAction.terminalAdmin => null,
              PeerAction.camera => null,
              PeerAction.tcpTunnel || PeerAction.rdp => switch (_target()) {
                final target? => LgMenuItem(
                  label: action == PeerAction.rdp ? 'RDP' : l10n.tunnelKindTcp,
                  checked: false,
                  onPressed: () => openTunnel(
                    target.id,
                    action == PeerAction.rdp ? TunnelKind.rdp : TunnelKind.tcp,
                    platform: _currentPlatform(),
                    category: target.category,
                  ),
                ),
                null => null,
              },
              _ => null,
            },
        ],
        clearLabel: l10n.connectBoxClear,
        helpLabel: l10n.connectBoxHelp,
        // Upstream `id_input_tip`, rewritten by 01 §7.6, as term and example.
        help: LgHelpContent(
          title: l10n.connectBoxHelpTitle,
          rows: [
            (l10n.connectBoxHelpId, _helpExamples.id),
            (l10n.connectBoxHelpIp, _helpExamples.ip),
            (l10n.connectBoxHelpDomain, _helpExamples.domain),
            (l10n.connectBoxHelpServer, _helpExamples.server),
            (
              l10n.connectBoxHelpOtherServer,
              l10n.connectBoxHelpOtherServerExample,
            ),
            (l10n.connectBoxViaRelay, _helpExamples.relay),
          ],
        ),
      ),
    );
  }

  /// The category bar and the list tools (01 P1 block F, `p1-menu-view`, `p1-menu-sort`).
  Widget _toolbar(AppLocalizations l10n, AccountCategoryView? account) {
    final shown = _tabs.shown;
    final fixedText = l10n.peersFixed;
    final viewFixed = _tabs.isFixed(kOptionPeerCardUiType);
    final sortFixed = _tabs.isFixed(kOptionPeerSorting);
    final categoriesFixed = _tabs.isFixed(kOptionPeerTabVisible);
    final detail = isDetailMode(appCore.options.local);
    return LgListToolbar(
      tabs: LgCategoryTabs<PeerCategory>(
        categories: [
          for (final c in shown) LgCategory(c, _categoryName(l10n, c)),
        ],
        selected: _tabs.current,
        onSelect: _selectCategory,
        semanticLabel: l10n.peersCategories,
      ),
      tools: [
        LgListToolMenu(
          icon: LgIcons.grid,
          label: l10n.peersView,
          items: [
            LgMenuGroup(l10n.peersView),
            for (final (view, label) in [
              (PeerView.cards, l10n.peersCards),
              (PeerView.list, l10n.peersList),
            ])
              LgMenuItem(
                label: label,
                checked: _tabs.view == view,
                disabledNote: viewFixed ? fixedText : null,
                onPressed: viewFixed ? null : () => _tabs.setView(view),
              ),
            LgMenuGroup(l10n.uiModeTitle),
            LgMenuSegmentedItem<bool>(
              segments: [
                LgSegment(false, l10n.uiModeSimple),
                LgSegment(true, l10n.uiModeDetail),
              ],
              selected: detail,
              onChanged: (on) => setDetailMode(appCore.options.local, on),
            ),
            const LgMenuDivider(),
            LgMenuExpandRow(
              label: l10n.peersAdjustCategories,
              expanded: _categoriesOpen,
              onToggle: () => setState(() => _categoriesOpen = !_categoriesOpen),
            ),
            if (_categoriesOpen)
              CategoryOrderList(
                tabs: _tabs,
                names: (c) => _categoryName(l10n, c),
                fixedNote: categoriesFixed ? fixedText : null,
              ),
          ],
        ),
        // "Recent" keeps its time order (01 P1 block F).
        if (_tabs.current != PeerCategory.recent)
          LgListToolMenu(
            icon: LgIcons.sort,
            label: l10n.peersSort,
            items: [
              for (final (sort, label) in _sortLabels(l10n))
                LgMenuItem(
                  label: label,
                  checked: _tabs.sort == sort,
                  disabledNote: sortFixed ? fixedText : null,
                  onPressed: sortFixed ? null : () => _tabs.setSort(sort),
                ),
            ],
          ),
        LgListToolButton(
          icon: LgIcons.select,
          label: l10n.peersSelect,
          onPressed: _selection.start,
        ),
        ...?account?.tools,
      ],
    );
  }

  List<(PeerSort, String)> _sortLabels(AppLocalizations l10n) => [
    (PeerSort.name, l10n.peersSortName),
    (PeerSort.id, l10n.peersSortId),
    (PeerSort.username, l10n.peersSortUsername),
    (PeerSort.status, l10n.peersSortStatus),
  ];

  /// The multiple selection bar in place of the category bar (01 P1 block F, `p1-multisel`).
  Widget _selectionBar(AppLocalizations l10n) {
    final category = _tabs.current;
    final ids = _selection.ids;
    // Removing from favorites neither asks nor looks dangerous, as in the menu of one device
    // (01 P1 block F); removing from the LAN list and deleting ask with [title].
    final (label, icon, title, toast) = switch (category) {
      PeerCategory.favorites => (
          l10n.peersRemoveFavorites,
          LgIcons.star,
          null,
          'peersToastRemovedFavorites',
        ),
      PeerCategory.lan => (
          l10n.peersRemove,
          LgIcons.trash,
          l10n.peersRemoveMany(ids.length),
          'peersToastRemoved',
        ),
      _ => (
          l10n.peersDelete,
          LgIcons.trash,
          l10n.peersDeleteMany(ids.length),
          'peersToastDeleted',
        ),
    };
    // The toast keys are ARB keys; the shell's `toastText` shows them.
    void done(String toast) {
      _selection.finish();
      appCore.toasts.show(toast);
    }

    // The address book and the team devices have only the address book's actions.
    final accountCategory = category == PeerCategory.addressBook ||
        category == PeerCategory.group;
    return LgSelectionBar(
      semanticLabel: l10n.peersSelect,
      actions: [
        if (!accountCategory)
        LgSelectionAction(
          label: label,
          icon: icon,
          danger: title != null,
          onPressed: ids.isEmpty
              ? null
              : () async {
                  if (title != null &&
                      !await confirmOnHome(widget.overlays,
                          title: title, action: label, cancel: l10n.homeCancel)) {
                    return;
                  }
                  await deletePeers(category, ids);
                  done(toast);
                },
        ),
        if (category == PeerCategory.recent)
          LgSelectionAction(
            label: l10n.peersAddFavorites,
            icon: LgIcons.star,
            onPressed: ids.isEmpty
                ? null
                : () async {
                    await addFavorites(ids);
                    done('peersToastAddedFavorites');
                  },
          ),
        ...abSelectionActions(
          l10n,
          category,
          ids,
          overlays: widget.overlays,
          done: done,
        ),
      ],
      countText: l10n.peersSelected(ids.length),
      selectAllLabel: l10n.peersSelectAll,
      onSelectAll: () => _selection.selectAll(_rowIds(null)),
      doneLabel: l10n.peersDone,
      onDone: _selection.finish,
    );
  }

  Widget _categoryList(AppLocalizations l10n, int? current) {
    final category = _tabs.current;
    final peers = categoryPeers(category);
    // The loading and empty states scroll in a window too short for them.
    if (!peers.loaded) {
      return SingleChildScrollView(
        child: _tabs.view == PeerView.cards
            ? LgDeviceCardGrid(
                semanticLabel: l10n.recentLoading,
                children: const [
                  LgDeviceCardSkeleton(),
                  LgDeviceCardSkeleton(),
                  LgDeviceCardSkeleton(),
                ],
              )
            : LgDeviceSkeleton(semanticLabel: l10n.recentLoading),
      );
    }
    final listed = _listed(category);
    if (listed.isEmpty) {
      return SingleChildScrollView(
        child: LgEmptyState(switch (category) {
          PeerCategory.favorites => l10n.peersEmptyFavorites,
          PeerCategory.lan => l10n.peersEmptyLan,
          _ => l10n.recentEmpty,
        }),
      );
    }
    final shown = _capped(listed);
    return _devices(
      l10n,
      [for (final p in shown) _item(l10n, p, category, source: null)],
      over: listed.length > shown.length,
      isCurrent: (i) => i == current,
    );
  }

  /// The address book or the team devices: the category's [AccountCategoryView.state] or its
  /// devices, under its header and beside its side list.
  Widget _accountList(
    AppLocalizations l10n,
    AccountCategoryView view,
    int? current,
  ) {
    final category = _tabs.current;
    final listed = _listed(category);
    final shown = _capped(listed);
    final list = view.state ??
        _devices(
          l10n,
          [for (final p in shown) _item(l10n, p, category, source: null)],
          over: listed.length > shown.length,
          isCurrent: (i) => i == current,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?view.header,
        Expanded(
          child: view.side == null
              ? list
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [view.side!, Expanded(child: list)],
                ),
        ),
      ],
    );
  }

  Widget _results(
    AppLocalizations l10n,
    ConnectBoxSearch search,
    Map<String, PeerCategory> sources,
    int current,
  ) {
    final shown = _capped(search.matches);
    final loading = _searched.any((c) => !c.loaded) || accountPeersLoading();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: LgConnectToRow(
                text: l10n.connectBoxConnectTo(_input),
                emphasis: _input,
                highlighted: current == 0,
                onTap: () => _connect(_input),
              ),
            ),
            // The "⋯" at the end of "Connect to" (`p1-cb-conn`; `LgConnectToRow` has no slot for
            // it, so it stands beside the row). What was typed has no known platform
            // ([connectMenu] with an empty one).
            LgMenuAnchor(
              items: [
                for (final action in connectMenu(''))
                  ?switch (action) {
                    PeerAction.remoteDesktop => LgMenuItem(
                      label: l10n.connectBoxRemoteDesktop,
                      onPressed: () => _connect(_input),
                    ),
                    PeerAction.fileTransfer => LgMenuItem(
                      label: l10n.ftFileTransfer,
                      onPressed: () => _connect(_input, fileTransfer: true),
                    ),
                    PeerAction.useAsExit when isExitId(_input) => LgMenuItem(
                      label: l10n.exitUseAsExit,
                      onPressed: () => useAsExit(_input),
                    ),
                    PeerAction.viaRelay => LgMenuItem(
                      label: l10n.connectBoxViaRelay,
                      description: l10n.connectBoxViaRelayNote,
                      onPressed: () => _connect(_input, relay: true),
                    ),
                    // TODO(M9b): terminal, camera (`LEAPGATE.md` §10.18).
                    PeerAction.terminal => null,
                    PeerAction.terminalAdmin => null,
                    PeerAction.camera => null,
                    PeerAction.tcpTunnel => LgMenuItem(
                      label: l10n.tunnelKindTcp,
                      onPressed: () => openTunnel(_input, TunnelKind.tcp),
                    ),
                    PeerAction.rdp => LgMenuItem(
                      label: 'RDP',
                      onPressed: () => openTunnel(_input, TunnelKind.rdp),
                    ),
                    _ => null,
                  },
              ],
              builder: (context, controller) => LgIconButton(
                icon: LgIcons.more,
                label: l10n.peersOtherConnectionTypes,
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
          ],
        ),
        const SizedBox(height: LgSpace.s3),
        if (search.matches.isEmpty && !loading)
          LgNoResultsNote(l10n.connectBoxNoMatch)
        else
          Expanded(
            child: _devices(
              l10n,
              [
                for (final p in shown)
                  _item(l10n, p, sources[p.id]!,
                      source: _categoryName(l10n, sources[p.id]!)),
              ],
              over: search.matches.length > shown.length,
              loadingOthers: loading,
              isCurrent: (i) => i + 1 == current,
            ),
          ),
      ],
    );
  }

  PeerItem _item(AppLocalizations l10n, Peer peer, PeerCategory category,
      {required String? source}) {
    // The UI process asks the server itself, service or not; only an unreachable server leaves
    // the query unanswered (`src/client.rs` `query_online_states`): offline then, not
    // "checking" forever. "Connecting" (the state at start) and a stopped service still ask.
    final serverUnreachable = widget.status.status == ServiceStatus.notReady;
    final (status, label) = !serverUnreachable &&
            !categoryPeers(category).hasOnlineState(peer.id)
        ? (LgDeviceStatus.querying, l10n.recentQuerying)
        : peer.online
            ? (LgDeviceStatus.online, l10n.recentOnline)
            : (LgDeviceStatus.offline, l10n.recentOffline);
    return PeerItem(
      peer: peer,
      category: category,
      status: status,
      statusLabel: label,
      favorite: isFavorite(peer.id),
      source: source,
    );
  }

  PeerItemActions _actions(PeerItem item, List<PeerItem> items, bool current) {
    final id = item.peer.id;
    // The search results are not picked: the selection bar acts on the selected category.
    final selecting = _selection.active && _input.isEmpty;
    return PeerItemActions(
      overlays: widget.overlays,
      selecting: selecting,
      selected: selecting && _selection.contains(id),
      current: current,
      onConnect: () => _connect(id, category: item.category),
      onTap: () {
        if (selecting) {
          _selection.tap(id, [for (final i in items) i.peer.id],
              shift: shiftPressed);
          return;
        }
        setState(() => _current = id);
        // A click outside the box takes the focus away on Windows; Enter runs the row from the
        // box.
        widget.focusNode.requestFocus();
      },
    );
  }

  /// [items] as cards or as the list, whichever view is chosen (01 P1 block F; the search
  /// results as well, `待调.md` 25), with the notes under them.
  Widget _devices(
    AppLocalizations l10n,
    List<PeerItem> items, {
    required bool over,
    bool loadingOthers = false,
    required bool Function(int i) isCurrent,
  }) {
    final notes = [
      if (over) LgListNote(l10n.peersOver1000),
      if (loadingOthers) LgListNote(l10n.peersLoadingOther),
    ];
    Widget asked(PeerItem item, Widget child) => _AskedRow(
        key: ValueKey(item.peer.id),
        id: item.peer.id,
        onlines: _onlines,
        child: child);
    if (_tabs.view == PeerView.cards) {
      // Built lazily, so only the cards on screen ask for their online state; the component's
      // `LgDeviceCardGrid` lays out all of them.
      return Semantics(
        container: true,
        explicitChildNodes: true,
        label: l10n.peersDeviceList,
        child: CustomScrollView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(0),
          slivers: [
            SliverGrid.builder(
              gridDelegate: const LgDeviceCardGridDelegate(),
              itemCount: items.length,
              itemBuilder: (context, i) => asked(
                items[i],
                PeerCard(
                    item: items[i],
                    actions: _actions(items[i], items, isCurrent(i))),
              ),
            ),
            SliverList.list(children: notes),
          ],
        ),
      );
    }
    final t = LgTokens.of(context);
    final rowHeight = t.sizes.tableRow;
    // The surface's own padding (`LgListSurface`), the column titles and the notes.
    final chrome = LgSpace.s1 + LgSpace.s2 + t.sizes.button;
    final searching = items.isNotEmpty && items.first.source != null;
    // Sorting by a title, as the "Sort" menu (not in "Recent", nor in the search results).
    final sortable = !searching && _tabs.current != PeerCategory.recent;
    final selecting = _selection.active && _input.isEmpty;
    // `LgDeviceTable`'s parts, with the rows built lazily for the same reason as the cards.
    return LayoutBuilder(
      builder: (context, box) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LgListSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LgDeviceTableHeader(
                  columns: [
                    LgTableColumn(
                        LgDeviceColumn.status, l10n.recentColumnStatus,
                        sortable: sortable),
                    LgTableColumn(LgDeviceColumn.name, l10n.recentColumnName,
                        sortable: sortable),
                    LgTableColumn(LgDeviceColumn.id, l10n.recentColumnId,
                        sortable: sortable),
                    LgTableColumn(
                        LgDeviceColumn.userHost, l10n.recentColumnUserHost,
                        sortable: sortable),
                    if (!searching && abNoteColumn(_tabs.current))
                      LgTableColumn(LgDeviceColumn.note, l10n.abFieldNote),
                    searching
                        ? LgTableColumn(
                            LgDeviceColumn.source, l10n.recentColumnSource)
                        : LgTableColumn(
                            LgDeviceColumn.tags, l10n.peersColumnTags),
                  ],
                  sort: sortable
                      ? LgTableSort(_sortColumns[_tabs.sort]!)
                      : null,
                  onSort: sortable && !_tabs.isFixed(kOptionPeerSorting)
                      ? (column) => _tabs.setSort(_sortColumns.entries
                          .firstWhere((e) => e.value == column)
                          .key)
                      : null,
                  pickColumn: selecting,
                  moreColumn: true,
                  ascendingLabel: l10n.peersSortAscending,
                  descendingLabel: l10n.peersSortDescending,
                ),
                SizedBox(
                  height: math.max(
                    0,
                    math.min(items.length * rowHeight,
                        box.maxHeight - chrome - notes.length * rowHeight),
                  ),
                  child: ListView.builder(
                    scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                    itemExtent: rowHeight,
                    itemCount: items.length,
                    itemBuilder: (context, i) => asked(
                      items[i],
                      PeerTableRow(
                        item: items[i],
                        actions: _actions(items[i], items, isCurrent(i)),
                        topDivider: i > 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...notes,
        ],
      ),
    );
  }
}

/// Asks [onlines] about its device while the row exists.
class _AskedRow extends StatefulWidget {
  const _AskedRow({
    super.key,
    required this.id,
    required this.onlines,
    required this.child,
  });

  final String id;
  final OnlineQuery onlines;
  final Widget child;

  @override
  State<_AskedRow> createState() => _AskedRowState();
}

class _AskedRowState extends State<_AskedRow> {
  @override
  void initState() {
    super.initState();
    widget.onlines.show(widget.id);
  }

  @override
  void dispose() {
    widget.onlines.hide(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
