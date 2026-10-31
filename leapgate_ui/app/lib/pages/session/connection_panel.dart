import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../../l10n/app_localizations.dart';
import '../../shell/navigation.dart';
import '../../widgets/lg_connection_panel.dart';
import '../../widgets/lg_panel_inputs.dart';
import '../../widgets/lg_selection.dart';
import 'reasons.dart';
import 'session_names.dart';

/// After this long on "已连接，正在等待画面…" the panel adds why the image may not come
/// (01 P2 block D "超过几秒").
const kWaitingImageHintAfter = 5;

/// The connection panel (01 P2 block D, §4.1, §4.3): what [ConnectionModel] says, in the middle of
/// the session tab while there is no image, drawn by [LgConnectionPanel].
///
/// Enter runs the button marked `isDefault`: "断开" on the insecure connection warning, the
/// submit button of the password and code panels, "连接" of the Windows user sessions. An
/// error has none (upstream's box has no default action, and "改用中继" would be saved for the
/// device).
class ConnectionPanel extends StatefulWidget {
  const ConnectionPanel({super.key, required this.ffi, required this.active});

  final FFI ffi;

  /// Its tab is the selected one.
  final bool active;

  @override
  State<ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends State<ConnectionPanel> {
  final _password = TextEditingController();
  final _code = TextEditingController();

  /// The password or code field, whichever shows.
  final _inputFocus = FocusNode();
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

  /// A field that came up while the tab was in the background could not take the focus
  /// (`autofocus` is refused there); it takes it when the tab is selected. The image does not
  /// take the keyboard back this way, the panel's field does.
  @override
  void didUpdateWidget(ConnectionPanel old) {
    super.didUpdateWidget(old);
    if (!old.active && widget.active && _inputFocus.context != null) {
      _inputFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _conn.removeListener(_onChange);
    _ticker?.cancel();
    _password.dispose();
    _code.dispose();
    _inputFocus.dispose();
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
    final conn = _conn;
    final ffi = widget.ffi;

    List<LgPanelStep>? steps;
    var tone = LgPanelTone.normal;
    String? message;
    var busy = false;
    String? secondary;
    String? notice;
    LgPanelCountdown? countdown;
    var dim = false;
    final inputs = <Widget>[];
    final actions = <LgPanelAction>[];
    final cancel = LgPanelAction(label: l10n.connCancel, onPressed: conn.cancel);

    List<LgPanelStep> twoSteps(LgStepState connect, LgStepState verify) => [
          LgPanelStep(l10n.connStepConnect, connect),
          LgPanelStep(l10n.connStepVerify, verify),
        ];

    switch (conn.stage) {
      case ConnStage.connecting:
        steps = twoSteps(LgStepState.current, LgStepState.todo);
        message = l10n.connConnectingTo(deviceName(ffi));
        busy = true;
        actions.add(cancel);
      case ConnStage.insecure:
        steps = twoSteps(LgStepState.current, LgStepState.todo);
        tone = LgPanelTone.warning;
        message = l10n.connInsecure;
        actions
          ..add(LgPanelAction(
              label: l10n.connContinue, onPressed: conn.continueInsecure))
          ..add(LgPanelAction(
              label: l10n.connDisconnect,
              onPressed: conn.rejectInsecure,
              primary: true,
              isDefault: true));
      case ConnStage.verifying:
        steps = twoSteps(LgStepState.done, LgStepState.current);
        switch (conn.input) {
          case ConnInput.password:
            inputs
              ..add(LgPasswordField(
                controller: _password,
                focusNode: _inputFocus,
                showLabel: l10n.connShowPassword,
                hideLabel: l10n.connHidePassword,
                placeholder: l10n.connPassword,
                semanticLabel: l10n.connPassword,
                autofocus: true,
                errorText: conn.reason?.code == 'wrong_password'
                    ? l10n.connWrongPassword
                    : null,
              ))
              ..add(LgCheckbox(
                value: _remember,
                label: l10n.connRememberPassword,
                onChanged: (v) => setState(() => _remember = v),
              ));
            // An empty password does nothing upstream; here the button says so (01 P2 block D).
            actions
              ..add(cancel)
              ..add(LgPanelAction(
                  label: l10n.connConnect,
                  onPressed: _password.text.trim().isEmpty ? null : _login,
                  primary: true,
                  isDefault: true));
          case ConnInput.twoFactor:
            inputs.add(LgCodeField(
              controller: _code,
              focusNode: _inputFocus,
              semanticLabel: l10n.connCode,
              autofocus: true,
              errorText:
                  conn.reason?.code == 'wrong_2fa' ? l10n.connWrong2fa : null,
              // Six digits submit by themselves.
              onCompleted: (_) => _submit2fa(),
            ));
            if (conn.trustedDevicesEnabled) {
              inputs.add(LgCheckbox(
                value: _trust,
                label: l10n.connTrustThisDevice,
                onChanged: (v) => setState(() => _trust = v),
              ));
            }
            actions
              ..add(cancel)
              ..add(LgPanelAction(
                  label: l10n.connVerify,
                  onPressed: _submit2fa,
                  primary: true,
                  isDefault: true));
          case ConnInput.remoteAccept:
            message = l10n.connWaitingAccept;
            busy = true;
            secondary = l10n.connWaited(_duration(l10n, _elapsed));
            actions.add(cancel);
          case ConnInput.windowsSession:
            message = l10n.connChooseWindowsSession;
            inputs.add(LgSelectField<String>(
              items: [
                for (final s in conn.windowsSessions) LgSelectItem(s.sid, s.name)
              ],
              value: _windowsSession,
              semanticLabel: l10n.connChooseWindowsSession,
              onChanged: (v) => setState(() => _windowsSession = v),
            ));
            // No cancel: upstream says closing it leaves a black screen.
            actions.add(LgPanelAction(
              label: l10n.connConnect,
              onPressed: _windowsSession == null
                  ? null
                  : () => conn.selectWindowsSession(_windowsSession!),
              primary: true,
              isDefault: true,
            ));
          // The terminal's OS account is round 3; M2a opens remote desktops only.
          case ConnInput.osAccount:
          case ConnInput.osAccountAndPassword:
          case ConnInput.none:
            message = l10n.connVerifying;
            busy = true;
            actions.add(cancel);
        }
      case ConnStage.waitingForImage:
        steps = twoSteps(LgStepState.done, LgStepState.done);
        message = l10n.connWaitingImage;
        busy = true;
        if (_elapsed >= kWaitingImageHintAfter) {
          notice = l10n.connWaitingImageHint;
        }
        actions.add(cancel);
      case ConnStage.restarting:
        message = l10n.connRestarting;
        busy = true;
        dim = true;
        actions.add(
            LgPanelAction(label: l10n.connCloseTab, onPressed: conn.cancel));
      case ConnStage.failed:
        final view = reasonView(l10n, conn.reason!, ffi.id);
        message = view.text;
        final left = conn.retryCountdown;
        if (left != null) {
          tone = LgPanelTone.warning;
          // The wait doubles from 1 s with each attempt (ConnectionModel.showMsgBox).
          final total = 1 << (conn.retryAttempt - 1);
          countdown = LgPanelCountdown(
            text: l10n.connRetryIn(left, conn.retryAttempt),
            progress: 1 - left / total,
          );
        } else {
          tone = LgPanelTone.error;
        }
        // The first next step is the main one and goes last, as the panel lays them out.
        for (final (i, step) in view.steps.indexed.toList().reversed) {
          final VoidCallback onPressed = switch (step) {
            NextStep.retry || NextStep.reconnect => conn.retry,
            NextStep.useRelay => conn.useRelay,
            // The failed tab goes; the ID waits in the connect box.
            NextStep.changeId => () {
                conn.cancel();
                mainNavigation.showHome(connectBoxText: ffi.id);
              },
            NextStep.closeTab => conn.cancel,
          };
          actions.add(LgPanelAction(
            label: switch (step) {
              NextStep.retry => l10n.connRetry,
              NextStep.reconnect => l10n.connReconnect,
              NextStep.useRelay => l10n.connUseRelay,
              NextStep.changeId => l10n.connChangeId,
              NextStep.closeTab => l10n.connCloseTab,
            },
            onPressed: onPressed,
            primary: i == 0,
          ));
        }
      case ConnStage.connected:
        return const SizedBox.shrink();
    }

    return LgConnectionPanel(
      title: deviceName(ffi),
      subtitle: formatPeerId(ffi.id),
      platform: platformOf(ffi),
      steps: steps,
      tone: tone,
      message: message,
      busy: busy,
      secondary: secondary,
      notice: notice,
      countdown: countdown,
      inputs: inputs,
      actions: actions,
      dimBackdrop: dim,
    );
  }
}
