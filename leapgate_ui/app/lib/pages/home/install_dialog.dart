// The install page (P11, 13 §4, M9a): a dialog over the home tab (R3-Q21), opened from the
// hint card's "安装" and from 远程打印 on the portable version (R3-Q20). Coder I's, on the
// designer's install dialog parts (`widgets/lg_install_dialog.dart`).
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/install_page.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/tab_overlays.dart';
import '../../widgets/lg_banner.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_feedback.dart';
import '../../widgets/lg_install_dialog.dart';

/// Opens the install page over the home tab; [printer] ticks the printer (from 远程打印).
/// Completes when it closes: "取消" or Esc. On success this process is ended instead.
Future<void> showInstallDialog(
  TabOverlays overlays,
  LocalStatusModel status, {
  bool printer = false,
}) {
  // Outside the builder: the overlay builds the dialog again when its tab comes back.
  final model = InstallPageModel(status, printer: printer);
  return overlays
      .show<void>(
        null,
        (context, close) =>
            InstallDialog(model: model, close: () => close(null)),
      )
      .whenComplete(model.dispose);
}

class InstallDialog extends StatefulWidget {
  const InstallDialog({super.key, required this.model, required this.close});

  final InstallPageModel model;
  final VoidCallback close;

  @override
  State<InstallDialog> createState() => _InstallDialogState();
}

enum _Focus { install, cancel, change }

class _InstallDialogState extends State<InstallDialog> {
  /// Where the keyboard is when the dialog opens, from the values then (13 §4.2 "键盘"): on
  /// "取消" when something in use would end, so one Enter does not end it; on "修改" when the
  /// location can't be used; on "安装" otherwise.
  late final _Focus _focus = widget.model.sessionsEnd
      ? _Focus.cancel
      : widget.model.blocked
      ? _Focus.change
      : _Focus.install;

  /// The sessions line follows them while the page is open; the status (busy, failed) is one
  /// of them.
  late final _changes = Listenable.merge([
    widget.model,
    widget.model.sessionsChanges,
  ]);

  /// A failure is added under the options: it is scrolled into view when it appears, and the
  /// keyboard goes back to "安装" ([_install]; greyed while it ran, so it may have been
  /// elsewhere) for Enter to try again.
  final _scroll = ScrollController();
  final _install = FocusNode();
  InstallFailure? _failure;

  @override
  void initState() {
    super.initState();
    _failure = widget.model.failure;
    widget.model.status.addListener(_onStatus);
  }

  @override
  void dispose() {
    widget.model.status.removeListener(_onStatus);
    _scroll.dispose();
    _install.dispose();
    super.dispose();
  }

  void _onStatus() {
    final failure = widget.model.failure;
    if (failure == null || identical(failure, _failure)) return;
    _failure = failure;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      _install.requestFocus();
    });
  }

  Future<void> _change() async {
    final folder = await FilePicker.platform.getDirectoryPath(
      // file_picker 5.5.0 ignores it on Windows (a known limit); passed for when it doesn't.
      initialDirectory: widget.model.pickerStart,
      // On the main window, so that it can't end up behind it.
      lockParentWindow: true,
    );
    if (folder != null && mounted) widget.model.choose(folder);
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final status = model.status;
    return ListenableBuilder(
      listenable: _changes,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final busy = status.installing;
        final failure = model.failure;
        final issue = model.issue;
        return LgDialogScrim(
          onEscape: busy ? null : widget.close,
          scrollable: false,
          child: LgInstallDialog(
            title: l10n.installTitle,
            scrollController: _scroll,
            actions: [
              LgDialogAction(
                label: l10n.homeCancel,
                onPressed: busy ? null : widget.close,
                isDefault: _focus == _Focus.cancel,
              ),
              // Asks for administrator permission (02 §1.2.6).
              LgDialogAction(
                label: busy ? l10n.homeInstalling : l10n.homeInstallButton,
                kind: LgButtonKind.primary,
                icon: LgIcons.uac,
                iconSize: 18,
                busy: busy,
                onPressed: model.blocked || busy ? null : model.install,
                isDefault: _focus == _Focus.install,
                focusNode: _install,
              ),
            ],
            pathRow: LgInstallPathRow(
              label: l10n.installLocation,
              path: model.path,
              changeLabel: l10n.installChange,
              changeSemanticLabel: l10n.installChangeLabel,
              onChange: busy ? null : _change,
              changeAutofocus: _focus == _Focus.change,
              tone: switch (issue) {
                null => LgPathTone.normal,
                InstallLocationIssue.notEmpty => LgPathTone.warning,
                _ => LgPathTone.error,
              },
              message: switch (issue) {
                null => null,
                InstallLocationIssue.notLocalDisk => l10n.installNotLocalDisk,
                InstallLocationIssue.percent => l10n.installPercent,
                InstallLocationIssue.insideProgram => l10n.installInsideProgram,
                InstallLocationIssue.notEmpty => l10n.installNotEmpty,
              },
              // The folder Leapgate runs from: for the portable single file it is where it was
              // unpacked, not where it was downloaded, so the line says which (13 §4.2 block A).
              messageTooltip: issue == InstallLocationIssue.insideProgram
                  ? model.programFolder
                  : null,
            ),
            options: [
              LgOptionCheck(
                value: model.startMenu,
                label: l10n.installStartMenu,
                onChanged: busy ? null : model.setStartMenu,
              ),
              LgOptionCheck(
                value: model.desktopShortcut,
                label: l10n.installDesktopShortcut,
                onChanged: busy ? null : model.setDesktopShortcut,
              ),
              // The note is 远程打印's word for word (01 §7.6 item 7).
              LgOptionCheck(
                value: model.printer,
                label: l10n.installPrinter,
                description: l10n.settingsRemotePrintPrinterNote,
                onChanged: busy ? null : model.setPrinter,
              ),
            ],
            // The license line waits for the brand decisions (13 §4.2 block C): not shown, as
            // on the About section.
            banners: [
              if (model.sessionsEnd)
                LgInstallBanner(
                  tone: LgTone.warning,
                  text: l10n.settingsServiceStartBody,
                ),
              if (failure != null)
                LgInstallBanner(
                  tone: LgTone.error,
                  text: switch (failure) {
                    InstallFailure(uacDenied: true) =>
                      l10n.homeInstallUacDenied,
                    InstallFailure(text: '') => l10n.homeInstallFailed,
                    InstallFailure(:final text) => l10n.homeInstallFailedText(
                      text,
                    ),
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
