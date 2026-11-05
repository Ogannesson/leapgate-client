import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/file_transfer/errors.dart';
import 'package:flutter_hbb/leapgate/file_transfer/jobs.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_file_queue.dart';
import '../../widgets/lg_tooltip.dart';
import 'file_dialogs.dart';
import 'formats.dart';

/// The expanded panel's height when none is saved, and its bounds.
const kQueueDefaultHeight = 200.0;
const kQueueMinHeight = 96.0;
const kQueueMaxHeight = 600.0;

/// The transfer queue at the bottom of the file transfer view (02 §2.2 block H): the summary
/// line, the rows, collapsing and dragging its height. Coder B's; the file view (coder C)
/// places it below the panes and gives it the full width (`LEAPGATE.md` §10.15).
///
/// A new job expands a collapsed panel once; collapsed by hand, it stays so until the next new
/// job. The height is saved for every device ([kOptionLeapgateFtQueueHeight]).
class FileQueuePanel extends StatefulWidget {
  const FileQueuePanel({super.key, required this.jobs, this.connection});

  final FileJobs jobs;

  /// The session's connection: while it is not connected, "继续" and "全部继续" are not drawn
  /// (a row the connection's end left paused does not resume until it is back). Null counts as
  /// connected.
  final ConnectionModel? connection;

  @override
  State<FileQueuePanel> createState() => _FileQueuePanelState();
}

class _FileQueuePanelState extends State<FileQueuePanel> {
  late Set<int> _seen;
  late bool _expanded;
  late double _height;

  /// The grip moved since the pointer went down: the height is saved when it comes up.
  var _dragged = false;

  @override
  void initState() {
    super.initState();
    _seen = {for (final r in widget.jobs.rows) r.id};
    _expanded = _seen.isNotEmpty;
    _height =
        (double.tryParse(
                  appCore.options.local.get(kOptionLeapgateFtQueueHeight),
                ) ??
                kQueueDefaultHeight)
            .clamp(kQueueMinHeight, kQueueMaxHeight);
    widget.jobs.addListener(_onJobs);
  }

  @override
  void didUpdateWidget(FileQueuePanel old) {
    super.didUpdateWidget(old);
    if (old.jobs == widget.jobs) return;
    old.jobs.removeListener(_onJobs);
    widget.jobs.addListener(_onJobs);
    _seen = {for (final r in widget.jobs.rows) r.id};
  }

  @override
  void dispose() {
    widget.jobs.removeListener(_onJobs);
    super.dispose();
  }

  void _onJobs() {
    final added = widget.jobs.rows.where((r) => !_seen.contains(r.id)).toList();
    _seen.addAll(added.map((r) => r.id));
    setState(() {
      if (added.isNotEmpty) _expanded = true;
    });
  }

  /// [limit] is the most the list gets in the space there is now, [content] what its rows need;
  /// the drag starts from what shows. Pulled past the rows nothing more shows, and a taller
  /// height saved before stays.
  void _drag(double dy, double limit, double content) => setState(() {
    _dragged = true;
    final kept = math.min(_height, limit);
    final next = (math.min(kept, content) - dy).clamp(kQueueMinHeight, limit);
    _height = next > content ? math.max(next, kept) : next;
  });

