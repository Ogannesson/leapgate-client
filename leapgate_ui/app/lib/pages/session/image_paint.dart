// 上游：flutter/lib/desktop/pages/remote_page.dart@bd9262397（改写：只留 _ViewStyleUpdater、ImagePaint、CursorPaint；_ViewStyleUpdater 改名 ViewStyleUpdater 好让会话页引用；Provider.of 取的 ImageModel、CanvasModel、CursorModel 改成从 ffi 取，外面包一层 ListenableBuilder 代替 Provider 的重建；CursorPaint 多一个 ffi 参数；删了只写不读的 _firstEnterImage（上游只在注释掉的代码里读它）；kScrollbarThickness 取上游 consts.dart:43 的值放在本文件。上游这几个类改了，合并时人工移植到这里）
// The app's lints are stricter than upstream's; the copy keeps upstream's code as it is.
// ignore_for_file: non_constant_identifier_names, prefer_const_constructors_in_immutables, sized_box_for_whitespace, sort_child_properties_last
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/native/custom_cursor.dart';
import 'package:flutter_hbb/utils/image.dart';
import 'package:get/get.dart';

const double kScrollbarThickness = 12.0;

/// Tracks view size and DPR to update CanvasModel.updateViewStyle()
/// and InputModel.updateImageWidgetSize() only when either changes.
/// This avoids scheduling post-frame callbacks on every LayoutBuilder rebuild.
class ViewStyleUpdater extends StatefulWidget {
  final CanvasModel canvasModel;
  final InputModel inputModel;
  final Widget child;

  const ViewStyleUpdater({
    Key? key,
    required this.canvasModel,
    required this.inputModel,
    required this.child,
  }) : super(key: key);

  @override
  State<ViewStyleUpdater> createState() => _ViewStyleUpdaterState();
}

class _ViewStyleUpdaterState extends State<ViewStyleUpdater> {
  Size? _lastSize;
  double? _lastDevicePixelRatio;
  bool _callbackScheduled = false;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        // Guard against infinite constraints (e.g., unconstrained ancestor).
        if (!maxWidth.isFinite || !maxHeight.isFinite) {
          return widget.child;
        }
        final newSize = Size(maxWidth, maxHeight);
        if (_lastSize != newSize || _lastDevicePixelRatio != devicePixelRatio) {
          _lastSize = newSize;
          _lastDevicePixelRatio = devicePixelRatio;
          // Schedule the update for after the current frame to avoid setState during build.
          // Use _callbackScheduled flag to prevent accumulating multiple callbacks
          // when size changes rapidly before any callback executes.
          if (!_callbackScheduled) {
            _callbackScheduled = true;
            SchedulerBinding.instance.addPostFrameCallback((_) {
              _callbackScheduled = false;
              final currentSize = _lastSize;
              if (mounted && currentSize != null) {
                widget.canvasModel.updateViewStyle();
                widget.inputModel.updateImageWidgetSize(currentSize);
              }
            });
          }
        }
        return widget.child;
      },
    );
  }
}

class ImagePaint extends StatefulWidget {
  final FFI ffi;
  final String id;
  final RxBool zoomCursor;
  final RxBool cursorOverImage;
  final RxBool keyboardEnabled;
  final RxBool remoteCursorMoved;
  final Widget Function(Widget)? listenerBuilder;

  ImagePaint(
      {Key? key,
      required this.ffi,
      required this.id,
      required this.zoomCursor,
      required this.cursorOverImage,
      required this.keyboardEnabled,
      required this.remoteCursorMoved,
      this.listenerBuilder})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _ImagePaintState();
}

class _ImagePaintState extends State<ImagePaint> {
  bool _lastRemoteCursorMoved = false;
  final _cursorDisplayScale = 1.0.obs;

  String get id => widget.id;
  RxBool get zoomCursor => widget.zoomCursor;
  RxBool get cursorOverImage => widget.cursorOverImage;
  RxBool get keyboardEnabled => widget.keyboardEnabled;
  RxBool get remoteCursorMoved => widget.remoteCursorMoved;
  Widget Function(Widget)? get listenerBuilder => widget.listenerBuilder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: Listenable.merge([
          widget.ffi.imageModel,
          widget.ffi.canvasModel,
          widget.ffi.cursorModel
        ]),
        builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final m = widget.ffi.imageModel;
    var c = widget.ffi.canvasModel;
    final s = c.scale;
    // Read the live DPR while the canvas's post-frame update is pending.
    final dpr = MediaQuery.devicePixelRatioOf(context);

