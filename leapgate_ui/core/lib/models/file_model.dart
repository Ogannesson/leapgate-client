// 上游：flutter/lib/models/file_model.dart@bd9262397（只删界面调用，不格式化；`FileModel`、`FileController` 改写到 `lib/leapgate/file_transfer/file_model.dart`；例外：`Entry` 读 `is_hidden` 的两行（FT1））
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/leapgate/file_transfer/file_model.dart';
import 'package:flutter_hbb/leapgate/notices.dart';
import 'package:flutter_hbb/utils/event_loop.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;

import 'platform_model.dart';

enum SortBy {
  name,
  type,
  modified,
  size;

  @override
  String toString() {
    final str = this.name.toString();
    return "${str[0].toUpperCase()}${str.substring(1)}";
  }
}

class JobID {
  int _count = 0;
  int next() {
    try {
      if (!isWeb) {
        String v = bind.mainGetCommonSync(key: 'transfer-job-id');
        return int.parse(v);
      }
    } catch (e) {
      debugPrint("Failed to get transfer job id: $e");
    }
    // Finally increase the count if on the web or if failed to get the id.
    _count++;
    return _count;
  }
}

typedef GetSessionID = SessionID Function();
typedef GetSessionNotices = SessionNotices? Function();
typedef ReadRemoteDirectory = Future<void> Function(
    SessionID sessionId, String path, bool includeHidden);

const _kRemoteReadDirTimeout = Duration(seconds: 30);
const _kRemoteSessionChangedError =
    'Remote directory read cancelled because the session changed';

class DirectoryData {
  final DirectoryOptions options;
  final FileDirectory directory;
  DirectoryData(this.directory, this.options);
}

const _kOneWayFileTransferError = 'one-way-file-transfer-tip';

class JobController {
  static final JobID jobID = JobID();
  final jobTable = List<JobProgress>.empty(growable: true).obs;
  final jobResultListener = JobResultListener<Map<String, dynamic>>();
  int _nextTransferConflictBatchId = 1;
  final Map<int, int> _transferConflictJobToBatch = {};
  int? _transferConflictRememberBatchId;
  bool? _transferConflictRememberOverrideConfirm;
  final GetSessionID getSessionID;
  final GetSessionNotices getSessionNotices;
  SessionID get sessionId => getSessionID();
  SessionNotices? get notices => getSessionNotices();
  int _lastTimeShowMsgbox = DateTime.now().millisecondsSinceEpoch;

  JobController(this.getSessionID, this.getSessionNotices);

  int getJob(int id) {
    return jobTable.indexWhere((element) => element.id == id);
  }

  void registerTransferConflictBatch(Iterable<int> jobIds, {int? batchId}) {
    final ids = jobIds.toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    batchId ??= _nextTransferConflictBatchId++;
    if (batchId >= _nextTransferConflictBatchId) {
      _nextTransferConflictBatchId = batchId + 1;
    }
    for (final jobId in ids) {
      _transferConflictJobToBatch[jobId] = batchId;
    }
  }

  int? transferConflictBatchId(int jobId) {
    return _transferConflictJobToBatch[jobId];
  }

  bool hasTransferConflictJob(int jobId) {
    return transferConflictBatchId(jobId) != null;
  }

  bool isTransferConflictRememberBatch(int? batchId) {
    return batchId != null && batchId == _transferConflictRememberBatchId;
  }

  bool? transferConflictRememberOverrideConfirm(int? batchId) {
    if (!isTransferConflictRememberBatch(batchId)) {
      return null;
    }
    return _transferConflictRememberOverrideConfirm;
  }

  void rememberTransferConflictBatch(int jobId, bool? overrideConfirm) {
    _transferConflictRememberBatchId = _transferConflictJobToBatch[jobId];
    _transferConflictRememberOverrideConfirm = overrideConfirm;
  }

  void unregisterTransferConflictJob(int jobId) {
    final batchId = _transferConflictJobToBatch.remove(jobId);
    if (batchId == null) {
      return;
    }
    if (!_transferConflictJobToBatch.containsValue(batchId)) {
      if (_transferConflictRememberBatchId == batchId) {
        _transferConflictRememberBatchId = null;
        _transferConflictRememberOverrideConfirm = null;
      }
    }
  }

  // return jobID
  int addTransferJob(Entry from, bool isRemoteToLocal) {
    final jobID = JobController.jobID.next();
    jobTable.add(JobProgress()
      ..type = JobType.transfer
      ..fileName = path.basename(from.path)
      ..jobName = from.path
      ..totalSize = from.size
      ..state = JobState.inProgress
      ..id = jobID
      ..isRemoteToLocal = isRemoteToLocal);
    return jobID;
  }

