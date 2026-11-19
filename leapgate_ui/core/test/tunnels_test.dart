import 'dart:convert';

import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/exit_nodes.dart';
import 'package:flutter_hbb/leapgate/tunnel_api.dart';
import 'package:flutter_hbb/leapgate/tunnel_card.dart';
import 'package:flutter_test/flutter_test.dart';

import 'exit_fakes.dart';
import 'fakes.dart';
import 'tunnel_fakes.dart';

// The tunnel cards' models (M9c, `LEAPGATE.md` §10.18, 13 §1.3): a card follows the tunnel events
// row by row and its session's prompts; the page's numbers; the ports shared with the exit cards.
// Device IDs are made up, addresses from the documentation ranges.

const _a = '100200300';
const _b = '400500600';
const _tcp = TunnelKind.tcp;

/// A session event of [card]'s session.
void emitTunnelSession(
        FakeBind bind, TunnelCard card, Map<String, dynamic> evt) =>
    bind.streams[card.sessionId]!.add(EventToUI.event(jsonEncode(evt)));

Map<String, dynamic> tunnelMsgbox(String type, String title) =>
    exitMsgbox(type, title, '');

void main() {
  late ({ExitBind bind, FakeLeapgate lg, FakeExitApi api}) fakes;
  late FakeTunnelApi api;

  setUp(() {
    fakes = installExitFakes();
    api = FakeTunnelApi();
    tunnelApi = api;
    api.forwards[_a] = [
      (localPort: 2222, host: 'localhost', remotePort: 22),
      (localPort: 15432, host: '192.0.2.20', remotePort: 5432),
    ];
  });

  Future<void> row(String state, int port,
      [Map<String, dynamic> extra = const {}, String id = _a]) async {
    api.push(id, _tcp, state, port: port, extra: extra);
    await settle();
  }

  Future<void> session(TunnelCard card, Map<String, dynamic> evt) async {
    emitTunnelSession(fakes.bind, card, evt);
    await settle();
  }

  List<TunnelRowState> states(TunnelCard card) =>
      [for (final r in card.rows) r.state];

  test('a card logs in at once with the saved forwards, each row on its own',
      () async {
    final card = appCore.tunnels.open(_a, _tcp, name: 'Study');
    expect(api.callsTo('sessionAdd'), [
      [card.sessionId, _a, _tcp, '', false, null, false]
    ]);
    expect(appCore.tunnels.open(_a, _tcp), same(card));
    expect(
        states(card), [TunnelRowState.connecting, TunnelRowState.connecting]);
    expect(appCore.tunnels.runningCount, 1);

    await row('in_use', 2222, {'transport': 'direct'});
    await row('in_use', 15432, {'transport': 'relay'});
    expect(states(card), [TunnelRowState.inUse, TunnelRowState.inUse]);
    expect([for (final r in card.rows) r.direct], [true, false]);

    await row('interrupted', 15432, {
      'cause': 'login_failed',
      'reason': {'code': 'peer_offline'}
    });
    expect(card.rows[1].state, TunnelRowState.interrupted);
    expect(card.rows[1].reason!.code, 'peer_offline');
    await row('interrupted', 2222, {'cause': 'tunnel_ended'});
    expect(card.rows[0].reason, isNull);
    // The listeners stay open: still running.
    expect(appCore.tunnels.runningCount, 1);

    await row('stopped', 2222, {
      'reason': {'code': 'other'},
      'text': 'Refused here'
    });
    expect(card.rows[0].reason!.code, 'other');
    expect(card.rows[0].reason!.text, 'Refused here');
    await row('port_in_use', 15432);
    expect(states(card), [TunnelRowState.stopped, TunnelRowState.portBusy]);
    expect(card.running, false);
    expect(appCore.tunnels.runningCount, 0);

    // "重试": connecting from the click on.
    card.retryRow(card.rows[1]);
    expect(api.callsTo('retry').single, [card.sessionId, 15432]);
    expect(card.rows[1].state, TunnelRowState.connecting);
    expect(appCore.tunnels.runningCount, 1);
  });

  test('the question is asked once and goes when no row logs in any more',
      () async {
    final card = appCore.tunnels.open(_a, _tcp);
    await session(card, tunnelMsgbox('input-password', 'Password Required'));
    expect(card.question, TunnelQuestion.password);
    expect(appCore.tunnels.needsAttention, true);
    expect(appCore.backgroundAttention, true);

    card.submitPassword(' pw ', remember: false);
    expect(card.question, TunnelQuestion.verifying);
    expect(fakes.bind.callsTo(#sessionLogin).single.namedArguments[#password],
        'pw');

    // "在本机接受": one row is accepted, the other still waits.
    await session(card, tunnelMsgbox('wait-remote-accept-nook', ''));
    expect(card.question, TunnelQuestion.waitAccept);
    await row('in_use', 2222, {'transport': 'direct'});
    expect(card.question, TunnelQuestion.waitAccept);
    await row('in_use', 15432, {'transport': 'direct'});
    expect(card.question, TunnelQuestion.none);
    expect(appCore.backgroundAttention, false);
  });

  test('an unencrypted connection is asked about, not declined', () async {
    final card = appCore.tunnels.open(_a, _tcp);
    await session(card, tunnelMsgbox('insecure-connection', ''));
    expect(card.question, TunnelQuestion.insecure);
    expect(card.needsAttention, true);
    await card.answerInsecure(proceed: false);
    expect(card.question, TunnelQuestion.none);
    final set = fakes.bind.callsTo(#sessionSetCommon).single.namedArguments;
    expect(set[#key], 'continue-insecure-connection');
    expect(set[#value], 'N');
    await row('stopped', 2222, {
      'reason': {'code': 'insecure_declined'}
    });
    expect(card.rows[0].reason!.code, 'insecure_declined');
  });

  test('adding: the three checks, then the row logs in; a port deleted waits',
      () async {
    final exit = appCore.exitNodes.use(_b);
    // The old UI's exit mapping on 31180: not a row, but upstream would not add its port.
    api.hiddenPorts[_a] = {31180};
    final card = appCore.tunnels.open(_a, _tcp);
    expect(card.rows.length, 2);
    expect(card.addForward(31180, '', 22), TunnelAddForwardError.duplicate);
    expect(card.addForward(0, '', 22), TunnelAddForwardError.invalid);
    expect(card.addForward(70000, '', 22), TunnelAddForwardError.invalid);
    expect(card.addForward(8080, '', 0), TunnelAddForwardError.invalid);
    expect(card.addForward(2222, '', 22), TunnelAddForwardError.duplicate);
    expect(card.addForward(exit.port, '', 22), TunnelAddForwardError.taken);
    expect(api.callsTo('addForward'), isEmpty);

    // An empty host is the remote device itself.
    expect(card.addForward(8080, ' ', 80), isNull);
    expect(api.callsTo('addForward').single,
        [card.sessionId, 8080, 'localhost', 80]);
    expect(card.rows.last.forward,
        (localPort: 8080, host: 'localhost', remotePort: 80));
    expect(card.rows.last.state, TunnelRowState.connecting);

    // Deleted: gone from the card at once; added again before Rust said `removed`, Rust takes
    // it once it did.
    card.removeForward(card.rows.first);
    expect(api.callsTo('removeForward').single, [card.sessionId, 2222]);
    expect([for (final r in card.rows) r.localPort], [15432, 8080]);
    expect(card.addForward(2222, '192.0.2.30', 2022), isNull);
    expect(api.callsTo('addForward').length, 1);
    await row('removed', 2222);
    expect(api.callsTo('addForward').last,
        [card.sessionId, 2222, '192.0.2.30', 2022]);
    expect(card.rows.where((r) => r.localPort == 2222).single.state,
        TunnelRowState.connecting);

    card.removeForward(card.rows.last);
    await row('removed', 8080);
    expect([for (final r in card.rows) r.localPort], [2222, 15432]);
  });

  test('exit and tunnel cards stay off each other\'s ports', () async {
    api.forwards[_a] = [
      (localPort: kExitFirstPort, host: 'localhost', remotePort: 22)
    ];
    appCore.tunnels.open(_a, _tcp);
    final exit = appCore.exitNodes.use(_b);
    expect(exit.port, kExitFirstPort + 1);
    expect(exit.changePort(kExitFirstPort), ExitPortError.taken);

    // A row that stopped listens no more.
    await row('stopped', kExitFirstPort);
    expect(exit.changePort(kExitFirstPort), isNull);
  });

  test('a conflict with an exit card: nothing runs until "Retry" adds it',
      () async {
    api.addError = const TunnelAddError('already');
    final card = appCore.tunnels.open(_a, _tcp);
    expect(card.addError!.code, 'already');
    expect(card.running, false);
    expect(appCore.backgroundCount, 0);
    expect(fakes.bind.callsTo(#sessionStart), isEmpty);

    api.addError = null;
    card.retry();
    expect(api.callsTo('sessionAdd').length, 2);
    expect(card.addError, isNull);
    expect(appCore.backgroundCount, 1);
  });

  test('"closed" and "Stop" take the card away; an old session is ignored',
      () async {
    final card = appCore.tunnels.open(_a, _tcp);
    await card.stop();
    expect(api.callsTo('close').single, [card.sessionId]);
    expect(appCore.tunnels.cards, isEmpty);

    final again = appCore.tunnels.open(_a, _tcp);
    // The old card's last events come after the new card was opened.
    await row('in_use', 2222,
        {'transport': 'direct', 'session_id': '${card.sessionId}'});
    expect(again.rows.first.state, TunnelRowState.connecting);

    api.push(_a, _tcp, 'closed');
    await settle();
    expect(appCore.tunnels.cards, isEmpty);
  });

  test('an RDP card: one row on port 0, the port from the device settings',
      () async {
    api.rdp[_a] = (port: '3390', username: '', password: '');
    final rdp = appCore.tunnels.open(_a, TunnelKind.rdp);
    final tcp = appCore.tunnels.open(_a, _tcp);
    expect(rdp, isNot(same(tcp)));
    expect(rdp.rdpPort, 3390);
    expect([for (final r in rdp.rows) r.localPort], [0]);
    expect(appCore.backgroundCount, 2);

    api.push(_a, TunnelKind.rdp, 'notice', port: 0, extra: {
      'reason': {'code': 'tunnel_unreachable', 'target': 'localhost:3390'}
    });
    await settle();
    expect(rdp.rows.single.notices.single.code, 'tunnel_unreachable');
    // The same reason again is not shown twice.
    api.push(_a, TunnelKind.rdp, 'notice', port: 0, extra: {
      'reason': {'code': 'tunnel_unreachable', 'target': 'localhost:3390'}
    });
    await settle();
    expect(rdp.rows.single.notices.length, 1);

    await rdp.newRdp();
    expect(api.callsTo('newRdp').single, [rdp.sessionId]);

    api.rdp[_b] = (port: 'x', username: '', password: '');
    expect(appCore.tunnels.open(_b, TunnelKind.rdp).rdpPort, kRdpDefaultPort);
  });

  test('the platform: the device list\'s first, the remote\'s once logged in',
      () async {
    api.addError = const TunnelAddError('already');
    // A card that never logs in keeps the list's.
    expect(appCore.tunnels.open(_b, _tcp, platform: 'Linux').platform, 'Linux');
    api.addError = null;
    final card = appCore.tunnels.open(_a, _tcp, platform: 'Linux');
    await session(card, {'name': 'peer_info', 'platform': 'Windows'});
    expect(card.platform, 'Windows');
  });

  test('the saved local ports include the old UI\'s exit mapping', () {
    expect(
        parseSavedLocalPorts(
            '{"port_forwards": [[21180, "leapgate-exit.invalid", 65536], [8080, "localhost", 80]]}'),
        {21180, 8080});
    expect(parseSavedLocalPorts('{}'), isEmpty);
  });
}
