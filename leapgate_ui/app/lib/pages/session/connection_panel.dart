import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/confirm_card.dart';
import '../../shell/navigation.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_selection.dart';
import '../../widgets/lg_status.dart';
import '../../widgets/lg_text_field.dart';
import 'reasons.dart';
import 'session_names.dart';

/// After this long on "已连接，正在等待画面…" the panel adds why the image may not come
/// (01 P2 block D "超过几秒").
const kWaitingImageHintAfter = 5;

enum _Step { pending, active, done }

/// The connection panel (01 P2 block D, §4.1, §4.3): what [ConnectionModel] says, in the middle of
/// the session tab while there is no image. Placeholder look until the designer's
/// `LgConnectionPanel` replaces it; the texts, inputs and buttons are final.
class ConnectionPanel extends StatefulWidget {
  const ConnectionPanel({super.key, required this.ffi});

  final FFI ffi;

  @override
  State<ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends State<ConnectionPanel> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  var _showPassword = false;
  var _remember = false;
  var _trust = false;
  String? _windowsSession;

  /// Seconds in the current stage and input, for "已等待" and the waiting-for-image hint.
  var _elapsed = 0;
  Timer? _ticker;
  (ConnStage, ConnInput)? _shown;

  ConnectionModel get _conn => widget.ffi.connection;

  @override
  void initState() {
    super.initState();
    _conn.addListener(_onChange);
    _onChange();
  }