    bool isViewOriginal() => c.viewStyle.style == kRemoteViewStyleOriginal;

    mouseRegion({child}) => Obx(() {
          double getCursorScale() {
            var c = widget.ffi.canvasModel;
            if (isDesktop) {
              return _getDesktopCursorScale(c, dpr);
            } else {
              return zoomCursor.value || isViewOriginal() ? s : 1.0;
            }
          }

          return MouseRegion(
              cursor: cursorOverImage.isTrue
                  ? c.cursorEmbedded
                      ? SystemMouseCursors.none
                      // Hide cursor when relative mouse mode is active
                      : widget.ffi.inputModel.relativeMouseMode.value
                          ? SystemMouseCursors.none
                          : keyboardEnabled.isTrue
                              ? (() {
                                  if (remoteCursorMoved.isTrue) {
                                    _lastRemoteCursorMoved = true;
                                    return SystemMouseCursors.none;
                                  } else {
                                    if (_lastRemoteCursorMoved) {
                                      _lastRemoteCursorMoved = false;
                                    }
                                    return _buildCustomCursor(
                                        context, getCursorScale());
                                  }
                                }())
                              : _buildDisabledCursor(context, getCursorScale())
                  : MouseCursor.defer,
              onHover: (evt) {},
              child: child);
        });
    if (c.imageOverflow.isTrue && c.scrollStyle != ScrollStyle.scrollauto) {
      final paintWidth = c.getDisplayWidth() * s;
      final paintHeight = c.getDisplayHeight() * s;
      final paintSize = Size(paintWidth, paintHeight);
      final paintWidget =
          m.useTextureRender || widget.ffi.ffiModel.pi.forceTextureRender
              ? _BuildPaintTextureRender(
                  c, s, Offset.zero, paintSize, isViewOriginal())
              : _buildScrollbarNonTextureRender(m, paintSize, s);
      return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            c.updateScrollPercent();
            return false;
          },
          child: mouseRegion(
            child: Obx(() => _buildCrossScrollbarFromLayout(
                  context,
                  _buildListener(paintWidget),
                  c.size,
                  paintSize,
                  c.scrollHorizontal,
                  c.scrollVertical,
                )),
          ));
    } else {
      if (c.size.width > 0 && c.size.height > 0) {
        final paintWidget =
            m.useTextureRender || widget.ffi.ffiModel.pi.forceTextureRender
                ? _BuildPaintTextureRender(
                    c,
                    s,
                    Offset(
                      isLinux ? c.x.toInt().toDouble() : c.x,
                      isLinux ? c.y.toInt().toDouble() : c.y,
                    ),
                    c.size,
                    isViewOriginal())
                : _buildScrollAutoNonTextureRender(m, c, s);
        return mouseRegion(child: _buildListener(paintWidget));
      } else {
        return Container();
      }
    }
  }

  /// Matches desktop cursors to the rendered image and native pixel units.
  ///
  /// Windows cursor pixels are physical; NSCursor/GdkCursor use logical pixels.
  /// Unzoomed Adaptive/Custom views preserve macOS cursors' point dimensions.
  double _getDesktopCursorScale(CanvasModel c, double dpr) {
    final peer = widget.ffi.ffiModel;
    if (!zoomCursor.value &&
        peer.pi.platform == kPeerPlatformMacOS &&
        (c.viewStyle.style == kRemoteViewStyleAdaptive ||
            c.viewStyle.style == kRemoteViewStyleCustom)) {
      return isWindows ? dpr : 1.0;
    }
    if (peer.isPeerLinux && peer.pi.currentDisplay == kAllDisplayValue) {
      if (!zoomCursor.value || c.viewStyle.style == kRemoteViewStyleOriginal) {
        // Remove the host output's density without applying canvas zoom.
        final scale = 1.0 / _cursorDisplayScale.value;
        return isWindows ? scale : scale / dpr;
      }
      final scale = c.scale / _cursorDisplayScale.value;
      return isWindows ? scale * dpr : scale;
    }
    if (!zoomCursor.value || c.viewStyle.style == kRemoteViewStyleOriginal) {
      // Original and unzoomed views do not apply canvas zoom.
      final scale = _getCursorScaleForDisplay(1.0);
      return isWindows ? scale : scale / dpr;
    }
    final scale = _getCursorScaleForDisplay(c.scale);
    return isWindows ? scale * dpr : scale;
  }

  double _getCursorScaleForDisplay(double scale) {
    final peer = widget.ffi.ffiModel;
    // All Displays can mix densities; no single display scale applies.
    if (peer.pi.currentDisplay == kAllDisplayValue) return scale;
    final displays = peer.pi.getCurDisplays();
    if (displays.isEmpty) return scale;
    if (peer.pi.platform == kPeerPlatformMacOS) {
      // macOS sends NSImage.size in points (src/platform/macos.rs:640,682),
      // while HiDPI screen frames use backing pixels (libs/scrap/src/quartz/display.rs:37).
      return scale * displays.first.scale;
    }
    if (!peer.isPeerLinux) return scale;
    // Match rendering when a Wayland host
    // with multiple outputs reports a display scale > 1.
    // A single-output host keeps scale at 1.0 to preserve physical uinput
    // coordinates, even with OS scaling enabled. This counts host outputs,
    // not the selected displays.length.
    // See src/server/display_service.rs:650 (update_sync_displays) and
    // src/server/drm_capturer.rs:1523 (DRM's matching convention).
    return scale / displays.first.scale;
  }

  Widget _buildScrollbarNonTextureRender(
      ImageModel m, Size imageSize, double s) {
    double sizeScale = s;
    if (widget.ffi.ffiModel.isPeerLinux) {
      final displays = widget.ffi.ffiModel.pi.getCurDisplays();
      if (displays.isNotEmpty) {
        sizeScale = s / displays[0].scale;
      }
    }
    return CustomPaint(
      size: imageSize,
      painter: ImagePainter(image: m.image, x: 0, y: 0, scale: sizeScale),
    );
  }

  Widget _buildScrollAutoNonTextureRender(
      ImageModel m, CanvasModel c, double s) {
    double sizeScale = s;
    if (widget.ffi.ffiModel.isPeerLinux) {
      final displays = widget.ffi.ffiModel.pi.getCurDisplays();
      if (displays.isNotEmpty) {
        sizeScale = s / displays[0].scale;
      }
    }
    return CustomPaint(
      size: Size(c.size.width, c.size.height),
      painter: ImagePainter(
          image: m.image,
          x: c.x / sizeScale,
          y: c.y / sizeScale,
          scale: sizeScale),
    );
  }

  Widget _BuildPaintTextureRender(
      CanvasModel c, double s, Offset offset, Size size, bool isViewOriginal) {
    final ffiModel = c.parent.target!.ffiModel;
    final displays = ffiModel.pi.getCurDisplays();
    final children = <Widget>[];
    final rect = ffiModel.rect;
    if (rect == null) {
      return Container();
    }
    final isPeerLinux = ffiModel.isPeerLinux;
    final curDisplay = ffiModel.pi.currentDisplay;
    for (var i = 0; i < displays.length; i++) {
      final textureId = widget.ffi.textureModel
          .getTextureId(curDisplay == kAllDisplayValue ? i : curDisplay);
      if (true) {
        // both "textureId.value != -1" and "true" seems ok
        final sizeScale = isPeerLinux ? s / displays[i].scale : s;
        children.add(Positioned(
          left: (displays[i].x - rect.left) * s + offset.dx,
          top: (displays[i].y - rect.top) * s + offset.dy,
          width: displays[i].width * sizeScale,
          height: displays[i].height * sizeScale,
          child: _trackCursorDisplay(
            Obx(() => Texture(
                  textureId: textureId.value,
                  filterQuality:
                      isViewOriginal ? FilterQuality.none : FilterQuality.low,
                )),
            displays[i],
          ),
        ));
      }
    }
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(children: children),
    );
  }

  Widget _trackCursorDisplay(Widget child, Display display) {
    final peer = widget.ffi.ffiModel;
    if (!isDesktop ||
        !peer.isPeerLinux ||
        peer.pi.currentDisplay != kAllDisplayValue) {
      return child;
    }
    return MouseRegion(
      onEnter: (_) => _cursorDisplayScale.value = display.scale,
      onHover: (_) => _cursorDisplayScale.value = display.scale,
      child: child,
    );
  }

  MouseCursor _buildCustomCursor(BuildContext context, double scale) {
    final cursor = widget.ffi.cursorModel;
    final cache = cursor.cache ?? preDefaultCursor.cache;
    return buildCursorOfCache(cursor, scale, cache);
  }

  MouseCursor _buildDisabledCursor(BuildContext context, double scale) {
    final cursor = widget.ffi.cursorModel;
    final cache = preForbiddenCursor.cache;
    return buildCursorOfCache(cursor, scale, cache);
  }

  Widget _buildCrossScrollbarFromLayout(
    BuildContext context,
    Widget child,
    Size layoutSize,
    Size size,
    ScrollController horizontal,
    ScrollController vertical,
  ) {
    var widget = child;
    if (layoutSize.width < size.width) {
      widget = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: horizontal,
          scrollDirection: Axis.horizontal,
          physics: cursorOverImage.isTrue
              ? const NeverScrollableScrollPhysics()
              : null,
          child: widget,
        ),
      );
    } else {
      widget = Row(
        children: [
          Container(
            width: ((layoutSize.width - size.width) ~/ 2).toDouble(),
          ),
          widget,
        ],
      );
    }
    if (layoutSize.height < size.height) {
      widget = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: vertical,
          physics: cursorOverImage.isTrue
              ? const NeverScrollableScrollPhysics()
              : null,
          child: widget,
        ),
      );
    } else {
      widget = Column(
        children: [
          Container(
            height: ((layoutSize.height - size.height) ~/ 2).toDouble(),
          ),
          widget,
        ],
      );
    }
    if (layoutSize.width < size.width) {
      widget = RawScrollbar(
        thickness: kScrollbarThickness,
        thumbColor: Colors.grey,
        controller: horizontal,
        thumbVisibility: false,
        trackVisibility: false,
        notificationPredicate: layoutSize.height < size.height
            ? (notification) => notification.depth == 1
            : defaultScrollNotificationPredicate,
        child: widget,
      );
    }
    if (layoutSize.height < size.height) {
      widget = RawScrollbar(
        thickness: kScrollbarThickness,
        thumbColor: Colors.grey,
        controller: vertical,
        thumbVisibility: false,
        trackVisibility: false,
        child: widget,
      );
    }

    return Container(
      child: widget,
      width: layoutSize.width,
      height: layoutSize.height,
    );
  }

  Widget _buildListener(Widget child) {
    if (listenerBuilder != null) {
      return listenerBuilder!(child);
    } else {
      return child;
    }
  }
}

