import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

part 'lg_icons.g.dart';

/// One drawable element of an icon, in viewBox units.
class LgIconPart {
  const LgIconPart(
    this.path, {
    this.fill = false,
    this.stroke = 0,
    this.scaleStroke = true,
    this.cap = StrokeCap.butt,
    this.join = StrokeJoin.miter,
    this.dash,
  });

  final Path path;
  final bool fill;

  /// Stroke width; 0 means no stroke.
  final double stroke;

  /// False for the default line of the 24-grid icons, which is 2 logical
  /// pixels at every size (A-基础.html:101-103); true for widths written on
  /// the element, which are viewBox units and scale with the icon.
  final bool scaleStroke;
  final StrokeCap cap;
  final StrokeJoin join;

  /// Dash pattern in viewBox units.
  final List<double>? dash;
}

class LgIconData {
  LgIconData(this.width, this.height, this.parts);

  final double width;
  final double height;
  final List<LgIconPart> parts;

  static final _cache = <LgIcons, LgIconData>{};

  static LgIconData of(LgIcons icon) =>
      _cache.putIfAbsent(icon, () => _buildIcon(icon));
}

Float64List _rotation(double degrees, double cx, double cy) {
  final a = degrees * math.pi / 180;
  final c = math.cos(a), s = math.sin(a);
  // Column-major 4x4: translate(cx, cy) * rotate(a) * translate(-cx, -cy).
  return Float64List.fromList([
    c, s, 0, 0, //
    -s, c, 0, 0, //
    0, 0, 1, 0, //
    cx - c * cx + s * cy, cy - s * cx - c * cy, 0, 1,
  ]);
}

/// An icon from the mockups, drawn with paths (03 §4.2).
///
/// [size] is the height; the width follows the icon's aspect ratio (the
/// detail-mode route markers are 36×12). The colour defaults to the ambient
/// text colour, like `currentColor` in the mockups. Decorative: excluded from
/// semantics; label the control that contains it instead.
class LgIcon extends StatelessWidget {
  const LgIcon(this.icon, {super.key, this.size = 20, this.color});

  final LgIcons icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final data = LgIconData.of(icon);
    final color =
        this.color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(size * data.width / data.height, size),
        painter: _LgIconPainter(data, color),
      ),
    );
  }
}

class _LgIconPainter extends CustomPainter {
  _LgIconPainter(this.data, this.color);

  final LgIconData data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / data.height;
    final m = Matrix4.diagonal3Values(s, s, 1).storage;
    for (final part in data.parts) {
      final path = part.path.transform(m);
      if (part.fill) {
        canvas.drawPath(path, Paint()..color = color);
      }
      if (part.stroke > 0) {
        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = part.scaleStroke ? part.stroke * s : part.stroke
          ..strokeCap = part.cap
          ..strokeJoin = part.join;
        final dash = part.dash;
        canvas.drawPath(
          dash == null ? path : _dashed(path, [for (final d in dash) d * s]),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LgIconPainter old) =>
      old.data != data || old.color != color;
}

Path _dashed(Path source, List<double> pattern) {
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var i = 0;
    while (distance < metric.length) {
      final len = pattern[i % pattern.length];
      if (i.isEven) {
        out.addPath(
          metric.extractPath(distance, math.min(distance + len, metric.length)),
          Offset.zero,
        );
      }
      distance += len;
      i++;
    }
  }
  return out;
}