  int addDeleteFileJob(Entry file, bool isRemote) {
    final jobID = JobController.jobID.next();
    jobTable.add(JobProgress()
      ..type = JobType.deleteFile
      ..fileName = path.basename(file.path)
      ..jobName = file.path
      ..totalSize = file.size
      ..state = JobState.none
      ..id = jobID
      ..isRemoteToLocal = isRemote);
    return jobID;
  }

  int addDeleteDirJob(Entry file, bool isRemote, int fileCount) {
    final jobID = JobController.jobID.next();
    jobTable.add(JobProgress()
      ..type = JobType.deleteDir
      ..fileName = path.basename(file.path)
      ..jobName = file.path
      ..fileCount = fileCount
      ..totalSize = file.size
      ..state = JobState.none
      ..id = jobID
      ..isRemoteToLocal = isRemote);
    return jobID;
  }

  void tryUpdateJobProgress(Map<String, dynamic> evt) {
    try {
      int id = int.parse(evt['id']);
      // id = index + 1
      final jobIndex = getJob(id);
      if (jobIndex >= 0 && jobTable.length > jobIndex) {
        final job = jobTable[jobIndex];
        job.fileNum = int.parse(evt['file_num']);
        job.speed = double.parse(evt['speed']);
        job.finishedSize = int.parse(evt['finished_size']);
        job.recvJobRes = true;
        jobTable.refresh();
      }
    } catch (e) {
      debugPrint("Failed to tryUpdateJobProgress, evt: ${evt.toString()}");
    }
  }

  Future<bool> jobDone(Map<String, dynamic> evt) async {
    if (jobResultListener.isListening) {
      jobResultListener.complete(evt);
      // return;
    }
    int id = -1;
    int? fileNum = 0;
    double? speed = 0;
    try {
      id = int.parse(evt['id']);
    } catch (_) {}
    final jobIndex = getJob(id);
    if (jobIndex == -1) {
      unregisterTransferConflictJob(id);
      return true;
    }
    final job = jobTable[jobIndex];
    if (job.type == JobType.transfer &&
        job.isRemoteToLocal &&
        job.state == JobState.error) {
      return true;
    }
    job.recvJobRes = true;
    if (job.type == JobType.deleteFile) {
      job.state = JobState.done;
    } else if (job.type == JobType.deleteDir) {
      try {
        fileNum = int.tryParse(evt['file_num']);
      } catch (_) {}
      if (fileNum != null) {
        if (fileNum < job.fileNum) return true; // file_num can be 0 at last
        job.fileNum = fileNum;
        if (fileNum >= job.fileCount - 1) {
          job.state = JobState.done;
        }
      }
    } else {
      try {
        fileNum = int.tryParse(evt['file_num']);
        speed = double.tryParse(evt['speed']);
      } catch (_) {}
      if (fileNum != null) job.fileNum = fileNum;
      if (speed != null) job.speed = speed;
      job.state = JobState.done;
    }
    jobTable.refresh();
    if (job.state == JobState.done || job.state == JobState.error) {
      unregisterTransferConflictJob(id);
    }
    if (job.type == JobType.deleteDir) {
      return job.state == JobState.done;
    } else {
      return true;
    }
  }

  void jobError(Map<String, dynamic> evt) {
    final err = evt['err'].toString();
    final id = int.tryParse(evt['id']?.toString() ?? '');
    if (id == null) {
      debugPrint("Ignore job error with invalid id: $evt");
      return;
    }
    int jobIndex = getJob(id);
    if (jobIndex != -1) {
      final job = jobTable[jobIndex];
      if (job.state == JobState.done && job.err == "cancel") return;
      job.state = JobState.error;
      job.err = err;
      job.recvJobRes = true;
      if (job.type == JobType.transfer) {
        int? fileNum = int.tryParse(evt['file_num']);
        if (fileNum != null) job.fileNum = fileNum;
        if (err == "skipped") {
          job.state = JobState.done;
          job.finishedSize = job.totalSize;
        }
      } else if (job.type == JobType.deleteDir) {
        if (jobResultListener.isListening) {
          jobResultListener.complete(evt);
        }
        int? fileNum = int.tryParse(evt['file_num']);
        if (fileNum != null) job.fileNum = fileNum;
      } else if (job.type == JobType.deleteFile) {
        if (jobResultListener.isListening) {
          jobResultListener.complete(evt);
        }
      }
      jobTable.refresh();
      if (job.state == JobState.done || job.state == JobState.error) {
        unregisterTransferConflictJob(job.id);
      }
    } else {
      unregisterTransferConflictJob(id);
    }
    if (err == _kOneWayFileTransferError) {
      if (DateTime.now().millisecondsSinceEpoch - _lastTimeShowMsgbox > 3000) {
        final dm = notices;
        if (dm != null) {
          _lastTimeShowMsgbox = DateTime.now().millisecondsSinceEpoch;
          dm.add(SessionNotice(err));
        }
      }
    }
    debugPrint("jobError $evt");
  }

