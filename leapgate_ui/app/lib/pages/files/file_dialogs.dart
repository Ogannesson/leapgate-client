import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/file_transfer/errors.dart';
import 'package:flutter_hbb/leapgate/prompts.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/tab_overlays.dart';
import '../../widgets/lg_banner.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_feedback.dart';
import '../../widgets/lg_form_dialog.dart';
import '../../widgets/lg_selection.dart';
import '../../widgets/lg_text_field.dart';
import 'formats.dart';

/// The file transfer view's questions that have a dialog here.
bool isFilePrompt(Prompt<Object?> prompt) =>
    prompt is FtOverwritePrompt ||
    prompt is FtDeletePrompt ||
    prompt is FtNewFolderPrompt ||
    prompt is FtRenamePrompt ||
    prompt is FtDisconnectPrompt;

/// The dialogs of the file transfer view's questions (02 §2.2 blocks I and J, §3.1):
/// [FtOverwritePrompt], [FtDeletePrompt], [FtNewFolderPrompt], [FtRenamePrompt],
/// [FtDisconnectPrompt], shown over [scope] (the session's device ID). `ShellPrompter.ask`
/// calls it. Coder B's (`LEAPGATE.md` §10.15).
Future<T?> showFilePrompt<T>(
  TabOverlays overlays,
  Object? scope,
  Prompt<T> prompt,
) {
  if (!isFilePrompt(prompt)) return Future.value(null);
  return overlays.show<T>(scope, (context, close) {
    void answer(Object? value) => close(value as T?);
    final p = prompt as Prompt<Object?>;
    final Widget dialog;
    if (p is FtOverwritePrompt) {
      dialog = _OverwriteDialog(prompt: p, close: answer);
    } else if (p is FtDeletePrompt) {
      dialog = _DeleteDialog(prompt: p, close: answer);
    } else if (p is FtNewFolderPrompt) {
      // These draw their own layer: Esc waits while the name is being submitted.
      return _NameDialog.newFolder(p, close: answer);
    } else if (p is FtRenamePrompt) {
      return _NameDialog.rename(p, close: answer);
    } else {
      dialog = _DisconnectDialog(
        unfinished: (p as FtDisconnectPrompt).unfinished,
        close: answer,
      );
    }
    return LgDialogScrim(onEscape: () => close(null), child: dialog);
  });
}

/// The short reason of 02 §2.5 for [error], with no full stop: for "无法新建文件夹。‹原因›。", a
/// queue row's "失败：‹原因›" and the delete count failure. [name] fills the sentences that name
/// the file; [toLocal] is the side the error can only happen on (the destination: this device
/// for a download), null when not known. An error no class fits shows Rust's text.
String ftReasonText(
  AppLocalizations l10n,
  FtError error, {
  required String name,
  bool? toLocal,
}) {
  String arg(int i, String fallback) =>
      error.args.length > i ? error.args[i] : fallback;
  return switch (error.reason) {
    FtReason.permissionDenied => l10n.ftReasonPermissionDenied,
    FtReason.inUse => l10n.ftReasonInUse,
    FtReason.notFound => l10n.ftReasonNotFound(name),
    FtReason.diskFull => switch (toLocal) {
      true => l10n.ftReasonDiskFullLocal,
      false => l10n.ftReasonDiskFullRemote,
      null => l10n.ftReasonDiskFull,
    },
    FtReason.fileTooLarge => l10n.ftReasonFileTooLarge(name),
    FtReason.pathTooLong => l10n.ftReasonPathTooLong(name),
    FtReason.invalidName => l10n.ftReasonInvalidName,
    FtReason.invalidNameWindows => l10n.ftReasonInvalidNameWindows(
      arg(0, name),
    ),
    FtReason.symlinkInPath => l10n.ftReasonSymlinkInPath,
    FtReason.oneWay => l10n.ftReasonOneWay,
    // `args` is [this time, the limit] (`LEAPGATE.md` §10.15).
    FtReason.tooManyFiles => l10n.ftReasonTooManyFiles(
      arg(1, '?'),
      arg(0, '?'),
    ),
    FtReason.androidScope => l10n.ftReasonAndroidScope,
    FtReason.timeout => l10n.ftReasonTimeout,
    FtReason.disconnected => l10n.ftReasonDisconnected,
    FtReason.skipped => l10n.queueStatusSkipped,
    FtReason.other =>
      error.text.isEmpty
          ? l10n.ftReasonOther
          : error.text.replaceFirst(RegExp(r'[.。]+$'), ''),
  };
}

/// The replace confirmation (02 block I, M7a-5): the copy by [FtOverwritePrompt.kind]; Enter
/// replaces, or skips when the two files are the same.
class _OverwriteDialog extends StatefulWidget {
  const _OverwriteDialog({required this.prompt, required this.close});

