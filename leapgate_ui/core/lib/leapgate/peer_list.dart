import 'dart:io';

import 'package:flutter/foundation.dart';

import '../consts.dart';
import '../models/peer_model.dart';
import 'recent_peers.dart';

/// A category shows at most this many devices and says so under the list (01 P1 block F);
/// upstream cut at the same number without a word (`common/widgets/peers_view.dart:238`).
const kMaxShownPeers = 1000;

/// The sort orders of 01 P1 block F. "Recent" is not sorted.
enum PeerSort { name, id, username, status }

/// [peers] in [sort] order; equal devices keep the order they came in.
///
/// Upstream sorted by status with `(p1, p2) => p1.online ? -1 : 1`
/// (`common/widgets/peers_view.dart:389-391`), which is not a comparator (it never says two
/// devices are equal, and says both a < b and b < a for two online ones), so devices in the same
/// state came out in no particular order and could swap on every refresh.
List<Peer> sortPeers(List<Peer> peers, PeerSort sort) {
  final int Function(Peer, Peer) compare = switch (sort) {
    PeerSort.name => (a, b) => peerDisplayName(a)
        .toLowerCase()
        .compareTo(peerDisplayName(b).toLowerCase()),
    PeerSort.id => (a, b) => a.id.compareTo(b.id),
    PeerSort.username => (a, b) =>
        a.username.toLowerCase().compareTo(b.username.toLowerCase()),
    PeerSort.status => (a, b) => (a.online ? 0 : 1) - (b.online ? 0 : 1),
  };
  final indexed = peers.indexed.toList()
    ..sort((a, b) {
      final c = compare(a.$2, b.$2);
      return c != 0 ? c : a.$1 - b.$1;
    });
  return [for (final (_, peer) in indexed) peer];
}

/// A device in the connect box results and the category it is listed under.
typedef SourcedPeer = ({Peer peer, PeerCategory source});

/// The devices the connect box searches (01 P1 block E): every category in the order given
/// (recent, favorites, LAN), each ID once, under the first category that has it.
List<SourcedPeer> searchablePeers(List<CategoryPeers> categories) {
  final seen = <String>{};
  return [
    for (final c in categories)
      for (final peer in c.peers)
        if (seen.add(peer.id)) (peer: peer, source: c.category),
  ];
}

/// What the "⋯" menu of a device offers (01 P1 block F).
enum PeerAction {
  remoteDesktop,
  // M7a: every device, as upstream's cards (`_transferFileAction`).
  fileTransfer,
  // M9 (`LEAPGATE.md` §10.18): the platform rules are [peerMenu]'s; the app builds the terminal
  // and camera items with M9b, the TCP tunnel and RDP items with M9c.
  terminal,
  terminalAdmin,
  camera,
  tcpTunnel,
  // M5: only when the remote device is on Windows (`libs/leapgate/src/exit/mod.rs`).
  useAsExit,
  rdp,
  viaRelay,
  alwaysRelay,
  wakeOnLan,
  createShortcut,
  rename,
  addFavorite,
  removeFavorite,
  clearPassword,
  delete,
  remove,
  // The address book's (M4, coder B; `LEAPGATE.md` §10.11): [peerMenu] offers them once B fills
  // in their conditions, the app builds them in `address_book.dart` `abPeerMenuItem`.
  addToAb,
  editTags,
  editNote,
  setSharedPassword,
  showBooks,
  deleteFromAb,
}

/// What the device menu needs from the address book (`AddressBookModel.menuFlags`): whether
/// there is a book to add the device to, whether the listed book is a shared one, and whether
/// it has tags.
typedef AbMenuFlags = ({bool addToAb, bool sharedBook, bool tags});

