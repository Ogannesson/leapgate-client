import 'package:flutter_hbb/leapgate/prompts.dart';

import '../../shell/tab_overlays.dart';

/// The dialogs of the file transfer view's questions (02 §2.2 blocks I and J, §3.1):
/// [FtOverwritePrompt], [FtDeletePrompt], [FtNewFolderPrompt], [FtRenamePrompt],
/// [FtDisconnectPrompt], shown over [scope] (the session's device ID). `ShellPrompter.ask`
/// calls it. Coder B's (`LEAPGATE.md` §10.15).
// TODO(M7a shell): coder B builds the dialogs and calls this from ShellPrompter.
Future<T?> showFilePrompt<T>(
        TabOverlays overlays, Object? scope, Prompt<T> prompt) async =>
    null;
