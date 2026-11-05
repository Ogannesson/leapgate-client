import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/file_transfer/errors.dart';
import 'package:flutter_hbb/leapgate/file_transfer/jobs.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_tooltip.dart';
import 'file_dialogs.dart';

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
  const FileQueuePanel({super.key, required this.jobs});

  final FileJobs jobs;

  @override
  State<FileQueuePanel> createState() => _FileQueuePanelState();
}

class _FileQueuePanelState extends State<FileQueuePanel> {
  late Set<int> _seen;
  late bool _expanded;
  late double _height;

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

  void _drag(DragUpdateDetails d) => setState(
    () => _height = (_height - d.delta.dy).clamp(
      kQueueMinHeight,
      kQueueMaxHeight,
    ),
  );

  void _saveHeight() => appCore.options.local.set(
    kOptionLeapgateFtQueueHeight,
    _height.round().toString(),
  );

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final l10n = AppLocalizations.of(context)!;
    final rows = widget.jobs.rows;
    final open = _expanded && rows.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (open)
            Semantics(
              label: l10n.queueResizeHandle,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeRow,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: _drag,
                  onVerticalDragEnd: (_) => _saveHeight(),
                  child: const SizedBox(height: LgSpace.s2),
                ),
              ),
            ),
          _Summary(
            jobs: widget.jobs,
            expanded: open,
            onToggle: rows.isEmpty
                ? null
                : () => setState(() => _expanded = !_expanded),
          ),
          if (open)
            SizedBox(
              height: _height,
              child: ListView(
                children: [
                  for (final r in rows) _Row(row: r, jobs: widget.jobs),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.jobs,
    required this.expanded,
    required this.onToggle,
  });

  final FileJobs jobs;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final l10n = AppLocalizations.of(context)!;
    final s = jobs.summary;
    final sep = l10n.queueSeparator;
    // "‹n› 个进行中，‹m› 个排队"; paused and interrupted only once nothing else is left
    // (02 block H "按样稿补的细节"). Failed and waiting go on in their colours.
    final counts = <InlineSpan>[];
    void add(String text, [Color? color]) {
      if (counts.isNotEmpty) counts.add(TextSpan(text: sep));
      counts.add(
        TextSpan(
          text: text,
          style: color == null
              ? null
              : TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      );
    }

    if (jobs.rows.isEmpty) {
      add(l10n.queueEmpty);
    } else {
      if (s.active > 0) add(l10n.queueActiveCount(s.active));
      if (s.queued > 0) add(l10n.queueQueuedCount(s.queued));
      if (s.active == 0 && s.queued == 0) {
        if (s.paused > 0) add(l10n.queuePausedCount(s.paused));
        if (s.interrupted > 0) add(l10n.queueInterruptedCount(s.interrupted));
      }
      if (s.failed > 0) add(l10n.queueFailedCount(s.failed), c.error);
      if (s.waitingConfirm > 0) {
        add(l10n.queueWaitingCount(s.waitingConfirm), c.warning);
      }
    }
    final progress = s.progress;
    return SizedBox(
      height: t.sizes.row,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
        child: Row(
          children: [
            Text(
              l10n.queueTitle,
              style: t.textM.copyWith(
                color: c.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: LgSpace.s3),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    ...counts,
                    if (progress != null)
                      TextSpan(text: ' · ${(progress * 100).floor()}%'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textM.copyWith(color: c.text2),
              ),
            ),
            if (s.paused > 0)
              LgButton(
                label: l10n.queueResumeAll,
                kind: LgButtonKind.text,
                onPressed: jobs.resumeAll,
              ),
            if (s.finished > 0)
              LgButton(
                label: l10n.queueClearFinished,
                kind: LgButtonKind.text,
                onPressed: jobs.clearFinished,
              ),
            if (onToggle != null)
              LgButton(
                label: expanded ? l10n.queueCollapse : l10n.queueExpand,
                kind: LgButtonKind.text,
                trailingIcon: expanded ? LgIcons.chevD : LgIcons.chevU,
                onPressed: onToggle,
              ),
          ],
        ),
      ),
    );
  }
}

/// One job (02 block H "每一行"): direction, name, source → destination, the state of the row
/// with its progress, and the buttons of that state. Pausing and retrying are M7b.
class _Row extends StatelessWidget {
  const _Row({required this.row, required this.jobs});

  final FileJobRow row;
  final FileJobs jobs;

  String _remaining(AppLocalizations l10n, Duration d) {
    final s = d.inSeconds;
    if (s < 60) return l10n.queueRemainingSeconds(s < 1 ? 1 : s);
    if (s < 3600) return l10n.queueRemainingMinutes((s / 60).round());
    return l10n.queueRemainingHours(d.inHours, d.inMinutes % 60);
  }

