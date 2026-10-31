// The details of the connection method (01 §4.2 second level; `d-conn*` in
// A-P2.html): opened from the mark in the toolbar. How the connection runs
// (route, relay, transport, encryption, fingerprint), the figures of the
// picture, the delay as a table with its line chart, and the switch that shows
// the quality figures on the picture.
//
// It only draws: every text and number comes from the caller, formatted and
// localised, and the caller says which groups there are. The chart is
// [LgSparkline], which can be used alone.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_selection.dart';
import 'lg_status.dart';

/// How a line is drawn. A colour alone never tells two lines apart (01 §7.1):
/// the second one is also a different weight, the third dashed.
enum LgLineStyle {
  /// The whole connection, end to end: text colour, 3 px.
  primary,

  /// The first part: accent colour, 2 px.
  accent,

  /// The second part: relay colour, dashed.
  relay,
}

Paint _linePaint(LgColors c, LgLineStyle style) {
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  switch (style) {
    case LgLineStyle.primary:
      paint
        ..color = c.text
        ..strokeWidth = 3;
    case LgLineStyle.accent:
      paint
        ..color = c.accent
        ..strokeWidth = 2;
    case LgLineStyle.relay:
      paint
        ..color = c.relay
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.butt;
  }
  return paint;
}

void _drawLine(Canvas canvas, Path path, Paint paint, LgLineStyle style) {
  if (style != LgLineStyle.relay) {
    canvas.drawPath(path, paint);
    return;
  }
  for (final metric in path.computeMetrics()) {
    var d = 0.0;
    while (d < metric.length) {
      canvas.drawPath(metric.extractPath(d, math.min(d + 6, metric.length)), paint);
      d += 10;
    }
  }
}

/// One line of a chart: the values left to right, evenly spaced; a null is a
/// gap (nothing measured at that moment).
class LgSparkSeries {
  const LgSparkSeries(this.values, this.style);

  final List<double?> values;
  final LgLineStyle style;
}

/// A line chart of the last minute (`.lch`): grid lines at 0, half and the top
/// of the scale with their numbers on the left, the time marks under it and a
/// dot at the end of the first line. The scale rounds up to 10, 20, 50, 100 …
/// [unit] ("ms") follows the numbers; [timeLabels] are the marks under the
/// chart, left to right (as many as given, spread evenly).
class LgSparkline extends StatelessWidget {
  const LgSparkline({
    super.key,
    required this.series,
    required this.unit,
    required this.timeLabels,
    required this.semanticLabel,
    this.height = 132,
  });

  final List<LgSparkSeries> series;
  final String unit;
  final List<String> timeLabels;