  void updateJobStatus(int id,
      {int? file_num, String? error, JobState? state}) {
    final jobIndex = getJob(id);
    if (jobIndex < 0) return;
    final job = jobTable[jobIndex];
    job.recvJobRes = true;
    if (file_num != null) {
      job.fileNum = file_num;
    }
    if (error != null) {
      job.err = error;
      job.state = JobState.error;
    }
    if (state != null) {
      job.state = state;
    }
    if (job.type == JobType.deleteFile && error == null) {
      job.state = JobState.done;
    }
    jobTable.refresh();
  }

  Future<void> cancelJob(int id) async {
    unregisterTransferConflictJob(id);
    await bind.sessionCancelJob(sessionId: sessionId, actId: id);
  }

  Future<void> cancelTransferConflictBatch(int jobId) async {
    final batchId = _transferConflictJobToBatch[jobId];
    final batchJobIds = batchId == null ? [jobId] : <int>[];
    if (batchId != null) {
      for (final entry in _transferConflictJobToBatch.entries) {
        if (entry.value == batchId) {
          batchJobIds.add(entry.key);
        }
      }
      for (final id in batchJobIds) {
        unregisterTransferConflictJob(id);
      }
    }
    final jobIdsToCancel = batchJobIds.toSet();
    for (final job in jobTable) {
      if (!jobIdsToCancel.contains(job.id) || job.state == JobState.done) {
        continue;
      }
      job.state = JobState.done;
      job.err = "cancel";
      job.recvJobRes = true;
    }
    jobTable.refresh();
    for (final id in batchJobIds) {
      try {
        await bind.sessionCancelJob(sessionId: sessionId, actId: id);
      } catch (e) {
        debugPrint("Failed to cancel transfer job $id in conflict batch: $e");
      }
    }
  }

  Future<void> loadLastJob(Map<String, dynamic> evt) async {
    debugPrint("load last job: $evt");
    Map<String, dynamic> jobDetail = json.decode(evt['value']);
    String remote = jobDetail['remote'];
    String to = jobDetail['to'];
    bool showHidden = jobDetail['show_hidden'];
    int fileNum = jobDetail['file_num'];
    bool isRemote = jobDetail['is_remote'];
    bool isAutoStart = jobDetail['auto_start'] == true;
    int currJobId = -1;
    if (isAutoStart) {
      // Ensure jobDetail['id'] exists and is an int
      if (jobDetail.containsKey('id') &&
          jobDetail['id'] != null &&
          jobDetail['id'] is int) {
        currJobId = jobDetail['id'];
      }
    }
    if (currJobId < 0) {
      // If id is missing or invalid, disable auto-start and assign a new job id
      isAutoStart = false;
      currJobId = JobController.jobID.next();
    }

    if (!isAutoStart) {
      if (!(isDesktop || isWebDesktop)) {
        // Don't add to job table if not auto start on mobile.
        // Because mobile does not support job list view now.
        return;
      }

      // Add to job table if not auto start on desktop.
      String fileName = path.basename(isRemote ? remote : to);
      final jobProgress = JobProgress()
        ..type = JobType.transfer
        ..fileName = fileName
        ..jobName = isRemote ? remote : to
        ..id = currJobId
        ..isRemoteToLocal = isRemote
        ..fileNum = fileNum
        ..remote = remote
        ..to = to
        ..showHidden = showHidden
        ..state = JobState.paused;
      jobTable.add(jobProgress);
    }
    registerTransferConflictBatch([currJobId]);
    await bind.sessionAddJob(
      sessionId: sessionId,
      isRemote: isRemote,
      includeHidden: showHidden,
      actId: currJobId,
      path: isRemote ? remote : to,
      to: isRemote ? to : remote,
      fileNum: fileNum,
    );

    if (isAutoStart) {
      await bind.sessionResumeJob(
          sessionId: sessionId, actId: currJobId, isRemote: isRemote);
    }
  }

  void resumeJob(int jobId) {
    final jobIndex = getJob(jobId);
    if (jobIndex != -1) {
      final job = jobTable[jobIndex];
      bind.sessionResumeJob(
          sessionId: sessionId, actId: job.id, isRemote: job.isRemoteToLocal);
      job.state = JobState.inProgress;
      jobTable.refresh();
    } else {
      debugPrint("jobId $jobId is not exists");
    }
  }

  void updateFolderFiles(Map<String, dynamic> evt) {
    // ret: "{\"id\":1,\"num_entries\":12,\"total_size\":1264822.0}"
    Map<String, dynamic> info = json.decode(evt['info']);
    int id = info['id'];
    int num_entries = info['num_entries'];
    double total_size = info['total_size'];
    final jobIndex = getJob(id);
    if (jobIndex != -1) {
      final job = jobTable[jobIndex];
      job.fileCount = num_entries;
      job.totalSize = total_size.toInt();
      jobTable.refresh();
    }
    debugPrint("update folder files: $info");
  }

