// One tunnel card of the exit page (13 §1.3 blocks B and C, `LEAPGATE.md` §10.18): a TCP tunnel
// with a device's port forwards, one row each, or RDP with one row. A session of its own, not in
// the session registry. Each row's state, reason and notices come from the tunnel events; what
// to enter comes from the session's own events ([CardLogin]), one question for all its rows.
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../common.dart';
import 'app_core.dart';
import 'card_login.dart';
import 'connection.dart' show ConnInput, ConnReason;
import 'tunnel_api.dart';
import 'tunnels.dart';

/// A row's states of 13 §1.3 block B.
enum TunnelRowState { connecting, inUse, interrupted, stopped, portBusy }

/// What the card's question area asks (13 §1.3 block B "提问区").
enum TunnelQuestion {
  none,
  password,
  twoFactor,
  verifying,
  waitAccept,
  insecure
}

/// Why a forward cannot be added (13 §1.3 block B "添加端口转发"), checked before Rust is asked.
enum TunnelAddForwardError {
  /// A port not in 1~65535.
  invalid,

  /// The card has a forward on this local port, whatever its state.
  duplicate,

  /// Another tunnel card's running forward or an exit card listens on it.
  taken,
}

/// The RDP port when the device's settings name none or one Rust cannot read (upstream `io_loop`).
const kRdpDefaultPort = 3389;

class TunnelRow {
  TunnelRow._(this._forward);

  TunnelForward _forward;
  var _state = TunnelRowState.connecting;
  var _direct = false;
  ConnReason? _reason;
  var _removing = false;

  /// Added again while it was being deleted: Rust takes it once the old one is `removed`.
  TunnelForward? _readd;

  final _notices = <ConnReason>[];
  final _noticed = <String>{};

  TunnelForward get forward => _forward;
  int get localPort => _forward.localPort;
  TunnelRowState get state => _state;

  /// [TunnelRowState.inUse]: direct (ICE or a direct TCP) or through a relay.
  bool get direct => _direct;

  /// Whether the local listener is open.
  bool get listening => const {
        TunnelRowState.connecting,
        TunnelRowState.inUse,
        TunnelRowState.interrupted,
      }.contains(_state);

  /// [TunnelRowState.stopped]: Rust's reason, null without one. [TunnelRowState.interrupted]:
  /// the failed login's, null when the tunnel ended.
  ConnReason? get reason => _reason;

  /// The peer's refusals of a channel (13 §1.3 block E), each reason once, in the order they came.
  List<ConnReason> get notices => List.unmodifiable(_notices);

  void _reset(TunnelForward forward) {
    _forward = forward;
    _state = TunnelRowState.connecting;
    _reason = null;
    _removing = false;
    _readd = null;
  }
}

class TunnelCard extends ChangeNotifier {
  TunnelCard(this._model, this._api, this.id, this.kind,
      {String? name,
      String? sharedPassword,
      this.password = '',
      this.forceRelay = false})
      : _name = name,
        _sharedPassword = sharedPassword,
        sessionId = const Uuid().v4obj() {
    _login = CardLogin(sessionId,
        onChanged: notifyListeners,
        mayAsk: () => _added,
        onHostname: (host) {
          if (_name != null) return;
          _name = host;
          notifyListeners();
        },
        onPlatform: (platform) {
          _platform = platform;
          notifyListeners();
        });
    if (kind == TunnelKind.rdp) {
      rdpPort =
          int.tryParse(_api.rdpSettings(id).port.trim()) ?? kRdpDefaultPort;
      _rows.add(TunnelRow._((localPort: 0, host: '', remotePort: rdpPort)));
    } else {
      rdpPort = 0;
      _rows.addAll([for (final f in _api.savedForwards(id)) TunnelRow._(f)]);
    }
  }

  final TunnelsModel _model;
  final TunnelApi _api;
  final String id;
  final TunnelKind kind;
  final SessionID sessionId;

  /// The address book's password for the device, used as when connecting from the book.
  final String? _sharedPassword;