  /// The grip has no end-of-drag callback; the pointer that dragged it comes up inside the
  /// panel's [Listener] (pointer events go where the pointer went down).
  void _endDrag() {
    if (!_dragged) return;
    _dragged = false;
    appCore.options.local.set(
      kOptionLeapgateFtQueueHeight,
      _height.round().toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connection = widget.connection;
    // Six tenths of the height the panel is given, at most kQueueMaxHeight; the saved height
    // stays as it is. Below the panes in a column the height is unbounded: the window's then.
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final limit = math.max(
          kQueueMinHeight,
          math.min(room * 0.6, kQueueMaxHeight),
        );
        final width = constraints.maxWidth;
        if (connection == null) return _build(context, true, limit, width);
        return ListenableBuilder(
          listenable: connection,
          builder: (context, _) => _build(
            context,
            connection.stage == ConnStage.connected,
            limit,
            width,
          ),
        );
      },
    );
  }

  /// [width] is the one the panel lays itself out in: the summary line's height follows it.
  Widget _build(
    BuildContext context,
    bool connected,
    double limit,
    double width,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final jobs = widget.jobs;
    final rows = jobs.rows;
    final s = jobs.summary;
    final open = _expanded && rows.isNotEmpty;
    final progress = rows.isEmpty ? null : s.progress;
    final t = LgTokens.of(context);
    final summary = LgQueuePanel.summaryHeight(t, width);
    final content = _contentHeight(t, width, rows);
    return Listener(
      onPointerUp: (_) => _endDrag(),
      onPointerCancel: (_) => _endDrag(),
      child: SizedBox(
        // A row or two: the list as high as they are, not the saved height with space under them.
        height:
            summary + (open ? math.min(math.min(_height, limit), content) : 0),
        child: LgQueuePanel(
          title: l10n.queueTitle,
          expanded: open,
          toggleLabel: open ? l10n.queueCollapse : l10n.queueExpand,
          onToggle: rows.isEmpty
              ? null
              : () => setState(() => _expanded = !_expanded),
          spans: rows.isEmpty ? const [] : _counts(l10n, s),
          emptyText: rows.isEmpty ? l10n.queueEmpty : null,
          progress: progress,
          percentText: progress == null ? null : '${(progress * 100).floor()}%',
          actions: [
            if (s.paused > 0 && connected)
              LgQueueSummaryAction(
                label: l10n.queueResumeAll,
                icon: LgIcons.play,
                onPressed: jobs.resumeAll,
              ),
            if (s.finished > 0)
              LgQueueSummaryAction(
                label: l10n.queueClearFinished,
                onPressed: jobs.clearFinished,
              ),
          ],
          rows: [
            for (final r in rows)
              _Row(row: r, jobs: jobs, connected: connected),
          ],
          onResize: (dy) => _drag(dy, limit, content),
        ),
      ),
    );
  }

  /// The height `LgQueuePanel`'s open list needs for [rows] at [width]: its padding, each row
  /// at its least height (`LgQueueRow`: a list row's when the path goes under the name, a
  /// button's when beside it) and the notes open under a row. A status that wraps is not
  /// counted; the list scrolls by that line.
  static double _contentHeight(
    LgTokens t,
    double width,
    List<FileJobRow> rows,
  ) {
    final s = t.sizes;
    final row = width < kLgQueueStackBelow
        ? math.max(s.tableRow, s.lh + s.lhS)
        : s.button - 2;
    var height = 2 * LgSpace.s1;
    for (final r in rows) {
      height += row;
      if (r.notes.isNotEmpty) {
        height +=
            LgSpace.s1 + LgSpace.s2 + r.notes.length * (s.lhM + LgSpace.s1 + 2);
      }
    }
    return height;
  }

  /// "‹n› 个进行中，‹m› 个排队"; paused and interrupted only once nothing else is left
  /// (02 block H "按样稿补的细节"). Failed and waiting go on in their colours.
  List<LgQueueSpan> _counts(AppLocalizations l10n, FileJobSummary s) {
    final spans = <LgQueueSpan>[];
    void add(String text, [LgQueueTone tone = LgQueueTone.neutral]) {
      if (spans.isNotEmpty) spans.add(LgQueueSpan(l10n.queueSeparator));
      spans.add(LgQueueSpan(text, tone: tone));
    }

    if (s.active > 0) add(l10n.queueActiveCount(s.active));
    if (s.queued > 0) add(l10n.queueQueuedCount(s.queued));
    if (s.active == 0 && s.queued == 0) {
      if (s.paused > 0) add(l10n.queuePausedCount(s.paused));
      if (s.interrupted > 0) add(l10n.queueInterruptedCount(s.interrupted));
    }
    if (s.failed > 0) add(l10n.queueFailedCount(s.failed), LgQueueTone.error);
    if (s.waitingConfirm > 0) {
      add(l10n.queueWaitingCount(s.waitingConfirm), LgQueueTone.warning);
    }
    return spans;
  }
}

