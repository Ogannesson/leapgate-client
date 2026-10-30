// 上游：flutter/lib/models/model.dart@bd9262397 的 FfiModel 连接部分（改写：msgbox、connection_ready、set_multiple_windows_session、cancel_msgbox 的处理，handleMsgBox、showMsgBox、shouldAutoRetryOnOffline、reconnect、showConnectedWaitingForImage 和 common.dart、common/widgets/dialog.dart 里连接用的对话框改成状态加方法。上游这几段改了，合并时人工移植到这里）
import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

import 'app_core.dart';
import 'bridge.dart';
import 'notices.dart';
import 'session.dart';

/// Where a connection is, as the stages of 01 §4.1.
enum ConnStage {
  /// Stages 1 to 3: Rust reports nothing between finding the device and the channel being up.
  connecting,

  /// Stage 3a: the channel is not end-to-end encrypted and Rust waits for
  /// [ConnectionModel.continueInsecure] or [ConnectionModel.rejectInsecure].
  insecure,

  /// Stage 4: [ConnectionModel.input] says what the user is asked for.
  verifying,

  /// Stage 5: connected, no frame yet.
  waitingForImage,

  /// Stages 6 and 7.
  connected,

  /// Stage 7: the remote device restarts and the session reconnects by itself, keeping the last
  /// frame dimmed.
  restarting,

  /// Interrupted (stage 7) or ended (stage 8): [ConnectionModel.reason] says why, and
  /// [ConnectionModel.retryCountdown] counts down when it retries by itself.
  failed,
}

/// What the user is asked for while [ConnStage.verifying].
enum ConnInput {
  /// Nothing: the password or code went out and the answer is pending ("Verifying...").
  none,
  password,
  twoFactor,

  /// The OS account for a terminal session.
  osAccount,
  osAccountAndPassword,

  /// One of [ConnectionModel.windowsSessions].
  windowsSession,

  /// Nothing to enter: the remote side has to accept.
  remoteAccept,
}

/// Why a connection failed, or why a prompt is asked again: C3's reason code for the message
/// box (`LEAPGATE.md` §10.4) and the message box itself. With code `other` the UI shows [text].
class ConnReason {
  ConnReason._(this.code, this.params, this.type, this.title, this.text);

  factory ConnReason._of(String type, String title, String text) {
    final params = Map<String, dynamic>.from(jsonDecode(
        lgBind.leapgateMsgboxReason(msgtype: type, title: title, text: text)));
    return ConnReason._(params.remove('code'), params, type, title, text);
  }

  final String code;

  /// `feature` or `port` for the codes that take one.
  final Map<String, dynamic> params;

  final String type;
  final String title;
  final String text;
}

/// The connection state of one session (03 §3.3 item 3), replacing upstream's chain of modal
/// dialogs. The session page shows it as the connection panel (01 §3.2 block D) and calls its
/// methods; each method makes the bridge calls upstream's dialog buttons made.
class ConnectionModel with ChangeNotifier {
  ConnectionModel(this.parent) {
    final events = parent.target!.events;
    events.on('msgbox', handleMsgBox);
    events.on('set_multiple_windows_session', handleMultipleWindowsSession);
    events.on('connection_ready', (evt) {
      setConnectionType(evt['secure'] == 'true', evt['direct'] == 'true',
          evt['stream_type'] ?? '');
      resetRestartReconnectState();
      _show(ConnStage.verifying);
    });
    events.on('cancel_msgbox', (evt) {
      parent.target?.notices.dismissTag('${evt['tag']}');
    });
  }

  final WeakReference<FFI> parent;

  SessionID get sessionId => parent.target!.sessionId;

  var _stage = ConnStage.connecting;
  var _input = ConnInput.none;
  ConnReason? _reason;
  int? _retryCountdown;
  var _retryAttempt = 0;
  var _windowsSessions = <({String sid, String name})>[];
  var _rememberPassword = false;
  bool? _secure;
  bool? _direct;
  var _streamType = '';

  Timer? _timer;
  Timer? _restartReconnectDelayTimer;
  var _reconnects = 1;
  DateTime? _offlineReconnectStartTime;
  var _waitForImageDialogShow = true;
  Timer? _waitForImageTimer;

  ConnStage get stage => _stage;
  ConnInput get input => _input;