  /// What the chart says in words ("近 60 秒端到端延迟，最近 12 ms").
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _SparklinePainter(
              series: series,
              colors: c,
              unit: unit,
              timeLabels: timeLabels,
              style: t.textS.copyWith(color: c.text2),
            ),
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.series,
    required this.colors,
    required this.unit,
    required this.timeLabels,
    required this.style,
  });

  final List<LgSparkSeries> series;
  final LgColors colors;
  final String unit;
  final List<String> timeLabels;
  final TextStyle style;

  static const _steps = <double>[
    10, 20, 40, 50, 100, 200, 400, 500, 1000, 2000, 5000, 10000, //
  ];

  TextPainter _text(String s) =>
      TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    var peak = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        if (v != null) peak = math.max(peak, v);
      }
    }
    final top = _steps.firstWhere(
      (s) => s >= peak * 1.05,
      orElse: () => peak.ceilToDouble(),
    );
    String fmt(double v) => v == 0 ? '0' : '${v.round()} $unit';
    final labels = [for (final v in [0.0, top / 2, top]) _text(fmt(v))];
    final gutter = labels.map((l) => l.width).reduce(math.max) + LgSpace.s2;
    final axisHeight = _text('0').height + LgSpace.s2;
    final plot = Rect.fromLTRB(
      gutter,
      labels.last.height / 2,
      size.width - 4,
      size.height - axisHeight,
    );
    double y(double v) => plot.bottom - plot.height * (v / top);

    final grid = Paint()
      ..color = colors.border
      ..strokeWidth = 1;
    for (final (i, v) in [0.0, top / 2, top].indexed) {
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), grid);
      labels[i].paint(
        canvas,
        Offset(0, y(v) - labels[i].height / 2),
      );
    }
    for (final (i, label) in timeLabels.indexed) {
      final tp = _text(label);
      final x = timeLabels.length == 1
          ? plot.left
          : plot.left +
                (plot.width - tp.width) * (i / (timeLabels.length - 1));
      tp.paint(canvas, Offset(x, size.height - tp.height));
    }
    for (final (index, s) in series.indexed) {
      final n = s.values.length;
      if (n < 2) continue;
      final path = Path();
      var pen = false;
      Offset? last;
      for (var i = 0; i < n; i++) {
        final v = s.values[i];
        if (v == null) {
          pen = false;
          continue;
        }
        final p = Offset(plot.left + plot.width * i / (n - 1), y(v));
        if (pen) {
          path.lineTo(p.dx, p.dy);
        } else {
          path.moveTo(p.dx, p.dy);
          pen = true;
        }
        last = p;
      }
      _drawLine(canvas, path, _linePaint(colors, s.style), s.style);
      if (index == 0 && last != null) {
        canvas.drawCircle(last, 4.5, Paint()..color = colors.float);
        canvas.drawCircle(last, 3, Paint()..color = _linePaint(colors, s.style).color);
      }
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.series != series ||
      old.colors != colors ||
      old.unit != unit ||
      old.timeLabels != timeLabels ||
      old.style != style;
}

/// The key to a line of the chart in front of a table row's name (`.lk`).
class LgLineKey extends StatelessWidget {
  const LgLineKey(this.style, {super.key});

  final LgLineStyle style;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return ExcludeSemantics(
      child: SizedBox(
        width: 24,
        height: 8,
        child: CustomPaint(painter: _KeyPainter(style, c)),
      ),
    );
  }
}

class _KeyPainter extends CustomPainter {
  _KeyPainter(this.style, this.colors);

  final LgLineStyle style;
  final LgColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(1.5, size.height / 2)
      ..lineTo(size.width - 1.5, size.height / 2);
    _drawLine(canvas, path, _linePaint(colors, style), style);
  }

  @override
  bool shouldRepaint(_KeyPainter old) =>
      old.style != style || old.colors != colors;
}

/// One line of a key-value group: "路径  经中继". A [copyLabel] with [onCopy]
/// adds a copy button at the end (the fingerprint); [icon] stands before the
/// value (a lock before "已加密"); [wrap] lets a long value run over two lines
/// (the fingerprint) instead of ending in "…".
class LgKeyValue {
  const LgKeyValue(
    this.label,
    this.value, {
    this.icon,
    this.copyLabel,
    this.onCopy,
    this.wrap = false,
  }) : assert(onCopy == null || copyLabel != null);

  final String label;
  final String value;
  final LgIcons? icon;
  final String? copyLabel;
  final VoidCallback? onCopy;
  final bool wrap;
}

/// A titled group of key-value lines ("连接", "画面数据").
class LgKeyValueGroup {
  const LgKeyValueGroup(this.title, this.rows);

  final String title;
  final List<LgKeyValue> rows;
}

/// A row of the delay table: a line key, a name and four numbers as texts
/// ("18 ms" or "—" for none).
class LgLatencyRow {
  const LgLatencyRow({
    required this.name,
    required this.line,
    required this.current,
    required this.min,
    required this.average,
    required this.max,
    this.indent = false,
  });

  final String name;
  final LgLineStyle line;
  final String current;
  final String min;
  final String average;
  final String max;

  /// Sets the row in under the one above ("其余" under the whole).
  final bool indent;
}

/// The delay section: its title and the note at its right, the column titles,
/// the rows and the chart under them.
class LgLatencySection {
  const LgLatencySection({
    required this.title,
    required this.note,
    required this.currentLabel,
    required this.minLabel,
    required this.averageLabel,
    required this.maxLabel,
    required this.rows,
    this.chart,
  });

