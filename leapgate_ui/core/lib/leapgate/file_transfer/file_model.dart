// 上游：flutter/lib/models/file_model.dart@bd9262397（改写：`FileModel`、`FileController` 两个类，其余在复制件 `models/file_model.dart`。上游这两个类改了，合并时人工移植到这里）
//
// The file transfer view's model (`LEAPGATE.md` §10.15, 10 §2.3). Against upstream: the panes
// say what they read and why it failed; remote folders are read one at a time; new folder,
// rename and delete wait for Rust's answer to their own request id; a delete is counted and
// confirmed once, links removed themselves; folders are sent with their hidden items; the sort
// is remembered on this device; the last folder is saved each time one opens.
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../common.dart';
import '../../consts.dart';
import '../../models/file_model.dart';
import '../../models/platform_model.dart';
import '../../utils/download_paths.dart';
import '../prompts.dart';
import '../session.dart';
import 'errors.dart';
import 'file_transfer_api.dart';
import 'jobs.dart';
import 'pane.dart';
import 'sort.dart';

/// Reading a remote folder (the copied `FileFetcher` has its own 30 s), counting before a
/// delete, reading empty folders, and each answer to a request (`LEAPGATE.md` §10.15).
const _kTimeout = Duration(seconds: 30);

/// This device's paths are Windows paths. `FileController.isWindows` is the pane's.
final _localWindows = isWindows;

/// A remote read for a folder another open replaced before its turn: never sent.
class _Superseded {
  const _Superseded();
}

/// The file transfer model of one session (upstream `FileModel`). Every session has one; only a
/// `ConnType.fileTransfer` session uses it.
class FileModel implements FileTransferModel {
  FileModel(this.parent) {
    getSessionID = () => parent.target!.sessionId;
    getSessionNotices = () => parent.target?.notices;
    fileFetcher = FileFetcher(getSessionID);
    jobController = JobController(getSessionID, getSessionNotices);
    jobs = FileTransferJobs(parent, jobController);
    localController = FileController(isLocal: true, model: this);
    remoteController = FileController(isLocal: false, model: this);
  }

  final WeakReference<FFI> parent;
  late final FileFetcher fileFetcher;
  late final JobController jobController;
  @override
  late final FileTransferJobs jobs;
  late final FileController localController;
  late final FileController remoteController;
  late final GetSessionID getSessionID;
  late final GetSessionNotices getSessionNotices;
  SessionID get sessionId => getSessionID();

  @override
  FilePane get local => localController;
  @override
  FilePane get remote => remoteController;

  /// New folder, rename and delete waiting for the `job_done` / `job_error` of their id.
  final _requests = <int, Completer<Map<String, dynamic>>>{};

  /// Replace confirmations are asked one at a time (02 block I).
  Future<void> _confirmations = Future.value();

  Future<void> onReady() async {
    fileFetcher.beginRemoteSession();
    await localController.onReady();
    await remoteController.onReady();
  }

  Future<void> close() async {
    await localController.close();
    await remoteController.close();
  }

  Future<void> refreshAll() async {
    await localController._refresh();
    await remoteController._refresh();
  }

  void receiveFileDir(Map<String, dynamic> evt) {
    if (evt['is_local'] == "false") {
      // init remote home, the remote connection will send one dir event when established. TODO opt
      remoteController.initDirAndHome(evt);
    }
    fileFetcher.tryCompleteTask(evt['value'], evt['is_local']);
  }

  void receiveEmptyDirs(Map<String, dynamic> evt) {
    fileFetcher.tryCompleteEmptyDirsTask(evt['value'], evt['is_local']);
  }

  /// `job_done`: answers a request first; upstream refreshes both panes when a job ends
  /// (`models/model.dart:376-383`).
  Future<void> onJobDone(Map<String, dynamic> evt) async {
    _completeRequest(evt);
    if (await jobController.jobDone(evt)) {
      await refreshAll();
    }
  }

  // Upstream completes a pending recursive read before `jobError` (its comment: the delete job
  // is added after the read, so `jobError` can't find it and the read would wait for its
  // timeout). A remote folder read fails with id 0; only one is ever pending.
  void handleJobError(Map<String, dynamic> evt) {
    final id = int.tryParse(evt['id']?.toString() ?? '');
    if (id != null) {
      final err = evt['err']?.toString() ?? 'Unknown error';
      if (id == 0) {
        fileFetcher.tryCompleteRemoteTaskWithError(err);
      } else {
        fileFetcher.tryCompleteRecursiveTaskWithError(id, err);
      }
      _completeRequest(evt);
    }
    jobController.jobError(evt);
  }

