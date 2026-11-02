// 上游：flutter/lib/models/user_model.dart@bd9262397（改写：HTTP 换成块 2 的账号导出，令牌和 `user_info` 只在 Rust 里读写；状态改成 ChangeNotifier；`refreshCurrentUser`、`updateOtherModels`、`logOut`、`reset` 的顺序照旧，见 `LEAPGATE.md` §10.11。上游这几段改了，合并时人工移植到这里）
import 'package:flutter/foundation.dart';

import '../models/platform_model.dart';
import 'account_api.dart';

/// LocalConfig: the user name of the last sign-in on this device, which the login dialog
/// prefills (01 P1 block K). Upstream prefills `user_info`'s name, which signing out empties.
const kOptionLeapgateLastUsername = 'leapgate-last-username';

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
/// section later (M6).
class AccountModel extends ChangeNotifier {
  AccountModel(this._api, {required List<AccountData> others})
      : _others = others;

  final AccountApi _api;
  final List<AccountData> _others;

  AccountUser? _user;
  ApiError? _error;
  bool _checking = false;
  bool _signingOut = false;

  /// Null while signed out.
  AccountUser? get user => _user;

  bool get loggedIn => _user != null;

  /// Why the last check with the server failed (network or server); still signed in then, and
  /// the lists offer to retry.
  ApiError? get error => _error;

  /// Hidden by the built-in `disable-account` option.
  bool get disabled => bind.isDisableAccount();

  /// Between "Sign out" and the end of the request (at most 2 s, M4-9).
  bool get signingOut => _signingOut;

  /// The login dialog's user name.
  String get lastUsername =>
      bind.mainGetLocalOption(key: kOptionLeapgateLastUsername);

  /// At startup: the stored user, the caches, the server's answer, then the others' pulls.
  Future<void> start() async {
    if (disabled) return;
    final local = _api.localUser();
    if (local == null) return;
    _user = local;
    notifyListeners();
    await Future.wait([for (final o in _others) o.loadCache()]);
    await refresh();
  }

  /// Whether the login dialog can reach the API server (M4-4).
  Future<ApiResult<void>> checkLoginOptions() => _api.loginOptions();

  /// On success the others pull; the dialog does not wait for them (upstream pulls after it
  /// closed).
  Future<ApiResult<AccountUser>> login(String username, String password) async {
    final result = await _api.login(username, password);
    if (result.ok) {
      _user = result.value;
      _error = null;
      await bind.mainSetLocalOption(
          key: kOptionLeapgateLastUsername, value: username);
      notifyListeners();
      _pullOthers();
    }
    return result;
  }

  /// Rust drops the token, `user_info` and both caches whatever the server said (M4-9); this
  /// resets the others as well.
  Future<void> logout() async {
    _signingOut = true;
    notifyListeners();
    await _api.logout();
    _signingOut = false;
    _signedOut();
  }

  /// Asks the server for the current user again ("retry" in the lists). A network or server
  /// error keeps the user and leaves the others as they are, as upstream's pulls return early
  /// on a network error.
  Future<void> refresh() async {
    if (!loggedIn || _checking) return;
    _checking = true;
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
    final result = await _api.currentUser();
    _checking = false;
    // Signed out meanwhile.
    if (!loggedIn) return;
    if (result.ok) {
      _user = result.value;
      notifyListeners();
      await _pullOthers();
    } else if (result.error!.kind == ApiErrorKind.unauthorized) {
      signedOutByServer();
    } else {
      _error = result.error;
      notifyListeners();
    }
  }

  /// Any call answered [ApiErrorKind.unauthorized]: Rust has already dropped the token; this
  /// signs out here and resets the others.
  void signedOutByServer() => _signedOut();

  void _signedOut() {
    _user = null;
    _error = null;
    for (final o in _others) {
      o.reset();
    }
    notifyListeners();
  }

  Future<void> _pullOthers() =>
      Future.wait([for (final o in _others) o.pull()]);
}
