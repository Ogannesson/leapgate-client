// 上游：flutter/lib/models/model.dart@bd9262397（只删界面调用，不格式化；FfiModel 改写到 lib/leapgate/ffi_model.dart，ConnType 和 FFI 改写到 lib/leapgate/session.dart；CachedPeerData 和标签拖成窗口那条路径不要，VirtualMouseMode 随移动端再复制，clearWaitingForImage 归连接状态；删了 QualityMonitorModel.webrtcTransport：只在 Web 上有值，读 CachedPeerData）
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:tuple/tuple.dart';
import 'package:image/image.dart' as img2;
import 'package:get/get.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

import '../common.dart';
import '../utils/image.dart' as img;
import 'input_model.dart';
import 'platform_model.dart';
import 'package:flutter_hbb/utils/scale.dart';

import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/native/custom_cursor.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/notices.dart';
import 'package:flutter_hbb/leapgate/session.dart';
export 'package:flutter_hbb/leapgate/session.dart';

part '../leapgate/ffi_model.dart';

class ImageModel with ChangeNotifier {
  ui.Image? _image;

  ui.Image? get image => _image;

  String id = '';

  late final SessionID sessionId;

  bool _useTextureRender = false;

  WeakReference<FFI> parent;

  final List<Function(String)> callbacksOnFirstImage = [];

  ImageModel(this.parent) {
    sessionId = parent.target!.sessionId;
  }

  get useTextureRender => _useTextureRender;

  addCallbackOnFirstImage(Function(String) cb) => callbacksOnFirstImage.add(cb);

  clearImage() => _image = null;

  bool _webDecodingRgba = false;
  final List<Uint8List> _webRgbaList = List.empty(growable: true);
  webOnRgba(int display, Uint8List rgba) async {
    // deep copy needed, otherwise "instantiateCodec failed: TypeError: Cannot perform Construct on a detached ArrayBuffer"
    _webRgbaList.add(Uint8List.fromList(rgba));
    if (_webDecodingRgba) {
      return;
    }
    _webDecodingRgba = true;
    try {
      while (_webRgbaList.isNotEmpty) {
        final rgba2 = _webRgbaList.last;
        _webRgbaList.clear();
        await decodeAndUpdate(display, rgba2);
      }
    } catch (e) {
      debugPrint('onRgba error: $e');
    }
    _webDecodingRgba = false;
  }

  onRgba(int display, Uint8List rgba) async {
    try {
      await decodeAndUpdate(display, rgba);
    } catch (e) {
      debugPrint('onRgba error: $e');
    }
    platformFFI.nextRgba(sessionId, display);
  }

  // web only: image already created from a decoded WebCodecs frame
  Future<void> onImage(
      int display, ui.Image image, bool Function() isCurrentSession) async {
    await update(image, isCurrentSession: isCurrentSession);
  }

  decodeAndUpdate(int display, Uint8List rgba) async {
    final pid = parent.target?.id;
    final rect = parent.target?.ffiModel.pi.getDisplayRect(display);
    final image = await img.decodeImageFromPixels(
      rgba,
      rect?.width.toInt() ?? 0,
      rect?.height.toInt() ?? 0,
      isWeb | isWindows | isLinux
          ? ui.PixelFormat.rgba8888
          : ui.PixelFormat.bgra8888,
    );
    if (parent.target?.id != pid) {
      image?.dispose();
      return;
    }
    await update(image);
  }

  Future<void> update(ui.Image? image,
      {bool Function()? isCurrentSession}) async {
    if (_disposeIfStale(image, isCurrentSession)) return;
    if (_image == null && image != null) {
      if (isDesktop || isWebDesktop) {
        await parent.target?.canvasModel.updateViewStyle();
        await parent.target?.canvasModel.updateScrollStyle();
        await parent.target?.canvasModel.initializeEdgeScrollEdgeThickness();
      }
      if (parent.target != null) {
        await initializeCursorAndCanvas(parent.target!);
      }
    }
    if (_disposeIfStale(image, isCurrentSession)) return;
    _image?.dispose();
    _image = image;
    if (image != null) notifyListeners();
  }

  bool _disposeIfStale(ui.Image? image, bool Function()? isCurrentSession) {
    if (image == null || isCurrentSession == null) return false;
    if (isCurrentSession()) return false;
    image.dispose();
    return true;
  }

  // mobile only
  double get maxScale {
    if (_image == null) return 1.5;
    final size = parent.target!.canvasModel.getSize();
    final xscale = size.width / _image!.width;
    final yscale = size.height / _image!.height;
    return max(1.5, max(xscale, yscale));
  }

  // mobile only
  double get minScale {
    if (_image == null) return 1.5;
    final size = parent.target!.canvasModel.getSize();
    final xscale = size.width / _image!.width;
    final yscale = size.height / _image!.height;
    return min(xscale, yscale) / 1.5;
  }

  updateUserTextureRender() {
    final preValue = _useTextureRender;
    _useTextureRender = isDesktop && bind.mainGetUseTextureRender();
    if (preValue != _useTextureRender) {
      notifyListeners();
    }
  }

  setUseTextureRender(bool value) {
    _useTextureRender = value;
    notifyListeners();
  }

  void disposeImage() {
    _image?.dispose();
    _image = null;
  }
}

enum ScrollStyle {
  scrollbar(kRemoteScrollStyleBar),
  scrollauto(kRemoteScrollStyleAuto),
  scrolledge(kRemoteScrollStyleEdge);

  const ScrollStyle(this.stringValue);

  final String stringValue;

  String toJson() {
    return name;
  }

  static ScrollStyle fromJson(String json, [ScrollStyle? fallbackValue]) {
    switch (json) {
      case 'scrollbar':
        return scrollbar;
      case 'scrollauto':
        return scrollauto;
      case 'scrolledge':
        return scrolledge;
    }

    if (fallbackValue != null) {
      return fallbackValue;
    }

    throw ArgumentError("Unknown ScrollStyle JSON value: '$json'");
  }

  @override
  String toString() {
    return stringValue;
  }

  static ScrollStyle fromString(String string, [ScrollStyle? fallbackValue]) {
    switch (string) {
      case kRemoteScrollStyleBar:
        return scrollbar;
      case kRemoteScrollStyleAuto:
        return scrollauto;
      case kRemoteScrollStyleEdge:
        return scrolledge;
    }

    if (fallbackValue != null) {
      return fallbackValue;
    }

    throw ArgumentError("Unknown ScrollStyle string value: '$string'");
  }
}

class ViewStyle {
  final String style;
  final double width;
  final double height;
  final int displayWidth;
  final int displayHeight;
  ViewStyle({
    required this.style,
    required this.width,
    required this.height,
    required this.displayWidth,
    required this.displayHeight,
  });

  static defaultViewStyle() {
    final desktop = (isDesktop || isWebDesktop);
    final w =
        desktop ? kDesktopDefaultDisplayWidth : kMobileDefaultDisplayWidth;
    final h =
        desktop ? kDesktopDefaultDisplayHeight : kMobileDefaultDisplayHeight;
    return ViewStyle(
      style: '',
      width: w.toDouble(),
      height: h.toDouble(),
      displayWidth: w,
      displayHeight: h,
    );
  }

  static int _double2Int(double v) => (v * 100).round().toInt();

  @override
  bool operator ==(Object other) =>
      other is ViewStyle &&
      other.runtimeType == runtimeType &&
      _innerEqual(other);

  bool _innerEqual(ViewStyle other) {
    return style == other.style &&
        ViewStyle._double2Int(other.width) == ViewStyle._double2Int(width) &&
        ViewStyle._double2Int(other.height) == ViewStyle._double2Int(height) &&
        other.displayWidth == displayWidth &&
        other.displayHeight == displayHeight;
  }

  @override
  int get hashCode => Object.hash(
        style,
        ViewStyle._double2Int(width),
        ViewStyle._double2Int(height),
        displayWidth,
        displayHeight,
      ).hashCode;

  double get scale {
    double s = 1.0;
    if (style == kRemoteViewStyleAdaptive) {
      if (width != 0 &&
          height != 0 &&
          displayWidth != 0 &&
          displayHeight != 0) {
        final s1 = width / displayWidth;
        final s2 = height / displayHeight;
        s = s1 < s2 ? s1 : s2;
      }
    } else if (style == kRemoteViewStyleCustom) {
      // Custom scale is session-scoped and applied in CanvasModel.updateViewStyle()
    }
    return s;
  }
}

enum EdgeScrollState {
  inactive,
  armed,
  active,
}

class EdgeScrollFallbackState {
  final CanvasModel _owner;

  late Ticker _ticker;

  Duration _lastTotalElapsed = Duration.zero;
  bool _nextEventIsFirst = true;
  Vector2 _encroachment = Vector2.zero();

  EdgeScrollFallbackState(this._owner, TickerProvider tickerProvider) {
    _ticker = tickerProvider.createTicker(emitTick);
  }

  void setEncroachment(Vector2 encroachment) {
    _encroachment = encroachment;
  }

  void emitTick(Duration totalElapsed) {
    if (_nextEventIsFirst) {
      _lastTotalElapsed = totalElapsed;
      _nextEventIsFirst = false;
    } else {
      final thisTickElapsed = totalElapsed - _lastTotalElapsed;

      const double kFrameTime = 1000.0 / 60.0;
      const double kSpeedFactor = 0.1;

      var delta = _encroachment *
          (kSpeedFactor * thisTickElapsed.inMilliseconds / kFrameTime);

      _owner.performEdgeScroll(delta);

      _lastTotalElapsed = totalElapsed;
    }
  }

  void start() {
    if (!_ticker.isActive) {
      _nextEventIsFirst = true;
      _ticker.start();
    }
  }

  void stop() {
    _ticker.stop();
  }
}

