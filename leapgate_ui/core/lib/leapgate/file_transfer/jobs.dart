// The transfer queue as the view shows it (02 §2.2 block H, §3.1, §3.2). The types above the
// line are the M7a step 0 contract (`LEAPGATE.md` §10.15) with M7b's additions (§10.17): the
// queue panel and the tab marks know only them. Below it is the model that derives the rows from
// the copied `JobController`'s job table.
import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/file_model.dart';
import '../../models/platform_model.dart';
import '../connection.dart';
import '../session.dart';
import 'errors.dart';
import 'file_transfer_api.dart';

enum FileJobDirection { upload, download, delete }

/// The states of a row.
enum FileJobStatus {
  /// Waiting for an earlier job in the same direction.
  queued,

  /// A folder job listing its files: count and total size not known yet.
  counting,
  inProgress,

  /// A replace confirmation is open for it.
  waitingConfirm,
  deleting,

  /// Paused by the user, left unfinished when the view or the window closed, or the peer ended
  /// the session; resumes with "继续".
  paused,

  /// The connection is down; it goes on by itself after reconnecting.
  interrupted,
  done,

  /// Done, but some files were not sent or skipped, or for a delete some items not deleted
  /// ([FileJobRow.unsent]). "清除已完成" leaves it (M7b-7).
  doneWithIssues,
  skipped,
  cancelled,
  failed,
}

/// Remarks on a row (02 §2.4.3, §2.4.7).
sealed class FileJobNote {
  const FileJobNote();
}

enum EmptyFoldersReason { peerTooOld, unreadable }

/// "空文件夹未创建：远程设备的版本过低 / 未能读取。" Neither case knows how many there were.
final class EmptyFoldersNotCreated extends FileJobNote {
  const EmptyFoldersNotCreated(this.reason);

  final EmptyFoldersReason reason;
}

/// The remote device is older than 1.4.2: resuming starts the current file over.
final class ResumeUnsupported extends FileJobNote {
  const ResumeUnsupported();
}

/// The current file was over 4 GiB: Rust dropped its temporary file and it starts over
/// (M7b-5, `restart_file`).
final class RestartFile extends FileJobNote {
  const RestartFile();
}

/// A file of a [FileJobStatus.doneWithIssues] row (02 block H "查看详情").
class FileJobUnsent {
  const FileJobUnsent(this.path, this.error, {this.skipped = false});

  /// From the row's top-level item, its name included ("项目资料\草稿.docx"): in this device's
  /// form for a transfer, the pane's for a delete.
  final String path;

  /// FT2's reason; [FtReason.skipped] when [skipped].
  final FtError error;

  /// Skipped by the user in a replace confirmation.
  final bool skipped;
}

/// 02 §2.5 "能否重试".
bool ftRetryable(FtError error) => switch (error.reason) {
      FtReason.permissionDenied ||
      FtReason.inUse ||
      FtReason.diskFull ||
      FtReason.disconnected ||
      FtReason.other =>
        true,
      _ => false,
    };

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
    this.unsent = const [],
    this.canPause = false,
    this.canRetry = false,
    this.canRetryUnsent = false,
  });

  /// Stays the same while the Rust job under the row changes (12 §4.1).
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

  /// With [FileJobStatus.doneWithIssues], all of them; "查看详情" shows the first 50 (12 §4.6).
  final List<FileJobUnsent> unsent;

  /// "暂停": a transfer under way, the remote device 1.4.2 or later.
  final bool canPause;

  /// "重试": a failed row whose reason can be retried (02 §2.5), or a delete that left items.
  final bool canRetry;

  /// "重试未传输的文件": a transfer with an unsent file whose reason can be retried (M7b-8).
  final bool canRetryUnsent;
}

