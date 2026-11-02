// 上游：flutter/lib/models/ab_model.dart@bd9262397（改写：HTTP 换成 H1 的导出，`LegacyAb` 不要（IQ8），`Get`、`BotToast`、`translate` 去掉，状态改成 ChangeNotifier；`AddressBookPeersView._hitTag` 从 common/widgets/peers_view.dart 搬来）
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../consts.dart';
import '../models/peer_model.dart';
import '../models/platform_model.dart';
import 'account.dart';
import 'account_api.dart';
import 'app_core.dart';
import 'peer_list.dart';
import 'recent_peers.dart';

/// The personal book's name where upstream stores one: the `current-ab-name` option and the
/// cache Rust reads the stored passwords from (`AbEntry::personal()`, 07 §4.2).
const kAbPersonalName = 'My address book';

/// The tag filter's "untagged" entry (upstream `kUntagged`); no real tag may take this name.
const kAbUntagged = 'Untagged';

/// The device menu's items that write the listed book: greyed in a read-only book (01 P1 block
/// F).
const kAbWriteActions = {
  PeerAction.rename,
  PeerAction.editTags,
  PeerAction.editNote,
  PeerAction.setSharedPassword,
  PeerAction.deleteFromAb,
};

/// Whether a device with [tags] passes the filter [selected] (upstream
/// `AddressBookPeersView._hitTag`): untagged devices with [kAbUntagged], and with the other
/// tags any of them or, with [intersection], all of them.
bool abTagFilter(Set<String> selected, List<dynamic> tags,
    {required bool intersection}) {
  if (selected.isEmpty) return true;
  final normal = selected.where((t) => t != kAbUntagged);
  if (selected.contains(kAbUntagged)) {
    if (tags.isEmpty) return true;
    if (normal.isEmpty) return false;
  }
  return intersection ? normal.every(tags.contains) : normal.any(tags.contains);
}

class _Book {
  var peers = <Peer>[];
  var tags = <AbTag>[];

  /// Answered by the server at least once (the cache does not count).
  bool initialized = false;
  bool loading = false;
  final selectedTags = <String>{};
}

/// The address book category (01 P1 block G): the personal book and the shared ones, the
/// current book's devices and tags.
class AddressBookModel extends ChangeNotifier implements AccountData {
  AddressBookModel(this._api) {
    platformFFI.registerEventHandler(_onlinesEvent, _handler, _onOnlines,
        replace: true);
  }

  final AccountApi _api;

  static const _onlinesEvent = 'callback_query_onlines';
  static const _handler = 'ab-state';

  var _books = <AbProfile>[];
  String _personalGuid = '';
  int _maxPeers = 0;
  final _data = <String, _Book>{};
  String? _currentGuid;
  bool _loaded = false;
  bool _pulling = false;
  bool _unsupported = false;
  ApiError? _pullError;
  ApiError? _pushError;

  // "与最近会话同步" (upstream `_syncFromRecent`): every 3 s while the option is on.
  Timer? _syncTimer;
  bool _syncAll = true;
  bool _syncing = false;

  /// Hidden by the built-in `disable-ab` option.
  bool get disabled => bind.isDisableAb();

  /// Until the first answer or cache.
  bool get loaded => _loaded;

  /// The book list or the current book is on its way.
  bool get loading => _pulling || (_current?.loading ?? false);

  /// The server has no address book (`ab/personal` 404, 07 §4.4).
  bool get unsupported => _unsupported;

  /// Why the last pull failed; the list keeps what it had.
  ApiError? get pullError => _pullError;

  /// Why the last change to a book failed ("无法保存地址簿的更改"), until [dismissErrors].
  ApiError? get pushError => _pushError;

  /// The personal book first, then the shared ones by name.
  List<AbProfile> get books => _books;

  /// Null until the list arrives.
  AbProfile? get current =>
      _books.where((b) => b.guid == _currentGuid).firstOrNull;

  _Book? get _current => _data[_currentGuid];

  bool isPersonal(AbProfile book) => book.guid == _personalGuid;