class CanvasModel with ChangeNotifier {
  // image offset of canvas
  double _x = 0;
  // image offset of canvas
  double _y = 0;
  // image scale
  double _scale = 1.0;
  bool _locked = false;
  double _devicePixelRatio = 1.0;
  Size _size = Size.zero;
  // the tabbar over the image
  // double tabBarHeight = 0.0;
  // the window border's width
  // double windowBorderWidth = 0.0;
  // remote id
  String id = '';
  late final SessionID sessionId;
  // scroll offset x percent
  double _scrollX = 0.0;
  // scroll offset y percent
  double _scrollY = 0.0;
  ScrollStyle _scrollStyle = ScrollStyle.scrollauto;
  // edge scroll mode: trigger scrolling when the cursor is close to the edge of the view
  int _edgeScrollEdgeThickness = 100;
  // tracks whether edge scroll should be active, prevents spurious
  // scrolling when the cursor enters the view from outside
  EdgeScrollState _edgeScrollState = EdgeScrollState.inactive;
  // fallback strategy for when Bump Mouse isn't available
  late EdgeScrollFallbackState _edgeScrollFallbackState;
  // to avoid hammering a non-functional Bump Mouse
  bool _bumpMouseIsWorking = true;
  ViewStyle _lastViewStyle = ViewStyle.defaultViewStyle();

  Timer? _timerMobileFocusCanvasCursor;
  Timer? _timerMobileRestoreCanvasOffset;
  Offset? _offsetBeforeMobileSoftKeyboard;
  double? _scaleBeforeMobileSoftKeyboard;

  // `isMobileCanvasChanged` is used to avoid canvas reset when changing the input method
  // after showing the soft keyboard.
  bool isMobileCanvasChanged = false;

  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();

  final _imageOverflow = false.obs;

  WeakReference<FFI> parent;

  CanvasModel(this.parent) {
    sessionId = parent.target!.sessionId;
  }

  double get x => _x;
  double get y => _y;
  double get scale => _scale;
  bool get locked => _locked;
  double get devicePixelRatio => _devicePixelRatio;
  Size get size => _size;
  ScrollStyle get scrollStyle => _scrollStyle;
  ViewStyle get viewStyle => _lastViewStyle;
  RxBool get imageOverflow => _imageOverflow;

  void setLocked(bool value) {
    if (_locked == value) return;
    _locked = value;
    notifyListeners();
  }

  _resetScroll() => setScrollPercent(0.0, 0.0);

  void setScrollPercent(double x, double y) {
    _scrollX = x.isFinite ? x : 0.0;
    _scrollY = y.isFinite ? y : 0.0;
  }

  void pushScrollPositionToUI(double scrollPixelX, double scrollPixelY) {
    if (_horizontal.hasClients) {
      _horizontal.jumpTo(scrollPixelX);
    }
    if (_vertical.hasClients) {
      _vertical.jumpTo(scrollPixelY);
    }
  }

  ScrollController get scrollHorizontal => _horizontal;
  ScrollController get scrollVertical => _vertical;
  double get scrollX => _scrollX;
  double get scrollY => _scrollY;

  static double get leftToEdge =>
      isDesktop ? windowBorderWidth + kDragToResizeAreaPadding.left : 0;
  static double get rightToEdge =>
      isDesktop ? windowBorderWidth + kDragToResizeAreaPadding.right : 0;
  static double get topToEdge => isDesktop
      ? tabBarHeight + windowBorderWidth + kDragToResizeAreaPadding.top
      : 0;
  static double get bottomToEdge =>
      isDesktop ? windowBorderWidth + kDragToResizeAreaPadding.bottom : 0;

  Size getSize() {
    final mediaData = MediaQueryData.fromView(ui.window);
    final size = mediaData.size;
    // If minimized, w or h may be negative here.
    double w = size.width - leftToEdge - rightToEdge;
    double h = size.height - topToEdge - bottomToEdge;
    if (isMobile) {
      // Account for horizontal safe area insets on both orientations.
      w = w - mediaData.padding.left - mediaData.padding.right;
      // Vertically, subtract the bottom keyboard inset (viewInsets.bottom) and any
      // bottom overlay (e.g. key-help tools) so the canvas is not covered.
      h = h -
          mediaData.viewInsets.bottom -
          (parent.target?.cursorModel.keyHelpToolsRectToAdjustCanvas?.bottom ??
              0);
      // Orientation-specific handling:
      //  - Portrait: additionally subtract top padding (e.g. status bar / notch)
      //  - Landscape: does not subtract mediaData.padding.top/bottom (home indicator auto-hides)
      final isPortrait = size.height > size.width;
      if (isPortrait) {
        // In portrait mode, subtract the top safe-area padding (e.g. status bar / notch)
        // so the remote image is not truncated, while keeping the bottom inset to avoid
        // introducing unnecessary blank space around the canvas.
        //
        // iOS -> Android, portrait, adjust mode:
        // h = h (no padding subtracted): top and bottom are truncated
        //   https://github.com/user-attachments/assets/30ed4559-c27e-432b-847f-8fec23c9f998
        // h = h - top - bottom: extra blank spaces appear
        //   https://github.com/user-attachments/assets/12a98817-3b4e-43aa-be0f-4b03cf364b7e
        // h = h - top (current): works fine
        //   https://github.com/user-attachments/assets/95f047f2-7f47-4a36-8113-5023989a0c81
        h = h - mediaData.padding.top;
      }
    }
    return Size(w < 0 ? 0 : w, h < 0 ? 0 : h);
  }

  // mobile only
  double getAdjustY() {
    final bottom =
        parent.target?.cursorModel.keyHelpToolsRectToAdjustCanvas?.bottom ?? 0;
    return max(bottom - MediaQueryData.fromView(ui.window).padding.top, 0);
  }

  updateSize() => _size = getSize();

  updateViewStyle({refreshMousePos = true, notify = true}) async {
    final style = await bind.sessionGetViewStyle(sessionId: sessionId);
    if (style == null) {
      return;
    }

    updateSize();
    final displayWidth = getDisplayWidth();
    final displayHeight = getDisplayHeight();
    final viewStyle = ViewStyle(
      style: style,
      width: size.width,
      height: size.height,
      displayWidth: displayWidth,
      displayHeight: displayHeight,
    );
    // If only the Custom scale percent changed, proceed to update even if
    // the basic ViewStyle fields are equal.
    // In Custom scale mode, the scale percent can change independently of the other
    // ViewStyle fields and is not captured by the equality check. Therefore, we must
    // allow updates to proceed when style == kRemoteViewStyleCustom, even if the
    // rest of the ViewStyle fields are unchanged.
    if (_lastViewStyle == viewStyle &&
        _devicePixelRatio == ui.window.devicePixelRatio &&
        style != kRemoteViewStyleCustom) {
      return;
    }
    if (_lastViewStyle.style != viewStyle.style) {
      _resetScroll();
    }
    _lastViewStyle = viewStyle;
    _scale = viewStyle.scale;

    // Apply custom scale percent when in Custom mode
    if (style == kRemoteViewStyleCustom) {
      try {
        _scale = await getSessionCustomScale(sessionId);
      } catch (e, stack) {
        debugPrint('Error in getSessionCustomScale: $e');
        debugPrintStack(stackTrace: stack);
        _scale = 1.0;
      }
    }

    _devicePixelRatio = ui.window.devicePixelRatio;
    if (kIgnoreDpi) {
      if (style == kRemoteViewStyleOriginal) {
        _scale = 1.0 / _devicePixelRatio;
      } else if (_scale != 0 && style == kRemoteViewStyleCustom) {
        _scale /= _devicePixelRatio;
      }
    }
    _resetCanvasOffset(displayWidth, displayHeight);
    final overflow = _x < 0 || y < 0;
    if (_imageOverflow.value != overflow) {
      _imageOverflow.value = overflow;
    }
    if (notify) {
      notifyListeners();
    }
    if (!isMobile && refreshMousePos) {
      parent.target?.inputModel.refreshMousePos();
    }
    tryUpdateScrollStyle(Duration.zero, style);
  }

  _resetCanvasOffset(int displayWidth, int displayHeight) {
    _x = (size.width - displayWidth * _scale) / 2;
    _y = (size.height - displayHeight * _scale) / 2;
    if (isMobile) {
      _moveToCenterCursor();
    }
  }

  tryUpdateScrollStyle(Duration duration, String? style) async {
    if (_scrollStyle == ScrollStyle.scrollauto) return;
    style ??= await bind.sessionGetViewStyle(sessionId: sessionId);
    if (style != kRemoteViewStyleOriginal && style != kRemoteViewStyleCustom) {
      return;
    }

    _resetScroll();

    Future.delayed(duration, () async {
      // Layout updates scroll extents and detaches scrollbars no longer needed.
      await SchedulerBinding.instance.endOfFrame;
      updateScrollPercent();
    });
  }

  Future<void> updateScrollStyle() async {
    final style = await bind.sessionGetScrollStyle(sessionId: sessionId);

    _scrollStyle =
        style != null ? ScrollStyle.fromString(style) : ScrollStyle.scrollauto;

    if (_scrollStyle != ScrollStyle.scrollauto) {
      // Scrollbar and Scroll Edge share controllers and retain their positions.
      updateScrollPercent();
    }

    notifyListeners();
  }

  Future<void> initializeEdgeScrollEdgeThickness() async {
    final savedValue =
        await bind.sessionGetEdgeScrollEdgeThickness(sessionId: sessionId);

    if (savedValue != null) {
      _edgeScrollEdgeThickness = savedValue;
    }
  }

  void updateEdgeScrollEdgeThickness(int newThickness) {
    _edgeScrollEdgeThickness = newThickness;
    notifyListeners();
  }

  void update(double x, double y, double scale) {
    _x = x;
    _y = y;
    _scale = scale;
    notifyListeners();
  }

  bool get cursorEmbedded =>
      parent.target?.ffiModel._pi.cursorEmbedded ?? false;

  int getDisplayWidth() {
    final defaultWidth = (isDesktop || isWebDesktop)
        ? kDesktopDefaultDisplayWidth
        : kMobileDefaultDisplayWidth;
    return parent.target?.ffiModel.rect?.width.toInt() ?? defaultWidth;
  }

  int getDisplayHeight() {
    final defaultHeight = (isDesktop || isWebDesktop)
        ? kDesktopDefaultDisplayHeight
        : kMobileDefaultDisplayHeight;
    return parent.target?.ffiModel.rect?.height.toInt() ?? defaultHeight;
  }

  static double get windowBorderWidth => stateGlobal.windowBorderWidth.value;
  static double get tabBarHeight => stateGlobal.tabBarHeight;

