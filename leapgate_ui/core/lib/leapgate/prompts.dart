import 'package:flutter/foundation.dart';

import 'file_transfer/errors.dart';
import 'session.dart';

/// Asks the user something in the middle of a flow and waits for the answer (03 §3.3 item 5).
/// Upstream builds these dialogs inside the models; here the models describe the question and
/// the app shows it. The app sets it on [AppCore.prompter].
abstract interface class Prompter {
  /// Shows [prompt] over the tab of [session] only, or over the home tab only when [session]
  /// is null (01 §4.5), and completes with the answer; null when it is closed without one.
  Future<T?> ask<T>(Prompt<T> prompt, {FFI? session});
}

/// A question whose answer is a [T]. The app shows one dialog per kind and writes the copy;
/// the fields carry only the data.
sealed class Prompt<T> {
  const Prompt();
}

// The copied file model's questions ([OverwritePrompt], [DeletePrompt], [RenamePrompt]) go
// with its `FileModel` and `FileController`: coder A removes them once the rewrite (M7a,
// `LEAPGATE.md` §10.15) uses the `Ft*` questions at the end of this file. [OverwriteChoice] and
// [OverwriteAnswer] stay.

/// A file being transferred already exists at the destination. Upstream:
/// `models/file_model.dart:178` (`overrideFileConfirm`), dialog at `:217-290`.
///
/// Closed without an answer (null) counts as cancel, as upstream's Esc does. Upstream could
/// also lose the dialog to a `dismissAll` from elsewhere and then read it as skip; nothing here
/// closes a question that way.
final class OverwritePrompt extends Prompt<OverwriteAnswer> {
  const OverwritePrompt({required this.path, required this.isIdentical});

  final String path;

  /// The two files are the same; upstream adds `identical_file_tip`.
  final bool isIdentical;
}

/// Upstream's dialog returns `true`, `null`, `false` for these three.
enum OverwriteChoice { overwrite, skip, cancel }

/// [forAll] is upstream's "Do this for all conflicts" box.
typedef OverwriteAnswer = ({OverwriteChoice choice, bool forAll});

enum DeleteKind {
  file,
  emptyDirectory,

  /// One file of a directory that is not empty, asked file by file; this one offers "for all".
  fileInDirectory,
}

/// Confirms deleting one item. Upstream: `models/file_model.dart:779`, `:814`
/// (`removeAction`), dialog at `:858-920`.
///
/// Closed without an answer (null) skips this file and asks about the next one. Upstream's Esc
/// is "cancel", and with "for all" ticked before it, that cancels the rest of the directory.
final class DeletePrompt extends Prompt<DeleteAnswer> {
  const DeletePrompt(
      {required this.kind,
      required this.path,
      this.index = 0,
      this.count = 1,
      this.forAll = false});

  final DeleteKind kind;
  final String path;

  /// Position among the files of the directory; upstream shows `index + 1/count` when there
  /// are more than one.
  final int index;
  final int count;

  /// How the "for all" box starts. Upstream keeps the last answer's box through one delete
  /// action, so the first file of the next directory starts with it.
  final bool forAll;
}

typedef DeleteAnswer = ({bool delete, bool forAll});

enum RenameError { alreadyExists, invalidName }

/// Asks for a new name and keeps asking until [check] passes. Upstream:
/// `models/file_model.dart:952-1015` (`renameAction`). Answers the new name as typed; an empty
/// or unchanged name is the caller's to ignore, as upstream does.
final class RenamePrompt extends Prompt<String> {
  const RenamePrompt(
      {required this.name, required this.isDirectory, required this.check});

  final String name;
  final bool isDirectory;

  /// Checked when the user submits; a non-null result is shown under the field.
  final RenameError? Function(String newName) check;
}

// ---- The file transfer view's questions (M7a step 0, `LEAPGATE.md` §10.15) ----
// Coder A asks them from the file transfer model; coder B draws them (`pages/files/
// file_dialogs.dart`) over the session tab. The copy is 02 §2.2 blocks I and J, §3.1.

/// What the replace confirmation says (02 block I, M7a-5).
enum FtOverwriteKind {
  /// "目标文件夹“‹路径›”中已有同名文件。"
  existing,

  /// Same size and modified time: one more line, and the focus starts on "跳过".
  identical,

  /// Only `‹name›.download` / `.digest` left by an unfinished transfer.
  tempOnly,