  void _completeRequest(Map<String, dynamic> evt) {
    final id = int.tryParse(evt['id']?.toString() ?? '');
    if (id != null) _requests.remove(id)?.complete(evt);
  }

  /// Sends a request with [id] and waits for Rust's answer with the same id: null when it was
  /// done, otherwise the error (a `job_error`'s text, or a [TimeoutException]).
  Future<Object?> _request(int id, Future<void> Function() send) async {
    final answer = Completer<Map<String, dynamic>>();
    _requests[id] = answer;
    try {
      await send();
      final evt = await answer.future.timeout(_kTimeout);
      return evt.containsKey('err') ? '${evt['err']}' : null;
    } catch (e) {
      return e;
    } finally {
      if (identical(_requests[id], answer)) _requests.remove(id);
    }
  }

  /// Queued behind the confirmations before it; the event handler doesn't wait for the answer.
  Future<void> postOverrideFileConfirm(Map<String, dynamic> evt) async {
    final id = int.tryParse(evt['id']?.toString() ?? '');
    if (id == null || !jobController.hasTransferConflictJob(id)) {
      debugPrint("Ignore stale override confirm event: $evt");
      return;
    }
    jobs.setConfirming(id, true);
    final asked = _confirmations.then((_) async {
      try {
        if (parent.target?.closed != false) return;
        // The batch's remembered answer, as upstream's `FileDialogEventLoop.onPreConsume`.
        final batchId = jobController.transferConflictBatchId(id);
        bool? remembered;
        var skip = false;
        if (jobController.isTransferConflictRememberBatch(batchId)) {
          remembered =
              jobController.transferConflictRememberOverrideConfirm(batchId);
          skip = remembered == null;
        }
        await overrideFileConfirm(evt, overrideConfirm: remembered, skip: skip);
      } finally {
        jobs.setConfirming(id, false);
      }
    });
    _confirmations = asked.catchError((Object e) {
      debugPrint("Failed to confirm overwrite: $e");
    });
  }

  /// [overrideConfirm] and [skip] carry the batch's remembered answer: `true` replace, `null`
  /// with [skip] skip, `false` cancel the batch.
  Future<void> overrideFileConfirm(Map<String, dynamic> evt,
      {bool? overrideConfirm, bool skip = false}) async {
    final id = int.tryParse(evt['id']?.toString() ?? '') ?? 0;
    if (id == 0 || !jobController.hasTransferConflictJob(id)) {
      debugPrint("Ignore override confirm for inactive job: $evt");
      return;
    }
    var resp = overrideConfirm;
    // A remembered answer goes to Rust remembered too, as upstream's checkbox stays ticked.
    var remember = overrideConfirm != null || skip;
    if (!remember) {
      final answer = await parent.target?.ask(_overwritePrompt(id, evt));
      // Closed without an answer is upstream's cancel (Esc).
      remember = answer?.forAll ?? false;
      resp = switch (answer?.choice) {
        OverwriteChoice.overwrite => true,
        OverwriteChoice.skip => null,
        OverwriteChoice.cancel || null => false,
      };
    }
    if (!jobController.hasTransferConflictJob(id)) {
      debugPrint("Ignore override confirm result for inactive job: $evt");
      return;
    }
    if (resp == false) {
      await jobController.cancelTransferConflictBatch(id);
      return;
    }
    if (remember) jobController.rememberTransferConflictBatch(id, resp);
    await bind.sessionSetConfirmOverrideFile(
        sessionId: sessionId,
        actId: id,
        fileNum: int.parse(evt['file_num']),
        needOverride: resp == true,
        remember: remember,
        isUpload: evt['is_upload'] == "true");
  }