  final FtOverwritePrompt prompt;
  final void Function(OverwriteAnswer? answer) close;

  @override
  State<_OverwriteDialog> createState() => _OverwriteDialogState();
}

class _OverwriteDialogState extends State<_OverwriteDialog> {
  var _forAll = false;

  void _answer(OverwriteChoice choice) =>
      widget.close((choice: choice, forAll: _forAll));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = widget.prompt;
    final identical = p.kind == FtOverwriteKind.identical;
    return LgConfirmDialog(
      title: l10n.ftOverwriteTitle(p.name),
      body: switch (p.kind) {
        FtOverwriteKind.existing ||
        FtOverwriteKind.identical => l10n.ftOverwriteExisting(p.folder),
        FtOverwriteKind.tempOnly => l10n.ftOverwriteTempOnly(p.folder),
        FtOverwriteKind.existingOrTemp => l10n.ftOverwriteExistingOrTemp(
          p.folder,
        ),
      },
      actions: [
        LgDialogAction(
          label: l10n.ftOverwriteCancel,
          onPressed: () => _answer(OverwriteChoice.cancel),
        ),
        LgDialogAction(
          label: l10n.ftOverwriteSkip,
          isDefault: identical,
          onPressed: () => _answer(OverwriteChoice.skip),
        ),
        LgDialogAction(
          label: l10n.ftOverwriteReplace,
          kind: LgButtonKind.primary,
          isDefault: !identical,
          onPressed: () => _answer(OverwriteChoice.overwrite),
        ),
      ],
      children: [
        if (identical) Text(l10n.ftOverwriteIdentical),
        LgCheckbox(
          value: _forAll,
          label: l10n.ftOverwriteForAll,
          onChanged: (v) => setState(() => _forAll = v),
        ),
      ],
    );
  }
}

/// The delete confirmation (02 block J, R2-Q23): follows [FtDeletePrompt.state] from
/// counting to the answer.
class _DeleteDialog extends StatelessWidget {
  const _DeleteDialog({required this.prompt, required this.close});

  final FtDeletePrompt prompt;
  final void Function(bool? delete) close;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final side = prompt.isRemote ? l10n.ftSideRemote : l10n.ftSideLocal;
    final cancel = LgDialogAction(
      label: l10n.connCancel,
      onPressed: () => close(null),
    );
    return ValueListenableBuilder<FtDeleteState>(
      valueListenable: prompt.state,
      builder: (context, state, _) => switch (state) {
        FtDeleteCounting() => LgConfirmDialog(
          title: l10n.ftDelete,
          body: l10n.ftDeleteCounting,
          bodyIcon: LgIcons.spinner,
          actions: [cancel],
        ),
        FtDeleteReady(:final kind, :final name, :final items) =>
          LgConfirmDialog(
            title: switch (kind) {
              FtDeleteKind.link => l10n.ftDeleteLinkTitle(name),
              _ when items > 1 => l10n.ftDeleteManyTitle(items),
              _ => l10n.ftDeleteOneTitle(name),
            },
            body: switch (kind) {
              FtDeleteKind.file => l10n.ftDeleteFileBody(side),
              FtDeleteKind.emptyFolder => l10n.ftDeleteEmptyFolderBody(side),
              FtDeleteKind.contents => l10n.ftDeleteContentsBody(
                state.files,
                formatFileSize(l10n, state.bytes),
                side,
              ),
              FtDeleteKind.link => l10n.ftDeleteLinkBody,
            },
            actions: [
              cancel,
              LgDialogAction(
                label: l10n.ftDelete,
                kind: LgButtonKind.dangerSolid,
                isDefault: true,
                onPressed: () => close(true),
              ),
            ],
          ),
        FtDeleteCountFailed(:final folder, :final error) => LgConfirmDialog(
          title: l10n.ftDelete,
          body: l10n.ftDeleteCountFailed(
            folder,
            ftReasonText(l10n, error, name: folder),
          ),
          actions: [
            cancel,
            LgDialogAction(
              label: l10n.connRetry,
              kind: LgButtonKind.primary,
              isDefault: true,
              onPressed: prompt.retry,
            ),
          ],
        ),
        FtDeleteOverLimit(:final folder, :final limit, :final count) =>
          LgConfirmDialog(
            title: l10n.ftDelete,
            body: l10n.ftDeleteOverLimit(limit, folder, count),
            actions: [
              LgDialogAction(
                label: l10n.closingClose,
                kind: LgButtonKind.primary,
                isDefault: true,
                onPressed: () => close(null),
              ),
            ],
          ),
      },
    );
  }
}

