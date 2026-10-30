import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connect_box.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:window_manager/window_manager.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/navigation.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_menu.dart';
import '../../widgets/lg_status.dart';
import '../../widgets/lg_text_field.dart';

// Examples in the connect box help, from the documentation ranges (01 §7.1 "示例数据").
const _helpExamples = (
  id: '123 456 789',
  ip: '192.0.2.10',
  domain: 'pc.example.com:21118',
  server: '123456789@leapgate.example.com',
);

/// "Connect to ‹input›" as the current row; device IDs are never empty.
const _connectToRow = '';

/// The devices page (01 P1 blocks E and F): the connect box, and under it "Recent" or, while
/// there is input, the search results. M2a has only the "Recent" category.
///
/// One current row stands for both the clicked device ("selected") and the row the arrow keys
/// moved to ("highlighted"); Enter and "Connect" run it. While searching and before the keys
/// move, it is [ConnectBoxSearch.defaultRow]. The rows are placeholders until the designer's
/// `LgDeviceRow` and `LgConnectToRow` (M2a integration).
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
    // Keys of the help button inside the box are its own, and so are the keys the input
    // method is composing with.
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
    final t = LgTokens.of(context);
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: Listenable.merge([_recent, widget.status]),
      builder: (context, _) {
        final search = _search;
        final current = _currentRow(search);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _connectBox(l10n),
            const SizedBox(height: LgSpace.s4),
            Text(
              search == null
                  ? l10n.recentCategory
                  : l10n.connectBoxSearchResults,
              style: t.textM.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: LgSpace.s2),
            Expanded(child: _list(l10n, search, current)),
          ],
        );
      },
    );
  }

  Widget _connectBox(AppLocalizations l10n) {
    final canConnect = _input.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: LgTextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              placeholder: l10n.connectBoxPlaceholder,
              semanticLabel: l10n.connectBoxPlaceholder,
              trailing: LgMenuAnchor(
                width: 360,
                items: [_HelpCard(l10n)],
                builder: (context, menu) => LgIconButton(
                  icon: LgIcons.help,
                  label: l10n.connectBoxHelp,
                  onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: LgSpace.s2),
        LgButton(
          label: l10n.connectBoxConnect,
          kind: LgButtonKind.primary,
          onPressed: canConnect ? _runCurrent : null,
        ),
        LgMenuAnchor(
          width: 320,
          items: [
            LgMenuItem(
              label: l10n.connectBoxRemoteDesktop,
              hint: l10n.connectBoxDefault,
              onPressed: _runCurrent,
            ),
            _NoteMenuItem(
              label: l10n.connectBoxViaRelay,
              note: l10n.connectBoxViaRelayNote,
              onPressed: () => _runCurrent(relay: true),
            ),
          ],
          builder: (context, menu) => LgIconButton(
            icon: LgIcons.chevD,
            label: l10n.connectBoxConnectionType,
            onPressed: canConnect
                ? () => menu.isOpen ? menu.close() : menu.open()
                : null,
          ),
        ),
      ],
    );
  }

  Widget _list(AppLocalizations l10n, ConnectBoxSearch? search, int? current) {
    final t = LgTokens.of(context);
    final note = t.textM.copyWith(color: t.colors.text2);
    if (search == null && !_recent.loaded) {
      return Align(
        alignment: Alignment.topLeft,
        child: Semantics(
          label: l10n.recentLoading,
          child: const LgSpinner(size: 20),
        ),
      );
    }
    if (search == null && _recent.peers.isEmpty) {
      return Text(l10n.recentEmpty, style: note);
    }
    final peers = search?.matches ?? _recent.peers;
    final offset = search == null ? 0 : 1;
    // The UI process asks the server itself, service or not; only an unreachable server leaves
    // the query unanswered.
    final serverUnreachable = widget.status.status == ServiceStatus.notReady;
    return ListView.builder(
      // Rows only exist on screen, so the rows that ask for online state are the visible ones.
      scrollCacheExtent: const ScrollCacheExtent.pixels(0),
      itemCount:
          peers.length + offset + (search != null && peers.isEmpty ? 1 : 0),
      itemBuilder: (context, i) {
        if (search != null && i == 0) {
          return _ConnectToRow(
            text: l10n.connectBoxConnectTo(_input),
            current: current == 0,
            onTap: () => _connect(_input),
          );
        }
        if (search != null && peers.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(LgSpace.s3),
            child: Text(l10n.connectBoxNoMatch, style: note),
          );
        }
        final peer = peers[i - offset];
        return _DeviceRow(
          key: ValueKey(peer.id),
          peer: peer,
          // Rust answers no query while the server is out of reach
          // (`src/client.rs` `query_online_states`): offline, not "checking" forever.
          // "Connecting" (the state at start) and a stopped service still ask.
          status: !serverUnreachable && !_recent.hasOnlineState(peer.id)
              ? (LgStatus.querying, l10n.recentQuerying)
              : peer.online
              ? (LgStatus.online, l10n.recentOnline)
              : (LgStatus.offline, l10n.recentOffline),
          source: search == null ? null : l10n.recentCategory,
          current: current == i,
          connectLabel: l10n.connectBoxConnect,
          onlines: _onlines,
          onTap: () {
            setState(() => _current = peer.id);
            // A click outside the box takes the focus away on Windows; Enter runs the row from
            // the box.
            widget.focusNode.requestFocus();
          },
          onConnect: () => _connect(peer.id),
        );
      },
    );
  }
}

