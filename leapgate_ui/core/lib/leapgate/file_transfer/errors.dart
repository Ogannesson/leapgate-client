// Why a file operation failed (FT2, `LEAPGATE.md` §10.15). The types above the line are the
// step 0 contract: the panes, the queue and the dialogs map [FtReason] to the copy of 02 §2.5.
// Coder A appends below it what turns a `job_error` into an [FtError].
import 'dart:async';

import 'file_transfer_api.dart';

/// The reason codes of `leapgate_ft_reason`, plus [timeout], which Dart decides itself. [code]
/// is the JSON value; it is an interface, as C3's codes are.
enum FtReason {
  permissionDenied('permission_denied'),
  inUse('in_use'),
  notFound('not_found'),
  diskFull('disk_full'),
  fileTooLarge('file_too_large'),
  pathTooLong('path_too_long'),
  invalidName('invalid_name'),

  /// `args`: the name.
  invalidNameWindows('invalid_name_windows'),
  symlinkInPath('symlink_in_path'),
  oneWay('one_way'),

  /// `args`: the number of files this time, then the remote device's limit.
  tooManyFiles('too_many_files'),
  androidScope('android_scope'),

  /// Not an error: upstream skipped the whole single-file job.
  skipped('skipped'),

  /// Not recognized: the UI shows [FtError.text].
  other('other'),

  /// Dart's own: reading a remote folder, counting before a delete or reading empty folders got
  /// no answer in time. Rust never returns it.
  timeout('timeout');

  const FtReason(this.code);

  final String code;

  /// Unknown codes are [other].
  static FtReason parse(String? code) => values.firstWhere((r) => r.code == code,
      orElse: () => FtReason.other);
}

/// Where an error happened, as far as Dart knows (§10.15 "错误来自哪一侧"): new folder, rename,
/// delete and reading a folder know their pane; a transfer job is [unknown].
enum FtSide {
  local('local'),
  remote('remote'),
  unknown('unknown');

  const FtSide(this.code);

  final String code;
}

/// A classified error: [args] go with [FtReason.invalidNameWindows] and [FtReason.tooManyFiles];
/// [text] is the original text, at most 200 characters.
class FtError {
  const FtError(this.reason, {this.args = const [], this.text = ''});

  const FtError.timeout() : this(FtReason.timeout);

  /// `leapgate_ft_reason`'s `{"reason","args","text"}`.
  factory FtError.fromJson(Map<String, dynamic> m) => FtError(
        FtReason.parse(m['reason'] as String?),
        args: [for (final a in m['args'] as List? ?? const []) '$a'],
        text: m['text'] as String? ?? '',
      );

  final FtReason reason;
  final List<String> args;
  final String text;
}

// ---- coder A ----

/// What the copied `FileFetcher` completes a remote read with when it gives up after 30 s
/// (`models/file_model.dart`, `_registerRemoteReadTask`).
const _kFetchTimeout = 'Failed to read dir, timeout';

/// What the file transfer models got back: a `job_error`'s `err`, or what a read or a wait for
/// Rust's answer ended with. A wait that ran out is [FtReason.timeout]; the rest goes to FT2.
/// [peerPlatform] is the peer info's `platform`.
FtError ftErrorOf(Object error,
    {required String peerPlatform, required FtSide side}) {
  if (error is TimeoutException || error == _kFetchTimeout) {
    return const FtError.timeout();
  }
  return fileTransferApi.reason('$error',
      peerPlatform: peerPlatform, side: side);
}