  /// Set when [stage] is [ConnStage.failed]; while asking for a password or a 2FA code again,
  /// `wrong_password` or `wrong_2fa`.
  ConnReason? get reason => _reason;

  /// Seconds until the automatic retry; null when it does not retry by itself.
  int? get retryCountdown => _retryCountdown;

  /// Which automatic retry [retryCountdown] counts down to, from 1.
  int get retryAttempt => _retryAttempt;

  bool get dimLastFrame => _stage == ConnStage.restarting;

  /// The user sessions to choose from with [selectWindowsSession].
  List<({String sid, String name})> get windowsSessions => _windowsSessions;

  /// Whether the password asked for is remembered, as saved for this device: the initial value
  /// of the panel's "Remember password".
  bool get rememberPassword => _rememberPassword;

  /// Whether the panel offers "Trust this device" with the 2FA code.
  bool get trustedDevicesEnabled =>
      bind.sessionGetEnableTrustedDevices(sessionId: sessionId);

  /// How the session is connected, from `connection_ready`; null before. Upstream kept it per
  /// device ID in `ConnectionTypeState` (`common/shared_state.dart`).
  bool? get secure => _secure;
  bool? get direct => _direct;
  String get streamType => _streamType;

  void _show(ConnStage stage,
      {ConnInput input = ConnInput.none, ConnReason? reason}) {
    _stage = stage;
    _input = input;
    _reason = reason;
    // Whatever comes next ends the countdown; upstream's timer would still reconnect after a
    // manual retry.
    _timer?.cancel();
    _timer = null;
    _retryCountdown = null;
    notifyListeners();
  }

  /// The connection part of upstream `FfiModel.clear` (`models/model.dart:254-264`).
  void clear() {
    _secure = null;
    _direct = null;
    _timer?.cancel();
    _timer = null;
    resetRestartReconnectState();
    _waitForImageTimer?.cancel();
  }

  void setConnectionType(bool secure, bool direct, String streamType) {
    _secure = secure;
    _direct = direct;
    _streamType = streamType;
    notifyListeners();
  }

  void handleMultipleWindowsSession(Map<String, dynamic> evt) {
    final sessionsList = json.decode(evt['windows_sessions']) as List<dynamic>;
    _windowsSessions = [
      for (var session in sessionsList)
        (sid: '${session['sid']}', name: '${session['name']}')
    ];
    _show(ConnStage.verifying, input: ConnInput.windowsSession);
  }

