// The one place the new UI reaches the exit node exports (M5, `LEAPGATE.md` §10.12). The exit
// models call [exitApi] only; tests set a fake. The login prompts of an exit session go through
// block 1 as for any session (`ExitCard`).
import 'dart:convert';

import '../common.dart';
import '../models/platform_model.dart';
import 'bridge.dart';
import 'session_route.dart';

/// Why `leapgate_exit_session_add` did not add the session: `already` (the device has an exit or
/// a port forward session), `invalid_port`, or `other` with Rust's [text].
class ExitAddError {
  const ExitAddError(this.code, [this.text = '']);

  final String code;
  final String text;
}

/// A row of the exit node directory (第四期 D2): online devices with the exit switch on that the
/// signed-in user may use.
class ExitNode {
  const ExitNode(
      {required this.id,
      this.hostname = '',
      this.owner = '',
      this.own = false});

  ExitNode.fromJson(Map<String, dynamic> m)
      : id = m['id'] as String? ?? '',
        hostname = m['hostname'] as String? ?? '',
        owner = m['owner'] as String? ?? '',
        own = m['own'] == true;

  final String id;
  final String hostname;

  /// The owner's user name; [own] says it is the signed-in user.
  final String owner;
  final bool own;
}

enum ExitDirectoryStatus { ok, unsupported, notLoggedIn, error }

typedef ExitDirectoryAnswer = ({
  ExitDirectoryStatus status,
  List<ExitNode> exits
});

/// `mainGetCommon(leapgate-exits)` as the old UI read it (`flutter/lib/leapgate/exit_nodes.dart`):
/// any state it does not know, and an answer of the wrong shape, is an error.
ExitDirectoryAnswer parseExitDirectory(String json) {
  const error = (status: ExitDirectoryStatus.error, exits: <ExitNode>[]);
  try {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return switch (m['state']) {
      'ok' => (
          status: ExitDirectoryStatus.ok,
          exits: [
            for (final e in m['exits'] as List? ?? const [])
              ExitNode.fromJson(e as Map<String, dynamic>),
          ]
        ),
      'unsupported' => (status: ExitDirectoryStatus.unsupported, exits: []),
      'not_logged_in' => (status: ExitDirectoryStatus.notLoggedIn, exits: []),
      _ => error,
    };
  } on FormatException {
    return error;
  } on TypeError {
    return error;
  }
}

/// The exports of §10.12 as the exit models use them.
abstract interface class ExitApi {
  /// `leapgate_exit_session_add`: a session that only runs the exit mapping on [port]; null when
  /// it was added. Its events then come from block 1's `sessionStart`. [password] is the address
  /// book's shared password, with [isSharedPassword].
  ExitAddError? sessionAdd(SessionID sessionId, String id, int port,
      {String password = '', bool isSharedPassword = false});

  /// `leapgate_exit_events`: each card's state as `{"id","session_id","port","state",…}`.
  /// Subscribing again replaces the old subscription; each card's current state comes first.
  Stream<Map<String, dynamic>> events();

  /// `leapgate_exit_retry`: logs in now, skipping the cool-down; false without such a card.
  bool retry(String id);

  /// `leapgate_exit_set_port`: listens on [port] instead, keeping the tunnel.
  bool setPort(String id, int port);

  /// Block 1's `sessionClose`: stops the card, also while it logs in.
  Future<void> close(SessionID sessionId);

  Future<ExitDirectoryAnswer> directory();

  /// Q3's export, after `connection_ready`.
  SessionRoute connection(SessionID sessionId);
}

/// Set by tests; the app keeps the default.
ExitApi exitApi = const RustExitApi();

/// Blocks 1 and 2.
class RustExitApi implements ExitApi {
  const RustExitApi();

  /// `{}` is null; otherwise the error code and Rust's text.
  @override
  ExitAddError? sessionAdd(SessionID sessionId, String id, int port,
          {String password = '', bool isSharedPassword = false}) =>
      _addError(lgBind.leapgateExitSessionAdd(
        sessionId: sessionId,
        id: id,
        port: port,
        password: password,
        isSharedPassword: isSharedPassword,
        connToken: null,
        forceRelay: false,
      ));

  static ExitAddError? _addError(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final code = m['error'];
    return code == null
        ? null
        : ExitAddError(code as String, (m['text'] as String?) ?? '');
  }

  @override
  Stream<Map<String, dynamic>> events() => lgBind
      .leapgateExitEvents()
      .map((e) => jsonDecode(e) as Map<String, dynamic>);

  @override
  bool retry(String id) => lgBind.leapgateExitRetry(id: id);

  @override
  bool setPort(String id, int port) =>
      lgBind.leapgateExitSetPort(id: id, port: port);

  @override
  Future<void> close(SessionID sessionId) =>
      bind.sessionClose(sessionId: sessionId);

  @override
  Future<ExitDirectoryAnswer> directory() async =>
      parseExitDirectory(await bind.mainGetCommon(key: 'leapgate-exits'));

  @override
  SessionRoute connection(SessionID sessionId) => SessionRoute.parse(
      lgBind.leapgateSessionConnection(sessionId: sessionId));
}
