import 'dart:async';
import 'dart:convert';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/exit_api.dart';
import 'package:flutter_hbb/leapgate/exit_card.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'fakes.dart';

/// The exit exports of §10.12 for tests: calls recorded by name, E2 played from the test with
/// [push]. Set [exitApi] to it before `appCore.exitNodes` or `exitDirectory` is first used.
class FakeExitApi implements ExitApi {
  final calls = <(String, List<Object?>)>[];

  List<List<Object?>> callsTo(String name) => [
        for (final (n, args) in calls)
          if (n == name) args
      ];

  /// What [sessionAdd] answers.
  ExitAddError? addError;

  ExitDirectoryAnswer directoryAnswer =
      (status: ExitDirectoryStatus.ok, exits: <ExitNode>[]);

  final _events = StreamController<Map<String, dynamic>>.broadcast();

  /// An E2 event: `{"id","session_id","port","state",…}`, with the session last added for [id],
  /// as Rust sends it; [extra] can name another.
  void push(String id, String state, [Map<String, dynamic> extra = const {}]) {
    final added = callsTo('sessionAdd').where((c) => c[1] == id).lastOrNull;
    _events.add({
      'id': id,
      if (added != null) 'session_id': '${added[0]}',
      'state': state,
      ...extra,
    });
  }

  @override
  ExitAddError? sessionAdd(SessionID sessionId, String id, int port,
      {String password = '', bool isSharedPassword = false}) {
    calls
        .add(('sessionAdd', [sessionId, id, port, password, isSharedPassword]));
    return addError;
  }

  @override
  Stream<Map<String, dynamic>> events() => _events.stream;

  /// What [retry] and [setPort] answer: false when Rust has no such card.
  var hasCard = true;

  @override
  bool retry(String id) {
    calls.add(('retry', [id]));
    return hasCard;
  }

  @override
  bool setPort(String id, int port) {
    calls.add(('setPort', [id, port]));
    return hasCard;
  }

  @override
  Future<void> close(SessionID sessionId) async =>
      calls.add(('close', [sessionId]));

  @override
  Future<ExitDirectoryAnswer> directory() async {
    calls.add(('directory', const []));
    return directoryAnswer;
  }
}

/// Block 1 with LocalConfig kept as Rust does, for the exit port table.
class ExitBind extends FakeBind {
  final local = <String, String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      case #mainGetLocalOption:
        calls.add(invocation);
        return local[args[#key]] ?? '';
      case #mainSetLocalOption:
        calls.add(invocation);
        local[args[#key]] = args[#value];
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

/// [installFakes] with [ExitBind] and a [FakeExitApi].
({ExitBind bind, FakeLeapgate lg, FakeExitApi api}) installExitFakes() {
  final fakes = installFakes();
  final bind = ExitBind();
  platformFFI.setBindingForTesting(bind);
  final api = FakeExitApi();
  exitApi = api;
  return (bind: bind, lg: fakes.lg, api: api);
}

/// A session event of [card]'s exit session.
void emitExitSession(ExitBind bind, ExitCard card, Map<String, dynamic> evt) =>
    bind.streams[card.sessionId]!.add(EventToUI.event(jsonEncode(evt)));

Map<String, dynamic> exitMsgbox(String type, String title, String text) =>
    {'name': 'msgbox', 'type': type, 'title': title, 'text': text, 'link': ''};