  /// M7a-5: the event has the job, one path and whether the two files are the same. The path
  /// of a download is this device's target file; of an upload, this device's source file.
  FtOverwritePrompt _overwritePrompt(int id, Map<String, dynamic> evt) {
    final path = '${evt['read_path']}';
    final identical = evt['is_identical'] == "true";
    if (evt['is_upload'] != "true") {
      final FtOverwriteKind kind;
      if (identical) {
        kind = FtOverwriteKind.identical;
      } else if (io.File(path).existsSync()) {
        kind = FtOverwriteKind.existing;
      } else if (io.File('$path.download').existsSync() ||
          io.File('$path.digest').existsSync()) {
        kind = FtOverwriteKind.tempOnly;
      } else {
        kind = FtOverwriteKind.existingOrTemp;
      }
      return FtOverwritePrompt(
          name: p.basename(path),
          folder: PathUtil.dirname(path, _localWindows),
          kind: kind);
    }
    final remote = remoteController;
    final target = _uploadTarget(id, path) ?? path;
    final folder = PathUtil.dirname(target, remote.isWindows);
    final name = PathUtil.split(target, remote.isWindows).last;
    var kind =
        identical ? FtOverwriteKind.identical : FtOverwriteKind.existingOrTemp;
    // The remote pane shows the destination: decide from what it read.
    if (!identical && remote._samePath(folder, remote.path)) {
      bool has(String n) =>
          remote.entries.any((e) => remote._sameName(e.name, n));
      if (has(name)) {
        kind = FtOverwriteKind.existing;
      } else if (remote.showHidden &&
          (has('$name.download') || has('$name.digest'))) {
        // Without hidden items the file itself may be there but not listed.
        kind = FtOverwriteKind.tempOnly;
      }
    }
    return FtOverwritePrompt(name: name, folder: folder, kind: kind);
  }

  /// An uploaded file's remote path: the job's destination plus the file's path under the
  /// job's source (10 §4.5).
  String? _uploadTarget(int id, String source) {
    final target = jobs.targetOf(id);
    final i = jobController.getJob(id);
    if (target == null || i < 0) return null;
    final local =
        _localWindows ? PathUtil.windowsContext : PathUtil.posixContext;
    final relative =
        local.relative(source, from: jobController.jobTable[i].jobName);
    if (relative == '.') return target;
    final remoteWindows = remoteController.isWindows;
    return PathUtil.join(
        target,
        PathUtil.convert(relative, _localWindows, remoteWindows),
        remoteWindows);
  }

  /// Dropped from the system's file manager: uploaded to [to] or the remote pane's folder.
  @override
  Future<void> uploadPaths(List<String> paths, {String? to}) async {
    final items = <Entry>[];
    for (final path in paths) {
      final type = io.FileSystemEntity.typeSync(path);
      if (type == io.FileSystemEntityType.notFound) continue;
      final dir = type == io.FileSystemEntityType.directory;
      var size = 0;
      if (!dir) {
        try {
          size = io.File(path).lengthSync();
        } catch (_) {}
      }
      items.add(Entry()
        ..entryType = dir ? 0 : 4
        ..name = p.basename(path)
        ..path = path
        ..size = size);
    }
    await localController.transfer(items, to: to);
  }
}

/// One pane (upstream `FileController`).
class FileController extends ChangeNotifier implements FilePane {
  FileController({required this.isLocal, required this.model});

  @override
  final bool isLocal;
  final FileModel model;

  FFI? get _session => model.parent.target;
  SessionID get sessionId => model.sessionId;
  JobController get jobController => model.jobController;
  FileController get _other =>
      isLocal ? model.remoteController : model.localController;

  var _home = '';
  var _directory = FileDirectory();
  final _history = <String>[];
  late FileSort _sort = loadFileSort(isLocal: isLocal);
  var _selection = <Entry>[];
  var _showHidden = false;
  ({String path, DateTime since})? _reading;
  ({String path, FtError error})? _openError;

  /// Incremented for each folder opened; only the latest one's result applies.
  int _directoryRequestGeneration = 0;

  /// The last read of "此电脑" on the remote side, for the root drop-down.
  List<Entry>? _drives;

  /// The remote read waiting for the one in flight, and the end of the line.
  ({
    String path,
    bool hidden,
    bool forOpen,
    Future<FileDirectory> result
  })? _remoteNext;
  Future<void> _remoteTail = Future.value();

  @override
  bool get isWindows => isLocal
      ? _localWindows
      : _session?.ffiModel.pi.platform == kPeerPlatformWindows;

  @override
  String get path => _directory.path;

  @override
  List<Entry> get entries => _directory.entries;

  @override
  bool get isThisPc => isWindows && path == '/';

  @override
  bool get canGoBack => _history.any((h) => h.isNotEmpty && h != path);

  @override
  bool get canGoUp =>
      path.isNotEmpty && !isThisPc && (isWindows || path != '/');

  @override
  ({String path, DateTime since})? get reading => _reading;

  @override
  ({String path, FtError error})? get openError => _openError;

  @override
  void dismissOpenError() {
    _openError = null;
    notifyListeners();
  }

  @override
  bool get showHidden => _showHidden;

  @override
  void setShowHidden(bool value) {
    _showHidden = value;
    notifyListeners();
    refresh();
  }

