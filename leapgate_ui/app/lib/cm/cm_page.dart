import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/cm_core.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;
import 'package:flutter_hbb/models/server_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../icons/lg_icon.dart';
import '../l10n/app_localizations.dart';
import '../theme/lg_tokens.dart';
import '../widgets/lg_button.dart';
import '../widgets/lg_feedback.dart';
import '../widgets/lg_pressable.dart';
import '../widgets/lg_selection.dart';
import '../widgets/lg_tooltip.dart';
import 'cm_parts.dart';
import 'cm_strip.dart';
import 'cm_window.dart';

// The connection manager's page (docs/新界面/01-内容与逻辑说明.md §3.3, A-P3.html): a tab per
// connection, the selected visitor's header, permissions and buttons; collapsed, the strip.
// Upstream: `flutter/lib/desktop/pages/server_page.dart`. The chat and file log side panels
// come with the second stage; their header buttons are there and do nothing yet.

/// Where a dropped remote click is reported: next to what was clicked (01 §3.3).
enum _HintPlace { header, permissions, actions, strip }

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

  _HintPlace? _blocked;
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

  VoidCallback _guarded(Client client, _HintPlace place, VoidCallback action) =>
      () => cmCheckClickTime(
        client.id,
        action,
        onBlocked: () => _showBlocked(place),
      );

  void _showBlocked(_HintPlace place) {
    if (!mounted) return;
    _blockedTimer?.cancel();
    setState(() => _blocked = place);
    _blockedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _blocked = null);
    });
  }

  /// More than one connection: always asked, whatever the main window's close confirmation
  /// is set to (02 R2-Q16).
  void _onClose() {
    if (_model.clients.length <= 1) {
      widget.window.close();
    } else {
      setState(() => _confirmingClose = true);
    }
  }

  Future<void> _closeDisconnected(Client client) async {
    if (await cmRemoveDisconnected(client)) await widget.window.close();
  }

  @override
  Widget build(BuildContext context) {
    final clients = _model.clients;
    final client = clients.where((c) => c.id == _selected).firstOrNull;
    if (widget.window.view.value == CmView.strip) {
      return Scaffold(
        body: CmStrip(
          clients: clients,
          seconds: _seconds,
          blocked: _blocked == _HintPlace.strip,
          onExpand: widget.window.expand,
          onDrag: widget.window.dragStrip,
          onDragEnd: widget.window.endStripDrag,
          onButton: clients.length == 1
              ? _guarded(
                  clients.single,
                  _HintPlace.strip,
                  () => _stripButton(clients.single),
                )
              : () {},
        ),
      );
    }
    final l10n = AppLocalizations.of(context)!;
    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titleArea(l10n),
        if (clients.isNotEmpty) _tabs(clients, l10n),
        if (client != null)
          Expanded(
            // Upstream `_buildKeyEventBlock`: the remote user's keyboard cannot reach the
            // buttons through the focus.
            child: ExcludeFocus(
              excluding: !allowRemoteCmModification(),
              child: _card(client, l10n),
            ),
          ),
      ],
    );
    if (clients.isNotEmpty) {
      // Upstream listens to down and move only, and Flutter's move is a drag; 01 §3.3 cancels
      // on any mouse movement too.
      body = Listener(
        onPointerDown: _onPointer,
        onPointerMove: _onPointer,
        onPointerHover: _onPointer,
        child: body,
      );
    }
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          body,
          if (_confirmingClose)
            LgDialogScrim(
              onEscape: () => setState(() => _confirmingClose = false),
              child: LgConfirmDialog(
                title: l10n.cmCloseAllTitle,
                actions: [
                  LgDialogAction(
                    label: l10n.cmCancel,
                    onPressed: () => setState(() => _confirmingClose = false),
                  ),
                  LgDialogAction(
                    label: l10n.cmDisconnect,
                    kind: LgButtonKind.dangerSolid,
                    onPressed: () {
                      setState(() => _confirmingClose = false);
                      widget.window.close();
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _stripButton(Client client) {
    if (client.disconnected) {
      _closeDisconnected(client);
    } else {
      cmDisconnect(client);
    }
  }

  Widget _titleArea(AppLocalizations l10n) {
    final t = LgTokens.of(context);
    return SizedBox(
      height: t.sizes.button + LgSpace.s2,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => widget.window.startDragging(),
              child: Padding(
                padding: const EdgeInsets.only(left: LgSpace.s3),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.appName,
                    style: t.textS.copyWith(color: t.colors.text2),
                  ),
                ),
              ),
            ),
          ),
          LgIconButton(
            icon: LgIcons.dockTop,
            label: l10n.cmCollapse,
            onPressed: widget.window.collapse,
          ),
          LgIconButton(
            icon: LgIcons.x,
            label: l10n.cmClose,
            onPressed: _onClose,
          ),
        ],
      ),
    );
  }

  Widget _tabs(List<Client> clients, AppLocalizations l10n) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
      child: Row(
        children: [
          for (final client in clients)
            LgTooltip(
              message: l10n.cmConnectionNumber(client.id),
              child: LgPressable(
                onPressed: () => setState(() => _selected = client.id),
                selected: client.id == _selected,
                semanticLabel: client.name,
                builder: (context, states) => Container(
                  height: t.sizes.button,
                  padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
                  decoration: BoxDecoration(
                    color: client.id == _selected ? c.cmBand : null,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(LgRadius.r10),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LgIcon(
                        cmKindIcon(client),
                        size: 16,
                        color: client.disconnected ? c.text2 : c.text,
                      ),
                      const SizedBox(width: LgSpace.s1),
                      ExcludeSemantics(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 100),
                          child: Text(
                            client.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textS.copyWith(
                              color: client.disconnected ? c.text2 : c.text,
                            ),
                          ),
                        ),
                      ),
                      Obx(() {
                        final unread = client.unreadChatMessageCount.value;
                        if (unread == 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(left: LgSpace.s1),
                          child: Text(
                            '$unread',
                            style: t.textS.copyWith(color: c.accent),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(Client client, AppLocalizations l10n) {
    final t = LgTokens.of(context);
    final permissions = cmPermissionsOf(client);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(LgSpace.s2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(client, l10n),
                if (_blocked == _HintPlace.header)
                  Padding(
                    padding: const EdgeInsets.only(top: LgSpace.s1),
                    child: CmBlockedHint(l10n.cmBlockedRemotely),
                  ),
                if (cmSessionKind(client) == CmSessionKind.exit)
                  Padding(
                    padding: const EdgeInsets.only(top: LgSpace.s3),
                    child: Text(
                      l10n.cmExitNote,
                      style: t.textS.copyWith(color: t.colors.text),
                    ),
                  ),
                if (permissions.isNotEmpty)
                  _permissions(client, permissions, l10n),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LgSpace.s2,
            0,
            LgSpace.s2,
            LgSpace.s2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_blocked == _HintPlace.actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: LgSpace.s1),
                  child: CmBlockedHint(l10n.cmBlockedRemotely),
                ),
              for (final row in _actions(client, l10n))
                Padding(
                  padding: const EdgeInsets.only(top: LgSpace.s1),
                  child: row,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(Client client, AppLocalizations l10n) {
    final t = LgTokens.of(context);
    final c = t.colors;
    String status;
    if (!client.authorized) {
      status = l10n.cmStatusRequesting;
    } else if (client.disconnected) {
      status = l10n.cmStatusDisconnected;
    } else if (client.incomingVoiceCall) {
      status = l10n.cmStatusVoiceRequest;
    } else if (client.inVoiceCall) {
      status = l10n.cmStatusInVoiceCall;
    } else {
      status = l10n.cmStatusConnected;
    }
    final counting = client.authorized && !client.disconnected;
    final kind = cmSessionKind(client);
    // Upstream `server_page.dart:562-581`: the chat (or, for file transfer, the file log) once
    // authorized; terminal, port forwarding and exit nodes have neither.
    final side =
        client.authorized &&
        (kind == CmSessionKind.remoteDesktop ||
            kind == CmSessionKind.fileTransfer ||
            kind == CmSessionKind.camera);
    return Container(
      padding: const EdgeInsets.all(LgSpace.s3),
      decoration: BoxDecoration(
        color: c.cmBand,
        borderRadius: BorderRadius.circular(LgRadius.r12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CmAvatar(client: client, size: 56),
          const SizedBox(width: LgSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textM.copyWith(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  formatPeerId(client.peerId),
                  style: t.textS.copyWith(color: c.text2),
                ),
                Text(
                  cmKindLabel(l10n, client),
                  style: t.textS.copyWith(color: c.text),
                ),
                Text(
                  counting
                      ? '$status ${cmDuration(_seconds[client.id] ?? 0)}'
                      : status,
                  style: t.textS.copyWith(color: c.text2),
                ),
              ],
            ),
          ),
          if (side)
            kind == CmSessionKind.fileTransfer
                ? LgIconButton(
                    icon: LgIcons.files,
                    label: l10n.cmFileLog,
                    onPressed: _guarded(client, _HintPlace.header, () {}),
                  )
                : LgIconButton(
                    icon: LgIcons.chat,
                    label: l10n.cmChat,
                    onPressed: _guarded(client, _HintPlace.header, () {}),
                  ),
        ],
      ),
    );
  }

  Widget _permissions(
    Client client,
    List<CmPermission> permissions,
    AppLocalizations l10n,
  ) {
    final t = LgTokens.of(context);
    final canModify = cmCanModifyPermissions();
    Widget cell(CmPermission p) {
      final label = cmPermissionLabel(l10n, p);
      final value = cmPermissionValue(client, p);
      return Row(
        children: [
          LgSwitch(
            value: value,
            semanticLabel: label,
            onChanged: canModify
                ? (v) => _guarded(
                    client,
                    _HintPlace.permissions,
                    () => setState(() => cmSwitchPermission(client, p, v)),
                  )()
                : null,
          ),
          const SizedBox(width: LgSpace.s2),
          Expanded(
            child: ExcludeSemantics(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textS.copyWith(color: t.colors.text),
              ),
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: LgSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.cmPermissions,
            style: t.textS.copyWith(
              color: t.colors.text2,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_blocked == _HintPlace.permissions)
            Padding(
              padding: const EdgeInsets.only(top: LgSpace.s1),
              child: CmBlockedHint(l10n.cmBlockedRemotely),
            ),
          for (var i = 0; i < permissions.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(top: LgSpace.s2),
              child: Row(
                children: [
                  Expanded(child: cell(permissions[i])),
                  const SizedBox(width: LgSpace.s2),
                  Expanded(
                    child: i + 1 < permissions.length
                        ? cell(permissions[i + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The buttons of 01 §3.3's table, each guarded against the remote user's clicks
  /// (`server_page.dart:873-1235`).
  List<Widget> _actions(Client client, AppLocalizations l10n) {
    VoidCallback g(VoidCallback action) =>
        _guarded(client, _HintPlace.actions, action);
    Widget wide(
      String label,
      VoidCallback onPressed, {
      LgButtonKind kind = LgButtonKind.secondary,
    }) => SizedBox(
      width: double.infinity,
      child: LgButton(label: label, kind: kind, onPressed: g(onPressed)),
    );
    Widget pair(Widget a, Widget b) => Row(
      children: [
        Expanded(child: a),
        const SizedBox(width: LgSpace.s2),
        Expanded(child: b),
      ],
    );

    if (client.disconnected) {
      return [
        wide(
          l10n.cmClose,
          () => _closeDisconnected(client),
          kind: LgButtonKind.primary,
        ),
      ];
    }
    if (!client.authorized) {
      final decline = wide(l10n.cmDecline, () => cmDisconnect(client));
      if (_model.approveMode == 'password') {
        final t = LgTokens.of(context);
        return [
          Text(
            l10n.cmWaitingForPassword,
            textAlign: TextAlign.center,
            style: t.textS.copyWith(color: t.colors.text2),
          ),
          decline,
        ];
      }
      return [
        wide(l10n.cmAccept, () {
          _model.sendLoginResponse(client, true);
          widget.window.collapse();
        }, kind: LgButtonKind.primary),
        if (cmShowAcceptAndElevate(_model, client))
          pair(
            wide(l10n.cmAcceptAndElevate, () {
              _model.sendLoginResponse(client, true);
              cmElevate(_model, client);
              widget.window.collapse();
            }),
            decline,
          )
        else
          decline,
      ];
    }
    return [
      if (client.incomingVoiceCall)
        pair(
          wide(
            l10n.cmAnswer,
            () => _model.handleVoiceCall(client, true),
            kind: LgButtonKind.primary,
          ),
          wide(l10n.cmDecline, () => _model.handleVoiceCall(client, false)),
        ),
      if (client.inVoiceCall)
        wide(
          l10n.cmHangUp,
          () => cmCloseVoiceCall(client),
          kind: LgButtonKind.danger,
        ),
      if (client.fromSwitch)
        wide(l10n.cmSwitchBack, () => cmSwitchBack(client)),
      if (cmShowElevate(_model, client))
        wide(l10n.cmElevate, () {
          cmElevate(_model, client);
          widget.window.collapse();
        }),
      wide(
        l10n.cmDisconnect,
        () => cmDisconnect(client),
        kind: LgButtonKind.danger,
      ),
    ];
  }
}
