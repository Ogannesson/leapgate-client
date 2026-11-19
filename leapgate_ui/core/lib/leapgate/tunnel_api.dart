// The one place the new UI reaches the tunnel exports (M9c, `LEAPGATE.md` §10.18). The tunnel
// models call [tunnelApi] only; tests set `FakeTunnelApi` (`test/tunnel_fakes.dart`). The login
// prompts of a tunnel session come on block 1's session stream, as for an exit card.
import 'dart:convert';

import '../common.dart';
import '../consts.dart';
import '../models/platform_model.dart';
import 'bridge.dart';

/// A tunnel card's kind: the TCP tunnel with a device's port forwards, or RDP.
enum TunnelKind { tcp, rdp }

/// A port forward: local port to [host]:[remotePort] on the remote side.
typedef TunnelForward = ({int localPort, String host, int remotePort});

/// A device's RDP settings, as the peer options keep them; [port] empty is 3389.
typedef RdpSettings = ({String port, String username, String password});

/// Why `leapgate_tunnel_session_add` did not add the session: `already` (TCP: the device has a
/// port forward session, an exit card or a tunnel card not yet closed; RDP: it has an RDP
/// session), `invalid_id`, or `other` with Rust's [text].
class TunnelAddError {
  const TunnelAddError(this.code, [this.text = '']);

  final String code;
  final String text;
}

abstract interface class TunnelApi {
  /// leapgate_tunnel_session_add; null when added, then block 1's sessionStart as for an exit card.
  TunnelAddError? sessionAdd(SessionID sessionId, String id, TunnelKind kind,
      {String password = '',
      bool isSharedPassword = false,
      String? connToken,
      bool forceRelay = false});

  /// leapgate_tunnel_events as JSON maps; subscribing again replaces the old subscription.
  Stream<Map<String, dynamic>> events();

  /// leapgate_tunnel_retry; [port] is 0 for RDP; false without such a card or forward.
  bool retry(SessionID sessionId, int port);

  /// Block 1: sessionAddPortForward, sessionRemovePortForward, sessionNewRdp, sessionClose.
  Future<void> addForward(
      SessionID sessionId, int localPort, String host, int remotePort);
  Future<void> removeForward(SessionID sessionId, int localPort);
  Future<void> newRdp(SessionID sessionId);
  Future<void> close(SessionID sessionId);

  /// Block 1 mainGetPeerSync's port_forwards, without the exit sentinel and ports ≤ 0.
  List<TunnelForward> savedForwards(String id);

  /// The local ports of all of the device's port_forwards, the exit sentinel's too: upstream
  /// `add_port_forward` ignores a port it keeps already (M9c review, 13 §1.3 block B).
  Set<int> savedLocalPorts(String id);

  /// rdp_port, rdp_username, rdp_password with mainGetPeerOption / mainSetPeerOption.
  RdpSettings rdpSettings(String id);
  Future<void> setRdpSettings(String id, RdpSettings settings);
}

/// Set by tests; the app keeps the default.
TunnelApi tunnelApi = const RustTunnelApi();

// ---------------------------------------------------------------------------------------------
// Above: the interface (step 0, unchanged by the lanes). Below: coder T's.

/// Blocks 1 and 2.
class RustTunnelApi implements TunnelApi {
  const RustTunnelApi();

  /// `{}` is null; otherwise the error code and Rust's text.
  @override
  TunnelAddError? sessionAdd(SessionID sessionId, String id, TunnelKind kind,
      {String password = '',
      bool isSharedPassword = false,
      String? connToken,
      bool forceRelay = false}) {
    final m = jsonDecode(lgBind.leapgateTunnelSessionAdd(
      sessionId: sessionId,
      id: id,
      rdp: kind == TunnelKind.rdp,
      password: password,
      isSharedPassword: isSharedPassword,
      connToken: connToken,
      forceRelay: forceRelay,
    )) as Map<String, dynamic>;
    final code = m['error'];
    return code == null
        ? null
        : TunnelAddError(code as String, (m['text'] as String?) ?? '');
  }

