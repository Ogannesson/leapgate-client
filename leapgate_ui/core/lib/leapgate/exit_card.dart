// One card of the exit node page (01 P1 block I, 08 M5-1): an exit session of its own, which is
// not in the session registry and has no `FFI` or `ConnectionModel` (`LEAPGATE.md` §10.12, 08
// §4.2). What to enter comes from the session's own events, as in `ConnectionModel.handleMsgBox`
// (`connection.dart`); everything else from the exit events (E2), which win.
import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../common.dart';
import '../generated_bridge.dart' show EventToUI_Event;
import '../models/platform_model.dart';
import 'bridge.dart';
import 'connection.dart' show ConnInput, ConnReason;
import 'exit_api.dart';
import 'exit_nodes.dart';

/// The card states of 01 P1 block I.
enum ExitCardState {
  connecting,
  password,
  twoFactor,
  verifying,
  waitAccept,
  inUse,
  interrupted,
  stopped,
  portBusy,
}

/// What E2 says, before the session's prompts are laid over it.
enum _Rust { connecting, inUse, interrupted, stopped, portBusy }

/// The codes of a target refused by the exit: card notices, not failures (08 §4.3).
const kExitNoticeCodes = {'exit_blocked', 'exit_fake_ip_literal'};

/// A [ConnReason] from E2's reason JSON or from a refused [ExitApi.sessionAdd], so the app shows
/// it as the connection panel does (`reasons.dart`).
class _Reason implements ConnReason {
  _Reason(this.code, [this.params = const {}, this.text = '']);

  @override
  final String code;
  @override
  final Map<String, dynamic> params;
  @override
  final String text;
  @override
  String get type => '';
  @override
  String get title => '';
}

class ExitCard extends ChangeNotifier {
  ExitCard(this._nodes, this._api, this.id, this._port,
      {String? name, String? sharedPassword})
      : _name = name,
        _sharedPassword = sharedPassword,
        sessionId = const Uuid().v4obj();

  final ExitNodesModel _nodes;
  final ExitApi _api;
  final String id;
  final SessionID sessionId;

  /// The address book's password for the device, used as when connecting from the book.
  final String? _sharedPassword;

  String? _name;
  int _port;
  var _added = false;
  var _ended = false;
  StreamSubscription? _session;

  var _rust = _Rust.connecting;
  var _direct = false;
  int? _busyPort;
  ConnReason? _stopReason;

  var _input = ConnInput.none;
  var _verifying = false;
  var _wrongInput = false;
  var _rememberPassword = false;
  DateTime? _waitingSince;

  /// The last failure the session reported; the stop reason when E2 brings none.
  ConnReason? _lastError;

  final _notices = <String>[];
  final _noticed = <String>{};

  /// The name given with "Use" (the directory's host name, the device list's name), else the
  /// remote host name once logged in; null until then.
  String? get name => _name;

  /// The local proxy port.
  int get port => _port;

  ExitCardState get state => switch (_rust) {
        _Rust.connecting => _verifying
            ? ExitCardState.verifying
            : switch (_input) {
                ConnInput.password => ExitCardState.password,
                ConnInput.twoFactor => ExitCardState.twoFactor,
                ConnInput.remoteAccept => ExitCardState.waitAccept,
                _ => ExitCardState.connecting,
              },
        _Rust.inUse => ExitCardState.inUse,
        _Rust.interrupted => ExitCardState.interrupted,
        _Rust.stopped => ExitCardState.stopped,
        _Rust.portBusy => ExitCardState.portBusy,
      };

  /// Whether the local listener is open: what the page and the close dialog count (M5-8).
  bool get running => _rust != _Rust.stopped && _rust != _Rust.portBusy;

  /// [ExitCardState.inUse]: direct (ICE or a direct TCP) or through a relay.
  bool get direct => _direct;

  /// [ExitCardState.portBusy]: the port E2 named.
  int get busyPort => _busyPort ?? _port;

  /// [ExitCardState.stopped]: E2's reason, else the session's last failure; null when neither
  /// has come yet.
  ConnReason? get stopReason => _stopReason ?? _lastError;