  @override
  FileSort get sort => _sort;

  @override
  void setSort(FileSort value) {
    _sort = value;
    _directory.entries = sortEntries(_directory.entries, value);
    notifyListeners();
    unawaited(saveFileSort(value, isLocal: isLocal));
  }

  @override
  List<Entry> get selection => _selection;

  @override
  void select(Iterable<Entry> entries) {
    _selection = entries.where((e) => !e.isDrive).toList();
    notifyListeners();
  }

  @override
  bool get canRename =>
      isLocal || versionCmp(_session?.ffiModel.pi.version ?? '', '1.3.0') >= 0;

  bool _sameName(String a, String b) =>
      isWindows ? a.toLowerCase() == b.toLowerCase() : a == b;

  bool _samePath(String a, String b) =>
      (isWindows ? PathUtil.windowsContext : PathUtil.posixContext)
          .equals(a, b);

  FtError _error(Object error) => error is FtError
      ? error
      : ftErrorOf(error,
          peerPlatform: _session?.ffiModel.pi.platform ?? '',
          side: isLocal ? FtSide.local : FtSide.remote);

  /// Upstream: the current folder, the last one opened on this device, then the home folder;
  /// once more after a second. Only the last try of all shows its error.
  Future<void> onReady() async {
    if (isLocal) {
      _home = await bind.mainGetHomeDir();
    }
    _showHidden = (await bind.sessionGetPeerOption(
            sessionId: sessionId,
            name: isLocal ? "local_show_hidden" : "remote_show_hidden"))
        .isNotEmpty;

    await Future.delayed(Duration(milliseconds: 100));

    final savedDir = await bind.sessionGetPeerOption(
        sessionId: sessionId, name: isLocal ? "local_dir" : "remote_dir");
    Future<bool> tryOpenReadyDirs({required bool showError}) async {
      final dirs = <String>[
        ...{
          if (path.isNotEmpty) path,
          if (savedDir.isNotEmpty) savedDir,
          _home,
        }
      ];
      for (var i = 0; i < dirs.length; i++) {
        final error = await _openDirectoryPath(dirs[i],
            isBack: true, showError: showError && i == dirs.length - 1);
        if (error == null) return true;
      }
      return false;
    }

    if (await tryOpenReadyDirs(showError: false)) return;
    // The peer may become ready during the reconnect delay, so retry the
    // same candidates instead of only retrying the default home directory.
    await Future.delayed(Duration(seconds: 1));
    await tryOpenReadyDirs(showError: true);
  }

  Future<void> close() async {
    // save config; an empty path would forget the folder of the last session
    final msgMap = <String, String>{
      if (path.isNotEmpty) isLocal ? "local_dir" : "remote_dir": path,
      isLocal ? "local_show_hidden" : "remote_show_hidden":
          _showHidden ? "Y" : "",
    };
    for (final msg in msgMap.entries) {
      await bind.sessionPeerOption(
          sessionId: sessionId, name: msg.key, value: msg.value);
    }
  }

  @override
  Future<FtError?> openDirectory(String path, {bool showError = true}) =>
      _openDirectoryPath(path, showError: showError);

  @override
  void refresh() => unawaited(_refresh());

  /// Reads the folder again: the one being opened, the one shown, or the one that failed to
  /// open first.
  Future<void> _refresh() async {
    final path =
        _reading?.path ?? (this.path.isNotEmpty ? this.path : _openError?.path);
    if (path != null) await _openDirectoryPath(path, isBack: true);
  }

  Future<FtError?> _openDirectoryPath(String path,
      {bool isBack = false, bool showError = true}) async {
    if (!isBack) {
      _pushHistory();
    }
    // process /C:\ -> C:\ on Windows
    if (isWindows && path.length > 1 && path[0] == '/') {
      path = path.substring(1);
      if (path[path.length - 1] != '\\') {
        path = "$path\\";
      }
    }
    final requestGeneration = ++_directoryRequestGeneration;
    _reading = (path: path, since: clock.now());
    notifyListeners();
    try {
      final fd = await _fetch(path, forOpen: true);
      if (requestGeneration != _directoryRequestGeneration) return null;
      _show(fd);
      return null;
    } catch (e) {
      if (e is _Superseded) return null;
      final error = _error(e);
      if (requestGeneration != _directoryRequestGeneration) return error;
      debugPrint("Failed to openDirectory $path: $e");
      _reading = null;
      if (showError) _openError = (path: path, error: error);
      notifyListeners();
      return error;
    }
  }

