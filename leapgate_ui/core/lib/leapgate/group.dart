// 上游：flutter/lib/models/group_model.dart@bd9262397（改写：HTTP 和缓存的读写换成块 2 的导出；设备组去掉（01 区块 H、M4-6）；人员搜索和筛选从 common/widgets/my_group.dart、peers_view.dart 的 `MyGroupPeerView.filter` 并进来；在线状态照 `Peers._updateOnlineState`。上游这几段改了，合并时人工移植到这里）
import 'package:flutter/foundation.dart';

import '../models/peer_model.dart';
import '../models/platform_model.dart';
import 'account.dart';
import 'account_api.dart';
import 'app_core.dart';

/// The team devices category (01 P1 block H): the people who share devices with this user and
/// their devices.
class GroupModel extends ChangeNotifier implements AccountData {
  GroupModel(this._api) {
    // Every category takes the answer for all IDs (`CategoryPeers`); this one marks its own.
    platformFFI.registerEventHandler(
        'callback_query_onlines', 'group-online', (evt) async => _online(evt),
        replace: true);
  }

  final AccountApi _api;

  var _loaded = false;
  var _loading = false;
  ApiError? _error;
  var _users = <AccountUser>[];
  var _peers = <Peer>[];
  String? _selected;
  var _search = '';

  /// Hidden by the built-in `disable-group-panel` option.
  bool get disabled => bind.isDisableGroupPanel();

  /// Until the first answer or cache.
  bool get loaded => _loaded;
  bool get loading => _loading;

  /// Why the last pull failed; the list keeps what it had.
  ApiError? get error => _error;

  /// This user first.
  List<AccountUser> get users => _users;

  /// Every device of every person, with [Peer.online] kept up to date.
  List<Peer> get peers => _peers;

  /// The person picked in the list ([AccountUser.name]); null shows everyone's devices.
  String? get selectedUser => _selected;

  void selectUser(String? name) {
    if (_selected == name) return;
    _selected = name;
    notifyListeners();
  }

  /// The people list's search; typing clears the person picked (upstream `_buildLeftHeader`).
  String get search => _search;

  void setSearch(String text) {
    _search = text;
    _selected = null;
    notifyListeners();
  }

  /// The people the list shows: by user name or display name.
  List<AccountUser> get shownUsers {
    final text = _search.toLowerCase();
    return [
      for (final u in _users)
        if (_matches(u, text)) u,
    ];
  }

  /// What the category lists: the devices of [selectedUser], or of the people [search] finds.
  List<Peer> get shownPeers {
    final selected = _selected;
    if (selected != null) {
      return [
        for (final p in _peers)
          if (p.loginName == selected) p,
      ];
    }
    if (_search.isEmpty) return _peers;
    final names = {for (final u in shownUsers) u.name};
    return [
      for (final p in _peers)
        if (names.contains(p.loginName)) p,
    ];
  }

  /// The banner was closed.
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  @override
  Future<void> loadCache() async {
    if (disabled || _loaded) return;
    final cache = await _api.groupCache();
    if (cache == null || _loaded) return;
    _set(
      [
        for (final u in cache['users'] as List? ?? const [])
          AccountUser.fromJson(u as Map<String, dynamic>),
      ],
      [
        // `config::Group` keeps the owner as `login_name` (upstream `toGroupCacheJson`).
        for (final p in cache['peers'] as List? ?? const [])
          Peer.fromJson({
            ...p as Map<String, dynamic>,
            'loginName': p['login_name'] ?? '',
          }),
      ],
    );
    _loaded = true;
    notifyListeners();
  }

  @override
  Future<void> pull() async {
    if (disabled || _loading || !appCore.account.loggedIn) return;
    _loading = true;
    _error = null;
    notifyListeners();
    final result = await _api.group();
    _loading = false;
    if (result.ok) {
      _set(result.value.users, result.value.peers);
    } else if (result.error!.kind == ApiErrorKind.unauthorized) {
      appCore.account.signedOutByServer();
      return;
    } else {
      _error = result.error;
    }
    _loaded = true;
    notifyListeners();
  }

  @override
  void reset() {
    _loaded = false;
    _loading = false;
    _error = null;
    _users = [];
    _peers = [];
    _selected = null;
    _search = '';
    notifyListeners();
  }

  void _set(List<AccountUser> users, List<Peer> peers) {
    // Me first.
    final me = appCore.account.user?.name;
    _users = [
      ...users.where((u) => u.name == me),
      ...users.where((u) => u.name != me),
    ];
    if (!users.any((u) => u.name == _selected)) _selected = null;
    // Recover online.
    final online = {
      for (final p in _peers)
        if (p.online) p.id,
    };
    for (final p in peers) {
      p.online = online.contains(p.id);
    }
    _peers = peers;
  }

  void _online(Map<String, dynamic> evt) {
    final onlines = (evt['onlines'] as String).split(',').toSet();
    final offlines = (evt['offlines'] as String).split(',').toSet();
    var changed = false;
    for (final p in _peers) {
      final online = onlines.contains(p.id)
          ? true
          : offlines.contains(p.id)
              ? false
              : p.online;
      if (online != p.online) {
        p.online = online;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  static bool _matches(AccountUser u, String text) =>
      text.isEmpty ||
      u.name.toLowerCase().contains(text) ||
      u.displayNameOrName.toLowerCase().contains(text);
}