  /// The password or the 2FA code asked again because the last one was wrong.
  bool get wrongInput => _wrongInput;

  /// The device's saved "remember password", the initial value of the card's check box.
  bool get rememberPassword => _rememberPassword;

  bool get trustedDevicesEnabled =>
      bind.sessionGetEnableTrustedDevices(sessionId: sessionId);

  /// [ExitCardState.waitAccept]: since when.
  DateTime? get waitingSince => _waitingSince;

  /// The notices shown, as C3 codes ([kExitNoticeCodes]), in the order they came.
  List<String> get notices => List.unmodifiable(_notices);

  String get socksAddress => 'socks5h://127.0.0.1:$_port';
  String get httpAddress => 'http://127.0.0.1:$_port';

  /// Adds the exit session and subscribes to its events; on a refusal the card stops with it.
  void start() {
    final error = _api.sessionAdd(sessionId, id, _port,
        password: _sharedPassword ?? '',
        isSharedPassword: _sharedPassword != null);
    if (error != null) {
      _rust = _Rust.stopped;
      _stopReason = _Reason(
          switch (error.code) {
            'already' => 'exit_already',
            // Rust would log in to another ID than the card's (`?key=…`, `/r`).
            'invalid_id' => 'exit_invalid_id',
            _ => 'other',
          },
          const {},
          error.text);
      notifyListeners();
      return;
    }
    _added = true;
    _session = bind.sessionStart(sessionId: sessionId, id: id).listen((m) {
      if (m is EventToUI_Event && m.field0 != 'close') {
        _onEvent(jsonDecode(m.field0) as Map<String, dynamic>);
      }
    });
  }

  void _clearInput() {
    _input = ConnInput.none;
    _verifying = false;
    _wrongInput = false;
    _waitingSince = null;
  }

  /// An E2 event for this device. `closed` is the model's.
  void onExitEvent(Map<String, dynamic> evt) {
    if (_ended) return;
    final rust = switch (evt['state']) {
      'connecting' => _Rust.connecting,
      'in_use' => _Rust.inUse,
      'interrupted' => _Rust.interrupted,
      'stopped' => _Rust.stopped,
      'port_in_use' => _Rust.portBusy,
      _ => null,
    };
    if (rust == null) return;
    if (rust == _Rust.connecting) {
      // A reconnect after the tunnel ended: the reasons of the last attempt go. "Retry" on a
      // stopped card has dropped them already; a failure the session reports first stays.
      if (_rust == _Rust.interrupted) {
        _stopReason = null;
        _lastError = null;
      }
    } else {
      _clearInput();
    }
    switch (rust) {
      case _Rust.inUse:
        _direct = evt['transport'] == 'direct';
        _lastError = null;
      case _Rust.stopped:
        final reason = evt['reason'];
        _stopReason = reason is Map<String, dynamic>
            ? _Reason(reason['code'] as String? ?? 'other',
                Map.of(reason)..remove('code'))
            : null;
      case _Rust.portBusy:
        _busyPort = evt['port'] as int?;
      case _Rust.connecting:
      case _Rust.interrupted:
        break;
    }
    _rust = rust;
    notifyListeners();
  }

  void _onEvent(Map<String, dynamic> evt) {
    if (_ended) return;
    switch (evt['name']) {
      case 'msgbox':
        _onMsgBox('${evt['type']}', '${evt['title']}', '${evt['text']}');
      case 'peer_info':
        final host = evt['hostname'];
        if (_name == null && host is String && host.isNotEmpty) {
          _name = host;
          notifyListeners();
        }
    }
  }

