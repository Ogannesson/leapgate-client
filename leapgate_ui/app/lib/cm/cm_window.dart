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

  /// Moves the strip along the top edge by [dx] logical pixels.
  Future<void> dragStrip(double dx);

  /// Remembers where the strip was left.
  Future<void> endStripDrag();
}

class LgCmWindow implements CmShellWindow {
  final _view = ValueNotifier(CmView.hidden);

  /// The strip's left edge in physical pixels while it is dragged.
  double? _stripX;

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
  Future<void> dragStrip(double dx) async {
    if (_view.value != CmView.strip) return;
    final (:work, :scale) = cmPrimaryWorkArea();
    final width = kCmStripSize.width * scale;
    final x = (_stripX ?? (await _bounds()).left) + dx * scale;
    _stripX = x.clamp(work.left, work.right - width);
    await windowManager.setPosition(
      Offset(_stripX!, work.top),
      ignoreDevicePixelRatio: true,
    );
  }

  @override
  Future<void> endStripDrag() async {
    final x = _stripX;
    if (x == null) return;
    _stripX = null;
    final (:work, :scale) = cmPrimaryWorkArea();
    final offset = (work.right - kCmStripSize.width * scale - x) / scale;
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
