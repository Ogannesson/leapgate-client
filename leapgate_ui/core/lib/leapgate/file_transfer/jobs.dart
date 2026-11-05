// The transfer queue as the view shows it (02 §2.2 block H, §3.1, §3.2). The types above the
// line are the M7a step 0 contract (`LEAPGATE.md` §10.15): the queue panel and the tab marks
// (coder B) know only them. Coder A appends below it the model that derives the rows from the
// copied `JobController`'s job table.
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/file_model.dart';
import '../connection.dart';
import '../session.dart';
import 'errors.dart';

enum FileJobDirection { upload, download, delete }

/// The M7a states of a row. Pausing by the user, retrying from the failed file, and "done, some
/// files not sent" are M7b.
enum FileJobStatus {
  /// Waiting for an earlier job in the same direction.
  queued,

  /// A folder job listing its files: count and total size not known yet.
  counting,
  inProgress,

  /// A replace confirmation is open for it.
  waitingConfirm,
  deleting,

  /// Left unfinished when the view or the window closed, or the peer ended the session; resumes
  /// with "继续".
  paused,

  /// The connection is down; it goes on by itself after reconnecting.
  interrupted,
  done,
  skipped,
  cancelled,
  failed,
}

/// Remarks on a row (02 §2.4.3, §2.4.7).
sealed class FileJobNote {
  const FileJobNote();
}

enum EmptyFoldersReason { peerTooOld, unreadable }

/// "‹k› 个空文件夹未创建：远程设备的版本过低 / 未能读取。"
final class EmptyFoldersNotCreated extends FileJobNote {
  const EmptyFoldersNotCreated(this.count, this.reason);

  final int count;
  final EmptyFoldersReason reason;
}

/// The remote device is older than 1.4.2: resuming starts the current file over.
final class ResumeUnsupported extends FileJobNote {
  const ResumeUnsupported();
}

class FileJobRow {
  const FileJobRow({
    required this.id,
    required this.direction,
    required this.name,
    required this.from,
    this.to = '',
    required this.status,
    this.doneBytes = 0,
    this.totalBytes = 0,
    this.fileIndex = 0,
    this.fileCount = 0,
    this.folderCount = 0,
    this.bytesPerSecond,
    this.remaining,
    this.error,
    this.notes = const [],
  });

  final int id;
  final FileJobDirection direction;

  /// The top-level item's name.
  final String name;

  /// The source path; for a delete, the path deleted.
  final String from;

  /// The destination folder; empty for a delete.
  final String to;
  final FileJobStatus status;
  final int doneBytes;
  final int totalBytes;

  /// Files handled so far (1-based while one is under way), of [fileCount].
  final int fileIndex;
  final int fileCount;

  /// Folders made by a job that held only empty folders ([fileCount] 0).
  final int folderCount;

  /// From the progress bytes over about the last 10 seconds; null until known.
  final double? bytesPerSecond;

  /// Null while the speed is not steady yet.
  final Duration? remaining;

  /// With [FileJobStatus.failed].
  final FtError? error;
  final List<FileJobNote> notes;
}

/// The summary line. [active] counts counting, in progress and deleting rows.
typedef FileJobSummary = ({
  int active,
  int queued,
  int waitingConfirm,
  int failed,
  int paused,
  int interrupted,

  /// Rows "清除已完成" removes: done, skipped, cancelled.
  int finished,

  /// Over the active and queued rows whose size is known; null when there is none.
  double? progress,
});

/// The queue of one file transfer session, rows in the order they were added. Notifies on
/// every change.
abstract interface class FileJobs implements Listenable {
  List<FileJobRow> get rows;
  FileJobSummary get summary;

  /// Queued, counting, in progress and waiting for confirmation: the "‹N› 个传输尚未完成" of the
  /// close and disconnect confirmations (02 §3.1).
  int get unfinished;

  void cancel(int id);
  void resume(int id);
  void resumeAll();