/// The "⋯" menu of a device in [category], by group: connection, device, manage, danger; a
/// group with nothing in it is left out. The conditions are upstream's
/// (`common/widgets/peer_card.dart:958-1100`, `RecentPeerCard`, `FavoritePeerCard`,
/// `DiscoveredPeerCard`) in 01's groups: the connection group has what M2b connects with,
/// "Favorites" has no danger group (01: "移出收藏" in the manage group does it), and every
/// category offers "加入地址簿" when there is a book to add to (M4). [peerPlatform] is the remote
/// device's (`kPeerPlatform*`, empty when not known), for the connection group (see
/// [connectMenu]); this one also has "终端（管理员）".
List<List<PeerAction>> peerMenu(
  PeerCategory category, {
  required bool favorite,
  required bool hasPassword,
  required bool windows,
  AbMenuFlags ab = (addToAb: false, sharedBook: false, tags: false),
  String peerPlatform = '',
}) {
  // [windows] is this device's platform (the shortcut, RDP); the rest is the remote device's.
  final connect = _connectGroup(peerPlatform, windows: windows, admin: true);
  // The address book and the team devices (01 P1 block F; upstream `AddressBookPeerCard`,
  // `MyGroupPeerCard`). A read-only book keeps its writing items, greyed by the app.
  if (category == PeerCategory.group) {
    return [
      connect,
      if (ab.addToAb) [PeerAction.addToAb],
    ];
  }
  if (category == PeerCategory.addressBook) {
    return [
      connect,
      [PeerAction.alwaysRelay, if (windows) PeerAction.createShortcut],
      [
        PeerAction.rename,
        favorite ? PeerAction.removeFavorite : PeerAction.addFavorite,
        if (ab.addToAb) PeerAction.addToAb,
        if (ab.tags) PeerAction.editTags,
        PeerAction.editNote,
        if (ab.sharedBook) PeerAction.setSharedPassword,
        if (hasPassword) PeerAction.clearPassword,
        PeerAction.showBooks,
      ],
      [PeerAction.deleteFromAb],
    ];
  }
  final groups = [
    connect,
    [
      PeerAction.alwaysRelay,
      if (category == PeerCategory.lan) PeerAction.wakeOnLan,
      if (windows) PeerAction.createShortcut,
    ],
    [
      if (category != PeerCategory.lan) PeerAction.rename,
      favorite ? PeerAction.removeFavorite : PeerAction.addFavorite,
      if (ab.addToAb) PeerAction.addToAb,
      if (category != PeerCategory.lan && hasPassword) PeerAction.clearPassword,
    ],
    [
      if (category == PeerCategory.recent) PeerAction.delete,
      if (category == PeerCategory.lan) PeerAction.remove,
    ],
  ];
  return [
    for (final g in groups)
      if (g.isNotEmpty) g,
  ];
}

/// The "连接" button's menu and the "⋯" after "连接到 ‹输入›" (`A-P1.html#p1-cb-menu`): the
/// connection types for a remote device on [peerPlatform] (`kPeerPlatform*`, empty when not
/// known, as for typed text), in the mockup's order, without "终端（管理员）" (14 §1.2).
/// [windows] is this device's platform, for RDP; tests pass it.
List<PeerAction> connectMenu(String peerPlatform, {bool? windows}) =>
    _connectGroup(peerPlatform, windows: windows ?? Platform.isWindows, admin: false);

/// The connection types in `p1-menu-more-top`'s order. What the remote platform is known not
/// to support is left out, an unknown platform offers all (R3-Q12, 01 §3.1 block F): the
/// terminal and the TCP tunnel not on Android, the administrator terminal only on Windows
/// (13 §2.1.1), the camera not on macOS or Android, the exit node not on a known non-Windows
/// (M5), RDP from Windows to a device not known to be another platform (13 §1.1.2).
List<PeerAction> _connectGroup(String peerPlatform,
    {required bool windows, required bool admin}) {
  final android = peerPlatform == kPeerPlatformAndroid;
  final peerWindows = peerPlatform == kPeerPlatformWindows;
  final notWindows = peerPlatform.isNotEmpty && !peerWindows;
  return [
    PeerAction.remoteDesktop,
    PeerAction.fileTransfer,
    if (!android) PeerAction.terminal,
    if (admin && peerWindows) PeerAction.terminalAdmin,
    if (!android && peerPlatform != kPeerPlatformMacOS) PeerAction.camera,
    if (!android) PeerAction.tcpTunnel,
    if (!notWindows) PeerAction.useAsExit,
    if (windows && !notWindows) PeerAction.rdp,
    PeerAction.viaRelay,
  ];
}

/// The devices picked in multiple selection (01 P1 block F, upstream
/// `models/peer_tab_model.dart` `select`, `selectAll`).
class PeerSelection extends ChangeNotifier {
  bool _active = false;
  final _ids = <String>{};
  String? _last;

  bool get active => _active;
  Set<String> get ids => Set.unmodifiable(_ids);

  bool contains(String id) => _ids.contains(id);

  void start() {
    _active = true;
    notifyListeners();
  }

  /// "Done", and after the selection was acted on.
  void finish() {
    _active = false;
    _ids.clear();
    _last = null;
    notifyListeners();
  }

  /// A click on [id] in [shown]. With Shift, the run from the last clicked device to this one
  /// takes this device's new state; otherwise this device flips.
  void tap(String id, List<String> shown, {bool shift = false}) {
    final at = shown.indexOf(id);
    final from = _last == null ? -1 : shown.indexOf(_last!);
    if (shift && at >= 0 && from >= 0) {
      final select = !_ids.contains(id);
      final (lo, hi) = at < from ? (at, from) : (from, at);
      for (final i in shown.sublist(lo, hi + 1)) {
        select ? _ids.add(i) : _ids.remove(i);
      }
    } else if (!_ids.remove(id)) {
      _ids.add(id);
    }
    _last = id;
    notifyListeners();
  }

  void selectAll(List<String> shown) {
    _ids.addAll(shown);
    notifyListeners();
  }
}