class CursorPaint extends StatelessWidget {
  final FFI ffi;
  final String id;
  final RxBool zoomCursor;

  const CursorPaint({
    Key? key,
    required this.ffi,
    required this.id,
    required this.zoomCursor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: Listenable.merge([ffi.cursorModel, ffi.canvasModel]),
        builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final m = ffi.cursorModel;
    final c = ffi.canvasModel;
    double hotx = m.hotx;
    double hoty = m.hoty;
    if (m.image == null) {
      if (preDefaultCursor.image != null) {
        hotx = preDefaultCursor.image!.width / 2;
        hoty = preDefaultCursor.image!.height / 2;
      }
    }

    double cx = c.x;
    double cy = c.y;
    if (c.viewStyle.style == kRemoteViewStyleOriginal &&
        c.scrollStyle == ScrollStyle.scrollbar) {
      final rect = c.parent.target!.ffiModel.rect;
      if (rect == null) {
        // unreachable!
        debugPrint('unreachable! The displays rect is null.');
        return Container();
      }
      if (cx < 0) {
        final imageWidth = rect.width * c.scale;
        cx = -imageWidth * c.scrollX;
      }
      if (cy < 0) {
        final imageHeight = rect.height * c.scale;
        cy = -imageHeight * c.scrollY;
      }
    }

    double x = (m.x - hotx) * c.scale + cx;
    double y = (m.y - hoty) * c.scale + cy;
    double scale = 1.0;
    final isViewOriginal = c.viewStyle.style == kRemoteViewStyleOriginal;
    if (zoomCursor.value || isViewOriginal) {
      x = m.x - hotx + cx / c.scale;
      y = m.y - hoty + cy / c.scale;
      scale = c.scale;
    }

    return CustomPaint(
      painter: ImagePainter(
        image: m.image ?? preDefaultCursor.image,
        x: x,
        y: y,
        scale: scale,
      ),
    );
  }
}
