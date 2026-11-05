// The one place the file transfer view reaches the M7a exports (`LEAPGATE.md` §10.15). The file
// transfer models call [fileTransferApi] only; tests set a fake (`test/file_transfer_fakes.dart`).
// The calls the copied models make to block 1 (`bind.session*`) stay where they are.
import '../../common.dart';
import '../../models/file_model.dart';
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

/// Block 2. The exports don't exist until the Rust lane is merged and the bridge regenerated
/// (`LEAPGATE.md` §10.15): every method throws until then.
// TODO(M7a 整合): call the block 2 exports; parse with FtError.fromJson and FileDirectory.fromJson.
class RustFileTransferApi implements FileTransferApi {
  const RustFileTransferApi();

  @override
  FtError reason(String text,
          {required String peerPlatform, required FtSide side}) =>
      throw UnimplementedError('leapgate_ft_reason');

  @override
  LocalDirResult readLocalDir(String path, {required bool showHidden}) =>
      throw UnimplementedError('leapgate_ft_read_local_dir');

  @override
  Future<void> removeLink(SessionID sessionId,
          {required int actId,
          required String path,
          required bool isRemote,
          required bool isDirLink}) =>
      throw UnimplementedError('leapgate_ft_remove_link');
}
