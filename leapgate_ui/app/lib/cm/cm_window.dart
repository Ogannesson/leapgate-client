import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/cm_core.dart';
import 'package:window_manager/window_manager.dart';

// The connection manager's window (01 §3.3): about 300×490 at the top right of the primary
// display's work area, on top of other windows, not resizable; collapsed, the same window becomes
// a strip along the top edge of that display. Upstream: `flutter/lib/main.dart:285-351`.

/// Where the strip was left: its distance from the right edge of the work area, in logical
/// pixels (a LocalConfig key of Leapgate's own).
const kOptionLeapgateCmStripOffset = 'leapgate-cm-strip-offset';

enum CmView { hidden, full, strip }

/// The strip, 48 high, as wide as the full window (A-P3.html `p3-pill-*`).
const Size kCmStripSize = Size(300, 48);

/// What the page does with the window besides what the copied ServerModel does.
abstract class CmShellWindow implements CmWindow {
  ValueListenable<CmView> get view;

  /// From the strip back to the full window.
  Future<void> expand();

  /// Moves the full window with the pointer (its title area).
  Future<void> startDragging();

  /// A drag of the strip starts at the cursor's current place.
  void startStripDrag();

  /// Moves the strip along the top edge with the cursor.
  Future<void> dragStrip();

  /// Puts the strip where the cursor left it and remembers the place.
  Future<void> endStripDrag();
}

class LgCmWindow implements CmShellWindow {
  final _view = ValueNotifier(CmView.hidden);

  /// While the strip is dragged: the cursor's screen x and the strip's left edge when the drag
  /// started, in physical pixels. The pointer's own deltas are in window coordinates, which move
  /// with the window.
  ({int cursorX, Future<double> left})? _drag;

  @override
  ValueListenable<CmView> get view => _view;

  /// Upstream `showCmWindow(isStartup: true)`.
  Future<void> start() async {
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        titleBarStyle: TitleBarStyle.hidden,
        alwaysOnTop: true,
      ),
      null,
    );
    // Closing goes through the page's close handler, which disconnects the visitors first
    // (upstream `server_page.dart:66-80`).
    await windowManager.setPreventClose(true);
    await windowManager.setResizable(false);
    await show();
  }

  @override
  Future<void> show() async {
    if (_view.value != CmView.hidden) return;
    await _toFront();
  }

  @override
  Future<void> hide() async {
    if (_view.value == CmView.hidden) return;
    _view.value = CmView.hidden;
    await windowManager.setOpacity(0);
    await windowManager.hide();
  }

  @override
  Future<void> collapse() async {
    if (_view.value != CmView.full) return;
    _view.value = CmView.strip;
    await _place(CmView.strip);
  }

  @override
  Future<void> expand() async {
    if (_view.value != CmView.strip) return;
    await _toFront();
  }

  @override
  Future<void> bringToFront() => _toFront();

  @override
  Future<void> close() => windowManager.close();

  @override
  Future<void> startDragging() => windowManager.startDragging();

  @override
  void startStripDrag() {
    if (_view.value != CmView.strip) return;
    _drag = (cursorX: cmCursorX(), left: _bounds().then((b) => b.left));
  }

  @override
  Future<void> dragStrip() async {
    final drag = _drag;
    if (drag == null) return;
    // The cursor is read before waiting, so that the moves made before the start position is
    // known are not lost.
    final cursorX = cmCursorX();
    final (:work, :scale) = cmPrimaryWorkArea();
    final x = (await drag.left + cursorX - drag.cursorX).clamp(
      work.left,
      work.right - kCmStripSize.width * scale,
    );
    await windowManager.setPosition(
      Offset(x, work.top),
      ignoreDevicePixelRatio: true,
    );
  }

  @override
  Future<void> endStripDrag() async {
    final drag = _drag;
    if (drag == null) return;
    _drag = null;
    final cursorX = cmCursorX();
    final (:work, :scale) = cmPrimaryWorkArea();
    final width = kCmStripSize.width * scale;
    final x = (await drag.left + cursorX - drag.cursorX).clamp(
      work.left,
      work.right - width,
    );
    await windowManager.setPosition(
      Offset(x, work.top),
      ignoreDevicePixelRatio: true,
    );
    final offset = (work.right - width - x) / scale;
    await appCore.options.local.set(
      kOptionLeapgateCmStripOffset,
      offset.round().toString(),
    );
  }

  @override
  Future<Rect> getFrame() => _bounds();

  @override
  Future<void> setFullscreen(bool fullscreen) =>
      windowManager.setFullScreen(fullscreen);

  Future<Rect> _bounds() =>
      windowManager.getBounds(ignoreDevicePixelRatio: true);

  Future<void> _toFront() async {
    _view.value = CmView.full;
    await _place(CmView.full);
    await windowManager.setOpacity(1);
    await windowManager.show();
    await windowManager.focus();
  }

  /// Puts the window at the top right of the primary display's work area; the strip keeps the
  /// distance from the right edge it was left at.
  Future<void> _place(CmView v) async {
    final (:work, :scale) = cmPrimaryWorkArea();
    final size =
        (v == CmView.strip
            ? kCmStripSize
            : kConnectionManagerWindowSizeClosedChat) *
        scale;
    var right = work.right;
    if (v == CmView.strip) {
      final offset =
          double.tryParse(
            appCore.options.local.get(kOptionLeapgateCmStripOffset),
          ) ??
          0;
      right = (work.right - offset * scale).clamp(
        work.left + size.width,
        work.right,
      );
    }
    final topLeft = Offset(right - size.width, work.top);
    // Moved first, so that the size is set at the primary display's scale when the window comes
    // from a display with another one.
    await windowManager.setPosition(topLeft, ignoreDevicePixelRatio: true);
    await windowManager.setBounds(topLeft & size, ignoreDevicePixelRatio: true);
  }
}