  void activateLocalCursor() {
    if (isDesktop || isWebDesktop) {
      try {
        parent.target!.remoteCursorMoved.value = false;
      } catch (e) {
        //
      }
    }
  }

  void updateLocalCursor(double x, double y) {
    if (parent.target?.ffiModel.viewOnly == true) return;
    // If keyboard is not permitted, do not move cursor when mouse is moving.
    if (parent.target != null && parent.target!.ffiModel.keyboard) {
      // Draw cursor if is not desktop.
      if (!(isDesktop || isWebDesktop)) {
        parent.target!.cursorModel.moveLocal(x, y);
      } else {
        try {
          parent.target!.remoteCursorMoved.value = false;
        } catch (e) {
          //
        }
      }
    }
  }

  void moveDesktopMouse(double x, double y) {
    if (size.width == 0 || size.height == 0) {
      return;
    }

    // On mobile platforms, move the canvas with the cursor.
    final dw = getDisplayWidth() * _scale;
    final dh = getDisplayHeight() * _scale;
    var dxOffset = 0;
    var dyOffset = 0;
    try {
      if (dw > size.width) {
        dxOffset = (x - dw * (x / size.width) - _x).toInt();
      }
      if (dh > size.height) {
        dyOffset = (y - dh * (y / size.height) - _y).toInt();
      }
    } catch (e) {
      debugPrintStack(
          label:
              '(x,y) ($x,$y), (_x,_y) ($_x,$_y), _scale $_scale, display size (${getDisplayWidth()},${getDisplayHeight()}), size $size, , $e');
      return;
    }

    _x += dxOffset;
    _y += dyOffset;
    if (dxOffset != 0 || dyOffset != 0) {
      notifyListeners();
    }
  }

  void initializeEdgeScrollFallback(TickerProvider tickerProvider) {
    _edgeScrollFallbackState = EdgeScrollFallbackState(this, tickerProvider);
  }

  void disableEdgeScroll() {
    _edgeScrollState = EdgeScrollState.inactive;
    cancelEdgeScroll();
  }

  void rearmEdgeScroll() {
    _edgeScrollState = EdgeScrollState.armed;
  }

  void cancelEdgeScroll() {
    _edgeScrollFallbackState.stop();
  }

  (Vector2, Vector2) getScrollInfo() {
    final scrollPixel = Vector2(
        _horizontal.hasClients ? _horizontal.position.pixels : 0,
        _vertical.hasClients ? _vertical.position.pixels : 0);

    final max = Vector2(
        _horizontal.hasClients ? _horizontal.position.maxScrollExtent : 0,
        _vertical.hasClients ? _vertical.position.maxScrollExtent : 0);

    return (scrollPixel, max);
  }

  void edgeScrollMouse(double x, double y) async {
    if ((_edgeScrollState == EdgeScrollState.inactive) ||
        (size.width == 0 || size.height == 0) ||
        !(_horizontal.hasClients || _vertical.hasClients)) {
      return;
    }

    if (_edgeScrollState == EdgeScrollState.armed) {
      // Edge scroll is armed to become active once the cursor
      // is observed within the rectangle interior to the
      // edge scroll regions. If the user has just moved the
      // cursor in from outside of the window, edge scrolling
      // doesn't happen yet.
      final clientArea = Rect.fromLTWH(0, 0, size.width, size.height);

      final innerZone = clientArea.deflate(_edgeScrollEdgeThickness.toDouble());

      if (innerZone.contains(Offset(x, y))) {
        _edgeScrollState = EdgeScrollState.active;
      } else {
        // Not yet.
        return;
      }
    }

    var dxOffset = 0.0;
    var dyOffset = 0.0;

    if (x < _edgeScrollEdgeThickness) {
      dxOffset = x - _edgeScrollEdgeThickness;
    } else if (x >= size.width - _edgeScrollEdgeThickness) {
      dxOffset = x - (size.width - _edgeScrollEdgeThickness);
    }

    if (y < _edgeScrollEdgeThickness) {
      dyOffset = y - _edgeScrollEdgeThickness;
    } else if (y >= size.height - _edgeScrollEdgeThickness) {
      dyOffset = y - (size.height - _edgeScrollEdgeThickness);
    }

    var encroachment = Vector2(dxOffset, dyOffset);

    var (scrollPixel, max) = getScrollInfo();

    encroachment.clamp(-scrollPixel, max - scrollPixel);

    if (encroachment.length2 == 0) {
      _edgeScrollFallbackState.stop();
    } else {
      var bumpAmount = -encroachment;

      // Round away from 0: this ensures that the mouse will be bumped clear of
      // whichever edge scroll zone(s) it is in
      bumpAmount.x += bumpAmount.x.sign * 0.5;
      bumpAmount.y += bumpAmount.y.sign * 0.5;

      var bumpMouseSucceeded = _bumpMouseIsWorking &&
          await RdPlatformChannel.instance.bumpMouse(
                  dx: bumpAmount.x.round(), dy: bumpAmount.y.round());

      if (bumpMouseSucceeded) {
        performEdgeScroll(encroachment);
      } else {
        // If we can't BumpMouse, then we switch to slower scrolling with autorepeat

        // Don't keep hammering BumpMouse if it's not working.
        _bumpMouseIsWorking = false;

        // Keep scrolling as long as the user is overtop of an edge.
        _edgeScrollFallbackState.setEncroachment(encroachment);
        _edgeScrollFallbackState.start();
      }
    }
  }

  void performEdgeScroll(Vector2 delta) {
    var (scrollPixel, max) = getScrollInfo();

    scrollPixel += delta;

    scrollPixel.clamp(Vector2.zero(), max);

    var scrollPixelPercent = scrollPixel.clone();

    scrollPixelPercent.divide(max);
    scrollPixelPercent.scale(100.0);

    setScrollPercent(scrollPixelPercent.x, scrollPixelPercent.y);
    pushScrollPositionToUI(scrollPixel.x, scrollPixel.y);

    notifyListeners();
  }

  panX(double dx) {
    _x += dx;
    if (isMobile) {
      isMobileCanvasChanged = true;
    }
    notifyListeners();
  }

  resetOffset() {
    if (isWebDesktop) {
      updateViewStyle();
    } else {
      _resetCanvasOffset(getDisplayWidth(), getDisplayHeight());
    }
    notifyListeners();
  }

  panY(double dy) {
    _y += dy;
    if (isMobile) {
      isMobileCanvasChanged = true;
    }
    notifyListeners();
  }

  // mobile only
  updateScale(double v, Offset focalPoint) {
    if (parent.target?.imageModel.image == null) return;
    final s = _scale;
    _scale *= v;
    final maxs = parent.target?.imageModel.maxScale ?? 1;
    final mins = parent.target?.imageModel.minScale ?? 1;
    if (_scale > maxs) _scale = maxs;
    if (_scale < mins) _scale = mins;
    // (focalPoint.dx - _x_1) / s1 + displayOriginX = (focalPoint.dx - _x_2) / s2 + displayOriginX
    // _x_2 = focalPoint.dx - (focalPoint.dx - _x_1) / s1 * s2
    _x = focalPoint.dx - (focalPoint.dx - _x) / s * _scale;
    final adjust = getAdjustY();
    // (focalPoint.dy - _y_1 - adjust) / s1 + displayOriginY = (focalPoint.dy - _y_2 - adjust) / s2 + displayOriginY
    // _y_2 = focalPoint.dy - adjust - (focalPoint.dy - _y_1 - adjust) / s1 * s2
    _y = focalPoint.dy - adjust - (focalPoint.dy - _y - adjust) / s * _scale;
    if (isMobile) {
      isMobileCanvasChanged = true;
    }
    notifyListeners();
  }

  // For reset canvas to the last view style
  reset() {
    _scale = _lastViewStyle.scale;
    _devicePixelRatio = ui.window.devicePixelRatio;
    if (kIgnoreDpi && _lastViewStyle.style == kRemoteViewStyleOriginal) {
      _scale = 1.0 / _devicePixelRatio;
    }
    _resetCanvasOffset(getDisplayWidth(), getDisplayHeight());
    bind.sessionSetViewStyle(sessionId: sessionId, value: _lastViewStyle.style);
    notifyListeners();
  }

  clear() {
    _x = 0;
    _y = 0;
    _scale = 1.0;
    _locked = false;
    _lastViewStyle = ViewStyle.defaultViewStyle();
    _timerMobileFocusCanvasCursor?.cancel();
    _timerMobileRestoreCanvasOffset?.cancel();
    _offsetBeforeMobileSoftKeyboard = null;
    _scaleBeforeMobileSoftKeyboard = null;
  }

  updateScrollPercent() {
    final percentX = _horizontal.hasClients
        ? _horizontal.position.extentBefore /
            (_horizontal.position.extentBefore +
                _horizontal.position.extentInside +
                _horizontal.position.extentAfter)
        : 0.0;
    final percentY = _vertical.hasClients
        ? _vertical.position.extentBefore /
            (_vertical.position.extentBefore +
                _vertical.position.extentInside +
                _vertical.position.extentAfter)
        : 0.0;
    setScrollPercent(percentX, percentY);
  }

  void mobileFocusCanvasCursor() {
    _timerMobileFocusCanvasCursor?.cancel();
    _timerMobileFocusCanvasCursor =
        Timer(Duration(milliseconds: 100), () async {
      updateSize();
      _resetCanvasOffset(getDisplayWidth(), getDisplayHeight());
      notifyListeners();
    });
  }

  void saveMobileOffsetBeforeSoftKeyboard() {
    _timerMobileRestoreCanvasOffset?.cancel();
    _offsetBeforeMobileSoftKeyboard = Offset(_x, _y);
    _scaleBeforeMobileSoftKeyboard = _scale;
  }

  void restoreMobileOffsetAfterSoftKeyboard() {
    _timerMobileRestoreCanvasOffset?.cancel();
    _timerMobileFocusCanvasCursor?.cancel();
    final targetOffset = _offsetBeforeMobileSoftKeyboard;
    final targetScale = _scaleBeforeMobileSoftKeyboard;
    if (targetOffset == null || targetScale == null) {
      return;
    }
    _timerMobileRestoreCanvasOffset = Timer(Duration(milliseconds: 100), () {
      updateSize();
      _x = targetOffset.dx;
      _y = targetOffset.dy;
      _scale = targetScale;
      _offsetBeforeMobileSoftKeyboard = null;
      _scaleBeforeMobileSoftKeyboard = null;
      notifyListeners();
    });
  }

