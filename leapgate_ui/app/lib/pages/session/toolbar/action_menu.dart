// The "操作" menu (01 P2 block B). Upstream: `flutter/lib/common/widgets/toolbar.dart`
// `toolbarControls` (:447-798), in 01's order. The view switches it had (file transfer,
// camera, terminal, TCP tunneling) are the view switch now, the mobile-only rows stay out, and
// rows hidden upstream for a permission the remote device did not give are greyed out with the
// reason.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
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

/// The toasts after "重置 Wayland 键盘授权" (upstream shows "Successful" / "Failed"); the keys
/// are the ARB keys (`shell/toast_view.dart`).
const kToastWaylandReset = 'menuToastWaylandReset';
const kToastWaylandResetFailed = 'menuToastWaylandResetFailed';

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
  // A-P2's three groups: what acts on the remote device, what sends input, the rest.
  void divide() {
    if (entries.isNotEmpty && entries.last is! TbDivider) {
      entries.add(const TbDivider());
    }
  }

  divide();
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
  divide();
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
    // The 30 s wait and the merged view of all monitors are the requests' (`session_requests`).
    final pending = ffi.requests.screenshotPending.value;
    entries.add(
      TbItem(
        label: pending ? l10n.menuScreenshotTaking : l10n.menuScreenshot,
        actionId: kShortcutActionScreenshot,
        onPressed: pending ? null : ffi.requests.takeScreenshot,
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
  if (entries.isNotEmpty && entries.last is TbDivider) entries.removeLast();
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

/// `toolbar.dart:536-564`: the saved choice is cleared and this connection asks again.
Future<void> _resetWayland(ToolbarEnv env) async {
  final ffi = env.ffi;
  var cleared = false;
  try {
    await appCore.options
        .peer(ffi.id)
        .set(
          _kPeerOptionAllowWaylandKeyboard,
          bool2option(_kPeerOptionAllowWaylandKeyboard, false),
        );
    cleared = true;
  } catch (e) {
    debugPrint('Failed to clear the Wayland keyboard permission: $e');
  } finally {
    _waylandAllowed.remove('${env.sessionId}');
    ffi.inputModel.keyboardInputAllowed = false;
  }
  appCore.toasts.show(cleared ? kToastWaylandReset : kToastWaylandResetFailed);
  env.notifyChanged();
}

/// `dialog.dart:1807-1826`: after switching, this side's session closes.
Future<void> _switchSides(ToolbarEnv env) async {
  final ffi = env.ffi;
  if (!await confirmSwitchSides(env.overlays, ffi, env.l10n)) return;
  await bind.sessionSwitchSides(sessionId: env.sessionId);
  await appCore.sessions.closeDevice(ffi.id);
}