  /// Shows [fd]: a refresh keeps the selection, another folder clears it and is saved as the
  /// last folder of this device.
  void _show(FileDirectory fd) {
    fd.format(isWindows);
    fd.entries = sortEntries(fd.entries, _sort);
    final refreshed = fd.path == path;
    if (refreshed) {
      final current = {for (final e in fd.entries) e.path: e};
      _selection = [
        for (final e in _selection)
          if (current[e.path]?.entryType == e.entryType) current[e.path]!
      ];
    } else {
      _selection = [];
    }
    _directory = fd;
    _reading = null;
    _openError = null;
    if (!isLocal && isThisPc) {
      _drives = fd.entries.where((e) => e.isDrive).toList();
    }
    notifyListeners();
    if (!refreshed) {
      unawaited(bind.sessionPeerOption(
          sessionId: sessionId,
          name: isLocal ? "local_dir" : "remote_dir",
          value: fd.path));
    }
  }

  Future<FileDirectory> _fetch(String path, {bool forOpen = false}) async {
    if (!isLocal) return _readRemote(path, _showHidden, forOpen: forOpen);
    final result = fileTransferApi.readLocalDir(path, showHidden: _showHidden);
    final directory = result.directory;
    if (directory == null) {
      throw result.error ?? FtError(FtReason.other, text: path);
    }
    return directory;
  }