  // mobile only
  // Move the canvas to make the cursor visible(center) on the screen.
  void _moveToCenterCursor() {
    Rect? imageRect = parent.target?.ffiModel.rect;
    if (imageRect == null) {
      // unreachable
      return;
    }
    final maxX = 0.0;
    final minX = _size.width + (imageRect.left - imageRect.right) * _scale;
    final maxY = 0.0;
    final minY = _size.height + (imageRect.top - imageRect.bottom) * _scale;
    Offset offsetToCenter =
        parent.target?.cursorModel.getCanvasOffsetToCenterCursor() ??
            Offset.zero;
    if (minX < 0) {
      _x = min(max(offsetToCenter.dx, minX), maxX);
    } else {
      // _size.width > (imageRect.right, imageRect.left) * _scale, we should not change _x
    }
    if (minY < 0) {
      _y = min(max(offsetToCenter.dy, minY), maxY);
    } else {
      // _size.height > (imageRect.bottom - imageRect.top) * _scale, , we should not change _y
    }
  }
}

// data for cursor
class CursorData {
  // At most 1 MiB of RGBA, including Linux's square cursor padding: twice the largest
  // accessibility cursor, beyond which a cursor is shown smaller rather than larger.
  static const _maxRasterSize = 512;

  final String peerId;
  final String id;
  img2.Image? _image;
  double scale;
  Uint8List? data;
  final double hotxOrigin;
  final double hotyOrigin;
  double hotx;
  double hoty;
  final int width;
  final int height;
  int _rasterWidth;
  int _rasterHeight;
  bool _scaleLimitReported = false;

  int get rasterWidth => _rasterWidth;
  int get rasterHeight => _rasterHeight;

  img2.Image get image => _image!;

  /// False for a shape not in use; only the shape in use keeps pixels, for a new raster.
  bool get hasPixels => _image != null;

  void releasePixels() {
    _image = null;
    data = null;
  }

  CursorData({
    required this.peerId,
    required this.id,
    required img2.Image image,
    required this.scale,
    required this.data,
    required this.hotxOrigin,
    required this.hotyOrigin,
    required this.width,
    required this.height,
  })  : _image = image,
        _rasterWidth = (width * scale).ceil(),
        _rasterHeight = (height * scale).ceil(),
        hotx = hotxOrigin * scale,
        hoty = hotyOrigin * scale;

  int _doubleToInt(double v) => (v * 10e6).round().toInt();

  double _limitScale(double requestedScale) {
    final valid = requestedScale.isFinite && requestedScale > 0;
    // Invalid requests retain the last valid raster and hotspot.
    final limitedScale = valid
        ? min(requestedScale, _maxRasterSize / max(width, height))
        : scale;
    final limited = !valid || limitedScale != requestedScale;
    if (limited && !_scaleLimitReported) {
      debugPrint(
          'Cursor $id: rejected scale $requestedScale for ${width}x$height; '
          'using $limitedScale (maximum raster side $_maxRasterSize).');
    }
    _scaleLimitReported = limited;
    return limitedScale;
  }

  double _checkUpdateScale(double scale) {
    scale = _limitScale(scale);
    if (scale != 1.0) {
      // A thin cursor must not grow just to make its short edge reach the minimum.
      scale = max(scale, kMinCursorSize / max(width, height));
    }

    final targetWidth = (width * scale).ceil();
    final targetHeight = (height * scale).ceil();
    if ((_rasterWidth != targetWidth || _rasterHeight != targetHeight) &&
        !hasPixels) {
      // Nothing to make this raster from; buildCursorOfCache asks for the pixels unless its
      // native cursor was made before.
      data = null;
      return scale;
    }
    if (_rasterWidth != targetWidth || _rasterHeight != targetHeight) {
      if (isWindows) {
        data = img2
            .copyResize(
              image,
              width: targetWidth,
              height: targetHeight,
              interpolation: img2.Interpolation.average,
            )
            .getBytes(order: img2.ChannelOrder.bgra);
      } else if (isDesktop && scale < 1.0 && !image.hasPalette) {
        data = Uint8List.fromList(
            img2.encodePng(_resizeWithAlpha(targetWidth, targetHeight)));
      } else {
        data = Uint8List.fromList(
          img2.encodePng(
            img2.copyResize(
              image,
              width: targetWidth,
              height: targetHeight,
              interpolation: img2.Interpolation.average,
            ),
          ),
        );
      }
      _rasterWidth = targetWidth;
      _rasterHeight = targetHeight;
    }

    this.scale = scale;
    hotx = hotxOrigin * _rasterWidth / width;
    hoty = hotyOrigin * _rasterHeight / height;
    return scale;
  }

  img2.Image _resizeWithAlpha(int targetWidth, int targetHeight) {
    final resized =
        img2.Image.fromResized(image, width: targetWidth, height: targetHeight);
    final dx = image.width / targetWidth;
    final dy = image.height / targetHeight;
    // Use the average filter's sample area, but weight RGB by alpha so
    // transparent pixels do not darken visible edges in the straight-alpha PNG.
    for (final pixel in resized) {
      final x = (pixel.x * dx).toInt();
      final y = (pixel.y * dy).toInt();
      final sampleWidth = ((pixel.x + 1) * dx).toInt() - x;
      final sampleHeight = ((pixel.y + 1) * dy).toInt() - y;
      final samples = image.getRange(x, y, sampleWidth, sampleHeight);
      num r = 0;
      num g = 0;
      num b = 0;
      num a = 0;
      while (samples.moveNext()) {
        final sample = samples.current;
        r += sample.r * sample.a;
        g += sample.g * sample.a;
        b += sample.b * sample.a;
        a += sample.a;
      }
      if (a == 0) {
        pixel.setRgba(0, 0, 0, 0);
        continue;
      }
      pixel.setRgba(r / a, g / a, b / a, a / (sampleWidth * sampleHeight));
    }
    return resized;
  }

  String updateGetKey(double scale) {
    scale = _checkUpdateScale(scale);
    // The raster asked for, not the one made last: a shape without pixels keeps the native
    // cursors of every raster it was shown at.
    return '${peerId}_${id}_${_doubleToInt(width * scale)}_${_doubleToInt(height * scale)}_${(width * scale).ceil()}_${(height * scale).ceil()}';
  }
}

const _forbiddenCursorPng =
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAAAAXNSR0IB2cksfwAAAAlwSFlzAAALEwAACxMBAJqcGAAAAkZQTFRFAAAA2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4G2B4GWAwCAAAAAAAA2B4GAAAAMTExAAAAAAAA2B4G2B4G2B4GAAAAmZmZkZGRAQEBAAAA2B4G2B4G2B4G////oKCgAwMDag8D2B4G2B4G2B4Gra2tBgYGbg8D2B4G2B4Gubm5CQkJTwsCVgwC2B4GxcXFDg4OAAAAAAAA2B4G2B4Gz8/PFBQUAAAAAAAA2B4G2B4G2B4G2B4G2B4G2B4G2B4GDgIA2NjYGxsbAAAAAAAA2B4GFwMB4eHhIyMjAAAAAAAA2B4G6OjoLCwsAAAAAAAA2B4G2B4G2B4G2B4G2B4GCQEA4ODgv7+/iYmJY2NjAgICAAAA9PT0Ojo6AAAAAAAAAAAA+/v7SkpKhYWFr6+vAAAAAAAA8/PzOTk5ERER9fX1KCgoAAAAgYGBKioqAAAAAAAApqamlpaWAAAAAAAAAAAAAAAAAAAAAAAALi4u/v7+GRkZAAAAAAAAAAAAAAAAAAAAfn5+AAAAAAAAV1dXkJCQAAAAAAAAAQEBAAAAAAAAAAAA7Hz6BAAAAMJ0Uk5TAAIWEwEynNz6//fVkCAatP2fDUHs6cDD8d0mPfT5fiEskiIR584A0gejr3AZ+P4plfALf5ZiTL85a4ziD6697fzN3UYE4v/4TwrNHuT///tdRKZh///+1U/ZBv///yjb///eAVL//50Cocv//6oFBbPvpGZCbfT//7cIhv///8INM///zBEcWYSZmO7//////1P////ts/////8vBv//////gv//R/z///QQz9sevP///2waXhNO/+fc//8mev/5gAe2r90MAAAByUlEQVR4nGNggANGJmYWBpyAlY2dg5OTi5uHF6s0H78AJxRwCAphyguLgKRExcQlQLSkFLq8tAwnp6ycPNABjAqKQKNElVDllVU4OVVhVquJA81Q10BRoAkUUYbJa4Edoo0sr6PLqaePLG/AyWlohKTAmJPTBFnelAFoixmSAnNOTgsUeQZLTk4rJAXWnJw2EHlbiDyDPCenHZICe04HFrh+RydnBgYWPU5uJAWinJwucPNd3dw9GDw5Ob2QFHBzcnrD7ffx9fMPCOTkDEINhmC4+3x8Q0LDwlEDIoKTMzIKKg9SEBIdE8sZh6SAJZ6Tkx0qD1YQkpCYlIwclCng0AXLQxSEpKalZyCryATKZwkhKQjJzsnNQ1KQXwBUUVhUXBJYWgZREFJeUVmFpMKlWg+anmqgCkJq6+obkG1pLEBTENLU3NKKrIKhrb2js8u4G6Kgpze0r3/CRAZMAHbkpJDJU6ZMmTqtFbuC6TNmhsyaMnsOFlmwgrnzpsxfELJwEXZ5Bp/FS3yWLlsesmLlKuwKVk9Ys5Zh3foN0zduwq5g85atDAzbpqSGbN9RhV0FGOzctWH3lD14FOzdt3H/gQw8Cg4u2gQPAwBYDXXdIH+wqAAAAABJRU5ErkJggg==';
const _defaultCursorPng =
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAAXNSR0IArs4c6QAAAARzQklUCAgICHwIZIgAAAFmSURBVFiF7dWxSlxREMbx34QFDRowYBchZSxSCWlMCOwD5FGEFHap06UI7KPsAyyEEIQFqxRaCqYTsqCJFsKkuAeRXb17wrqV918dztw55zszc2fo6Oh47MR/e3zO1/iAHWmznHKGQwx9ip/LEbCfazbsoY8j/JLOhcC6sCW9wsjEwJf483AC9nPNc1+lFRwI13d+l3rYFS799rFGxJMqARv2pBXh+72XQ7gWvklPS7TmMl9Ak/M+DqrENvxAv/guKKApuKPWl0/TROK4+LbSqzhuB+OZ3fRSeFPWY+Fkyn56Y29hfgTSpnQ+s98cvorVey66uPlNFxKwZOYLCGfCs5n9NMYVrsp6mvXSoFqpqYFDvMBkStgJJe93dZOwVXxbqUnBENulydSReqUrDhcX0PT2EXarBYS3GNXMhboinBgIl9K71kg0L3+PvyYGdVpruT2MwrF0iotiXfIwus0Dj+OOjo6Of+e7ab74RkpgAAAAAElFTkSuQmCC';

