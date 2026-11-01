// A slider (`.sl` in A-基础.html): a 4 px track with the part up to the value in
// the accent colour and a 20 px knob with a 3 px ring in the ground colour.
// Dragging, clicking the track and the keyboard (arrows, Page keys, Home, End)
// all work; a screen reader gets the value and the increase / decrease actions.
// Used inside menus (`LgMenuSliderItem`) and wherever a number is picked from a
// range.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';

const double _knob = 20;
const double _ring = 3;

class LgSlider extends StatefulWidget {
  const LgSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.step,
    this.semanticLabel,
    this.format,
    this.focusNode,
    this.onChangeEnd,
    this.verticalArrows = true,
  }) : assert(max > min);

  final double value;

  /// Null disables the slider.
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;

  /// Values snap to `min + n * step`; null is continuous. Arrow keys move by
  /// one step (a hundredth of the range when continuous).
  final double? step;

  /// Accessible name ("缩放").
  final String? semanticLabel;

  /// Writes a value as the screen reader should say it ("100%"); defaults to
  /// the number. It also tells what the value would become one step up or down.
  final String Function(double value)? format;
  final FocusNode? focusNode;

  /// Called once when a drag or click is over, with the last value.
  final ValueChanged<double>? onChangeEnd;

  /// Whether Up and Down also move the knob. Inside a menu they are left to
  /// the menu, which moves between its rows with them.
  final bool verticalArrows;

  @override
  State<LgSlider> createState() => _LgSliderState();
}

class _LgSliderState extends State<LgSlider> {
  bool _focused = false;
  bool _hovered = false;
  bool _dragging = false;
  double? _last;

  double get _unit => widget.step ?? (widget.max - widget.min) / 100;

  double _snap(double v) {
    var x = v.clamp(widget.min, widget.max);
    final step = widget.step;
    if (step != null && step > 0) {
      x = widget.min + ((x - widget.min) / step).round() * step;
      x = x.clamp(widget.min, widget.max);
    }
    return x;
  }

  String _say(double v) =>
      widget.format?.call(v) ?? v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);

  void _set(double v) {
    final x = _snap(v);
    if (x == widget.value) return;
    _last = x;
    widget.onChanged?.call(x);
  }

  // A screen reader's "increase" and "decrease" are one finished change, like a
  // key press.
  void _step(int direction) {
    final next = widget.value + direction * _unit;
    _set(next);
    widget.onChangeEnd?.call(_snap(next));
  }

  void _fromDx(double dx, double width) {
    final span = width - _knob;
    final f = span <= 0 ? 0.0 : ((dx - _knob / 2) / span).clamp(0.0, 1.0);
    _set(widget.min + f * (widget.max - widget.min));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.onChanged == null || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final big = _unit * 10;
    final up = widget.verticalArrows && key == LogicalKeyboardKey.arrowUp;
    final down = widget.verticalArrows && key == LogicalKeyboardKey.arrowDown;
    final double? next = key == LogicalKeyboardKey.arrowRight || up
        ? widget.value + _unit
        : key == LogicalKeyboardKey.arrowLeft || down
        ? widget.value - _unit
        : key == LogicalKeyboardKey.pageUp
        ? widget.value + big
        : key == LogicalKeyboardKey.pageDown
        ? widget.value - big
        : key == LogicalKeyboardKey.home
        ? widget.min
        : key == LogicalKeyboardKey.end
        ? widget.max
        : null;
    if (next == null) return KeyEventResult.ignored;
    _set(next);
    widget.onChangeEnd?.call(_snap(next));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final enabled = widget.onChanged != null;
    final forced = LgStateOverride.of(context);
    final focused = enabled &&
        (_focused || forced.contains(WidgetState.focused));
    final hot = enabled && (_hovered || forced.contains(WidgetState.hovered));
    final fraction =
        ((widget.value - widget.min) / (widget.max - widget.min)).clamp(
          0.0,
          1.0,
        );
    return Semantics(
      slider: true,
      enabled: enabled,
      label: widget.semanticLabel,
      value: _say(widget.value),
      increasedValue: _say(_snap(widget.value + _unit)),
      decreasedValue: _say(_snap(widget.value - _unit)),
      onIncrease: enabled ? () => _step(1) : null,
      onDecrease: enabled ? () => _step(-1) : null,
      child: Focus(
        focusNode: widget.focusNode,
        canRequestFocus: enabled,
        onFocusChange: (v) => setState(() => _focused = v),
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: enabled
                    ? (d) {
                        // The value may have been changed from outside since
                        // the last press: start from what is shown.
                        _last = widget.value;
                        _fromDx(d.localPosition.dx, width);
                        widget.onChangeEnd?.call(_last ?? widget.value);
                      }
                    : null,
                onHorizontalDragStart: enabled
                    ? (d) {
                        _last = widget.value;
                        setState(() => _dragging = true);
                        _fromDx(d.localPosition.dx, width);
                      }
                    : null,
                onHorizontalDragUpdate: enabled
                    ? (d) => _fromDx(d.localPosition.dx, width)
                    : null,
                onHorizontalDragEnd: enabled
                    ? (_) {
                        setState(() => _dragging = false);
                        widget.onChangeEnd?.call(_last ?? widget.value);
                      }
                    : null,
                child: Opacity(
                  opacity: enabled ? 1 : .6,
                  child: SizedBox(
                    height: _knob + 2 * _ring,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _SliderPainter(
                        fraction: fraction,
                        track: c.track,
                        fill: c.accent,
                        ring: c.float,
                        focusRing: focused ? c.accent : null,
                        halo: (hot || _dragging) ? c.hover : null,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter({
    required this.fraction,
    required this.track,
    required this.fill,
    required this.ring,
    required this.focusRing,
    required this.halo,
  });

  final double fraction;
  final Color track;
  final Color fill;
  final Color ring;
  final Color? focusRing;
  final Color? halo;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const left = _knob / 2;
    final right = math.max(left, size.width - _knob / 2);
    final x = left + (right - left) * fraction;
    canvas.drawRRect(
      RRect.fromLTRBR(0, cy - 2, size.width, cy + 2, const Radius.circular(2)),
      Paint()..color = track,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(0, cy - 2, x, cy + 2, const Radius.circular(2)),
      Paint()..color = fill,
    );
    if (halo != null) {
      canvas.drawCircle(
        Offset(x, cy),
        _knob / 2 + _ring + 4,
        Paint()..color = halo!,
      );
    }
    canvas.drawCircle(Offset(x, cy), _knob / 2 + _ring, Paint()..color = ring);
    canvas.drawCircle(Offset(x, cy), _knob / 2, Paint()..color = fill);
    if (focusRing != null) {
      canvas.drawCircle(
        Offset(x, cy),
        _knob / 2 + _ring + 1,
        Paint()
          ..color = focusRing!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.fraction != fraction ||
      old.track != track ||
      old.fill != fill ||
      old.ring != ring ||
      old.focusRing != focusRing ||
      old.halo != halo;
}