  void clear() {
    jobTable.clear();
    _transferConflictJobToBatch.clear();
    _transferConflictRememberBatchId = null;
    _transferConflictRememberOverrideConfirm = null;
    jobResultListener.clear();
  }
}

class JobResultListener<T> {
  Completer<T>? _completer;
  Timer? _timer;
  final int _timeoutSecond = 5;

  bool get isListening => _completer != null;

  clear() {
    if (_completer != null) {
      _timer?.cancel();
      _timer = null;
      _completer!.completeError("Cancel manually");
      _completer = null;
      return;
    }
  }

  Future<T> start() {
    if (_completer != null) return Future.error("Already start listen");
    _completer = Completer();
    _timer = Timer(Duration(seconds: _timeoutSecond), () {
      if (!_completer!.isCompleted) {
        _completer!.completeError("Time out");
      }
      _completer = null;
    });
    return _completer!.future;
  }

  complete(T res) {
    if (_completer != null) {
      _timer?.cancel();
      _timer = null;
      _completer!.complete(res);
      _completer = null;
      return;
    }
  }
}

class _RemoteReadTask {
  final bool includeHidden;
  final Completer<FileDirectory> completer = Completer<FileDirectory>();
  final Completer<void> released = Completer<void>();
  late final Timer timer;

  _RemoteReadTask(this.includeHidden);
}

class FileFetcher {
  // Map<String,Completer<FileDirectory>> localTasks = {}; // now we only use read local dir sync
  final Map<String, _RemoteReadTask> _remoteReadTasks = {};
  Map<String, Completer<List<FileDirectory>>> remoteEmptyDirsTasks = {};
  Map<int, Completer<FileDirectory>> readRecursiveTasks = {};
  int _remoteSessionGeneration = 0;

  final GetSessionID getSessionID;
  final ReadRemoteDirectory _readRemoteDirectory;
  SessionID get sessionId => getSessionID();

  FileFetcher(this.getSessionID, {ReadRemoteDirectory? readRemoteDirectory})
      : _readRemoteDirectory = readRemoteDirectory ??
            ((sessionId, path, includeHidden) => bind.sessionReadRemoteDir(
                sessionId: sessionId,
                path: path,
                includeHidden: includeHidden));

  bool hasPendingRemoteRead(String path) => _remoteReadTasks.containsKey(path);

  bool isLikelyRemoteHomeResponse(String path) =>
      _remoteReadTasks.isEmpty ||
      (_remoteReadTasks.length == 1 &&
          hasPendingRemoteRead("") &&
          !hasPendingRemoteRead(path));

  void beginRemoteSession() {
    _remoteSessionGeneration++;
    final pendingTasks = _remoteReadTasks.entries.toList(growable: false);
    for (final entry in pendingTasks) {
      final task = entry.value;
      if (!_removeRemoteReadTask(entry.key, task)) continue;
      task.completer.completeError(StateError(_kRemoteSessionChangedError));
    }
  }

  _RemoteReadTask _registerRemoteReadTask(String path, bool includeHidden) {
    if (hasPendingRemoteRead(path)) {
      throw "Failed to registerReadTask, already have same read job";
    }
    final task = _RemoteReadTask(includeHidden);
    _remoteReadTasks[path] = task;
    task.timer = Timer(_kRemoteReadDirTimeout, () {
      if (!_removeRemoteReadTask(path, task)) return;
      task.completer.completeError("Failed to read dir, timeout");
    });
    return task;
  }

  bool _removeRemoteReadTask(String path, _RemoteReadTask task) {
    if (!identical(_remoteReadTasks[path], task)) return false;
    _remoteReadTasks.remove(path);
    task.timer.cancel();
    task.released.complete();
    return true;
  }

  bool _completeRemoteReadTask(String path, FileDirectory directory) {
    final task = _remoteReadTasks[path];
    if (task == null || !_removeRemoteReadTask(path, task)) return false;
    task.completer.complete(directory);
    return true;
  }

  Future<List<FileDirectory>> registerReadEmptyDirsTask(
      bool isLocal, String path) {
    // final jobs = isLocal?localJobs:remoteJobs; // maybe we will use read local dir async later
    final tasks = remoteEmptyDirsTasks; // bypass now
    if (tasks.containsKey(path)) {
      throw "Failed to registerReadEmptyDirsTask, already have same read job";
    }
    final c = Completer<List<FileDirectory>>();
    tasks[path] = c;

    Timer(Duration(seconds: 2), () {
      tasks.remove(path);
      if (c.isCompleted) return;
      c.completeError("Failed to read empty dirs, timeout");
    });
    return c.future;
  }

