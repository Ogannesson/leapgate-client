import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/tab_overlays.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_feedback.dart';
import '../../widgets/lg_menu.dart';
import '../../widgets/lg_session_toolbar.dart';
import '../../widgets/lg_status.dart';
import '../../widgets/lg_tooltip.dart';
import 'session_names.dart';

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

/// The session's floating toolbar, top centre (01 P2 block B; M2a's set, `04-M2a拆法.md` §1.1),
/// drawn by [LgSessionToolbar].
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
  String _quality = '';
  Timer? _collapseTimer;
  Worker? _enterWorker;

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
            widget.cursorOverImage.value) {
          setState(() => _collapsed = true);
        }
      });
    });
    _readQuality();
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _enterWorker?.dispose();
    super.dispose();
  }

  Future<void> _readQuality() async {
    final q = await _ffi.getImageQuality();
    if (mounted) setState(() => _quality = q);
  }

  void _toggleCollapsed() {
    _ffi.options.toggle(kOptionCollapseToolbar);
    setState(() => _collapsed = !_collapsed);
  }

  /// Asks over this tab only; Enter restarts, as upstream's OK does.
  Future<void> _confirmRestart() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await widget.overlays.show<bool>(
      _ffi.id,
      (context, close) => LgDialogScrim(
        onEscape: () => close(null),
        child: LgConfirmDialog(
          title: l10n.toolbarRestartTitle,
          body: l10n.toolbarRestartBody,
          actions: [
            LgDialogAction(label: l10n.connCancel, onPressed: () => close(null)),
            LgDialogAction(
              label: l10n.toolbarRestartConfirm,
              kind: LgButtonKind.dangerSolid,
              isDefault: true,
              onPressed: () => close(true),
            ),
          ],
        ),
      ),
    );
    if (ok == true) _ffi.restartRemoteDevice();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _ffi.connection,
        _ffi.ffiModel,
        _ffi.canvasModel,
        appCore.options.flutter.listenable(kOptionRemoteMenubarState),
      ]),
      builder: (context, _) => Obx(() => _build(context)),
    );
  }

  Widget _build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fullscreen = stateGlobal.fullscreen.isTrue;
    final conn = _ffi.connection;
    final pi = _ffi.ffiModel.pi;
    // Shown from "waiting for the image" on (01 P2 block A); before that the folded bar has no dot.
    final shown = showsRoute(conn);
    final route = conn.direct == true ? LgRoute.direct : LgRoute.relay;
    final routeLabel =
        conn.direct == true ? l10n.sessionDirect : l10n.sessionRelayed;
    final routeTip =
        conn.direct == true ? l10n.sessionDirectTip : l10n.sessionRelayedTip;
    final encrypted = conn.secure != false;
    final viewStyle = _ffi.canvasModel.viewStyle.style;
    final actions = [
      if (_ffi.canSendCtrlAltDel)
        LgMenuItem(
            label: l10n.toolbarCtrlAltDel, onPressed: _ffi.sendCtrlAltDel),
      if (_ffi.canRestartRemoteDevice)
        LgMenuItem(label: l10n.toolbarRestart, onPressed: _confirmRestart),
    ];
    final pinned = _pinned;

    return LgSessionToolbar(
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
      onToggleCollapsed: _toggleCollapsed,
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
        ],
        [
          if (pi.displays.length > 1)
            LgToolbarMenuButton(
              label: l10n.toolbarMonitor,
              icon: LgIcons.displays,
              items: [
                for (var i = 0; i < pi.displays.length; i++)
                  LgMenuItem(
                    label: l10n.toolbarMonitorN(i + 1),
                    checked: pi.currentDisplay == i,
                    onPressed: () => openMonitorInTheSameTab(i, _ffi, pi),
                  ),
              ],
            ),
          LgToolbarMenuButton(
            label: l10n.toolbarDisplay,
            icon: LgIcons.image,
            items: [
              LgMenuGroup(l10n.toolbarScale),
              for (final (style, label) in [
                (kRemoteViewStyleOriginal, l10n.toolbarScaleOriginal),
                (kRemoteViewStyleAdaptive, l10n.toolbarScaleAdaptive),
              ])
                LgMenuItem(
                  label: label,
                  checked: viewStyle == style,
                  onPressed: () => _ffi.setViewStyle(style),
                ),
              LgMenuGroup(l10n.toolbarQuality),
              for (final (quality, label) in [
                (kRemoteImageQualityBest, l10n.toolbarQualityBest),
                (kRemoteImageQualityBalanced, l10n.toolbarQualityBalanced),
                (kRemoteImageQualityLow, l10n.toolbarQualityLow),
              ])
                LgMenuItem(
                  label: label,
                  checked: _quality == quality,
                  onPressed: () async {
                    await _ffi.setImageQuality(quality);
                    await _readQuality();
                  },
                ),
            ],
          ),
          if (actions.isNotEmpty)
            LgToolbarMenuButton(
              label: l10n.toolbarActions,
              icon: LgIcons.bolt,
              items: actions,
            ),
        ],
        if (shown)
          [
            LgTooltip(
              message: encrypted
                  ? routeTip
                  : '$routeTip\n${l10n.sessionUnencryptedTip}',
              // The connection details open from here in M2b.
              child: LgToolbarStatus(
                child: LgRouteMark(
                  route: route,
                  label: routeLabel,
                  encrypted: encrypted,
                  unencryptedLabel: l10n.sessionUnencrypted,
                ),
              ),
            ),
          ],
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
