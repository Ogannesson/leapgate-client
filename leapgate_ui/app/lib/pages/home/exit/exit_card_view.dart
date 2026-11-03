import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/connection.dart' show ConnReason;
import 'package:flutter_hbb/leapgate/exit_card.dart';
import 'package:flutter_hbb/leapgate/exit_nodes.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_device.dart';
import '../../../widgets/lg_exit_card.dart';
import '../../session/reasons.dart';
import '../password_row.dart' show copyWithToast;

// An exit card (01 P1 block I card table) over [ExitCard], drawn by [LgExitCard] (`LEAPGATE.md`
// §10.12 "组件接口").

/// The reason after "已停止：", and whether "Retry" can help (01 P1 block I): not for an old
/// version, an unencrypted connection or an ID Rust would change. Null without a reason.
({String? reason, bool retry}) exitStoppedView(
  AppLocalizations l10n,
  ConnReason? reason,
  String id,
) {
  if (reason == null) return (reason: null, retry: true);
  final (text, retry) = switch (reason.code) {
    'exit_not_enabled' => (l10n.exitReasonNotEnabled, true),
    'exit_not_supported' ||
    'peer_too_old' => (l10n.exitReasonNotSupported, false),
    'exit_need_encryption' => (l10n.exitReasonNeedEncryption, false),
    'too_many_attempts' => (l10n.exitReasonTooManyAttempts, true),
    'exit_already' => (l10n.exitReasonAlready, true),
    'exit_invalid_id' => (l10n.exitBadId, false),
    // Only its first sentence, without the full stop (01 §7.6).
    _ => (
      RegExp(
            r'^[^。]*?(?=。|\.(?:\s|$)|$)',
          ).firstMatch(reasonView(l10n, reason, id).text)?.group(0) ??
          '',
      true,
    ),
  };
  return (reason: text.isEmpty ? null : text, retry: retry);
}

/// The card's name: given with "Use", else the remote host name, else the ID.
String exitCardName(ExitCard card) => card.name ?? formatPeerId(card.id);

final _promptFocus = <String>{};

/// The user asked [id] to log in ("使用", "用作出口", "重试", "重新连接"): its next password or
/// code prompt takes the keyboard. A prompt that comes by itself on a reconnect does not
/// (`LEAPGATE.md` §10.12 "整合时要注意的").
void focusExitPromptOf(String id) => _promptFocus.add(id);

class ExitCardView extends StatefulWidget {
  const ExitCardView({super.key, required this.card});

  final ExitCard card;

  @override
  State<ExitCardView> createState() => _ExitCardViewState();
}

