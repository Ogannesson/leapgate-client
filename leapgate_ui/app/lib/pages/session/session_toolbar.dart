import 'dart:async';

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
import '../../shell/confirm_card.dart';
import '../../shell/tab_overlays.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_menu.dart';
import '../../widgets/lg_status.dart';
import '../../widgets/lg_tooltip.dart';
import 'session_names.dart';

// Upstream option keys and values (`flutter/lib/consts.dart:139`, `:144`, `:414-421`). Per
// LEAPGATE.md §10.7 they belong in core's consts.dart, outside this block's files; they move
// there when the blocks are merged.
const kOptionCollapseToolbar = 'collapse_toolbar';
const kOptionZoomCursor = 'zoom-cursor';
const kRemoteImageQualityBest = 'best';
const kRemoteImageQualityBalanced = 'balanced';
const kRemoteImageQualityLow = 'low';

/// Unpinned, the toolbar collapses this long after the pointer enters the image (upstream
/// `desktop/widgets/remote_toolbar.dart:648-676`).
const kToolbarAutoCollapse = Duration(seconds: 5);

/// "Pin", shared by every session tab for this run. Upstream also saves it
/// (`remoteMenubarState` in the Flutter options); that store has no scope in the options model
/// yet (`LEAPGATE.md` §10.7).
final toolbarPinned = ValueNotifier<bool>(false);

/// The session's floating toolbar, top centre (01 P2 block B; M2a's set, `04-M2a拆法.md` §1.1).
/// Placeholder look until the designer's `LgSessionToolbar` replaces it.
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
            !toolbarPinned.value &&
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

  Future<void> _confirmRestart() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await widget.overlays.show<bool>(_ffi.id, (context, close) {
      final restart = ConfirmAction(
          l10n.toolbarRestartConfirm, () => close(true),
          kind: LgButtonKind.danger);
      return ConfirmCard(
        title: l10n.toolbarRestartTitle,
        body: l10n.toolbarRestartBody,
        actions: [ConfirmAction(l10n.connCancel, () => close(null)), restart],
        defaultAction: restart,
        onCancel: () => close(null),
      );
    });
    if (ok == true) _ffi.restartRemoteDevice();
  }

  Widget _menu(String label, List<Widget> items) => LgMenuAnchor(
        items: items,
        builder: (context, controller) => LgButton(
          label: label,
          kind: LgButtonKind.text,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _ffi.connection,
        _ffi.ffiModel,
        _ffi.canvasModel,
        toolbarPinned,
      ]),
      builder: (context, _) => Obx(() => _build(context)),
    );
  }

  Widget _build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final fullscreen = stateGlobal.fullscreen.isTrue;
    final conn = _ffi.connection;
    final pi = _ffi.ffiModel.pi;

    final fullscreenButton = LgIconButton(
      icon: fullscreen ? LgIcons.fullscreenExit : LgIcons.fullscreen,
      label: fullscreen ? l10n.toolbarExitFullscreen : l10n.toolbarFullscreen,
      onPressed: () => stateGlobal.setFullscreen(!fullscreen),
    );
    final route = conn.direct == null
        ? null
        : LgTooltip(
            message: conn.direct!
                ? l10n.sessionDirectTip
                : l10n.sessionRelayedTip,
            // The connection details open from here in M2b.
            child: LgRouteMark(
              route: conn.direct! ? LgRoute.direct : LgRoute.relay,
              label: conn.direct! ? l10n.sessionDirect : l10n.sessionRelayed,
              encrypted: conn.secure != false,
              unencryptedLabel: l10n.sessionUnencrypted,
            ),
          );

    final List<Widget> children;
    if (_collapsed) {
      children = [
        if (route != null) route,
        LgIconButton(
            icon: LgIcons.chevD,
            label: l10n.toolbarExpand,
            onPressed: _toggleCollapsed),
        fullscreenButton,
        if (fullscreen)
          LgIconButton(
              icon: LgIcons.windowMin,
              label: l10n.minimize,
              onPressed: windowManager.minimize),
      ];
    } else {
      final viewStyle = _ffi.canvasModel.viewStyle.style;
      final actions = [
        if (_ffi.canSendCtrlAltDel)
          LgMenuItem(
              label: l10n.toolbarCtrlAltDel, onPressed: _ffi.sendCtrlAltDel),
        if (_ffi.canRestartRemoteDevice)
          LgMenuItem(label: l10n.toolbarRestart, onPressed: _confirmRestart),
      ];
      children = [
        if (fullscreen)
          Text(deviceName(_ffi),
              style: t.text
                  .copyWith(color: t.colors.text, fontWeight: FontWeight.w700)),
        LgIconButton(
          icon: LgIcons.pin,
          label: toolbarPinned.value ? l10n.toolbarUnpin : l10n.toolbarPin,
          onPressed: () => toolbarPinned.value = !toolbarPinned.value,
        ),
        _menu(l10n.toolbarRemoteDesktop, [
          LgMenuItem(
              label: l10n.toolbarRemoteDesktop, checked: true, onPressed: () {}),
        ]),
        if (pi.displays.length > 1)
          _menu(l10n.toolbarMonitor, [
            for (var i = 0; i < pi.displays.length; i++)
              LgMenuItem(
                label: l10n.toolbarMonitorN(i + 1),
                checked: pi.currentDisplay == i,
                onPressed: () => openMonitorInTheSameTab(i, _ffi, pi),
              ),
          ]),
        _menu(l10n.toolbarDisplay, [
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
        ]),
        if (actions.isNotEmpty) _menu(l10n.toolbarActions, actions),
        if (route != null) route,
        LgButton(
          label: l10n.toolbarDisconnect,
          kind: LgButtonKind.danger,
          onPressed: () => appCore.sessions.close(_ffi),
        ),
        fullscreenButton,
        LgIconButton(
            icon: LgIcons.chevU,
            label: l10n.toolbarCollapse,
            onPressed: _toggleCollapsed),
      ];
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
      decoration: BoxDecoration(
        color: t.colors.float,
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(LgRadius.r10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const SizedBox(width: LgSpace.s1),
            c,
          ],
        ],
      ),
    );
  }
}
