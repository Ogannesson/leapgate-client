import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/options.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../widgets/lg_button.dart';
import '../widgets/lg_feedback.dart';
import '../widgets/lg_selection.dart';
import 'session_views.dart';
import 'tab_overlays.dart';

// What closing the main window does (01 §2.1 "窗口关闭", §3.2 block G, §8.1 Q6). Asking
// before closing sessions is upstream's kOptionEnableConfirmClosingTabs; the settings page
// names it "关闭窗口前确认断开会话" (02 §1.5.4).

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
  // Sessions are views, as the tab's own confirmation counts them.
  final views =
      appCore.sessions.devices.expand(appCore.sessions.sessionsOf).toList();
  final plan = planWindowClose(
    sessions: views.length,
    installed: appCore.options.isInstalled,
    confirmSessions: local.getBool(kOptionEnableConfirmClosingTabs),
    remembered: rememberedCloseAction(local),
  );
  var action = plan.action;
  // What runs on the exit page goes on in the background or stops with it (13 §1.3 block F).
  final exits = appCore.exitNodes.runningCount;
  final tunnels = appCore.tunnels.runningCount;
  // Unfinished transfers are asked about even after "Don't show again" (R2-Q28, 02 §3.1).
  final transfers = unfinishedTransfers(views);
  if (plan.askSessions || plan.askAction || transfers > 0) {
    final answer = await overlays.show<CloseAnswer>(
        kWindowScope,
        (context, close) => LgDialogScrim(
            onEscape: () => close(null),
            child: CloseDialog(
                plan: plan,
                sessions: views.length,
                exits: exits,
                tunnels: tunnels,
                transfers: transfers,
                onClose: close)));
    if (answer == null) return;
    if (plan.askAction) action = answer.action;
    if (answer.dontShowAgain) {
      await local.setBool(kOptionEnableConfirmClosingTabs, false);
    }
    if (answer.remember) {
      await local.set(kOptionLeapgateCloseAction, answer.action.name);
    }
  } else if (appCore.backgroundCount > 0 && action == CloseAction.exit) {
    // Quitting stops the exit nodes and tunnels: asked even when "Quit" is remembered (M5-11).
    final quit = await overlays.show<bool>(
        kWindowScope,
        (context, close) => LgDialogScrim(
            onEscape: () => close(null),
            child: _QuitWithExitsDialog(
                exits: exits, tunnels: tunnels, onClose: close)));
    if (quit != true) return;
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

/// What happens to the exit nodes and tunnels running (13 §1.3 block F "关窗和退出"): they go on
/// in the background, or stop when [quit].
String backgroundSentence(AppLocalizations l10n,
        {required int exits, required int tunnels, required bool quit}) =>
    switch ((exits > 0, tunnels > 0)) {
      (_, false) => quit
          ? l10n.exitCloseQuitBody(exits)
          : l10n.exitCloseBackground(exits),
      (false, true) => quit
          ? l10n.closingTunnelsQuit(tunnels)
          : l10n.closingTunnelsBackground(tunnels),
      (true, true) => quit
          ? l10n.closingBothQuit(exits, tunnels)
          : l10n.closingBothBackground(exits, tunnels),
    };

/// The close confirmation (01 §3.2 block G); Enter is the main button, Esc cancels.
class CloseDialog extends StatefulWidget {
  const CloseDialog(
      {super.key,
      required this.plan,
      required this.sessions,
      this.exits = 0,
      this.tunnels = 0,
      this.transfers = 0,
      required this.onClose});

  final ClosePlan plan;
  final int sessions;

  /// Exit nodes running: they go on in the background, or stop with a remembered "Quit".
  final int exits;

  /// Tunnel cards running, as [exits] (13 §1.3 block F).
  final int tunnels;

  /// Unfinished file transfers: one more sentence, beside the exit nodes' one.
  final int transfers;
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
    final running = widget.exits + widget.tunnels > 0;
    String background({required bool quit}) => backgroundSentence(l10n,
        exits: widget.exits, tunnels: widget.tunnels, quit: quit);
    return LgConfirmDialog(
      title: plan.askSessions
          ? l10n.closingDisconnectAll(widget.sessions)
          : l10n.closingTitle,
      actions: [
        LgDialogAction(
            label: l10n.connCancel, onPressed: () => widget.onClose(null)),
        LgDialogAction(
          label: plan.askSessions ? l10n.closingDisconnect : l10n.closingClose,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: _confirm,
        ),
      ],
      children: [
        if (plan.askAction) ...[
          for (final (a, label, detail) in [
            (CloseAction.exit, l10n.closingExit, l10n.closingExitDetail),
            (
              CloseAction.background,
              l10n.closingBackground,
              l10n.closingBackgroundDetail
            ),
          ])
            LgRadio<CloseAction>(
              value: a,
              groupValue: _action,
              label: label,
              description: detail,
              onChanged: (v) => setState(() => _action = v),
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
        // Not in the question asked only for the transfers (02 §3.1).
        if (running && (plan.askSessions || plan.askAction))
          if ((plan.askAction ? _action : plan.action) ==
              CloseAction.background)
            Text(background(quit: false))
          // The "Quit" choice says so itself.
          else if (!plan.askAction)
            Text(background(quit: true)),
        if (widget.transfers > 0) Text(l10n.ftUnfinished(widget.transfers)),
        // Quitting with exit nodes or tunnels is asked anyway (M5-11): one dialog with both
        // sentences.
        if (running &&
            !plan.askSessions &&
            !plan.askAction &&
            plan.action == CloseAction.exit)
          Text(background(quit: true)),
      ],
    );
  }
}

/// Quitting the portable version with exit nodes or tunnels running (01 §2.1, M5-11, 13 §1.3
/// block F).
class _QuitWithExitsDialog extends StatelessWidget {
  const _QuitWithExitsDialog(
      {required this.exits, required this.tunnels, required this.onClose});

  final int exits;
  final int tunnels;
  final void Function(bool? quit) onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LgConfirmDialog(
      title: l10n.exitCloseQuitTitle,
      body: backgroundSentence(l10n, exits: exits, tunnels: tunnels, quit: true),
      actions: [
        LgDialogAction(label: l10n.connCancel, onPressed: () => onClose(null)),
        LgDialogAction(
          label: l10n.exitCloseQuit,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: () => onClose(true),
        ),
      ],
    );
  }
}
