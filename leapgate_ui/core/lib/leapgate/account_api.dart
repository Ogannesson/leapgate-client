// The one place the new UI reaches the account, address book and team device exports of block 2
// (H1, `LEAPGATE.md` §10.11). The three models call [accountApi] only; tests set a fake.
import 'dart:convert';

import '../consts.dart';
import '../models/peer_model.dart';
import 'bridge.dart';

/// The error kinds H1 reports (`LEAPGATE.md` §10.11 "错误的形状").
enum ApiErrorKind {
  /// The token is no longer valid; Rust has already removed it, `user_info` and both caches.
  unauthorized,

  /// Login only: wrong user name or password.
  wrongCredentials,

  /// Login only: the server wants a verification code or 2FA, which Leapgate does not do (M4-1).
  verificationRequired,
  notFound,
  conflict,

  /// `ab/personal` answered 404: the server has no address book (07 §4.4).
  unsupported,
  network,
  server,
}

const _errorKinds = {
  'unauthorized': ApiErrorKind.unauthorized,
  'wrong_credentials': ApiErrorKind.wrongCredentials,
  'verification_required': ApiErrorKind.verificationRequired,
  'not_found': ApiErrorKind.notFound,
  'conflict': ApiErrorKind.conflict,
  'unsupported': ApiErrorKind.unsupported,
  'network': ApiErrorKind.network,
  'server': ApiErrorKind.server,
};

class ApiError {
  const ApiError(this.kind, [this.text = '']);

  final ApiErrorKind kind;

  /// What the server or the network said, as it said it; empty when there is nothing to show.
  final String text;
}

/// A value, or why there is none.
class ApiResult<T> {
  const ApiResult.ok(T this._value) : error = null;
  const ApiResult.error(ApiError this.error) : _value = null;

  final T? _value;
  final ApiError? error;

  bool get ok => error == null;

  /// Only when [ok].
  T get value => _value as T;
}

/// An export's JSON: `{"error":…,"text":…}` is an error, anything else goes to [ok]. A kind this
/// UI does not know counts as `server`.
ApiResult<T> parseApiResult<T>(
    String json, T Function(Map<String, dynamic> m) ok) {
  final m = jsonDecode(json) as Map<String, dynamic>;
  final error = m['error'];
  if (error is String) {
    return ApiResult.error(ApiError(
        _errorKinds[error] ?? ApiErrorKind.server, m['text'] as String? ?? ''));
  }
  return ApiResult.ok(ok(m));
}

/// A signed-in user, or a person in the team devices: the server's user object (upstream
/// `common/hbbs/hbbs.dart` `UserPayload`).
class AccountUser {
  const AccountUser({
    required this.name,
    this.displayName = '',
    this.avatar = '',
    this.email = '',
    this.note = '',
    this.isAdmin = false,
  });

  AccountUser.fromJson(Map<String, dynamic> m)
      : name = m['name'] as String? ?? '',
        displayName = m['display_name'] as String? ?? '',
        avatar = m['avatar'] as String? ?? '',
        email = m['email'] as String? ?? '',
        note = m['note'] as String? ?? '',
        isAdmin = m['is_admin'] == true;

  /// The user name, `@name` in the account menu.
  final String name;
  final String displayName;
  final String avatar;
  final String email;
  final String note;
  final bool isAdmin;

  String get displayNameOrName =>
      displayName.trim().isEmpty ? name : displayName;
}

/// Upstream `common/hbbs/hbbs.dart` `ShareRule`, without its text: the rule of a shared address
/// book.
enum ShareRule {
  read(1),
  readWrite(2),
  fullControl(3);

  const ShareRule(this.value);
  final int value;

  static ShareRule? fromValue(int v) =>
      values.where((r) => r.value == v).firstOrNull;
}

/// An address book in the list: the personal one or a shared one (upstream `AbProfile`).
class AbProfile {
  const AbProfile({
    required this.guid,
    required this.name,
    this.owner = '',
    this.note = '',
    this.rule = 0,
  });

  AbProfile.fromJson(Map<String, dynamic> m)
      : guid = m['guid'] as String? ?? '',
        name = m['name'] as String? ?? '',
        owner = m['owner'] as String? ?? '',
        note = m['note'] as String? ?? '',
        rule = m['rule'] as int? ?? 0;

  final String guid;

  /// A shared book's name; the personal book has its own name in the UI.
  final String name;
  final String owner;
  final String note;

  /// [ShareRule.value] for a shared book; 0 for the personal one.
  final int rule;
}

