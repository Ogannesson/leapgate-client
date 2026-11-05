// The one place the file transfer view reaches the M7a exports (`LEAPGATE.md` §10.15). The file
// transfer models call [fileTransferApi] only; tests set a fake (`test/file_transfer_fakes.dart`).
// The calls the copied models make to block 1 (`bind.session*`) stay where they are.
import 'dart:convert';

import '../../common.dart';
import '../../models/file_model.dart';
import '../bridge.dart';
import 'errors.dart';

/// `leapgate_ft_read_local_dir`: the folder, or why it could not be read.
typedef LocalDirResult = ({FileDirectory? directory, FtError? error});

/// The exports of §10.15 as the file transfer models use them.
abstract interface class FileTransferApi {
  /// `leapgate_ft_reason` (FT2): [text] is a `job_error`'s `err`; [peerPlatform] is the peer
  /// info's `platform` as upstream has it (`Windows`, `Linux`, `Mac OS`, `Android`).
  FtError reason(String text,
      {required String peerPlatform, required FtSide side});

  /// `leapgate_ft_read_local_dir` (M7a-4): upstream's `session_read_local_dir_sync`, keeping
  /// the reason when the folder can't be read.
  LocalDirResult readLocalDir(String path, {required bool showHidden});

  /// `leapgate_ft_remove_link` (M7a-3): removes the link at [path] itself, never what it points
  /// to. The result comes as `job_done` / `job_error` with [actId] and file number 0.
  Future<void> removeLink(SessionID sessionId,
      {required int actId,
      required String path,
      required bool isRemote,
      required bool isDirLink});
}

/// Set by tests; the app keeps the default.
FileTransferApi fileTransferApi = const RustFileTransferApi();

/// Block 2 (`src/leapgate_ffi.rs`, "File transfer (M7a)").
class RustFileTransferApi implements FileTransferApi {
  const RustFileTransferApi();

  @override
  FtError reason(String text,
          {required String peerPlatform, required FtSide side}) =>
      FtError.fromJson(jsonDecode(lgBind.leapgateFtReason(
          text: text, peerPlatform: peerPlatform, side: side.code)));

  @override
  LocalDirResult readLocalDir(String path, {required bool showHidden}) {
    final m = jsonDecode(
            lgBind.leapgateFtReadLocalDir(path: path, showHidden: showHidden))
        as Map<String, dynamic>;
    if (m.containsKey('error')) {
      return (
        directory: null,
        error: FtError(FtReason.parse(m['reason'] as String?),
            text: m['error'] as String? ?? ''),
      );
    }
    return (directory: FileDirectory.fromJson(m), error: null);
  }

  @override
  Future<void> removeLink(SessionID sessionId,
          {required int actId,
          required String path,
          required bool isRemote,
          required bool isDirLink}) =>
      lgBind.leapgateFtRemoveLink(
          sessionId: sessionId,
          actId: actId,
          path: path,
          isRemote: isRemote,
          isDirLink: isDirLink);
}