/// "Connect to ‹input›", the first search result.
class _ConnectToRow extends StatelessWidget {
  const _ConnectToRow({
    required this.text,
    required this.current,
    required this.onTap,
  });

  final String text;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Semantics(
      container: true,
      button: true,
      selected: current,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
          alignment: Alignment.centerLeft,
          color: current ? t.colors.nav : null,
          child: Text(text, style: t.text),
        ),
      ),
    );
  }
}

/// One device: name, formatted ID, `user@host`, online state, and "Connect" while hovered.
/// Asks [onlines] about its device while it exists.
class _DeviceRow extends StatefulWidget {
  const _DeviceRow({
    super.key,
    required this.peer,
    required this.status,
    required this.source,
    required this.current,
    required this.connectLabel,
    required this.onlines,
    required this.onTap,
    required this.onConnect,
  });

  final Peer peer;
  final (LgStatus, String) status;
  final String? source;
  final bool current;
  final String connectLabel;
  final OnlineQuery onlines;
  final VoidCallback onTap;
  final VoidCallback onConnect;

  @override
  State<_DeviceRow> createState() => _DeviceRowState();
}

class _DeviceRowState extends State<_DeviceRow> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    widget.onlines.show(widget.peer.id);
  }

  @override
  void dispose() {
    widget.onlines.hide(widget.peer.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final peer = widget.peer;
    final userHost = peerUserHost(peer);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        container: true,
        selected: widget.current,
        child: GestureDetector(
          onTap: widget.onTap,
          onDoubleTap: widget.onConnect,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
            color: widget.current ? c.nav : null,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        peerDisplayName(peer),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [
                          formatPeerId(peer.id),
                          userHost,
                        ].where((s) => s.isNotEmpty).join('  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textS.copyWith(color: c.text2),
                      ),
                    ],
                  ),
                ),
                if (widget.source != null) ...[
                  Text(widget.source!, style: t.textS.copyWith(color: c.text2)),
                  const SizedBox(width: LgSpace.s3),
                ],
                DefaultTextStyle(
                  style: t.textS,
                  child: LgStatusText(widget.status.$1, widget.status.$2),
                ),
                if (_hovered) ...[
                  const SizedBox(width: LgSpace.s3),
                  LgButton(
                    label: widget.connectLabel,
                    onPressed: widget.onConnect,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A menu item with a line of small text under its label ("经中继连接", 01 P1 block E).
class _NoteMenuItem extends StatelessWidget {
  const _NoteMenuItem({
    required this.label,
    required this.note,
    required this.onPressed,
  });

  final String label;
  final String note;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return MenuItemButton(
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LgSpace.s1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: t.text),
            Text(note, style: t.textS.copyWith(color: t.colors.text2)),
          ],
        ),
      ),
    );
  }
}

/// What the connect box takes (upstream `id_input_tip`, rewritten by 01 §7.6).
class _HelpCard extends StatelessWidget {
  const _HelpCard(this.l10n);

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final small = t.textS.copyWith(color: t.colors.text2);
    Widget line(String what, String example) => Padding(
      padding: const EdgeInsets.only(top: LgSpace.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(what, style: t.textS)),
          Expanded(flex: 3, child: Text(example, style: small)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(LgSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.connectBoxHelpTitle,
            style: t.textS.copyWith(fontWeight: FontWeight.w700),
          ),
          line(l10n.connectBoxHelpId, _helpExamples.id),
          line(l10n.connectBoxHelpIp, _helpExamples.ip),
          line(l10n.connectBoxHelpDomain, _helpExamples.domain),
          line(l10n.connectBoxHelpServer, _helpExamples.server),
          const SizedBox(height: LgSpace.s2),
          Text(l10n.connectBoxHelpKey, style: small),
          const SizedBox(height: LgSpace.s1),
          Text(l10n.connectBoxHelpRelay, style: small),
        ],
      ),
    );
  }
}