/// `leapgate_ab_books`.
class AbBooks {
  const AbBooks({
    required this.maxPeers,
    required this.personal,
    required this.shared,
  });

  AbBooks.fromJson(Map<String, dynamic> m)
      : maxPeers = m['max_peers'] as int? ?? 0,
        personal = m['personal'] as String? ?? '',
        shared = [
          for (final p in m['shared'] as List? ?? const [])
            AbProfile.fromJson(p as Map<String, dynamic>),
        ];

  /// Devices one book may hold; 0 is no limit.
  final int maxPeers;

  /// The personal book's guid.
  final String personal;

  /// As the server sent them.
  final List<AbProfile> shared;
}

class AbTag {
  const AbTag(this.name, this.color);

  AbTag.fromJson(Map<String, dynamic> m)
      : name = m['name'] as String? ?? '',
        color = m['color'] as int? ?? 0;

  final String name;

  /// ARGB, as Flutter's `Color.value` (what upstream stores).
  final int color;
}

/// `leapgate_ab_book`: one book's devices and tags.
class AbBookData {
  const AbBookData({required this.peers, required this.tags});

  AbBookData.fromJson(Map<String, dynamic> m)
      : peers = [
          for (final p in m['peers'] as List? ?? const [])
            Peer.fromJson(p as Map<String, dynamic>),
        ],
        tags = [
          for (final t in m['tags'] as List? ?? const [])
            AbTag.fromJson(t as Map<String, dynamic>),
        ];

  final List<Peer> peers;
  final List<AbTag> tags;
}

/// `leapgate_group`: the people and the devices of the team devices category.
class GroupData {
  const GroupData({required this.users, required this.peers});

  GroupData.fromJson(Map<String, dynamic> m)
      : users = [
          for (final u in m['users'] as List? ?? const [])
            AccountUser.fromJson(u as Map<String, dynamic>),
        ],
        peers = [
          for (final p in m['peers'] as List? ?? const [])
            groupPeer(p as Map<String, dynamic>),
        ];

  final List<AccountUser> users;

  /// [Peer.loginName] is the owner's user name.
  final List<Peer> peers;
}

/// A device of `/api/peers` as a [Peer]: upstream `common/hbbs/hbbs.dart` `PeerPayload.toPeer`
/// and `_platform`, unchanged.
Peer groupPeer(Map<String, dynamic> json) {
  final info = json['info'] is Map<String, dynamic>
      ? json['info'] as Map<String, dynamic>
      : <String, dynamic>{};
  return Peer.fromJson({
    "id": json['id'] ?? '',
    'loginName': json['user_name'] ?? '',
    "username": info['username'] ?? '',
    "platform": _platform(info['os']),
    "hostname": info['device_name'],
    "device_group_name": json['device_group_name'] ?? '',
    "note": json['note'] ?? '',
  });
}

String? _platform(dynamic field) {
  if (field == null) {
    return null;
  }
  final fieldStr = field.toString();
  List<String> list = fieldStr.split(' / ');
  if (list.isEmpty) return null;
  final os = list[0];
  switch (os.toLowerCase()) {
    case 'windows':
      return kPeerPlatformWindows;
    case 'linux':
      return kPeerPlatformLinux;
    case 'macos':
      return kPeerPlatformMacOS;
    case 'android':
      return kPeerPlatformAndroid;
    default:
      if (fieldStr.toLowerCase().contains('linux')) {
        return kPeerPlatformLinux;
      }
      return null;
  }
}

/// H1's exports as the models use them (`LEAPGATE.md` §10.11 table). The token never comes
/// through here (M4-3).
abstract interface class AccountApi {
  /// The signed-in user as stored on this device, without asking the server; null when there is
  /// no token. `leapgate_account_local`.
  AccountUser? localUser();

  /// Whether the API server answers at all (M4-4); what it offers is ignored.
  Future<ApiResult<void>> loginOptions();

  Future<ApiResult<AccountUser>> login(String username, String password);

  Future<ApiResult<AccountUser>> currentUser();

  /// Always ends signed out on this device, whatever the server said (M4-9).
  Future<void> logout();

  /// The address book cache as Rust stored it (upstream's `_ab` entries: `guid`, `name`,
  /// `peers`, `tags`, `tag_colors`); empty without a cache for the current token.
  Future<List<Map<String, dynamic>>> abCache();

  /// The team devices cache (upstream's `_group`: `users`, `peers`); null without one.
  Future<Map<String, dynamic>?> groupCache();

  Future<ApiResult<AbBooks>> books();

  /// [personal] and [name] tell Rust where the book goes in the cache.
  Future<ApiResult<AbBookData>> book(String guid,
      {required String name, required bool personal});