const kPreForbiddenCursorId = "-2";
final preForbiddenCursor = PredefinedCursor(
  png: _forbiddenCursorPng,
  id: kPreForbiddenCursorId,
);
const kPreDefaultCursorId = "-1";
final preDefaultCursor = PredefinedCursor(
  png: _defaultCursorPng,
  id: kPreDefaultCursorId,
  hotxGetter: (double w) => w / 2,
  hotyGetter: (double h) => h / 2,
);

class PredefinedCursor {
  ui.Image? _image;
  img2.Image? _image2;
  CursorData? _cache;
  String png;
  String id;
  double Function(double)? hotxGetter;
  double Function(double)? hotyGetter;

  PredefinedCursor(
      {required this.png, required this.id, this.hotxGetter, this.hotyGetter}) {
    init();
  }

  ui.Image? get image => _image;
  CursorData? get cache => _cache;

  init() {
    _image2 = img2.decodePng(base64Decode(png));
    if (_image2 != null) {
      // The png type of forbidden cursor image is `PngColorType.indexed`.
      if (id == kPreForbiddenCursorId) {
        _image2 = _image2!.convert(format: img2.Format.uint8, numChannels: 4);
      }

      () async {
        final defaultImg = _image2!;
        // This function is called only one time, no need to care about the performance.
        Uint8List data = defaultImg.getBytes(order: img2.ChannelOrder.rgba);
        _image?.dispose();
        _image = await img.decodeImageFromPixels(
            data, defaultImg.width, defaultImg.height, ui.PixelFormat.rgba8888);
        if (_image == null) {
          print("decodeImageFromPixels failed, pre-defined cursor $id");
          return;
        }
        double scale = 1.0;
        if (isWindows) {
          data = _image2!.getBytes(order: img2.ChannelOrder.bgra);
        } else {
          data = Uint8List.fromList(img2.encodePng(_image2!));
        }

        _cache = CursorData(
          peerId: '',
          id: id,
          image: _image2!.clone(),
          scale: scale,
          data: data,
          hotxOrigin:
              hotxGetter != null ? hotxGetter!(_image2!.width.toDouble()) : 0,
          hotyOrigin:
              hotyGetter != null ? hotyGetter!(_image2!.height.toDouble()) : 0,
          width: _image2!.width,
          height: _image2!.height,
        );
      }();
    }
  }
}

class CursorModel with ChangeNotifier {
  ui.Image? _image;
  final _images = <String, Tuple3<ui.Image, double, double>>{};
  CursorData? _cache;
  final _cacheMap = <String, CursorData>{};
  final _cacheKeys = <String>{};
  double _x = -10000;
  double _y = -10000;
  // int.parse(evt['id']) may cause FormatException
  // So we use String here.
  String _id = "-1";
  double _hotx = 0;
  double _hoty = 0;
  double _displayOriginX = 0;
  double _displayOriginY = 0;
  DateTime? _firstUpdateMouseTime;
  Rect? _windowRect;
  List<RemoteWindowCoords> _remoteWindowCoords = [];
  bool gotMouseControl = true;
  DateTime _lastPeerMouse = DateTime.now()
      .subtract(Duration(milliseconds: 3000 * kMouseControlTimeoutMSec));
  String peerId = '';
  WeakReference<FFI> parent;

  // Only for mobile, touch mode
  // To block touch event above the KeyHelpTools
  //
  // A better way is to not listen events from the KeyHelpTools.
  // But we're now using a Container(child: Stack(...)) to wrap the KeyHelpTools,
  // and the listener is on the Container.
  Rect? _keyHelpToolsRect;
  // `lastIsBlocked` is only used in common/widgets/remote_input.dart -> _RawTouchGestureDetectorRegionState -> onDoubleTap()
  // Because onDoubleTap() doesn't have the `event` parameter, we can't get the touch event's position.
  bool _lastIsBlocked = false;
  bool _lastKeyboardIsVisible = false;

  bool get lastKeyboardIsVisible => _lastKeyboardIsVisible;

  Rect? get keyHelpToolsRectToAdjustCanvas =>
      _lastKeyboardIsVisible ? _keyHelpToolsRect : null;
  // The blocked rect is used to block the pointer/touch events in the remote page.
  final List<Rect> _blockedRects = [];
  // Used in shouldBlock().
  // _blockEvents is a flag to block pointer/touch events on the remote image.
  // It is set to true to prevent accidental touch events in the following scenarios:
  //   1. In floating mouse mode, when the scroll circle is shown.
  //   2. In floating mouse widgets mode, when the left/right buttons are moving.
  //   3. In floating mouse widgets mode, when using the virtual joystick.
  // When _blockEvents is true, all pointer/touch events are blocked regardless of the contents of _blockedRects.
  // _blockedRects contains specific rectangular regions where events are blocked; these are checked when _blockEvents is false.
  // In summary: _blockEvents acts as a global block, while _blockedRects provides fine-grained blocking.
  bool _blockEvents = false;
  List<Rect> get blockedRects => List.unmodifiable(_blockedRects);

  set blockEvents(bool v) => _blockEvents = v;

  keyHelpToolsVisibilityChanged(Rect? rect, bool keyboardIsVisible) {
    _keyHelpToolsRect = rect;
    if (rect == null) {
      _lastIsBlocked = false;
    } else {
      // Block the touch event is safe here.
      // `lastIsBlocked` is only used in onDoubleTap() to block the touch event from the KeyHelpTools.
      // `lastIsBlocked` will be set when the cursor is moving or touch somewhere else.
      _lastIsBlocked = true;
    }
    if (isMobile && _lastKeyboardIsVisible != keyboardIsVisible) {
      if (keyboardIsVisible) {
        parent.target?.canvasModel.saveMobileOffsetBeforeSoftKeyboard();
        parent.target?.canvasModel.mobileFocusCanvasCursor();
        parent.target?.canvasModel.isMobileCanvasChanged = false;
      } else {
        parent.target?.canvasModel.restoreMobileOffsetAfterSoftKeyboard();
      }
    }
    _lastKeyboardIsVisible = keyboardIsVisible;
  }

  addBlockedRect(Rect rect) {
    _blockedRects.add(rect);
  }

  removeBlockedRect(Rect rect) {
    _blockedRects.remove(rect);
  }

  get lastIsBlocked => _lastIsBlocked;

  /// The image of the shape in use, or the one shown before until it is back: a switch falls
  /// back to the default cursor only for a shape the core cannot give. Asks the core for the
  /// shape in use when it was let go.
  ui.Image? get image {
    if (_images[_id] == null && _cacheMap.containsKey(_id)) {
      restorePixels(_id);
    }
    return _image;
  }

  CursorData? get cache => _cache;

  double get x => _x - _displayOriginX;
  double get y => _y - _displayOriginY;

  double get devicePixelRatio => parent.target!.canvasModel.devicePixelRatio;

  Offset get offset => Offset(_x, _y);

  double get hotx => _hotx;
  double get hoty => _hoty;

  set id(String id) {
    if (_id != id) _unavailable = null;
    _id = id;
  }

  bool get isPeerControlProtected =>
      DateTime.now().difference(_lastPeerMouse).inMilliseconds <
      kMouseControlTimeoutMSec;

  bool isConnIn2Secs() {
    if (_firstUpdateMouseTime == null) {
      _firstUpdateMouseTime = DateTime.now();
      return true;
    } else {
      return DateTime.now().difference(_firstUpdateMouseTime!).inSeconds < 2;
    }
  }

  CursorModel(this.parent) {
    // Made now, not when first drawn: nothing draws again when their decode lands, so the first
    // build that needs one would show the shape before in its place.
    preDefaultCursor.cache;
    preForbiddenCursor.cache;
  }

  Set<String> get cachedKeys => _cacheKeys;
  addKey(String key) => _cacheKeys.add(key);

  // remote physical display coordinate
  // For update pan (mobile), onOneFingerPanStart, onOneFingerPanUpdate, onHoldDragUpdate
  Rect getVisibleRect() {
    final size = parent.target?.canvasModel.getSize() ??
        MediaQueryData.fromView(ui.window).size;
    final xoffset = parent.target?.canvasModel.x ?? 0;
    final yoffset = parent.target?.canvasModel.y ?? 0;
    final scale = parent.target?.canvasModel.scale ?? 1;
    final x0 = _displayOriginX - xoffset / scale;
    final y0 = _displayOriginY - yoffset / scale;
    return Rect.fromLTWH(x0, y0, size.width / scale, size.height / scale);
  }

  Offset getCanvasOffsetToCenterCursor() {
    // Cursor should be at the center of the visible rect.
    // _x = rect.left + rect.width / 2
    // _y = rect.right + rect.height / 2
    // See `getVisibleRect()`
    // _x = _displayOriginX - xoffset / scale + size.width / scale * 0.5;
    // _y = _displayOriginY - yoffset / scale + size.height / scale * 0.5;
    final size = parent.target?.canvasModel.getSize() ??
        MediaQueryData.fromView(ui.window).size;
    final xoffset = (_displayOriginX - _x) * scale + size.width * 0.5;
    final yoffset = (_displayOriginY - _y) * scale + size.height * 0.5;
    return Offset(xoffset, yoffset);
  }

