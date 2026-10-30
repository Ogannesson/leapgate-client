import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connect_box.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../shell/navigation.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_connect_box.dart';
import '../../widgets/lg_device.dart';
import '../../widgets/lg_menu.dart';
import '../peer_platform.dart';

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

/// The devices page (01 P1 blocks E and F): the connect box, and under it "Recent" or, while
/// there is input, the search results. M2a has only the "Recent" category.
///
/// One current row stands for both the clicked device and the row the arrow keys moved to;
/// Enter and "Connect" run it. It is drawn as `selected` in "Recent" and as `highlighted` in
/// the search results. While searching and before the keys move, it is
/// [ConnectBoxSearch.defaultRow].
class DevicesPage extends StatefulWidget {
  const DevicesPage({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.status,
  });

  /// Owned by the home page, which puts text and the cursor into the box on request.
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Whether the server, which answers the online queries, is out of reach.
  final LocalStatusModel status;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> with WindowListener {
  final _recent = appCore.recentPeers;
  late final _onlines = OnlineQuery(_recent.queryOnlines);
  String _text = '';

  /// The current row's device ID, or [_connectToRow]; set by a click or the arrow keys, null
  /// follows the default. Kept by ID: Rust pushes the list again whenever a session in another
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
    _recent.load();
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

  ConnectBoxSearch? get _search =>
      _input.isEmpty ? null : ConnectBoxSearch(_input, _recent.peers);

  /// The rows in order: [_connectToRow] first while searching, then device IDs.
  List<String> _rowIds(ConnectBoxSearch? search) => search == null
      ? [
          if (_recent.loaded)
            for (final p in _recent.peers) p.id,
        ]
      : [_connectToRow, for (final p in search.matches) p.id];

  /// Where the current row is now; the default once its device is no longer listed.
  int? _currentRow(ConnectBoxSearch? search) {
    final at = _current == null ? -1 : _rowIds(search).indexOf(_current!);
    return at >= 0 ? at : search?.defaultRow;
  }

  void _connect(String id, {bool relay = false}) =>
      mainNavigation.connect(id, forceRelay: relay);

  /// Enter, "Connect" and its menu: the current row.
  void _runCurrent({bool relay = false}) {
    final search = _search;
    final row = _currentRow(search);
    if (row == null) return;
    if (search == null) {
      _connect(_recent.peers[row].id, relay: relay);
    } else if (row == 0) {
      _connect(_input, relay: relay);
    } else {
      _connect(search.matches[row - 1].id, relay: relay);
    }
  }

  void _move(int by) {
    final search = _search;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: Listenable.merge([_recent, widget.status]),
      builder: (context, _) {
        final search = _search;
        final current = _currentRow(search);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _connectBar(l10n),
            const SizedBox(height: LgSpace.s6),
            LgSectionTitle(
              search == null
                  ? l10n.recentCategory
                  : l10n.connectBoxSearchResults,
            ),
            const SizedBox(height: LgSpace.s2),
            Expanded(
              child: search == null
                  ? _recentList(l10n, current)
                  : _results(l10n, search, current!),
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

  Widget _recentList(AppLocalizations l10n, int? current) {
    // The loading and empty states scroll in a window too short for them.
    if (!_recent.loaded) {
      return SingleChildScrollView(
        child: LgDeviceSkeleton(semanticLabel: l10n.recentLoading),
      );
    }
    final peers = _recent.peers;
    if (peers.isEmpty) {
      return SingleChildScrollView(child: LgEmptyState(l10n.recentEmpty));
    }
    return _deviceList(
      l10n,
      peers,
      source: null,
      isCurrent: (i) => (selected: i == current, highlighted: false),
    );
  }

  Widget _results(AppLocalizations l10n, ConnectBoxSearch search, int current) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LgConnectToRow(
          text: l10n.connectBoxConnectTo(_input),
          emphasis: _input,
          highlighted: current == 0,
          onTap: () => _connect(_input),
        ),
        const SizedBox(height: LgSpace.s3),
        if (search.matches.isEmpty)
          LgNoResultsNote(l10n.connectBoxNoMatch)
        else
          Expanded(
            child: _deviceList(
              l10n,
              search.matches,
              source: l10n.recentCategory,
              isCurrent: (i) =>
                  (selected: false, highlighted: i + 1 == current),
            ),
          ),
      ],
    );
  }

  /// The rows on their surface, as tall as they need up to the space there is; the list
  /// scrolls beyond that. Rows only exist on screen, so the rows that ask for online state are
  /// the visible ones.
  Widget _deviceList(
    AppLocalizations l10n,
    List<Peer> peers, {
    required String? source,
    required ({bool selected, bool highlighted}) Function(int i) isCurrent,
  }) {
    final t = LgTokens.of(context);
    final rowHeight = t.sizes.tableRow;
    // The surface's own padding (`LgListSurface`) and the column titles.
    final chrome = LgSpace.s1 + LgSpace.s2 + t.sizes.button;
    // The UI process asks the server itself, service or not; only an unreachable server leaves
    // the query unanswered (`src/client.rs` `query_online_states`): offline then, not
    // "checking" forever. "Connecting" (the state at start) and a stopped service still ask.
    final serverUnreachable = widget.status.status == ServiceStatus.notReady;
    return LayoutBuilder(
      builder: (context, box) => Align(
        alignment: Alignment.topCenter,
        child: LgListSurface(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LgDeviceListHeader(
                status: l10n.recentColumnStatus,
                name: l10n.recentColumnName,
                id: l10n.recentColumnId,
                userHost: l10n.recentColumnUserHost,
                source: source == null ? null : l10n.recentColumnSource,
              ),
              SizedBox(
                height: math.max(
                  0,
                  math.min(peers.length * rowHeight, box.maxHeight - chrome),
                ),
                child: ListView.builder(
                  scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                  itemExtent: rowHeight,
                  itemCount: peers.length,
                  itemBuilder: (context, i) {
                    final peer = peers[i];
                    final (
                      status,
                      label,
                    ) = !serverUnreachable && !_recent.hasOnlineState(peer.id)
                        ? (LgDeviceStatus.querying, l10n.recentQuerying)
                        : peer.online
                        ? (LgDeviceStatus.online, l10n.recentOnline)
                        : (LgDeviceStatus.offline, l10n.recentOffline);
                    final userHost = peerUserHost(peer);
                    final current = isCurrent(i);
                    return _AskedRow(
                      key: ValueKey(peer.id),
                      id: peer.id,
                      onlines: _onlines,
                      child: LgDeviceRow(
                        name: peerDisplayName(peer),
                        id: formatPeerId(peer.id),
                        platform: lgPlatformOf(peer.platform),
                        status: status,
                        statusLabel: label,
                        userHost: userHost.isEmpty ? null : userHost,
                        source: source,
                        selected: current.selected,
                        highlighted: current.highlighted,
                        topDivider: i > 0,
                        connectLabel: l10n.connectBoxConnect,
                        onTap: () {
                          setState(() => _current = peer.id);
                          // A click outside the box takes the focus away on Windows; Enter
                          // runs the row from the box.
                          widget.focusNode.requestFocus();
                        },
                        onDoubleTap: () => _connect(peer.id),
                        onConnect: () => _connect(peer.id),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