  /// A link's `--password` and `--relay`.
  final String password;
  final bool forceRelay;

  /// The port an RDP card goes to, read once as the session reads it (13 §1.3 block C); 0 for a
  /// TCP card.
  late final int rdpPort;

  String? _name;
  var _platform = '';
  var _added = false;
  var _ended = false;
  TunnelAddError? _addError;
  final _rows = <TunnelRow>[];
  late final CardLogin _login;

  /// The name given when it was opened (the device list's), else the remote host name once
  /// logged in; null until then.
  String? get name => _name;

  /// The remote platform (`kPeerPlatform*`) once logged in, for the icon; empty until then.
  String get platform => _platform;

  /// The rows, in the order the device keeps its forwards; an RDP card has one, port 0.
  List<TunnelRow> get rows =>
      List.unmodifiable(_rows.where((r) => !r._removing));

  /// Rust did not add the session: `already` (a conflict, 13 §1.3 block B), `invalid_id` or
  /// `other`. The card shows no rows then.
  TunnelAddError? get addError => _addError;

  /// A row's listener is open (13 §1.3 block F): what the page and the close dialog count.
  bool get running => _addError == null && _rows.any((r) => r.listening);

  TunnelQuestion get question {
    if (_login.insecure) return TunnelQuestion.insecure;
    if (_login.verifying) return TunnelQuestion.verifying;
    return switch (_login.input) {
      ConnInput.password => TunnelQuestion.password,
      ConnInput.twoFactor => TunnelQuestion.twoFactor,
      ConnInput.remoteAccept => TunnelQuestion.waitAccept,
      _ => TunnelQuestion.none,
    };
  }

  /// The question waits for the user (13 §1.3 block F).
  bool get needsAttention => const {
        TunnelQuestion.password,
        TunnelQuestion.twoFactor,
        TunnelQuestion.waitAccept,
        TunnelQuestion.insecure,
      }.contains(question);

  bool get wrongInput => _login.wrongInput;
  bool get rememberPassword => _login.rememberPassword;
  bool get trustedDevicesEnabled => _login.trustedDevicesEnabled;
  DateTime? get waitingSince => _login.waitingSince;

  /// Adds the session and subscribes to its events; on a refusal the card shows why.
  void start() {
    final error = _api.sessionAdd(sessionId, id, kind,
        password: _sharedPassword ?? password,
        isSharedPassword: _sharedPassword != null,
        connToken: appCore.sessions.tokenOf(id),
        forceRelay: forceRelay);
    _addError = error;
    if (error != null) {
      notifyListeners();
      return;
    }
    _added = true;
    _login.listen(id);
    notifyListeners();
  }

  /// A tunnel event of this card's session with a `port`. `closed` is the model's.
  void onTunnelEvent(Map<String, dynamic> evt) {
    if (_ended) return;
    final port = evt['port'];
    final row = _rows.where((r) => r.localPort == port).firstOrNull;
    if (row == null) return;
    switch (evt['state']) {
      case 'connecting':
        row._state = TunnelRowState.connecting;
        row._reason = null;
      case 'in_use':
        row._state = TunnelRowState.inUse;
        row._direct = evt['transport'] == 'direct';
        row._reason = null;
      case 'interrupted':
        row._state = TunnelRowState.interrupted;
        row._reason = evt['cause'] == 'login_failed' && evt['reason'] is Map
            ? CardReason.ofEvent(evt)
            : null;
      case 'stopped':
        row._state = TunnelRowState.stopped;
        row._reason = evt['reason'] is Map ? CardReason.ofEvent(evt) : null;
      case 'port_in_use':
        row._state = TunnelRowState.portBusy;
        row._reason = null;
      case 'notice':
        if (evt['reason'] is! Map) return;
        final reason = CardReason.ofEvent(evt);
        final key = '${reason.code} ${reason.params} ${reason.text}';
        if (!row._noticed.add(key)) return;
        row._notices.add(reason);
      case 'removed':
        final readd = row._readd;
        if (readd == null) {
          _rows.remove(row);
        } else {
          row._reset(readd);
          _api.addForward(
              sessionId, readd.localPort, readd.host, readd.remotePort);
        }
      default:
        return;
    }
    // The question goes once no row logs in any more ("在本机接受" asks each row in turn).
    if (!_rows.any((r) => r._state == TunnelRowState.connecting)) {
      _login.clear();
    }
    notifyListeners();
  }

