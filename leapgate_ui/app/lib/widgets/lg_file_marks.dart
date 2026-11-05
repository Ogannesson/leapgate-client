// Small parts of the file transfer view (02 §2.2, §3.2; P7 mockups): the progress ring and the
// reminder mark of a tab and of the view switch, the tail of the view switch's menu row, the
// "counting" line of the delete confirmation and the loading row of the drive list. All text comes
// from the caller.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_status.dart';

/// The small ring of the overall progress of the file transfers (`.rg` in A-P7-文件传输.html):
/// 16 px, a 2.4 px line (3 of the 20 units of its box), the track in the track colour and the
/// finished part in the accent colour from the top, clockwise. Decoration: whoever carries it
/// names it ("文件传输 45%").
class LgProgressRing extends StatelessWidget {
  const LgProgressRing({super.key, required this.value, this.size = 16});

  /// 0..1.
  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _RingPainter(value.clamp(0.0, 1.0), c.track, c.accent),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.track, this.fill);

  final double value;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    // The mockup draws r 8 and a line of 3 in a box of 20.
    final unit = size.width / 20;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: 8 * unit);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * unit
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawCircle(center, 8 * unit, line);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value,
        false,
        line..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}

/// The reminder mark (`.rmd`): the warning triangle, 16 px, in the warning colour. It replaces
/// the progress ring while a replace confirmation waits, and, as in the exit page, it is never
/// alone: the control that holds it says "需要处理" in its name.
class LgReminderMark extends StatelessWidget {
  const LgReminderMark({super.key});

  @override
  Widget build(BuildContext context) => LgIcon(
    LgIcons.warn,
    size: 16,
    color: LgTokens.of(context).colors.warning,
  );
}

/// What the "文件传输" row of the view switch's menu shows at its end (`.mr .rg`, `.pc`): the ring
/// (or the reminder mark), the percentage in bold accent, then the connection method of that
/// view. Give it to `LgMenuItem.trailing`.
class LgViewMenuTail extends StatelessWidget {
  const LgViewMenuTail({
    super.key,
    this.progress,
    this.percentText,
    this.alert = false,
    this.status,
  });

  /// 0..1 of the view's transfers; null draws no ring.
  final double? progress;

  /// "45%".
  final String? percentText;

  /// A replace confirmation waits: the reminder mark takes the ring's place.
  final bool alert;

  /// The connection method mark of the view ([LgRouteMark]) or its state text.
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final parts = <Widget>[
      if (alert)
        const LgReminderMark()
      else if (progress != null)
        LgProgressRing(value: progress!),
      if (percentText != null && !alert)
        Text(
          percentText!,
          style: t.textS.copyWith(
            color: t.colors.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ?status,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, p) in parts.indexed) ...[
          if (i > 0) const SizedBox(width: LgSpace.s2),
          p,
        ],
      ],
    );
  }
}

/// "正在统计要删除的项目…" under the title of the delete confirmation (`d-dl-count`): a turning
/// arc and one line. Announced as it appears, since nothing else tells a reader that the
/// question has not come yet.
class LgCountingNote extends StatelessWidget {
  const LgCountingNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Semantics(
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: Row(
          children: [
            LgSpinner(size: 20, color: t.colors.connecting),
            const SizedBox(width: LgSpace.s3),
            Expanded(
              child: Text(text, style: t.text.copyWith(color: t.colors.text)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The only row of the drive list while the remote device's drives are read (`d-pa-ddld`): a
/// turning arc and "正在读取…" in the greyed text. Not a button.
class LgMenuLoadingRow extends StatelessWidget {
  const LgMenuLoadingRow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Semantics(
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: Container(
          height: t.sizes.row,
          padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
          child: Row(
            children: [
              LgSpinner(size: 18, color: t.colors.connecting),
              const SizedBox(width: LgSpace.s3),
              Expanded(
                child: Text(
                  text,
                  style: t.text.copyWith(color: t.colors.text2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