  /// The current book has answered; before that the list shows its cache or the loading state.
  bool get currentInitialized => _current?.initialized ?? false;

  /// The current book's devices, with [Peer.online] kept up to date.
  List<Peer> get peers => _current?.peers ?? const [];

  /// The current book's tags, by name when the `sync-ab-tags` option asks for it.
  List<AbTag> get tags {
    final tags = _current?.tags ?? const <AbTag>[];
    if (bind.mainGetLocalOption(key: sortAbTagsOption) != 'Y') return tags;
    return [...tags]..sort((a, b) => a.name.compareTo(b.name));
  }

  /// The colour of [tag] in the current book, null when it has none.
  int? tagColor(String tag) =>
      _current?.tags.where((t) => t.name == tag).firstOrNull?.color;

  Set<String> get selectedTags => _current?.selectedTags ?? const {};

  bool get filterByIntersection =>
      bind.mainGetLocalOption(key: filterAbTagOption) == 'Y';

  bool get syncWithRecent => bind.mainGetLocalOption(key: syncAbOption) == 'Y';

  /// What the category lists: [peers] through the tag filter.
  List<Peer> get shownPeers {
    final selected = selectedTags;
    final intersection = filterByIntersection;
    return [
      for (final p in peers)
        if (abTagFilter(selected, p.tags, intersection: intersection)) p,
    ];
  }

  /// Every loaded book's devices, each ID once, the current book's first, for the connect box
  /// (01 P1 block E).
  List<Peer> get allPeers {
    final seen = <String>{};
    return [
      for (final b in [_current, ..._data.values])
        for (final p in b?.peers ?? const <Peer>[])
          if (seen.add(p.id)) p,
    ];
  }

  bool canWriteBook(AbProfile book) =>
      isPersonal(book) ||
      book.rule == ShareRule.readWrite.value ||
      book.rule == ShareRule.fullControl.value;

  bool get canWrite => current != null && canWriteBook(current!);

  /// The books "Add to address book" offers.
  List<AbProfile> get writableBooks => [
        for (final b in _books)
          if (canWriteBook(b)) b,
      ];

  /// [book] holds as many devices as the server allows.
  bool isFull(AbProfile book) =>
      _maxPeers > 0 && (_data[book.guid]?.peers.length ?? 0) >= _maxPeers;

  /// Whether [id] is in [book] as far as it is loaded.
  bool contains(AbProfile book, String id) =>
      _data[book.guid]?.peers.any((p) => p.id == id) ?? false;

  /// The loaded books that hold [id] (upstream `idExistIn`).
  List<AbProfile> idExistIn(String id) => [
        for (final b in _books)
          if (contains(b, id)) b,
      ];

  /// The books a device listed in [category] can be added to: the writable ones, but not the
  /// one it is listed in.
  List<AbProfile> addTargets(PeerCategory category) => [
        for (final b in writableBooks)
          if (category != PeerCategory.addressBook || b.guid != _currentGuid) b,
      ];

  AbMenuFlags menuFlags(PeerCategory category) => (
        addToAb: addTargets(category).isNotEmpty,
        sharedBook: current != null && !isPersonal(current!),
        tags: _current?.tags.isNotEmpty ?? false,
      );

  /// Whether [action] in the address book category's menu is greyed: it writes a read-only book.
  bool greyed(PeerAction action) =>
      !canWrite && kAbWriteActions.contains(action);

  /// The shared password of [id] in the current shared book, to connect with; null in the
  /// personal book or when none is stored (upstream `connectInPeerTab`).
  String? sharedPasswordOf(String id) {
    final book = current;
    if (book == null || isPersonal(book)) return null;
    final password = peers.where((p) => p.id == id).firstOrNull?.password ?? '';
    return password.isEmpty ? null : password;
  }

  // ---- Pulling (upstream `pullAb`, `_pullAb`, `Ab.pullAbImpl`).

  /// Who an answer was asked for: an answer that comes back after a sign-out, or after another
  /// user signed in, is dropped (the model was reset meanwhile).
  String? get _me => appCore.account.user?.name;