  /// Upstream `handleMsgBox` (`models/model.dart:888-976`). Three ways: prompts and inputs go
  /// into this state, notices onto the session's notices, errors into this state with a reason.
  void handleMsgBox(Map<String, dynamic> evt) {
    final ffi = parent.target;
    if (ffi == null) return;
    final String type = evt['type'];
    final String title = evt['title'];
    final String text = evt['text'];
    final String link = evt['link'] ?? '';

    // Disable relative mouse mode on any error-type message to ensure cursor is released.
    // This includes connection errors, session-ending messages, elevation errors, etc.
    // Safety: releasing pointer lock on errors prevents the user from being stuck.
    if (title == 'Connection Error' ||
        type == 'error' ||
        type == 'restarting' ||
        type.contains('error')) {
      ffi.inputModel.setRelativeMouseMode(false);
    }

    if (type == 're-input-password') {
      _askPassword(ConnInput.password, ConnReason._of(type, title, text));
    } else if (type == 'input-2fa') {
      // The title says whether it is asked for the first time (`REQUIRE_2FA`, no reason) or
      // the code was wrong.
      _show(ConnStage.verifying,
          input: ConnInput.twoFactor,
          reason: title == '2FA Required'
              ? null
              : ConnReason._of(type, title, text));
    } else if (type == 'input-password') {
      _askPassword(ConnInput.password, null);
    } else if (type == 'terminal-admin-login') {
      _show(ConnStage.verifying, input: ConnInput.osAccount);
    } else if (type == 'terminal-admin-login-password') {
      _askPassword(ConnInput.osAccountAndPassword, null);
    } else if (type == 'restarting') {
      // Treat restart messages as reconnect control events. Rust still sends
      // title/text for legacy UI and translation reuse; the last frame stays, dimmed.
      if (_restartReconnectDelayTimer == null) {
        ffi.inputModel.setRelativeMouseMode(false);
        ffi.ffiModel.cancelPendingMonitorRestore();
        bind.sessionReconnect(sessionId: sessionId, forceRelay: false);
        ffi.ffiModel.clearPermissions();
        _show(ConnStage.restarting);
        // Retry once more after the silent window so restart reconnect attempts
        // are spaced by the empirical short cadence instead of only updating UI.
        _restartReconnectDelayTimer =
            Timer(Duration(seconds: _restartReconnectSilentDelaySecs), () {
          _restartReconnectDelayTimer = null;
          if (parent.target?.closed == true) {
            return;
          }
          reconnect(false);
        });
      }
    } else if (type == 'restarting-show') {
      _restartReconnectDelayTimer?.cancel();
      _restartReconnectDelayTimer = null;
      reconnect(false);
      // Also the first word of a restart when the peer went silent (`io_loop.rs:335`); with
      // title "Connecting..." it is the peer-gone detector (`io_loop.rs:361`).
      if (title == 'Restarting remote device') _show(ConnStage.restarting);
    } else if (type == 'wait-remote-accept-nook') {
      _show(ConnStage.verifying, input: ConnInput.remoteAccept);
    } else if (type == 'on-uac' || type == 'on-foreground-elevated') {
      // Rust takes these back with `cancel_msgbox` by type. Upstream also skips them while its
      // elevation request dialog is open; that dialog comes with the session toolbar (M2b).
      if (ffi.notices.items.any((n) => n.tag == 'wait-uac')) return;
      _notice(ffi, type, title, text, link, tag: type);
    } else if (type == 'wait-uac') {
      // Upstream's wait dialog replaced the "waiting for UAC" one (`dismissAll`).
      ffi.notices.dismissTag('on-uac');
      ffi.notices.dismissTag('on-foreground-elevated');
      _notice(ffi, type, 'Wait', 'wait_accept_uac_tip', link, tag: type);
    } else if (type == 'elevation-error') {
      _notice(ffi, type, title, text, link, tag: type);
    } else if (type.contains('insecure-connection')) {
      // Upstream handles it in `msgBox` (`common.dart:1186`). Rust waits for the answer.
      _show(ConnStage.insecure);
    } else if (type == 'relay-hint' || type == 'relay-hint2') {
      // The reason (`direct_reset`) offers "Use relay"; no automatic retry.
      _show(ConnStage.failed, reason: ConnReason._of(type, title, text));
    } else if (text == kMsgboxTextWaitingForImage) {
      showConnectedWaitingForImage();
    } else if (!_isError(type, title)) {
      // Privacy mode ones among them: upstream shows those 3 s late so a canvas refresh does
      // not dismiss them; notices are not dismissed that way.
      _notice(ffi, type, title, text, link);
    } else {
      var hasRetry = evt['hasRetry'] == 'true';
      if (!hasRetry) {
        hasRetry = shouldAutoRetryOnOffline(type, title, text);
      }
      showMsgBox(type, title, text, hasRetry);
    }
  }

  /// A message box that ends the connection, as upstream's `msgBox` closes it on OK for every
  /// type without "custom" (`common.dart:1232`); the others only inform.
  static bool _isError(String type, String title) =>
      title == 'Connection Error' ||
      (type.contains('error') && !type.contains('custom'));

  /// The key is the message box text, upstream's translation key; the tag is upstream's dialog
  /// tag without the session ID.
  void _notice(FFI ffi, String type, String title, String text, String link,
      {String? tag}) {
    ffi.notices.add(SessionNotice(text,
        args: {'type': type, 'title': title, if (link.isNotEmpty) 'link': link},
        tag: tag ?? '$type-$title-$text-$link'));
  }

  /// Upstream reads the saved "remember" before showing the password dialog
  /// (`common/widgets/dialog.dart:972-975`).
  Future<void> _askPassword(ConnInput input, ConnReason? reason) async {
    _rememberPassword =
        await bind.sessionGetRemember(sessionId: sessionId) ?? false;
    _show(ConnStage.verifying, input: input, reason: reason);
  }

  void resetRestartReconnectState() {
    _restartReconnectDelayTimer?.cancel();
    _restartReconnectDelayTimer = null;
  }

