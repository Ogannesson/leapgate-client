// Skeleton (`LEAPGATE.md` §10.11); coder A rewrites upstream `models/user_model.dart` here and
// adds its source line.
import 'package:flutter/foundation.dart';

import 'account_api.dart';

/// What hangs on the sign-in: the address book and the team devices, later the exit directory
/// (M5). The account model drives them in the order of §10.11.
abstract interface class AccountData {
  /// Shows what was cached for the current token before the server answers.
  Future<void> loadCache();

  Future<void> pull();

  /// Forgets everything; after signing out or when the token is no longer valid.
  void reset();
}

/// The account area and the login dialog (01 P1 blocks D and K), and the settings page's account
/// section later (M6). Coder A fills it.
class AccountModel extends ChangeNotifier {
  AccountModel(this._api, {required List<AccountData> others})
      : _others = others;

  // ignore: unused_field
  final AccountApi _api;
  // ignore: unused_field
  final List<AccountData> _others;

  /// Null while signed out.
  AccountUser? get user => null;

  bool get loggedIn => user != null;

  /// Why the last check with the server failed (network or server); still signed in then, and
  /// the lists offer to retry.
  ApiError? get error => null;

  /// Hidden by the built-in `disable-account` option.
  bool get disabled => false;

  /// At startup: the stored user, the caches, the server's answer, then the others' pulls.
  Future<void> start() async {}

  /// Whether the login dialog can reach the API server (M4-4).
  Future<ApiResult<void>> checkLoginOptions() async =>
      const ApiResult.error(ApiError(ApiErrorKind.unsupported));

  /// On success the others pull.
  Future<ApiResult<AccountUser>> login(
          String username, String password) async =>
      const ApiResult.error(ApiError(ApiErrorKind.unsupported));

  /// Resets the others as well.
  Future<void> logout() async {}

  /// Asks the server for the current user again ("retry" in the lists).
  Future<void> refresh() async {}

  /// Any call answered [ApiErrorKind.unauthorized]: Rust has already dropped the token; this
  /// signs out here and resets the others.
  void signedOutByServer() {}
}
