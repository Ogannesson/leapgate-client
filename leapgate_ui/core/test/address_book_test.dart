import 'dart:convert';

import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/account.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/address_book.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/peer_list.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'account_fakes.dart';
import 'fakes.dart' show FakeWindow;

/// LocalConfig, its Flutter table and the recent sessions the address book reads.
class _Bind implements RustdeskImpl {
  final local = <String, String>{};
  final flutter = <String, String>{};
  final forgotten = <String>[];
  String recentForAb = '';

  @override
  bool isDisableAb({dynamic hint}) => false;

  @override
  String mainGetLocalOption({required String key, dynamic hint}) =>
      local[key] ?? '';

  @override
  Future<void> mainSetLocalOption(
          {required String key, required String value, dynamic hint}) async =>
      local[key] = value;

  @override
  String getLocalFlutterOption({required String k, dynamic hint}) =>
      flutter[k] ?? '';

  @override
  Future<void> setLocalFlutterOption(
          {required String k, required String v, dynamic hint}) async =>
      flutter[k] = v;

  @override
  Future<void> mainSetPeerAlias(
      {required String id, required String alias, dynamic hint}) async {}

  @override
  Future<void> mainForgetPassword({required String id, dynamic hint}) async =>
      forgotten.add(id);

  @override
  Future<String> mainGetNewStoredPeers({dynamic hint}) async => '';

  @override
  Future<String> mainLoadRecentPeersForAb(
          {required String filter, dynamic hint}) async =>
      recentForAb;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Signed in as zhangsan; a sign-out by the server resets the address book, as the account
/// model does.
class _Account extends AccountModel {
  _Account() : super(FakeAccountApi(), others: const []);

  var signedOut = 0;

  @override
  AccountUser? get user => const AccountUser(name: 'zhangsan');

  @override
  bool get loggedIn => true;

  @override
  void signedOutByServer() {
    signedOut++;
    appCore.addressBook.reset();
  }
}

class _Core extends AppCore {
  _Core() : super(window: FakeWindow());

  final _account = _Account();