/// One job (02 block H "每一行"): direction, name, source → destination, the state of the row
/// with its progress, and the buttons of that state. Pausing and retrying are M7b.
class _Row extends StatelessWidget {
  const _Row({required this.row, required this.jobs, required this.connected});

  final FileJobRow row;
  final FileJobs jobs;
  final bool connected;

  String _remaining(AppLocalizations l10n, Duration d) {
    final s = d.inSeconds;
    if (s < 60) return l10n.queueRemainingSeconds(s < 1 ? 1 : s);
    // Rounded to minutes first, so 59.5 minutes and more read as an hour.
    final minutes = (s / 60).round();
    if (minutes < 60) return l10n.queueRemainingMinutes(minutes);
    if (minutes % 60 == 0) return l10n.queueRemainingWholeHours(minutes ~/ 60);
    return l10n.queueRemainingHours(minutes ~/ 60, minutes % 60);
  }

  /// What a transfer under way says after its percentage.
  List<String> _progressParts(AppLocalizations l10n) {
    final r = row;
    String size(int b) => formatFileSize(l10n, b);
    return [
      l10n.queueBytesOf(size(r.doneBytes), size(r.totalBytes)),
      if (r.fileCount > 1) l10n.queueFilesOf(r.fileIndex, r.fileCount),
      if (r.bytesPerSecond != null) '${size(r.bytesPerSecond!.round())}/s',
      if (r.remaining != null) _remaining(l10n, r.remaining!),
    ];
  }

  /// What the row says (after the percentage of a transfer under way), and the text behind it
  /// on hover (the original error text).
  (String, String?) _status(AppLocalizations l10n) {
    final r = row;
    String size(int b) => formatFileSize(l10n, b);
    switch (r.status) {
      case FileJobStatus.queued:
        return (l10n.queueStatusQueued, null);
      case FileJobStatus.counting:
        return (l10n.queueStatusCounting, null);
      case FileJobStatus.inProgress:
        return (_progressParts(l10n).join(' · '), null);
      case FileJobStatus.waitingConfirm:
        return (l10n.queueStatusWaiting, null);
      case FileJobStatus.deleting:
        return (l10n.queueStatusDeleting(r.fileIndex, r.fileCount), null);
      // A job loaded from the last session has no bytes until it goes on (the saved job keeps
      // none, `fs.rs` `TransferJobMeta`).
      case FileJobStatus.paused when r.doneBytes == 0:
        return (l10n.queueStatusPausedOnly, null);
      case FileJobStatus.paused:
        return (
          l10n.queueStatusPaused(size(r.doneBytes), size(r.totalBytes)),
          null,
        );
      case FileJobStatus.interrupted:
        return (l10n.queueStatusInterrupted, null);
      // A delete gives no size: "已完成 · ‹N› 个文件", or "已完成" with only empty folders or
      // links.
      case FileJobStatus.done when r.direction == FileJobDirection.delete:
        return (
          r.fileCount == 0
              ? l10n.queueStatusDeletedNoFiles
              : l10n.queueStatusDeleted(r.fileCount),
          null,
        );
      case FileJobStatus.done:
        return (
          r.fileCount == 0 && r.folderCount > 0
              ? l10n.queueStatusDoneFolders(r.folderCount)
              : l10n.queueStatusDone(r.fileCount, size(r.totalBytes)),
          null,
        );
      case FileJobStatus.skipped:
        return (l10n.queueStatusSkipped, null);
      case FileJobStatus.cancelled:
        return (l10n.queueStatusCancelled, null);
      case FileJobStatus.failed:
        final e = r.error ?? const FtError(FtReason.other);
        // "传输失败。‹原文›": the text is behind the row until "查看详情" (M7b).
        if (e.reason == FtReason.other) {
          return (
            r.direction == FileJobDirection.delete
                ? l10n.queueStatusDeleteFailed
                : l10n.ftReasonOther,
            e.text.isEmpty ? null : e.text,
          );
        }
        return (
          l10n.queueStatusFailed(
            ftReasonText(
              l10n,
              e,
              name: r.name,
              toLocal: r.direction == FileJobDirection.download,
            ),
          ),
          null,
        );
    }
  }

