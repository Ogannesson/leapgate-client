import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/connection.dart' show ConnReason;
import 'package:flutter_hbb/leapgate/exit_card.dart';
import 'package:flutter_hbb/leapgate/exit_nodes.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;

import '../../../l10n/app_localizations.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_banner.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_panel_inputs.dart';
import '../../../widgets/lg_selection.dart';
import '../../../widgets/lg_status.dart';
import '../../../widgets/lg_text_field.dart';
import '../../session/reasons.dart';
import '../password_row.dart' show copyWithToast;

// An exit card (01 P1 block I card table) over [ExitCard]. Placeholder layout until designer's
// card component (`LEAPGATE.md` §10.12 "组件"); the texts and the buttons are final.

/// "已停止：…" and whether "Retry" can help (01 P1 block I): not for an old version or an
/// unencrypted connection.
({String text, bool retry}) exitStoppedView(
  AppLocalizations l10n,
  ConnReason? reason,
  String id,
) {
  if (reason == null) return (text: l10n.exitStoppedPlain, retry: true);
  final (text, retry) = switch (reason.code) {
    'exit_not_enabled' => (l10n.exitReasonNotEnabled, true),
    'exit_not_supported' ||
    'peer_too_old' => (l10n.exitReasonNotSupported, false),
    'exit_need_encryption' => (l10n.exitReasonNeedEncryption, false),
    'too_many_attempts' => (l10n.exitReasonTooManyAttempts, true),
    'exit_already' => (l10n.exitReasonAlready, true),
    // After "已停止：" only its first sentence, without the full stop (01 §7.6).
    _ => (
      RegExp(
            r'^[^。]*?(?=。|\.(?:\s|$)|$)',
          ).firstMatch(reasonView(l10n, reason, id).text)?.group(0) ??
          '',
      true,
    ),
  };
  return (
    text: text.isEmpty ? l10n.exitStoppedPlain : l10n.exitStopped(text),
    retry: retry,
  );
}

/// The card's name: given with "Use", else the remote host name, else the ID.
String exitCardName(ExitCard card) => card.name ?? formatPeerId(card.id);

class ExitCardView extends StatefulWidget {
  const ExitCardView({super.key, required this.card, this.highlighted = false});

  final ExitCard card;

  /// Shortly after the page scrolled to it.
  final bool highlighted;

  @override
  State<ExitCardView> createState() => _ExitCardViewState();
}