  /// "Connect" in the question area.
  void submitPassword(String password, {required bool remember}) {
    if (question != TunnelQuestion.password) return;
    _login.submitPassword(password, remember: remember);
  }

  void submit2fa(String code, {required bool trust}) {
    if (question != TunnelQuestion.twoFactor) return;
    _login.submit2fa(code, trust: trust);
  }

  /// "继续" or "断开" on an unencrypted connection; the rows logging in go on or stop.
  Future<void> answerInsecure({required bool proceed}) =>
      _login.answerInsecure(proceed: proceed);

  /// "添加" (13 §1.3 block B): [host] empty is the remote device itself, kept as `localhost` as
  /// upstream does. Null when Rust was asked; the row logs in at once.
  TunnelAddForwardError? addForward(
      int localPort, String host, int remotePort) {
    if (!_validPort(localPort) || !_validPort(remotePort)) {
      return TunnelAddForwardError.invalid;
    }
    if (rows.any((r) => r.localPort == localPort)) {
      return TunnelAddForwardError.duplicate;
    }
    if (_model.portTaken(localPort, this)) return TunnelAddForwardError.taken;
    final forward = (
      localPort: localPort,
      host: host.trim().isEmpty ? 'localhost' : host.trim(),
      remotePort: remotePort
    );
    final removing = _rows.where((r) => r.localPort == localPort).firstOrNull;
    if (removing != null) {
      // Rust ignores the port until the old row is `removed` (`LEAPGATE.md` §10.18).
      removing._readd = forward;
      removing._removing = false;
      removing._state = TunnelRowState.connecting;
      removing._reason = null;
      removing._forward = forward;
    } else {
      _rows.add(TunnelRow._(forward));
      _api.addForward(sessionId, localPort, forward.host, remotePort);
    }
    notifyListeners();
    return null;
  }

  static bool _validPort(int port) => port >= 1 && port <= 65535;

  /// "删除" (13 §1.3 block B): off the device's saved forwards and stopped; not confirmed.
  void removeForward(TunnelRow row) {
    if (!_rows.contains(row) || row._removing) return;
    row._removing = true;
    row._readd = null;
    _api.removeForward(sessionId, row.localPort);
    notifyListeners();
  }

  /// "重试" and "重新连接" of a row: logs in now (a stopped or busy row listens again first).
  void retryRow(TunnelRow row) {
    if (row._state == TunnelRowState.stopped ||
        row._state == TunnelRowState.portBusy) {
      // Connecting from the click on, without the old reason.
      row._state = TunnelRowState.connecting;
      row._reason = null;
      notifyListeners();
    }
    if (!_api.retry(sessionId, row.localPort)) _gone();
  }

  /// "重试" of a card Rust did not add (the conflict): adds it again.
  void retry() {
    if (_added) return;
    start();
  }

  /// "新建 RDP 连接" (13 §1.3 block C); while interrupted it logs in again.
  Future<void> newRdp() => _api.newRdp(sessionId);

  void dismissNotice(TunnelRow row, ConnReason notice) {
    if (row._notices.remove(notice)) notifyListeners();
  }

  /// "Stop", "Remove" and "Cancel" (13 §1.3 block B): every listener and tunnel closes, the card
  /// goes; the saved forwards stay.
  Future<void> stop() async {
    ended();
    try {
      if (_added) await _api.close(sessionId);
    } finally {
      _model.drop(this);
    }
  }

  /// Rust has no such card any more: it ended without a word, so the card goes.
  void _gone() {
    ended();
    _model.drop(this);
  }

  /// Rust ended the card (`closed`), or it was stopped here: nothing more comes in.
  void ended() {
    _ended = true;
    _login.end();
  }
}
