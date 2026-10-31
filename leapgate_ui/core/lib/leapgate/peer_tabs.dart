import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../consts.dart';
import '../models/platform_model.dart';
import 'app_core.dart';
import 'options.dart';
import 'peer_list.dart';
import 'recent_peers.dart';
import 'ui_mode.dart';

/// LocalConfig, upstream's literal (`models/peer_tab_model.dart:43`): hides the LAN category.
const _kOptionDisableDiscoveryPanel = 'disable-discovery-panel';

enum PeerView { cards, list }

// `peer-card-ui-type` as upstream stores it (`common/widgets/peer_tab_page.dart` `PeerUiType`):
// 0 big tiles, 1 small tiles, 2 list. The new UI has cards (big tiles) and the list (small tiles
// and the list, which 01 P1 block F merges).
const _uiTypeCards = '0';
const _uiTypeList = '2';

// `peer-sorting` as upstream stores it (`common/widgets/peers_view.dart` `PeerSortType`), so both
// UIs read the same choice. "Name" takes the slot of upstream's "Remote Host", which it
// replaces (01 P1 block F).
const _sortValues = {
  PeerSort.id: 'Remote ID',
  PeerSort.name: 'Remote Host',
  PeerSort.username: 'Username',
  PeerSort.status: 'Status',
};

/// The category bar and list tools of the devices page (01 P1 block F): which categories show
/// and in what order, the selected one, the view and the sort order. Kept in the same Flutter
/// options as upstream's `PeerTabModel` (`models/peer_tab_model.dart`) and peer view, so the old
/// UI and this one share them.
class PeerTabs extends ChangeNotifier {
  PeerTabs(this._options) {
    final visible = _decode(kOptionPeerTabVisible);
    if (visible is List && visible.length == _count) {
      for (var i = 0; i < _count; i++) {
        if (visible[i] is bool) _visible[i] = visible[i];
      }
    }
    final order = _decode(kOptionPeerTabOrder);
    if (order is List &&
        order.length == _count &&
        (order.whereType<int>().toList()..sort()).join() ==
            List.generate(_count, (i) => i).join()) {
      _order.setAll(0, order.cast<int>());
    }
    final index = int.tryParse(_flutter.get(kOptionPeerTabIndex)) ?? 0;
    _current = PeerCategory.values[index.clamp(0, _count - 1)];
    _keepCurrentShown();
  }

  final OptionsModel _options;
  static final _count = PeerCategory.values.length;
  final _visible = List.filled(PeerCategory.values.length, true);
  final _order = List.generate(PeerCategory.values.length, (i) => i);
  late PeerCategory _current;

  OptionScope get _flutter => _options.flutter;

  dynamic _decode(String key) {
    try {
      final s = _flutter.get(key);
      return s.isEmpty ? null : jsonDecode(s);
    } on FormatException {
      return null;
    }
  }

  /// Whether this build has [category] at all. The address book and team devices come with M4;
  /// LAN unless the built-in option hides it (upstream `PeerTabModel.isEnabled`).
  bool isEnabled(PeerCategory category) => switch (category) {
        PeerCategory.recent || PeerCategory.favorites => true,
        PeerCategory.lan =>
          _options.local.get(_kOptionDisableDiscoveryPanel) != 'Y',
        _ => false,
      };

  /// The enabled categories in the user's order, shown or not: the list under "Adjust the
  /// categories shown and their order".
  List<PeerCategory> get ordered => [
        for (final i in _order)
          if (isEnabled(PeerCategory.values[i])) PeerCategory.values[i],
      ];

  /// The category bar.
  List<PeerCategory> get shown => [
        for (final c in ordered)
          if (_visible[c.index]) c,
      ];

  bool isVisible(PeerCategory category) => _visible[category.index];

  /// The selected category; when every category is hidden, the one last selected.
  PeerCategory get current => _current;

  void select(PeerCategory category) {
    if (_current == category) return;
    _current = category;
    _flutter.set(kOptionPeerTabIndex, '${category.index}');
    notifyListeners();
  }

  /// As upstream `setTabVisible`: hiding the selected category selects the first shown one,
  /// showing the only one selects it (both by [_keepCurrentShown]).
  void setVisible(PeerCategory category, bool visible) {
    if (_visible[category.index] == visible) return;
    _visible[category.index] = visible;
    _flutter.set(kOptionPeerTabVisible, jsonEncode(_visible));
    _keepCurrentShown();
    notifyListeners();
  }

  /// Moves [category] to [to] in [ordered]; the categories this build does not have keep their
  /// places in the stored order.
  void move(PeerCategory category, int to) {
    final list = ordered..remove(category);
    list.insert(to.clamp(0, list.length), category);
    var next = 0;
    for (var i = 0; i < _count; i++) {
      if (isEnabled(PeerCategory.values[_order[i]])) {
        _order[i] = list[next++].index;
      }
    }
    _flutter.set(kOptionPeerTabOrder, jsonEncode(_order));
    notifyListeners();
  }

