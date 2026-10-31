// The "操作" menu (01 P2 block B). Upstream: `flutter/lib/common/widgets/toolbar.dart`
// `toolbarControls` (:447-798), in 01's order. The view switches it had (file transfer,
// camera, terminal, TCP tunneling) are the view switch now, the mobile-only rows stay out, and
// rows hidden upstream for a permission the remote device did not give are greyed out with the
// reason.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/notices.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import '../../../icons/lg_icon.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_session_toolbar.dart';
import 'dialogs.dart';
import 'entries.dart';
import 'toolbar_env.dart';

const kActionMenuActions = [
  kShortcutActionSendCtrlAltDel,
  kShortcutActionInsertLock,
  kShortcutActionRestartRemote,
  kShortcutActionToggleBlockInput,
  kShortcutActionSendClipboardKeystrokes,
  kShortcutActionRefresh,
  kShortcutActionScreenshot,
  kShortcutActionSwitchSides,
];

const _kPeerOptionAllowWaylandKeyboard = 'allow-wayland-keyboard';

/// Connections whose Wayland keyboard question was answered "allow" without remembering it
/// (upstream `toolbar.dart:23-47`).
final _waylandAllowed = <String>{};

/// The 30 s screenshot cooldown of each session (upstream `FfiModel.timerScreenshot`).
final _screenshotCooldown = Expando<Timer>();

/// Ends the cooldown when the screenshot comes back (upstream `model.dart:486-487`); for the
/// `screenshot` event handler.
void endScreenshotCooldown(FFI ffi) {
  _screenshotCooldown[ffi]?.cancel();
  _screenshotCooldown[ffi] = null;
}

