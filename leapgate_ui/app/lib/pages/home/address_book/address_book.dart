import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/peer_list.dart';
import 'package:flutter_hbb/leapgate/peer_tabs.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_device.dart';
import '../../../widgets/lg_device_parts.dart';
import '../../../widgets/lg_list_chrome.dart';
import '../../../widgets/lg_menu.dart';
import '../../../widgets/lg_menu_items.dart';
import '../account/account.dart';
import '../account_category.dart';
import '../home_dialogs.dart';
import '../peer_views.dart';
import 'ab_dialogs.dart';
import 'ab_parts.dart';

// The address book (01 P1 blocks F and G, M4, coder B; `LEAPGATE.md` §10.11): the category
// itself, and its parts in the device menu, the selection bar, the cards and the connect box.
// Rewritten after upstream `common/widgets/address_book.dart` and the address book parts of
// `common/widgets/peer_card.dart` (`AddressBookPeerCard`, `_addToAb`) and
// `common/widgets/peer_tab_page.dart` (the selection bar).

/// The book switcher, the tag bar, the tools and the states of the address book category.
AccountCategoryView addressBookCategory(
  BuildContext context,
  TabOverlays overlays,
) {
  final l10n = AppLocalizations.of(context)!;
  final account = appCore.account;
  final ab = appCore.addressBook;
  if (!account.loggedIn) {
    return AccountCategoryView(
      state: AbStateWithAction(
        text: l10n.abSignedOut,
        icon: LgIcons.book,
        action: l10n.abSignIn,
        onPressed: () => showLoginDialog(overlays),
      ),
    );
  }
  if (ab.unsupported) {
    return AccountCategoryView(
      state: SingleChildScrollView(
        child: LgEmptyState(l10n.abUnsupported, icon: LgIcons.book),
      ),
    );
  }
  // A failed check of the sign-in leaves the address book as cached; retrying asks again.
  final accountError = account.error;
  final error = accountError ?? ab.pullError;
  void retry() => accountError != null ? account.refresh() : ab.pull();
  final refresh = LgListToolButton(
    icon: LgIcons.refresh,
    label: l10n.abRefresh,
    onPressed: ab.loading ? null : retry,
  );
  if (error?.kind == ApiErrorKind.network) {
    return AccountCategoryView(
      tools: [refresh],
      state: AbStateWithAction(
        text: l10n.abNetworkError,
        icon: LgIcons.wifiOff,
        action: l10n.abRetry,
        onPressed: retry,
      ),
    );
  }
  final hidden = appCore.options.local.listenable(kOptionHideAbTagsPanel);
  bool tagsHidden() => appCore.options.local.get(kOptionHideAbTagsPanel) == 'Y';
  final banner = error != null
      ? (l10n.abLoadFailed(abReason(l10n, error)), retry)
      : ab.pushError != null
      ? (l10n.abSaveFailed(abReason(l10n, ab.pushError!)), ab.pull)
      : null;
  return AccountCategoryView(
    tools: [
      refresh,
      ListenableBuilder(
        listenable: hidden,
        builder: (context, _) => LgListToolButton(
          icon: LgIcons.tag,
          label: l10n.abTags,
          active: !tagsHidden(),
          onPressed: () => appCore.options.local.set(
            kOptionHideAbTagsPanel,
            tagsHidden() ? '' : 'Y',
          ),
        ),
      ),
    ],
    header: ListenableBuilder(
      listenable: hidden,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ab.current != null) AbBookBar(more: _moreItems(l10n, overlays)),
          if (ab.current != null && !tagsHidden())
            AbTagBar(tagMenu: (tag) => _tagItems(l10n, overlays, tag)),
          if (banner != null)
            AbBanner(
              text: banner.$1,
              onRetry: banner.$2,
              onClose: ab.dismissErrors,
            ),
        ],
      ),
    ),
    state: !ab.loaded || (ab.peers.isEmpty && ab.loading)
        ? SingleChildScrollView(
            child: LgDeviceSkeleton(semanticLabel: l10n.recentLoading),
          )
        : ab.current == null
        ? const SizedBox.shrink()
        : ab.peers.isEmpty
        ? SingleChildScrollView(
            child: LgEmptyState(l10n.abEmpty, icon: LgIcons.book),
          )
        : ab.shownPeers.isEmpty
        ? SingleChildScrollView(
            child: LgEmptyState(l10n.abNoTagMatch, icon: LgIcons.tag),
          )
        : null,
  );
}