  /// Auto-retry check for "Remote desktop is offline" error.
  /// returns true to auto-retry, false otherwise.
  bool shouldAutoRetryOnOffline(
    String type,
    String title,
    String text,
  ) {
    if (type == 'error' &&
        title == 'Connection Error' &&
        text == 'Remote desktop is offline' &&
        parent.target!.ffiModel.pi.isSet.isTrue) {
      // Auto retry for ~30s (server's peer offline threshold) when controlled peer's account changes
      // (e.g., signout, switch user, login into OS) causes temporary offline via websocket/tcp connection.
      // The actual wait may exceed 30s (e.g., 20s elapsed + 16s next retry = 36s), which is acceptable
      // since the controlled side reconnects quickly after account changes.
      // Uses time-based check instead of _reconnects count because user can manually retry.
      // https://github.com/rustdesk/rustdesk/discussions/14048
      if (_offlineReconnectStartTime == null) {
        // First offline, record time and start retry
        _offlineReconnectStartTime = clock.now();
        return true;
      } else {
        final elapsed =
            clock.now().difference(_offlineReconnectStartTime!).inSeconds;
        if (elapsed < 30) {
          return true;
        }
      }
    }
    return false;
  }

  /// Upstream `showMsgBox` (`models/model.dart:1064-1103`) without the dialog and the note asked
  /// at the end of a connection (01 §5.5).
  void showMsgBox(String type, String title, String text, bool hasRetry) {
    _show(ConnStage.failed, reason: ConnReason._of(type, title, text));
    if (hasRetry) {
      _retryAttempt++;
      _retryCountdown = _reconnects;
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _retryCountdown = _retryCountdown! - 1;
        if (_retryCountdown! > 0) {
          notifyListeners();
          return;
        }
        timer.cancel();
        _timer = null;
        reconnect(false);
      });
      _reconnects *= 2;
    } else {
      _reconnects = 1;
      _offlineReconnectStartTime = null;
      _retryAttempt = 0;
    }
    notifyListeners();
  }

  /// Upstream `reconnect` (`models/model.dart:1116-1126`) without its dialog manager.
  void reconnect(bool forceRelay) {
    final ffi = parent.target!;
    // Disable relative mouse mode before reconnecting to ensure cursor is released.
    ffi.inputModel.setRelativeMouseMode(false);
    ffi.ffiModel.cancelPendingMonitorRestore();
    bind.sessionReconnect(sessionId: sessionId, forceRelay: forceRelay);
    ffi.ffiModel.clearPermissions();
    _show(_stage == ConnStage.restarting
        ? ConnStage.restarting
        : ConnStage.connecting);
  }

  /// Upstream `showConnectedWaitingForImage` (`models/model.dart:1184-1205`): 1.5 s after
  /// connecting without a frame, an empty OS password wakes a locked screen.
  ///
  /// A render switch (`isRefreshing`) reaches every session (`src/flutter_ffi.rs:1259-1273`);
  /// upstream only lays its dialog over whatever is shown, so a session asking for a password
  /// or counting down to a retry stays as it is, and only a connected one waits for the image.
  void showConnectedWaitingForImage() {
    final ffiModel = parent.target!.ffiModel;
    if (ffiModel.waitForFirstImage.isFalse) return;
    if (!ffiModel.isRefreshing || _stage == ConnStage.connected) {
      _show(ConnStage.waitingForImage);
    }
    _waitForImageDialogShow = true;
    _waitForImageTimer?.cancel();
    // V1: a hidden tab gets no frames; the wait starts when it shows (onVisibilityChanged).
    if (parent.target!.visible) {
      _waitForImageTimer = Timer(Duration(milliseconds: 1500), () {
        if (ffiModel.waitForFirstImage.isTrue && !ffiModel.isRefreshing) {
          bind.sessionInputOsPassword(sessionId: sessionId, value: '');
        }
      });
    }
    bind.sessionOnWaitingForImageDialogShow(sessionId: sessionId);
  }

  /// The tab was hidden or shown (V1): hidden, the wake timer stops; shown while still waiting
  /// for the first frame, the wait starts again.
  void onVisibilityChanged() {
    if (!parent.target!.visible) {
      _waitForImageTimer?.cancel();
    } else if (_stage == ConnStage.waitingForImage) {
      showConnectedWaitingForImage();
    }
  }

  // Called from where upstream dismissed or reset the connection dialogs.

  /// A frame arrived (upstream `FFI.onEvent2UIRgba`, `models/model.dart:4322-4326`).
  void onImage() {
    if (_waitForImageDialogShow) {
      _waitForImageDialogShow = false;
      _waitForImageTimer?.cancel();
      if (_stage == ConnStage.waitingForImage) _show(ConnStage.connected);
    }
  }

  /// The first frame after connecting or a render switch (`models/model.dart:4327-4331`).
  void onFirstImage() {
    resetRestartReconnectState();
    _show(ConnStage.connected);
  }

  /// Peer info arrived: the connection is up (`models/model.dart:1355`).
  void onPeerInfo() => _show(ConnStage.connected);

  /// The peer has displays (`models/model.dart:1454-1456`).
  void onDisplays() {
    _reconnects = 1;
    _offlineReconnectStartTime = null;
    _retryAttempt = 0;
    resetRestartReconnectState();
  }

  // What the connection panel does. Each only acts in the state it answers, so a second Enter
  // sends nothing again.

  bool _asking(ConnInput input) =>
      _stage == ConnStage.verifying && _input == input;

  /// Upstream `FFI.login` from the password and OS account dialogs
  /// (`common/widgets/dialog.dart:962-1105`): fields trimmed, ignored while a required one is
  /// empty, as there.
  void login(
      {String osUsername = '',
      String osPassword = '',
      String password = '',
      bool remember = false}) {
    final user = osUsername.trim(), osPw = osPassword.trim();
    final pw = password.trim();
    if (_asking(ConnInput.password)) {
      if (pw.isEmpty) return;
    } else if (_asking(ConnInput.osAccount)) {
      if (user.isEmpty) return;
    } else if (_asking(ConnInput.osAccountAndPassword)) {
      if (user.isEmpty || pw.isEmpty) return;
    } else {
      return;
    }
    bind.sessionLogin(
        sessionId: sessionId,
        osUsername: user,
        osPassword: osPw,
        password: pw,
        remember: remember);
    _show(ConnStage.verifying);
  }

  /// Upstream `enter2FaDialog` (`common/widgets/dialog.dart:2346-2410`).
  void submit2fa(String code, {required bool trustThisDevice}) {
    if (!_asking(ConnInput.twoFactor)) return;
    bind.sessionSend2Fa(
        sessionId: sessionId,
        code: code.trim(),
        trustThisDevice: trustThisDevice);
    _show(ConnStage.verifying);
  }

  /// Upstream `showWindowsSessionsDialog` (`common/widgets/dialog.dart:2412-2461`). It has no
  /// cancel: upstream says closing it leaves a black screen.
  void selectWindowsSession(String sid) {
    if (!_asking(ConnInput.windowsSession)) return;
    bind.sessionSendSelectedSessionId(sessionId: sessionId, sid: sid);
    _show(ConnStage.verifying);
  }

  /// "Continue" on the insecure connection warning (`common.dart:1186-1219`).
  void continueInsecure() {
    if (_stage != ConnStage.insecure) return;
    unawaited(bind.sessionSetCommon(
        sessionId: sessionId, key: 'continue-insecure-connection', value: 'Y'));
    _show(ConnStage.verifying);
  }

  /// "Disconnect" on the insecure connection warning, also its default action: Enter and
  /// closing it disconnect, as upstream.
  Future<void> rejectInsecure() async {
    if (_stage != ConnStage.insecure) return;
    await bind.sessionSetCommon(
        sessionId: sessionId, key: 'continue-insecure-connection', value: 'N');
    await cancel();
  }

  /// Retry now, also during the countdown.
  void retry() => reconnect(false);

  /// "Use relay": Rust saves it for this device, so later connections use the relay too
  /// (`src/ui_session_interface.rs:1329-1336`).
  void useRelay() => reconnect(true);

  /// Cancel, close: closes this view (upstream `closeConnection`).
  Future<void> cancel() => appCore.sessions.close(parent.target!);
}

// Empirical restart reconnect cadence: keep the last frame briefly and retry quickly.
const _restartReconnectSilentDelaySecs = 5;
