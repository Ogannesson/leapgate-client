import 'package:flutter_hbb/leapgate/connection.dart';

import '../../l10n/app_localizations.dart';
import 'session_names.dart';

/// A next step under a connection error (01 §4.3 "下一步").
enum NextStep { retry, reconnect, useRelay, changeId, closeTab }

/// What the connection panel says about a failure and which buttons it offers, by C3's reason
/// code (`LEAPGATE.md` §10.4, 01 §4.3). "打开网络设置" waits for the settings page (M6) and is
/// left out; a reason left with no step offers "关闭标签". Code `other`, which also carries a
/// server's own refusal text, shows the message as Rust sent it.
({String text, List<NextStep> steps}) reasonView(
    AppLocalizations l10n, ConnReason reason, String id) {
  const retryClose = [NextStep.retry, NextStep.closeTab];
  const close = [NextStep.closeTab];
  final (text, steps) = switch (reason.code) {
    'id_not_exist' => (
        l10n.connReasonIdNotExist(formatId(id)),
        [NextStep.changeId, NextStep.closeTab]
      ),
    'peer_offline' => (l10n.connReasonPeerOffline, retryClose),
    'key_mismatch' => (l10n.connReasonKeyMismatch, const <NextStep>[]),
    'key_overuse' => (l10n.connReasonKeyOveruse, close),
    'punch_failed' => (l10n.connReasonPunchFailed, retryClose),
    'rendezvous_failed' => (
        l10n.connReasonRendezvousFailed,
        [NextStep.retry]
      ),
    'secure_tcp_failed' => (l10n.connReasonSecureTcpFailed, [NextStep.retry]),
    'direct_reset' => (
        l10n.connReasonDirectReset,
        [NextStep.useRelay, NextStep.retry, NextStep.closeTab]
      ),
    'direct_failed' => (l10n.connReasonDirectFailed, retryClose),
    'relay_failed' => (l10n.connReasonRelayFailed, retryClose),
    'peer_id_changed' => (
        l10n.connReasonPeerIdChanged,
        [NextStep.changeId, NextStep.closeTab]
      ),
    'linux_login_screen' => (l10n.connReasonLinuxLoginScreen, close),
    'too_many_attempts' => (l10n.connReasonTooManyAttempts, close),
    'blocked' => (l10n.connReasonBlocked, close),
    'not_allowed' => (l10n.connReasonNotAllowed, close),
    'main_window_not_open' => (
        l10n.connReasonMainWindowNotOpen,
        [NextStep.retry]
      ),
    'installed_only' => (l10n.connReasonInstalledOnly, close),
    'no_permission' => (
        switch (reason.params['feature']) {
          'camera' => l10n.connReasonNoPermissionCamera,
          'terminal' => l10n.connReasonNoPermissionTerminal,
          'port_forward' => l10n.connReasonNoPermissionPortForward,
          _ => l10n.connReasonNoPermissionFileTransfer,
        },
        close
      ),
    'privacy_mode_occupied' => (l10n.connReasonPrivacyModeOccupied, close),
    'peer_too_old' => (
        switch (reason.params['feature']) {
          'terminal' => l10n.connReasonPeerTooOldTerminal,
          'port_forward' => l10n.connReasonPeerTooOldPortForward,
          _ => l10n.connReasonPeerTooOldCamera,
        },
        close
      ),
    'reset_by_peer' => (l10n.connReasonResetByPeer, [NextStep.retry]),
    'timeout' => (l10n.connReasonTimeout, [NextStep.retry]),
    'closed_by_peer' => (
        l10n.connReasonClosedByPeer,
        [NextStep.reconnect, NextStep.closeTab]
      ),
    'inactivity' => (l10n.connReasonInactivity, [NextStep.reconnect]),
    'no_displays' => (l10n.connReasonNoDisplays, close),
    _ => (reason.text, retryClose),
  };
  return (text: text, steps: steps.isEmpty ? close : steps);
}

/// The session ended rather than broke: someone closed it (01 §2.1 "已断开", §7.6 术语表).
bool isDisconnected(ConnReason reason) =>
    reason.code == 'closed_by_peer' || reason.code == 'inactivity';
