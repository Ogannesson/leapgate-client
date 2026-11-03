import 'package:flutter_hbb/leapgate/account_api.dart';

/// H1's exports for tests (`LEAPGATE.md` §10.11): every call is recorded by name with its
/// arguments, and answers with the field of the same name. Set [accountApi] to it before the
/// models are first used (they are built on first use of `appCore.account`, `addressBook`,
/// `group`).
class FakeAccountApi implements AccountApi {
  final calls = <(String, List<Object?>)>[];

  List<List<Object?>> callsTo(String name) => [
        for (final (n, args) in calls)
          if (n == name) args
      ];

  static const _unsupported =
      ApiResult<Never>.error(ApiError(ApiErrorKind.unsupported));

  AccountUser? local;
  ApiResult<void> loginOptionsResult = const ApiResult.ok(null);
  ApiResult<AccountUser> loginResult = _unsupported;
  ApiResult<AccountUser> currentUserResult = _unsupported;
  List<Map<String, dynamic>> abCacheResult = const [];
  Map<String, dynamic>? groupCacheResult;
  ApiResult<AbBooks> booksResult = _unsupported;

  /// By guid; a guid not here answers `not_found`.
  final bookResults = <String, ApiResult<AbBookData>>{};

  /// What every write answers.
  ApiResult<void> writeResult = const ApiResult.ok(null);
  ApiResult<GroupData> groupResult = _unsupported;

  ApiResult<void> _write(String name, List<Object?> args) {
    calls.add((name, args));
    return writeResult;
  }

  @override
  AccountUser? localUser() {
    calls.add(('localUser', const []));
    return local;
  }

  @override
  Future<ApiResult<void>> loginOptions() async {
    calls.add(('loginOptions', const []));
    return loginOptionsResult;
  }

  @override
  Future<ApiResult<AccountUser>> login(String username, String password) async {
    calls.add(('login', [username, password]));
    return loginResult;
  }

  @override
  Future<ApiResult<AccountUser>> currentUser() async {
    calls.add(('currentUser', const []));
    return currentUserResult;
  }

  @override
  Future<void> logout() async => calls.add(('logout', const []));

  @override
  Future<List<Map<String, dynamic>>> abCache() async {
    calls.add(('abCache', const []));
    return abCacheResult;
  }

  @override
  Future<Map<String, dynamic>?> groupCache() async {
    calls.add(('groupCache', const []));
    return groupCacheResult;
  }

  @override
  Future<ApiResult<AbBooks>> books() async {
    calls.add(('books', const []));
    return booksResult;
  }

  @override
  Future<ApiResult<AbBookData>> book(String guid,
      {required String name, required bool personal}) async {
    calls.add(('book', [guid, name, personal]));
    return bookResults[guid] ??
        const ApiResult.error(ApiError(ApiErrorKind.notFound));
  }

  @override
  Future<ApiResult<void>> addPeer(
          String guid, Map<String, dynamic> peer) async =>
      _write('addPeer', [guid, peer]);

  @override
  Future<ApiResult<void>> updatePeer(
          String guid, String id, Map<String, dynamic> fields) async =>
      _write('updatePeer', [guid, id, fields]);

  @override
  Future<ApiResult<void>> deletePeers(String guid, List<String> ids) async =>
      _write('deletePeers', [guid, ids]);

  @override
  Future<ApiResult<void>> addTag(String guid, String name, int color) async =>
      _write('addTag', [guid, name, color]);

  @override
  Future<ApiResult<void>> renameTag(
          String guid, String oldName, String newName) async =>
      _write('renameTag', [guid, oldName, newName]);

  @override
  Future<ApiResult<void>> setTagColor(
          String guid, String name, int color) async =>
      _write('setTagColor', [guid, name, color]);

  @override
  Future<ApiResult<void>> deleteTags(String guid, List<String> names) async =>
      _write('deleteTags', [guid, names]);

  @override
  Future<ApiResult<GroupData>> group() async {
    calls.add(('group', const []));
    return groupResult;
  }
}
