// The two controls that pick a colour by hand (`.tcwheel`, `.tcmk` in A-P1.html,
// 02 §3.6): a wheel with the hue around it and the saturation from the middle
// out, and a bar for the lightness. Both are drawn here, no package. The
// keyboard works on both (arrows), and each is one node for a screen reader with
// its value.
//
// Only drawing and picking: the colour itself is the caller's (HSV numbers
// in, new numbers out).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';

/// The ring of the thumb (`.tcmk`): the colour in a disc, a 3 px rim of the
/// floating ground and a thin line in the text colour around it.
void _paintThumb(Canvas canvas, Offset at, Color fill, LgColors c) {
  canvas.drawCircle(at, 11, Paint()..color = c.float);
  canvas.drawCircle(at, 8, Paint()..color = fill);
  canvas.drawCircle(
    at,
    11.75,
    Paint()
      ..color = c.text
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
}

/// A disc of colours: the angle from the top is the hue, the distance from the
/// middle is the saturation, [value] darkens it all (the lightness bar's job).
class LgColorWheel extends StatefulWidget {
  const LgColorWheel({
    super.key,
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.semanticValue,
    this.enabled = true,
    this.size = 148,
  });

  /// 0 to 360, red at the top and clockwise from there.
  final double hue;

  /// 0 in the middle, 1 at the edge.
  final double saturation;

  /// 1 is full colour, 0 black.
  final double value;

  /// A pick with the pointer or the arrow keys: the new hue and saturation.
  final void Function(double hue, double saturation) onChanged;

  /// "色轮".
  final String semanticLabel;

  /// What a screen reader says after the name: the colour as `#RRGGBB`.
  final String? semanticValue;
  final bool enabled;
  final double size;

  @override
  State<LgColorWheel> createState() => _LgColorWheelState();
}

class _LgColorWheelState extends State<LgColorWheel> {
  final _node = FocusNode(debugLabel: 'colour wheel');

  // The keyboard works on the wheel after a click on it too, but the ring that
  // shows it has the keyboard waits for the first key.
  bool _focused = false;
  bool _byPointer = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _press(Offset local) {
    _byPointer = true;
    _node.requestFocus();
    _pick(local);
  }

  void _pick(Offset local) {
    final r = widget.size / 2;
    final d = local - Offset(r, r);
    final dist = d.distance;
    final sat = (dist / r).clamp(0.0, 1.0);
    // In the very middle the angle means nothing: keep the hue.
    final hue = dist < 1
        ? widget.hue
        : (math.atan2(d.dy, d.dx) * 180 / math.pi + 90 + 360) % 360;
    widget.onChanged(hue, sat);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !widget.enabled) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final big = HardwareKeyboard.instance.isShiftPressed;
    final h = widget.hue, s = widget.saturation;
    _byPointer = false;
    if (k == LogicalKeyboardKey.arrowLeft) {
      widget.onChanged((h - (big ? 15 : 3) + 360) % 360, s);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      widget.onChanged((h + (big ? 15 : 3)) % 360, s);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      widget.onChanged(h, (s + (big ? .1 : .02)).clamp(0.0, 1.0));
    } else if (k == LogicalKeyboardKey.arrowDown) {
      widget.onChanged(h, (s - (big ? .1 : .02)).clamp(0.0, 1.0));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    final w = widget;
    final forced = LgStateOverride.of(context).contains(WidgetState.focused);
    return Semantics(
      label: w.semanticLabel,
      value: w.semanticValue,
      enabled: w.enabled,
      focusable: w.enabled,
      focused: _focused,
      child: ExcludeSemantics(
        child: Focus(
          focusNode: _node,
          canRequestFocus: w.enabled,
          onKeyEvent: _key,
          onFocusChange: (v) => setState(() {
            _focused = v;
            if (!v) _byPointer = false;
          }),
          child: LgFocusRing(
            show: (_focused && !_byPointer) || (w.enabled && forced),
            radius: BorderRadius.circular(w.size / 2),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: w.enabled ? (d) => _press(d.localPosition) : null,
              onPanUpdate: w.enabled ? (d) => _pick(d.localPosition) : null,
              child: Opacity(
                opacity: w.enabled ? 1 : .6,
                child: CustomPaint(
                  size: Size.square(w.size),
                  painter: _WheelPainter(
                    hue: w.hue,
                    saturation: w.saturation,
                    value: w.value,
                    colors: c,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.colors,
  });

  final double hue;
  final double saturation;
  final double value;
  final LgColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: r);
    // `conic-gradient(red, yellow, green, cyan, blue, magenta, red)` from the
    // top, then white fading out from the middle, then the darkening.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = SweepGradient(
          transform: const GradientRotation(-math.pi / 2),
          colors: [
            for (var i = 0; i <= 6; i++)
              HSVColor.fromAHSV(1, i * 60.0 % 360, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    if (value < 1) {
      canvas.drawCircle(
        center,
        r,
        Paint()..color = Colors.black.withValues(alpha: 1 - value),
      );
    }
    canvas.drawCircle(
      center,
      r - .5,
      Paint()
        ..color = colors.borderStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final a = (hue - 90) * math.pi / 180;
    final at = center + Offset(math.cos(a), math.sin(a)) * (saturation * r);
    _paintThumb(
      canvas,
      at,
      HSVColor.fromAHSV(1, hue, saturation, value).toColor(),
      colors,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.hue != hue ||
      old.saturation != saturation ||
      old.value != value ||
      old.colors != colors;
}

/// The lightness bar under the wheel: from black to the full colour of the
/// current hue and saturation, with a thumb at the chosen place.
class LgValueBar extends StatefulWidget {
  const LgValueBar({
    super.key,
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.enabled = true,
    this.height = 24,
  });

  final double hue;
  final double saturation;

  /// 0 to 1.
  final double value;
  final ValueChanged<double> onChanged;

  /// "明度"; the percentage follows it.
  final String semanticLabel;
  final bool enabled;
  final double height;

  @override
  State<LgValueBar> createState() => _LgValueBarState();
}

class _LgValueBarState extends State<LgValueBar> {
  final _node = FocusNode(debugLabel: 'lightness bar');
  bool _focused = false;
  bool _byPointer = false;

  // The thumb's centre stays 11 px from either end, so it is never cut.
  static const _inset = 11.0;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _press(Offset local, double width) {
    _byPointer = true;
    _node.requestFocus();
    _pick(local, width);
  }

  void _pick(Offset local, double width) {
    widget.onChanged(
      ((local.dx - _inset) / (width - 2 * _inset)).clamp(0.0, 1.0),
    );
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !widget.enabled) return KeyEventResult.ignored;
    final k = event.logicalKey;
    final step = HardwareKeyboard.instance.isShiftPressed ? .1 : .02;
    final v = widget.value;
    _byPointer = false;
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowDown) {
      widget.onChanged((v - step).clamp(0.0, 1.0));
    } else if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.arrowUp) {
      widget.onChanged((v + step).clamp(0.0, 1.0));
    } else if (k == LogicalKeyboardKey.home) {
      widget.onChanged(0);
    } else if (k == LogicalKeyboardKey.end) {
      widget.onChanged(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    final w = widget;
    final forced = LgStateOverride.of(context).contains(WidgetState.focused);
    final radius = BorderRadius.circular(w.height / 2);
    final percent = '${(w.value * 100).round()}%';
    return Semantics(
      label: w.semanticLabel,
      value: percent,
      slider: true,
      enabled: w.enabled,
      focusable: w.enabled,
      focused: _focused,
      increasedValue: '${((w.value + .05).clamp(0.0, 1.0) * 100).round()}%',
      decreasedValue: '${((w.value - .05).clamp(0.0, 1.0) * 100).round()}%',
      onIncrease: w.enabled
          ? () => w.onChanged((w.value + .05).clamp(0.0, 1.0))
          : null,
      onDecrease: w.enabled
          ? () => w.onChanged((w.value - .05).clamp(0.0, 1.0))
          : null,
      child: ExcludeSemantics(
        child: Focus(
          focusNode: _node,
          canRequestFocus: w.enabled,
          onKeyEvent: _key,
          onFocusChange: (v) => setState(() {
            _focused = v;
            if (!v) _byPointer = false;
          }),
          child: LgFocusRing(
            show: (_focused && !_byPointer) || (w.enabled && forced),
            radius: radius,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: w.enabled
                      ? (d) => _press(d.localPosition, width)
                      : null,
                  onPanUpdate: w.enabled
                      ? (d) => _pick(d.localPosition, width)
                      : null,
                  child: Opacity(
                    opacity: w.enabled ? 1 : .6,
                    child: CustomPaint(
                      size: Size(width, w.height),
                      painter: _BarPainter(
                        hue: w.hue,
                        saturation: w.saturation,
                        value: w.value,
                        colors: c,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.colors,
  });

  final double hue;
  final double saturation;
  final double value;
  final LgColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF000000),
            HSVColor.fromAHSV(1, hue, saturation, 1).toColor(),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      rrect.deflate(.5),
      Paint()
        ..color = colors.borderStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final x = _LgValueBarState._inset + value * (size.width - 22);
    _paintThumb(
      canvas,
      Offset(x, size.height / 2),
      HSVColor.fromAHSV(1, hue, saturation, value).toColor(),
      colors,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.hue != hue ||
      old.saturation != saturation ||
      old.value != value ||
      old.colors != colors;
}