/// The "More" menu (01 P1 block G): a read-only book keeps only the filter's items.
List<Widget> _moreItems(AppLocalizations l10n, TabOverlays overlays) {
  final ab = appCore.addressBook;
  return [
    if (ab.canWrite) ...[
      LgMenuItem(
        label: l10n.abAddDevice,
        onPressed: () => showAbAddDeviceDialog(overlays),
      ),
      LgMenuItem(
        label: l10n.abAddTag,
        onPressed: () => showAbAddTagDialog(overlays, l10n),
      ),
    ],
    LgMenuItem(label: l10n.abUnselectAllTags, onPressed: ab.unselectAllTags),
    if (ab.canWrite)
      LgMenuCheckItem(
        label: l10n.abSyncWithRecent,
        value: ab.syncWithRecent,
        onChanged: ab.setSyncWithRecent,
      ),
    LgMenuCheckItem(
      label: l10n.abFilterIntersection,
      value: ab.filterByIntersection,
      onChanged: ab.setFilterByIntersection,
    ),
  ];
}

/// A tag's right-click menu in a book that can be written.
List<Widget> _tagItems(
  AppLocalizations l10n,
  TabOverlays overlays,
  String tag,
) {
  final ab = appCore.addressBook;
  return [
    LgMenuItem(
      label: l10n.abTagRename,
      onPressed: () => showAbRenameTagDialog(overlays, l10n, tag),
    ),
    LgMenuItem(
      label: l10n.abTagChangeColor,
      onPressed: () => showAbTagColorDialog(overlays, tag),
    ),
    LgMenuItem(
      label: l10n.abTagDelete,
      danger: true,
      onPressed: () async {
        final e = await ab.deleteTag(tag);
        _failed(e);
      },
    ),
  ];
}

/// A change made outside a dialog failed: the banner says so (a sign-out needs nothing more).
void _failed(ApiError? error) {
  if (error != null && error.kind != ApiErrorKind.unauthorized) {
    appCore.addressBook.pushFailed(error);
  }
}

bool get _signedIn => appCore.account.loggedIn;

/// The connect box's devices (01 P1 block E): [sourced] (recent, favorites, LAN) followed by the
/// address book's and the team devices' devices that are not in it yet.
List<SourcedPeer> withAccountPeers(List<SourcedPeer> sourced) {
  if (!_signedIn) return sourced;
  final seen = {for (final s in sourced) s.peer.id};
  final ab = appCore.addressBook;
  final group = appCore.group;
  return [
    ...sourced,
    if (!ab.disabled)
      for (final p in ab.allPeers)
        if (seen.add(p.id)) (peer: p, source: PeerCategory.addressBook),
    if (!group.disabled)
      for (final p in group.peers)
        if (seen.add(p.id)) (peer: p, source: PeerCategory.group),
  ];
}

/// Whether the address book or the team devices have not loaded yet ("正在加载其他分类…"). After a
/// failed check of the sign-in neither is pulled, so neither is on its way.
bool accountPeersLoading() {
  if (!_signedIn || appCore.account.error != null) return false;
  final ab = appCore.addressBook;
  final group = appCore.group;
  return (!ab.disabled && !ab.loaded) ||
      (!group.disabled && !group.loaded && group.error == null);
}

/// The tags a card or a list row shows: the address book's, in their colours; none elsewhere.
List<LgDeviceTag> abPeerTags(PeerItem item) =>
    item.category != PeerCategory.addressBook
    ? const []
    : [
        for (final t in item.peer.tags)
          LgDeviceTag(t.toString(), abTagColor(t.toString())),
      ];

/// The key mark's tooltip when the shared book stores the device's password; null shows no key.
String? abPeerKeyLabel(AppLocalizations l10n, PeerItem item) =>
    item.category == PeerCategory.addressBook &&
        appCore.addressBook.sharedPasswordOf(item.peer.id) != null
    ? l10n.abSavedPassword
    : null;