  get scale => parent.target?.canvasModel.scale ?? 1.0;

  // mobile Soft keyboard, block touch event from the KeyHelpTools
  shouldBlock(double x, double y) {
    if (_blockEvents) {
      return true;
    }
    final offset = Offset(x, y);
    for (final rect in _blockedRects) {
      if (isPointInRect(offset, rect)) {
        return true;
      }
    }

    // For help tools rectangle, only block touch event when in touch mode.
    if (!(parent.target?.ffiModel.touchMode ?? false)) {
      return false;
    }
    if (_keyHelpToolsRect != null &&
        isPointInRect(offset, _keyHelpToolsRect!)) {
      return true;
    }
    return false;
  }

  // For touch mode
  Future<bool> move(double x, double y) async {
    if (shouldBlock(x, y)) {
      _lastIsBlocked = true;
      return false;
    }
    _lastIsBlocked = false;
    if (!_moveLocalIfInRemoteRect(x, y)) {
      return false;
    }
    await parent.target?.inputModel.moveMouse(_x, _y);
    return true;
  }

  Future<void> syncCursorPosition() async {
    await parent.target?.inputModel.moveMouse(_x, _y);
  }

  bool isInRemoteRect(Offset offset) {
    return getRemotePosInRect(offset) != null;
  }

  Offset? getRemotePosInRect(Offset offset) {
    final adjust = parent.target?.canvasModel.getAdjustY() ?? 0;
    final newPos = _getNewPos(offset.dx, offset.dy, adjust);
    final visibleRect = getVisibleRect();
    if (!isPointInRect(newPos, visibleRect)) {
      return null;
    }
    final rect = parent.target?.ffiModel.rect;
    if (rect != null) {
      if (!isPointInRect(newPos, rect)) {
        return null;
      }
    }
    return newPos;
  }

  Offset _getNewPos(double x, double y, double adjust) {
    final xoffset = parent.target?.canvasModel.x ?? 0;
    final yoffset = parent.target?.canvasModel.y ?? 0;
    final newX = (x - xoffset) / scale + _displayOriginX;
    final newY = (y - yoffset - adjust) / scale + _displayOriginY;
    return Offset(newX, newY);
  }

  bool _moveLocalIfInRemoteRect(double x, double y) {
    final newPos = getRemotePosInRect(Offset(x, y));
    if (newPos == null) {
      return false;
    }
    _x = newPos.dx;
    _y = newPos.dy;
    notifyListeners();
    return true;
  }

  moveLocal(double x, double y, {double adjust = 0}) {
    final newPos = _getNewPos(x, y, adjust);
    _x = newPos.dx;
    _y = newPos.dy;
    notifyListeners();
  }

  reset() {
    _x = _displayOriginX;
    _y = _displayOriginY;
    parent.target?.inputModel.moveMouse(_x, _y);
    parent.target?.canvasModel.reset();
    notifyListeners();
  }

  updatePan(Offset delta, Offset localPosition, bool touchMode) async {
    if (touchMode) {
      await _handleTouchMode(delta, localPosition);
      return;
    }
    double dx = delta.dx;
    double dy = delta.dy;
    if (parent.target?.imageModel.image == null) return;
    final scale = parent.target?.canvasModel.scale ?? 1.0;
    dx /= scale;
    dy /= scale;
    final r = getVisibleRect();
    var cx = r.center.dx;
    var cy = r.center.dy;
    var tryMoveCanvasX = false;
    final displayRect = parent.target?.ffiModel.rect;
    if (dx > 0) {
      final maxCanvasCanMove = _displayOriginX +
          (displayRect?.width ?? 1280) -
          r.right.roundToDouble();
      tryMoveCanvasX = _x + dx > cx && maxCanvasCanMove > 0;
      if (tryMoveCanvasX) {
        dx = min(dx, maxCanvasCanMove);
      } else {
        final maxCursorCanMove = r.right - _x;
        dx = min(dx, maxCursorCanMove);
      }
    } else if (dx < 0) {
      final maxCanvasCanMove = _displayOriginX - r.left.roundToDouble();
      tryMoveCanvasX = _x + dx < cx && maxCanvasCanMove < 0;
      if (tryMoveCanvasX) {
        dx = max(dx, maxCanvasCanMove);
      } else {
        final maxCursorCanMove = r.left - _x;
        dx = max(dx, maxCursorCanMove);
      }
    }
    var tryMoveCanvasY = false;
    if (dy > 0) {
      final mayCanvasCanMove = _displayOriginY +
          (displayRect?.height ?? 720) -
          r.bottom.roundToDouble();
      tryMoveCanvasY = _y + dy > cy && mayCanvasCanMove > 0;
      if (tryMoveCanvasY) {
        dy = min(dy, mayCanvasCanMove);
      } else {
        final mayCursorCanMove = r.bottom - _y;
        dy = min(dy, mayCursorCanMove);
      }
    } else if (dy < 0) {
      final mayCanvasCanMove = _displayOriginY - r.top.roundToDouble();
      tryMoveCanvasY = _y + dy < cy && mayCanvasCanMove < 0;
      if (tryMoveCanvasY) {
        dy = max(dy, mayCanvasCanMove);
      } else {
        final mayCursorCanMove = r.top - _y;
        dy = max(dy, mayCursorCanMove);
      }
    }

    if (dx == 0 && dy == 0) return;

    Point<double>? newPos;
    final rect = parent.target?.ffiModel.rect;
    if (rect == null) {
      // unreachable
      return;
    }
    newPos = InputModel.getPointInRemoteRect(
        false,
        parent.target?.ffiModel.pi.platform,
        kPointerEventKindMouse,
        kMouseEventTypeDefault,
        _x + dx,
        _y + dy,
        rect,
        buttons: kPrimaryButton);
    if (newPos == null) {
      return;
    }
    dx = newPos.x - _x;
    dy = newPos.y - _y;
    _x = newPos.x;
    _y = newPos.y;
    if (tryMoveCanvasX && dx != 0) {
      parent.target?.canvasModel.panX(-dx * scale);
    }
    if (tryMoveCanvasY && dy != 0) {
      parent.target?.canvasModel.panY(-dy * scale);
    }

    parent.target?.inputModel.moveMouse(_x, _y);
    notifyListeners();
  }

  bool _isInCurrentWindow(double x, double y) {
    final w = _windowRect!.width / devicePixelRatio;
    final h = _windowRect!.width / devicePixelRatio;
    return x >= 0 && y >= 0 && x <= w && y <= h;
  }

  _handleTouchMode(Offset delta, Offset localPosition) async {
    bool isMoved = false;
    if (_remoteWindowCoords.isNotEmpty &&
        _windowRect != null &&
        !_isInCurrentWindow(localPosition.dx, localPosition.dy)) {
      final coords = InputModel.findRemoteCoords(localPosition.dx,
          localPosition.dy, _remoteWindowCoords, devicePixelRatio);
      if (coords != null) {
        double x2 =
            (localPosition.dx - coords.relativeOffset.dx / devicePixelRatio) /
                coords.canvas.scale;
        double y2 =
            (localPosition.dy - coords.relativeOffset.dy / devicePixelRatio) /
                coords.canvas.scale;
        x2 += coords.cursor.offset.dx;
        y2 += coords.cursor.offset.dy;
        await parent.target?.inputModel.moveMouse(x2, y2);
        isMoved = true;
      }
    }
    if (!isMoved) {
      final rect = parent.target?.ffiModel.rect;
      if (rect == null) {
        // unreachable
        return;
      }

      Offset? movementInRect(double x, double y, Rect r) {
        final isXInRect = x >= r.left && x <= r.right;
        final isYInRect = y >= r.top && y <= r.bottom;
        if (!(isXInRect || isYInRect)) {
          return null;
        }
        if (x < r.left) {
          x = r.left;
        } else if (x > r.right) {
          x = r.right;
        }
        if (y < r.top) {
          y = r.top;
        } else if (y > r.bottom) {
          y = r.bottom;
        }
        return Offset(x, y);
      }

      final scale = parent.target?.canvasModel.scale ?? 1.0;
      var movement =
          movementInRect(_x + delta.dx / scale, _y + delta.dy / scale, rect);
      if (movement == null) {
        return;
      }
      movement = movementInRect(movement.dx, movement.dy, getVisibleRect());
      if (movement == null) {
        return;
      }

      _x = movement.dx;
      _y = movement.dy;
      await parent.target?.inputModel.moveMouse(_x, _y);
    }
    notifyListeners();
  }

  disposeImages() {
    _images.forEach((_, v) => v.item1.dispose());
    _images.clear();
  }

  /// Its image is kept with the ones used last, see [_imageLimit]; a shape that does not decode
  /// is marked as one the core cannot give.
  Future<void> updateCursorData(String id, int hotxInt, int hotyInt, int width,
      int height, Uint8List rgba) async {
    final generation = _generation;
    if (_unavailable == id) _unavailable = null;
    final hotx = hotxInt.toDouble();
    final hoty = hotyInt.toDouble();
    final image = await img.decodeImageFromPixels(
        rgba, width, height, ui.PixelFormat.rgba8888);
    if (image == null) {
      // It did not decode; painting must not ask for it on every frame.
      _markUnavailable(generation, id);
      return;
    }
    if (!await _updateCache(
        generation, rgba, image, id, hotx, hoty, width, height)) {
      // Not kept, or the session was cleared while it decoded.
      image.dispose();
      _markUnavailable(generation, id);
      return;
    }
    final old = _images.remove(id);
    _images[id] = Tuple3(image, hotx, hoty);
    if (old != null) {
      if (identical(old.item1, _image)) _image = image;
      old.item1.dispose();
    }

    // Update last cursor data.
    // Do not use the previous `image` and `id`, because `_id` may be changed.
    _updateCurData();
    final cache = _cacheMap[id];
    if (id != _id && cache != null) _switchedAway(cache);
  }