/// The summary line. [active] counts counting, in progress and deleting rows.
typedef FileJobSummary = ({
  int active,
  int queued,
  int waitingConfirm,
  int failed,
  int paused,
  int interrupted,

  /// Rows "清除已完成" removes: done, skipped, cancelled (not done with issues, M7b-7).
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

  /// [FileJobRow.canPause]: the row is paused once Rust says so.
  void pause(int id);

  /// [FileJobRow.canRetry]: a transfer goes on from the file it failed at; a delete counts again
  /// and deletes what is still there.
  void retry(int id);

  /// [FileJobRow.canRetryUnsent]: each unsent file whose reason can be retried goes again under
  /// the same row (12 §4.3).
  void retryUnsent(int id);

  /// Takes a finished row out of the list; no file is touched.
  void remove(int id);
  void clearFinished();
}

// ---- the model ----

/// The speed is the progress bytes over this long (02 §2.2 block H).
const _kSpeedWindow = Duration(seconds: 10);

/// No time left is given while the speed is measured over less than this.
const _kSpeedSteady = Duration(seconds: 3);

/// The `err` of a delete the connection cut off.
const _kDisconnected = 'disconnected';

/// A row goes on by itself after this many `continue_from` in a row; the next one fails it
/// (12 M7b-3).
const _kMaxContinues = 20;

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

/// A job that ended in error: an upstream `job_error`, or Rust's `kept`, which can go on from
/// [resumeFrom] ("重试").
class _Failure {
  _Failure(this.text, this.error, [this.resumeFrom]);

  final String text;
  final FtError error;
  final int? resumeFrom;
}

/// A file a job did not send, or a delete did not delete.
class _Unsent {
  const _Unsent(this.path, this.error, {this.skipped = false});

  /// A transfer's: under the job's top-level item, `/` between the parts, empty for the item
  /// itself. A delete's: as [FileJobUnsent.path].
  final String path;
  final FtError error;
  final bool skipped;
}

/// What M7b keeps about a row (12 §4), by its key; a "重试未传输的文件" job has its own.
class _RowState {
  /// "恢复后的排队序号" (12 §4.4): the order the jobs of a direction run in.
  int? order;

  /// The job as a whole failed (M7a's first `job_error`, or `kept`).
  _Failure? failure;

  /// By [_Unsent.path], in the order they came.
  final unsent = <String, _Unsent>{};

  /// An upload paused in this session: it waits in Rust and goes on with `leapgate_ft_resume`.
  var soft = false;

  /// The last `restart_file` (M7b-5).
  var restartFile = false;

  /// The last `continue_from` and how many came one file after the other.
  ({int from, int count})? continued;

  /// Counts a delete again and deletes what is left.
  Future<void> Function()? retryDelete;

  /// For a "重试未传输的文件" job: the file it sends again.
  _Unsent? retrying;
}

/// [FileJobs] over the copied [JobController]'s table (`LEAPGATE.md` §10.15, §10.17): the rows
/// are derived from it each time they are read; only what the table lacks is kept here.
///
/// A row is one table entry. Its key, [FileJobRow.id], is the Rust job id it started with;
/// pausing, retrying and going on after a file failed give the entry a new Rust id (12 §4.1),
/// and every id it had finds it. A "重试未传输的文件" job is an entry of its own that no row shows.
class FileTransferJobs extends ChangeNotifier implements FileJobs {
  FileTransferJobs(this._parent, this._jobs) {
    _jobs.jobTable.listen((_) => _onTable());
  }

  final WeakReference<FFI> _parent;
  final JobController _jobs;

  /// By key, as the rest below unless said otherwise.
  final _info = <int, _JobInfo>{};

  /// A delete's files and their size, as counted before the confirmation: the job table has
  /// none for a single file and the folder entry's own size for a folder.
  final _deletes = <int, ({int files, int bytes})>{};

  /// Jobs a replace confirmation is open or queued for, by Rust id.
  final _confirming = <int>{};

  /// FT2's answer for the `err` it was asked about.
  final _errors = <int, ({String text, FtError error})>{};

  /// By Rust id.
  final _samples = <int, List<({DateTime at, int bytes})>>{};

  /// The row key of each Rust id a row had after its first.
  final _keys = <int, int>{};

  /// Rust ids a row had before its current one. Their `job_progress`, `job_done` and
  /// `job_error` are dropped: a download's peer may still send them after the pause.
  final _retired = <int>{};

  /// The replace confirmation open for a Rust id, closed when the id is retired.
  final _withdrawn = <int, ValueNotifier<bool>>{};
  final _rows = <int, _RowState>{};

  /// A "重试未传输的文件" job's Rust id → its row's key.
  final _parentOf = <int, int>{};

  /// Rust ids paused by the user in this session (12 §4.1).
  final _userPaused = <int>{};
  var _nextOrder = 0;

  FFI? get _session => _parent.target;

  int _key(int id) => _keys[id] ?? id;

  _RowState _state(int key) => _rows.putIfAbsent(key, _RowState.new);

  JobProgress? _jobOf(int key) {
    for (final job in _jobs.jobTable) {
      if (_key(job.id) == key) return job;
    }
    return null;
  }

  /// [id] is no longer the Rust id of its row: upstream's events for it are dropped.
  bool isRetired(int id) => _retired.contains(id);

  /// Becomes true when the replace confirmation for [id] is to close unanswered: the row was
  /// paused and Rust would drop the answer.
  ValueListenable<bool> confirmWithdrawn(int id) =>
      _withdrawn.putIfAbsent(id, () => ValueNotifier(false));

  /// A transfer started here: [target] is the top-level item's path at the destination.
  void addTransfer(int id, {required String target, required bool isFolder}) =>
      _info[id] = _JobInfo(target, isFolder);

  /// The destination path of a transfer started here or loaded from the last session.
  String? targetOf(int id) {
    final info = _info[_key(id)];
    if (info != null) return info.target;
    final i = _jobs.getJob(id);
    if (i < 0) return null;
    final job = _jobs.jobTable[i];
    // `loadLastJob` keeps the remote path in `remote` and the local one in `to`.
    final target = job.isRemoteToLocal ? job.to : job.remote;
    return target.isEmpty ? null : target;
  }

  /// A delete started here: [files] files of [bytes] in all go (0 for a link or empty folders).
  void addDelete(int id, {required int files, required int bytes}) {
    _deletes[id] = (files: files, bytes: bytes);
    notifyListeners();
  }

  /// What "重试" does for the delete [id].
  void setDeleteRetry(int id, Future<void> Function() retry) =>
      _state(id).retryDelete = retry;

  /// A file of the delete [id] could not be deleted: it is listed, and the delete goes on with
  /// the next one. [path] is [FileJobUnsent.path].
  void deleteFileFailed(int id, String path, String text,
      {required bool remote}) {
    final i = _jobs.getJob(id);
    if (i < 0) return;
    _state(id).unsent[path] = _Unsent(
        path, _classify(text, remote ? FtSide.remote : FtSide.local));
    // The copied `jobError` made the job failed.
    _jobs.jobTable[i].state = JobState.none;
    _jobs.jobTable.refresh();
  }

  /// The delete [id] went through all its files: done, also when some could not be deleted
  /// (02 §2.5 "已完成，‹k› 个项目未删除").
  void deleteEnded(int id) {
    if (_rows[id]?.unsent.isNotEmpty ?? false) {
      _jobs.updateJobStatus(id, state: JobState.done);
    }
  }

  void addFoldersMade(int id) {
    _info[_key(id)]?.foldersMade++;
    notifyListeners();
  }

  void emptyFoldersNotCreated(int id, EmptyFoldersNotCreated note) {
    _info[_key(id)]?.emptyFolders = note;
    notifyListeners();
  }

  /// [error] for the job's current `err`, decided by Dart (an invalid name, a timeout).
  void setError(int id, FtError error) {
    final i = _jobs.getJob(id);
    if (i < 0) return;
    _errors[_key(id)] = (text: _jobs.jobTable[i].err, error: error);
    notifyListeners();
  }

  /// After the job table took a `job_error` for [id]. The first one fails a transfer for good:
  /// a folder upload goes on with its other files and ends with a `job_done`, which must not
  /// make the row done.
  void onJobError(int id) {
    final i = _jobs.getJob(id);
    if (i < 0) return;
    final job = _jobs.jobTable[i];
    if (job.type == JobType.transfer &&
        job.state == JobState.error &&
        job.err != 'cancel') {
      _state(_key(id)).failure ??=
          _Failure(job.err, _classify(job.err, FtSide.unknown));
    }
  }

  /// The user skipped [path] (as [_Unsent.path]) of the job [id] in a replace confirmation.
  void fileSkipped(int id, String path) {
    _state(_key(id)).unsent[path] =
        _Unsent(path, const FtError(FtReason.skipped), skipped: true);
    notifyListeners();
  }

  /// A job Rust gives back with `auto_start` after reconnecting: true when the user paused it in
  /// this session, so it is not started (12 §4.1). Rust now has it as an ordinary waiting job.
  bool reloadPaused(int id) {
    if (!_userPaused.contains(id)) return false;
    _rows[_key(id)]?.soft = false;
    return true;
  }

  /// A `leapgate_ft` event of this session: the fields of §10.17 as a JSON object in `value`
  /// (upstream's `push_event` keeps the top-level `name` for the event's own).
  void onEvent(Map<String, dynamic> event) {
    final evt = jsonDecode('${event['value']}') as Map<String, dynamic>;
    final id = evt['id'] as int?;
    if (id == null) return;
    final i = _jobs.getJob(id);
    if (i < 0) return;
    final job = _jobs.jobTable[i];
    switch (evt['kind']) {
      case 'paused':
        _onPaused(job, evt);
      case 'kept':
        _onKept(job, evt);
      case 'continue_from':
        _onContinueFrom(job, evt);
      case 'file_failed':
        _state(_key(job.id)).unsent['${evt['name'] ?? ''}'] = _Unsent(
            '${evt['name'] ?? ''}',
            _classify('${evt['err'] ?? ''}', _side(evt['side'])));
        notifyListeners();
    }
  }

  static FtSide _side(Object? v) => switch (v) {
        'local' => FtSide.local,
        'remote' => FtSide.remote,
        _ => FtSide.unknown,
      };

  FtError _classify(String text, FtSide side) => ftErrorOf(text,
      peerPlatform: _session?.ffiModel.pi.platform ?? '', side: side);

  void _onPaused(JobProgress job, Map<String, dynamic> evt) {
    final st = _state(_key(job.id));
    final newId = evt['new_id'] as int? ?? job.id;
    _switchId(job, newId);
    _userPaused.add(newId);
    st.soft = evt['soft'] == true;
    st.restartFile = evt['restart_file'] == true;
    _jobs.updateJobStatus(newId, state: JobState.paused);
  }

  /// Rust stopped the job and dropped it; its temporary files stay. Not saved when the view
  /// closes (M7b-6).
  void _onKept(JobProgress job, Map<String, dynamic> evt) {
    final st = _state(_key(job.id));
    final text = '${evt['err'] ?? ''}';
    st.failure = _Failure(text, _classify(text, _side(evt['side'])),
        evt['resume_from'] as int? ?? job.fileNum);
    st.restartFile = evt['restart_file'] == true;
    _fail(job, text);
  }

  /// A file failed and Rust stopped the job: it goes on at once from the next one under a new
  /// id, unless that came one file after the other more than [_kMaxContinues] times.
  void _onContinueFrom(JobProgress job, Map<String, dynamic> evt) {
    final from = evt['resume_from'] as int?;
    if (from == null) return;
    final st = _state(_key(job.id));
    final last = st.continued;
    final count = last != null && from == last.from + 1 ? last.count + 1 : 1;
    st.continued = (from: from, count: count);
    if (count > _kMaxContinues) {
      final error =
          st.unsent.values.lastOrNull?.error ?? const FtError(FtReason.other);
      st.failure = _Failure(error.text, error, from);
      _fail(job, error.text);
      return;
    }
    if (job.fileCount > 0 && from >= job.fileCount) {
      _jobs.unregisterTransferConflictJob(job.id);
      _jobs.updateJobStatus(job.id, state: JobState.done);
      return;
    }
    _restart(job, from);
  }

  void _fail(JobProgress job, String text) {
    _jobs.unregisterTransferConflictJob(job.id);
    _jobs.updateJobStatus(job.id, error: text);
  }

  /// The table entry of a row takes the Rust id [id]; the batch of its replace confirmations
  /// goes with it, and one open for the old id closes.
  void _switchId(JobProgress job, int id) {
    final old = job.id;
    if (old == id) return;
    _keys[id] = _key(old);
    _retired.add(old);
    _jobs.registerTransferConflictBatch([id],
        batchId: _jobs.transferConflictBatchId(old));
    _jobs.unregisterTransferConflictJob(old);
    _confirming.remove(old);
    _withdrawn.remove(old)?.value = true;
    _samples.remove(old);
    _userPaused.remove(old);
    job.id = id;
  }

  /// The transfer of [job] again from its file [from], under a new id, at the end of its
  /// direction's line (12 §4.4).
  void _restart(JobProgress job, int from) {
    final target = targetOf(job.id);
    if (target == null) return;
    final key = _key(job.id);
    final id = JobController.jobID.next();
    _switchId(job, id);
    _state(key).order = _nextOrder++;
    job.err = '';
    _jobs.updateJobStatus(id, state: JobState.inProgress);
    unawaited(_addAndResume(id,
        path: job.jobName,
        to: target,
        fileNum: from,
        includeHidden: _info[key] != null || job.showHidden,
        isRemote: job.isRemoteToLocal));
  }

  /// As `loadLastJob` starts a job of the last session.
  Future<void> _addAndResume(int id,
      {required String path,
      required String to,
      required int fileNum,
      required bool includeHidden,
      required bool isRemote}) async {
    final s = _session;
    if (s == null) return;
    await bind.sessionAddJob(
        sessionId: s.sessionId,
        actId: id,
        path: path,
        to: to,
        fileNum: fileNum,
        includeHidden: includeHidden,
        isRemote: isRemote);
    await bind.sessionResumeJob(
        sessionId: s.sessionId, actId: id, isRemote: isRemote);
  }

  void setConfirming(int id, bool confirming) {
    if (!confirming) _withdrawn.remove(id);
    if (confirming ? _confirming.add(id) : _confirming.remove(id)) {
      notifyListeners();
    }
  }

  /// The session's connection changed: transfers under way show interrupted or paused; deletes
  /// under way fail for good (02 §2.4.7: deletes are not resumed), and their loops stop.
  void onConnectionChanged() {
    if (!_connected) {
      for (final job in _jobs.jobTable.toList()) {
        if (job.type != JobType.transfer &&
            (job.state == JobState.none || job.state == JobState.inProgress)) {
          _jobs.updateJobStatus(job.id, error: _kDisconnected);
        }
      }
    }
    notifyListeners();
  }

  void _onTable() {
    final now = clock.now();
    final live = <int>{};
    _assignOrders();
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
    _endRetries();
    notifyListeners();
  }

  /// A row's place in its direction's line is the order it first came in; it moves to the end
  /// when it goes on again (12 §4.4).
  void _assignOrders() {
    for (final job in _jobs.jobTable) {
      _state(_key(job.id)).order ??= _nextOrder++;
    }
  }

  /// The "重试未传输的文件" jobs of a row once they all ended: each file that went again is gone
  /// from the row's list, or back in it with why it failed this time (12 §4.3).
  void _endRetries() {
    final table = _jobs.jobTable;
    final byRow = <int, List<JobProgress>>{};
    for (final job in table) {
      final key = _parentOf[job.id];
      if (key != null) (byRow[key] ??= []).add(job);
    }
    final gone = <int>{};
    for (final MapEntry(key: key, value: retries) in byRow.entries) {
      if (retries.any(_isActive)) continue;
      final row = _state(key);
      for (final job in retries) {
        gone.add(job.id);
        final st = _rows.remove(job.id);
        _parentOf.remove(job.id);
        _info.remove(job.id);
        _errors.remove(job.id);
        final tried = st?.retrying;
        if (tried == null) continue;
        final left = _retried(job, st!, tried);
        if (left != null) row.unsent[tried.path] = left;
      }
    }
    if (gone.isNotEmpty) table.removeWhere((job) => gone.contains(job.id));
  }

  /// What a "重试未传输的文件" job left of [tried]: null when the file went.
  _Unsent? _retried(JobProgress job, _RowState st, _Unsent tried) {
    if (job.err == 'cancel') return tried;
    if (job.err == 'skipped' || st.unsent.values.any((u) => u.skipped)) {
      return _Unsent(tried.path, const FtError(FtReason.skipped),
          skipped: true);
    }
    final error = st.failure?.error ??
        st.unsent.values.firstOrNull?.error ??
        (job.state == JobState.error ? _errorOf(job, job.id) : null);
    return error == null ? null : _Unsent(tried.path, error);
  }

  static bool _isActive(JobProgress job) =>
      job.type == JobType.transfer &&
      (job.state == JobState.inProgress || job.state == JobState.none);

  int _order(JobProgress job) => _rows[_key(job.id)]?.order ?? 0;

  /// Rust works on one job in each direction at a time (02 §2.2 block H): the one first in line.
  /// It reports the progress of the waiting ones too (`io_loop.rs` `update_jobs_status`), so
  /// having had a `job_progress` says nothing.
  bool _isQueued(List<JobProgress> table, JobProgress job) {
    final order = _order(job);
    return table.any((j) =>
        !identical(j, job) &&
        _isActive(j) &&
        j.isRemoteToLocal == job.isRemoteToLocal &&
        _order(j) < order);
  }

  List<JobProgress> _retriesOf(List<JobProgress> table, int key) =>
      [for (final j in table) if (_parentOf[j.id] == key) j];

  @override
  List<FileJobRow> get rows {
    final table = _jobs.jobTable;
    _assignOrders();
    return [
      for (var i = 0; i < table.length; i++)
        if (!_parentOf.containsKey(table[i].id)) _row(table, i)
    ];
  }

  FileJobRow _row(List<JobProgress> table, int i) {
    final job = table[i];
    final key = _key(job.id);
    final st = _rows[key];
    final retries = _retriesOf(table, key);
    final status = _status(table, job, retries);
    final transfer = job.type == JobType.transfer;
    final info = _info[key];
    final done = status == FileJobStatus.done;
    final target = transfer ? targetOf(job.id) : null;
    final deleted = transfer ? null : _deletes[key];
    var fileCount = deleted?.files ?? job.fileCount;
    var totalBytes = deleted?.bytes ?? job.totalSize;
    var doneBytes = done ? totalBytes : job.finishedSize;
    var fileIndex = done
        ? fileCount
        : (job.recvJobRes ? job.fileNum + 1 : job.fileNum).clamp(0, fileCount);
    var rated = job;
    if (retries.isNotEmpty) {
      // The files going again, added up.
      fileCount = retries.length;
      fileIndex = retries.where((j) => !_isActive(j)).length;
      totalBytes = retries.fold(0, (n, j) => n + j.totalSize);
      doneBytes = retries.fold(0, (n, j) => n + j.finishedSize);
      rated = retries.where(_isActive).firstOrNull ?? job;
    }
    final rate = status == FileJobStatus.inProgress ? _rate(rated) : null;
    final error = status != FileJobStatus.failed
        ? null
        : job.err == _kDisconnected
            ? const FtError.disconnected()
            : _errorOf(job, key);
    final unsent = status == FileJobStatus.doneWithIssues
        ? [for (final u in st!.unsent.values) _shown(job, u)]
        : const <FileJobUnsent>[];
    final ended = const {
      FileJobStatus.done,
      FileJobStatus.doneWithIssues,
      FileJobStatus.skipped,
      FileJobStatus.cancelled,
    }.contains(status);
    return FileJobRow(
      id: key,
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
      doneBytes: doneBytes,
      totalBytes: totalBytes,
      fileIndex: fileIndex,
      fileCount: fileCount,
      folderCount: info?.foldersMade ?? 0,
      bytesPerSecond: rate?.speed,
      remaining: retries.isEmpty ? rate?.remaining : null,
      error: error,
      notes: [
        if (info?.emptyFolders != null) info!.emptyFolders!,
        if (transfer && status == FileJobStatus.paused && _resumeUnsupported)
          const ResumeUnsupported(),
        if (transfer && !ended && (st?.restartFile ?? false))
          const RestartFile(),
      ],
      unsent: unsent,
      canPause: transfer &&
          status == FileJobStatus.inProgress &&
          retries.isEmpty &&
          !_resumeUnsupported,
      canRetry: switch (status) {
        FileJobStatus.failed when transfer =>
          st?.failure?.resumeFrom != null && ftRetryable(error!),
        FileJobStatus.failed =>
          st?.retryDelete != null && ftRetryable(error!),
        FileJobStatus.doneWithIssues when !transfer =>
          st?.retryDelete != null && unsent.any((u) => ftRetryable(u.error)),
        _ => false,
      },
      canRetryUnsent: transfer &&
          status == FileJobStatus.doneWithIssues &&
          unsent.any((u) => !u.skipped && ftRetryable(u.error)),
    );
  }

  /// [u] as the details show it: a transfer's path in this device's form under the top-level
  /// item's name.
  FileJobUnsent _shown(JobProgress job, _Unsent u) {
    if (job.type != JobType.transfer) {
      return FileJobUnsent(u.path, u.error, skipped: u.skipped);
    }
    final path = u.path.isEmpty
        ? job.fileName
        : PathUtil.join(job.fileName, PathUtil.convert(u.path, false, isWindows),
            isWindows);
    return FileJobUnsent(path, u.error, skipped: u.skipped);
  }

  bool get _connected {
    final conn = _session?.connection;
    return conn == null || conn.stage == ConnStage.connected;
  }

  /// [retries]: the "重试未传输的文件" jobs of the row; while there are any they say what the row
  /// is doing.
  FileJobStatus _status(
      List<JobProgress> table, JobProgress job, List<JobProgress> retries) {
    final transfer = job.type == JobType.transfer;
    final st = _rows[_key(job.id)];
    if (retries.isEmpty) {
      switch (job.state) {
        case JobState.done:
        // Upstream's own values in `err`: a `job_error` "cancel" is not a failure, and FT2 is
        // not asked about either.
        case JobState.error when job.err == 'cancel':
          if (job.err == 'cancel') return FileJobStatus.cancelled;
          if (st?.failure != null) return FileJobStatus.failed;
          if (transfer && job.err == 'skipped') return FileJobStatus.skipped;
          if (st?.unsent.isNotEmpty ?? false) {
            return FileJobStatus.doneWithIssues;
          }
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
    }
    final work = retries.isEmpty ? [job] : retries;
    final conn = _session?.connection;
    if (conn != null && !_connected) {
      // Ended without retrying by itself: Rust keeps the job and resumes it on reconnecting.
      return conn.stage == ConnStage.failed && conn.retryCountdown == null
          ? FileJobStatus.paused
          : FileJobStatus.interrupted;
    }
    if (work.any((j) => _confirming.contains(j.id))) {
      return FileJobStatus.waitingConfirm;
    }
    final live = work.where(_isActive);
    if (live.isNotEmpty && live.every((j) => _isQueued(table, j))) {
      return FileJobStatus.queued;
    }
    if (retries.isEmpty &&
        (_info[_key(job.id)]?.isFolder ?? false) &&
        job.fileCount == 0 &&
        !job.recvJobRes) {
      return FileJobStatus.counting;
    }
    return FileJobStatus.inProgress;
  }

  /// A download's destination is this device, an upload's the remote one.
  bool _targetWindows(bool download) => download ? isWindows : _peerWindows;

  bool get _peerWindows =>
      _session?.ffiModel.pi.platform == kPeerPlatformWindows;

  bool get _resumeUnsupported {
    final version = _session?.ffiModel.pi.version ?? '';
    return version.isNotEmpty && versionCmp(version, '1.4.2') < 0;
  }

  ({double speed, Duration? remaining})? _rate(JobProgress job) {
    final s = _samples[job.id];
    if (s == null || s.length < 2) return null;
    // Up to now, so a transfer that stalls slows down instead of keeping its last speed.
    final now = clock.now();
    final windowStart = now.subtract(_kSpeedWindow);
    final from =
        s.lastWhere((x) => !x.at.isAfter(windowStart), orElse: () => s.first);
    final span = now.difference(from.at);
    if (span <= Duration.zero) return null;
    final speed = (s.last.bytes - from.bytes) * 1000 / span.inMilliseconds;
    final left = job.totalSize - job.finishedSize;
    return (
      speed: speed,
      remaining: span >= _kSpeedSteady && speed > 0 && left >= 0
          ? Duration(seconds: (left / speed).ceil())
          : null,
    );
  }

  FtError _errorOf(JobProgress job, int key) {
    final cached = _errors[key];
    if (cached != null && cached.text == job.err) return cached.error;
    final failure = _rows[key]?.failure;
    if (failure != null) return failure.error;
    final error = _classify(
        job.err,
        job.type == JobType.transfer
            ? FtSide.unknown
            : job.isRemoteToLocal
                ? FtSide.remote
                : FtSide.local);
    _errors[key] = (text: job.err, error: error);
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
        // Neither finished nor failed (M7b-7).
        case FileJobStatus.doneWithIssues:
          break;
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

  /// Stops the job and marks it cancelled; a delete stops before its next file. A row sending
  /// files again stops them, and they are back in its list.
  @override
  void cancel(int id) {
    final retries = _retriesOf(_jobs.jobTable, id);
    final row = _jobOf(id);
    final jobs = retries.isNotEmpty
        ? retries.where(_isActive).toList()
        : row == null
            ? const <JobProgress>[]
            : [row];
    for (final job in jobs) {
      if (job.type == JobType.transfer) _jobs.cancelJob(job.id);
      _jobs.updateJobStatus(job.id, error: 'cancel', state: JobState.done);
    }
  }

  @override
  void resume(int id) {
    final job = _jobOf(id);
    if (job != null && job.state == JobState.paused) _resume(job);
  }

  @override
  void resumeAll() {
    for (final job in _jobs.jobTable.toList()) {
      if (job.state == JobState.paused) _resume(job);
    }
  }

  /// At the end of its direction's line (12 §4.4).
  void _resume(JobProgress job) {
    final st = _state(_key(job.id));
    st.order = _nextOrder++;
    st.continued = null;
    _userPaused.remove(job.id);
    final s = _session;
    if (st.soft && s != null) {
      st.soft = false;
      _jobs.updateJobStatus(job.id, state: JobState.inProgress);
      unawaited(fileTransferApi.resume(s.sessionId, job.id));
      return;
    }
    _jobs.resumeJob(job.id);
  }

  @override
  void pause(int id) {
    final job = _jobOf(id);
    final s = _session;
    if (job == null || s == null || !_isActive(job)) return;
    _userPaused.add(job.id);
    unawaited(fileTransferApi.pause(s.sessionId, job.id));
  }

  @override
  void retry(int id) {
    final job = _jobOf(id);
    final st = _rows[id];
    if (job == null || st == null) return;
    _errors.remove(id);
    if (job.type != JobType.transfer) {
      final again = st.retryDelete;
      if (again == null) return;
      st.unsent.clear();
      job
        ..err = ''
        ..fileNum = 0
        ..state = JobState.none;
      _jobs.jobTable.refresh();
      unawaited(again());
      return;
    }
    final failure = st.failure;
    final from = failure?.resumeFrom;
    if (from == null || !ftRetryable(failure!.error)) return;
    st
      ..failure = null
      ..continued = null;
    _restart(job, from);
  }

  @override
  void retryUnsent(int id) {
    final job = _jobOf(id);
    final st = _rows[id];
    final target = job == null ? null : targetOf(job.id);
    if (job == null || st == null || target == null) return;
    final tries = [
      for (final u in st.unsent.values)
        if (!u.skipped && ftRetryable(u.error)) u
    ];
    if (tries.isEmpty) return;
    final download = job.isRemoteToLocal;
    final fromWindows = download ? _peerWindows : isWindows;
    final toWindows = _targetWindows(download);
    final hidden = _info[id] != null || job.showHidden;
    final sends = <({int id, String from, String to})>[];
    for (final u in tries) {
      st.unsent.remove(u.path);
      String under(String root, bool windows) => u.path.isEmpty
          ? root
          : PathUtil.join(root, PathUtil.convert(u.path, false, windows), windows);
      final from = under(job.jobName, fromWindows);
      final to = under(target, toWindows);
      final retry = _jobs.addTransferJob(Entry()..path = from, download);
      _parentOf[retry] = id;
      _state(retry).retrying = u;
      _info[retry] = _JobInfo(to, false);
      sends.add((id: retry, from: from, to: to));
    }
    _jobs.registerTransferConflictBatch(sends.map((s) => s.id));
    notifyListeners();
    for (final s in sends) {
      unawaited(_addAndResume(s.id,
          path: s.from,
          to: s.to,
          fileNum: 0,
          includeHidden: hidden,
          isRemote: download));
    }
  }

  @override
  void remove(int id) => _removeWhere((row) =>
      row.id == id &&
      (_finished.contains(row.status) ||
          row.status == FileJobStatus.doneWithIssues ||
          row.status == FileJobStatus.failed));

  @override
  void clearFinished() =>
      _removeWhere((row) => _finished.contains(row.status));

  static const _finished = {
    FileJobStatus.done,
    FileJobStatus.skipped,
    FileJobStatus.cancelled,
  };

  void _removeWhere(bool Function(FileJobRow row) test) {
    final gone = {
      for (final row in rows)
        if (test(row)) row.id
    };
    if (gone.isEmpty) return;
    final ids = {
      for (final job in _jobs.jobTable)
        if (gone.contains(_key(job.id))) job.id
    };
    for (final id in gone) {
      _info.remove(id);
      _deletes.remove(id);
      _errors.remove(id);
      _rows.remove(id);
    }
    _retired.removeWhere((id) => gone.contains(_key(id)));
    _keys.removeWhere((_, key) => gone.contains(key));
    _confirming.removeAll(ids);
    _userPaused.removeAll(ids);
    _jobs.jobTable.removeWhere((job) => ids.contains(job.id));
  }
}
