import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../../shell/tab_overlays.dart';
import '../../shell/toast_view.dart';
import '../../theme/lg_tokens.dart';
import 'connection_panel.dart';
import 'image_paint.dart';
import 'remote_input.dart';
import 'session_notices.dart';
import 'session_toolbar.dart';

/// A remote desktop view in its session tab (01 P2): the image, keyboard and mouse, the
/// connection panel while there is no image, the toolbar and the notices.
///
/// Keyboard (`04-M2a拆法.md` §4, upstream `desktop/pages/remote_page.dart`, its Windows paths):
/// the image takes the keyboard only when its tab is [active], no panel or dialog covers the
/// tab, the window has focus, and the pointer is on the image or just clicked it. Taking it
/// turns the keyboard hook on (`enterOrLeave(true)`). Leaving the tab, closing it and the
/// window losing focus turn it off at once, so keys still down are released on the remote
/// device and the hook waits before another tab can take it.
class SessionPage extends StatefulWidget {
  const SessionPage(
      {super.key,
      required this.ffi,
      required this.active,
      required this.overlays});

  final FFI ffi;

  /// This tab is the selected one.
  final bool active;
  final TabOverlays overlays;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage>
    with WindowListener, TickerProviderStateMixin {
  final _rawKeyFocusNode = FocusNode(debugLabel: 'rawkeyFocusNode');
  final _cursorOverImage = false.obs;
  late final RxBool _zoomCursor;
  bool _isWindowBlur = false;

  /// "已建立直连" / "已建立中继连接" was shown for this session (01 §4.1 stage 6).
  bool _announced = false;

  FFI get _ffi => widget.ffi;

  bool get _blocked =>
      _ffi.connection.stage != ConnStage.connected ||
      widget.overlays.isOpen(_ffi.id) ||
      widget.overlays.isOpen(kWindowScope);

  // Upstream `_windowsCanFocusRemoteInput`: every requestFocus() passes it.
  bool get _canFocusRemoteInput => widget.active && !_blocked;

  @override
  void initState() {
    super.initState();
    // Starts Rust's keyboard grab, without which no key reaches the remote device; upstream does
    // it for every remote window (`desktop/screen/desktop_remote_screen.dart:13-14`), and again
    // is harmless.
    bind.mainInitInputSource();
    stateGlobal.getInputSource(force: true);
    _ffi.canvasModel.initializeEdgeScrollFallback(this);
    // Upstream reads them once the session started (`remote_page.dart:200-206`); the registry
    // started it before the page.
    _ffi.showRemoteCursor.value = _ffi.options.getToggle('show-remote-cursor');
    _zoomCursor = _ffi.options.getToggle(kOptionZoomCursor).obs;
    windowManager.addListener(this);
    appCore.sessions.addListener(_onRegistry);
    _ffi.connection.addListener(_onConnection);
    widget.overlays.addListener(_onCovered);
  }

  @override
  void didUpdateWidget(SessionPage old) {
    super.didUpdateWidget(old);
    if (old.active == widget.active) return;
    // Switched away: release now, before the next tab can take the keyboard. Coming back does
    // not take it; the pointer entering or clicking the image does (§4 item 3).
    if (!widget.active) _release();
    // V1: no frames for a tab nobody sees (§4 item 7).
    _ffi.setVisible(widget.active);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    appCore.sessions.removeListener(_onRegistry);
    _ffi.connection.removeListener(_onConnection);
    widget.overlays.removeListener(_onCovered);
    _release();
    _rawKeyFocusNode.dispose();
    super.dispose();
  }

  /// The registry drops the session before it closes it, so the keys still down reach the
  /// remote device as released (upstream's page released them in `dispose` before `FFI.close`).
  void _onRegistry() {
    if (!appCore.sessions.sessionsOf(_ffi.id).contains(_ffi)) _release();
  }

  void _onConnection() {
    _onCovered();
    final conn = _ffi.connection;
    // The panel covers the toolbar, and with it the way out of full screen.
    if (widget.active &&
        conn.stage != ConnStage.connected &&
        stateGlobal.fullscreen.isTrue) {
      stateGlobal.setFullscreen(false);
    }
    if (!_announced && conn.stage == ConnStage.connected && conn.direct != null) {
      _announced = true;
      appCore.toasts.show(
          conn.direct! ? kToastDirectEstablished : kToastRelayEstablished);
    }
  }

  /// A panel or a dialog covers the tab: the image lets go of the keyboard.
  void _onCovered() {
    if (_blocked && _rawKeyFocusNode.hasFocus) _rawKeyFocusNode.unfocus();
  }

  /// `enterOrLeave(false)` sends key-ups for what is still pressed, resets the modifiers and
  /// sets the hook to wait; then system keys stay on this device and the focus goes. The focus
  /// change sends another "off" later; Rust takes "off" only from the session holding the
  /// keyboard (`src/keyboard.rs`), so it cannot turn off the next tab's.
  void _release() {
    _ffi.inputModel.enterOrLeave(false);
    bind.hostStopSystemKeyPropagate(stopped: true);
    _cursorOverImage.value = false;
    _rawKeyFocusNode.unfocus();
  }

  void _onFocusChange(bool imageFocused) {
    if (_isWindowBlur) {
      imageFocused = false;
      Future.delayed(Duration.zero, () {
        if (mounted) _rawKeyFocusNode.unfocus();
      });
    }
    _ffi.inputModel.enterOrLeave(imageFocused);
  }

  @override
  void onWindowBlur() {
    // Unfocus when the whole window loses focus and let the OS handle the keys.
    _isWindowBlur = true;
    _rawKeyFocusNode.unfocus();
    if (_ffi.inputModel.relativeMouseMode.value) {
      _ffi.inputModel.onWindowBlur();
    }
  }

  @override
  void onWindowFocus() {
    _isWindowBlur = false;
    // Refocus without PointerEnter: the cursor already hovers the image when focus returns
    // (Alt+Tab, taskbar), so enterView() never fires again.
    if (_cursorOverImage.value &&
        _canFocusRemoteInput &&
        !_rawKeyFocusNode.hasFocus) {
      _rawKeyFocusNode.requestFocus();
    }
    if (_ffi.inputModel.relativeMouseMode.value) {
      if (_canFocusRemoteInput) _rawKeyFocusNode.requestFocus();
      _ffi.inputModel.onWindowFocus();
    }
  }

  // Upstream handles a restore from minimized here on Windows.
  @override
  void onWindowRestore() => _isWindowBlur = false;

  void _enterView(PointerEnterEvent evt) {
    _ffi.canvasModel.rearmEdgeScroll();
    _cursorOverImage.value = true;
    // Focus only while the window is really active, or a background window would grab system
    // keys. onFocusChange does enterOrLeave.
    if (!_isWindowBlur &&
        _canFocusRemoteInput &&
        !_rawKeyFocusNode.hasFocus) {
      _rawKeyFocusNode.requestFocus();
    }
  }

  void _leaveView(PointerExitEvent evt) {
    _ffi.canvasModel.disableEdgeScroll();
    if (_ffi.ffiModel.keyboard) {
      _ffi.inputModel.tryMoveEdgeOnExit(evt.position);
    }
    _cursorOverImage.value = false;
  }

  Widget _pointerRegion(Widget child) => RawPointerMouseRegion(
        onEnter: _enterView,
        onExit: _leaveView,
        onPointerDown: (event) {
          // Sometimes the system does not send the focus event to Flutter; a click on the
          // image means the window is active.
          if (_isWindowBlur) _isWindowBlur = false;
          if (!_rawKeyFocusNode.hasFocus) _rawKeyFocusNode.requestFocus();
        },
        inputModel: _ffi.inputModel,
        child: child,
      );

  /// Upstream `getBodyForDesktop` without the quality monitor (it comes with the connection
  /// details, M2b) and the touch gestures.
  Widget _remoteView() {
    final paints = <Widget>[
      MouseRegion(
        onEnter: (evt) => bind.hostStopSystemKeyPropagate(stopped: false),
        onExit: (evt) => bind.hostStopSystemKeyPropagate(stopped: true),
        child: ViewStyleUpdater(
          canvasModel: _ffi.canvasModel,
          inputModel: _ffi.inputModel,
          child: Obx(
            () => _ffi.ffiModel.pi.isSet.isFalse
                ? Container(color: Colors.transparent)
                : Obx(() {
                    _ffi.textureModel
                        .updateCurrentDisplay(_ffi.currentDisplay.value);
                    return ImagePaint(
                      id: _ffi.id,
                      zoomCursor: _zoomCursor,
                      cursorOverImage: _cursorOverImage,
                      keyboardEnabled: _ffi.keyboardEnabled,
                      remoteCursorMoved: _ffi.remoteCursorMoved,
                      listenerBuilder: _pointerRegion,
                      ffi: _ffi,
                    );
                  }),
          ),
        ),
      ),
    ];
    if (!_ffi.canvasModel.cursorEmbedded) {
      paints.add(Obx(() =>
          _ffi.showRemoteCursor.isFalse || _ffi.remoteCursorMoved.isFalse
              ? const Offstage()
              : CursorPaint(ffi: _ffi, id: _ffi.id, zoomCursor: _zoomCursor)));
    }
    return Stack(children: paints);
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([_ffi.connection, _ffi.ffiModel]),
      builder: (context, _) {
        final conn = _ffi.connection;
        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: c.canvas,
                child: RawKeyFocusScope(
                  focusNode: _rawKeyFocusNode,
                  onFocusChange: _onFocusChange,
                  inputModel: _ffi.inputModel,
                  child: _remoteView(),
                ),
              ),
            ),
            if (_ffi.ffiModel.pi.isSet.isTrue)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: SessionToolbar(
                      ffi: _ffi,
                      cursorOverImage: _cursorOverImage,
                      overlays: widget.overlays),
                ),
              ),
            // At the right below the toolbar (`LgNoticeStack`: right 16, top 12 + bar + 12).
            Positioned(
              top: LgSpace.s3 + t.sizes.bar + LgSpace.s3,
              right: LgSpace.s4,
              child: SessionNoticesView(ffi: _ffi),
            ),
            // The panel dims the last frame itself while the remote device restarts.
            if (conn.stage != ConnStage.connected) ...[
              const ModalBarrier(dismissible: false),
              ConnectionPanel(ffi: _ffi, active: widget.active),
            ],
          ],
        );
      },
    );
  }
}