  Future<bool> _updateCache(
    int generation,
    Uint8List rgba,
    ui.Image image,
    String id,
    double hotx,
    double hoty,
    int w,
    int h,
  ) async {
    Uint8List? data;
    img2.Image imgOrigin = img2.Image.fromBytes(
        width: w,
        height: h,
        bytes: rgba.buffer,
        bytesOffset: rgba.offsetInBytes,
        order: img2.ChannelOrder.rgba);
    if (isWindows) {
      data = imgOrigin.getBytes(order: img2.ChannelOrder.bgra);
    } else {
      ByteData? imgBytes =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (imgBytes == null) {
        return false;
      }
      data = imgBytes.buffer.asUint8List();
      if (isDesktop &&
          (parent.target?.ffiModel.isPeerLinux == true ||
              parent.target?.ffiModel.isPeerWindows == true)) {
        // PNG decoding supplies straight alpha for Linux/Windows cursor resizing.
        final decoded = img2.decodePng(data);
        if (decoded == null) {
          debugPrint('Unable to decode cursor $id PNG for resizing');
          return false;
        }
        imgOrigin = decoded;
      }
    }
    final cache = CursorData(
      peerId: peerId,
      id: id,
      image: imgOrigin,
      scale: 1.0,
      data: data,
      hotxOrigin: hotx,
      hotyOrigin: hoty,
      width: w,
      height: h,
    );
    if (generation != _generation) {
      return false;
    }
    _cacheMap[id] = cache;
    return true;
  }

  @visibleForTesting
  Iterable<String> get shapeIds => _images.keys;

  @visibleForTesting
  CursorData? cachedShape(String id) => _cacheMap[id];

  final _restoring = <String>{};

  // Tabs in a window share its engine's native cursors, predefined ones included.
  static int _nextKeyScope = 0;
  final int _keyScope = _nextKeyScope++;

  String nativeKey(CursorData cache, double scale) {
    final key = '${_keyScope}_${cache.updateGetKey(scale)}';
    // A native cursor at another raster does not hold the pixels this one is made from.
    if (!_cacheKeys.contains(key)) _nativeIds.remove(cache.id);
    return key;
  }

  // Native cursors stay for the session, one per raster of each shape, and only [clear]
  // deletes them, as before; unlike the painted images they have no LRU, for now. A delete
  // frees nothing on Windows: the engine's `deleteCustomCursor/windows` releases the HCURSOR
  // with `DeleteObject`, which does not take a cursor. Measured on Windows with 500 cursors
  // made by `CreateIconIndirect`, as the engine makes them: `DeleteObject` failed all 500 and
  // left 500 USER objects alive, while `DestroyCursor` or `DestroyIcon` freed all 500. Each
  // delete leaks its handle until the process exits, and making the cursor again for a raster
  // or a shape shown once more leaks another, so an LRU would leak more than keeping them.
  //
  // Fixing the engine is not cheap. x64 runs our fork, rustdesk/engine, on Flutter 3.24; the
  // fix is one more patch to rebuild, publish, and carry across every Flutter upgrade. arm64
  // runs the stock engine of a newer Flutter, which has the same code: fixing it means
  // porting the fork to that version and building and publishing an arm64 engine as well, or
  // an upstream fix and waiting for it to reach stable. Once both engines destroy cursors, an
  // LRU like the painted images' can come back. Content ids keep the count to the shapes the
  // peer really shows, a few dozen to a couple of hundred.

  /// The shape in use keeps its pixels, so a new raster is made from them at once; the others
  /// keep none once their native cursor holds them.
  void registered(CursorData cache, String key) {
    _nativeIds.add(cache.id);
    _awaitingNative.remove(cache.id);
    if (cache.id != _id && identical(_cacheMap[cache.id], cache)) {
      cache.releasePixels();
    }
  }

  // The shapes a native cursor holds, and those keeping their pixels until one does, oldest
  // first: one decoded after the peer moved on must still get a native cursor when shown
  // again, rather than be decoded again every time it comes back.
  final _nativeIds = <String>{};
  final _awaitingNative = <String>{};

  void _switchedAway(CursorData cache) {
    _awaitingNative.remove(cache.id);
    // Mobile only paints the cursor, from its image.
    if (isMobile || _nativeIds.contains(cache.id)) {
      cache.releasePixels();
      return;
    }
    _awaitingNative.add(cache.id);
    while (_awaitingNative.length > kRecentShapes) {
      final oldest = _awaitingNative.first;
      _awaitingNative.remove(oldest);
      if (oldest != _id) _cacheMap[oldest]?.releasePixels();
    }
  }

  /// The peer's shapes used last that keep a painted image, and the most that keep their pixels
  /// waiting for a native cursor; the core rebuilds the others. An animated cursor is a shape per
  /// frame, 18 for the Windows busy cursor and 23 for KDE's, and a cycle longer than this limit
  /// would rebuild every frame.
  static const kRecentShapes = 64;

  /// The native cursor of the shape shown last, shown on while the shape in use is made.
  String? shownKey;

  void shown(CursorData cache, String key) {
    // The forbidden cursor shows only while input is off; it is no stand-in for a shape.
    if (cache.id != kPreForbiddenCursorId) shownKey = key;
  }

  /// Whether the desktop paints the peer's cursor over the remote image.
  @protected
  bool get showsRemoteCursor {
    return parent.target?.showRemoteCursor.value ?? false;
  }

  // Painted images kept: mobile always paints the cursor, a desktop only when it shows the
  // remote cursor, and otherwise the native cursors show the shapes.
  int get _imageLimit => isMobile || showsRemoteCursor ? kRecentShapes : 1;

  // `_images` is in order of use. The image painted is kept, whoever's it is.
  void _evictImages() {
    var excess = _images.length - _imageLimit;
    _images.removeWhere((id, shape) {
      if (excess <= 0 || id == _id || identical(shape.item1, _image)) {
        return false;
      }
      excess--;
      shape.item1.dispose();
      return true;
    });
  }

  /// The core keeps every shape the peer sent, compressed; see `Session::cursor_shapes`.
  @protected
  Future<CursorShape?> fetchCursorShape(String id) {
    final ffi = parent.target;
    if (ffi == null) return Future.value(null);
    return bind.sessionGetCursorShape(sessionId: ffi.sessionId, id: id);
  }

  // The shape the core could not give, not asked for again while it is the one in use. One
  // is enough: only the shape in use is asked for on every frame, and the peer's ids must not
  // accumulate here.
  String? _unavailable;
  // Counts session clears, so that a decode finishing after one keeps nothing.
  int _generation = 0;

  /// Decodes the shape in use again from the core, for a raster its native cursor lacks, for
  /// painting it, or for a window a tab moved to.
  void restorePixels(String id) {
    if (id != _id || _unavailable == id || !_restoring.add(id)) return;
    final generation = _generation;
    () async {
      try {
        // A throw becomes an error the await hands over later, not during the build that may
        // have asked: a failure tells the listeners.
        final shape = await Future.sync(() => fetchCursorShape(id));
        if (generation != _generation) {
          return;
        } else if (shape == null) {
          _markUnavailable(generation, id);
          debugPrint('Cursor $id is not kept by the core');
        } else {
          // Decoded even if the peer moved on: an animation comes back to it.
          await updateCursorData(id, shape.hotx, shape.hoty, shape.width,
              shape.height, shape.colors);
        }
      } catch (e) {
        _markUnavailable(generation, id);
        debugPrint('Failed to fetch cursor $id: $e');
      } finally {
        _restoring.remove(id);
      }
    }();
  }

  void _markUnavailable(int generation, String id) {
    if (generation != _generation || id != _id) return;
    _unavailable = id;
    _updateCurData();
  }

  bool _updateCurData() {
    final previous = _cache;
    final cache = _cacheMap[_id];
    // A shape not decoded yet leaves the one shown before in place until it is; one the core
    // cannot give leaves none, so the default cursor shows, as for a shape never sent.
    if (cache != null || _unavailable == _id) _cache = cache;
    if (previous != null && !identical(previous, _cache)) {
      _switchedAway(previous);
    }
    final tmp = _images.remove(_id);
    if (tmp != null) {
      _images[_id] = tmp;
      _image = tmp.item1;
      _hotx = tmp.item2;
      _hoty = tmp.item3;
    } else if (_unavailable == _id) {
      _image = null;
    }
    _evictImages();
    try {
      // may throw exception, because the listener maybe already dispose
      notifyListeners();
    } catch (e) {
      debugPrint('WARNING: updateCursorId $_id, without notifyListeners(). $e');
    }
    return tmp != null || cache != null;
  }

  updateCursorId(Map<String, dynamic> evt) {
    if (!_updateCurData()) {
      restorePixels(_id);
    }
  }

  /// Update the cursor position.
  updateCursorPosition(Map<String, dynamic> evt, String id) async {
    if (!isConnIn2Secs()) {
      gotMouseControl = false;
      _lastPeerMouse = DateTime.now();
    }
    _x = double.parse(evt['x']);
    _y = double.parse(evt['y']);
    try {
      parent.target!.remoteCursorMoved.value = true;
    } catch (e) {
      //
    }
    notifyListeners();
  }

  updateDisplayOrigin(double x, double y, {updateCursorPos = true}) {
    _displayOriginX = x;
    _displayOriginY = y;
    if (updateCursorPos) {
      _x = x + 1;
      _y = y + 1;
      parent.target?.inputModel.moveMouse(x, y);
    }
    parent.target?.canvasModel.resetOffset();
    notifyListeners();
  }

  updateDisplayOriginWithCursor(
      double x, double y, double xCursor, double yCursor) {
    _displayOriginX = x;
    _displayOriginY = y;
    _x = xCursor;
    _y = yCursor;
    parent.target?.inputModel.moveMouse(x, y);
    notifyListeners();
  }

  clear() {
    _x = -10000;
    _x = -10000;
    _image = null;
    _firstUpdateMouseTime = null;
    gotMouseControl = true;
    disposeImages();

    _clearCache();
    _cache = null;
    _cacheMap.clear();
    _nativeIds.clear();
    _awaitingNative.clear();
    _unavailable = null;
    _generation++;
  }

  _clearCache() {
    final keys = {...cachedKeys};
    for (var k in keys) {
      debugPrint("deleting cursor with key $k");
      deleteCustomCursor(k);
    }
    _cacheKeys.clear();
    shownKey = null;
    resetSystemCursor();
  }

  trySetRemoteWindowCoords() {
    Future.delayed(Duration.zero, () async {
      _windowRect =
          await InputModel.fillRemoteCoordsAndGetCurFrame(_remoteWindowCoords);
    });
  }