  Future<FileDirectory> registerReadRecursiveTask(int actID) {
    final tasks = readRecursiveTasks;
    if (tasks.containsKey(actID)) {
      throw "Failed to registerRemoveTask, already have same ReadRecursive job";
    }
    final c = Completer<FileDirectory>();
    tasks[actID] = c;

    Timer(Duration(seconds: 2), () {
      tasks.remove(actID);
      if (c.isCompleted) return;
      c.completeError("Failed to read dir, timeout");
    });
    return c.future;
  }

  tryCompleteEmptyDirsTask(String? msg, String? isLocalStr) {
    if (msg == null || isLocalStr == null) return;
    late final Map<String, Completer<List<FileDirectory>>> tasks;
    try {
      final map = jsonDecode(msg);
      final String path = map["path"];
      final List<dynamic> fdJsons = map["empty_dirs"];
      final List<FileDirectory> fds =
          fdJsons.map((fdJson) => FileDirectory.fromJson(fdJson)).toList();

      tasks = remoteEmptyDirsTasks;
      final completer = tasks.remove(path);

      completer?.complete(fds);
    } catch (e) {
      debugPrint("tryCompleteJob err: $e");
    }
  }

  tryCompleteTask(String? msg, String? isLocalStr) {
    if (msg == null || isLocalStr == null) return;
    try {
      final fd = FileDirectory.fromJson(jsonDecode(msg));
      if (fd.id > 0) {
        // fd.id > 0 is result for read recursive
        final completer = readRecursiveTasks.remove(fd.id);
        completer?.complete(fd);
        return;
      }
      if (isLocalStr == "false" && fd.path.isNotEmpty) {
        if (_completeRemoteReadTask(fd.path, fd)) {
          return;
        }
        // A Home request uses an empty path but returns its resolved path.
        if (isLikelyRemoteHomeResponse(fd.path)) {
          _completeRemoteReadTask("", fd);
        }
      }
    } catch (e) {
      debugPrint("tryCompleteJob err: $e");
    }
  }

  bool tryCompleteRemoteTaskWithError(String error) {
    if (_remoteReadTasks.length != 1) return false;
    final entry = _remoteReadTasks.entries.single;
    final task = entry.value;
    if (!_removeRemoteReadTask(entry.key, task)) return false;
    task.completer.completeError(error);
    return true;
  }

  // Complete a pending recursive read task with an error.
  // See FileModel.handleJobError() for why this is necessary.
  void tryCompleteRecursiveTaskWithError(int id, String error) {
    final completer = readRecursiveTasks.remove(id);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }

  Future<List<FileDirectory>> readEmptyDirs(
      String path, bool isLocal, bool showHidden) async {
    try {
      if (isLocal) {
        final res = await bind.sessionReadLocalEmptyDirsRecursiveSync(
            sessionId: sessionId, path: path, includeHidden: showHidden);

        final List<dynamic> fdJsons = jsonDecode(res);

        final List<FileDirectory> fds =
            fdJsons.map((fdJson) => FileDirectory.fromJson(fdJson)).toList();
        return fds;
      } else {
        await bind.sessionReadRemoteEmptyDirsRecursiveSync(
            sessionId: sessionId, path: path, includeHidden: showHidden);
        return registerReadEmptyDirsTask(isLocal, path);
      }
    } catch (e) {
      return Future.error(e);
    }
  }

  Future<FileDirectory> fetchDirectory(
      String path, bool isLocal, bool showHidden) async {
    try {
      if (isLocal) {
        final res = await bind.sessionReadLocalDirSync(
            sessionId: sessionId, path: path, showHidden: showHidden);
        final fd = FileDirectory.fromJson(jsonDecode(res));
        return fd;
      } else {
        final remoteSessionGeneration = _remoteSessionGeneration;
        final pendingTask = _remoteReadTasks[path];
        if (pendingTask != null) {
          if (pendingTask.includeHidden == showHidden) {
            return pendingTask.completer.future;
          }
          await pendingTask.released.future;
          if (remoteSessionGeneration != _remoteSessionGeneration) {
            throw StateError(_kRemoteSessionChangedError);
          }
          return fetchDirectory(path, isLocal, showHidden);
        }
        final task = _registerRemoteReadTask(path, showHidden);
        unawaited(Future<void>.sync(
                () => _readRemoteDirectory(sessionId, path, showHidden))
            .catchError((Object error, StackTrace stackTrace) {
          if (!_removeRemoteReadTask(path, task)) return;
          task.completer.completeError(error, stackTrace);
        }));
        return task.completer.future;
      }
    } catch (e) {
      return Future.error(e);
    }
  }

  Future<FileDirectory> fetchDirectoryRecursiveToRemove(
      int actID, String path, bool isLocal, bool showHidden) async {
    // TODO test Recursive is show hidden default?
    try {
      await bind.sessionReadDirToRemoveRecursive(
          sessionId: sessionId,
          actId: actID,
          path: path,
          isRemote: !isLocal,
          showHidden: showHidden);
      return registerReadRecursiveTask(actID);
    } catch (e) {
      return Future.error(e);
    }
  }
}

