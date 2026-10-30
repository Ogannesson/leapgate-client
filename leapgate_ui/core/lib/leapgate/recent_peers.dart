import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../models/peer_model.dart';
import '../models/platform_model.dart';

/// The "Recent" category (01 P1 block F): upstream's `Peers` fed by `load_recent_peers`, plus
/// whether the first load has arrived (the list shows "loading" until then) and which devices
/// have an online answer yet (until then a row shows "checking", not "offline").
class RecentPeers extends Peers {
  RecentPeers()
      : super(
            name: 'recent',
            loadEvent: 'load_recent_peers',
            getInitPeers: null) {
    // Run after `Peers`' own handlers, which registered first under [name].
    platformFFI.registerEventHandler(loadEvent, _handler, (evt) async {
      if (!loaded) {
        loaded = true;
        notifyListeners();
      }
    });
    platformFFI.registerEventHandler(_onlinesEvent, _handler, (evt) async {
      final before = _answered.length;
      for (final key in const ['onlines', 'offlines']) {
        _answered.addAll((evt[key] as String).split(','));
      }
      if (_answered.length != before) notifyListeners();
    });
  }

  static const _handler = 'recent-state';
  static const _onlinesEvent = 'callback_query_onlines';

  bool loaded = false;
  final _answered = <String>{};

  /// Whether an online query has answered for [id]; until then `Peer.online` means nothing.
  bool hasOnlineState(String id) => _answered.contains(id);

  /// Asks Rust to push the list again (it also does on every new connection,
  /// `FfiModel.handlePeerInfo`).
  void load() => bind.mainLoadRecentPeers();

  /// Rust answers with `callback_query_onlines`; feed it to an [OnlineQuery].
  void queryOnlines(List<String> ids) => bind.queryOnlines(ids: ids);

  @override
  void dispose() {
    platformFFI.unregisterEventHandler(loadEvent, _handler);
    platformFFI.unregisterEventHandler(_onlinesEvent, _handler);
    super.dispose();
  }
}

/// The name a device row shows: alias, else host name, else the formatted ID (01 P1 block F).
String peerDisplayName(Peer peer) => peer.alias.isNotEmpty
    ? peer.alias
    : peer.hostname.isNotEmpty
        ? peer.hostname
        : formatPeerId(peer.id);

/// `user@host` as a device row shows it; empty when both are unknown.
String peerUserHost(Peer peer) => peer.username.isEmpty && peer.hostname.isEmpty
    ? ''
    : '${peer.username}@${peer.hostname}';

/// A numeric ID in groups of three from the right, keeping a `/r` suffix; anything else as it
/// is (upstream `common/formatter/id_formatter.dart` `formatID`).
String formatPeerId(String id) {
  var digits = id.replaceAll(' ', '');
  var suffix = '';
  if (digits.endsWith(r'\r') || digits.endsWith('/r')) {
    suffix = digits.substring(digits.length - 2);
    digits = digits.substring(0, digits.length - 2);
  }
  if (int.tryParse(digits) == null) return id;
  final n = digits.length;
  final first = n % 3 != 0 ? n % 3 : 3;
  final groups = [
    digits.substring(0, first),
    for (var i = first; i < n; i += 3) digits.substring(i, i + 3),
  ];
  return groups.join(' ') + suffix;
}

/// Online state of the rows on screen, the way upstream's peer view asks
/// (`flutter/lib/common/widgets/peers_view.dart:313-346`): a changed set of rows is asked once
/// it has stood for a second, the same rows again every [interval] (6 s, upstream's value for a
/// self-hosted server) while the window is [active].
class OnlineQuery {
  OnlineQuery(this._query, {this.interval = const Duration(seconds: 6)});

  final void Function(List<String> ids) _query;
  final Duration interval;
  final _shown = <String>{};
  var _asked = <String>{};
  var _changedAt = clock.now();
  DateTime? _askedAt;
  Timer? _timer;

  /// False while the window is not focused or the list is not on screen.
  bool active = true;

  void start() => _timer =
      Timer.periodic(const Duration(milliseconds: 300), (_) => _tick());

  void dispose() => _timer?.cancel();

  void show(String id) {
    if (_shown.add(id)) _changedAt = clock.now();
  }

  void hide(String id) {
    if (_shown.remove(id)) _changedAt = clock.now();
  }

  void _tick() {
    final now = clock.now();
    if (!setEquals(_shown, _asked)) {
      if (now.difference(_changedAt) > const Duration(seconds: 1)) _ask(now);
    } else if (active &&
        _shown.isNotEmpty &&
        (_askedAt == null || now.difference(_askedAt!) >= interval)) {
      _ask(now);
    }
  }

  void _ask(DateTime now) {
    if (_shown.isNotEmpty) _query(_shown.toList(growable: false));
    _asked = {..._shown};
    _askedAt = now;
  }
}