  clearRemoteWindowCoords() {
    _windowRect = null;
    _remoteWindowCoords.clear();
  }
}

class QualityMonitorData {
  String? speed;
  String? fps;
  String? delay;
  String? targetBitrate;
  String? codecFormat;
  String? chroma;
}

class QualityMonitorModel with ChangeNotifier {
  WeakReference<FFI> parent;

  QualityMonitorModel(this.parent);
  var _show = false;
  final _data = QualityMonitorData();

  bool get show => _show;
  QualityMonitorData get data => _data;

  checkShowQualityMonitor(SessionID sessionId) async {
    final show = await bind.sessionGetToggleOption(
            sessionId: sessionId, arg: 'show-quality-monitor') ==
        true;
    if (_show != show) {
      _show = show;
      notifyListeners();
    }
  }

  updateQualityStatus(Map<String, dynamic> evt) {
    try {
      if (evt.containsKey('speed') && (evt['speed'] as String).isNotEmpty) {
        _data.speed = evt['speed'];
      }
      if (evt.containsKey('fps') && (evt['fps'] as String).isNotEmpty) {
        final fps = jsonDecode(evt['fps']) as Map<String, dynamic>;
        final pi = parent.target?.ffiModel.pi;
        if (pi != null) {
          final currentDisplay = pi.currentDisplay;
          if (currentDisplay != kAllDisplayValue) {
            final fps2 = fps[currentDisplay.toString()];
            if (fps2 != null) {
              _data.fps = fps2.toString();
            }
          } else if (fps.isNotEmpty) {
            final fpsList = [];
            for (var i = 0; i < pi.displays.length; i++) {
              fpsList.add((fps[i.toString()] ?? 0).toString());
            }
            _data.fps = fpsList.join(' ');
          }
        } else {
          _data.fps = null;
        }
      }
      if (evt.containsKey('delay') && (evt['delay'] as String).isNotEmpty) {
        _data.delay = evt['delay'];
      }
      if (evt.containsKey('target_bitrate') &&
          (evt['target_bitrate'] as String).isNotEmpty) {
        _data.targetBitrate = evt['target_bitrate'];
      }
      if (evt.containsKey('codec_format') &&
          (evt['codec_format'] as String).isNotEmpty) {
        _data.codecFormat = evt['codec_format'];
      }
      if (evt.containsKey('chroma') && (evt['chroma'] as String).isNotEmpty) {
        _data.chroma = evt['chroma'];
      }
      notifyListeners();
    } catch (e) {
      //
    }
  }
}

class RecordingModel with ChangeNotifier {
  WeakReference<FFI> parent;
  RecordingModel(this.parent);
  bool _start = false;
  bool get start => _start;

  toggle() async {
    if (isIOS) return;
    final sessionId = parent.target?.sessionId;
    if (sessionId == null) return;
    final pi = parent.target?.ffiModel.pi;
    if (pi == null) return;
    bool value = !_start;
    if (value) {
      await sessionRefreshVideo(sessionId, pi);
    }
    await bind.sessionRecordScreen(sessionId: sessionId, start: value);
  }

  updateStatus(bool status) {
    _start = status;
    notifyListeners();
  }
}

class ElevationModel with ChangeNotifier {
  WeakReference<FFI> parent;
  ElevationModel(this.parent);
  bool _running = false;
  bool _canElevate = false;
  bool get showRequestMenu => _canElevate && !_running;
  onPeerInfo(PeerInfo pi) {
    _canElevate = pi.platform == kPeerPlatformWindows && pi.sasEnabled == false;
    _running = false;
  }

  onPortableServiceRunning(bool running) => _running = running;
}

const kInvalidResolutionValue = -1;
const kVirtualDisplayResolutionValue = 0;

class Display {
  double x = 0;
  double y = 0;
  int width = 0;
  int height = 0;
  bool cursorEmbedded = false;
  int originalWidth = kInvalidResolutionValue;
  int originalHeight = kInvalidResolutionValue;
  double _scale = 1.0;
  double get scale => _scale > 1.0 ? _scale : 1.0;

  Display() {
    width = (isDesktop || isWebDesktop)
        ? kDesktopDefaultDisplayWidth
        : kMobileDefaultDisplayWidth;
    height = (isDesktop || isWebDesktop)
        ? kDesktopDefaultDisplayHeight
        : kMobileDefaultDisplayHeight;
  }

  @override
  bool operator ==(Object other) =>
      other is Display &&
      other.runtimeType == runtimeType &&
      _innerEqual(other);

  bool _innerEqual(Display other) =>
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.cursorEmbedded == cursorEmbedded;

  bool get isOriginalResolutionSet =>
      originalWidth != kInvalidResolutionValue &&
      originalHeight != kInvalidResolutionValue;
  bool get isVirtualDisplayResolution =>
      originalWidth == kVirtualDisplayResolutionValue &&
      originalHeight == kVirtualDisplayResolutionValue;
  bool get isOriginalResolution =>
      width == (originalWidth * scale).round() &&
      height == (originalHeight * scale).round();
}

class Resolution {
  int width = 0;
  int height = 0;
  Resolution(this.width, this.height);

  @override
  String toString() {
    return 'Resolution($width,$height)';
  }
}

class Features {
  bool privacyMode = false;
}

const kInvalidDisplayIndex = -1;

class PeerInfo with ChangeNotifier {
  String version = '';
  String username = '';
  String hostname = '';
  String platform = '';
  bool sasEnabled = false;
  bool isSupportMultiUiSession = false;
  int currentDisplay = 0;
  int primaryDisplay = kInvalidDisplayIndex;
  RxList<Display> displays = <Display>[].obs;
  Features features = Features();
  List<Resolution> resolutions = [];
  Map<String, dynamic> platformAdditions = {};

  RxInt displaysCount = 0.obs;
  RxBool isSet = false.obs;

  bool get isWayland => platformAdditions[kPlatformAdditionsIsWayland] == true;
  bool get isInstalled =>
      platform != kPeerPlatformWindows ||
      platformAdditions[kPlatformAdditionsIsInstalled] == true;
  List<int> get RustDeskVirtualDisplays => List<int>.from(
      platformAdditions[kPlatformAdditionsRustDeskVirtualDisplays] ?? []);
  int get amyuniVirtualDisplayCount =>
      platformAdditions[kPlatformAdditionsAmyuniVirtualDisplays] ?? 0;

  bool get isSupportMultiDisplay =>
      (isDesktop || isWebDesktop) && isSupportMultiUiSession;
  bool get forceTextureRender => currentDisplay == kAllDisplayValue;

  bool get cursorEmbedded => tryGetDisplay()?.cursorEmbedded ?? false;

  bool get isRustDeskIdd =>
      platformAdditions[kPlatformAdditionsIddImpl] == 'rustdesk_idd';
  bool get isAmyuniIdd =>
      platformAdditions[kPlatformAdditionsIddImpl] == 'amyuni_idd';

  Display? tryGetDisplay({int? display}) {
    if (displays.isEmpty) {
      return null;
    }
    display ??= currentDisplay;
    if (display == kAllDisplayValue) {
      return displays[0];
    } else {
      if (display > 0 && display < displays.length) {
        return displays[display];
      } else {
        return displays[0];
      }
    }
  }

  Display? tryGetDisplayIfNotAllDisplay({int? display}) {
    if (displays.isEmpty) {
      return null;
    }
    display ??= currentDisplay;
    if (display == kAllDisplayValue) {
      return null;
    }
    if (display >= 0 && display < displays.length) {
      return displays[display];
    } else {
      return null;
    }
  }

  List<Display> getCurDisplays() {
    if (currentDisplay == kAllDisplayValue) {
      return displays;
    } else {
      if (currentDisplay >= 0 && currentDisplay < displays.length) {
        return [displays[currentDisplay]];
      } else {
        return [];
      }
    }
  }

  double scaleOfDisplay(int display) {
    if (display >= 0 && display < displays.length) {
      return displays[display].scale;
    }
    return 1.0;
  }

  Rect? getDisplayRect(int display) {
    final d = tryGetDisplayIfNotAllDisplay(display: display);
    if (d == null) return null;
    return Rect.fromLTWH(d.x, d.y, d.width.toDouble(), d.height.toDouble());
  }
}

const canvasKey = 'canvas';

Future<void> setCanvasConfig(
    SessionID sessionId,
    double xCursor,
    double yCursor,
    double xCanvas,
    double yCanvas,
    double scale,
    int currentDisplay) async {
  final p = <String, dynamic>{};
  p['xCursor'] = xCursor;
  p['yCursor'] = yCursor;
  p['xCanvas'] = xCanvas;
  p['yCanvas'] = yCanvas;
  p['scale'] = scale;
  p['currentDisplay'] = currentDisplay;
  await bind.sessionSetFlutterOption(
      sessionId: sessionId, k: canvasKey, v: jsonEncode(p));
}

Future<Map<String, dynamic>?> getCanvasConfig(SessionID sessionId) async {
  if (!isWebDesktop) return null;
  var p =
      await bind.sessionGetFlutterOption(sessionId: sessionId, k: canvasKey);
  if (p == null || p.isEmpty) return null;
  try {
    Map<String, dynamic> m = json.decode(p);
    return m;
  } catch (e) {
    return null;
  }
}

Future<void> initializeCursorAndCanvas(FFI ffi) async {
  var p = await getCanvasConfig(ffi.sessionId);
  int currentDisplay = 0;
  if (p != null) {
    currentDisplay = p['currentDisplay'];
  }
  if (p == null || currentDisplay != ffi.ffiModel.pi.currentDisplay) {
    ffi.cursorModel.updateDisplayOrigin(
        ffi.ffiModel.rect?.left ?? 0, ffi.ffiModel.rect?.top ?? 0);
    return;
  }
  double xCursor = p['xCursor'];
  double yCursor = p['yCursor'];
  double xCanvas = p['xCanvas'];
  double yCanvas = p['yCanvas'];
  double scale = p['scale'];
  ffi.cursorModel.updateDisplayOriginWithCursor(ffi.ffiModel.rect?.left ?? 0,
      ffi.ffiModel.rect?.top ?? 0, xCursor, yCursor);
  ffi.canvasModel.update(xCanvas, yCanvas, scale);
}
