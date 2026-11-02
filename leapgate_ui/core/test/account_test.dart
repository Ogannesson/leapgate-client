import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/account.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'account_fakes.dart';
import 'fakes.dart' show FakeWindow, settle;

/// LocalConfig and the built-in options.
class _Bind implements RustdeskImpl {
  final local = <String, String>{};
  bool disableAccount = false;

  @override
  String mainGetLocalOption({required String key, dynamic hint}) =>
      local[key] ?? '';

  @override
  Future<void> mainSetLocalOption(
          {required String key, required String value, dynamic hint}) async =>
      local[key] = value;

  @override
  bool isDisableAccount({dynamic hint}) => disableAccount;

  @override
  bool isDisableAb({dynamic hint}) => false;

  @override
  bool isDisableGroupPanel({dynamic hint}) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _alice = AccountUser(name: 'alice', displayName: 'Alice');
const _bob = AccountUser(name: 'bob');

Peer _peer(String id, String owner) =>
    Peer.fromJson({'id': id, 'loginName': owner});

GroupData _team() => GroupData(
      users: const [_bob, _alice],
      peers: [_peer('111', 'bob'), _peer('222', 'alice'), _peer('333', 'bob')],
    );

void main() {
  late _Bind bind;
  late FakeAccountApi api;

  setUp(() {
    bind = _Bind();
    platformFFI.setBindingForTesting(bind);
    api = FakeAccountApi();
    accountApi = api;
    appCore = AppCore(window: FakeWindow());
    addTearDown(appCore.recentPeers.dispose);
    addTearDown(appCore.favPeers.dispose);
    addTearDown(appCore.lanPeers.dispose);
  });

  AccountModel account() => appCore.account;

  group('start (upstream refreshCurrentUser)', () {
    test('without a stored user nothing is asked', () async {
      await account().start();
      expect(account().loggedIn, isFalse);
      expect(api.callsTo('currentUser'), isEmpty);
      expect(api.callsTo('group'), isEmpty);
    });

    test('the built-in option keeps the account off', () async {
      bind.disableAccount = true;
      api.local = _alice;
      await account().start();
      expect(account().loggedIn, isFalse);
    });

    test(
        'a stored user shows the caches at once, then the server answer and the '
        'pulls', () async {
      api
        ..local = _alice
        ..groupCacheResult = {
          'users': [
            {'name': 'bob'},
            {'name': 'alice', 'display_name': 'Alice'},
          ],
          'peers': [
            {'id': '111', 'login_name': 'bob'},
          ],
        }
        ..currentUserResult =
            const ApiResult.ok(AccountUser(name: 'alice', displayName: 'Al'))
        ..groupResult = ApiResult.ok(_team());
      // Before the server answers.
      final started = account().start();
      expect(account().user!.displayNameOrName, 'Alice');
      await settle();
      await started;
      expect(account().user!.displayNameOrName, 'Al');
      expect(api.callsTo('groupCache'), hasLength(1));
      expect(api.callsTo('group'), hasLength(1));
      expect(appCore.group.peers.map((p) => p.id), ['111', '222', '333']);
    });

    test('the cached team devices keep their owner', () async {
      api
        ..local = _alice
        ..groupCacheResult = {
          'users': [
            {'name': 'bob'},
          ],
          'peers': [
            {'id': '111', 'login_name': 'bob'},
          ],
        }
        ..currentUserResult =
            const ApiResult.error(ApiError(ApiErrorKind.network, 'timed out'));
      await account().start();
      appCore.group.selectUser('bob');
      expect(appCore.group.shownPeers.map((p) => p.id), ['111']);
    });

    test(
        'a network error keeps the user and does not pull; retry asks again and '
        'pulls', () async {
      api
        ..local = _alice
        ..currentUserResult =
            const ApiResult.error(ApiError(ApiErrorKind.network, 'timed out'))
        ..groupResult = ApiResult.ok(_team());
      await account().start();
      expect(account().loggedIn, isTrue);
      expect(account().error!.kind, ApiErrorKind.network);
      expect(api.callsTo('group'), isEmpty);

      api.currentUserResult = const ApiResult.ok(_alice);
      await account().refresh();
      expect(account().error, isNull);
      expect(api.callsTo('group'), hasLength(1));
    });

    test('an invalid token signs out and forgets the cached team', () async {
      api
        ..local = _alice
        ..groupCacheResult = {
          'users': [
            {'name': 'alice'},
          ],
          'peers': [
            {'id': '222', 'login_name': 'alice'},
          ],
        }
        ..currentUserResult =
            const ApiResult.error(ApiError(ApiErrorKind.unauthorized));
      await account().start();
      expect(account().loggedIn, isFalse);
      expect(appCore.group.loaded, isFalse);
      expect(appCore.group.peers, isEmpty);
    });
  });

  group('login and logout', () {
    test('signing in keeps the user name for the next time and pulls',
        () async {
      api
        ..loginResult = const ApiResult.ok(_alice)
        ..groupResult = ApiResult.ok(_team());
      final result = await account().login('alice', 'secret');
      await settle();
      expect(result.ok, isTrue);
      expect(account().user!.name, 'alice');
      expect(account().lastUsername, 'alice');
      expect(api.callsTo('login'), [
        ['alice', 'secret']
      ]);
      expect(appCore.group.users.first.name, 'alice');
    });

    test('a wrong password leaves it signed out', () async {
      api.loginResult = const ApiResult.error(
          ApiError(ApiErrorKind.wrongCredentials, 'Wrong credentials'));
      final result = await account().login('alice', 'nope');
      expect(result.error!.kind, ApiErrorKind.wrongCredentials);
      expect(account().loggedIn, isFalse);
      expect(account().lastUsername, '');
      expect(api.callsTo('group'), isEmpty);
    });

    test('signing out ends with nothing left of the team', () async {
      api
        ..loginResult = const ApiResult.ok(_alice)
        ..groupResult = ApiResult.ok(_team());
      await account().login('alice', 'secret');
      await settle();
      await account().logout();
      expect(api.callsTo('logout'), hasLength(1));
      expect(account().loggedIn, isFalse);
      expect(appCore.group.peers, isEmpty);
      expect(appCore.group.users, isEmpty);
    });

    test('the team devices answering "unauthorized" sign out', () async {
      api
        ..loginResult = const ApiResult.ok(_alice)
        ..groupResult =
            const ApiResult.error(ApiError(ApiErrorKind.unauthorized));
      await account().login('alice', 'secret');
      await settle();
      expect(account().loggedIn, isFalse);
    });
  });

  group('team devices (upstream my_group.dart)', () {
    setUp(() async {
      api
        ..loginResult = const ApiResult.ok(_alice)
        ..groupResult = ApiResult.ok(_team());
      await account().login('alice', 'secret');
      await settle();
    });

    test('this user first; a person picked shows only their devices', () {
      final group = appCore.group;
      expect(group.users.map((u) => u.name), ['alice', 'bob']);
      expect(group.shownPeers, hasLength(3));
      group.selectUser('bob');
      expect(group.shownPeers.map((p) => p.id), ['111', '333']);
      group.selectUser(null);
      expect(group.shownPeers, hasLength(3));
    });

    test('the search finds people by name and clears the person picked', () {
      final group = appCore.group..selectUser('bob');
      group.setSearch('ALI');
      expect(group.selectedUser, isNull);
      expect(group.shownUsers.map((u) => u.name), ['alice']);
      expect(group.shownPeers.map((p) => p.id), ['222']);
    });

    test('a failed pull keeps the list and says why', () async {
      api.groupResult =
          const ApiResult.error(ApiError(ApiErrorKind.server, 'HTTP 500'));
      await appCore.group.pull();
      expect(appCore.group.error!.text, 'HTTP 500');
      expect(appCore.group.peers, hasLength(3));
    });

    test('online answers mark its devices', () async {
      await platformFFI.tryHandle({
        'name': 'callback_query_onlines',
        'onlines': '111',
        'offlines': '222',
      });
      final online = {for (final p in appCore.group.peers) p.id: p.online};
      expect(online, {'111': true, '222': false, '333': false});
    });
  });
}