  @override
  AccountModel get account => _account;
}

Peer _peer(String id,
        {List<String> tags = const [],
        String password = '',
        String hash = '',
        String username = '',
        bool? sameServer}) =>
    Peer.fromJson({
      'id': id,
      'tags': tags,
      'password': password,
      'hash': hash,
      'username': username,
      'same_server': sameServer,
    });

const _home =
    AbProfile(guid: 'g-home', name: '家里的电脑', owner: 'zhangsan', rule: 2);
const _friends =
    AbProfile(guid: 'g-friends', name: '朋友们', owner: 'lisi', rule: 1);

late FakeAccountApi api;
late _Bind _bind;

AddressBookModel get ab => appCore.addressBook;

/// The personal book with two devices and two tags; the shared ones as given.
void _serve({List<Peer>? personal, List<AbProfile> shared = const []}) {
  api.booksResult =
      ApiResult.ok(AbBooks(maxPeers: 0, personal: 'g-me', shared: [...shared]));
  api.bookResults['g-me'] = ApiResult.ok(AbBookData(
    peers: personal ??
        [
          _peer('123456789', tags: ['家里']),
          _peer('234567891'),
        ],
    tags: const [AbTag('家里', 0xFFE91E63), AbTag('工作', 0xFF2196F3)],
  ));
}

void main() {
  setUp(() {
    _bind = _Bind();
    platformFFI.setBindingForTesting(_bind);
    api = FakeAccountApi();
    accountApi = api;
    appCore = _Core();
    addTearDown(() => appCore.addressBook.dispose());
  });

  test(
      'the personal book first, the shared ones by name, with what each lets you do',
      () async {
    _serve(shared: [_home, _friends]);
    api.bookResults['g-friends'] =
        ApiResult.ok(AbBookData(peers: [_peer('345678912')], tags: const []));
    await ab.pull();

    expect(
        [for (final b in ab.books) b.name], [kAbPersonalName, '家里的电脑', '朋友们']);
    expect(ab.isPersonal(ab.current!), isTrue);
    expect([for (final p in ab.peers) p.id], ['123456789', '234567891']);
    expect([for (final b in ab.writableBooks) b.guid], ['g-me', 'g-home']);

    await ab.select(ab.books[2]);
    expect(_bind.flutter[kOptionCurrentAbName], '朋友们');
    expect([for (final p in ab.peers) p.id], ['345678912']);
    expect(ab.canWrite, isFalse);
    // The device menu of a read-only book keeps its writing items, greyed; the others stay.
    final menu = peerMenu(PeerCategory.addressBook,
            favorite: false,
            hasPassword: false,
            windows: true,
            ab: ab.menuFlags(PeerCategory.addressBook))
        .expand((g) => g);
    expect(menu, containsAll([PeerAction.rename, PeerAction.deleteFromAb]));
    expect([
      for (final a in menu)
        if (ab.greyed(a)) a
    ], [
      PeerAction.rename,
      PeerAction.editNote,
      PeerAction.setSharedPassword,
      PeerAction.deleteFromAb,
    ]);
    // The personal book is where it can go.
    expect(menu, contains(PeerAction.addToAb));
    expect([for (final b in ab.addTargets(PeerCategory.addressBook)) b.guid],
        ['g-me', 'g-home']);
  });

  test('team devices offer the connection types and "add to address book" only',
      () async {
    _serve();
    await ab.pull();
    expect(
        peerMenu(PeerCategory.group,
            favorite: false,
            hasPassword: true,
            windows: true,
            ab: ab.menuFlags(PeerCategory.group)),
        [
          [PeerAction.remoteDesktop, PeerAction.viaRelay],
          [PeerAction.addToAb],
        ]);
  });

  test('the tag filter: any selected tag, all of them, or untagged', () async {
    _serve(personal: [
      _peer('1', tags: ['家里']),
      _peer('2', tags: ['家里', '工作']),
      _peer('3'),
    ]);
    await ab.pull();
    List<String> shown() => [for (final p in ab.shownPeers) p.id];

    expect(shown(), ['1', '2', '3']);
    ab.toggleTag('家里');
    ab.toggleTag('工作');
    expect(shown(), ['1', '2']);
    await ab.setFilterByIntersection(true);
    expect(shown(), ['2']);
    ab.toggleTag(kAbUntagged);
    expect(shown(), ['2', '3']);
    ab.unselectAllTags();
    expect(shown(), ['1', '2', '3']);
  });

  test('"sync with recent sessions" writes what differs and only that',
      () async {
    _serve(personal: [
      _peer('1', username: 'old'),
      _peer('2', username: 'same'),
      _peer('3', username: 'mine', sameServer: true),
    ]);
    await ab.pull();
    await ab.setSyncWithRecent(true);
    _bind.recentForAb = jsonEncode([
      {'id': '1', 'username': 'new', 'hash': 'h1'},
      {'id': '2', 'username': 'same'},
      {'id': '3', 'username': 'theirs'},
    ]);
    await ab.syncFromRecent();

    expect(api.callsTo('updatePeer'), [
      [
        'g-me',
        '1',
        {'username': 'new', 'hash': 'h1'}
      ],
    ]);
    expect(ab.peers.first.username, 'new');
  });

  test(
      'a password Rust saved goes into the personal book when the device is in it',
      () async {
    _serve();
    await ab.pull();
    await ab.syncPeerHash('123456789', 'h');
    await ab.syncPeerHash('999999999', 'h');
    expect(api.callsTo('updatePeer'), [
      [
        'g-me',
        '123456789',
        {'hash': 'h'}
      ],
    ]);
  });

  test('connecting from a shared book takes its stored password', () async {
    _serve(shared: [_home]);
    api.bookResults['g-home'] = ApiResult.ok(AbBookData(
        peers: [_peer('1', password: 'pw'), _peer('2')], tags: const []));
    await ab.pull();
    expect(ab.sharedPasswordOf('1'), isNull);
    await ab.select(ab.books[1]);
    expect(ab.sharedPasswordOf('1'), 'pw');
    expect(ab.sharedPasswordOf('2'), isNull);
  });

  test('an expired token signs out and empties the address book', () async {
    _serve();
    await ab.pull();
    api.writeResult =
        const ApiResult.error(ApiError(ApiErrorKind.unauthorized));
    await ab.setNote('123456789', 'x');

    expect((appCore.account as _Account).signedOut, 1);
    expect(ab.books, isEmpty);
    expect(ab.peers, isEmpty);
    expect(ab.loaded, isFalse);
  });

  test('a server without an address book says so', () async {
    api.booksResult = const ApiResult.error(ApiError(ApiErrorKind.unsupported));
    await ab.pull();
    expect(ab.loaded, isTrue);
    expect(ab.unsupported, isTrue);
    expect(ab.pullError, isNull);
  });
}
