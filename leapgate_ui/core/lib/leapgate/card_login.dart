// The login prompts of a card on the exit page (M5 exit cards, M9c tunnel cards; 14 §2.5): what
// to enter comes from the card session's own events, as in `ConnectionModel.handleMsgBox`
// (`connection.dart`). Taken out of `ExitCard`; the card says what its state is.
import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../common.dart';
import '../generated_bridge.dart' show EventToUI_Event;
import '../models/platform_model.dart';
import 'connection.dart' show ConnInput, ConnReason;

/// A [ConnReason] from a reason JSON (the exit and tunnel events) or a refused session add, so
/// the app shows it as the connection panel does (`reasons.dart`).
class CardReason implements ConnReason {
  CardReason(this.code, [this.params = const {}, this.text = '']);

  /// `{"code",…}` as the exit and tunnel events carry it; `other` keeps Rust's `text`.
  factory CardReason.fromJson(Map<String, dynamic> m) {
    final params = Map<String, dynamic>.of(m);
    final code = params.remove('code') as String? ?? 'other';
    final text = params.remove('text');
    return CardReason(code, params, text is String ? text : '');
  }

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

class CardLogin {
  CardLogin(
    this.sessionId, {
    required this.onChanged,
    required this.mayAsk,
    this.declineInsecure,
    this.onError,
    this.onHostname,
  });

  final SessionID sessionId;
  final VoidCallback onChanged;

  /// Whether a prompt that comes now is shown: not one of an attempt that stopped.
  final bool Function() mayAsk;

  /// Set: an unencrypted connection is declined at once and this is called (an exit is never
  /// unencrypted, 第四期). Null: the user is asked (a tunnel, as upstream `port_forward.rs`).
  final VoidCallback? declineInsecure;

  /// A failure the session reports. The tunnels' come on their own events.
  final void Function(String type, String title, String text)? onError;

  /// The remote host name, once logged in.
  final void Function(String hostname)? onHostname;

  var _ended = false;
  StreamSubscription? _session;

  var _input = ConnInput.none;
  var _insecure = false;
  var _verifying = false;
  var _wrongInput = false;
  var _rememberPassword = false;
  DateTime? _waitingSince;

  /// What the card asks for; [ConnInput.none] while it asks nothing.
  ConnInput get input => _input;

  /// The unencrypted connection is asked about (only without [declineInsecure]).
  bool get insecure => _insecure;

  /// The password or the code was sent and no answer has come yet.
  bool get verifying => _verifying;

  /// The password or the 2FA code asked again because the last one was wrong.
  bool get wrongInput => _wrongInput;

  /// The device's saved "remember password", the initial value of the card's check box.
  bool get rememberPassword => _rememberPassword;

  /// [ConnInput.remoteAccept]: since when.
  DateTime? get waitingSince => _waitingSince;

  bool get trustedDevicesEnabled =>
      bind.sessionGetEnableTrustedDevices(sessionId: sessionId);

  /// Subscribes to the session's events (block 1's `sessionStart`).
  void listen(String id) {
    _session = bind.sessionStart(sessionId: sessionId, id: id).listen((m) {
      if (m is EventToUI_Event && m.field0 != 'close') {
        _onEvent(jsonDecode(m.field0) as Map<String, dynamic>);
      }
      // The session may be closed already; its stream then ends with an error.
    }, onError: (_) {});
  }

  /// Nothing is asked any more.
  void clear() {
    _input = ConnInput.none;
    _insecure = false;
    _verifying = false;
    _wrongInput = false;
    _waitingSince = null;
  }

  void _onEvent(Map<String, dynamic> evt) {
    if (_ended) return;
    switch (evt['name']) {
      case 'msgbox':
        _onMsgBox('${evt['type']}', '${evt['title']}', '${evt['text']}');
      case 'peer_info':
        final host = evt['hostname'];
        if (host is String && host.isNotEmpty) onHostname?.call(host);
    }
  }

  /// `ConnectionModel.handleMsgBox`'s choice of what to ask (`connection.dart`), without its
  /// retries: the cards reconnect by themselves (第四期 C9, E1; 13 §1.3).
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
      final decline = declineInsecure;
      if (decline == null) {
        if (!mayAsk()) return;
        _input = ConnInput.none;
        _verifying = false;
        _insecure = true;
        onChanged();
        return;
      }
      await bind.sessionSetCommon(
          sessionId: sessionId,
          key: 'continue-insecure-connection',
          value: 'N');
      decline();
    } else if (title == 'Connection Error' ||
        (type.contains('error') && !type.contains('custom'))) {
      onError?.call(type, title, text);
    }
  }

  void _ask(ConnInput input, {bool wrong = false}) {
    if (!mayAsk()) return;
    _input = input;
    _insecure = false;
    _verifying = false;
    _wrongInput = wrong;
    onChanged();
  }

  /// "Connect" with the password (`ConnectionModel.login`); nothing when it is empty.
  void submitPassword(String password, {required bool remember}) {
    final pw = password.trim();
    if (pw.isEmpty) return;
    bind.sessionLogin(
        sessionId: sessionId,
        osUsername: '',
        osPassword: '',
        password: pw,
        remember: remember);
    _verifying = true;
    onChanged();
  }

  void submit2fa(String code, {required bool trust}) {
    bind.sessionSend2Fa(
        sessionId: sessionId, code: code.trim(), trustThisDevice: trust);
    _verifying = true;
    onChanged();
  }

  /// "继续" ([proceed]) or "断开" on the unencrypted connection. Each login asking goes on or
  /// stops; Rust says which on the card's events.
  Future<void> answerInsecure({required bool proceed}) async {
    if (!_insecure) return;
    _insecure = false;
    onChanged();
    await bind.sessionSetCommon(
        sessionId: sessionId,
        key: 'continue-insecure-connection',
        value: proceed ? 'Y' : 'N');
  }

  /// The card ended: nothing more comes in.
  void end() {
    _ended = true;
    _session?.cancel();
    _session = null;
  }
}