  String _note(AppLocalizations l10n, FileJobNote note) => switch (note) {
    EmptyFoldersNotCreated(:final reason) =>
      reason == EmptyFoldersReason.peerTooOld
          ? l10n.queueNoteEmptyFoldersOld
          : l10n.queueNoteEmptyFoldersUnreadable,
    ResumeUnsupported() => l10n.queueNoteResumeUnsupported,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final r = row;
    final (status, detail) = _status(l10n);
    final (direction, label) = switch (r.direction) {
      FileJobDirection.upload => (LgQueueDirection.upload, l10n.queueUpload),
      FileJobDirection.download => (
        LgQueueDirection.download,
        l10n.queueDownload,
      ),
      FileJobDirection.delete => (LgQueueDirection.delete, l10n.queueDelete),
    };
    double ratio(int done, int total) => total > 0 ? done / total : 0.0;
    final (state, progress) = switch (r.status) {
      FileJobStatus.queued => (LgQueueState.queued, null),
      FileJobStatus.counting => (LgQueueState.counting, null),
      FileJobStatus.inProgress => (
        LgQueueState.inProgress,
        ratio(r.doneBytes, r.totalBytes),
      ),
      FileJobStatus.waitingConfirm => (LgQueueState.waitingConfirm, null),
      FileJobStatus.deleting => (
        LgQueueState.deleting,
        r.fileCount > 0 ? ratio(r.fileIndex, r.fileCount) : null,
      ),
      FileJobStatus.paused => (
        LgQueueState.paused,
        r.doneBytes == 0 ? null : ratio(r.doneBytes, r.totalBytes),
      ),
      FileJobStatus.interrupted => (LgQueueState.interrupted, null),
      FileJobStatus.done => (LgQueueState.done, null),
      FileJobStatus.skipped => (LgQueueState.skipped, null),
      FileJobStatus.cancelled => (LgQueueState.cancelled, null),
      FileJobStatus.failed => (LgQueueState.failed, null),
    };
    final lead = r.status == FileJobStatus.inProgress
        ? '${(progress! * 100).floor()}%'
        : null;
    final remove = LgQueueAction(
      icon: LgIcons.x,
      label: l10n.queueRemove,
      onPressed: () => jobs.remove(r.id),
    );
    final cancel = LgQueueAction(
      icon: LgIcons.x,
      label: l10n.queueCancel,
      onPressed: () => jobs.cancel(r.id),
    );
    final actions = switch (r.status) {
      FileJobStatus.done ||
      FileJobStatus.skipped ||
      FileJobStatus.cancelled ||
      FileJobStatus.failed => [remove],
      FileJobStatus.waitingConfirm => const <LgQueueAction>[],
      FileJobStatus.paused => [
        if (connected)
          LgQueueAction(
            icon: LgIcons.play,
            label: l10n.queueResume,
            onPressed: () => jobs.resume(r.id),
          ),
        cancel,
      ],
      _ => [cancel],
    };
    final spoken = lead == null
        ? status
        : [lead, ..._progressParts(l10n)].join(l10n.queueSeparator);
    // The notes stay open under the row; "查看详情" with the files left out is M7b.
    final Widget item = LgQueueRow(
      direction: direction,
      semanticLabel: l10n.queueRowLabel(label, r.name, spoken),
      name: r.name,
      path: r.to.isEmpty ? r.from : '${r.from} → ${r.to}',
      state: state,
      status: status,
      statusLead: lead,
      progress: progress,
      actions: actions,
      detailsOpen: r.notes.isNotEmpty,
      details: [for (final note in r.notes) LgQueueDetail(_note(l10n, note))],
    );
    return detail == null ? item : LgTooltip(message: detail, child: item);
  }
}
