// The same file is in core/test and app/test (`LEAPGATE.md` §10.15, §10.17). A lane that needs
// more subclasses these in its own test file.
import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/leapgate/file_transfer/errors.dart';
import 'package:flutter_hbb/leapgate/file_transfer/file_transfer_api.dart';
import 'package:flutter_hbb/leapgate/file_transfer/jobs.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/models/file_model.dart';

/// [FileTransferApi] for tests: answers what the test sets and records what was asked.
class FakeFileTransferApi implements FileTransferApi {
  FtError Function(String text, String peerPlatform, FtSide side) onReason =
      (text, peerPlatform, side) => FtError(FtReason.other, text: text);
  LocalDirResult Function(String path, bool showHidden) onReadLocalDir =
      (path, showHidden) => (directory: FileDirectory()..path = path, error: null);
  final removedLinks = <({
    SessionID sessionId,
    int actId,
    String path,
    bool isRemote,
    bool isDirLink
  })>[];

  @override
  FtError reason(String text,
          {required String peerPlatform, required FtSide side}) =>
      onReason(text, peerPlatform, side);

  @override
  LocalDirResult readLocalDir(String path, {required bool showHidden}) =>
      onReadLocalDir(path, showHidden);

  @override
  Future<void> removeLink(SessionID sessionId,
      {required int actId,
      required String path,
      required bool isRemote,
      required bool isDirLink}) async {
    removedLinks.add((
      sessionId: sessionId,
      actId: actId,
      path: path,
      isRemote: isRemote,
      isDirLink: isDirLink
    ));
  }

  var eventsOn = false;
  final paused = <({SessionID sessionId, int id})>[];
  final resumed = <({SessionID sessionId, int id})>[];

  @override
  void turnOnEvents() => eventsOn = true;

  @override
  Future<void> pause(SessionID sessionId, int id) async =>
      paused.add((sessionId: sessionId, id: id));

  @override
  Future<void> resume(SessionID sessionId, int id) async =>
      resumed.add((sessionId: sessionId, id: id));
}

/// [FilePane] for page tests: the test sets the fields (then [notifyListeners]) and reads the
/// calls in [calls], each as `name` or `name:argument`.
class FakeFilePane extends ChangeNotifier implements FilePane {
  FakeFilePane({this.isLocal = true, this.isWindows = true});

  final calls = <String>[];

  @override
  final bool isLocal;
  @override
  bool isWindows;
  @override
  String path = '';
  @override
  List<Entry> entries = [];
  @override
  bool canGoBack = false;
  @override
  bool canGoUp = false;
  @override
  ({String path, DateTime since})? reading;
  @override
  ({String path, FtError error})? openError;
  @override
  bool showHidden = false;
  @override
  FileSort sort = (field: FileSortField.name, ascending: true);
  @override
  List<Entry> selection = [];
  @override
  bool canRename = true;
  List<Entry> driveList = [];

  /// What [openDirectory] answers.
  FtError? openResult;

  @override
  bool get isThisPc => isWindows && path == '/';

  @override
  void dismissOpenError() {
    calls.add('dismissOpenError');
    openError = null;
    notifyListeners();
  }

  @override
  Future<FtError?> openDirectory(String path, {bool showError = true}) async {
    calls.add('openDirectory:$path');
    return openResult;
  }

  @override
  void goBack() => calls.add('goBack');

  @override
  void goUp() => calls.add('goUp');

  @override
  void goHome() => calls.add('goHome');

  @override
  void refresh() => calls.add('refresh');

  @override
  Future<List<Entry>> drives() async => driveList;

  @override
  void setShowHidden(bool value) {
    calls.add('setShowHidden:$value');
    showHidden = value;
    notifyListeners();
  }

  @override
  void setSort(FileSort value) {
    calls.add('setSort:${value.field.name}:${value.ascending}');
    sort = value;
    notifyListeners();
  }

  @override
  void select(Iterable<Entry> entries) {
    selection = entries.where((e) => !e.isDrive).toList();
    notifyListeners();
  }

  @override
  Future<void> transfer(List<Entry> items, {String? to}) async =>
      calls.add('transfer:${items.map((e) => e.name).join(',')}'
          '${to == null ? '' : '>$to'}');

  @override
  Future<void> newFolder() async => calls.add('newFolder');

  @override
  Future<void> rename(Entry entry) async => calls.add('rename:${entry.name}');

  @override
  Future<void> delete(List<Entry> items) async =>
      calls.add('delete:${items.map((e) => e.name).join(',')}');
}

/// [FileJobs] for page tests: the test sets [rows], [summary], [unfinished].
class FakeFileJobs extends ChangeNotifier implements FileJobs {
  final calls = <String>[];

  @override
  List<FileJobRow> rows = [];
  @override
  FileJobSummary summary = (
    active: 0,
    queued: 0,
    waitingConfirm: 0,
    failed: 0,
    paused: 0,
    interrupted: 0,
    finished: 0,
    progress: null,
  );
  @override
  int unfinished = 0;

  @override
  void cancel(int id) => calls.add('cancel:$id');

  @override
  void resume(int id) => calls.add('resume:$id');

  @override
  void resumeAll() => calls.add('resumeAll');

  @override
  void pause(int id) => calls.add('pause:$id');

  @override
  void retry(int id) => calls.add('retry:$id');

  @override
  void retryUnsent(int id) => calls.add('retryUnsent:$id');

  @override
  void remove(int id) => calls.add('remove:$id');

  @override
  void clearFinished() => calls.add('clearFinished');
}

class FakeFileTransferModel implements FileTransferModel {
  FakeFileTransferModel({FakeFilePane? local, FakeFilePane? remote})
      : local = local ?? FakeFilePane(),
        remote = remote ?? FakeFilePane(isLocal: false);

  @override
  final FakeFilePane local;
  @override
  final FakeFilePane remote;
  @override
  final FakeFileJobs jobs = FakeFileJobs();
  final uploads = <({List<String> paths, String? to})>[];

  @override
  Future<void> uploadPaths(List<String> paths, {String? to}) async =>
      uploads.add((paths: paths, to: to));
}
