import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/cm_core.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;
import 'package:flutter_hbb/models/server_model.dart';
import 'package:window_manager/window_manager.dart';

import '../icons/lg_icon.dart';
import '../l10n/app_localizations.dart';
import '../widgets/lg_button.dart';
import '../widgets/lg_cm_actions.dart';
import '../widgets/lg_cm_close_confirm.dart';
import '../widgets/lg_cm_frame.dart';
import '../widgets/lg_cm_head.dart';
import '../widgets/lg_cm_permissions.dart';
import '../widgets/lg_cm_tabs.dart';
import '../widgets/lg_feedback.dart';
import 'cm_parts.dart';
import 'cm_strip.dart';
import 'cm_window.dart';

// The connection manager's page (docs/新界面/01-内容与逻辑说明.md §3.3, A-P3.html): a tab per
// connection, the selected visitor's header, permissions and buttons; collapsed, the strip.
// Upstream: `flutter/lib/desktop/pages/server_page.dart`. The chat and file log side panels
// come with the second stage; their header buttons are there and do nothing yet.

/// Where a dropped remote click is reported (01 §3.3): over the panel for the header button,
/// the permissions and closing; on the strip; or over the button itself (`action:` + label).
const _hintPanel = 'panel';
const _hintStrip = 'strip';

class CmPage extends StatefulWidget {
  const CmPage({super.key, required this.model, required this.window});

  final ServerModel model;
  final CmShellWindow window;

  @override
  State<CmPage> createState() => _CmPageState();
}

class _CmPageState extends State<CmPage> with WindowListener {
  ServerModel get _model => widget.model;

  int? _selected;
  var _order = <int>[];

  /// Connected seconds by connection, counted while authorized and connected, as upstream's
  /// header does (`server_page.dart:438-444`).
  final _seconds = <int, int>{};
  Timer? _clock;

  String? _blocked;
  Timer? _blockedTimer;

  bool _confirmingClose = false;

  @override
  void initState() {
    super.initState();
    _model.addListener(_onModel);
    widget.window.view.addListener(_onView);
    windowManager.addListener(this);
    _model.updateClientState();
    _syncTabs();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _model.removeListener(_onModel);
    widget.window.view.removeListener(_onView);
    windowManager.removeListener(this);
    _clock?.cancel();
    _blockedTimer?.cancel();
    super.dispose();
  }

  /// Upstream `_DesktopServerPageState.onWindowClose`; on Windows every close is the operator's.
  @override
  void onWindowClose() {
    _model.closeAll().then((_) async {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    });
  }

  void _onView() => setState(() {});

  void _onModel() => setState(_syncTabs);

  /// A new connection's tab is selected, as upstream's tab controller does when a tab is added;
  /// when the selected one goes, the one that takes its place.
  void _syncTabs() {
    final ids = [for (final c in _model.clients) c.id];
    final added = ids.where((id) => !_order.contains(id)).toList();
    if (added.isNotEmpty) {
      _selected = added.last;
    } else if (!ids.contains(_selected)) {
      final at = _order.indexOf(_selected ?? -1);
      _selected = ids.isEmpty ? null : ids[at.clamp(0, ids.length - 1)];
    }
    _seconds.removeWhere((id, _) => !ids.contains(id));
    _order = ids;
  }

  void _onTick() {
    final counting = _model.clients
        .where((c) => c.authorized && !c.disconnected)
        .toList();
    if (counting.isEmpty) return;
    setState(() {
      for (final c in counting) {
        _seconds[c.id] = (_seconds[c.id] ?? 0) + 1;
      }
    });
  }

  /// Pressing or moving the mouse in the full window cancels the pending collapse
  /// (upstream `server_page.dart:180-186`, 01 §3.3).
  void _onPointer(PointerEvent _) {
    if (_model.cmHiddenTimer != null) {
      _model.cmHiddenTimer!.cancel();
      _model.cmHiddenTimer = null;
    }
  }

  VoidCallback _guarded(Client client, String place, VoidCallback action) =>
      () => cmCheckClickTime(
        client.id,
        action,
        onBlocked: () => _showBlocked(place),
      );

