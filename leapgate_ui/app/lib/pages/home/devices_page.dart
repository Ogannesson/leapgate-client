import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connect_box.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/peer_list.dart';
import 'package:flutter_hbb/leapgate/peer_tabs.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/leapgate/ui_mode.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:window_manager/window_manager.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/navigation.dart';
import '../../shell/tab_overlays.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_connect_box.dart';
import '../../widgets/lg_device.dart';
import '../../widgets/lg_menu.dart';
import '../../widgets/lg_selection.dart';
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
    final sourced = searchablePeers(_searched);
    return (
      search: ConnectBoxSearch(_input, [for (final s in sourced) s.peer]),
      sources: {for (final s in sourced) s.peer.id: s.source},
    );
  }

  /// The selected category's devices: "Recent" in time order, the others sorted.
  List<Peer> _listed(PeerCategory category) {
    final peers = categoryPeers(category).peers;
    return category == PeerCategory.recent
        ? peers
        : sortPeers(peers, _tabs.sort);
  }

  List<Peer> _capped(List<Peer> peers) =>
      peers.length > kMaxShownPeers ? peers.sublist(0, kMaxShownPeers) : peers;

  /// The rows in order: [_connectToRow] first while searching, then device IDs.
  List<String> _rowIds(ConnectBoxSearch? search) {
    if (search != null) {
      return [_connectToRow, for (final p in _capped(search.matches)) p.id];
    }
    final category = categoryPeers(_tabs.current);
    return [
      if (category.loaded)
        for (final p in _capped(_listed(_tabs.current))) p.id,
    ];
  }

  /// Where the current row is now; the default once its device is no longer listed.
  int? _currentRow(ConnectBoxSearch? search) {
    final at = _current == null ? -1 : _rowIds(search).indexOf(_current!);
    return at >= 0 ? at : search?.defaultRow;
  }

  void _connect(String id, {bool relay = false}) =>
      mainNavigation.connect(id, forceRelay: relay);

  /// Enter, "Connect" and its menu: the current row.
  void _runCurrent({bool relay = false}) {
    final search = _search?.search;
    final row = _currentRow(search);
    if (row == null) return;
    if (search == null) {
      _connect(_rowIds(null)[row], relay: relay);
    } else if (row == 0) {
      _connect(_input, relay: relay);
    } else {
      _connect(search.matches[row - 1].id, relay: relay);
    }
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
      ]),
      builder: (context, _) {
        final found = _search;
        final search = found?.search;
        final current = _currentRow(search);
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
              _toolbar(l10n),
            const SizedBox(height: LgSpace.s2),
            Expanded(
              child: found == null
                  ? _categoryList(l10n, current)
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
          LgMenuItem(
            label: l10n.connectBoxRemoteDesktop,
            checked: true,
            hint: l10n.connectBoxDefault,
            onPressed: _runCurrent,
          ),
          LgMenuItem(
            label: l10n.connectBoxViaRelay,
            checked: false,
            description: l10n.connectBoxViaRelayNote,
            onPressed: () => _runCurrent(relay: true),
          ),
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

  /// The category bar and the list tools (01 P1 block F). Placeholder for the designer's
  /// category segments and list toolbar.
  Widget _toolbar(AppLocalizations l10n) {
    final shown = _tabs.shown;
    final fixedText = l10n.peersFixed;
    final viewFixed = _tabs.isFixed(kOptionPeerCardUiType);
    final categoriesFixed = _tabs.isFixed(kOptionPeerTabVisible);
    final detail = isDetailMode(appCore.options.local);
    return Row(
      children: [
        if (shown.isNotEmpty)
          LgSegmented<PeerCategory>(
            segments: [
              for (final c in shown) LgSegment(c, _categoryName(l10n, c)),
            ],
            selected: _tabs.current,
            onChanged: _selectCategory,
          ),
        const Spacer(),
        _menuButton(
          label: l10n.peersView,
          icon: LgIcons.grid,
          items: [
            LgMenuGroup(l10n.peersView),
            for (final (view, label) in [
              (PeerView.cards, l10n.peersCards),
              (PeerView.list, l10n.peersList),
            ])
              LgMenuItem(
                label: label,
                checked: _tabs.view == view,
                description: viewFixed ? fixedText : null,
                onPressed: viewFixed ? null : () => _tabs.setView(view),
              ),
            LgMenuGroup(l10n.uiModeTitle),
            for (final (on, label) in [
              (false, l10n.uiModeSimple),
              (true, l10n.uiModeDetail),
            ])
              LgMenuItem(
                label: label,
                checked: detail == on,
                onPressed: () => setDetailMode(appCore.options.local, on),
              ),
            LgSubmenu(
              label: l10n.peersAdjustCategories,
              items: [
                CategoryOrderList(
                  tabs: _tabs,
                  names: (c) => _categoryName(l10n, c),
                  enabled: !categoriesFixed,
                ),
              ],
            ),
          ],
        ),
        // "Recent" keeps its time order (01 P1 block F).
        if (_tabs.current != PeerCategory.recent) ...[
          const SizedBox(width: LgSpace.s1),
          _menuButton(
            label: l10n.peersSort,
            icon: LgIcons.sort,
            items: [
              for (final (sort, label) in [
                (PeerSort.name, l10n.peersSortName),
                (PeerSort.id, l10n.peersSortId),
                (PeerSort.username, l10n.peersSortUsername),
                (PeerSort.status, l10n.peersSortStatus),
              ])
                LgMenuItem(
                  label: label,
                  checked: _tabs.sort == sort,
                  description:
                      _tabs.isFixed(kOptionPeerSorting) ? fixedText : null,
                  onPressed: _tabs.isFixed(kOptionPeerSorting)
                      ? null
                      : () => _tabs.setSort(sort),
                ),
            ],
          ),
        ],
        const SizedBox(width: LgSpace.s1),
        LgButton(
          label: l10n.peersSelect,
          icon: LgIcons.select,
          kind: LgButtonKind.text,
          onPressed: _selection.start,
        ),
      ],
    );
  }

  Widget _menuButton({
    required String label,
    required LgIcons icon,
    required List<Widget> items,
  }) =>
      LgMenuAnchor(
        items: items,
        builder: (context, controller) => LgButton(
          label: label,
          icon: icon,
          kind: LgButtonKind.text,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      );

  /// The multiple selection bar in place of the category bar (01 P1 block F). Placeholder for
  /// the designer's `p1-multisel` bar.
  Widget _selectionBar(AppLocalizations l10n) {
    final category = _tabs.current;
    final ids = _selection.ids;
    final (label, title, toast) = switch (category) {
      PeerCategory.favorites => (
          l10n.peersRemoveFavorites,
          l10n.peersRemoveFavoritesMany(ids.length),
          'peersToastRemovedFavorites',
        ),
      PeerCategory.lan => (
          l10n.peersRemove,
          l10n.peersRemoveMany(ids.length),
          'peersToastRemoved',
        ),
      _ => (
          l10n.peersDelete,
          l10n.peersDeleteMany(ids.length),
          'peersToastDeleted',
        ),
    };
    // The toast keys are ARB keys; the shell's `toastText` shows them.
    void done(String toast) {
      _selection.finish();
      appCore.toasts.show(toast);
    }

    return Row(
      children: [
        LgButton(
          label: label,
          icon: LgIcons.trash,
          kind: LgButtonKind.danger,
          onPressed: ids.isEmpty
              ? null
              : () async {
                  if (!await confirmOnHome(widget.overlays,
                      title: title, action: label, cancel: l10n.homeCancel)) {
                    return;
                  }
                  await deletePeers(category, ids);
                  done(toast);
                },
        ),
        if (category == PeerCategory.recent) ...[
          const SizedBox(width: LgSpace.s1),
          LgButton(
            label: l10n.peersAddFavorites,
            icon: LgIcons.star,
            kind: LgButtonKind.text,
            onPressed: ids.isEmpty
                ? null
                : () async {
                    await addFavorites(ids);
                    done('peersToastAddedFavorites');
                  },
          ),
        ],
        const SizedBox(width: LgSpace.s3),
        Text(l10n.peersSelected(ids.length)),
        const Spacer(),
        LgButton(
          label: l10n.peersSelectAll,
          kind: LgButtonKind.text,
          onPressed: () => _selection.selectAll(_rowIds(null)),
        ),
        LgButton(
          label: l10n.peersDone,
          kind: LgButtonKind.text,
          onPressed: _selection.finish,
        ),
      ],
    );
  }

  Widget _categoryList(AppLocalizations l10n, int? current) {
    final category = _tabs.current;
    final peers = categoryPeers(category);
    // The loading and empty states scroll in a window too short for them.
    if (!peers.loaded) {
      return SingleChildScrollView(
        child: LgDeviceSkeleton(semanticLabel: l10n.recentLoading),
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

  Widget _results(
    AppLocalizations l10n,
    ConnectBoxSearch search,
    Map<String, PeerCategory> sources,
    int current,
  ) {
    final shown = _capped(search.matches);
    final loading = _searched.any((c) => !c.loaded);
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
            // Placeholder for the "⋯" at the end of `LgConnectToRow`: what was typed has no
            // known platform, so the connection types are those of M2b (05 §1.3).
            LgMenuAnchor(
              items: [
                LgMenuItem(
                  label: l10n.connectBoxRemoteDesktop,
                  onPressed: () => _connect(_input),
                ),
                LgMenuItem(
                  label: l10n.connectBoxViaRelay,
                  description: l10n.connectBoxViaRelayNote,
                  onPressed: () => _connect(_input, relay: true),
                ),
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
      onConnect: () => _connect(id),
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
      if (over) LgNoResultsNote(l10n.peersOver1000),
      if (loadingOthers) LgNoResultsNote(l10n.peersLoadingOther),
    ];
    Widget asked(PeerItem item, Widget child) => _AskedRow(
        key: ValueKey(item.peer.id),
        id: item.peer.id,
        onlines: _onlines,
        child: child);
    if (_tabs.view == PeerView.cards) {
      return LayoutBuilder(builder: (context, box) {
        const gap = LgSpace.s3;
        final columns =
            math.max(1, ((box.maxWidth + gap) / (kMinCardWidth + gap)).floor());
        return CustomScrollView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(0),
          slivers: [
            SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                mainAxisExtent: 148,
              ),
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
        );
      });
    }
    final t = LgTokens.of(context);
    final rowHeight = t.sizes.tableRow;
    // The surface's own padding (`LgListSurface`), the column titles and the notes.
    final chrome = LgSpace.s1 + LgSpace.s2 + t.sizes.button;
    return LayoutBuilder(
      builder: (context, box) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LgListSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LgDeviceListHeader(
                  status: l10n.recentColumnStatus,
                  name: l10n.recentColumnName,
                  id: l10n.recentColumnId,
                  userHost: l10n.recentColumnUserHost,
                  source: items.isNotEmpty && items.first.source != null
                      ? l10n.recentColumnSource
                      : null,
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
