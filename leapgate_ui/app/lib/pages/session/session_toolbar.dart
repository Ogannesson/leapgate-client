import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/session_views.dart';
import '../../shell/tab_overlays.dart';
import '../../shell/tab_shortcuts.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_menu.dart';
import '../../widgets/lg_session_toolbar.dart';
import '../../widgets/lg_status.dart';
import '../../widgets/lg_tooltip.dart';
import 'chat/chat.dart';
import 'recording.dart';
import 'route_details.dart';
import 'session_names.dart';
import 'toolbar/action_menu.dart';
import 'toolbar/display_menu.dart';
import 'toolbar/dock.dart';
import 'toolbar/entries.dart';
import 'toolbar/input_menu.dart';
import 'toolbar/monitor_menu.dart';
import 'toolbar/session_menu.dart';
import 'toolbar/session_shortcuts.dart';
import 'toolbar/toolbar_env.dart';

/// Unpinned, the toolbar collapses this long after the pointer enters the image (upstream
/// `desktop/widgets/remote_toolbar.dart:648-676`).
const kToolbarAutoCollapse = Duration(seconds: 5);

/// "Pin", one for every device, saved as upstream's toolbar saves it
/// (`desktop/widgets/remote_toolbar.dart:253-324`: `{"pin": …}` in the Flutter options).
bool get _pinned {
  final s = appCore.options.flutter.get(kOptionRemoteMenubarState);
  if (s.isEmpty) return false;
  try {
    return jsonDecode(s)['pin'] == true;
  } catch (e) {
    debugPrint('Failed to decode toolbar state $e');
    return false;
  }
}

void _setPinned(bool pin) => appCore.options.flutter
    .set(kOptionRemoteMenubarState, jsonEncode({'pin': pin}));

/// The session's floating toolbar (01 P2 block B), drawn by [LgSessionToolbar] in an
/// [LgToolbarPlacer]: the menus of `toolbar/`, the monitors, the chat, recording and connection
/// mark of the other session files, and "断开". It fills the image area; where the bar sits and
/// where a drag drops it are `toolbar/dock.dart`'s rules. With the relative mouse mode on it is
/// hidden (`remote_page.dart:782-792`).
class SessionToolbar extends StatefulWidget {
  const SessionToolbar(
      {super.key,
      required this.ffi,
      required this.cursorOverImage,
      required this.overlays});

  final FFI ffi;

  /// Set by the session page while the pointer is over the image.
  final RxBool cursorOverImage;
  final TabOverlays overlays;

  @override
  State<SessionToolbar> createState() => _SessionToolbarState();
}

class _SessionToolbarState extends State<SessionToolbar> {
  late bool _collapsed;
  Timer? _collapseTimer;
  Worker? _enterWorker;
  ToolbarEnv? _env;

  /// Null until the device's place is read; the toolbar shows from then on.
  ToolbarDock? _dock;

  /// While dragging: where it would land.
  ToolbarDock? _preview;

  /// The place a drag started from, and where on the bar the pointer took hold of it.
  LgToolbarPlacement? _dragFrom;
  double _grab = 0;

  /// Where the last press on the bar went down (global).
  Offset _downAt = Offset.zero;
  Size _dragSize = Size.zero;
  final _barKey = GlobalKey();

  FFI get _ffi => widget.ffi;

  @override
  void initState() {
    super.initState();
    // Saved per device, as upstream's toolbar state.
    _collapsed = _ffi.options.getToggle(kOptionCollapseToolbar);
    _enterWorker = ever(widget.cursorOverImage, (bool over) {
      if (!over) return;
      _collapseTimer?.cancel();
      _collapseTimer = Timer(kToolbarAutoCollapse, () {
        if (mounted &&
            !_pinned &&
            !_collapsed &&
            _preview == null &&
            widget.cursorOverImage.value) {
          setState(() => _collapsed = true);
        }
      });
    });
    loadToolbarDock(_ffi).then((dock) {
      if (mounted) setState(() => _dock = dock);
    });
    _multiEdge.addListener(_reloadDock);
  }

  final _multiEdge =
      appCore.options.local.listenable(kOptionAllowMultiEdgeToolbarDock);

