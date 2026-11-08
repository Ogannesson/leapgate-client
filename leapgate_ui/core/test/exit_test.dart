import 'dart:convert';

import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/exit_api.dart';
import 'package:flutter_hbb/leapgate/exit_card.dart';
import 'package:flutter_hbb/leapgate/exit_directory.dart';
import 'package:flutter_hbb/leapgate/exit_nodes.dart';
import 'package:flutter_hbb/leapgate/peer_list.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'account_fakes.dart';
import 'exit_fakes.dart';
import 'fakes.dart';

// The exit node page's models (M5, `LEAPGATE.md` §10.12): a card follows E2 and its session's
// prompts in either order; the page's numbers, the ports, the directory. Device IDs are made up.

const _a = '100200300';
const _b = '400500600';

void main() {
  late ({ExitBind bind, FakeLeapgate lg, FakeExitApi api}) fakes;

  setUp(() => fakes = installExitFakes());

  Future<void> session(ExitCard card, Map<String, dynamic> evt) async {
    emitExitSession(fakes.bind, card, evt);
    await settle();
  }

  Future<void> e2(String id, String state,
      [Map<String, dynamic> extra = const {}]) async {
    fakes.api.push(id, state, extra);
    await settle();
  }

  test('use logs in at once; the password, then in use', () async {
    final card = appCore.exitNodes.use(_a, name: 'Study');
    expect(fakes.api.callsTo('sessionAdd'), [
      [card.sessionId, _a, kExitFirstPort, '', false]
    ]);
    expect(card.state, ExitCardState.connecting);
    // The same device again: the same card.
    expect(appCore.exitNodes.use(_a), same(card));

    await session(card, exitMsgbox('input-password', 'Password Required', ''));
    expect(card.state, ExitCardState.password);
    expect(appCore.exitNodes.needsAttention, true);

    card.submitPassword(' pw ', remember: true);
    expect(card.state, ExitCardState.verifying);
    final login = fakes.bind.callsTo(#sessionLogin).single.namedArguments;
    expect(login[#password], 'pw');
    expect(login[#remember], true);

    await session(card, exitMsgbox('re-input-password', 'Wrong Password', ''));
    expect(card.state, ExitCardState.password);
    expect(card.wrongInput, true);

    await e2(_a, 'in_use', {'transport': 'relay'});
    expect(card.state, ExitCardState.inUse);
    expect(card.direct, false);
    expect(card.socksAddress, 'socks5h://127.0.0.1:21180');
    expect(card.httpAddress, 'http://127.0.0.1:21180');
    expect(appCore.exitNodes.needsAttention, false);
  });

  test('2FA: the code, a wrong one, then verifying', () async {
    // From the address book: with its shared password.
    final card = appCore.exitNodes.use(_a, sharedPassword: 'abc');
    expect(fakes.api.callsTo('sessionAdd').single.sublist(3), ['abc', true]);
    await session(card, exitMsgbox('input-2fa', '2FA Required', ''));
    expect(card.state, ExitCardState.twoFactor);
    expect(card.wrongInput, false);
    expect(appCore.exitNodes.needsAttention, true);

    card.submit2fa(' 123456 ', trust: true);
    expect(card.state, ExitCardState.verifying);
    final sent = fakes.bind.callsTo(#sessionSend2Fa).single.namedArguments;
    expect(sent[#code], '123456');
    expect(sent[#trustThisDevice], true);

    await session(card, exitMsgbox('input-2fa', 'Wrong 2FA Code', ''));
    expect(card.state, ExitCardState.twoFactor);
    expect(card.wrongInput, true);
  });

  test('a refusal stops the card whichever stream says it first', () async {
    fakes.lg.reasons['Exit not enabled'] = 'exit_not_enabled';
    final first = appCore.exitNodes.use(_a);
    await e2(_a, 'stopped');
    expect(first.state, ExitCardState.stopped);
    expect(first.stopReason, isNull);
    await session(
        first, exitMsgbox('error', 'Login Error', 'Exit not enabled'));
    expect(first.stopReason!.code, 'exit_not_enabled');

    final second = appCore.exitNodes.use(_b);
    await session(
        second, exitMsgbox('error', 'Login Error', 'Exit not enabled'));
    expect(second.state, ExitCardState.connecting);
    await e2(_b, 'stopped');
    expect(second.stopReason!.code, 'exit_not_enabled');

    // E2's own reason wins. A prompt of the stopped attempt is dropped; "Retry" connects from
    // the click on, without the old reason, and the new attempt's prompts count again.
    await e2(_b, 'stopped', {
      'reason': {'code': 'exit_not_supported'}
    });
    expect(second.stopReason!.code, 'exit_not_supported');
    await session(second, exitMsgbox('wait-remote-accept-nook', '', ''));
    second.retry();
    expect(fakes.api.callsTo('retry'), [
      [_b]
    ]);
    expect(second.state, ExitCardState.connecting);
    await e2(_b, 'stopped');
    expect(second.stopReason, isNull);
  });

  test('an insecure connection is refused and stops as unencrypted', () async {
    final card = appCore.exitNodes.use(_a);
    await session(
        card, exitMsgbox('insecure-connection-nocancel-hasclose', '', ''));
    final answer = fakes.bind.callsTo(#sessionSetCommon).single.namedArguments;
    expect(answer[#value], 'N');
    await e2(_a, 'stopped');
    expect(card.stopReason!.code, 'exit_need_encryption');
  });

  test('a blocked target is a notice once, not a failure', () async {
    fakes.lg.reasons['blocked'] = 'exit_blocked';
    fakes.lg.reasons['port'] = 'local_port_in_use';
    final card = appCore.exitNodes.use(_a);
    await e2(_a, 'in_use', {'transport': 'direct'});
    await session(card, exitMsgbox('error', 'Error', 'blocked'));
    await session(card, exitMsgbox('error', 'Error', 'blocked'));
    expect(card.notices, ['exit_blocked']);
    expect(card.state, ExitCardState.inUse);
    card.dismissNotice('exit_blocked');
    await session(card, exitMsgbox('error', 'Error', 'blocked'));
    expect(card.notices, isEmpty);
    // The port in use comes with E2; the session's message changes nothing.
    await session(card, exitMsgbox('error', 'Error', 'port'));
    await e2(_a, 'stopped');
    expect(card.stopReason, isNull);
  });

  test('what the numbers count', () async {
    final a = appCore.exitNodes.use(_a);
    final b = appCore.exitNodes.use(_b);
    expect(appCore.exitNodes.runningCount, 2);
    await e2(_a, 'port_in_use', {'port': 21180});
    expect(a.state, ExitCardState.portBusy);
    expect(a.busyPort, 21180);
    await e2(_b, 'interrupted', {'cause': 'tunnel_ended'});
    expect(appCore.exitNodes.runningCount, 1);
    await session(b, exitMsgbox('wait-remote-accept-nook', '', ''));
    // E2 has not said the new attempt began: still interrupted.
    expect(b.state, ExitCardState.interrupted);
    await e2(_b, 'connecting');
    expect(b.state, ExitCardState.waitAccept);
    expect(appCore.exitNodes.needsAttention, true);
    await e2(_b, 'stopped');
    expect(appCore.exitNodes.runningCount, 0);
    expect(appCore.exitNodes.needsAttention, false);
  });

  test('ports: kept per device, never another card\'s', () async {
    // A kept port out of range counts as none.
    fakes.bind.local[kOptionLeapgateExitPorts] =
        jsonEncode({_a: 70000, _b: 21181});
    final a = appCore.exitNodes.use(_a);
    expect(a.port, 21180);
    expect(appCore.exitNodes.use('700800900').port, 21182);
    final b = appCore.exitNodes.use(_b);
    expect(b.port, 21181);
    expect(jsonDecode(fakes.bind.local[kOptionLeapgateExitPorts]!),
        {_a: 21180, _b: 21181, '700800900': 21182});

    expect(a.changePort(21181), ExitPortError.taken);
    expect(a.changePort(0), ExitPortError.invalid);
    expect(fakes.api.callsTo('setPort'), isEmpty);
    expect(a.changePort(21190), isNull);
    expect(fakes.api.callsTo('setPort'), [
      [_a, 21190]
    ]);
    expect(a.socksAddress, 'socks5h://127.0.0.1:21190');

    // Stopped and used again: the port it kept.
    await a.stop();
    expect(appCore.exitNodes.use(_a).port, 21190);
  });

  test(
      'a new port after "port in use": the next login\'s prompt counts at once',
      () async {
    final card = appCore.exitNodes.use(_a);
    await e2(_a, 'port_in_use', {'port': 21180});
    expect(card.changePort(21190), isNull);
    expect(card.state, ExitCardState.connecting);
    // Rust logs in on the new port; its prompt comes before E2's `connecting`.
    await session(card, exitMsgbox('input-password', 'Password Required', ''));
    expect(card.state, ExitCardState.password);

    // Taken again: the same port is tried again (another program may have let it go); in use,
    // the same port asks nothing.
    await e2(_a, 'port_in_use', {'port': 21190});
    expect(card.changePort(21190), isNull);
    expect(card.state, ExitCardState.connecting);
    await e2(_a, 'in_use', {'transport': 'direct'});
    expect(card.changePort(21190), isNull);
    expect(fakes.api.callsTo('setPort'), [
      [_a, 21190],
      [_a, 21190],
    ]);

    // Rust no longer has the card: it goes.
    fakes.api.hasCard = false;
    await e2(_a, 'interrupted', {'cause': 'tunnel_ended'});
    card.retry();
    expect(appCore.exitNodes.cards, isEmpty);
  });

  test('interrupted by a failed login: the session says why', () async {
    fakes.lg.reasons['Remote desktop is offline'] = 'peer_offline';
    final card = appCore.exitNodes.use(_a);
    await e2(_a, 'interrupted', {'cause': 'login_failed'});
    await session(card,
        exitMsgbox('error', 'Connection Error', 'Remote desktop is offline'));
    expect(card.interruptReason!.code, 'peer_offline');
    await e2(_a, 'connecting');
    await e2(_a, 'interrupted', {'cause': 'tunnel_ended'});
    expect(card.interruptReason, isNull);
  });

  test('stop closes the session; Rust closing removes the card', () async {
    final a = appCore.exitNodes.use(_a);
    appCore.exitNodes.use(_b);
    await a.stop();
    expect(fakes.api.callsTo('close'), [
      [a.sessionId]
    ]);
    await e2(_b, 'closed');
    expect(appCore.exitNodes.cards, isEmpty);

    // Used again at once: the old session's last events are not the new card's.
    final again = appCore.exitNodes.use(_a);
    await e2(_a, 'closed', {'session_id': '${a.sessionId}'});
    await e2(_a, 'stopped', {'session_id': '${a.sessionId}'});
    expect(appCore.exitNodes.cards, [again]);
    expect(again.state, ExitCardState.connecting);
  });

  test('a session Rust does not add stops; Retry adds it again', () async {
    fakes.api.addError = const ExitAddError('already');
    final card = appCore.exitNodes.use(_a);
    expect(card.state, ExitCardState.stopped);
    expect(card.stopReason!.code, 'exit_already');
    fakes.api.addError = null;
    card.retry();
    expect(fakes.api.callsTo('sessionAdd'), hasLength(2));
    expect(card.state, ExitCardState.connecting);
  });

  test(
      'the device menu offers "Use as exit node" for a device not known to run '
      'another system than Windows', () {
    List<PeerAction> connect(String peerPlatform) => peerMenu(
            PeerCategory.recent,
            favorite: false,
            hasPassword: false,
            windows: true,
            peerPlatform: peerPlatform)
        .first;
    expect(connect('Windows'), contains(PeerAction.useAsExit));
    expect(connect(''), contains(PeerAction.useAsExit));
    expect(connect('Linux'), isNot(contains(PeerAction.useAsExit)));
  });

  test('an exit takes a device ID or ID@server', () {
    expect(isExitId('100 200 300'), true);
    expect(isExitId('study-pc'), true);
    expect(isExitId('abc_12@example.com'), true);
    expect(isExitId('abc_1@example.com'), false);
    expect(isExitId('12345'), false);
    expect(isExitId('123456'), true);
    expect(isExitId('a234567890123456'), true);
    expect(isExitId('a2345678901234567'), false);
    expect(isExitId('100200300@a@b'), false);
    expect(offersExit('100200300', ''), true);
    expect(offersExit('100200300', 'Windows'), true);
    expect(offersExit('100200300', 'Linux'), false);
    expect(offersExit('192.168.1.2', 'Windows'), false);
    expect(isExitId('192.168.1.2'), false);
    expect(isExitId('example.com:21118'), false);
    expect(isExitId('100200300/r'), false);
    expect(isExitId('100200300/r@example.com'), false);
    expect(isExitId('100200300@example.com/r'), false);
    expect(isExitId('100200300@example.com?key=abc'), false);
    expect(isExitId('书房'), false);
  });

  group('directory', () {
    late FakeAccountApi account;

    setUp(() {
      account = FakeAccountApi()
        ..loginResult = const ApiResult.ok(AccountUser(name: 'zhang'));
      accountApi = account;
    });

    test('signed out it asks nothing', () async {
      appCore.exitDirectory.open();
      await settle();
      expect(appCore.exitDirectory.state, ExitDirectoryState.notLoggedIn);
      expect(fakes.api.callsTo('directory'), isEmpty);
    });

    test(
        'signed in: loaded when the page opens and after signing in; signing out clears it',
        () async {
      fakes.api.directoryAnswer = (
        status: ExitDirectoryStatus.ok,
        exits: [const ExitNode(id: _a, hostname: 'Study', own: true)]
      );
      appCore.exitDirectory.open();
      await appCore.account.login('zhang', 'pw');
      await settle();
      expect(appCore.exitDirectory.state, ExitDirectoryState.ok);
      expect(appCore.exitDirectory.exits.single.hostname, 'Study');

      fakes.api.directoryAnswer =
          (status: ExitDirectoryStatus.ok, exits: <ExitNode>[]);
      await appCore.exitDirectory.load();
      expect(appCore.exitDirectory.state, ExitDirectoryState.empty);

      fakes.api.directoryAnswer =
          (status: ExitDirectoryStatus.unsupported, exits: <ExitNode>[]);
      await appCore.exitDirectory.load();
      expect(appCore.exitDirectory.state, ExitDirectoryState.unsupported);

      // A card in use stays when signing out (第四期 A2).
      appCore.exitNodes.use(_a);
      await appCore.account.logout();
      expect(appCore.exitDirectory.state, ExitDirectoryState.notLoggedIn);
      expect(appCore.exitNodes.cards, hasLength(1));
    });

    test('"not signed in" while signed in asks the account once', () async {
      await appCore.account.login('zhang', 'pw');
      account.currentUserResult =
          const ApiResult.ok(AccountUser(name: 'zhang'));
      fakes.api.directoryAnswer =
          (status: ExitDirectoryStatus.notLoggedIn, exits: <ExitNode>[]);
      appCore.exitDirectory.open();
      await settle();
      expect(account.callsTo('currentUser'), hasLength(1));
      expect(fakes.api.callsTo('directory'), hasLength(2));
      expect(appCore.exitDirectory.state, ExitDirectoryState.notLoggedIn);

      // The server signed us out meanwhile (M4).
      account.currentUserResult =
          const ApiResult.error(ApiError(ApiErrorKind.unauthorized));
      await appCore.exitDirectory.load();
      expect(appCore.account.loggedIn, false);
    });
  });

  test('the directory answer as Rust gives it', () {
    final ok = parseExitDirectory(jsonEncode({
      'state': 'ok',
      'exits': [
        {'id': _a, 'hostname': '', 'owner': 'li', 'own': false}
      ]
    }));
    expect(ok.status, ExitDirectoryStatus.ok);
    expect(ok.exits.single.owner, 'li');
    expect(parseExitDirectory('{"state":"not_logged_in"}').status,
        ExitDirectoryStatus.notLoggedIn);
    expect(parseExitDirectory('{"state":"error"}').status,
        ExitDirectoryStatus.error);
    expect(parseExitDirectory('nonsense').status, ExitDirectoryStatus.error);
  });
}