  @override
  Future<void> loadCache() async {
    if (_loaded || _pulling || disabled) return;
    final me = _me;
    final entries = await _api.abCache();
    if (_me != me || _loaded || _pulling || entries.isEmpty) return;
    _books = [];
    _data.clear();
    for (final e in entries) {
      final guid = e['guid'] as String?;
      final name = e['name'] as String?;
      if (guid == null || name == null) continue;
      if (name == kAbPersonalName) {
        _personalGuid = guid;
        _books.insert(0, AbProfile(guid: guid, name: name));
      } else {
        // The cache keeps no rule: read-only until the server answers.
        _books
            .add(AbProfile(guid: guid, name: name, rule: ShareRule.read.value));
      }
      final colors = e['tag_colors'] is String
          ? Map<String, dynamic>.from(jsonDecode(e['tag_colors']) as Map)
          : const <String, dynamic>{};
      // A tag without a colour takes upstream's default (`getCurrentAbTagColor`).
      final existing = [
        for (final c in colors.values)
          if (c is int) c
      ];
      _data[guid] = _Book()
        ..peers = [
          for (final p in e['peers'] as List? ?? const [])
            Peer.fromJson(p as Map<String, dynamic>),
        ]
        ..tags = [
          for (final t in e['tags'] as List? ?? const [])
            AbTag(
                t.toString(),
                colors[t] as int? ??
                    abDefaultTagColor(t.toString(), existing: existing)),
        ];
    }
    _currentGuid = _lastBook() ?? _books.firstOrNull?.guid;
    _loaded = true;
    notifyListeners();
  }

  /// The book the user had open last time (upstream `trySetCurrentToLast`).
  String? _lastBook() {
    final name = bind.getLocalFlutterOption(k: kOptionCurrentAbName);
    return _books.where((b) => b.name == name).firstOrNull?.guid;
  }