  final String title;

  /// "统计自本次会话开始，折线为近 60 秒".
  final String note;
  final String currentLabel;
  final String minLabel;
  final String averageLabel;
  final String maxLabel;
  final List<LgLatencyRow> rows;
  final LgSparkline? chart;
}

/// The switch row at the bottom ("在画面上显示质量数据").
class LgDetailsSwitch {
  const LgDetailsSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
}

/// The card (`.pop`, 400 wide; 480 for a wider table): the connection method
/// at the top in its own colour and shape, a line on what it means ([why]),
/// the [groups], the [latency] section and the [qualitySwitch].
class LgRouteDetails extends StatelessWidget {
  const LgRouteDetails({
    super.key,
    required this.route,
    required this.title,
    required this.semanticLabel,
    this.why,
    this.encrypted = true,
    this.unencryptedLabel,
    this.groups = const [],
    this.latency,
    this.qualitySwitch,
    this.width = 400,
    this.maxHeight,
  }) : assert(encrypted || unencryptedLabel != null);

  final LgRoute route;

  /// "直连" / "经中继".
  final String title;

  /// Name of the card for a screen reader ("连接方式").
  final String semanticLabel;

  /// "流量由中继服务器转发，速度可能较慢".
  final String? why;
  final bool encrypted;
  final String? unencryptedLabel;
  final List<LgKeyValueGroup> groups;
  final LgLatencySection? latency;
  final LgDetailsSwitch? qualitySwitch;
  final double width;