  /// What the row says, and the text behind it on hover (the original error text).
  (String, String?) _status(AppLocalizations l10n) {
    final r = row;
    String size(int b) => ftSize(l10n, b);
    switch (r.status) {
      case FileJobStatus.queued:
        return (l10n.queueStatusQueued, null);
      case FileJobStatus.counting:
        return (l10n.queueStatusCounting, null);
      case FileJobStatus.inProgress:
        final progress = r.totalBytes > 0 ? r.doneBytes / r.totalBytes : 0.0;
        return (
          [
            '${(progress * 100).floor()}%',
            l10n.queueBytesOf(size(r.doneBytes), size(r.totalBytes)),
            if (r.fileCount > 1) l10n.queueFilesOf(r.fileIndex, r.fileCount),
            if (r.bytesPerSecond != null)
              '${size(r.bytesPerSecond!.round())}/s',
            if (r.remaining != null) _remaining(l10n, r.remaining!),
          ].join(' · '),
          null,
        );
      case FileJobStatus.waitingConfirm:
        return (l10n.queueStatusWaiting, null);
      case FileJobStatus.deleting:
        return (l10n.queueStatusDeleting(r.fileIndex, r.fileCount), null);
      case FileJobStatus.paused:
        return (
          l10n.queueStatusPaused(size(r.doneBytes), size(r.totalBytes)),
          null,
        );
      case FileJobStatus.interrupted:
        return (l10n.queueStatusInterrupted, null);
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
          return (l10n.ftReasonOther, e.text.isEmpty ? null : e.text);
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
    final t = LgTokens.of(context);
    final c = t.colors;
    final l10n = AppLocalizations.of(context)!;
    final r = row;
    final (status, detail) = _status(l10n);
    final color = switch (r.status) {
      FileJobStatus.failed => c.error,
      FileJobStatus.waitingConfirm => c.warning,
      _ => c.text2,
    };
    final (icon, direction) = switch (r.direction) {
      FileJobDirection.upload => (LgIcons.upload, l10n.queueUpload),
      FileJobDirection.download => (LgIcons.download, l10n.queueDownload),
      FileJobDirection.delete => (LgIcons.trash, l10n.queueDelete),
    };
    final ends = switch (r.status) {
      FileJobStatus.done ||
      FileJobStatus.skipped ||
      FileJobStatus.cancelled ||
      FileJobStatus.failed => [
        LgIconButton(
          icon: LgIcons.x,
          label: l10n.queueRemove,
          onPressed: () => jobs.remove(r.id),
        ),
      ],
      FileJobStatus.waitingConfirm => const <Widget>[],
      FileJobStatus.paused => [
        LgIconButton(
          icon: LgIcons.play,
          label: l10n.queueResume,
          onPressed: () => jobs.resume(r.id),
        ),
        LgIconButton(
          icon: LgIcons.x,
          label: l10n.queueCancel,
          onPressed: () => jobs.cancel(r.id),
        ),
      ],
      _ => [
        LgIconButton(
          icon: LgIcons.x,
          label: l10n.queueCancel,
          onPressed: () => jobs.cancel(r.id),
        ),
      ],
    };
    Widget statusText = Text(
      status,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.textS.copyWith(color: color),
    );
    if (detail != null) {
      statusText = LgTooltip(message: detail, child: statusText);
    }
    final path = r.to.isEmpty ? r.from : '${r.from} → ${r.to}';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LgSpace.s4,
        vertical: LgSpace.s1,
      ),
      child: Row(
        children: [
          Semantics(
            label: direction,
            child: LgIcon(icon, size: 18, color: c.text2),
          ),
          const SizedBox(width: LgSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textM.copyWith(color: c.text),
                      ),
                    ),
                    const SizedBox(width: LgSpace.s3),
                    Expanded(
                      child: Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textS.copyWith(color: c.text2),
                      ),
                    ),
                  ],
                ),
                if (r.status == FileJobStatus.inProgress)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: LinearProgressIndicator(
                      value: r.totalBytes > 0
                          ? r.doneBytes / r.totalBytes
                          : null,
                      color: c.accent,
                      backgroundColor: c.track,
                    ),
                  ),
                statusText,
                for (final note in r.notes)
                  Text(
                    _note(l10n, note),
                    style: t.textS.copyWith(color: c.text2),
                  ),
              ],
            ),
          ),
          ...ends,
        ],
      ),
    );
  }
}