Future<List<TbEntry>> actionMenuEntries(ToolbarEnv env) async {
  final l10n = env.l10n;
  final ffi = env.ffi;
  final pi = env.pi;
  final sid = env.sessionId;
  final isDefault = env.isDefaultConn;
  final noKeyboard = env.keyboardReason;
  final inputReason = env.inputReason;
  final isWayland = pi.platform == kPeerPlatformLinux && pi.isWayland;
  final entries = <TbEntry>[];

  if (isDefault && (pi.platform == kPeerPlatformLinux || pi.sasEnabled)) {
    entries.add(
      TbItem(
        label: l10n.toolbarCtrlAltDel,
        actionId: kShortcutActionSendCtrlAltDel,
        disabledReason: inputReason,
        onPressed: inputReason != null
            ? null
            : () => bind.sessionCtrlAltDel(sessionId: sid),
      ),
    );
  }
  if (isDefault) {
    entries.add(
      TbItem(
        label: l10n.menuLock,
        actionId: kShortcutActionInsertLock,
        disabledReason: inputReason,
        onPressed: inputReason != null
            ? null
            : () => bind.sessionLockScreen(sessionId: sid),
      ),
    );
  }
  if (isDefault &&
      const [
        kPeerPlatformLinux,
        kPeerPlatformWindows,
        kPeerPlatformMacOS,
      ].contains(pi.platform)) {
    final reason = env.permitted('restart') ? null : l10n.menuNoRestart;
    entries.add(
      TbItem(
        label: l10n.toolbarRestart,
        actionId: kShortcutActionRestartRemote,
        disabledReason: reason,
        onPressed: reason != null ? null : () => _confirmRestart(env),
      ),
    );
  }
  if (isDefault && pi.platform == kPeerPlatformWindows) {
    final reason =
        noKeyboard ??
        (env.permitted('block_input') ? null : l10n.menuNoBlockInput);
    final blocked = ffi.blockInput.value;
    entries.add(
      TbItem(
        label: blocked ? l10n.menuUnblockInput : l10n.menuBlockInput,
        actionId: kShortcutActionToggleBlockInput,
        disabledReason: reason,
        onPressed: reason != null
            ? null
            : () {
                bind.sessionToggleOption(
                  sessionId: sid,
                  value: '${blocked ? 'un' : ''}block-input',
                );
                ffi.blockInput.value = !blocked;
                env.notifyChanged();
              },
      ),
    );
  }
  if (isDefault && ffi.elevationModel.showRequestMenu) {
    entries.add(
      TbItem(
        label: l10n.menuRequestElevation,
        disabledReason: noKeyboard,
        onPressed: noKeyboard != null
            ? null
            : () => showRequestElevationDialog(env.overlays, ffi, l10n),
      ),
    );
  }
  if (isDefault) {
    entries.add(
      TbItem(
        label: l10n.menuOsPassword,
        disabledReason: noKeyboard,
        onPressed: noKeyboard != null ? null : () => _osPassword(env),
        trailing: noKeyboard != null
            ? null
            : LgToolbarButton(
                icon: LgIcons.edit,
                label: l10n.menuEditOsPassword,
                onPressed: () =>
                    showOsPasswordDialog(env.overlays, ffi, l10n, login: false),
              ),
      ),
    );
  }
  if (isDefault && pi.platform != kPeerPlatformAndroid) {
    entries.add(
      TbItem(
        label: l10n.menuTypeClipboard,
        actionId: kShortcutActionSendClipboardKeystrokes,
        disabledReason: noKeyboard,
        onPressed: noKeyboard != null
            ? null
            : () => _typeClipboard(env, isWayland),
      ),
    );
  }
  if (isDefault &&
      isWayland &&
      (_waylandRemembered(ffi) || _waylandAllowed.contains('$sid'))) {
    entries.add(
      TbItem(label: l10n.menuResetWayland, onPressed: () => _resetWayland(env)),
    );
  }
  if (pi.version.isNotEmpty) {
    entries.add(
      TbItem(
        label: l10n.menuRefresh,
        actionId: kShortcutActionRefresh,
        onPressed: () => sessionRefreshVideo(sid, pi),
      ),
    );
  }
  if ((isDefault || ffi.connType == ConnType.viewCamera) &&
      isDesktop &&
      bind.sessionGetCommonSync(
            sessionId: sid,
            key: 'is_screenshot_supported',
            param: '',
          ) ==
          'true') {
    final cooling = _screenshotCooldown[ffi] != null;
    entries.add(
      TbItem(
        label: cooling ? l10n.menuScreenshotTaking : l10n.menuScreenshot,
        actionId: kShortcutActionScreenshot,
        onPressed: cooling ? null : () => _screenshot(env),
      ),
    );
  }
  if (isDefault &&
      isDesktop &&
      pi.platform != kPeerPlatformAndroid &&
      versionCmp(pi.version, '1.2.0') >= 0 &&
      bind.peerGetSessionsCount(id: ffi.id, connType: ffi.connType.index) ==
          1) {
    entries.add(
      TbItem(
        label: l10n.menuSwitchSides,
        actionId: kShortcutActionSwitchSides,
        disabledReason: noKeyboard,
        onPressed: noKeyboard != null ? null : () => _switchSides(env),
      ),
    );
  }
  if (isDefault && !bind.isDisableAccount()) {
    // Upstream signs in first; signing in comes with the account page (M4).
    final signedIn = appCore.options.local.get('access_token').isNotEmpty;
    entries.add(
      TbItem(
        label: l10n.menuAddNote,
        disabledReason: signedIn ? null : l10n.menuNoteSignIn,
        onPressed: signedIn
            ? () => showNoteDialog(env.overlays, ffi, l10n)
            : null,
      ),
    );
  }
  return entries;
}

/// Asks over this tab only; Enter restarts, as upstream's OK does (`dialog.dart:1403-1431`).
Future<void> _confirmRestart(ToolbarEnv env) async {
  final l10n = env.l10n;
  final ok = await env.overlays.show<bool>(
    env.ffi.id,
    (context, close) => LgDialogScrim(
      onEscape: () => close(null),
      child: LgConfirmDialog(
        title: l10n.toolbarRestartTitle,
        body: l10n.toolbarRestartBody,
        actions: [
          LgDialogAction(label: l10n.connCancel, onPressed: () => close(null)),
          LgDialogAction(
            label: l10n.toolbarRestartConfirm,
            kind: LgButtonKind.dangerSolid,
            isDefault: true,
            onPressed: () => close(true),
          ),
        ],
      ),
    ),
  );
  if (ok == true) {
    bind.sessionRestartRemoteDevice(sessionId: env.sessionId);
  }
}