  @override
  void dispose() {
    _conn.removeListener(_onChange);
    _ticker?.cancel();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  /// A new question starts with empty fields and the saved "remember password"; the timer runs
  /// only where a duration shows.
  void _onChange() {
    final shown = (_conn.stage, _conn.input);
    if (shown == _shown) return;
    _shown = shown;
    _password.clear();
    _code.clear();
    _remember = _conn.rememberPassword;
    _trust = false;
    _windowsSession = _conn.windowsSessions.firstOrNull?.sid;
    _elapsed = 0;
    _ticker?.cancel();
    _ticker = null;
    final timed = _conn.stage == ConnStage.waitingForImage ||
        (_conn.stage == ConnStage.verifying &&
            _conn.input == ConnInput.remoteAccept);
    if (timed) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed++);
      });
    }
  }

  void _login() {
    _conn.login(password: _password.text, remember: _remember);
  }

  void _submit2fa() => _conn.submit2fa(_code.text, trustThisDevice: _trust);

  String _duration(AppLocalizations l10n, int seconds) => seconds < 60
      ? l10n.connSeconds(seconds)
      : l10n.connMinutesSeconds(seconds ~/ 60, seconds % 60);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: Listenable.merge([_conn, _password, _code]),
        builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final c = t.colors;
    final conn = _conn;
    final ffi = widget.ffi;

    _Step? connectStep, verifyStep;
    String? text;
    String? detail;
    String? error;
    final inputs = <Widget>[];
    final buttons = <(String, VoidCallback?, LgButtonKind)>[];
    final cancel = (l10n.connCancel, conn.cancel, LgButtonKind.secondary);

    switch (conn.stage) {
      case ConnStage.connecting:
        connectStep = _Step.active;
        verifyStep = _Step.pending;
        text = l10n.connConnectingTo(deviceName(ffi));
        buttons.add(cancel);
      case ConnStage.insecure:
        connectStep = _Step.active;
        verifyStep = _Step.pending;
        text = l10n.connInsecure;
        buttons
          ..add((l10n.connContinue, conn.continueInsecure, LgButtonKind.secondary))
          ..add((l10n.connDisconnect, conn.rejectInsecure, LgButtonKind.primary));
      case ConnStage.verifying:
        connectStep = _Step.done;
        verifyStep = _Step.active;
        switch (conn.input) {
          case ConnInput.password:
            if (conn.reason?.code == 'wrong_password') {
              error = l10n.connWrongPassword;
            }
            inputs
              ..add(LgTextField(
                controller: _password,
                placeholder: l10n.connPassword,
                semanticLabel: l10n.connPassword,
                obscureText: !_showPassword,
                autofocus: true,
                errorText: error,
                onSubmitted: (_) => _login(),
                trailing: LgIconButton(
                  icon: _showPassword ? LgIcons.eyeOff : LgIcons.eye,
                  label: _showPassword
                      ? l10n.connHidePassword
                      : l10n.connShowPassword,
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ))
              ..add(LgCheckbox(
                value: _remember,
                label: l10n.connRememberPassword,
                onChanged: (v) => setState(() => _remember = v),
              ));
            // An empty password does nothing upstream; here the button says so (01 P2 block D).
            buttons
              ..add((
                l10n.connConnect,
                _password.text.trim().isEmpty ? null : _login,
                LgButtonKind.primary
              ))
              ..add(cancel);
          case ConnInput.twoFactor:
            if (conn.reason?.code == 'wrong_2fa') error = l10n.connWrong2fa;
            inputs.add(LgTextField(
              controller: _code,
              placeholder: l10n.connCode,
              semanticLabel: l10n.connCode,
              autofocus: true,
              errorText: error,
              onSubmitted: (_) => _submit2fa(),
              // Six digits submit by themselves.
              onChanged: (v) {
                if (v.trim().length == 6) _submit2fa();
              },
            ));
            if (conn.trustedDevicesEnabled) {
              inputs.add(LgCheckbox(
                value: _trust,
                label: l10n.connTrustThisDevice,
                onChanged: (v) => setState(() => _trust = v),
              ));
            }
            buttons
              ..add((l10n.connVerify, _submit2fa, LgButtonKind.primary))
              ..add(cancel);
          case ConnInput.remoteAccept:
            text = l10n.connWaitingAccept;
            detail = l10n.connWaited(_duration(l10n, _elapsed));
            buttons.add(cancel);
          case ConnInput.windowsSession:
            text = l10n.connChooseWindowsSession;
            for (final s in conn.windowsSessions) {
              inputs.add(LgRadio<String>(
                value: s.sid,
                groupValue: _windowsSession,
                label: s.name,
                onChanged: (v) => setState(() => _windowsSession = v),
              ));
            }
            // No cancel: upstream says closing it leaves a black screen.
            buttons.add((
              l10n.connConnect,
              _windowsSession == null
                  ? null
                  : () => conn.selectWindowsSession(_windowsSession!),
              LgButtonKind.primary
            ));
          // The terminal's OS account is round 3; M2a opens remote desktops only.
          case ConnInput.osAccount:
          case ConnInput.osAccountAndPassword:
          case ConnInput.none:
            text = l10n.connVerifying;
            buttons.add(cancel);
        }
      case ConnStage.waitingForImage:
        connectStep = _Step.done;
        verifyStep = _Step.done;
        text = l10n.connWaitingImage;
        if (_elapsed >= kWaitingImageHintAfter) {
          detail = l10n.connWaitingImageHint;
        }
        buttons.add(cancel);
      case ConnStage.restarting:
        text = l10n.connRestarting;
        buttons.add((l10n.connCloseTab, conn.cancel, LgButtonKind.secondary));
      case ConnStage.failed:
        final view = reasonView(l10n, conn.reason!, ffi.id);
        text = view.text;
        final countdown = conn.retryCountdown;
        if (countdown != null) {
          detail = l10n.connRetryIn(countdown, conn.retryAttempt);
        }
        // The first step is the main one.
        for (final (i, step) in view.steps.indexed) {
          final kind = i == 0 ? LgButtonKind.primary : LgButtonKind.secondary;
          buttons.add(switch (step) {
            NextStep.retry => (l10n.connRetry, conn.retry, kind),
            NextStep.reconnect => (l10n.connReconnect, conn.retry, kind),
            NextStep.useRelay => (l10n.connUseRelay, conn.useRelay, kind),
            NextStep.changeId => (
                l10n.connChangeId,
                // The failed tab goes; the ID waits in the connect box.
                () {
                  conn.cancel();
                  mainNavigation.showHome(connectBoxText: ffi.id);
                },
                kind
              ),
            NextStep.closeTab => (l10n.connCloseTab, conn.cancel, kind),
          });
        }
      case ConnStage.connected:
        return const SizedBox.shrink();
    }

    final panel = Container(
      width: 440,
      padding: const EdgeInsets.all(LgSpace.s6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(LgRadius.r12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(deviceName(ffi),
              style: t.text.copyWith(color: c.text, fontWeight: FontWeight.w700)),
          Text(formatId(ffi.id), style: t.textS.copyWith(color: c.text2)),
          if (connectStep != null) ...[
            const SizedBox(height: LgSpace.s4),
            Row(children: [
              _StepMark(connectStep, l10n.connStepConnect),
              const SizedBox(width: LgSpace.s4),
              _StepMark(verifyStep!, l10n.connStepVerify),
            ]),
          ],
          if (text != null) ...[
            const SizedBox(height: LgSpace.s4),
            Text(text, style: t.text.copyWith(color: c.text)),
          ],
          if (detail != null) ...[
            const SizedBox(height: LgSpace.s2),
            Text(detail, style: t.textS.copyWith(color: c.text2)),
          ],
          for (final input in inputs) ...[
            const SizedBox(height: LgSpace.s3),
            input,
          ],
          if (buttons.isNotEmpty) ...[
            const SizedBox(height: LgSpace.s6),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: LgSpace.s2,
              runSpacing: LgSpace.s2,
              children: [
                for (final (label, onPressed, kind) in buttons.reversed)
                  LgButton(label: label, kind: kind, onPressed: onPressed),
              ],
            ),
          ],
        ],
      ),
    );
    // Enter disconnects only on the insecure connection warning (01 P2 block D); upstream's
    // error box has no default action, and "Use relay" would be saved for the device. The
    // password and code fields submit by themselves.
    if (conn.stage != ConnStage.insecure) return panel;
    return DefaultActionScope(onDefault: conn.rejectInsecure, child: panel);
  }
}

class _StepMark extends StatelessWidget {
  const _StepMark(this.step, this.label);

  final _Step step;
  final String label;

  @override
  Widget build(BuildContext context) {
    final status = switch (step) {
      _Step.pending => LgStatus.offline,
      _Step.active => LgStatus.connecting,
      _Step.done => LgStatus.online,
    };
    return LgStatusText(status, label);
  }
}