  /// Docking on any edge switched in the settings: off puts the bar back on the top edge at
  /// once (02 §1.4.4).
  void _reloadDock() => loadToolbarDock(_ffi).then((dock) {
        if (mounted) setState(() => _dock = dock);
      });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context)!;
    if (_env?.l10n == l10n) return;
    _env = ToolbarEnv(ffi: _ffi, l10n: l10n, overlays: widget.overlays);
    registerSessionShortcuts(
      _env!,
      onNextTab: () => mounted ? TabShortcuts.of(context)?.next() : null,
      onPreviousTab: () =>
          mounted ? TabShortcuts.of(context)?.previous() : null,
      onToggleCollapsed: () => _setCollapsed(!_collapsed),
      onTogglePin: () => _setPinned(!_pinned),
      detailMode: () => mounted && LgTokens.of(context).detail,
    );
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _enterWorker?.dispose();
    _multiEdge.removeListener(_reloadDock);
    super.dispose();
  }

  /// Folding or unfolding by hand is saved; the automatic fold is not, so a later unfold
  /// saves "unfolded" instead of flipping the saved value (`待调.md` item 29; upstream toggles).
  void _setCollapsed(bool collapsed) {
    if (_ffi.options.getToggle(kOptionCollapseToolbar) != collapsed) {
      _ffi.options.toggle(kOptionCollapseToolbar);
    }
    if (mounted) setState(() => _collapsed = collapsed);
  }

  /// The placer's rule for a pointer at [local] in [area]: the edge by upstream's hysteresis
  /// (only the top one unless docking on any edge is on), the place along it so the bar keeps
  /// where it was taken hold of, within the bounds. The placer keeps [kToolbarEdgeMargin] at
  /// both ends of the edge, so the way the bar can travel is that much shorter.
  LgToolbarPlacement _resolve(
    Offset local,
    Size area,
    LgToolbarPlacement start,
  ) {
    if (!identical(start, _dragFrom)) {
      // The first call comes once the pointer has moved past the slop, so the hold is taken
      // from where it went down.
      _dragFrom = start;
      final box = context.findRenderObject() as RenderBox?;
      final bar = _barKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && bar != null) {
        _dragSize = bar.size;
        final at = box.globalToLocal(bar.localToGlobal(Offset.zero));
        final down = box.globalToLocal(_downAt);
        _grab = start.dock.vertical ? down.dy - at.dy : down.dx - at.dx;
      }
    }
    final from = dockOf(start).edge;
    final edge = nearestToolbarEdge(
      local,
      area,
      multiEdge: multiEdgeDocking(),
      current: from,
      previewed: _preview?.edge ?? from,
    );
    final size = toolbarSizeOn(edge, _dragSize);
    final horizontal = isHorizontalEdge(edge);
    final extent = horizontal ? size.width : size.height;
    const m = kToolbarEdgeMargin;
    final fraction = dragFraction(
      edge,
      local - (horizontal ? const Offset(m, 0) : const Offset(0, m)),
      _grab.clamp(0, extent),
      horizontal
          ? Size(area.width - 2 * m, area.height)
          : Size(area.width, area.height - 2 * m),
      size,
    );
    return placementOf((edge: edge, fraction: fraction));
  }

  void _onMove(LgToolbarPlacement p) => setState(() => _preview = dockOf(p));

  void _onMoveEnd(LgToolbarPlacement p) {
    final dock = dockOf(p);
    _dragFrom = null;
    setState(() {
      _dock = dock;
      _preview = null;
    });
    saveToolbarDock(_ffi, dock);
  }

  /// The ghost: the bar as measured when the drag began, turned to the edge it would land on.
  Size _previewSize(LgToolbarDock dock) {
    final edge = ToolbarEdge.values.byName(dock.name);
    final size = toolbarSizeOn(edge, _dragSize);
    // Without the 12 px the bar keeps from its edge.
    return isHorizontalEdge(edge)
        ? Size(size.width, size.height - LgSpace.s3)
        : Size(size.width - LgSpace.s3, size.height);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _ffi.connection,
        _ffi.ffiModel,
        // The chat's unread count on "更多" is read when the bar builds.
        _ffi.chatModel,
        _ffi.notices,
        _env!.changed,
        appCore.options.flutter.listenable(kOptionRemoteMenubarState),
        // The settings of 工具栏与显示器 (02 §1.4.4, §3.3).
        appCore.options.userDefault.listenable(kKeyShowMonitorsToolbar),
        appCore.options.local.listenable(kOptionAllowMonitorSwitchMainToolbar),
        appCore.options.local.listenable(kOptionAllowMonitorSwitchMinToolbar),
      ]),
      builder: (context, _) => Obx(() {
        // Read here so the toolbar follows them.
        _ffi.privacyMode.value;
        _ffi.ffiModel.pi.displaysCount.value;
        if (_ffi.inputModel.relativeMouseMode.value) {
          return const SizedBox.shrink();
        }
        final dock = _dock;
        if (dock == null) return const SizedBox.shrink();
        final preview = _preview;
        return LgToolbarPlacer(
          placement: placementOf(dock),
          preview: preview == null ? null : placementOf(preview),
          anyEdge: multiEdgeDocking(),
          resolve: _resolve,
          onMove: _onMove,
          onMoveEnd: _onMoveEnd,
          previewSize: _previewSize,
          edgeMargin: kToolbarEdgeMargin,
          child: Listener(
            onPointerDown: (e) => _downAt = e.position,
            child: KeyedSubtree(key: _barKey, child: _bar(context, dock)),
          ),
        );
      }),
    );
  }

  /// A menu of the bar. [disabledReason] greys the button and is said on hover; the menu still
  /// opens, its rows greyed (A-P2 `x-no-perm`). [refresh] also rebuilds the open menu besides
  /// the env's own changes.
  Widget _menu(String label, LgIcons icon,
          Future<List<TbEntry>> Function(ToolbarEnv) entries,
          {String? disabledReason, Listenable? refresh, double? width}) =>
      LgToolbarMenuButton(
        label: label,
        icon: icon,
        width: width ?? kLgMenuWidth,
        enabled: disabledReason == null,
        disabledNote: disabledReason,
        items: [_content(entries, refresh: refresh)],
      );

  Widget _content(Future<List<TbEntry>> Function(ToolbarEnv) entries,
          {Listenable? refresh}) =>
      TbMenuContent(
        build: () => entries(_env!),
        refresh: refresh == null
            ? _env!.changed
            : Listenable.merge([_env!.changed, refresh]),
      );

  Widget _bar(BuildContext context, ToolbarDock dock) {
    final env = _env!;
    final l10n = env.l10n;
    final fullscreen = stateGlobal.fullscreen.isTrue;
    final conn = _ffi.connection;
    // Shown from "waiting for the image" on (01 P2 block A); before that the folded bar has no dot.
    final shown = showsRoute(conn);
    final route = conn.direct == true ? LgRoute.direct : LgRoute.relay;
    final routeLabel =
        conn.direct == true ? l10n.sessionDirect : l10n.sessionRelayed;
    final encrypted = conn.secure != false;
    final routeMark = sessionRouteMark(context, _ffi, widget.overlays);
    final record = recordButton(context, _ffi);
    final chat = chatToolbarButtons(context, _ffi, widget.overlays);
    final collapsedSwitch = collapsedMonitorSwitch(env);

    // What does not fit goes into "更多" from the end: 录制, then 聊天, then 会话
    // (01 P2 block B); the bar measures, these say what each becomes in the menu.
    final session = LgToolbarFoldable(
      inline: _menu(l10n.toolbarSession, LgIcons.toggles, sessionMenuEntries,
          width: 340),
      menuItem: LgSubmenu(
        label: l10n.toolbarSession,
        icon: LgIcons.toggles,
        width: 340,
        items: [_content(sessionMenuEntries)],
      ),
    );
    // Chat and recording come foldable, with their rows for "更多"; the chat's count is read
    // when the bar builds, which it does on every chat change (see [build]).
    final talk = <Widget>[...chat, ?record];

    return LgSessionToolbar(
      labels: LgToolbarLabels(
        toolbar: l10n.toolbarName,
        pin: l10n.toolbarPin,
        fullscreen: l10n.toolbarFullscreen,
        exitFullscreen: l10n.toolbarExitFullscreen,
        minimize: l10n.minimize,
        collapse: l10n.toolbarCollapse,
        expand: l10n.toolbarExpand,
        drag: l10n.toolbarMove,
        more: l10n.toolbarMore,
      ),
      dock: placementOf(dock).dock,
      pinned: _pinned,
      onTogglePin: () => _setPinned(!_pinned),
      collapsed: _collapsed,
      onToggleCollapsed: () => _setCollapsed(!_collapsed),
      fullscreen: fullscreen,
      onToggleFullscreen: () => stateGlobal.setFullscreen(!fullscreen),
      // The bar has "Minimize" in full screen, expanded or collapsed (01 P2 block B).
      onMinimize: windowManager.minimize,
      deviceName: deviceName(_ffi),
      deviceId: _ffi.id,
      route: shown ? route : null,
      routeLabel: shown ? routeLabel : null,
      encrypted: encrypted,
      unencryptedLabel: l10n.sessionUnencrypted,
      collapsedActions: [?collapsedSwitch],
      // The notices sit at the top right of the image: notes open on the left (`x-revoked`).
      noteSide: _ffi.notices.items.isEmpty ? null : LgNoteSide.left,
      groups: [
        [
          SessionViewSwitch(ffi: _ffi),
          ...monitorToolbarItems(env),
        ],
        [
          _menu(l10n.toolbarDisplay, LgIcons.image, displayMenuEntries),
          // Upstream hides the keyboard menu without the keyboard permission
          // (`remote_toolbar.dart` `_KeyboardMenu`); 01 greys it with the reason.
          if (_ffi.connType == ConnType.defaultConn)
            _menu(l10n.toolbarInput, LgIcons.keyboard, inputMenuEntries,
                disabledReason: env.keyboardReason),
          _menu(l10n.toolbarActions, LgIcons.bolt, actionMenuEntries,
              refresh: _ffi.requests.screenshotPending, width: 380),
          // Its rows are the remote desktop's only; the camera has no "会话" (13 §3.2 block A).
          if (env.isDefaultConn) session,
        ],
        if (talk.isNotEmpty) talk,
        if (routeMark != null) [routeMark],
        [
          LgToolbarButton(
            icon: LgIcons.power,
            label: l10n.toolbarDisconnect,
            danger: true,
            onPressed: () => appCore.sessions.close(_ffi),
          ),
        ],
      ],
    );
  }
}