  /// The card scrolls when the window is lower than its content.
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: LgSpace.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: DefaultTextStyle(
                  style: t.textN,
                  child: LgRouteMark(
                    route: route,
                    label: title,
                    encrypted: encrypted,
                    unencryptedLabel: unencryptedLabel,
                  ),
                ),
              ),
              if (why != null)
                Padding(
                  padding: const EdgeInsets.only(top: LgSpace.s2),
                  child: Text(why!, style: t.textS.copyWith(color: c.text2)),
                ),
            ],
          ),
        ),
        for (final group in groups) _Group(group: group),
        if (latency != null) _Latency(section: latency!),
        if (qualitySwitch != null) _SwitchRow(row: qualitySwitch!),
      ],
    );
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Container(
        width: width,
        constraints: maxHeight == null
            ? null
            : BoxConstraints(maxHeight: maxHeight!),
        padding: const EdgeInsets.only(top: LgSpace.s5, bottom: LgSpace.s2),
        decoration: BoxDecoration(
          color: c.float,
          borderRadius: BorderRadius.circular(LgRadius.r16),
          boxShadow: c.shadow,
        ),
        child: maxHeight == null ? body : SingleChildScrollView(child: body),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title, {this.note});

  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final style = t.textS.copyWith(
      color: t.colors.text2,
      fontWeight: FontWeight.w700,
    );
    return Container(
      constraints: BoxConstraints(minHeight: t.sizes.menuGroup),
      padding: EdgeInsets.only(top: t.sizes.menuGroup - 22),
      alignment: Alignment.centerLeft,
      child: Semantics(
        header: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(title, style: style),
            if (note != null) ...[
              const SizedBox(width: LgSpace.s2),
              Expanded(
                child: Text(
                  note!,
                  textAlign: TextAlign.right,
                  style: style.copyWith(fontWeight: FontWeight.w400),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.group});

  final LgKeyValueGroup group;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LgSpace.s5,
        LgSpace.s3,
        LgSpace.s5,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupTitle(group.title),
          for (final (i, row) in group.rows.indexed)
            Container(
              constraints: BoxConstraints(minHeight: t.sizes.menuGroup),
              padding: EdgeInsets.symmetric(vertical: row.wrap ? 4 : 0),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: c.border)),
              ),
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: Row(
                  children: [
                    SizedBox(
                      width: 104,
                      child: ExcludeSemantics(
                        child: Text(
                          row.label,
                          style: t.textS.copyWith(color: c.text2),
                        ),
                      ),
                    ),
                    const SizedBox(width: LgSpace.s3),
                    Expanded(
                      child: Semantics(
                        label: '${row.label}: ${row.value}',
                        child: ExcludeSemantics(
                          child: Row(
                            children: [
                              if (row.icon != null) ...[
                                LgIcon(row.icon!, size: 16, color: c.text),
                                const SizedBox(width: LgSpace.s2),
                              ],
                              Expanded(
                                child: Text(
                                  row.value,
                                  maxLines: row.wrap ? 3 : 1,
                                  overflow: row.wrap
                                      ? TextOverflow.clip
                                      : TextOverflow.ellipsis,
                                  style: t.textM.copyWith(
                                    color: c.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (row.onCopy != null) ...[
                      const SizedBox(width: LgSpace.s2),
                      LgIconButton(
                        icon: LgIcons.copy,
                        label: row.copyLabel!,
                        size: 28,
                        iconSize: 18,
                        onPressed: row.onCopy,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Latency extends StatelessWidget {
  const _Latency({required this.section});

  final LgLatencySection section;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final head = t.textS.copyWith(color: c.text2, fontWeight: FontWeight.w700);
    final numbers = t.textM;
    Widget number(String text, double width, {bool strong = false}) => SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        maxLines: 1,
        style: numbers.copyWith(
          color: strong ? c.text : c.text2,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
    const wide = 76.0;
    const narrow = 58.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LgSpace.s5,
        LgSpace.s3,
        LgSpace.s5,
        0,
      ),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GroupTitle(section.title, note: section.note),
            Padding(
              padding: const EdgeInsets.only(bottom: LgSpace.s1),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    const Spacer(),
                    SizedBox(
                      width: wide,
                      child: Text(
                        section.currentLabel,
                        textAlign: TextAlign.right,
                        style: head,
                      ),
                    ),
                    for (final l in [
                      section.minLabel,
                      section.averageLabel,
                      section.maxLabel,
                    ])
                      SizedBox(
                        width: narrow,
                        child: Text(l, textAlign: TextAlign.right, style: head),
                      ),
                  ],
                ),
              ),
            ),
            for (final (i, row) in section.rows.indexed)
              Semantics(
                container: true,
                label:
                    '${row.name}: ${section.currentLabel} ${row.current}, '
                    '${section.minLabel} ${row.min}, '
                    '${section.averageLabel} ${row.average}, '
                    '${section.maxLabel} ${row.max}',
                child: ExcludeSemantics(
                  child: Container(
                    height: t.sizes.menuGroup,
                    decoration: BoxDecoration(
                      border: i == 0
                          ? null
                          : Border(top: BorderSide(color: c.border)),
                    ),
                    child: Row(
                      children: [
                        if (row.indent)
                          const SizedBox(width: LgSpace.s6 + LgSpace.s2),
                        LgLineKey(row.line),
                        const SizedBox(width: LgSpace.s2),
                        Expanded(
                          child: Text(
                            row.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: numbers.copyWith(color: c.text),
                          ),
                        ),
                        number(row.current, wide, strong: true),
                        number(row.min, narrow),
                        number(row.average, narrow),
                        number(row.max, narrow),
                      ],
                    ),
                  ),
                ),
              ),
            if (section.chart != null)
              Padding(
                padding: const EdgeInsets.only(top: LgSpace.s3),
                child: section.chart!,
              ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.row});

  final LgDetailsSwitch row;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Container(
      margin: const EdgeInsets.only(top: LgSpace.s2),
      padding: const EdgeInsets.fromLTRB(
        LgSpace.s5,
        LgSpace.s3,
        LgSpace.s5,
        LgSpace.s2,
      ),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
      child: Row(
        children: [
          Expanded(
            child: Text(row.label, style: t.text.copyWith(color: c.text)),
          ),
          const SizedBox(width: LgSpace.s3),
          LgSwitch(
            value: row.value,
            onChanged: row.onChanged,
            semanticLabel: row.label,
          ),
        ],
      ),
    );
  }
}