/// Types the saved OS password, or asks for one first (`toolbar.dart:264-279`).
Future<void> _osPassword(ToolbarEnv env) async {
  final ffi = env.ffi;
  final password = await ffi.options.get('os-password') ?? '';
  if (password.isEmpty) {
    await showOsPasswordDialog(env.overlays, ffi, env.l10n, login: true);
  } else {
    bind.sessionInputOsPassword(sessionId: env.sessionId, value: password);
  }
}

bool _waylandRemembered(FFI ffi) => option2bool(
  _kPeerOptionAllowWaylandKeyboard,
  appCore.options.peer(ffi.id).get(_kPeerOptionAllowWaylandKeyboard),
);

/// `toolbar.dart:505-535`: on a Wayland peer, typing needs the user's consent first.
Future<void> _typeClipboard(ToolbarEnv env, bool isWayland) async {
  final ffi = env.ffi;
  final sid = env.sessionId;
  Future<void> send() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      bind.sessionInputString(sessionId: sid, value: data!.text!);
    }
  }

  if (isWayland &&
      !_waylandRemembered(ffi) &&
      !_waylandAllowed.contains('$sid')) {
    ffi.inputModel.keyboardInputAllowed = false;
    final answer = await askWaylandKeyboard(env.overlays, ffi, env.l10n);
    if (answer == null) return;
    await send();
    ffi.inputModel.keyboardInputAllowed = true;
    if (answer.remember) {
      await appCore.options
          .peer(ffi.id)
          .set(
            _kPeerOptionAllowWaylandKeyboard,
            bool2option(_kPeerOptionAllowWaylandKeyboard, true),
          );
    }
    _waylandAllowed.add('$sid');
    env.notifyChanged();
    return;
  }
  await send();
}

/// `toolbar.dart:536-564`.
Future<void> _resetWayland(ToolbarEnv env) async {
  final ffi = env.ffi;
  await appCore.options
      .peer(ffi.id)
      .set(
        _kPeerOptionAllowWaylandKeyboard,
        bool2option(_kPeerOptionAllowWaylandKeyboard, false),
      );
  _waylandAllowed.remove('${env.sessionId}');
  ffi.inputModel.keyboardInputAllowed = false;
  appCore.toasts.show('Successful');
  env.notifyChanged();
}

/// `toolbar.dart:739-778`. A merged view of all monitors cannot be captured.
void _screenshot(ToolbarEnv env) {
  final ffi = env.ffi;
  final pi = env.pi;
  if (_screenshotCooldown[ffi] != null) return;
  if (pi.currentDisplay == kAllDisplayValue) {
    ffi.notices.add(
      SessionNotice(
        'screenshot-merged-screen-not-supported-tip',
        args: const {
          'type': 'custom-nook-nocancel-hasclose-info',
          'title': 'Take screenshot',
        },
      ),
    );
    return;
  }
  bind.sessionTakeScreenshot(
    sessionId: env.sessionId,
    display: pi.currentDisplay,
  );
  _screenshotCooldown[ffi] = Timer(const Duration(seconds: 30), () {
    _screenshotCooldown[ffi] = null;
    env.notifyChanged();
  });
  env.notifyChanged();
}

/// `dialog.dart:1807-1826`: after switching, this side's session closes.
Future<void> _switchSides(ToolbarEnv env) async {
  final ffi = env.ffi;
  if (!await confirmSwitchSides(env.overlays, ffi, env.l10n)) return;
  await bind.sessionSwitchSides(sessionId: env.sessionId);
  await appCore.sessions.closeDevice(ffi.id);
}
