// The install page (P11, 13 §4, M9a): a dialog over the home tab (R3-Q21), opened from the
// hint card's "安装" and from 远程打印 on the portable version (R3-Q20). Coder I's; it is built
// from the components there are, the designer's take their place when M9a is put together.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/install_page.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';

import '../../l10n/app_localizations.dart';
import '../../shell/tab_overlays.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_banner.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_feedback.dart';
import '../../widgets/lg_selection.dart';
import '../../widgets/lg_tooltip.dart';

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

  Future<void> _change() async {
    final folder = await FilePicker.platform.getDirectoryPath(
      initialDirectory: widget.model.pickerStart,
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
        final t = LgTokens.of(context);
        final c = t.colors;
        final busy = status.installing;
        final failure = model.failure;
        return LgDialogScrim(
          onEscape: busy ? null : widget.close,
          child: LgConfirmDialog(
            title: l10n.installTitle,
            actions: [
              LgDialogAction(
                label: l10n.homeCancel,
                onPressed: busy ? null : widget.close,
                isDefault: _focus == _Focus.cancel,
              ),
              // TODO(M9 整合): the shield (02 §1.2.6) with the designer's dialog button.
              LgDialogAction(
                label: busy ? l10n.homeInstalling : l10n.homeInstallButton,
                kind: LgButtonKind.primary,
                busy: busy,
                onPressed: model.blocked || busy ? null : model.install,
                isDefault: _focus == _Focus.install,
              ),
            ],
            children: [
              _Location(
                model: model,
                onChange: busy ? null : _change,
                autofocus: _focus == _Focus.change,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LgCheckbox(
                    value: model.startMenu,
                    onChanged: busy ? null : model.setStartMenu,
                    label: l10n.installStartMenu,
                  ),
                  LgCheckbox(
                    value: model.desktopShortcut,
                    onChanged: busy ? null : model.setDesktopShortcut,
                    label: l10n.installDesktopShortcut,
                  ),
                  LgCheckbox(
                    value: model.printer,
                    onChanged: busy ? null : model.setPrinter,
                    label: l10n.installPrinter,
                  ),
                  // Under the label, as 远程打印 has it word for word (01 §7.6 item 7).
                  Padding(
                    padding: const EdgeInsets.only(left: 20 + LgSpace.s3),
                    child: Text(
                      l10n.settingsRemotePrintPrinterNote,
                      style: t.textS.copyWith(color: c.text2),
                    ),
                  ),
                ],
              ),
              // The license line waits for the brand decisions (13 §4.2 block C): not shown,
              // as on the About section.
              if (model.sessionsEnd)
                Text(
                  l10n.settingsServiceStartBody,
                  style: t.textM.copyWith(color: c.text),
                ),
              if (failure != null)
                LgBanner(
                  tone: LgTone.error,
                  slim: true,
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

/// Block A: "安装位置", the path with "修改", and what is wrong with it.
class _Location extends StatelessWidget {
  const _Location({
    required this.model,
    required this.onChange,
    required this.autofocus,
  });

  final InstallPageModel model;
  final VoidCallback? onChange;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final c = t.colors;
    final issue = model.issue;
    final issueText = switch (issue) {
      null => null,
      InstallLocationIssue.notLocalDisk => l10n.installNotLocalDisk,
      InstallLocationIssue.percent => l10n.installPercent,
      InstallLocationIssue.insideProgram => l10n.installInsideProgram,
      InstallLocationIssue.notEmpty => l10n.installNotEmpty,
    };
    final issueLine = issueText == null
        ? null
        : Text(
            issueText,
            style: t.textS.copyWith(
              color: issue == InstallLocationIssue.notEmpty
                  ? c.warning
                  : c.error,
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.installLocation,
          style: t.textS.copyWith(color: c.text2, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: LgSpace.s1),
        Row(
          children: [
            Expanded(child: _MiddleEllipsisPath(model.path)),
            const SizedBox(width: LgSpace.s3),
            LgButton(
              label: l10n.installChange,
              semanticLabel: l10n.installChangeLabel,
              autofocus: autofocus,
              onPressed: onChange,
            ),
          ],
        ),
        if (issueLine != null) ...[
          const SizedBox(height: LgSpace.s1),
          // The folder Leapgate runs from is not the one the user downloaded it to when it is
          // the portable single file: hovering says which.
          issue == InstallLocationIssue.insideProgram
              ? LgTooltip(message: model.programFolder, child: issueLine)
              : issueLine,
        ],
      ],
    );
  }
}

/// A path on one line, cut in the middle when it does not fit (13 §4.2 block A); hovering shows
/// it whole.
class _MiddleEllipsisPath extends StatelessWidget {
  const _MiddleEllipsisPath(this.path);

  final String path;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final style = t.textM.copyWith(color: t.colors.text);
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      label: path,
      excludeSemantics: true,
      child: LgTooltip(
        message: path,
        child: LayoutBuilder(
          builder: (context, constraints) {
            bool fits(String s) {
              final painter = TextPainter(
                text: TextSpan(text: s, style: style),
                textDirection: direction,
                textScaler: scaler,
                maxLines: 1,
              )..layout();
              final width = painter.width;
              painter.dispose();
              return width <= constraints.maxWidth;
            }

            var shown = path;
            if (!fits(path)) {
              // The most characters kept, half from each end, that fit with the "…".
              var low = 0;
              var high = path.length;
              while (low < high) {
                final keep = (low + high + 1) ~/ 2;
                if (fits(_cut(keep))) {
                  low = keep;
                } else {
                  high = keep - 1;
                }
              }
              shown = _cut(low);
            }
            return Text(shown, style: style, maxLines: 1, softWrap: false);
          },
        ),
      ),
    );
  }

  String _cut(int keep) => cutMiddle(path, keep);
}

/// [keep] UTF-16 units of [text], half from each end, around a "…"; a cut that falls inside a
/// surrogate pair moves one unit off it.
@visibleForTesting
String cutMiddle(String text, int keep) {
  bool high(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
  bool low(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
  var head = (keep + 1) ~/ 2;
  var tail = text.length - (keep - head);
  if (head > 0 && high(text.codeUnitAt(head - 1))) head--;
  if (tail < text.length && low(text.codeUnitAt(tail))) tail++;
  return '${text.substring(0, head)}…${text.substring(tail)}';
}
