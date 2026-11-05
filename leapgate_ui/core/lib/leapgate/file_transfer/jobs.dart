// The transfer queue as the view shows it (02 §2.2 block H, §3.1, §3.2). The types above the
// line are the M7a step 0 contract (`LEAPGATE.md` §10.15): the queue panel and the tab marks
// (coder B) know only them. Coder A appends below it the model that derives the rows from the
// copied `JobController`'s job table.
import 'package:flutter/foundation.dart';

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