  /// Could not tell [existing] from [tempOnly] (an upload into a folder the remote pane does
  /// not show): the merged sentence.
  existingOrTemp,
}

/// A file of a transfer already exists at the destination. Closed without an answer (null)
/// counts as "取消传输", as upstream's Esc does. [OverwriteAnswer.forAll] is "对此次传输中的其他
/// 冲突执行相同操作".
final class FtOverwritePrompt extends Prompt<OverwriteAnswer> {
  const FtOverwritePrompt(
      {required this.name, required this.folder, required this.kind});

  /// The file's name, for the title.
  final String name;

  /// The destination folder, for the text.
  final String folder;
  final FtOverwriteKind kind;
}

/// What a delete confirmation shows (02 block J); the dialog follows [FtDeletePrompt.state].
sealed class FtDeleteState {
  const FtDeleteState();
}

/// "正在统计要删除的项目…", with "取消".
final class FtDeleteCounting extends FtDeleteState {
  const FtDeleteCounting();
}

enum FtDeleteKind {
  file,
  emptyFolder,

  /// One folder with files, or several items: [FtDeleteReady.files] and [FtDeleteReady.bytes].
  contents,
  link,
}

final class FtDeleteReady extends FtDeleteState {
  const FtDeleteReady(
      {required this.kind,
      required this.name,
      this.items = 1,
      this.files = 0,
      this.bytes = 0});

  final FtDeleteKind kind;

  /// The item's name when [items] is 1.
  final String name;
  final int items;
  final int files;
  final int bytes;
}

/// "无法统计“‹文件夹名›”中的文件。‹原因›。", with "重试" ([FtDeletePrompt.retry]) and "取消".
final class FtDeleteCountFailed extends FtDeleteState {
  const FtDeleteCountFailed({required this.folder, required this.error});

  final String folder;
  final FtError error;
}

/// The remote device's file count limit: "最多 ‹limit› 个，“‹folder›”中有 ‹count› 个文件", with
/// "关闭".
final class FtDeleteOverLimit extends FtDeleteState {
  const FtDeleteOverLimit(
      {required this.folder, required this.limit, required this.count});

  final String folder;
  final int limit;
  final int count;
}

/// Deleting asks once (R2-Q23). Answers true for "删除"; null (closed, "取消", "关闭") deletes
/// nothing and stops counting.
final class FtDeletePrompt extends Prompt<bool> {
  const FtDeletePrompt(
      {required this.isRemote, required this.state, required this.retry});

  /// "将从远程设备上删除…" or "…本机…".
  final bool isRemote;
  final ValueListenable<FtDeleteState> state;

  /// Counts again after [FtDeleteCountFailed]; [state] goes back to [FtDeleteCounting].
  final VoidCallback retry;
}

enum FtNameError {
  /// Holds a character the destination's system refuses: on Windows `\ / : * ? " < > |`,
  /// elsewhere `/`.
  invalidChars,

  /// The folder already shows an item with that name.
  alreadyExists,
}

/// "新建文件夹": answers the name made, null when cancelled. [check] runs as the user types;
/// [submit] makes the folder and completes with null when it was made, or why not, which the
/// dialog shows ("无法新建文件夹。‹原因›。") without closing.
final class FtNewFolderPrompt extends Prompt<String> {
  const FtNewFolderPrompt(
      {required this.isWindows, required this.check, required this.submit});

  /// The destination's name rules, for the [FtNameError.invalidChars] text.
  final bool isWindows;
  final FtNameError? Function(String name) check;
  final Future<FtError?> Function(String name) submit;
}

/// "重命名“‹名称›”": as [FtNewFolderPrompt]; "重命名" is off while the name is unchanged.
final class FtRenamePrompt extends Prompt<String> {
  const FtRenamePrompt(
      {required this.name,
      required this.isDirectory,
      required this.isWindows,
      required this.check,
      required this.submit});

  final String name;

  /// A file's name is selected up to its extension.
  final bool isDirectory;
  final bool isWindows;
  final FtNameError? Function(String name) check;
  final Future<FtError?> Function(String name) submit;
}

/// "断开文件传输？" with [unfinished] transfers (R2-Q28). Answers true for "断开".
final class FtDisconnectPrompt extends Prompt<bool> {
  const FtDisconnectPrompt(this.unfinished);

  final int unfinished;
}
