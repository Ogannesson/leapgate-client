import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/peer_list.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_device_parts.dart';
import '../../../widgets/lg_list_chrome.dart';
import '../account_category.dart';
import '../peer_views.dart';

// The address book (01 P1 blocks F and G, M4, coder B; `LEAPGATE.md` §10.11): the category
// itself, and its parts in the device menu, the selection bar, the cards and the connect box.

/// The book switcher, the tag bar, the tools and the states of the address book category.
AccountCategoryView addressBookCategory(
  BuildContext context,
  TabOverlays overlays,
) => const AccountCategoryView();

/// The connect box's devices (01 P1 block E): [sourced] (recent, favorites, LAN) followed by the
/// address book's and the team devices' devices that are not in it yet.
List<SourcedPeer> withAccountPeers(List<SourcedPeer> sourced) => sourced;

/// Whether the address book or the team devices have not loaded yet ("正在加载其他分类…").
bool accountPeersLoading() => false;

/// The tags a card or a list row shows: the address book's, in their colours; none elsewhere.
List<LgDeviceTag> abPeerTags(PeerItem item) => const [];

/// The key mark's tooltip when the shared book stores the device's password; null shows no key.
String? abPeerKeyLabel(AppLocalizations l10n, PeerItem item) => null;

/// The device menu's item for [action] where the address book has its own: the six address book
/// actions everywhere, and in the address book category whatever B takes over (rename changes
/// the book's alias, for one). Null keeps the page's own item.
Widget? abPeerMenuItem(
  AppLocalizations l10n,
  PeerItem item,
  PeerAction action, {
  required TabOverlays overlays,
}) => null;

/// The note beside the title of [group] in [groups] ("此地址簿为只读"): on the first group with a
/// greyed item only (01 P1 block F).
String? abMenuGroupNote(
  AppLocalizations l10n,
  PeerItem item,
  List<PeerAction> group,
  List<List<PeerAction>> groups,
) => null;

/// The selection bar's address book actions in [category]: "加入地址簿" while signed in, and in
/// the address book "编辑标签" and "从地址簿中删除". In the address book and the team devices
/// they are the only actions; elsewhere they follow the page's own. [done] shows a toast by its
/// ARB key and ends the selection.
List<LgSelectionAction> abSelectionActions(
  AppLocalizations l10n,
  PeerCategory category,
  Set<String> ids, {
  required TabOverlays overlays,
  required void Function(String toast) done,
}) => const [];
