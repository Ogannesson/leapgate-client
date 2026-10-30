import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/options.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../theme/lg_tokens.dart';
import '../widgets/lg_button.dart';
import '../widgets/lg_selection.dart';
import 'confirm_card.dart';
import 'tab_overlays.dart';

// What closing the main window does (01 §2.1 "窗口关闭", §3.2 block G, §8.1 Q6).

/// Upstream `consts.dart:170`: ask before closing sessions. The settings page names it
/// "关闭窗口前确认断开会话" (02 §1.5.4).
const kOptionEnableConfirmClosingTabs = 'enable-confirm-closing-tabs';

/// The portable version's remembered answer to "quit or run in background" (Q6), a LocalConfig
/// key of Leapgate's own: `exit`, `background`, or empty while not remembered.
const kOptionLeapgateCloseAction = 'leapgate-close-action';

enum CloseAction { exit, background }

/// What to ask before closing; [action] is what happens when nothing is asked.
typedef ClosePlan = ({bool askSessions, bool askAction, CloseAction action});

/// The installed version hides to the tray (its service keeps running in another process); the
/// portable version asks Q6 until an answer is remembered. Open sessions are confirmed first
/// unless "Don't show again" was ticked; both questions share one dialog.
ClosePlan planWindowClose(
    {required int sessions,
    required bool installed,
    required bool confirmSessions,
    required CloseAction? remembered}) {
  return (
    askSessions: sessions > 0 && confirmSessions,
    askAction: !installed && remembered == null,
    action: installed ? CloseAction.background : remembered ?? CloseAction.exit,
  );
}

CloseAction? rememberedCloseAction(OptionScope local) =>
    switch (local.get(kOptionLeapgateCloseAction)) {
      'exit' => CloseAction.exit,
      'background' => CloseAction.background,
      _ => null,
    };

/// The user's answer to the close dialog.
typedef CloseAnswer = ({
  CloseAction action,
  bool dontShowAgain,
  bool remember,
});

/// Runs the close flow; the window stays when the user cancels.
Future<void> closeMainWindow(TabOverlays overlays) async {
  final local = appCore.options.local;
  final devices = appCore.sessions.devices;
  final plan = planWindowClose(
    sessions: devices.length,
    installed: appCore.options.isInstalled,
    confirmSessions: local.getBool(kOptionEnableConfirmClosingTabs),
    remembered: rememberedCloseAction(local),
  );
  var action = plan.action;
  if (plan.askSessions || plan.askAction) {
    final answer = await overlays.show<CloseAnswer>(
        kWindowScope,
        (context, close) => CloseDialog(
            plan: plan, sessions: devices.length, onClose: close));
    if (answer == null) return;
    if (plan.askAction) action = answer.action;
    if (answer.dontShowAgain) {
      await local.setBool(kOptionEnableConfirmClosingTabs, false);
    }
    if (answer.remember) {
      await local.set(kOptionLeapgateCloseAction, answer.action.name);
    }
  }
  try {
    // A remote session does not go on in a window nobody sees (01 §2.1).
    await Future.wait([
      for (final d in appCore.sessions.devices) appCore.sessions.closeDevice(d)
    ]);
  } finally {
    // The window goes even when closing a session failed, as upstream's `finally`
    // (`common.dart:2844-2848`).
    // Upstream calls it on every close of the main window
    // (`desktop/pages/connection_page.dart:289`).
    await bind.mainOnMainWindowClose();
    if (action == CloseAction.exit) {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } else {
      await windowManager.hide();
    }
  }
}

/// The close confirmation; placeholder controls until the designer's dialog replaces them.
class CloseDialog extends StatefulWidget {
  const CloseDialog(
      {super.key,
      required this.plan,
      required this.sessions,
      required this.onClose});

  final ClosePlan plan;
  final int sessions;
  final void Function(CloseAnswer? answer) onClose;

  @override
  State<CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<CloseDialog> {
  var _action = CloseAction.exit;
  var _dontShowAgain = false;
  var _remember = false;

  void _confirm() => widget.onClose(
      (action: _action, dontShowAgain: _dontShowAgain, remember: _remember));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final plan = widget.plan;
    final confirm = ConfirmAction(
        plan.askSessions ? l10n.closingDisconnect : l10n.closingClose, _confirm,
        kind: LgButtonKind.primary);
    return ConfirmCard(
      title: plan.askSessions
          ? l10n.closingDisconnectAll(widget.sessions)
          : l10n.closingTitle,
      controls: [
        if (plan.askAction) ...[
          for (final (a, label, detail) in [
            (CloseAction.exit, l10n.closingExit, l10n.closingExitDetail),
            (
              CloseAction.background,
              l10n.closingBackground,
              l10n.closingBackgroundDetail
            ),
          ])
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LgRadio<CloseAction>(
                  value: a,
                  groupValue: _action,
                  label: label,
                  onChanged: (v) => setState(() => _action = v),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: LgSpace.s7),
                  child: Text(detail,
                      style: LgTokens.of(context)
                          .textS
                          .copyWith(color: LgTokens.of(context).colors.text2)),
                ),
              ],
            ),
          LgCheckbox(
            value: _remember,
            label: l10n.closingRemember,
            onChanged: (v) => setState(() => _remember = v),
          ),
        ],
        if (plan.askSessions)
          LgCheckbox(
            value: _dontShowAgain,
            label: l10n.closingDontShowAgain,
            onChanged: (v) => setState(() => _dontShowAgain = v),
          ),
      ],
      actions: [
        ConfirmAction(l10n.connCancel, () => widget.onClose(null)),
        confirm,
      ],
      defaultAction: confirm,
      onCancel: () => widget.onClose(null),
    );
  }
}