  @override
  Future<void> pull() async {
    if (_pulling || disabled) return;
    _pulling = true;
    _pullError = null;
    notifyListeners();
    final me = _me;
    final r = await _api.books();
    if (_me != me) return;
    if (r.ok) {
      final b = r.value;
      _unsupported = false;
      _maxPeers = b.maxPeers;
      _personalGuid = b.personal;
      final shared = [...b.shared]
        ..sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()));
      // A reset, and the next pull, put a new list in place: this round is over then.
      final books = _books = [
        AbProfile(guid: b.personal, name: kAbPersonalName),
        ...shared
      ];
      bool over() => _me != me || !identical(_books, books);
      _data.removeWhere((guid, _) => !_books.any((x) => x.guid == guid));
      if (current == null) {
        _currentGuid = _lastBook() ?? b.personal;
      }
      final current_ = current!;
      await _pullBook(current_, quiet: false);
      if (over()) return;
      if (!isPersonal(current_)) {
        final personal = _books.where(isPersonal).firstOrNull;
        if (personal != null && !(_data[personal.guid]?.initialized ?? false)) {
          await _pullBook(personal, quiet: true);
          if (over()) return;
        }
      }
      _startSync();
    } else if (r.error!.kind == ApiErrorKind.unsupported) {
      _unsupported = true;
    } else if (!_failed(r.error!)) {
      return;
    }
    _pulling = false;
    _loaded = true;
    notifyListeners();
  }

  /// Records [error] of a pull; false when it signed out (the model is reset).
  bool _failed(ApiError error) {
    if (error.kind == ApiErrorKind.unauthorized) {
      appCore.account.signedOutByServer();
      return false;
    }
    _pullError = error;
    return true;
  }

  /// [quiet] after a change, as upstream: a failure leaves the list as it was, unseen.
  Future<void> _pullBook(AbProfile book, {required bool quiet}) async {
    final data = _data.putIfAbsent(book.guid, _Book.new);
    if (data.loading) return;
    data.loading = true;
    if (!quiet) notifyListeners();
    final personal = isPersonal(book);
    final r = await _api.book(book.guid,
        name: personal ? kAbPersonalName : book.name, personal: personal);
    data.loading = false;
    if (!identical(_data[book.guid], data)) return; // Reset meanwhile.
    if (r.ok) {
      final online = {
        for (final p in data.peers)
          if (p.online) p.id
      };
      data.peers = [
        for (final p in r.value.peers) p..online = online.contains(p.id),
      ];
      data.tags = r.value.tags;
      final names = {kAbUntagged, for (final t in data.tags) t.name};
      data.selectedTags.retainWhere(names.contains);
      data.initialized = true;
    } else if (r.error!.kind == ApiErrorKind.unauthorized) {
      appCore.account.signedOutByServer();
      return;
    } else if (!quiet && book.guid == _currentGuid) {
      // A book left meanwhile does not put its failure over the one shown.
      _pullError = r.error;
    }
    notifyListeners();
  }

  /// The book switcher (upstream `setCurrentName`).
  Future<void> select(AbProfile book) async {
    if (book.guid == _currentGuid) return;
    _currentGuid = book.guid;
    _syncAll = true;
    await bind.setLocalFlutterOption(k: kOptionCurrentAbName, v: book.name);
    notifyListeners();
    if (!(_data[book.guid]?.initialized ?? false)) {
      _pullError = null;
      await _pullBook(book, quiet: false);
    }
  }

  @override
  void reset() {
    _books = [];
    _personalGuid = '';
    _maxPeers = 0;
    _data.clear();
    _currentGuid = null;
    _loaded = false;
    _pulling = false;
    _unsupported = false;
    _pullError = null;
    _pushError = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _syncAll = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    platformFFI.unregisterEventHandler(_onlinesEvent, _handler);
    super.dispose();
  }

  Future<void> _onOnlines(Map<String, dynamic> evt) async {
    final onlines = (evt['onlines'] as String).split(',').toSet();
    final offlines = (evt['offlines'] as String).split(',').toSet();
    var changed = false;
    for (final b in _data.values) {
      for (final p in b.peers) {
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
    }
    if (changed) notifyListeners();
  }

  // ---- The tag filter.

  void toggleTag(String tag) {
    final selected = _current?.selectedTags;
    if (selected == null) return;
    if (!selected.remove(tag)) selected.add(tag);
    notifyListeners();
  }

  void unselectAllTags() {
    _current?.selectedTags.clear();
    notifyListeners();
  }

  Future<void> setFilterByIntersection(bool v) async {
    await bind.mainSetLocalOption(key: filterAbTagOption, value: v ? 'Y' : '');
    notifyListeners();
  }

  void dismissErrors() {
    _pullError = null;
    _pushError = null;
    notifyListeners();
  }

  /// Shows [error] of a change made outside a dialog in the banner.
  void pushFailed(ApiError error) {
    _pushError = error;
    notifyListeners();
  }

  // ---- Changes. Each returns why it failed, null when it went through; the book is pulled
  // again quietly afterwards, as upstream (`pullNonLegacyAfterChange`), which also rewrites the
  // cache Rust keeps.

  /// [call] for each of [items] in turn, stopping at the first error; [local] applies each one
  /// that went through to the list at once.
  Future<ApiError?> _writeEach<T>(
    AbProfile book,
    Iterable<T> items,
    Future<ApiResult<void>> Function(T item) call,
    void Function(_Book data, T item) local,
  ) async {
    // Pulled again whether it went through or not, as upstream: a device or tag someone else
    // removed (`not_found`) leaves the list too.
    var called = false;
    final me = _me;
    for (final item in items) {
      called = true;
      final r = await call(item);
      if (_me != me) return null;
      if (!r.ok) {
        if (r.error!.kind == ApiErrorKind.unauthorized) {
          appCore.account.signedOutByServer();
          return r.error;
        }
        // Unreachable server: a second request would only wait out another timeout.
        if (r.error!.kind != ApiErrorKind.network) {
          await _pullBook(book, quiet: true);
        }
        return r.error;
      }
      final data = _data[book.guid];
      if (data != null) local(data, item);
      notifyListeners();
    }
    if (called) await _pullBook(book, quiet: true);
    return null;
  }

  Future<ApiError?> _write(
          AbProfile book, Future<ApiResult<void>> Function() call,
          [void Function(_Book data)? local]) =>
      _writeEach(book, const [0], (_) => call(), (d, _) => local?.call(d));

  Peer? _peer(_Book data, String id) =>
      data.peers.where((p) => p.id == id).firstOrNull;

  /// "Add device" into the current book (upstream `addIdToCurrent`). The caller has checked
  /// [isFull] and that [id] is not in it yet.
  Future<ApiError?> addDevice({
    required String id,
    String alias = '',
    String password = '',
    String note = '',
    List<String> tags = const [],
  }) {
    final book = current;
    // Signed out while a confirmation was open: nothing to change any more.
    if (book == null) return Future.value();
    _syncAll = true;
    final peer = {
      'id': id,
      'alias': alias,
      'tags': tags,
      // Upstream sends neither when empty, so an existing value is not cleared.
      if (password.isNotEmpty && !isPersonal(book)) 'password': password,
      if (note.isNotEmpty) 'note': note,
    };
    return _write(book, () => _api.addPeer(book.guid, peer),
        (d) => d.peers.add(Peer.fromJson(peer)));
  }

  /// "Add to address book" (upstream `addPeersToAbDialog`, `addPeersTo`): one by one, stopping at
  /// the first error; devices already in [book] are skipped. Their passwords are not shared
  /// into it, and only the tags [book] has go along.
  Future<ApiError?> addPeersTo(AbProfile book, List<Peer> peers) {
    final tags = {
      for (final t in _data[book.guid]?.tags ?? const <AbTag>[]) t.name
    };
    _syncAll = true;
    return _writeEach(
      book,
      [
        for (final p in peers)
          if (!contains(book, p.id))
            p.toJson()
              ..remove('password')
              ..remove('hash')
              ..['tags'] = [
                for (final t in p.tags)
                  if (tags.contains(t)) t
              ],
      ],
      (json) => _api.addPeer(book.guid, json),
      (d, json) => d.peers.add(Peer.fromJson(json)),
    );
  }

  Future<ApiError?> setTags(List<String> ids, List<String> tags) {
    final book = current;
    // Signed out while a confirmation was open: nothing to change any more.
    if (book == null) return Future.value();
    return _writeEach(
        book,
        ids,
        (id) => _api.updatePeer(book.guid, id, {'tags': tags}),
        (d, id) => _peer(d, id)?.tags = [...tags]);
  }

  /// "Rename" in the address book: the book's alias, and the device's own as upstream does.
  Future<ApiError?> setAlias(String id, String alias) async {
    final book = current;
    // Signed out while a confirmation was open: nothing to change any more.
    if (book == null) return Future.value();
    final error = await _write(
        book,
        () => _api.updatePeer(book.guid, id, {'alias': alias}),
        (d) => _peer(d, id)?.alias = alias);
    if (error == null) await bind.mainSetPeerAlias(id: id, alias: alias);
    return error;
  }

  Future<ApiError?> setNote(String id, String note) {
    final book = current;
    // Signed out while a confirmation was open: nothing to change any more.
    if (book == null) return Future.value();
    return _write(book, () => _api.updatePeer(book.guid, id, {'note': note}),
        (d) => _peer(d, id)?.note = note);
  }

  Future<ApiError?> setSharedPassword(String id, String password) {
    final book = current;
    // Signed out while a confirmation was open: nothing to change any more.
    if (book == null) return Future.value();
    return _write(
        book,
        () => _api.updatePeer(book.guid, id, {'password': password}),
        (d) => _peer(d, id)?.password = password);
  }

  /// "Clear saved password" in the personal book: the book's hash and this device's copy
  /// (upstream `_unrememberPasswordAction`).
  Future<ApiError?> clearPassword(String id) async {
    final error = await _setHash(id, '');
    await bind.mainForgetPassword(id: id);
    return error;
  }

  Future<ApiError?> _setHash(String id, String hash) async {
    final personal = _books.where(isPersonal).firstOrNull;
    if (personal == null || !contains(personal, id)) return null;
    return _write(
        personal,
        () => _api.updatePeer(personal.guid, id, {'hash': hash}),
        (d) => _peer(d, id)?.hash = hash);
  }

  /// Rust's `sync_peer_hash_password_to_personal_ab`: stores [hash] for [id] in the personal book
  /// when [id] is in it (upstream `changePersonalHashPassword`).
  Future<void> syncPeerHash(String id, String hash) async {
    await _setHash(id, hash);
  }

  Future<ApiError?> deletePeers(List<String> ids) {
    final book = current;
    // Signed out while a confirmation was open: nothing to change any more.
    if (book == null) return Future.value();
    return _write(book, () => _api.deletePeers(book.guid, ids),
        (d) => d.peers.removeWhere((p) => ids.contains(p.id)));
  }

  /// "Add tag": [names] one by one with upstream's colours (`str2color2`), stopping at the first
  /// error.
  Future<ApiError?> addTags(List<String> names) {
    final book = current;
    // Signed out while a confirmation was open: nothing to change any more.
    if (book == null) return Future.value();
    final colors = [for (final t in _current?.tags ?? const <AbTag>[]) t.color];
    final tags = [
      for (final name in names)
        AbTag(name, abDefaultTagColor(name, existing: colors)),
    ];
    return _writeEach(
        book,
        tags,
        (t) => _api.addTag(book.guid, t.name, t.color),
        (d, t) => d.tags.add(t));
  }

  Future<ApiError?> renameTag(String oldName, String newName) {
    final book = current;
    // Signed out while a confirmation was open: nothing to change any more.
    if (book == null) return Future.value();
    return _write(book, () => _api.renameTag(book.guid, oldName, newName), (d) {
      d.tags = [
        for (final t in d.tags) t.name == oldName ? AbTag(newName, t.color) : t,
      ];
      for (final p in d.peers) {
        p.tags = [for (final t in p.tags) t == oldName ? newName : t];
      }
      if (d.selectedTags.remove(oldName)) d.selectedTags.add(newName);
    });
  }

  Future<ApiError?> setTagColor(String name, int color) {
    final book = current;
    // Signed out while a confirmation was open: nothing to change any more.
    if (book == null) return Future.value();
    return _write(book, () => _api.setTagColor(book.guid, name, color), (d) {
      d.tags = [
        for (final t in d.tags) t.name == name ? AbTag(name, color) : t
      ];
    });
  }

  Future<ApiError?> deleteTag(String name) {
    final book = current;
    // Signed out while a confirmation was open: nothing to change any more.
    if (book == null) return Future.value();
    return _write(book, () => _api.deleteTags(book.guid, [name]), (d) {
      d.tags.removeWhere((t) => t.name == name);
      for (final p in d.peers) {
        p.tags = [
          for (final t in p.tags)
            if (t != name) t
        ];
      }
      d.selectedTags.remove(name);
    });
  }

  // ---- "与最近会话同步" (upstream `_syncFromRecent`, `Ab.syncFromRecent`).

  Future<void> setSyncWithRecent(bool v) async {
    await bind.mainSetLocalOption(key: syncAbOption, value: v ? 'Y' : '');
    _syncAll = true;
    _syncTimer?.cancel();
    _syncTimer = null;
    _startSync();
    notifyListeners();
  }

  void _startSync() {
    if (_syncTimer != null || !syncWithRecent || _books.isEmpty) return;
    _syncTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => syncFromRecent());
  }

  /// One round of the timer: the recent sessions' user name, host name and platform (unless the
  /// device is on the same server) and, in the personal book, the password hash, written to the
  /// current book's devices that differ. New devices are not added.
  Future<void> syncFromRecent() async {
    final book = current;
    final data = _current;
    if (_syncing ||
        !syncWithRecent ||
        book == null ||
        data == null ||
        !data.initialized ||
        !canWrite) {
      return;
    }
    _syncing = true;
    try {
      await _syncFrom(_me, book, data, await _recentPeers());
    } finally {
      _syncing = false;
    }
  }

  Future<List<Peer>> _recentPeers() async {
    List<String> ids;
    if (_syncAll) {
      _syncAll = false;
      ids = [];
    } else {
      final stored = await bind.mainGetNewStoredPeers();
      if (stored.isEmpty) return [];
      ids = [for (final id in jsonDecode(stored) as List) id.toString()];
      if (ids.isEmpty) return [];
    }
    final loaded = await bind.mainLoadRecentPeersForAb(filter: jsonEncode(ids));
    if (loaded.isEmpty) return [];
    return [
      for (final m in jsonDecode(loaded) as List)
        if (m is Map<String, dynamic>) Peer.fromJson(m),
    ];
  }

  /// [me] is who the round started for; it stops once someone else is signed in.
  Future<void> _syncFrom(
      String? me, AbProfile book, _Book data, List<Peer> recents) async {
    var hashChanged = false;
    for (final p in [...data.peers]) {
      final r = recents.where((r) => r.id == p.id).firstOrNull;
      if (r == null) continue;
      final fields = abSyncFields(p, r, personal: isPersonal(book));
      if (fields.isEmpty || _me != me) continue;
      final result = await _api.updatePeer(book.guid, p.id, fields);
      if (_me != me) return;
      if (!result.ok) {
        if (result.error!.kind == ApiErrorKind.unauthorized) {
          appCore.account.signedOutByServer();
          return;
        }
        continue;
      }
      p
        ..username = fields['username'] ?? p.username
        ..hostname = fields['hostname'] ?? p.hostname
        ..platform = fields['platform'] ?? p.platform
        ..hash = fields['hash'] ?? p.hash;
      hashChanged |= fields.containsKey('hash');
      notifyListeners();
    }
    // Upstream saved the cache here; the quiet pull makes Rust rewrite it.
    if (hashChanged) await _pullBook(book, quiet: true);
  }
}