/// The device menu's item for [action] where the address book has its own: the six address book
/// actions everywhere, and in the address book category "重命名" (the book's alias) and "清除保存的
/// 密码" in the personal book (the book's hash as well). Null keeps the page's own item. The items
/// that write a read-only book are greyed (01 P1 block F); [abMenuGroupNote] says why.
Widget? abPeerMenuItem(
  AppLocalizations l10n,
  PeerItem item,
  PeerAction action, {
  required TabOverlays overlays,
}) {
  final ab = appCore.addressBook;
  final peer = item.peer;
  final inAb = item.category == PeerCategory.addressBook;
  VoidCallback? unlessGreyed(VoidCallback run) =>
      inAb && ab.greyed(action) ? null : run;
  void toast(String key) => appCore.toasts.show(key);
  return switch (action) {
    PeerAction.addToAb => LgMenuItem(
      label: l10n.abAddToAb,
      onPressed: () async {
        if (await showAbAddToDialog(overlays, [
          peer,
        ], ab.addTargets(item.category))) {
          toast('abToastAdded');
        }
      },
    ),
    PeerAction.editTags => LgMenuItem(
      label: l10n.abEditTags,
      onPressed: unlessGreyed(
        () => showAbEditTagsDialog(overlays, [peer.id], peer.tags),
      ),
    ),
    PeerAction.editNote => LgMenuItem(
      label: l10n.abEditNote,
      onPressed: unlessGreyed(() => showAbEditNoteDialog(overlays, l10n, peer)),
    ),
    PeerAction.setSharedPassword => LgMenuItem(
      label: l10n.abSetSharedPassword,
      onPressed: unlessGreyed(
        () => showAbSharedPasswordDialog(overlays, l10n, peer),
      ),
    ),
    PeerAction.showBooks => LgMenuItem(
      label: l10n.abShowBooks,
      onPressed: () => showAbBooksDialog(overlays, l10n, peer.id),
    ),
    PeerAction.deleteFromAb => LgMenuItem(
      label: l10n.abDeleteFromAb,
      danger: true,
      onPressed: unlessGreyed(() async {
        if (!await confirmOnHome(
          overlays,
          title: l10n.abDeleteOne(peerDisplayName(peer)),
          action: l10n.abDelete,
          cancel: l10n.homeCancel,
        )) {
          return;
        }
        final e = await ab.deletePeers([peer.id]);
        e == null ? toast('abToastDeleted') : _failed(e);
      }),
    ),
    PeerAction.rename when inAb => LgMenuItem(
      label: l10n.peerMenuRename,
      onPressed: unlessGreyed(() async {
        final alias = await askAlias(overlays, l10n, alias: peer.alias);
        if (alias == null || alias == peer.alias) return;
        final e = await ab.setAlias(peer.id, alias);
        e == null ? toast('peerMenuToastRenamed') : _failed(e);
      }),
    ),
    PeerAction.clearPassword
        when inAb &&
            ab.current != null &&
            ab.isPersonal(ab.current!) &&
            peer.hash.isNotEmpty =>
      LgMenuItem(
        label: l10n.peerMenuClearPassword,
        onPressed: () async {
          final e = await ab.clearPassword(peer.id);
          e == null ? toast('peerMenuToastPasswordCleared') : _failed(e);
        },
      ),
    _ => null,
  };
}

/// The note beside the title of [group] in [groups] ("此地址簿为只读"): on the first group with a
/// greyed item only (01 P1 block F).
String? abMenuGroupNote(
  AppLocalizations l10n,
  PeerItem item,
  List<PeerAction> group,
  List<List<PeerAction>> groups,
) {
  if (item.category != PeerCategory.addressBook) return null;
  final ab = appCore.addressBook;
  final first = groups.where((g) => g.any(ab.greyed)).firstOrNull;
  return identical(first, group) ? l10n.abReadOnly : null;
}

/// The devices [ids] of [category], for "加入地址簿".
List<Peer> _picked(PeerCategory category, Set<String> ids) {
  final list = switch (category) {
    PeerCategory.addressBook => appCore.addressBook.peers,
    PeerCategory.group => appCore.group.peers,
    _ => categoryPeers(category).peers,
  };
  return [
    for (final p in list)
      if (ids.contains(p.id)) p,
  ];
}

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
}) {
  final ab = appCore.addressBook;
  final targets = ab.addTargets(category);
  final inAb = category == PeerCategory.addressBook;
  // Greyed in a read-only book, as the device menu (the bar has no place for the reason).
  final writable = ids.isNotEmpty && ab.canWrite;
  return [
    if (_signedIn && targets.isNotEmpty)
      LgSelectionAction(
        label: l10n.abAddToAb,
        icon: LgIcons.book,
        onPressed: ids.isEmpty
            ? null
            : () async {
                if (await showAbAddToDialog(
                  overlays,
                  _picked(category, ids),
                  targets,
                )) {
                  done('abToastAdded');
                }
              },
      ),
    if (inAb && ab.tags.isNotEmpty)
      LgSelectionAction(
        label: l10n.abEditTags,
        icon: LgIcons.tag,
        onPressed: writable
            ? () => showAbEditTagsDialog(overlays, ids.toList(), const [])
            : null,
      ),
    if (inAb)
      LgSelectionAction(
        label: l10n.abDeleteFromAb,
        icon: LgIcons.trash,
        danger: true,
        onPressed: writable
            ? () async {
                if (!await confirmOnHome(
                  overlays,
                  title: l10n.abDeleteMany(ids.length),
                  action: l10n.abDelete,
                  cancel: l10n.homeCancel,
                )) {
                  return;
                }
                final e = await ab.deletePeers(ids.toList());
                e == null ? done('abToastDeleted') : _failed(e);
              }
            : null,
      ),
  ];
}
