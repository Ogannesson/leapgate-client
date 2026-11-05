// What the file transfer view reads and calls (M7a step 0, `LEAPGATE.md` §10.15). Coder A's
// rewritten `FileModel` and `FileController` (`file_model.dart` here) implement it; the panes
// (coder C) and the shell (coder B) know only these types and test against fakes. Questions
// (new folder, rename, delete, replace) go to `appCore.prompter` from inside these calls.
import 'package:flutter/foundation.dart';

import '../../models/file_model.dart';
import '../session.dart';
import 'errors.dart';
import 'jobs.dart';

/// The list columns a pane sorts by (02 §2.2 block E). Folders and drives come first whatever
/// the column.
enum FileSortField { name, modified, type, size }

typedef FileSort = ({FileSortField field, bool ascending});

extension FileEntryKind on Entry {
  /// A directory link (`entry_type` 2, also a Windows junction) or a file link (5).
  bool get isLink => entryType == 2 || entryType == 5;
}

/// One side of a file transfer session: this device or the remote one. Notifies on every change
/// below.
abstract interface class FilePane implements Listenable {
  bool get isLocal;

  /// The side's paths are Windows paths: "此电脑" is `/`, names can't hold `\ / : * ? " < > |`.
  bool get isWindows;

  /// The folder shown; empty until a folder opened (the first open failed: [openError] is then
  /// shown in the list area with "转到主文件夹" and "重试").
  String get path;

  /// [path]'s entries with their full paths, sorted by [sort]; hidden ones only with
  /// [showHidden].
  List<Entry> get entries;

  /// The drive list of a Windows side (`/`): nothing can be sent into it or made in it.
  bool get isThisPc;

  bool get canGoBack;
  bool get canGoUp;

  /// A folder read in flight and since when; the pane shows "正在读取…" after about 0.5 s and dims
  /// [entries] while [reading]'s path is another folder.
  ({String path, DateTime since})? get reading;

  /// The last folder that would not open, until [dismissOpenError] or the next folder opens.
  ({String path, FtError error})? get openError;
  void dismissOpenError();

  /// Opens [path]; null when it opened. [showError] false leaves [openError] alone, for the
  /// path field, which shows the error under itself.
  Future<FtError?> openDirectory(String path, {bool showError = true});
  void goBack();
  void goUp();
  void goHome();

  /// Reads [path] again, keeping the selection.
  void refresh();

  /// The drives under "此电脑", for the root drop-down; remote reads go one at a time, so this
  /// may wait for the read in flight.
  Future<List<Entry>> drives();

  bool get showHidden;
  void setShowHidden(bool value);

  /// Remembered locally for each pane.
  FileSort get sort;
  void setSort(FileSort value);

  /// Cleared when another folder opens; drives are never selected.
  List<Entry> get selection;
  void select(Iterable<Entry> entries);

  /// Rename is offered (remote side: version 1.3.0 or later).
  bool get canRename;

  /// Sends [items] of this pane to the other pane's folder, or to [to] (a folder or drive row
  /// of the other pane it was dropped on). One job per item.
  Future<void> transfer(List<Entry> items, {String? to});

  /// Asks for a name, makes the folder in [path] and refreshes.
  Future<void> newFolder();
  Future<void> rename(Entry entry);

  /// Counts, asks once, deletes; links are removed themselves (§10.15 "删除").
  Future<void> delete(List<Entry> items);
}

/// The file transfer view of one session.
abstract interface class FileTransferModel {
  FilePane get local;
  FilePane get remote;
  FileJobs get jobs;

  /// Files and folders dropped from the system's file manager: uploaded to [to] (a folder row of
  /// the remote pane) or the remote pane's folder.
  Future<void> uploadPaths(List<String> paths, {String? to});
}

/// The file transfer model of [session], a `ConnType.fileTransfer` view.
FileTransferModel fileTransferOf(FFI session) => session.fileModel;