  /// Takes a finished row out of the list; no file is touched.
  void remove(int id);
  void clearFinished();
}

// ---- coder A ----

/// The speed is the progress bytes over this long (02 §2.2 block H).
const _kSpeedWindow = Duration(seconds: 10);

/// No time left is given while the speed is measured over less than this.
const _kSpeedSteady = Duration(seconds: 3);

/// What the job table does not keep about a transfer started from this view.
class _JobInfo {
  _JobInfo(this.target, this.isFolder);

  /// The top-level item's full path at the destination.
  final String target;
  final bool isFolder;

  /// Empty folders made at the destination.
  var foldersMade = 0;
  EmptyFoldersNotCreated? emptyFolders;
}

/// [FileJobs] over the copied [JobController]'s table (`LEAPGATE.md` §10.15): the rows are
/// derived from it each time they are read; only what the table lacks is kept here.
class FileTransferJobs extends ChangeNotifier implements FileJobs {
  FileTransferJobs(this._parent, this._jobs) {
    _jobs.jobTable.listen((_) => _onTable());
  }

  final WeakReference<FFI> _parent;
  final JobController _jobs;
  final _info = <int, _JobInfo>{};

  /// Jobs a replace confirmation is open or queued for.
  final _confirming = <int>{};

  /// FT2's answer for the `err` it was asked about.
  final _errors = <int, ({String text, FtError error})>{};
  final _samples = <int, List<({DateTime at, int bytes})>>{};

  FFI? get _session => _parent.target;

  /// A transfer started here: [target] is the top-level item's path at the destination.
  void addTransfer(int id, {required String target, required bool isFolder}) =>
      _info[id] = _JobInfo(target, isFolder);

  /// The destination path of a transfer started here or loaded from the last session.
  String? targetOf(int id) {
    final info = _info[id];
    if (info != null) return info.target;
    final i = _jobs.getJob(id);
    if (i < 0) return null;
    final job = _jobs.jobTable[i];
    // `loadLastJob` keeps the remote path in `remote` and the local one in `to`.
    final target = job.isRemoteToLocal ? job.to : job.remote;
    return target.isEmpty ? null : target;
  }

  void addFoldersMade(int id) {
    _info[id]?.foldersMade++;
    notifyListeners();
  }

  void emptyFoldersNotCreated(int id, EmptyFoldersNotCreated note) {
    _info[id]?.emptyFolders = note;
    notifyListeners();
  }

  /// [error] for the job's current `err`, decided by Dart (an invalid name, a timeout).
  void setError(int id, FtError error) {
    final i = _jobs.getJob(id);
    if (i < 0) return;
    _errors[id] = (text: _jobs.jobTable[i].err, error: error);
    notifyListeners();
  }

  void setConfirming(int id, bool confirming) {
    if (confirming ? _confirming.add(id) : _confirming.remove(id)) {
      notifyListeners();
    }
  }

  /// The session's connection changed: rows under way show interrupted or paused.
  void onConnectionChanged() => notifyListeners();

  void _onTable() {
    final now = clock.now();
    final live = <int>{};
    for (final job in _jobs.jobTable) {
      live.add(job.id);
      if (job.type != JobType.transfer ||
          job.state != JobState.inProgress ||
          !job.recvJobRes) {
        _samples.remove(job.id);
        continue;
      }
      final s = _samples.putIfAbsent(job.id, () => []);
      if (s.isEmpty || s.last.bytes != job.finishedSize) {
        s.add((at: now, bytes: job.finishedSize));
      }
      // Keeps one sample from before the window, so the span is the whole window.
      while (s.length > 2 && now.difference(s[1].at) >= _kSpeedWindow) {
        s.removeAt(0);
      }
    }
    _samples.removeWhere((id, _) => !live.contains(id));
    notifyListeners();
  }

  @override
  List<FileJobRow> get rows {
    final table = _jobs.jobTable;
    return [for (var i = 0; i < table.length; i++) _row(table, i)];
  }