  /// [peer] as upstream sends it: the personal book without `password`, a shared one without
  /// `hash` (the caller strips them).
  Future<ApiResult<void>> addPeer(String guid, Map<String, dynamic> peer);

  /// Only the fields to change, besides `id`: `tags`, `alias`, `note`, `hash`, `password`,
  /// `username`, `hostname`, `platform`, ….
  Future<ApiResult<void>> updatePeer(
      String guid, String id, Map<String, dynamic> fields);

  Future<ApiResult<void>> deletePeers(String guid, List<String> ids);

  Future<ApiResult<void>> addTag(String guid, String name, int color);

  Future<ApiResult<void>> renameTag(
      String guid, String oldName, String newName);

  Future<ApiResult<void>> setTagColor(String guid, String name, int color);

  Future<ApiResult<void>> deleteTags(String guid, List<String> names);

  Future<ApiResult<GroupData>> group();
}

/// Set by tests; the app keeps the default.
AccountApi accountApi = const RustAccountApi();

/// Block 2: the exports of §10.11.
class RustAccountApi implements AccountApi {
  const RustAccountApi();

  static ApiResult<AccountUser> _user(String json) => parseApiResult(
      json, (m) => AccountUser.fromJson(m['user'] as Map<String, dynamic>));

  static ApiResult<void> _done(String json) => parseApiResult(json, (_) {});

  @override
  AccountUser? localUser() {
    final user = jsonDecode(lgBind.leapgateAccountLocal())['user'];
    return user is Map<String, dynamic> ? AccountUser.fromJson(user) : null;
  }

  @override
  Future<ApiResult<void>> loginOptions() async =>
      _done(await lgBind.leapgateAccountLoginOptions());

  @override
  Future<ApiResult<AccountUser>> login(
          String username, String password) async =>
      _user(await lgBind.leapgateAccountLogin(
          username: username, password: password));

  @override
  Future<ApiResult<AccountUser>> currentUser() async =>
      _user(await lgBind.leapgateAccountCurrentUser());

  @override
  Future<void> logout() => lgBind.leapgateAccountLogout();

  @override
  Future<List<Map<String, dynamic>>> abCache() async => [
        for (final e
            in jsonDecode(await lgBind.leapgateAbCache())['entries'] as List)
          e as Map<String, dynamic>,
      ];

  @override
  Future<Map<String, dynamic>?> groupCache() async {
    final m = jsonDecode(await lgBind.leapgateGroupCache())
        as Map<String, dynamic>;
    return m.isEmpty ? null : m;
  }

  @override
  Future<ApiResult<AbBooks>> books() async =>
      parseApiResult(await lgBind.leapgateAbBooks(), AbBooks.fromJson);

  @override
  Future<ApiResult<AbBookData>> book(String guid,
          {required String name, required bool personal}) async =>
      parseApiResult(
          await lgBind.leapgateAbBook(
              guid: guid, name: name, personal: personal),
          AbBookData.fromJson);

  @override
  Future<ApiResult<void>> addPeer(
          String guid, Map<String, dynamic> peer) async =>
      _done(await lgBind.leapgateAbAddPeer(guid: guid, peer: jsonEncode(peer)));

  @override
  Future<ApiResult<void>> updatePeer(
          String guid, String id, Map<String, dynamic> fields) async =>
      _done(await lgBind.leapgateAbUpdatePeer(
          guid: guid, peer: jsonEncode({...fields, 'id': id})));

  @override
  Future<ApiResult<void>> deletePeers(String guid, List<String> ids) async =>
      _done(await lgBind.leapgateAbDeletePeers(guid: guid, ids: ids));

  @override
  Future<ApiResult<void>> addTag(String guid, String name, int color) async =>
      _done(
          await lgBind.leapgateAbAddTag(guid: guid, name: name, color: color));

  @override
  Future<ApiResult<void>> renameTag(
          String guid, String oldName, String newName) async =>
      _done(await lgBind.leapgateAbRenameTag(
          guid: guid, oldName: oldName, newName: newName));

  @override
  Future<ApiResult<void>> setTagColor(
          String guid, String name, int color) async =>
      _done(await lgBind.leapgateAbSetTagColor(
          guid: guid, name: name, color: color));

  @override
  Future<ApiResult<void>> deleteTags(String guid, List<String> names) async =>
      _done(await lgBind.leapgateAbDeleteTags(guid: guid, names: names));

  @override
  Future<ApiResult<GroupData>> group() async =>
      parseApiResult(await lgBind.leapgateGroup(), GroupData.fromJson);
}