/// "新建文件夹" and "重命名" (02 block J): checked as the user types, the error under the field;
/// the button waits for [submit] and the dialog stays with "无法…。‹原因›。" when it failed.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.action,
    required this.initial,
    required this.selectTo,
    required this.isWindows,
    required this.check,
    required this.submit,
    required this.failed,
    required this.close,
    this.unchanged,
  });

  _NameDialog.newFolder(
    FtNewFolderPrompt p, {
    required void Function(String?) close,
  }) : this(
         title: (l10n) => l10n.ftNewFolder,
         action: (l10n) => l10n.ftNewFolderCreate,
         initial: (l10n) => l10n.ftNewFolder,
         selectTo: null,
         isWindows: p.isWindows,
         check: p.check,
         submit: p.submit,
         failed: (l10n, reason) => l10n.ftNewFolderFailed(reason),
         close: close,
       );

  _NameDialog.rename(FtRenamePrompt p, {required void Function(String?) close})
    : this(
        title: (l10n) => l10n.ftRenameTitle(p.name),
        action: (l10n) => l10n.ftRename,
        initial: (_) => p.name,
        // A file's name up to its extension (a leading dot is part of the name).
        selectTo: p.isDirectory || p.name.lastIndexOf('.') <= 0
            ? null
            : p.name.lastIndexOf('.'),
        isWindows: p.isWindows,
        check: p.check,
        submit: p.submit,
        failed: (l10n, reason) => l10n.ftRenameFailed(reason),
        close: close,
        unchanged: p.name,
      );

  final String Function(AppLocalizations l10n) title;
  final String Function(AppLocalizations l10n) action;
  final String Function(AppLocalizations l10n) initial;

  /// The end of the selection in the initial name; null selects it all.
  final int? selectTo;
  final bool isWindows;
  final FtNameError? Function(String name) check;
  final Future<FtError?> Function(String name) submit;
  final String Function(AppLocalizations l10n, String reason) failed;
  final void Function(String? name) close;

  /// The name the button stays off for (rename).
  final String? unchanged;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  TextEditingController? _text;
  FtNameError? _error;
  FtError? _failure;
  var _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_text != null) return;
    final initial = widget.initial(AppLocalizations.of(context)!);
    _text = TextEditingController(text: initial)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.selectTo ?? initial.length,
      );
    _error = widget.check(initial);
  }

  @override
  void dispose() {
    _text?.dispose();
    super.dispose();
  }

  String get _name => _text!.text;

  bool get _canSubmit =>
      !_busy &&
      _name.trim().isNotEmpty &&
      _error == null &&
      _name != widget.unchanged;

  void _onChanged(String name) => setState(() {
    _error = widget.check(name);
    _failure = null;
  });

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final name = _name;
    setState(() => _busy = true);
    final failure = await widget.submit(name);
    if (!mounted) return;
    if (failure == null) {
      widget.close(name);
      return;
    }
    setState(() {
      _busy = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final failure = _failure;
    final dialog = LgFormDialog(
      title: widget.title(l10n),
      icon: LgIcons.folderPlus,
      banner: failure == null
          ? null
          : LgBanner(
              tone: LgTone.error,
              slim: true,
              text: widget.failed(
                l10n,
                ftReasonText(l10n, failure, name: _name),
              ),
            ),
      actions: [
        LgDialogAction(
          label: l10n.connCancel,
          onPressed: _busy ? null : () => widget.close(null),
        ),
        LgDialogAction(
          label: widget.action(l10n),
          kind: LgButtonKind.primary,
          isDefault: true,
          busy: _busy,
          onPressed: _canSubmit ? () => unawaited(_submit()) : null,
        ),
      ],
      children: [
        LgFormField(
          label: l10n.ftNameLabel,
          child: LgTextField(
            controller: _text,
            autofocus: true,
            enabled: !_busy,
            semanticLabel: l10n.ftNameLabel,
            errorText: switch (_error) {
              FtNameError.invalidChars =>
                widget.isWindows
                    ? l10n.ftNameInvalidChars(r'\ / : * ? " < > |')
                    : l10n.ftNameInvalidSlash,
              FtNameError.alreadyExists => l10n.ftNameExists,
              null => null,
            },
            onChanged: _onChanged,
            onSubmitted: (_) => unawaited(_submit()),
          ),
        ),
      ],
    );
    return LgDialogScrim(
      onEscape: _busy ? null : () => widget.close(null),
      child: dialog,
    );
  }
}

/// "断开文件传输？" (R2-Q28, 02 §3.1).
class _DisconnectDialog extends StatelessWidget {
  const _DisconnectDialog({required this.unfinished, required this.close});

  final int unfinished;
  final void Function(bool? disconnect) close;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LgConfirmDialog(
      title: l10n.ftDisconnectTitle,
      body: l10n.ftUnfinished(unfinished),
      actions: [
        LgDialogAction(label: l10n.connCancel, onPressed: () => close(null)),
        LgDialogAction(
          label: l10n.closingDisconnect,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: () => close(true),
        ),
      ],
    );
  }
}