  /// A remote read fails without saying which (10 §4.4), so one goes at a time; a read asked
  /// again while it still waits shares that wait. A read [forOpen] a folder that is no longer
  /// the one being opened when its turn comes is not sent.
  Future<FileDirectory> _readRemote(String path, bool hidden,
      {required bool forOpen}) {
    final next = _remoteNext;
    if (next != null &&
        next.path == path &&
        next.hidden == hidden &&
        next.forOpen == forOpen) {
      return next.result;
    }
    late final Future<FileDirectory> result;
    result = _remoteTail.then((_) {
      if (identical(_remoteNext?.result, result)) _remoteNext = null;
      if (forOpen && _reading?.path != path) throw const _Superseded();
      return model.fileFetcher.fetchDirectory(path, false, hidden);
    });
    _remoteNext =
        (path: path, hidden: hidden, forOpen: forOpen, result: result);
    _remoteTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void _pushHistory() {
    if (_history.isNotEmpty && _history.last == path) {
      return;
    }
    _history.add(path);
  }

  @override
  void goHome() {
    if (isLocal) {
      openDirectory(_home);
      return;
    }
    // The remote device resolves an empty path to its own home folder.
    _home = "";
    openDirectory(_home);
  }

  @override
  void goBack() {
    if (_history.isEmpty) return;
    final path = _history.removeLast();
    if (path.isEmpty) return;
    if (this.path == path) {
      goBack();
      return;
    }
    unawaited(_openDirectoryPath(path, isBack: true));
  }

  @override
  void goUp() {
    if (!canGoUp) return;
    final parent = PathUtil.dirname(path, isWindows);
    // specially for C:\, D:\, goto '/'
    unawaited(_openDirectoryPath(parent == path ? '/' : parent));
  }

  @override
  Future<List<Entry>> drives() async {
    if (!isWindows) return const [];
    final cached = _drives;
    if (!isLocal && cached != null) return cached;
    try {
      final fd = await _fetch('/');
      fd.format(isWindows);
      final drives = sortEntries(
          fd.entries.where((e) => e.isDrive).toList(), kDefaultFileSort);
      if (!isLocal) _drives = drives;
      return drives;
    } catch (e) {
      debugPrint("Failed to read drives: $e");
      return const [];
    }
  }

  // TODO deprecated this
  void initDirAndHome(Map<String, dynamic> evt) {
    try {
      final fd = FileDirectory.fromJson(jsonDecode(evt['value']));
      final isHomeResponse =
          model.fileFetcher.isLikelyRemoteHomeResponse(fd.path);
      if (fd.id > 0) {
        final jobIndex = jobController.getJob(fd.id);
        if (jobIndex != -1) {
          final job = jobController.jobTable[jobIndex];
          var totalSize = 0;
          var fileCount = fd.entries.length;
          for (var element in fd.entries) {
            totalSize += element.size;
          }
          job.totalSize = totalSize;
          job.fileCount = fileCount;
          debugPrint("update receive details: ${fd.path}");
          jobController.jobTable.refresh();
        }
      } else if (_home.isEmpty && isHomeResponse) {
        _home = fd.path;
        debugPrint("init remote home: ${fd.path}");
        if (_directoryRequestGeneration == 0) {
          _show(fd);
        }
      }
    } catch (e) {
      debugPrint("initDirAndHome err=$e");
    }
  }

  /// Sends [items] to [to] or the other pane's folder, one job each, with hidden items
  /// (R2-Q22); never into "此电脑".
  @override
  Future<void> transfer(List<Entry> items, {String? to}) async {
    final other = _other;
    final folder = to ?? other.path;
    final otherWindows = other.isWindows;
    if (folder.isEmpty || (otherWindows && folder == '/')) return;

    // alias
    final isRemoteToLocal = !isLocal;
    final transferJobs = <(Entry, int)>[];
    for (final from in items.where((e) => !e.isDrive)) {
      final jobID = jobController.addTransferJob(from, isRemoteToLocal);
      model.jobs.addTransfer(jobID,
          target: PathUtil.join(folder, from.name, otherWindows),
          isFolder: from.isDirectory);
      // Keep this check before PathUtil.join: Rust does not receive the selected
      // root separately, and Web transfers bypass Rust validation.
      if (isRemoteToLocal &&
          !DownloadPaths.validName(from.name, windows: otherWindows)) {
        jobController.jobError({
          'id': '$jobID',
          'file_num': '0',
          'err': 'Invalid file name: ${from.name}',
        });
        model.jobs.setError(
            jobID,
            otherWindows
                ? FtError(FtReason.invalidNameWindows, args: [from.name])
                : const FtError(FtReason.invalidName));
        continue;
      }
      transferJobs.add((from, jobID));
    }
    jobController.registerTransferConflictBatch(transferJobs.map((j) => j.$2));
    for (final (from, jobID) in transferJobs) {
      bind.sessionSendFiles(
          sessionId: sessionId,
          actId: jobID,
          path: from.path,
          to: PathUtil.join(folder, from.name, otherWindows),
          fileNum: 0,
          includeHidden: true,
          isRemote: isRemoteToLocal,
          isDir: from.isDirectory);
    }

    final folders = transferJobs.where((j) => j.$1.isDirectory);
    if (isRemoteToLocal) {
      if (versionCmp(_session?.ffiModel.pi.version ?? '', '1.3.3') < 0) {
        for (final (_, jobID) in folders) {
          model.jobs.emptyFoldersNotCreated(jobID,
              const EmptyFoldersNotCreated(EmptyFoldersReason.peerTooOld));
        }
        return;
      }
      for (final (entry, jobID) in folders) {
        await _downloadEmptyDirectories(entry, jobID, folder);
      }
      return;
    }
    for (final (item, jobID) in folders) {
      final List<FileDirectory> emptyDirs;
      try {
        emptyDirs = await _readEmptyDirs(item.path);
      } catch (e) {
        _emptyDirsUnreadable(jobID, e);
        continue;
      }
      final root = PathUtil.dirname(item.path, isWindows);
      for (final dir in emptyDirs) {
        _createEmptyDir(
            jobID,
            PathUtil.getOtherSidePath(
                root, dir.path, isWindows, folder, otherWindows),
            true);
      }
    }
  }

  Future<void> _downloadEmptyDirectories(
      Entry entry, int jobID, String folder) async {
    final List<FileDirectory> emptyDirs;
    try {
      emptyDirs = await _readEmptyDirs(entry.path);
    } catch (e) {
      _emptyDirsUnreadable(jobID, e);
      return;
    }
    final localWindows = _other.isWindows;
    try {
      final localRoot = PathUtil.join(folder, entry.name, localWindows);
      final paths = emptyDirs
          .map((dir) => DownloadPaths.mapDirectory(
              entry.path, dir.path, localRoot,
              remoteWindows: isWindows, localWindows: localWindows))
          .toList();
      for (final path in paths) {
        await DownloadPaths.ensureNoLinks(folder, path);
      }
      for (final path in paths) {
        _createEmptyDir(jobID, path, false);
      }
    } on FormatException catch (err) {
      await bind.sessionCancelJob(sessionId: sessionId, actId: jobID);
      jobController.jobError({
        'id': '$jobID',
        'file_num': '0',
        'err': err.message,
      });
    }
  }

  void _emptyDirsUnreadable(int jobID, Object error) {
    debugPrint("Failed to read empty dirs of job $jobID: $error");
    model.jobs.emptyFoldersNotCreated(
        jobID, const EmptyFoldersNotCreated(EmptyFoldersReason.unreadable));
  }

  /// A remote device that can't read them answers nothing (M7a-7): that is the timeout.
  Future<List<FileDirectory>> _readEmptyDirs(String path) async {
    if (isLocal) {
      final res = await bind.sessionReadLocalEmptyDirsRecursiveSync(
          sessionId: sessionId, path: path, includeHidden: true);
      final List<dynamic> fdJsons = jsonDecode(res);
      return [for (final fd in fdJsons) FileDirectory.fromJson(fd)];
    }
    final tasks = model.fileFetcher.remoteEmptyDirsTasks;
    final task = tasks[path] ??= Completer<List<FileDirectory>>();
    try {
      await bind.sessionReadRemoteEmptyDirsRecursiveSync(
          sessionId: sessionId, path: path, includeHidden: true);
      return await task.future.timeout(_kTimeout);
    } finally {
      if (identical(tasks[path], task)) tasks.remove(path);
    }
  }

  /// Upstream `createDirWithRemote`, counting the folder for [jobID] once Rust says it was made.
  void _createEmptyDir(int jobID, String path, bool isRemote) {
    final id = JobController.jobID.next();
    unawaited(model
        ._request(
            id,
            () => bind.sessionCreateDir(
                sessionId: sessionId,
                actId: id,
                path: path,
                isRemote: isRemote))
        .then((error) {
      if (error == null) model.jobs.addFoldersMade(jobID);
    }));
  }

  FtNameError? _checkName(String name, {Entry? renaming}) {
    if (name.isEmpty) return null;
    if (!PathUtil.validName(name, isWindows)) return FtNameError.invalidChars;
    if (entries
        .any((e) => e.path != renaming?.path && _sameName(e.name, name))) {
      return FtNameError.alreadyExists;
    }
    return null;
  }

  Future<FtError?> _submit(Future<void> Function(int actId) send) async {
    final id = JobController.jobID.next();
    final error = await model._request(id, () => send(id));
    return error == null ? null : _error(error);
  }

  @override
  Future<void> newFolder() async {
    final folder = path;
    if (folder.isEmpty || isThisPc) return;
    await _session?.ask(FtNewFolderPrompt(
        isWindows: isWindows,
        check: _checkName,
        submit: (name) => _submit((id) => bind.sessionCreateDir(
            sessionId: sessionId,
            actId: id,
            path: PathUtil.join(folder, name, isWindows),
            isRemote: !isLocal))));
  }

  @override
  Future<void> rename(Entry entry) async {
    if (!canRename) return;
    await _session?.ask(FtRenamePrompt(
        name: entry.name,
        isDirectory: entry.isDirectory,
        isWindows: isWindows,
        check: (name) => _checkName(name, renaming: entry),
        submit: (name) => _submit((id) => bind.sessionRenameFile(
            sessionId: sessionId,
            actId: id,
            path: entry.path,
            newName: name,
            isRemote: !isLocal))));
  }

  /// R2-Q23: folders (not links) are counted while the confirmation shows, then everything is
  /// deleted file by file after one answer, each folder's empty folders last. Links are removed
  /// themselves (M7a-3).
  @override
  Future<void> delete(List<Entry> items) async {
    items = items.where((e) => !e.isDrive).toList();
    if (items.isEmpty) return;
    final folders = items.where((e) => e.isDirectory && !e.isLink).toList();
    final contents = <String, List<Entry>>{};
    final state = ValueNotifier<FtDeleteState>(const FtDeleteCounting());
    var asking = true;
    Future<void> count() async {
      state.value = const FtDeleteCounting();
      for (final folder in folders) {
        if (contents.containsKey(folder.path)) continue;
        try {
          final fd = await _readRecursive(folder.path);
          if (!asking) return;
          contents[folder.path] = fd.entries;
        } catch (e) {
          if (!asking) return;
          final error = _error(e);
          state.value =
              error.reason == FtReason.tooManyFiles && error.args.length == 2
                  ? FtDeleteOverLimit(
                      folder: folder.name,
                      limit: int.tryParse(error.args[1]) ?? 0,
                      count: int.tryParse(error.args[0]) ?? 0)
                  : FtDeleteCountFailed(folder: folder.name, error: error);
          return;
        }
      }
      state.value = _deleteReady(items, contents);
    }

    if (folders.isEmpty) {
      state.value = _deleteReady(items, contents);
    } else {
      unawaited(count());
    }
    final confirmed = await _session?.ask(FtDeletePrompt(
        isRemote: !isLocal, state: state, retry: () => unawaited(count())));
    // The remote side's count can't be called back: its answer is dropped.
    asking = false;
    if (confirmed != true || state.value is! FtDeleteReady) return;
    for (final item in items) {
      await _deleteItem(item, contents[item.path] ?? const []);
    }
    await _refresh();
  }

  FtDeleteReady _deleteReady(
      List<Entry> items, Map<String, List<Entry>> contents) {
    if (items.length == 1) {
      final item = items.single;
      if (item.isLink) {
        return FtDeleteReady(kind: FtDeleteKind.link, name: item.name);
      }
      if (item.isFile) {
        return FtDeleteReady(
            kind: FtDeleteKind.file,
            name: item.name,
            files: 1,
            bytes: item.size);
      }
      final files = contents[item.path] ?? const [];
      if (files.isEmpty) {
        return FtDeleteReady(kind: FtDeleteKind.emptyFolder, name: item.name);
      }
    }
    var files = 0, bytes = 0;
    for (final item in items) {
      if (item.isLink) continue;
      for (final file
          in item.isFile ? [item] : contents[item.path] ?? const <Entry>[]) {
        files++;
        bytes += file.size;
      }
    }
    return FtDeleteReady(
        kind: FtDeleteKind.contents,
        name: items.length == 1 ? items.single.name : '',
        items: items.length,
        files: files,
        bytes: bytes);
  }

  /// The files under [path] (upstream `fetchDirectoryRecursiveToRemove`, with the 30 s wait).
  Future<FileDirectory> _readRecursive(String path) async {
    final id = JobController.jobID.next();
    final tasks = model.fileFetcher.readRecursiveTasks;
    final task = tasks[id] = Completer<FileDirectory>();
    try {
      await bind.sessionReadDirToRemoveRecursive(
          sessionId: sessionId,
          actId: id,
          path: path,
          isRemote: !isLocal,
          showHidden: true);
      final fd = await task.future.timeout(_kTimeout);
      if (fd.path.isEmpty) {
        fd.path = path;
      }
      fd.format(isWindows);
      return fd;
    } finally {
      tasks.remove(id);
    }
  }

  Future<void> _deleteItem(Entry item, List<Entry> files) async {
    final isRemote = !isLocal;
    if (item.isLink || item.isFile) {
      final id = jobController.addDeleteFileJob(item, isRemote);
      final error = await model._request(
          id,
          () => item.isLink
              ? fileTransferApi.removeLink(sessionId,
                  actId: id,
                  path: item.path,
                  isRemote: isRemote,
                  isDirLink: item.entryType == 2)
              : bind.sessionRemoveFile(
                  sessionId: sessionId,
                  actId: id,
                  path: item.path,
                  isRemote: isRemote,
                  fileNum: 0));
      _requestFailed(id, error);
      return;
    }
    final id = jobController.addDeleteDirJob(item, isRemote, files.length);
    for (var i = 0; i < files.length; i++) {
      if (_stopped(id)) return;
      final error = await model._request(
          id,
          () => bind.sessionRemoveFile(
              sessionId: sessionId,
              actId: id,
              path: files[i].path,
              isRemote: isRemote,
              fileNum: i));
      if (_requestFailed(id, error)) return;
    }
    if (_stopped(id)) return;
    _history.removeWhere((element) => element.contains(item.path));
    await bind.sessionRemoveAllEmptyDirs(
        sessionId: sessionId, actId: id, path: item.path, isRemote: isRemote);
    // This device's empty folders go without an answer (`file_trait.rs` `remove_dir`); a
    // folder with files was done at its last file.
    if (isLocal && files.isEmpty) {
      jobController.updateJobStatus(id, state: JobState.done);
    }
  }

  /// Cancelled from its row, cut off by the connection (`FileTransferJobs.onConnectionChanged`),
  /// or removed. A file that could not be deleted does not stop the rest, as upstream.
  bool _stopped(int id) {
    final i = jobController.getJob(id);
    if (i < 0) return true;
    final err = jobController.jobTable[i].err;
    return err == 'cancel' || err == 'disconnected';
  }

  /// The row fails and the item stops when there was no answer, or the request could not go
  /// out; a `job_error` (a [String]) the copied `jobError` has already put on the row.
  bool _requestFailed(int id, Object? error) {
    if (error == null || error is String) return false;
    // Already ended by a cancel or the connection: keep that reason.
    if (_stopped(id)) return true;
    if (error is TimeoutException) {
      jobController.updateJobStatus(id, error: 'timeout');
      model.jobs.setError(id, const FtError.timeout());
    } else {
      jobController.updateJobStatus(id, error: '$error');
    }
    return true;
  }
}