  FileJobRow _row(List<JobProgress> table, int i) {
    final job = table[i];
    final status = _status(table, i);
    final transfer = job.type == JobType.transfer;
    final info = _info[job.id];
    final done = status == FileJobStatus.done;
    final target = transfer ? targetOf(job.id) : null;
    final rate = status == FileJobStatus.inProgress ? _rate(job) : null;
    return FileJobRow(
      id: job.id,
      direction: !transfer
          ? FileJobDirection.delete
          : job.isRemoteToLocal
              ? FileJobDirection.download
              : FileJobDirection.upload,
      name: job.fileName,
      from: job.jobName,
      to: target == null
          ? ''
          : PathUtil.dirname(target, _targetWindows(job.isRemoteToLocal)),
      status: status,
      doneBytes: done ? job.totalSize : job.finishedSize,
      totalBytes: job.totalSize,
      fileIndex: done
          ? job.fileCount
          : (job.recvJobRes ? job.fileNum + 1 : job.fileNum)
              .clamp(0, job.fileCount),
      fileCount: job.fileCount,
      folderCount: info?.foldersMade ?? 0,
      bytesPerSecond: rate?.speed,
      remaining: rate?.remaining,
      error: status == FileJobStatus.failed ? _errorOf(job) : null,
      notes: [
        if (info?.emptyFolders != null) info!.emptyFolders!,
        if (transfer && status == FileJobStatus.paused && _resumeUnsupported)
          const ResumeUnsupported(),
      ],
    );
  }

  FileJobStatus _status(List<JobProgress> table, int i) {
    final job = table[i];
    final transfer = job.type == JobType.transfer;
    switch (job.state) {
      case JobState.done:
      // Upstream's own values in `err`: a `job_error` "cancel" is not a failure, and FT2 is not
      // asked about either.
      case JobState.error when job.err == 'cancel':
        if (job.err == 'cancel') return FileJobStatus.cancelled;
        if (transfer && job.err == 'skipped') return FileJobStatus.skipped;
        return FileJobStatus.done;
      case JobState.error:
        return FileJobStatus.failed;
      case JobState.paused:
        return FileJobStatus.paused;
      case JobState.none:
      case JobState.inProgress:
        break;
    }
    if (!transfer) return FileJobStatus.deleting;
    final conn = _session?.connection;
    if (conn != null && conn.stage != ConnStage.connected) {
      // Ended without retrying by itself: Rust keeps the job and resumes it on reconnecting.
      return conn.stage == ConnStage.failed && conn.retryCountdown == null
          ? FileJobStatus.paused
          : FileJobStatus.interrupted;
    }
    if (_confirming.contains(job.id)) return FileJobStatus.waitingConfirm;
    // Rust works on one job in each direction at a time (02 §2.2 block H).
    if (!job.recvJobRes &&
        table.take(i).any((j) =>
            j.type == JobType.transfer &&
            j.isRemoteToLocal == job.isRemoteToLocal &&
            (j.state == JobState.inProgress || j.state == JobState.none))) {
      return FileJobStatus.queued;
    }
    if ((_info[job.id]?.isFolder ?? false) &&
        job.fileCount == 0 &&
        !job.recvJobRes) {
      return FileJobStatus.counting;
    }
    return FileJobStatus.inProgress;
  }

  /// A download's destination is this device, an upload's the remote one.
  bool _targetWindows(bool download) => download
      ? isWindows
      : _session?.ffiModel.pi.platform == kPeerPlatformWindows;

  bool get _resumeUnsupported {
    final version = _session?.ffiModel.pi.version ?? '';
    return version.isNotEmpty && versionCmp(version, '1.4.2') < 0;
  }

