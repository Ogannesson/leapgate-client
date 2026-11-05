// The transfer queue at the foot of the file transfer view (02 §2.2 block H; `.q`, `.qs`, `.qr`,
// `.qd` in A-P7-文件传输.html): the summary line that stays when the panel is folded, the grip that
// drags its height, the rows in every state a transfer can be in, and the list under a row that
// finished with files left over (that list belongs to M7b, the parts are drawn now). All text
// comes from the caller.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_pressable.dart';
import 'lg_status.dart';
import 'lg_tooltip.dart';

/// Below this width of the panel a row puts the path under the name, as the 960 px window needs
/// (`.mn .qr`).
const double kLgQueueStackBelow = 1080;

enum LgQueueDirection { upload, download, delete }

/// The states of a row (02 §2.2 block H). The icon and the look of the progress follow from it;
/// the words are the caller's.
enum LgQueueState {
  /// Waits for an earlier transfer in its direction: no icon, no bar.
  queued,

  /// A folder whose files are still being listed: a turning arc.
  counting,
  inProgress,

  /// A replace question is open for it: the warning triangle.
  waitingConfirm,
  deleting,

  /// Left half way (by the user, by closing the view, or the peer ended the session): the bar in
  /// the quiet colour.
  paused,

  /// The connection is down; it goes on by itself: a crossed-out signal.
  interrupted,
  done,

  /// Finished, but some files were not sent (M7b): the warning triangle and the details link.
  doneWithIssues,
  skipped,
  cancelled,

  /// The error colour, icon and bold text.
  failed,
}

/// A button at the end of a row (pause, cancel, resume, retry, remove): an icon, its name for the
/// tooltip and the screen reader.
class LgQueueAction {
  const LgQueueAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final LgIcons icon;
  final String label;
  final VoidCallback? onPressed;
}

/// One line of the list that opens under a row (`.qd`): a path in the heavier text and, after a
/// dot, why it was left out in the error colour. A remark that is no file ("2 个空文件夹未创建")
/// has no [reason].
class LgQueueDetail {
  const LgQueueDetail(this.text, {this.reason});

  final String text;
  final String? reason;
}

/// The bar of the progress of one transfer: 96 × 6, the accent colour, or the quiet one while
/// [paused].
class LgQueueBar extends StatelessWidget {
  const LgQueueBar({super.key, required this.value, this.paused = false});