  void _showBlocked(String place) {
    if (!mounted) return;
    _blockedTimer?.cancel();
    setState(() => _blocked = place);
    _blockedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _blocked = null);
    });
  }

  /// Closing ends every session, so it is guarded too, against the selected visitor's input
  /// (upstream leaves its close button unguarded); the hint goes over the panel.
  void _guardClose(VoidCallback action) {
    final client = _model.clients.where((c) => c.id == _selected).firstOrNull;
    if (client == null) {
      action();
    } else {
      _guarded(client, _hintPanel, action)();
    }
  }

  /// More than one connection: always asked, whatever the main window's close confirmation
  /// is set to (02 R2-Q16).
  void _onClose() => _guardClose(() {
    if (_model.clients.length <= 1) {
      widget.window.close();
    } else {
      setState(() => _confirmingClose = true);
    }
  });

  Future<void> _closeDisconnected(Client client) async {
    if (await cmRemoveDisconnected(client)) await widget.window.close();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final clients = _model.clients;
    final client = clients.where((c) => c.id == _selected).firstOrNull;
    if (widget.window.view.value == CmView.strip) {
      return Scaffold(
        // As the panel's: the remote user's keyboard cannot reach the button.
        body: ExcludeFocus(
          excluding: !allowRemoteCmModification(),
          child: CmStrip(
            clients: clients,
            seconds: _seconds,
            blocked: _blocked == _hintStrip,
            onExpand: widget.window.expand,
            onDragStart: widget.window.startStripDrag,
            onDrag: widget.window.dragStrip,
            onDragEnd: widget.window.endStripDrag,
            onButton: clients.length == 1
                ? _guarded(
                    clients.single,
                    _hintStrip,
                    () => _stripButton(clients.single),
                  )
                : () {},
          ),
        ),
      );
    }
    Widget frame = LgCmFrame(
      title: l10n.appName,
      collapseLabel: l10n.cmCollapse,
      closeLabel: l10n.cmClose,
      onCollapse: widget.window.collapse,
      onClose: _onClose,
      onStartDrag: widget.window.startDragging,
      tabs: LgCmTabStrip(
        tabs: [
          for (final c in clients)
            LgCmTab(
              kind: cmTabKind(c),
              name: c.name,
              identity: cmIdentity(c),
              unread: c.unreadChatMessageCount.value,
              gone: c.disconnected,
              tooltip: l10n.cmConnectionNumber(c.id),
            ),
        ],
        selected: client == null ? 0 : clients.indexOf(client),
        onSelect: (i) => setState(() => _selected = clients[i].id),
      ),
      panel: client == null
          ? const SizedBox.shrink()
          // Upstream `_buildKeyEventBlock`: the remote user's keyboard cannot reach the
          // buttons through the focus.
          : ExcludeFocus(
              excluding: !allowRemoteCmModification(),
              child: LgCmTipAnchor(
                tip: _blocked == _hintPanel ? l10n.cmBlockedRemotely : null,
                child: _panel(client, l10n),
              ),
            ),
      overlay: _confirmingClose
          ? LgCmCloseConfirm(
              title: l10n.cmCloseAllTitle,
              onEscape: () => setState(() => _confirmingClose = false),
              actions: [
                LgDialogAction(
                  label: l10n.cmCancel,
                  isDefault: true,
                  onPressed: () => setState(() => _confirmingClose = false),
                ),
                LgDialogAction(
                  label: l10n.cmDisconnect,
                  kind: LgButtonKind.danger,
                  onPressed: () => _guardClose(() {
                    setState(() => _confirmingClose = false);
                    widget.window.close();
                  }),
                ),
              ],
            )
          : null,
    );
    if (clients.isNotEmpty) {
      // Upstream listens to down and move only, and Flutter's move is a drag; 01 §3.3 cancels
      // on any mouse movement too.
      frame = Listener(
        onPointerDown: _onPointer,
        onPointerMove: _onPointer,
        onPointerHover: _onPointer,
        child: frame,
      );
    }
    return Scaffold(body: frame);
  }

  void _stripButton(Client client) {
    if (client.disconnected) {
      _closeDisconnected(client);
    } else {
      cmDisconnect(client);
    }
  }

  Widget _panel(Client client, AppLocalizations l10n) {
    final permissions = cmPermissionsOf(client);
    final kind = cmSessionKind(client);
    return LgCmPanel(
      header: _header(client, l10n),
      body: kind == CmSessionKind.exit
          ? LgCmNoteBlock(text: l10n.cmExitNote)
          : permissions.isEmpty
          ? null
          : LgCmPermissions(
              title: l10n.cmPermissions,
              readOnly: !cmCanModifyPermissions(),
              items: [
                for (final p in permissions)
                  LgCmPermission(
                    label: cmPermissionLabel(l10n, p),
                    value: cmPermissionValue(client, p),
                    onChanged: (v) => _guarded(
                      client,
                      _hintPanel,
                      () => setState(() => cmSwitchPermission(client, p, v)),
                    )(),
                  ),
              ],
            ),
      actions: LgCmActions(children: _actions(client, l10n)),
    );
  }

  Widget _header(Client client, AppLocalizations l10n) {
    final LgCmStatusLine status;
    final time = cmDuration(_seconds[client.id] ?? 0);
    if (!client.authorized) {
      status = LgCmStatusLine(
        phase: LgCmPhase.requesting,
        label: l10n.cmStatusRequesting,
      );
    } else if (client.disconnected) {
      status = LgCmStatusLine(
        phase: LgCmPhase.disconnected,
        label: l10n.cmStatusDisconnected,
      );
    } else if (client.incomingVoiceCall) {
      status = LgCmStatusLine(
        phase: LgCmPhase.voiceRequesting,
        label: l10n.cmStatusVoiceRequest,
        time: time,
      );
    } else if (client.inVoiceCall) {
      status = LgCmStatusLine(
        phase: LgCmPhase.voiceActive,
        label: l10n.cmStatusInVoiceCall,
        time: time,
      );
    } else {
      status = LgCmStatusLine(
        phase: LgCmPhase.connected,
        label: l10n.cmStatusConnected,
        time: time,
      );
    }
    final kind = cmSessionKind(client);
    // Upstream `server_page.dart:562-581`: the chat (or, for file transfer, the file log) once
    // authorized; terminal, port forwarding and exit nodes have neither.
    final side =
        client.authorized &&
        (kind == CmSessionKind.remoteDesktop ||
            kind == CmSessionKind.fileTransfer ||
            kind == CmSessionKind.camera);
    return LgCmHeader(
      name: client.name,
      id: formatPeerId(client.peerId),
      identity: cmIdentity(client),
      type: cmKindLabel(l10n, client),
      status: status,
      avatarText: cmLetter(client),
      avatarImage: cmAvatarImage(client),
      sideButton: side
          ? LgCmSideButton(
              icon: kind == CmSessionKind.fileTransfer
                  ? LgIcons.files
                  : LgIcons.chat,
              label: kind == CmSessionKind.fileTransfer
                  ? l10n.cmFileLog
                  : l10n.cmChat,
              onPressed: _guarded(client, _hintPanel, () {}),
            )
          : null,
    );
  }

  /// The buttons of 01 §3.3's table, each guarded against the remote user's clicks
  /// (`server_page.dart:873-1235`), the hint over the button that was clicked.
  List<Widget> _actions(Client client, AppLocalizations l10n) {
    LgCmAction action(
      String label,
      VoidCallback onPressed, {
      LgCmActionKind kind = LgCmActionKind.secondary,
      LgIcons? icon,
    }) {
      final place = 'action:$label';
      return LgCmAction(
        label: label,
        kind: kind,
        icon: icon,
        tip: _blocked == place ? l10n.cmBlockedRemotely : null,
        onPressed: _guarded(client, place, onPressed),
      );
    }

    LgCmActionRow row(LgCmAction a) => LgCmActionRow(actions: [a]);

    if (client.disconnected) {
      return [row(action(l10n.cmClose, () => _closeDisconnected(client)))];
    }
    if (!client.authorized) {
      final decline = action(l10n.cmDecline, () => cmDisconnect(client));
      if (_model.approveMode == 'password') {
        return [LgCmNote(text: l10n.cmWaitingForPassword), row(decline)];
      }
      return [
        row(
          action(l10n.cmAccept, () {
            _model.sendLoginResponse(client, true);
            widget.window.collapse();
          }, kind: LgCmActionKind.primary),
        ),
        if (cmShowAcceptAndElevate(_model, client))
          LgCmActionRow(
            flex: const [2, 1],
            actions: [
              action(l10n.cmAcceptAndElevate, () {
                _model.sendLoginResponse(client, true);
                cmElevate(_model, client);
                widget.window.collapse();
              }, icon: LgIcons.shield),
              decline,
            ],
          )
        else
          row(decline),
      ];
    }
    return [
      if (client.incomingVoiceCall)
        LgCmActionRow(
          actions: [
            action(
              l10n.cmAnswer,
              () => _model.handleVoiceCall(client, true),
              kind: LgCmActionKind.primary,
              icon: LgIcons.call,
            ),
            action(l10n.cmDecline, () => _model.handleVoiceCall(client, false)),
          ],
        ),
      if (client.inVoiceCall)
        row(
          action(
            l10n.cmHangUp,
            () => cmCloseVoiceCall(client),
            icon: LgIcons.callEnd,
          ),
        ),
      if (client.fromSwitch)
        row(action(l10n.cmSwitchBack, () => cmSwitchBack(client))),
      if (cmShowElevate(_model, client))
        row(
          action(l10n.cmElevate, () {
            cmElevate(_model, client);
            widget.window.collapse();
          }, icon: LgIcons.shield),
        ),
      row(
        action(
          l10n.cmDisconnect,
          () => cmDisconnect(client),
          kind: LgCmActionKind.danger,
        ),
      ),
    ];
  }
}
