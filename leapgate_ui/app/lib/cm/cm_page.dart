import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/cm_chat.dart';
import 'package:flutter_hbb/leapgate/cm_core.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;
import 'package:flutter_hbb/models/chat_model.dart' show VoiceInputs;
import 'package:flutter_hbb/models/cm_file_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:window_manager/window_manager.dart';

import '../icons/lg_icon.dart';
import '../l10n/app_localizations.dart';
import '../widgets/lg_button.dart';
import '../widgets/lg_chat.dart';
import '../widgets/lg_cm_actions.dart';
import '../widgets/lg_cm_chat.dart';
import '../widgets/lg_cm_close_confirm.dart';
import '../widgets/lg_cm_files.dart';
import '../widgets/lg_cm_frame.dart';
import '../widgets/lg_cm_head.dart';
import '../widgets/lg_cm_permissions.dart';
import '../widgets/lg_cm_tabs.dart';
import '../widgets/lg_feedback.dart';
import '../widgets/lg_panel_inputs.dart' show LgSelectItem;
import 'cm_parts.dart';
import 'cm_strip.dart';
import 'cm_window.dart';

// The connection manager's page (docs/新界面/01-内容与逻辑说明.md §3.3, A-P3.html): a tab per
// connection, the selected visitor's header, permissions and buttons, and the side panel with
// the chat or the file log; collapsed, the strip. Upstream:
// `flutter/lib/desktop/pages/server_page.dart`, the CM parts of `models/chat_model.dart`.

/// Where a dropped remote click is reported (01 §3.3): over the panel for the header button,
/// the permissions and closing; on the strip; over the side panel; or over the button itself
/// (`action:` + label). [_hintNoMic] puts "未找到音频输入设备" on the microphone field instead.
const _hintPanel = 'panel';
const _hintStrip = 'strip';
const _hintSide = 'side';
const _hintMic = 'mic';
const _hintNoMic = 'no-mic';

class CmPage extends StatefulWidget {
  const CmPage({
    super.key,
    required this.model,
    required this.chat,
    required this.files,
    required this.window,
  });

  final ServerModel model;
  final CmChatModel chat;
  final CmFileModel files;
  final CmShellWindow window;

  @override
  State<CmPage> createState() => _CmPageState();
}

class _CmPageState extends State<CmPage> with WindowListener {
  ServerModel get _model => widget.model;

  int? _selected;
  var _order = <int>[];

  /// Avatar pictures by connection, made once: a new image object each second would load the
  /// picture again.
  final _avatars = <int, ImageProvider?>{};

  /// Connected seconds by connection, counted while authorized and connected, as upstream's
  /// header does (`server_page.dart:438-444`).
  final _seconds = <int, int>{};
  Timer? _clock;

  String? _blocked;
  Timer? _blockedTimer;

  bool _confirmingClose = false;

  /// The side panel was opened. It shows while the selected visitor has one (`_hasSide`); the
  /// window is as wide as it needs (upstream keeps one `isShowCMSidePage` for all tabs too).
  bool _sideOpen = false;

  /// One draft for every visitor, as upstream's one text controller.
  final _chatInput = TextEditingController();
  final _chatFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _model.addListener(_onModel);
    widget.chat.addListener(_onSideContent);
    widget.files.addListener(_onSideContent);
    widget.chat.onReceive = _onChatReceived;
    widget.window.view.addListener(_onView);
    windowManager.addListener(this);
    _model.updateClientState();
    _syncTabs();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    _model.removeListener(_onModel);
    widget.chat.removeListener(_onSideContent);
    widget.files.removeListener(_onSideContent);
    widget.chat.onReceive = null;
    widget.window.view.removeListener(_onView);
    windowManager.removeListener(this);
    _clock?.cancel();
    _blockedTimer?.cancel();
    _chatInput.dispose();
    _chatFocus.dispose();
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

  void _onModel() {
    setState(_syncTabs);
    _syncSide();
  }

  /// A message or a file record came; the unread counts they change are read in build.
  void _onSideContent() => setState(() {});

  Client? get _selectedClient =>
      _model.clients.where((c) => c.id == _selected).firstOrNull;

  /// Upstream `server_page.dart:562-581`: the chat (or, for file transfer, the file log) once
  /// authorized; terminal, port forwarding and exit nodes have neither.
  bool _hasSide(Client client) {
    final kind = cmSessionKind(client);
    return client.authorized &&
        (kind == CmSessionKind.remoteDesktop ||
            kind == CmSessionKind.fileTransfer ||
            kind == CmSessionKind.camera);
  }