class _ExitCardViewState extends State<ExitCardView> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _port = TextEditingController();
  final _passwordFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _portFocus = FocusNode();
  final _changePortFocus = FocusNode();
  var _remember = false;
  var _trust = false;
  var _editingPort = false;
  ExitPortError? _portError;
  var _helpOpen = false;
  Timer? _ticker;
  late ExitCardState _state;

  ExitCard get _card => widget.card;

  @override
  void initState() {
    super.initState();
    _state = _card.state;
    _remember = _card.rememberPassword;
    _card.addListener(_onCard);
    _password.addListener(_rebuild);
    _syncTicker();
  }

  @override
  void dispose() {
    _card.removeListener(_onCard);
    _ticker?.cancel();
    _password.dispose();
    _code.dispose();
    _port.dispose();
    _passwordFocus.dispose();
    _codeFocus.dispose();
    _portFocus.dispose();
    _changePortFocus.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  /// Once the field is built. A node that is not on the card then (a port change that went on
  /// to connecting) is left alone: it would take the focus whenever it next appears.
  void _focusLater(FocusNode node) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && node.context != null) node.requestFocus();
      });

  void _onCard() {
    final state = _card.state;
    if (state != _state) {
      if (_state == ExitCardState.password) _password.clear();
      if (state == ExitCardState.password) _remember = _card.rememberPassword;
      if (state == ExitCardState.twoFactor) _code.clear();
      final prompt =
          state == ExitCardState.password || state == ExitCardState.twoFactor;
      if (prompt) {
        // Asked by the user, or asked again after a wrong entry (Enter took the focus away).
        if (_promptFocus.remove(_card.id) || _card.wrongInput) {
          _focusLater(
            state == ExitCardState.password ? _passwordFocus : _codeFocus,
          );
        }
      } else if (!const {
        ExitCardState.connecting,
        ExitCardState.verifying,
        ExitCardState.waitAccept,
      }.contains(state)) {
        _promptFocus.remove(_card.id);
      }
      // The port edit belongs to "in use" and "port in use".
      if (state != ExitCardState.inUse && state != ExitCardState.portBusy) {
        _editingPort = false;
        _portError = null;
      }
      _state = state;
      _syncTicker();
    }
    setState(() {});
  }

  /// "（已等待 0:12）" goes with the seconds.
  void _syncTicker() {
    if (_card.state == ExitCardState.waitAccept) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _rebuild());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _editPort() {
    setState(() {
      _editingPort = true;
      _portError = null;
      _port.text = '${_card.port}';
    });
    _focusLater(_portFocus);
  }

  void _closePort() {
    setState(() => _editingPort = false);
    _focusLater(_changePortFocus);
  }

  void _confirmPort() {
    final port = int.tryParse(_port.text.trim());
    final error = port == null ? ExitPortError.invalid : _card.changePort(port);
    if (error == null) return _closePort();
    setState(() => _portError = error);
    // Enter took the focus out of the field.
    _focusLater(_portFocus);
  }

  void _retry() {
    focusExitPromptOf(_card.id);
    _card.retry();
  }

  String _waited() {
    final since = _card.waitingSince;
    final s = since == null ? 0 : DateTime.now().difference(since).inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final card = _card;
    final name = exitCardName(card);
    final state = card.state;

    // With several cards on the page, a screen reader tells their buttons apart by the name.
    LgExitAction action(
      String label,
      VoidCallback? onPressed, {
      LgButtonKind kind = LgButtonKind.secondary,
      LgIcons? icon,
      bool named = false,
    }) => LgExitAction(
      label: label,
      onPressed: onPressed,
      kind: kind,
      icon: icon,
      semanticLabel: named ? l10n.exitActionFor(label, name) : null,
    );
    final cancel = action(l10n.connCancel, card.cancel, named: true);
    final stop = action(
      l10n.exitStop,
      card.stop,
      icon: LgIcons.square,
      named: true,
    );
    final remove = action(
      l10n.exitRemove,
      card.stop,
      icon: LgIcons.trash,
      named: true,
    );
    LgExitAction changePort(LgButtonKind kind) => LgExitAction(
      label: l10n.exitChangePort,
      onPressed: _editPort,
      kind: kind,
      icon: LgIcons.edit,
      focusNode: _changePortFocus,
    );

    LgExitStatus status;
    LgExitPasswordArea? password;
    LgExitCodeArea? code;
    var addresses = false;
    var leading = <LgExitAction>[];
    var actions = <LgExitAction>[];
    switch (state) {
      case ExitCardState.connecting:
        status = LgExitStatus(
          LgExitStatusKind.busy,
          l10n.connConnectingTo(name),
        );
        actions = [cancel];
      case ExitCardState.password:
        // The connection panel's words and button (01 P1 block I).
        void login() =>
            card.submitPassword(_password.text, remember: _remember);
        status = LgExitStatus(
          LgExitStatusKind.password,
          l10n.connEnterPassword,
        );
        password = LgExitPasswordArea(
          controller: _password,
          focusNode: _passwordFocus,
          semanticLabel: l10n.connPassword,
          placeholder: l10n.connPassword,
          showLabel: l10n.connShowPassword,
          hideLabel: l10n.connHidePassword,
          rememberLabel: l10n.connRememberPassword,
          remember: _remember,
          onRememberChanged: (v) => setState(() => _remember = v),
          onSubmitted: (_) => login(),
          errorText: card.wrongInput ? l10n.connWrongPassword : null,
        );
        actions = [
          action(
            l10n.connConnect,
            _password.text.trim().isEmpty ? null : login,
            kind: LgButtonKind.primary,
          ),
          cancel,
        ];
      case ExitCardState.twoFactor:
        void verify() => card.submit2fa(_code.text, trust: _trust);
        final trusted = card.trustedDevicesEnabled;
        status = LgExitStatus(LgExitStatusKind.code, l10n.exitEnterCode);
        code = LgExitCodeArea(
          controller: _code,
          focusNode: _codeFocus,
          semanticLabel: l10n.connCode,
          trustLabel: trusted ? l10n.connTrustThisDevice : null,
          trust: trusted ? _trust : null,
          onTrustChanged: (v) => setState(() => _trust = v),
          errorText: card.wrongInput ? l10n.connWrong2fa : null,
          onCompleted: (_) => verify(),
        );
        actions = [
          action(l10n.connVerify, verify, kind: LgButtonKind.primary),
          cancel,
        ];
      case ExitCardState.verifying:
        status = LgExitStatus(LgExitStatusKind.busy, l10n.connVerifying);
        actions = [cancel];
      case ExitCardState.waitAccept:
        status = LgExitStatus(
          LgExitStatusKind.busy,
          l10n.connWaitingAccept,
          elapsed: l10n.exitWaited(_waited()),
        );
        actions = [cancel];
      case ExitCardState.inUse:
        status = card.direct
            ? LgExitStatus(LgExitStatusKind.direct, l10n.exitInUseDirect)
            : LgExitStatus(
                LgExitStatusKind.relay,
                l10n.exitInUseRelay,
                note: l10n.exitRelayNote,
              );
        addresses = true;
        leading = [
          changePort(LgButtonKind.text),
          LgExitAction(
            label: l10n.exitBrowserSetup,
            onPressed: () => setState(() => _helpOpen = !_helpOpen),
            expanded: _helpOpen,
          ),
        ];
        actions = [stop];
      case ExitCardState.interrupted:
        // A failed login says why under it, so a mistyped ID shows (01 P1 block I).
        status = LgExitStatus(
          LgExitStatusKind.warning,
          l10n.exitInterrupted,
          note: exitStoppedView(l10n, card.interruptReason, card.id).reason,
        );
        // The listener stays open, so the addresses still work (M5-10).
        addresses = true;
        actions = [
          action(
            l10n.connReconnect,
            _retry,
            kind: LgButtonKind.primary,
            icon: LgIcons.restart,
            named: true,
          ),
          stop,
        ];
      case ExitCardState.stopped:
        final view = exitStoppedView(l10n, card.stopReason, card.id);
        status = LgExitStatus(
          LgExitStatusKind.error,
          view.reason == null ? l10n.exitStoppedPlain : l10n.exitStoppedPrefix,
          reason: view.reason,
        );
        actions = [
          if (view.retry)
            action(
              l10n.connRetry,
              _retry,
              kind: LgButtonKind.primary,
              icon: LgIcons.refresh,
              named: true,
            ),
          remove,
        ];
      case ExitCardState.portBusy:
        status = LgExitStatus(
          LgExitStatusKind.error,
          l10n.exitPortBusy(card.busyPort),
        );
        actions = [changePort(LgButtonKind.primary), remove];
    }

    final editingPort = _editingPort;
    return LgExitCard(
      name: name,
      id: formatPeerId(card.id),
      // Only Windows serves as an exit node (`libs/leapgate/src/exit/mod.rs`).
      platform: LgPlatform.windows,
      status: status,
      password: password,
      code: code,
      addresses: [
        if (addresses)
          for (final (address, label) in [
            (card.socksAddress, l10n.exitCopySocks),
            (card.httpAddress, l10n.exitCopyHttp),
          ])
            LgExitAddress(
              address: address,
              copyLabel: label,
              onCopy: () => copyWithToast(address),
            ),
      ],
      notices: [
        for (final notice in card.notices)
          LgExitNotice(
            id: notice,
            text: notice == 'exit_blocked'
                ? l10n.exitNoticeBlocked
                : l10n.exitNoticeFakeIp,
            dismissLabel: l10n.sessionNoticeDismiss,
            onDismiss: () => card.dismissNotice(notice),
          ),
      ],
      portEdit: editingPort
          ? LgExitPortEdit(
              controller: _port,
              focusNode: _portFocus,
              semanticLabel: l10n.exitPort,
              confirmLabel: l10n.homeOk,
              cancelLabel: l10n.homeCancel,
              onConfirm: _confirmPort,
              onCancel: _closePort,
              hint: state == ExitCardState.inUse ? l10n.exitPortHint : null,
              errorText: switch (_portError) {
                ExitPortError.invalid => l10n.exitPortInvalid,
                ExitPortError.taken => l10n.exitPortTaken,
                null => null,
              },
            )
          : null,
      leadingActions: editingPort ? const [] : leading,
      actions: editingPort ? const [] : actions,
      help: _helpOpen && state == ExitCardState.inUse
          ? LgExitHelp(
              title: l10n.exitBrowserSetup,
              items: [
                LgExitHelpItem(l10n.exitHelpTcp),
                LgExitHelpItem(l10n.exitHelpApps),
                LgExitHelpItem(l10n.exitHelpFirefox),
                LgExitHelpItem(
                  l10n.exitHelpChrome,
                  code: '--proxy-server=socks5://127.0.0.1:${card.port}',
                  after: l10n.exitHelpChromeAfter,
                ),
              ],
            )
          : null,
    );
  }
}