class FileDirectory {
  List<Entry> entries = [];
  int id = 0;
  String path = "";

  FileDirectory();

  FileDirectory.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    path = json['path'];
    json['entries'].forEach((v) {
      entries.add(Entry.fromJson(v));
    });
  }

  // generate full path for every entry , init sort style if need.
  format(bool isWindows, {SortBy? sort}) {
    for (var entry in entries) {
      entry.path = PathUtil.join(path, entry.name, isWindows);
    }
    if (sort != null) {
      changeSortStyle(sort);
    }
  }

  changeSortStyle(SortBy sort, {bool ascending = true}) {
    entries = _sortList(entries, sort, ascending);
  }

  clear() {
    entries = [];
    id = 0;
    path = "";
  }
}

class Entry {
  int entryType = 4;
  int modifiedTime = 0;
  String name = "";
  String path = "";
  int size = 0;
  bool isHidden = false;

  Entry();

  Entry.fromJson(Map<String, dynamic> json) {
    entryType = json['entry_type'];
    modifiedTime = json['modified_time'];
    name = json['name'];
    size = json['size'];
    isHidden = json['is_hidden'] ?? false;
  }

  bool get isFile => entryType > 3;

  bool get isDirectory => entryType < 3;

  bool get isDrive => entryType == 3;

  DateTime lastModified() {
    return DateTime.fromMillisecondsSinceEpoch(modifiedTime * 1000);
  }
}

enum JobState { none, inProgress, done, error, paused }

extension JobStateDisplay on JobState {
  String display() {
    switch (this) {
      case JobState.none:
        return translate("Waiting");
      case JobState.inProgress:
        return translate("Transfer file");
      case JobState.done:
        return translate("Finished");
      case JobState.error:
        return translate("Error");
      default:
        return "";
    }
  }
}

enum JobType { none, transfer, deleteFile, deleteDir }

class JobProgress {
  JobType type = JobType.none;
  JobState state = JobState.none;
  var recvJobRes = false;
  var id = 0;
  var fileNum = 0;
  var speed = 0.0;
  var finishedSize = 0;
  var totalSize = 0;
  var fileCount = 0;
  // [isRemote == true] means [remote -> local]
  // var isRemote = false;
  // to-do use enum
  var isRemoteToLocal = false;
  var jobName = "";
  var fileName = "";
  var remote = "";
  var to = "";
  var showHidden = false;
  var err = "";
  int lastTransferredSize = 0;

  double get percent =>
      totalSize > 0 ? (finishedSize.toDouble() / totalSize) : 0.0;
  String get percentText => '${(percent * 100).toStringAsFixed(0)}%';

  clear() {
    type = JobType.none;
    state = JobState.none;
    recvJobRes = false;
    id = 0;
    fileNum = 0;
    speed = 0;
    finishedSize = 0;
    jobName = "";
    fileName = "";
    fileCount = 0;
    remote = "";
    to = "";
    err = "";
  }

  String display() {
    if (type == JobType.transfer) {
      if (state == JobState.done && err == "cancel") {
        return translate("Cancel");
      }
      if (state == JobState.done && err == "skipped") {
        return translate("Skipped");
      }
    } else if (type == JobType.deleteFile) {
      if (err == "cancel") {
        return translate("Cancel");
      }
    }

    return state.display();
  }

  String getStatus() {
    int handledFileCount = recvJobRes ? fileNum + 1 : fileNum;
    if (handledFileCount >= fileCount) {
      handledFileCount = fileCount;
    }
    if (state == JobState.done) {
      handledFileCount = fileCount;
      finishedSize = totalSize;
    }
    final filesStr = "$handledFileCount/$fileCount files";
    final sizeStr = totalSize > 0 ? readableFileSize(totalSize.toDouble()) : "";
    final sizePercentStr = totalSize > 0 && finishedSize > 0
        ? "${readableFileSize(finishedSize.toDouble())} / ${readableFileSize(totalSize.toDouble())}"
        : "";
    if (type == JobType.deleteFile) {
      return display();
    } else if (type == JobType.deleteDir) {
      var res = '';
      if (state == JobState.done || state == JobState.error) {
        res = display();
      }
      if (filesStr.isNotEmpty) {
        if (res.isNotEmpty) {
          res += " ";
        }
        res += filesStr;
      }

      if (sizeStr.isNotEmpty) {
        if (res.isNotEmpty) {
          res += ", ";
        }
        res += sizeStr;
      }
      return res;
    } else if (type == JobType.transfer) {
      var res = "";
      if (state != JobState.inProgress && state != JobState.none) {
        res += display();
      }
      if (filesStr.isNotEmpty) {
        if (res.isNotEmpty) {
          res += ", ";
        }
        res += filesStr;
      }
      if (sizeStr.isNotEmpty && state != JobState.inProgress) {
        if (res.isNotEmpty) {
          res += ", ";
        }
        res += sizeStr;
      }
      if (sizePercentStr.isNotEmpty && state == JobState.inProgress) {
        if (res.isNotEmpty) {
          res += ", ";
        }
        res += sizePercentStr;
      }
      return res;
    }
    return '';
  }
}