  /// `ConnectionModel.handleMsgBox`'s choice of what to ask (`connection.dart`), without its
  /// retries: the exit reconnects by itself (第四期 C9, E1).
  Future<void> _onMsgBox(String type, String title, String text) async {
    if (type == 'input-password' || type == 're-input-password') {
      _rememberPassword =
          await bind.sessionGetRemember(sessionId: sessionId) ?? false;
      if (_ended) return;
      _ask(ConnInput.password, wrong: type == 're-input-password');
    } else if (type == 'input-2fa') {
      _ask(ConnInput.twoFactor, wrong: title != '2FA Required');
    } else if (type == 'wait-remote-accept-nook') {
      _waitingSince = clock.now();
      _ask(ConnInput.remoteAccept);
    } else if (type.contains('insecure-connection')) {
      // An exit is never unencrypted (第四期); Rust stops the card with this reason as well.
      await bind.sessionSetCommon(
          sessionId: sessionId,
          key: 'continue-insecure-connection',
          value: 'N');
      _lastError = _Reason('exit_need_encryption');
      notifyListeners();
    } else if (title == 'Connection Error' ||
        (type.contains('error') && !type.contains('custom'))) {
      final reason = _reasonOf(type, title, text);
      if (kExitNoticeCodes.contains(reason.code)) {
        if (_noticed.add(reason.code)) _notices.add(reason.code);
      } else if (reason.code != 'local_port_in_use') {
        // E2's `port_in_use` says the same with the port.
        _lastError = reason;
      }
      notifyListeners();
    }
  }

  void _ask(ConnInput input, {bool wrong = false}) {
    // A prompt of the attempt that stopped; after "Retry" the card is connecting again.
    if (_rust == _Rust.stopped || _rust == _Rust.portBusy) return;
    _input = input;
    _verifying = false;
    _wrongInput = wrong;
    notifyListeners();
  }

  static ConnReason _reasonOf(String type, String title, String text) {
    final params = Map<String, dynamic>.from(jsonDecode(
        lgBind.leapgateMsgboxReason(msgtype: type, title: title, text: text)));
    return _Reason(params.remove('code') as String? ?? 'other', params, text);
  }

  /// "Connect" with the password (`ConnectionModel.login`).
  void submitPassword(String password, {required bool remember}) {
    final pw = password.trim();
    if (state != ExitCardState.password || pw.isEmpty) return;
    bind.sessionLogin(
        sessionId: sessionId,
        osUsername: '',
        osPassword: '',
        password: pw,
        remember: remember);
    _verifying = true;
    notifyListeners();
  }

  void submit2fa(String code, {required bool trust}) {
    if (state != ExitCardState.twoFactor) return;
    bind.sessionSend2Fa(
        sessionId: sessionId, code: code.trim(), trustThisDevice: trust);
    _verifying = true;
    notifyListeners();
  }

  /// "Cancel" while logging in: Rust drops the login, so it is [stop].
  Future<void> cancel() => stop();

  /// "Stop" and "Remove" (M5-10): closes the listener and the tunnel; the card goes.
  Future<void> stop() async {
    ended();
    try {
      if (_added) await _api.close(sessionId);
    } finally {
      _nodes.drop(this);
    }
  }

  /// "Retry" (stopped) and "Reconnect" (interrupted), M5-7: logs in now. A card Rust refused to
  /// add tries to add it again.
  void retry() {
    if (_rust == _Rust.stopped) {
      // Connecting from the click on, without the old reason.
      _stopReason = null;
      _lastError = null;
      _rust = _Rust.connecting;
      notifyListeners();
    }
    if (_added) {
      _api.retry(id);
    } else {
      start();
    }
  }

  /// Another listener port, keeping the tunnel (M5-5); null when Rust was asked, else why not.
  ExitPortError? changePort(int port) {
    final error = _nodes.portError(port, this);
    if (error != null) return error;
    if (port == _port) return null;
    _port = port;
    _nodes.savePort(id, port);
    // Rust listens and logs in at once; as after "Retry", the prompts of that login count.
    if (_rust == _Rust.portBusy) _rust = _Rust.connecting;
    _api.setPort(id, port);
    notifyListeners();
    return null;
  }

  void dismissNotice(String code) {
    if (_notices.remove(code)) notifyListeners();
  }

  /// Rust ended the card (`closed`), or it was stopped here: nothing more comes in.
  void ended() {
    _ended = true;
    _session?.cancel();
    _session = null;
  }
}