  /// The visitor whose chat or file log shows.
  Client? get _sideClient {
    final client = _selectedClient;
    return _sideOpen && client != null && _hasSide(client) ? client : null;
  }

  /// After the selection or the side panel changed: the window's width, and what is shown is
  /// read (upstream `toggleCMSidePage`, `_addUnread`).
  void _syncSide() {
    final client = _sideClient;
    widget.window.setExpanded(client != null);
    widget.files.shownConnId = client?.id;
    client?.unreadChatMessageCount.value = 0;
  }

  void _select(Client client) {
    setState(() {
      _selected = client.id;
      // Upstream `server_page.dart:131-145`: a tab with something unread opens it.
      if (client.unreadChatMessageCount.value > 0 && _hasSide(client)) {
        _sideOpen = true;
      }
    });
    _syncSide();
  }

  void _toggleSide() {
    setState(() => _sideOpen = !_sideOpen);
    _syncSide();
    final client = _sideClient;
    if (client != null && cmSessionKind(client) != CmSessionKind.fileTransfer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _chatFocus.context != null) _chatFocus.requestFocus();
      });
    }
  }

  /// Upstream `ChatModel.receive` in the CM: the window comes up with the sender's chat, unless
  /// the user is writing to another visitor; the sender's tab then counts it as unread.
  void _onChatReceived(Client client) {
    widget.window.bringToFront();
    final shown = _sideClient;
    if (shown != null && shown.id != client.id && _chatFocus.hasFocus) {
      client.unreadChatMessageCount.value += 1;
      setState(() {});
      return;
    }
    setState(() {
      _selected = client.id;
      _sideOpen = true;
    });
    _syncSide();
  }

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
    _avatars.removeWhere((id, _) => !ids.contains(id));
    // The window is hidden: the next visitor, within the 6 s before the process ends, starts
    // with it closed.
    if (ids.isEmpty) _sideOpen = false;
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

  /// Closing ends every session, so it is guarded too (upstream leaves its close button
  /// unguarded); the hint goes over the panel. The time is asked of a visitor still connected:
  /// a disconnected one has no connection to answer, and its stale time would let the remote
  /// side through. With nobody connected there is no remote side.
  void _guardClose(VoidCallback action) {
    final client = _model.clients.where((c) => !c.disconnected).firstOrNull;
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
      // Upstream `_buildKeyEventBlock`: the remote user's keyboard cannot reach the buttons
      // through the focus. Title buttons, tabs, panel and the confirmation: the service only
      // takes the remote side's input time on a left button release and Enter, so Tab and Space
      // would pass the click guard. The chat input takes it; sending is guarded.
      sideFocusOnly: !allowRemoteCmModification(),
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
              semanticLabel: c.disconnected
                  ? l10n.cmTabNameGone(c.name, cmKindLabel(l10n, c))
                  : l10n.cmTabName(c.name, cmKindLabel(l10n, c)),
            ),
        ],
        selected: client == null ? 0 : clients.indexOf(client),
        onSelect: (i) => _select(clients[i]),
      ),
      panel: client == null
          ? const SizedBox.shrink()
          : LgCmTipAnchor(
              tip: _blocked == _hintPanel ? l10n.cmBlockedRemotely : null,
              child: _panel(client, l10n),
            ),
      side: _side(l10n),
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
    // Left before being let in counts as left, as in the action area.
    if (client.disconnected) {
      status = LgCmStatusLine(
        phase: LgCmPhase.disconnected,
        label: l10n.cmStatusDisconnected,
      );
    } else if (!client.authorized) {
      status = LgCmStatusLine(
        phase: LgCmPhase.requesting,
        label: l10n.cmStatusRequesting,
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
    return LgCmHeader(
      name: client.name,
      id: formatPeerId(client.peerId),
      identity: cmIdentity(client),
      type: cmKindLabel(l10n, client),
      status: status,
      avatarText: cmLetter(client),
      avatarImage: _avatars.putIfAbsent(client.id, () => cmAvatarImage(client)),
      sideButton: _hasSide(client)
          ? LgCmSideButton(
              icon: kind == CmSessionKind.fileTransfer
                  ? LgIcons.files
                  : LgIcons.chat,
              label: kind == CmSessionKind.fileTransfer
                  ? l10n.cmFileLog
                  : l10n.cmChat,
              selected: _sideClient == client,
              unread: client.unreadChatMessageCount.value,
              onPressed: _guarded(client, _hintPanel, _toggleSide),
            )
          : null,
    );
  }

  /// The chat or the file log of [_sideClient] (01 §3.3); a dropped remote click on "发送" is
  /// reported over it.
  Widget? _side(AppLocalizations l10n) {
    final client = _sideClient;
    if (client == null) return null;
    final Widget panel;
    if (cmSessionKind(client) == CmSessionKind.fileTransfer) {
      panel = LgCmSidePanel(
        icon: LgIcons.files,
        title: l10n.cmFileLog,
        child: LgCmFileLog(
          // Newest first: what is going on now is on top without scrolling.
          entries: [
            for (final log in widget.files.logOf(client.id).reversed)
              cmFileEntry(l10n, log),
          ],
          emptyText: l10n.cmFileLogEmpty,
        ),
      );
    } else {
      String two(int v) => v.toString().padLeft(2, '0');
      panel = LgCmSidePanel(
        icon: LgIcons.chat,
        title: l10n.cmChat,
        child: LgCmChat(
          messages: [
            for (final m in widget.chat.messagesOf(client))
              LgChatMessage(
                text: m.text,
                time: '${two(m.at.hour)}:${two(m.at.minute)}',
                mine: m.isOut,
                sender: m.isOut ? null : client.name,
              ),
          ],
          controller: _chatInput,
          focusNode: _chatFocus,
          placeholder: l10n.chatPlaceholder,
          sendLabel: l10n.chatSend,
          mineLabel: l10n.chatMine,
          theirsLabel: l10n.chatTheirs,
          emptyText: l10n.cmChatEmpty,
          readOnly: client.disconnected,
          readOnlyText: l10n.cmChatPeerLeft,
          onSend: (text) => _guarded(client, _hintSide, () {
            if (widget.chat.send(client, text)) _chatInput.clear();
          })(),
        ),
      );
    }
    return LgCmTipAnchor(
      tip: _blocked == _hintSide ? l10n.cmBlockedRemotely : null,
      child: panel,
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
        _CmMicRow(
          tip: switch (_blocked) {
            _hintMic => l10n.cmBlockedRemotely,
            _hintNoMic => l10n.cmNoAudioInput,
            _ => null,
          },
          onNoDevices: () => _showBlocked(_hintNoMic),
          onHangUp: _guarded(client, _hintMic, () => cmCloseVoiceCall(client)),
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

/// During a voice call: the microphones of this device, "系统声音" first where it can be used
/// (upstream `server_page.dart:893-960`, `AudioInput`), and "挂断". Without any, pressing the
/// field says so (upstream's `no_audio_input_device_tip`). Choosing one is not guarded, as
/// upstream's menu is not.
class _CmMicRow extends StatefulWidget {
  const _CmMicRow({
    required this.tip,
    required this.onNoDevices,
    required this.onHangUp,
  });

  final String? tip;
  final VoidCallback onNoDevices;
  final VoidCallback onHangUp;

  @override
  State<_CmMicRow> createState() => _CmMicRowState();
}

class _CmMicRowState extends State<_CmMicRow> {
  VoiceInputs? _inputs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inputs = await cmVoiceInputs();
    if (mounted) setState(() => _inputs = inputs);
  }

  Future<void> _choose(String device) async {
    await cmSetVoiceInput(device);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final inputs = _inputs;
    final loopback = inputs?.loopback ?? false;
    final current = inputs?.current ?? '';
    return LgCmMicRow(
      microphoneLabel: l10n.chatMicrophone,
      placeholder: l10n.cmChooseMicrophone,
      devices: [
        if (loopback) LgSelectItem('', l10n.chatSystemSound),
        for (final d in inputs?.devices ?? const <String>[]) LgSelectItem(d, d),
      ],
      // '' is the default: "系统声音" where there is one, otherwise nothing chosen.
      device: current.isEmpty && !loopback ? null : current,
      onDeviceChanged: _choose,
      onNoDevices: widget.onNoDevices,
      hangUpLabel: l10n.cmHangUp,
      onHangUp: widget.onHangUp,
      tip: widget.tip,
    );
  }
}