  /// The selected category is one this build has, and a shown one while any is shown.
  void _keepCurrentShown() {
    if (!isEnabled(_current)) {
      _current = ordered.firstOrNull ?? PeerCategory.recent;
    }
    final s = shown;
    if (!s.contains(_current) && s.isNotEmpty) _current = s.first;
  }

  /// Cards or the list. Until the user picks one it follows the interface mode: the list in the
  /// detail mode, cards otherwise (01 §2.3). Upstream's small tiles are the list: 01 P1 block F
  /// merges them, as their content is nearly the same.
  PeerView get view => switch (_flutter.get(kOptionPeerCardUiType)) {
        '' => isDetailMode(_options.local) ? PeerView.list : PeerView.cards,
        _uiTypeCards => PeerView.cards,
        _ => PeerView.list,
      };

  void setView(PeerView view) {
    _flutter.set(kOptionPeerCardUiType,
        view == PeerView.list ? _uiTypeList : _uiTypeCards);
    notifyListeners();
  }

  /// ID when nothing (or something unknown) is stored, as upstream.
  PeerSort get sort {
    final v = _flutter.get(kOptionPeerSorting);
    return _sortValues.entries.where((e) => e.value == v).firstOrNull?.key ??
        PeerSort.id;
  }

  void setSort(PeerSort sort) {
    _flutter.set(kOptionPeerSorting, _sortValues[sort]!);
    notifyListeners();
  }

  /// Fixed by built-in settings: the menu item is greyed out with the reason (01 P1 block F).
  bool isFixed(String key) => _options.isFixed(key);
}

/// The categories' lists, in the order the connect box searches them (01 P1 block E).
List<CategoryPeers> get searchedCategories =>
    [appCore.recentPeers, appCore.favPeers, appCore.lanPeers];

CategoryPeers categoryPeers(PeerCategory category) => switch (category) {
      PeerCategory.favorites => appCore.favPeers,
      PeerCategory.lan => appCore.lanPeers,
      _ => appCore.recentPeers,
    };

/// Whether [id] is a favorite, as far as the loaded favorites tell: every favorite that has a
/// record or was found on the LAN is in them (`src/flutter_ffi.rs` `main_load_fav_peers`), and
/// only those are on the page.
bool isFavorite(String id) => appCore.favPeers.peers.any((p) => p.id == id);

// The device actions of the "⋯" menu and multiple selection, with upstream's calls
// (`common/widgets/peer_card.dart` `_addFavAction`, `_rmFavAction`, `_removeAction`,
// `_renameAction`, `_unrememberPasswordAction`, `_wolAction`, `_createShortCutAction`,
// `_forceAlwaysRelayAction`; `common/widgets/peer_tab_page.dart` `deleteSelection`,
// `addSelectionToFav`).

Future<void> addFavorites(Iterable<String> ids) async {
  final favs = (await bind.mainGetFav()).toList();
  for (final id in ids) {
    if (!favs.contains(id)) favs.add(id);
  }
  await bind.mainStoreFav(favs: favs);
  appCore.favPeers.load();
}

Future<void> removeFavorites(Iterable<String> ids) async {
  final favs = (await bind.mainGetFav()).toList();
  favs.removeWhere(ids.contains);
  await bind.mainStoreFav(favs: favs);
  appCore.favPeers.load();
}

/// "Delete" in "Recent", "Remove from favorites" in "Favorites", "Remove" on the LAN.
Future<void> deletePeers(PeerCategory category, Iterable<String> ids) async {
  switch (category) {
    case PeerCategory.recent:
      for (final id in ids) {
        await bind.mainRemovePeer(id: id);
      }
      appCore.recentPeers.load();
    case PeerCategory.favorites:
      await removeFavorites(ids);
    case PeerCategory.lan:
      for (final id in ids) {
        await bind.mainRemoveDiscovered(id: id);
      }
      appCore.lanPeers.load();
    case PeerCategory.addressBook || PeerCategory.group:
      break;
  }
}

/// The alias [id] has now (upstream `_getAlias`).
String peerAlias(String id) => appCore.options.peer(id).get('alias');

/// An empty [alias] removes it. Every category shows the alias, so the two with records reload.
Future<void> renamePeer(String id, String alias) async {
  await bind.mainSetPeerAlias(id: id, alias: alias);
  appCore.recentPeers.load();
  appCore.favPeers.load();
}

Future<bool> peerHasPassword(String id) => bind.mainPeerHasPassword(id: id);

Future<void> clearSavedPassword(String id) => bind.mainForgetPassword(id: id);

bool alwaysRelay(String id) =>
    appCore.options.peer(id).getBool(kOptionForceAlwaysRelay);

Future<bool> setAlwaysRelay(String id, bool value) =>
    appCore.options.peer(id).setBool(kOptionForceAlwaysRelay, value);

Future<void> wakeOnLan(String id) => bind.mainWol(id: id);

Future<void> createShortcut(String id) => bind.mainCreateShortcut(id: id);
