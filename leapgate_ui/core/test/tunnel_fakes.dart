// The same file is in core/test and app/test (`LEAPGATE.md` §10.18). A lane that needs more
// subclasses it in its own test file.
import 'dart:async';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/leapgate/tunnel_api.dart';

/// The tunnel exports of §10.18 for tests: calls recorded by name, the tunnel events played from
/// the test with [push]. Set [tunnelApi] to it before the tunnel models are first used.
class FakeTunnelApi implements TunnelApi {
  final calls = <(String, List<Object?>)>[];

  List<List<Object?>> callsTo(String name) => [
        for (final (n, args) in calls)
          if (n == name) args
      ];

  /// What [sessionAdd] answers.
  TunnelAddError? addError;

  /// What [retry] answers: false when Rust has no such card or forward.
  var hasRow = true;

  /// The port forwards and RDP settings Rust keeps per device, as [savedForwards] and
  /// [rdpSettings] read them.
  final forwards = <String, List<TunnelForward>>{};
  final rdp = <String, RdpSettings>{};

  /// Saved local ports [savedForwards] leaves out (the old UI's exit mapping), which
  /// [savedLocalPorts] still gives.
  final hiddenPorts = <String, Set<int>>{};

  final _events = StreamController<Map<String, dynamic>>.broadcast();

  /// A tunnel event `{"id","session_id","kind","state",…}` with the session last added for
  /// [id] and [kind], as Rust sends it; a row event passes its local [port] (0 for RDP).
  void push(String id, TunnelKind kind, String state,
      {int? port, Map<String, dynamic> extra = const {}}) {
    final added = callsTo('sessionAdd')
        .where((c) => c[1] == id && c[2] == kind)
        .lastOrNull;
    _events.add({
      'id': id,
      if (added != null) 'session_id': '${added[0]}',
      'kind': kind.name,
      if (port != null) 'port': port,
      'state': state,
      ...extra,
    });
  }

  @override
  TunnelAddError? sessionAdd(SessionID sessionId, String id, TunnelKind kind,
      {String password = '',
      bool isSharedPassword = false,
      String? connToken,
      bool forceRelay = false}) {
    calls.add((
      'sessionAdd',
      [sessionId, id, kind, password, isSharedPassword, connToken, forceRelay]
    ));
    return addError;
  }

  @override
  Stream<Map<String, dynamic>> events() => _events.stream;

  @override
  bool retry(SessionID sessionId, int port) {
    calls.add(('retry', [sessionId, port]));
    return hasRow;
  }

  @override
  Future<void> addForward(
      SessionID sessionId, int localPort, String host, int remotePort) async {
    calls.add(('addForward', [sessionId, localPort, host, remotePort]));
  }

  @override
  Future<void> removeForward(SessionID sessionId, int localPort) async {
    calls.add(('removeForward', [sessionId, localPort]));
  }

  @override
  Future<void> newRdp(SessionID sessionId) async {
    calls.add(('newRdp', [sessionId]));
  }

  @override
  Future<void> close(SessionID sessionId) async {
    calls.add(('close', [sessionId]));
  }

  @override
  List<TunnelForward> savedForwards(String id) => forwards[id] ?? const [];

  @override
  Set<int> savedLocalPorts(String id) => {
        for (final f in forwards[id] ?? const <TunnelForward>[]) f.localPort,
        ...?hiddenPorts[id],
      };

  @override
  RdpSettings rdpSettings(String id) =>
      rdp[id] ?? (port: '', username: '', password: '');

  @override
  Future<void> setRdpSettings(String id, RdpSettings settings) async {
    calls.add(('setRdpSettings', [id, settings]));
    rdp[id] = settings;
  }
}
