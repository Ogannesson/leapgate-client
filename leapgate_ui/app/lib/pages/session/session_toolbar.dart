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
import '../../shell/tab_menu.dart';
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

/// Narrower than this, "录制", "聊天" and "会话" go into "更多" (01 P2 block B, measured on the
/// mockups: simple / detail mode, without / with the monitor button). The designer's toolbar
/// measures its items instead (`LEAPGATE.md` §10.9).
double _foldWidth({required bool detail, required bool monitors}) =>
    monitors ? (detail ? 1022 : 1009) : (detail ? 919 : 918);

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

/// The session's floating toolbar (01 P2 block B), drawn by [LgSessionToolbar]: the menus of
/// `toolbar/`, the monitors, the chat, recording and connection mark of the other session
/// files, and "断开". It fills the image area and places itself on the edge it is docked to;
/// with the relative mouse mode on it is hidden (`remote_page.dart:782-792`).
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

  /// While dragging: where it would land, and where the pointer holds it.
  ToolbarDock? _preview;
  double _grab = 0;
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
  }

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

  RenderBox? get _area => context.findRenderObject() as RenderBox?;

  void _dragStart(DragStartDetails d) {
    final area = _area;
    final bar = _barKey.currentContext?.findRenderObject() as RenderBox?;
    final dock = _dock;
    if (area == null || bar == null || dock == null) return;
    _dragSize = bar.size;
    final cursor = area.globalToLocal(d.globalPosition);
    final at = toolbarOffset(dock, area.size, toolbarSizeOn(dock.edge, _dragSize));
    _grab = isHorizontalEdge(dock.edge) ? cursor.dx - at.dx : cursor.dy - at.dy;
    setState(() => _preview = dock);
  }

  void _dragUpdate(DragUpdateDetails d) {
    final area = _area;
    final dock = _dock;
    final preview = _preview;
    if (area == null || dock == null || preview == null) return;
    final cursor = area.globalToLocal(d.globalPosition);
    final edge = nearestToolbarEdge(cursor, area.size,
        multiEdge: multiEdgeDocking(),
        current: dock.edge,
        previewed: preview.edge);
    final size = toolbarSizeOn(edge, _dragSize);
    final extent = isHorizontalEdge(edge) ? size.width : size.height;
    setState(() => _preview = (
          edge: edge,
          fraction: dragFraction(
              edge, cursor, _grab.clamp(0, extent), area.size, size),
        ));
  }

  void _dragEnd(DragEndDetails d) {
    final preview = _preview;
    if (preview == null) return;
    setState(() {
      _dock = preview;
      _preview = null;
    });
    saveToolbarDock(_ffi, preview);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _ffi.connection,
        _ffi.ffiModel,
        _ffi.canvasModel,
        _env!.changed,
        appCore.options.flutter.listenable(kOptionRemoteMenubarState),
      ]),
      builder: (context, _) => Obx(() {
        // Read here so the toolbar follows them.
        _ffi.privacyMode.value;
        _ffi.ffiModel.pi.displaysCount.value;
        if (_ffi.inputModel.relativeMouseMode.value) {
          return const SizedBox.shrink();
        }
        return LayoutBuilder(builder: _build);
      }),
    );
  }

  Widget _build(BuildContext context, BoxConstraints constraints) {
    final dock = _dock;
    if (dock == null) return const SizedBox.shrink();
    final preview = _preview;
    final bar = KeyedSubtree(key: _barKey, child: _bar(context, constraints));
    return Stack(
      fit: StackFit.expand,
      children: [
        if (preview != null) _dropPreview(preview, constraints.biggest),
        Align(alignment: alignmentForEdge(dock.edge, dock.fraction), child: bar),
      ],
    );
  }

  /// Where the toolbar lands if dropped now. Placeholder for the designer's preview.
  Widget _dropPreview(ToolbarDock preview, Size area) {
    final c = LgTokens.of(context).colors;
    final size = toolbarSizeOn(preview.edge, _dragSize);
    final at = toolbarOffset(preview, area, size);
    return Positioned(
      left: at.dx,
      top: at.dy,
      width: size.width,
      height: size.height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.accent.withValues(alpha: .1),
            border: Border.all(color: c.accent, width: 1.5),
            borderRadius: BorderRadius.circular(LgRadius.r16),
          ),
        ),
      ),
    );
  }

  /// A menu of the bar. [disabledReason] greys the whole button and is said on hover;
  /// [refresh] also rebuilds the open menu besides the env's own changes.
  Widget _menu(String label, LgIcons icon,
      Future<List<TbEntry>> Function(ToolbarEnv) entries,
      {String? disabledReason, Listenable? refresh}) {
    final button = LgToolbarMenuButton(
      label: label,
      icon: icon,
      enabled: disabledReason == null,
      items: [
        TbMenuContent(
          build: () => entries(_env!),
          refresh: refresh == null
              ? _env!.changed
              : Listenable.merge([_env!.changed, refresh]),
        ),
      ],
    );
    return disabledReason == null
        ? button
        : LgTooltip(message: disabledReason, child: button);
  }

  Widget _bar(BuildContext context, BoxConstraints constraints) {
    final env = _env!;
    final l10n = env.l10n;
    final t = LgTokens.of(context);
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
    final monitors = monitorToolbarItems(env);
    final pinned = _pinned;

    final sessionMenu =
        _menu(l10n.toolbarSession, LgIcons.toggles, sessionMenuEntries);
    final fold = isHorizontalEdge(_dock!.edge) &&
        constraints.maxWidth <
            _foldWidth(detail: t.detail, monitors: monitors.isNotEmpty);
    final unread = tabUnread(_ffi);
    // "更多" holds what does not fit, in the order 录制、聊天、会话 (01 P2 block B).
    final more = LgToolbarMenuButton(
      label: unread > 0 ? '${l10n.toolbarMore} $unread' : l10n.toolbarMore,
      icon: LgIcons.more,
      items: [
        LgSubmenu(label: l10n.toolbarSession, items: [
          TbMenuContent(
              build: () => sessionMenuEntries(env), refresh: env.changed),
        ]),
        ...chat,
        ?record,
      ],
    );

    final toolbar = LgSessionToolbar(
      labels: LgToolbarLabels(
        toolbar: l10n.toolbarName,
        pin: l10n.toolbarPin,
        fullscreen: l10n.toolbarFullscreen,
        exitFullscreen: l10n.toolbarExitFullscreen,
        minimize: l10n.minimize,
        collapse: l10n.toolbarCollapse,
        expand: l10n.toolbarExpand,
      ),
      pinned: pinned,
      onTogglePin: () => _setPinned(!pinned),
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
      groups: [
        [
          LgToolbarMenuButton(
            label: l10n.toolbarRemoteDesktop,
            icon: LgIcons.monitor,
            items: [
              LgMenuItem(
                  label: l10n.toolbarRemoteDesktop,
                  checked: true,
                  onPressed: () {}),
            ],
          ),
          ...monitors,
        ],
        [
          _menu(l10n.toolbarDisplay, LgIcons.image, displayMenuEntries),
          // Upstream hides the keyboard menu without the keyboard permission
          // (`remote_toolbar.dart` `_KeyboardMenu`); 01 greys it with the reason.
          if (_ffi.connType == ConnType.defaultConn)
            _menu(l10n.toolbarInput, LgIcons.keyboard, inputMenuEntries,
                disabledReason: env.keyboardReason),
          _menu(l10n.toolbarActions, LgIcons.bolt, actionMenuEntries,
              refresh: _ffi.requests.screenshotPending),
          if (fold) more else sessionMenu,
        ],
        if (!fold && (chat.isNotEmpty || record != null)) [...chat, ?record],
        if (routeMark != null) [routeMark],
        [
          LgToolbarButton(
            icon: LgIcons.power,
            label: l10n.toolbarDisconnect,
            danger: true,
            onPressed: () => appCore.sessions.close(_ffi),
          ),
          // Only the handle drags the bar, as upstream's drag button
          // (`remote_toolbar.dart` `_DraggableShowHide`): a press on a button that slips a few
          // pixels still opens its menu.
          Semantics(
            label: l10n.toolbarMove,
            child: ExcludeSemantics(
              child: GestureDetector(
                onPanStart: _dragStart,
                onPanUpdate: _dragUpdate,
                onPanEnd: _dragEnd,
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: LgIcon(LgIcons.grip,
                        size: t.sizes.icon, color: t.colors.text2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
    final collapsedSwitch = _collapsed ? collapsedMonitorSwitch(env) : null;
    if (collapsedSwitch == null) return toolbar;
    return Row(mainAxisSize: MainAxisSize.min, children: [toolbar, collapsedSwitch]);
  }
}
