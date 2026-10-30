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

/// A file being transferred already exists at the destination. Upstream:
/// `models/file_model.dart:178` (`overrideFileConfirm`), dialog at `:217-290`.
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
final class DeletePrompt extends Prompt<DeleteAnswer> {
  const DeletePrompt(
      {required this.kind, required this.path, this.index = 0, this.count = 1});

  final DeleteKind kind;
  final String path;

  /// Position among the files of the directory; upstream shows `index + 1/count` when there
  /// are more than one.
  final int index;
  final int count;
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