  ({double speed, Duration? remaining})? _rate(JobProgress job) {
    final s = _samples[job.id];
    if (s == null || s.length < 2) return null;
    final span = s.last.at.difference(s.first.at);
    if (span <= Duration.zero) return null;
    final speed = (s.last.bytes - s.first.bytes) * 1000 / span.inMilliseconds;
    final left = job.totalSize - job.finishedSize;
    return (
      speed: speed,
      remaining: span >= _kSpeedSteady && speed > 0 && left >= 0
          ? Duration(seconds: (left / speed).ceil())
          : null,
    );
  }

  FtError _errorOf(JobProgress job) {
    final cached = _errors[job.id];
    if (cached != null && cached.text == job.err) return cached.error;
    final error = ftErrorOf(job.err,
        peerPlatform: _session?.ffiModel.pi.platform ?? '',
        side: job.type == JobType.transfer
            ? FtSide.unknown
            : job.isRemoteToLocal
                ? FtSide.remote
                : FtSide.local);
    _errors[job.id] = (text: job.err, error: error);
    return error;
  }

  @override
  FileJobSummary get summary {
    var active = 0, queued = 0, waiting = 0, failed = 0, paused = 0;
    var interrupted = 0, finished = 0, doneBytes = 0, totalBytes = 0;
    for (final row in rows) {
      switch (row.status) {
        case FileJobStatus.counting:
        case FileJobStatus.inProgress:
        case FileJobStatus.deleting:
          active++;
        case FileJobStatus.queued:
          queued++;
        case FileJobStatus.waitingConfirm:
          waiting++;
        case FileJobStatus.failed:
          failed++;
        case FileJobStatus.paused:
          paused++;
        case FileJobStatus.interrupted:
          interrupted++;
        case FileJobStatus.done:
        case FileJobStatus.skipped:
        case FileJobStatus.cancelled:
          finished++;
      }
      if ((row.status == FileJobStatus.inProgress ||
              row.status == FileJobStatus.counting ||
              row.status == FileJobStatus.queued) &&
          row.totalBytes > 0) {
        doneBytes += row.doneBytes;
        totalBytes += row.totalBytes;
      }
    }
    return (
      active: active,
      queued: queued,
      waitingConfirm: waiting,
      failed: failed,
      paused: paused,
      interrupted: interrupted,
      finished: finished,
      progress: totalBytes > 0 ? (doneBytes / totalBytes).clamp(0.0, 1.0) : null,
    );
  }

  @override
  int get unfinished => rows
      .where((r) => const {
            FileJobStatus.queued,
            FileJobStatus.counting,
            FileJobStatus.inProgress,
            FileJobStatus.waitingConfirm,
          }.contains(r.status))
      .length;

  /// Stops the job and marks it cancelled; a delete stops before its next file.
  @override
  void cancel(int id) {
    final i = _jobs.getJob(id);
    if (i < 0) return;
    if (_jobs.jobTable[i].type == JobType.transfer) _jobs.cancelJob(id);
    _jobs.updateJobStatus(id, error: 'cancel', state: JobState.done);
  }

  @override
  void resume(int id) {
    final i = _jobs.getJob(id);
    if (i >= 0 && _jobs.jobTable[i].state == JobState.paused) {
      _jobs.resumeJob(id);
    }
  }

  @override
  void resumeAll() {
    for (final job in _jobs.jobTable.toList()) {
      if (job.state == JobState.paused) _jobs.resumeJob(job.id);
    }
  }

  @override
  void remove(int id) => _removeWhere((job) => job.id == id);

  @override
  void clearFinished() => _removeWhere((job) => job.state == JobState.done);

  /// Only ended rows go: done, skipped, cancelled and failed.
  void _removeWhere(bool Function(JobProgress job) test) {
    final gone = {
      for (final job in _jobs.jobTable)
        if ((job.state == JobState.done || job.state == JobState.error) &&
            test(job))
          job.id
    };
    if (gone.isEmpty) return;
    for (final id in gone) {
      _info.remove(id);
      _errors.remove(id);
      _confirming.remove(id);
    }
    _jobs.jobTable.removeWhere((job) => gone.contains(job.id));
  }
}