/// What "与最近会话同步" writes to [p] from the recent session [r] (upstream
/// `Ab.syncFromRecent.trySyncOnePeer`): the user name, host name and platform when [p] is not on
/// this server and [r] knows them, and in the personal book the password hash.
Map<String, String> abSyncFields(Peer p, Peer r, {required bool personal}) {
  final other = p.sameServer != true;
  return {
    if (other && r.username.isNotEmpty && p.username != r.username)
      'username': r.username,
    if (other && r.hostname.isNotEmpty && p.hostname != r.hostname)
      'hostname': r.hostname,
    if (other && r.platform.isNotEmpty && p.platform != r.platform)
      'platform': r.platform,
    if (personal && r.hash.isNotEmpty && p.hash != r.hash) 'hash': r.hash,
  };
}

/// A new tag's colour (upstream `str2color2` in `common.dart`): Material colours as ARGB, picked
/// by name or by the name's code units, avoiding the colours [existing] tags already have.
int abDefaultTagColor(String name, {List<int> existing = const []}) {
  const named = {
    'red': 0xFFF44336,
    'green': 0xFF4CAF50,
    'blue': 0xFF2196F3,
    'orange': 0xFFFF9800,
    'purple': 0xFF9C27B0,
    'grey': 0xFF9E9E9E,
    'cyan': 0xFF00BCD4,
    'lime': 0xFFCDDC39,
    'teal': 0xFF009688,
    'pink': 0xFFF48FB1,
    'indigo': 0xFF3F51B5,
    'brown': 0xFF795548,
  };
  final lower = name.toLowerCase();
  if (named[lower] != null) return named[lower]!;
  if (lower == 'yellow') return 0xFFFFEB3B;
  final colors = named.values.toList();
  var hash = 0;
  for (final c in name.codeUnits) {
    hash += c;
  }
  final color = colors[hash % colors.length];
  if (!existing.contains(color)) return color;
  return colors.where((c) => !existing.contains(c)).firstOrNull ?? color;
}