class _ExitCardViewState extends State<ExitCardView> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _port = TextEditingController();
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
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _onCard() {
    final state = _card.state;
    if (state != _state) {
      if (_state == ExitCardState.password) _password.clear();
      if (state == ExitCardState.password) _remember = _card.rememberPassword;
      if (state == ExitCardState.twoFactor) _code.clear();
      _state = state;
      _syncTicker();
    }
    setState(() {});
  }

  /// "已等待 0:12" goes with the seconds.
  void _syncTicker() {
    if (_card.state == ExitCardState.waitAccept) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _rebuild());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _editPort() => setState(() {
    _editingPort = true;
    _portError = null;
    _port.text = '${_card.port}';
  });

  void _confirmPort() {
    final port = int.tryParse(_port.text.trim());
    final error = port == null ? ExitPortError.invalid : _card.changePort(port);
    setState(() {
      _portError = error;
      _editingPort = error != null;
    });
  }

  String _waited() {
    final since = _card.waitingSince;
    final s = since == null ? 0 : DateTime.now().difference(since).inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final c = t.colors;
    final card = _card;
    final name = exitCardName(card);
    final body = <Widget>[];
    final actions = <Widget>[];
    var addresses = false;

    LgButton button(
      String label,
      VoidCallback? onPressed, {
      LgButtonKind kind = LgButtonKind.secondary,
    }) => LgButton(label: label, onPressed: onPressed, kind: kind);
    final cancel = button(l10n.connCancel, card.cancel);
    final stop = button(l10n.exitStop, card.stop);
    final remove = button(l10n.exitRemove, card.stop);
    final changePort = button(
      l10n.exitChangePort,
      _editPort,
      kind: LgButtonKind.text,
    );

    switch (card.state) {
      case ExitCardState.connecting:
        body.add(
          LgStatusText(LgStatus.connecting, l10n.connConnectingTo(name)),
        );
        actions.add(cancel);
      case ExitCardState.password:
        // The connection panel's words and button (01 P1 block I).
        void login() =>
            card.submitPassword(_password.text, remember: _remember);
        body
          ..add(Text(l10n.connEnterPassword))
          ..add(
            LgPasswordField(
              controller: _password,
              showLabel: l10n.connShowPassword,
              hideLabel: l10n.connHidePassword,
              placeholder: l10n.connPassword,
              semanticLabel: l10n.connPassword,
              autofocus: true,
              errorText: card.wrongInput ? l10n.connWrongPassword : null,
              onSubmitted: (_) => login(),
            ),
          )
          ..add(
            LgCheckbox(
              value: _remember,
              label: l10n.connRememberPassword,
              onChanged: (v) => setState(() => _remember = v),
            ),
          );
        actions
          ..add(cancel)
          ..add(
            button(
              l10n.connConnect,
              _password.text.trim().isEmpty ? null : login,
              kind: LgButtonKind.primary,
            ),
          );
      case ExitCardState.twoFactor:
        void verify() => card.submit2fa(_code.text, trust: _trust);
        body
          ..add(Text(l10n.exitEnterCode))
          ..add(
            LgCodeField(
              controller: _code,
              semanticLabel: l10n.connCode,
              autofocus: true,
              errorText: card.wrongInput ? l10n.connWrong2fa : null,
              onCompleted: (_) => verify(),
            ),
          );
        if (card.trustedDevicesEnabled) {
          body.add(
            LgCheckbox(
              value: _trust,
              label: l10n.connTrustThisDevice,
              onChanged: (v) => setState(() => _trust = v),
            ),
          );
        }
        actions
          ..add(cancel)
          ..add(button(l10n.connVerify, verify, kind: LgButtonKind.primary));
      case ExitCardState.verifying:
        body.add(LgStatusText(LgStatus.connecting, l10n.connVerifying));
        actions.add(cancel);
      case ExitCardState.waitAccept:
        body.add(
          LgStatusText(LgStatus.connecting, l10n.exitWaiting(_waited())),
        );
        actions.add(cancel);
      case ExitCardState.inUse:
        body.add(
          LgStatusText(
            LgStatus.online,
            card.direct ? l10n.exitInUseDirect : l10n.exitInUseRelay,
          ),
        );
        if (!card.direct) {
          body.add(
            Text(l10n.exitRelayNote, style: t.textS.copyWith(color: c.text2)),
          );
        }
        addresses = true;
        if (!_editingPort) {
          actions.addAll([
            changePort,
            button(
              l10n.exitBrowserSetup,
              () => setState(() => _helpOpen = !_helpOpen),
              kind: LgButtonKind.text,
            ),
            stop,
          ]);
        }
      case ExitCardState.interrupted:
        body.add(LgStatusText(LgStatus.warning, l10n.exitInterrupted));
        // The listener stays open, so the addresses still work (M5-10).
        addresses = true;
        actions.addAll([button(l10n.connReconnect, card.retry), stop]);
      case ExitCardState.stopped:
        final view = exitStoppedView(l10n, card.stopReason, card.id);
        body.add(LgStatusText(LgStatus.warning, view.text));
        actions.addAll([
          if (view.retry) button(l10n.connRetry, card.retry),
          remove,
        ]);
      case ExitCardState.portBusy:
        body.add(
          LgStatusText(LgStatus.warning, l10n.exitPortBusy(card.busyPort)),
        );
        if (!_editingPort) actions.addAll([changePort, remove]);
    }

    if (addresses) {
      for (final (address, label) in [
        (card.socksAddress, l10n.exitCopySocks),
        (card.httpAddress, l10n.exitCopyHttp),
      ]) {
        body.add(
          Row(
            children: [
              Expanded(
                child: Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textS,
                ),
              ),
              button(
                label,
                () => copyWithToast(address),
                kind: LgButtonKind.text,
              ),
            ],
          ),
        );
      }
    }
    if (_editingPort) {
      body.add(
        Row(
          children: [
            Expanded(
              child: LgTextField(
                controller: _port,
                semanticLabel: l10n.exitPort,
                autofocus: true,
                maxLength: 5,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                errorText: switch (_portError) {
                  ExitPortError.invalid => l10n.exitPortInvalid,
                  ExitPortError.taken => l10n.exitPortTaken,
                  null => null,
                },
                onSubmitted: (_) => _confirmPort(),
              ),
            ),
            button(l10n.homeOk, _confirmPort, kind: LgButtonKind.primary),
            button(l10n.homeCancel, () => setState(() => _editingPort = false)),
          ],
        ),
      );
      if (card.state != ExitCardState.portBusy) {
        body.add(
          Text(l10n.exitPortHint, style: t.textS.copyWith(color: c.text2)),
        );
      }
    }
    if (_helpOpen && card.state == ExitCardState.inUse) {
      for (final line in [
        l10n.exitHelpTcp,
        l10n.exitHelpApps,
        l10n.exitHelpFirefox,
        l10n.exitHelpChrome('--proxy-server=socks5://127.0.0.1:${card.port}'),
      ]) {
        body.add(SelectableText('• $line', style: t.textS));
      }
    }
    for (final code in card.notices) {
      body.add(
        LgBanner(
          tone: LgTone.info,
          text: code == 'exit_blocked'
              ? l10n.exitNoticeBlocked
              : l10n.exitNoticeFakeIp,
          dismissLabel: l10n.sessionNoticeDismiss,
          onDismiss: () => card.dismissNotice(code),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(LgSpace.s4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(LgRadius.r12),
        border: Border.all(
          color: widget.highlighted ? c.accent : c.border,
          width: widget.highlighted ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: t.text.copyWith(fontWeight: FontWeight.w700)),
          Text(formatPeerId(card.id), style: t.textS.copyWith(color: c.text2)),
          const SizedBox(height: LgSpace.s2),
          for (final w in body)
            Padding(
              padding: const EdgeInsets.only(bottom: LgSpace.s2),
              child: w,
            ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: LgSpace.s2,
            runSpacing: LgSpace.s2,
            children: actions,
          ),
        ],
      ),
    );
  }
}