class _PathStat {
  final String path;
  final DateTime dateTime;

  _PathStat(this.path, this.dateTime);
}

class PathUtil {
  static final windowsContext = path.Context(style: path.Style.windows);
  static final posixContext = path.Context(style: path.Style.posix);

  static String getOtherSidePath(String mainRootPath, String mainPath,
      bool isMainWindows, String otherRootPath, bool isOtherWindows) {
    final mainPathUtil = isMainWindows ? windowsContext : posixContext;
    final relativePath = mainPathUtil.relative(mainPath, from: mainRootPath);

    final names = mainPathUtil.split(relativePath);

    final otherPathUtil = isOtherWindows ? windowsContext : posixContext;

    String path = otherRootPath;

    for (var name in names) {
      path = otherPathUtil.join(path, name);
    }

    return path;
  }

  static String join(String path1, String path2, bool isWindows) {
    final pathUtil = isWindows ? windowsContext : posixContext;
    return pathUtil.join(path1, path2);
  }

  static List<String> split(String path, bool isWindows) {
    final pathUtil = isWindows ? windowsContext : posixContext;
    return pathUtil.split(path);
  }

  static String convert(String path, bool isMainWindows, bool isOtherWindows) {
    final mainPathUtil = isMainWindows ? windowsContext : posixContext;
    final otherPathUtil = isOtherWindows ? windowsContext : posixContext;
    return otherPathUtil.joinAll(mainPathUtil.split(path));
  }

  static String dirname(String path, bool isWindows) {
    final pathUtil = isWindows ? windowsContext : posixContext;
    return pathUtil.dirname(path);
  }

  static bool validName(String name, bool isWindows) {
    final unixFileNamePattern = RegExp(r'^[^/\x00]+$');
    final windowsFileNamePattern = RegExp(r'^[^<>:"/\\|?*]+$');
    final reg = isWindows ? windowsFileNamePattern : unixFileNamePattern;
    return reg.hasMatch(name);
  }
}

class DirectoryOptions {
  String home;
  bool showHidden;
  bool isWindows;

  DirectoryOptions(
      {this.home = "", this.showHidden = false, this.isWindows = false});

  clear() {
    home = "";
    showHidden = false;
    isWindows = false;
  }
}

class SelectedItems {
  final bool isLocal;
  final items = RxList<Entry>.empty(growable: true);

  SelectedItems({required this.isLocal});

  void add(Entry e) {
    if (e.isDrive) return;
    if (!items.contains(e)) {
      items.add(e);
    }
  }

  void remove(Entry e) {
    items.remove(e);
  }

  void clear() {
    items.clear();
  }

  void reconcile(List<Entry> entries) {
    if (items.isEmpty) return;
    final currentByPath = {for (final entry in entries) entry.path: entry};
    final reconciled = <Entry>[];
    for (final item in items) {
      final current = currentByPath[item.path];
      if (current != null && current.entryType == item.entryType) {
        reconciled.add(current);
      }
    }
    items
      ..clear()
      ..addAll(reconciled);
  }

  void selectAll(List<Entry> entries) {
    items.clear();
    items.addAll(entries);
  }

  static bool valid(RxList<Entry> items) {
    if (items.isNotEmpty) {
      // exclude DirDrive type
      return items.any((item) => !item.isDrive);
    }
    return false;
  }
}