  final double value;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return ExcludeSemantics(
      child: Container(
        width: 96,
        height: 6,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: c.track,
          borderRadius: BorderRadius.circular(LgRadius.r6),
        ),
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: paused ? c.text2 : c.accent,
              borderRadius: BorderRadius.circular(LgRadius.r6),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of the queue.
///
/// [status] is the line of the state ("排队中", "正在统计文件…", "已中断，重新连接后将继续") and, for
/// a transfer under way, what follows [statusLead] ("45%" in bold, then "610 MB / 1.32 GB · …").
/// [progress] draws the bar for a transfer that has a size ([LgQueueState.inProgress],
/// [LgQueueState.deleting], [LgQueueState.paused]). [path] is the source and the target in one
/// line ("D:\备份\照片 → C:\Users\zhangsan\Pictures"). [detailsLabel] adds the "查看详情" link to a
/// [LgQueueState.doneWithIssues] row, which opens [details] under it.
class LgQueueRow extends StatelessWidget {
  const LgQueueRow({
    super.key,
    required this.direction,
    required this.directionLabel,
    required this.name,
    required this.path,
    required this.state,
    required this.status,
    this.statusLead,
    this.progress,
    this.actions = const [],
    this.detailsLabel,
    this.detailsOpen = false,
    this.onToggleDetails,
    this.details = const [],
  });

  final LgQueueDirection direction;

  /// "上传" / "下载" / "删除", for a screen reader.
  final String directionLabel;
  final String name;
  final String path;
  final LgQueueState state;
  final String status;
  final String? statusLead;
  final double? progress;
  final List<LgQueueAction> actions;
  final String? detailsLabel;
  final bool detailsOpen;
  final VoidCallback? onToggleDetails;
  final List<LgQueueDetail> details;

  LgIcons get _directionIcon => switch (direction) {
    LgQueueDirection.upload => LgIcons.upload,
    LgQueueDirection.download => LgIcons.download,
    LgQueueDirection.delete => LgIcons.trash,
  };

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final stacked = _QueueStacking.of(context);
    final failed = state == LgQueueState.failed;
    final bar =
        progress != null &&
        (state == LgQueueState.inProgress ||
            state == LgQueueState.deleting ||
            state == LgQueueState.paused);
    final (LgIcons?, Color?) stateIcon = switch (state) {
      LgQueueState.counting => (LgIcons.markSpin, c.connecting),
      LgQueueState.waitingConfirm => (LgIcons.warn, c.warning),
      LgQueueState.interrupted => (LgIcons.wifiOff, c.text2),
      LgQueueState.done => (LgIcons.checkCircle, c.text2),
      LgQueueState.doneWithIssues => (LgIcons.warn, c.warning),
      LgQueueState.cancelled => (LgIcons.ban, c.text2),
      LgQueueState.failed => (LgIcons.err, c.error),
      _ => (null, null),
    };
    final small = t.textM;
    final statusText = Text.rich(
      TextSpan(
        children: [
          if (statusLead != null)
            TextSpan(
              text: statusLead,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          if (statusLead != null) const TextSpan(text: ' · '),
          TextSpan(text: status),
        ],
      ),
      style: small.copyWith(
        color: failed ? c.error : c.text,
        fontWeight: failed ? FontWeight.w700 : FontWeight.w400,
      ),
    );
    final statusCell = Row(
      children: [
        if (bar) ...[
          LgQueueBar(value: progress!, paused: state == LgQueueState.paused),
          const SizedBox(width: LgSpace.s2),
        ] else ...[
          SizedBox(
            width: 16,
            child: stateIcon.$1 == null
                ? null
                : (state == LgQueueState.counting
                      ? LgSpinner(
                          icon: LgIcons.markSpin,
                          size: 16,
                          color: stateIcon.$2,
                        )
                      : LgIcon(stateIcon.$1!, size: 16, color: stateIcon.$2)),
          ),
          const SizedBox(width: LgSpace.s2),
        ],
        Flexible(child: statusText),
        if (state == LgQueueState.doneWithIssues && detailsLabel != null) ...[
          const SizedBox(width: LgSpace.s4),
          _DetailsLink(
            label: detailsLabel!,
            open: detailsOpen,
            onPressed: onToggleDetails,
          ),
        ],
      ],
    );
    final nameText = Text(
      name,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: t.text.copyWith(color: c.text, fontWeight: FontWeight.w700),
    );
    final pathText = Text(
      path,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: (stacked ? t.textS : small).copyWith(color: c.text2),
    );
    final identity = stacked
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: LgSpace.s1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LgEllipsisText(
                  name,
                  style: t.text.copyWith(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                pathText,
              ],
            ),
          )
        : Row(
            children: [
              SizedBox(width: 116, child: nameText),
              const SizedBox(width: LgSpace.s3),
              Expanded(child: pathText),
            ],
          );
    final row = Container(
      constraints: BoxConstraints(
        minHeight: stacked ? t.sizes.tableRow + LgSpace.s1 : t.sizes.button - 2,
      ),
      padding: const EdgeInsets.only(left: LgSpace.s3, right: LgSpace.s2),
      child: Row(
        children: [
          LgIcon(_directionIcon, size: 20, color: c.text2),
          const SizedBox(width: LgSpace.s3),
          Expanded(flex: stacked ? 100 : 125, child: identity),
          const SizedBox(width: LgSpace.s3),
          Expanded(flex: stacked ? 150 : 160, child: statusCell),
          const SizedBox(width: LgSpace.s3),
          SizedBox(
            width: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final a in actions)
                  LgIconButton(
                    icon: a.icon,
                    label: a.label,
                    size: t.sizes.button - LgSpace.s1,
                    onPressed: a.onPressed,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        if (detailsOpen && details.isNotEmpty) _Details(details: details),
      ],
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label:
          '$directionLabel $name, ${statusLead == null ? '' : '$statusLead, '}$status',
      child: body,
    );
  }
}

/// Tells the rows of a panel whether to put the path under the name (the panel narrower than
/// [kLgQueueStackBelow]).
class _QueueStacking extends InheritedWidget {
  const _QueueStacking({required this.stacked, required super.child});

  final bool stacked;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_QueueStacking>()?.stacked ??
      false;

  @override
  bool updateShouldNotify(_QueueStacking old) => old.stacked != stacked;
}

/// A row with the thin line above it (`.qr+.qr::before`).
class _Divided extends StatelessWidget {
  const _Divided({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return Stack(
      children: [
        child,
        Positioned(
          left: LgSpace.s3,
          right: LgSpace.s3,
          top: 0,
          height: 1,
          child: ColoredBox(color: c.border),
        ),
      ],
    );
  }
}

class _DetailsLink extends StatelessWidget {
  const _DetailsLink({
    required this.label,
    required this.open,
    required this.onPressed,
  });

  final String label;
  final bool open;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return LgPressable(
      onPressed: onPressed,
      semanticLabel: label,
      expanded: open,
      builder: (context, states) => LgFocusRing(
        show: states.contains(WidgetState.focused),
        radius: BorderRadius.circular(LgRadius.r6),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: t.textM.copyWith(
                  color: c.accent,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationThickness: 2,
                  decorationColor: c.accent,
                ),
              ),
              const SizedBox(width: LgSpace.s1),
              LgIcon(
                open ? LgIcons.chevU : LgIcons.chevD,
                size: 16,
                color: c.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.details});

  final List<LgQueueDetail> details;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Padding(
      // Under the name: the row's 12 padding, the icon, its gap and 8.
      padding: const EdgeInsets.fromLTRB(
        LgSpace.s3 + 20 + LgSpace.s3 + LgSpace.s2,
        LgSpace.s1,
        LgSpace.s2,
        LgSpace.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final d in details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: d.text,
                      style: TextStyle(
                        color: d.reason == null ? c.text2 : c.text,
                        fontWeight: d.reason == null
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                    if (d.reason != null) ...[
                      const TextSpan(text: ' · '),
                      TextSpan(
                        text: d.reason,
                        style: TextStyle(color: c.error),
                      ),
                    ],
                  ],
                ),
                style: t.textM.copyWith(
                  color: c.text2,
                  height: (t.sizes.lhM + LgSpace.s1) / t.sizes.fsM,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum LgQueueTone { neutral, error, warning }

/// A piece of the count in the summary ("3 个进行中，1 个排队，" in the ordinary colour,
/// "1 个失败" bold in the error colour, "1 个等待确认" bold in the warning colour). The caller puts
/// the separators in the neutral pieces.
class LgQueueSpan {
  const LgQueueSpan(this.text, {this.tone = LgQueueTone.neutral});

  final String text;
  final LgQueueTone tone;
}

/// A button of the summary line: "全部继续", "清除已完成".
class LgQueueSummaryAction {
  const LgQueueSummaryAction({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final LgIcons? icon;
}

/// The queue panel: a card of the surface colour with the summary line and, when it is open, the
/// [rows] under it. The caller gives it the height it has (the folded panel is [summaryHeight]
/// high; an open one is as high as the user dragged it) and it fills it; the rows scroll.
///
/// With [emptyText] the line reads "传输  暂无传输任务" and has no fold button. While
/// [onResize] is given and the panel is open, the grip at its top edge drags it: the callback
/// gets the movement in pixels, positive downwards (the caller makes the panel higher when the
/// pointer goes up).
class LgQueuePanel extends StatelessWidget {
  const LgQueuePanel({
    super.key,
    required this.title,
    required this.expanded,
    required this.toggleLabel,
    this.onToggle,
    this.spans = const [],
    this.progress,
    this.percentText,
    this.emptyText,
    this.actions = const [],
    this.rows = const [],
    this.onResize,
    this.resizeLabel,
  });

  /// "传输".
  final String title;
  final bool expanded;

  /// "收起" when it is open, "展开" when it is folded.
  final String toggleLabel;
  final VoidCallback? onToggle;
  final List<LgQueueSpan> spans;

  /// The overall progress; with [percentText] ("45%") drawn after the count.
  final double? progress;
  final String? percentText;
  final String? emptyText;
  final List<LgQueueSummaryAction> actions;

  /// [LgQueueRow]s; the panel adds the dividers and sets how their path is laid out.
  final List<Widget> rows;
  final ValueChanged<double>? onResize;

  /// The grip's name ("调整传输面板的高度").
  final String? resizeLabel;

  /// The height of the summary line in this mode and at this width.
  static double summaryHeight(LgTokens t, double width) =>
      width < kLgQueueStackBelow ? t.sizes.button + LgSpace.s2 : t.sizes.bar;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(LgRadius.r16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LgRadius.r16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < kLgQueueStackBelow;
            final summary = _Summary(
              height: summaryHeight(t, constraints.maxWidth),
              title: title,
              spans: spans,
              emptyText: emptyText,
              progress: progress,
              percentText: percentText,
              actions: actions,
              expanded: expanded,
              toggleLabel: toggleLabel,
              onToggle: emptyText == null ? onToggle : null,
            );
            final open = expanded && emptyText == null;
            return Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  children: [
                    summary,
                    if (open)
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: c.border)),
                          ),
                          child: _QueueStacking(
                            stacked: stacked,
                            child: ListView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: LgSpace.s2,
                                vertical: LgSpace.s1,
                              ),
                              children: [
                                for (final (i, r) in rows.indexed)
                                  i == 0 ? r : _Divided(child: r),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (open && onResize != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: LgSpace.s3,
                    child: _Grip(label: resizeLabel, onDelta: onResize!),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Grip extends StatelessWidget {
  const _Grip({required this.label, required this.onDelta});

  final String? label;
  final ValueChanged<double> onDelta;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return Semantics(
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (d) => onDelta(d.delta.dy),
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: LgSpace.s1),
              child: Opacity(
                opacity: .6,
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.borderStrong,
                    borderRadius: BorderRadius.circular(LgRadius.r6),
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

class _Summary extends StatelessWidget {
  const _Summary({
    required this.height,
    required this.title,
    required this.spans,
    required this.emptyText,
    required this.progress,
    required this.percentText,
    required this.actions,
    required this.expanded,
    required this.toggleLabel,
    required this.onToggle,
  });

  final double height;
  final String title;
  final List<LgQueueSpan> spans;
  final String? emptyText;
  final double? progress;
  final String? percentText;
  final List<LgQueueSummaryAction> actions;
  final bool expanded;
  final String toggleLabel;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final count = emptyText != null
        ? Text(
            emptyText!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.text.copyWith(color: c.text2),
          )
        : Text.rich(
            TextSpan(
              children: [
                for (final s in spans)
                  TextSpan(
                    text: s.text,
                    style: switch (s.tone) {
                      LgQueueTone.neutral => null,
                      LgQueueTone.error => TextStyle(
                        color: c.error,
                        fontWeight: FontWeight.w700,
                      ),
                      LgQueueTone.warning => TextStyle(
                        color: c.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    },
                  ),
              ],
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: t.text.copyWith(color: c.text2),
          );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      liveRegion: true,
      child: Container(
        height: height,
        padding: const EdgeInsets.only(left: LgSpace.s5, right: LgSpace.s2),
        child: Row(
          children: [
            // The title, the count and the bar keep to the left and share what the buttons
            // leave; the count is what gives way.
            Expanded(
              child: Row(
                children: [
                  Text(
                    title,
                    style: t.text.copyWith(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: LgSpace.s3),
                  Flexible(child: count),
                  if (progress != null && emptyText == null) ...[
                    const SizedBox(width: LgSpace.s3),
                    LgQueueBar(value: progress!),
                    if (percentText != null) ...[
                      const SizedBox(width: LgSpace.s2),
                      Text(
                        percentText!,
                        style: t.text.copyWith(
                          color: c.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            for (final a in actions) ...[
              LgButton(
                label: a.label,
                icon: a.icon,
                iconSize: 16,
                kind: LgButtonKind.text,
                horizontalPadding: LgSpace.s3,
                onPressed: a.onPressed,
              ),
              const SizedBox(width: LgSpace.s1),
            ],
            if (onToggle != null)
              LgButton(
                label: toggleLabel,
                trailingIcon: expanded ? LgIcons.chevD : LgIcons.chevU,
                iconSize: 16,
                kind: LgButtonKind.text,
                horizontalPadding: LgSpace.s3,
                expanded: expanded,
                onPressed: onToggle,
              ),
          ],
        ),
      ),
    );
  }
}