  @override
  Stream<Map<String, dynamic>> events() => lgBind
      .leapgateTunnelEvents()
      .map((e) => jsonDecode(e) as Map<String, dynamic>);

  @override
  bool retry(SessionID sessionId, int port) =>
      lgBind.leapgateTunnelRetry(sessionId: sessionId, port: port);

  @override
  Future<void> addForward(
          SessionID sessionId, int localPort, String host, int remotePort) =>
      bind.sessionAddPortForward(
          sessionId: sessionId,
          localPort: localPort,
          remoteHost: host,
          remotePort: remotePort);

  @override
  Future<void> removeForward(SessionID sessionId, int localPort) =>
      bind.sessionRemovePortForward(sessionId: sessionId, localPort: localPort);

  @override
  Future<void> newRdp(SessionID sessionId) =>
      bind.sessionNewRdp(sessionId: sessionId);

  @override
  Future<void> close(SessionID sessionId) =>
      bind.sessionClose(sessionId: sessionId);

  @override
  List<TunnelForward> savedForwards(String id) =>
      parseSavedForwards(bind.mainGetPeerSync(id: id));

  @override
  Set<int> savedLocalPorts(String id) =>
      parseSavedLocalPorts(bind.mainGetPeerSync(id: id));

  @override
  RdpSettings rdpSettings(String id) => (
        port: bind.mainGetPeerOptionSync(id: id, key: _kRdpPort),
        username: bind.mainGetPeerOptionSync(id: id, key: _kRdpUsername),
        password: bind.mainGetPeerOptionSync(id: id, key: _kRdpPassword),
      );

  @override
  Future<void> setRdpSettings(String id, RdpSettings settings) async {
    await bind.mainSetPeerOption(id: id, key: _kRdpPort, value: settings.port);
    await bind.mainSetPeerOption(
        id: id, key: _kRdpUsername, value: settings.username);
    await bind.mainSetPeerOption(
        id: id, key: _kRdpPassword, value: settings.password);
  }
}

// The peer options upstream's RDP settings dialog writes (`common/widgets/peer_card.dart`
// `_rdpDialog`) and Rust reads (`src/ui_session_interface.rs` `io_loop`).
const _kRdpPort = 'rdp_port';
const _kRdpUsername = 'rdp_username';
const _kRdpPassword = 'rdp_password';

/// The `port_forwards` of `mainGetPeerSync`'s JSON (`[[local port, host, remote port], …]`, as
/// upstream `port_forward_page.dart` reads it), without the old UI's exit mapping
/// ([kLeapgateExitHost]:[kLeapgateExitPort]) and local or remote ports ≤ 0, as upstream
/// `io_loop` and the Rust card loop skip them. Empty when the JSON is not of that shape.
List<TunnelForward> parseSavedForwards(String json) {
  try {
    final config = jsonDecode(json) as Map<String, dynamic>;
    return [
      for (final e in config['port_forwards'] as List? ?? const [])
        if (e is List &&
            e.length == 3 &&
            e[0] is int &&
            e[1] is String &&
            e[2] is int &&
            (e[0] as int) > 0 &&
            (e[2] as int) > 0 &&
            !(e[1] == kLeapgateExitHost && e[2] == kLeapgateExitPort))
          (
            localPort: e[0] as int,
            host: e[1] as String,
            remotePort: e[2] as int
          ),
    ];
  } on FormatException {
    return const [];
  } on TypeError {
    return const [];
  }
}

/// The local port of every entry of `mainGetPeerSync`'s `port_forwards`, as upstream
/// `add_port_forward` compares them: the exit mapping and ports ≤ 0 included. Empty when the JSON
/// is not of that shape.
Set<int> parseSavedLocalPorts(String json) {
  try {
    final config = jsonDecode(json) as Map<String, dynamic>;
    return {
      for (final e in config['port_forwards'] as List? ?? const [])
        if (e is List && e.isNotEmpty && e[0] is int) e[0] as int,
    };
  } on FormatException {
    return const {};
  } on TypeError {
    return const {};
  }
}