// edited from [https://github.com/DevsOnFlutter/file_manager/blob/c1bf7f0225b15bcb86eba602c60acd5c4da90dd8/lib/file_manager.dart#L22]
List<Entry> _sortList(List<Entry> list, SortBy sortType, bool ascending) {
  if (sortType == SortBy.name) {
    // making list of only folders.
    final dirs = list
        .where((element) => element.isDirectory || element.isDrive)
        .toList();
    // sorting folder list by name.
    dirs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // making list of only flies.
    final files = list.where((element) => element.isFile).toList();
    // sorting files list by name.
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // first folders will go to list (if available) then files will go to list.
    return ascending
        ? [...dirs, ...files]
        : [...dirs.reversed.toList(), ...files.reversed.toList()];
  } else if (sortType == SortBy.modified) {
    // making the list of Path & DateTime
    List<_PathStat> pathStat = [];
    for (Entry e in list) {
      pathStat.add(_PathStat(e.name, e.lastModified()));
    }

    // sort _pathStat according to date
    pathStat.sort((b, a) => a.dateTime.compareTo(b.dateTime));

    // sorting [list] according to [_pathStat]
    list.sort((a, b) => pathStat
        .indexWhere((element) => element.path == a.name)
        .compareTo(pathStat.indexWhere((element) => element.path == b.name)));
    return ascending ? list : list.reversed.toList();
  } else if (sortType == SortBy.type) {
    // making list of only folders.
    final dirs = list.where((element) => element.isDirectory).toList();

    // sorting folders by name.
    dirs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // making the list of files
    final files = list.where((element) => element.isFile).toList();

    // sorting files list by extension.
    files.sort((a, b) => a.name
        .toLowerCase()
        .split('.')
        .last
        .compareTo(b.name.toLowerCase().split('.').last));
    return ascending
        ? [...dirs, ...files]
        : [...dirs.reversed.toList(), ...files.reversed.toList()];
  } else if (sortType == SortBy.size) {
    // create list of path and size
    Map<String, int> sizeMap = {};
    for (Entry e in list) {
      sizeMap[e.name] = e.size;
    }

    // making list of only folders.
    final dirs = list.where((element) => element.isDirectory).toList();
    // sorting folder list by name.
    dirs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // making list of only flies.
    final files = list.where((element) => element.isFile).toList();

    // creating sorted list of [_sizeMapList] by size.
    final List<MapEntry<String, int>> sizeMapList = sizeMap.entries.toList();
    sizeMapList.sort((b, a) => a.value.compareTo(b.value));

    // sort [list] according to [_sizeMapList]
    files.sort((a, b) => sizeMapList
        .indexWhere((element) => element.key == a.name)
        .compareTo(sizeMapList.indexWhere((element) => element.key == b.name)));
    return ascending
        ? [...dirs, ...files]
        : [...dirs.reversed.toList(), ...files.reversed.toList()];
  }
  return [];
}

/// Define a general queue which can accepts different dialog type.
///
/// [Visibility]
/// The `_FileDialogType` and `_DialogEvent` are invisible for other models.
enum FileDialogType { overwrite, unknown }

class _FileDialogEvent extends BaseEvent<FileDialogType, Map<String, dynamic>> {
  WeakReference<FileModel> fileModel;
  bool? _overrideConfirm;
  bool _skip = false;

  _FileDialogEvent(this.fileModel, super.type, super.data);

  void setOverrideConfirm(bool? confirm) {
    _overrideConfirm = confirm;
  }

  void setSkip(bool skip) {
    _skip = skip;
  }

  @override
  EventCallback<Map<String, dynamic>>? findCallback(FileDialogType type) {
    final model = fileModel.target;
    if (model == null) {
      return null;
    }
    switch (type) {
      case FileDialogType.overwrite:
        return (data) async {
          return await model.overrideFileConfirm(data,
              overrideConfirm: _overrideConfirm, skip: _skip);
        };
      default:
        debugPrint("Unknown event type: $type with $data");
        return null;
    }
  }
}

class FileDialogEventLoop
    extends BaseEventLoop<FileDialogType, Map<String, dynamic>> {
  int? _batchId;
  bool? _overrideConfirm;
  bool _skip = false;

  @override
  Future<void> onPreConsume(
      BaseEvent<FileDialogType, Map<String, dynamic>> evt) async {
    final event = evt as _FileDialogEvent;
    final model = event.fileModel.target;
    final jobId = int.tryParse(evt.data['id']?.toString() ?? '');
    final batchId = model == null || jobId == null
        ? null
        : model.jobController.transferConflictBatchId(jobId);
    final keepRemembered = model != null &&
        model.jobController.isTransferConflictRememberBatch(batchId);
    // The loop only preloads the remembered batch choice. The model updates it
    // after the user answers the current overwrite dialog.
    if (_batchId != batchId && !keepRemembered) {
      _batchId = batchId;
      _overrideConfirm = null;
      _skip = false;
    } else {
      _batchId = batchId;
    }
    if (keepRemembered) {
      _overrideConfirm =
          model.jobController.transferConflictRememberOverrideConfirm(batchId);
      _skip = _overrideConfirm == null;
    }
    event.setOverrideConfirm(_overrideConfirm);
    event.setSkip(_skip);
    debugPrint(
        "FileDialogEventLoop: consuming<jobId: ${evt.data['id']} batchId: $_batchId overrideConfirm: $_overrideConfirm, skip: $_skip>");
  }

  @override
  Future<void> onEventsClear() {
    _batchId = null;
    _overrideConfirm = null;
    _skip = false;
    return super.onEventsClear();
  }

  void setOverrideConfirm(bool? confirm) {
    _overrideConfirm = confirm;
  }

  void setSkip(bool skip) {
    _skip = skip;
  }
}
