import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/address_book.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/peer_list.dart';
import 'package:flutter_hbb/leapgate/peer_tabs.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_banner.dart';
import '../../../widgets/lg_book_switcher.dart';
import '../../../widgets/lg_device.dart';
import '../../../widgets/lg_device_parts.dart';
import '../../../widgets/lg_list_chrome.dart';
import '../../../widgets/lg_menu.dart';
import '../../../widgets/lg_menu_items.dart';
import '../../../widgets/lg_tag_chips.dart';
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

/// The book switcher, the tag bar, the tools and the states of the address book category; the
/// loading skeleton in [view].
AccountCategoryView addressBookCategory(
  BuildContext context,
  TabOverlays overlays,
  PeerView view,
) {
  final l10n = AppLocalizations.of(context)!;
  final account = appCore.account;
  final ab = appCore.addressBook;
  // A list state of one sentence, with a button when there is something to do.
  Widget state(
    String text,
    LgIcons icon, {
    String? action,
    LgIcons? actionIcon,
    VoidCallback? onAction,
  }) => SingleChildScrollView(
    child: LgEmptyState(
      text,
      icon: icon,
      actionLabel: action,
      actionIcon: actionIcon,
      onAction: onAction,
    ),
  );
  if (!account.loggedIn) {
    return AccountCategoryView(
      state: state(
        l10n.abSignedOut,
        LgIcons.book,
        action: l10n.abSignIn,
        actionIcon: LgIcons.login,
        onAction: () => showLoginDialog(overlays),
      ),
    );
  }
  if (ab.unsupported) {
    return AccountCategoryView(state: state(l10n.abUnsupported, LgIcons.book));
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
      state: state(
        l10n.abNetworkError,
        LgIcons.wifiOff,
        action: l10n.abRetry,
        actionIcon: LgIcons.refresh,
        onAction: retry,
      ),
    );
  }
  // The server refused the check of the sign-in: nothing was pulled (01 P1 block F).
  if (accountError != null) {
    return AccountCategoryView(
      tools: [refresh],
      state: state(
        l10n.abLoadFailed(abReason(l10n, accountError)),
        LgIcons.err,
        action: l10n.abRetry,
        actionIcon: LgIcons.refresh,
        onAction: retry,
      ),
    );
  }
  final hidden = appCore.options.local.listenable(kOptionHideAbTagsPanel);
  bool tagsHidden() => appCore.options.local.get(kOptionHideAbTagsPanel) == 'Y';
  final banner = error != null
      ? (l10n.abLoadFailed(abReason(l10n, error)), retry)
      : ab.pushError != null
      ? (
          l10n.abSaveFailed(abReason(l10n, ab.pushError!)),
          () {
            ab.dismissErrors();
            ab.pull();
          },
        )
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
          if (ab.current != null) ...[
            _bookSwitcher(l10n, overlays),
            // The mockup's 12 and 20; the tag bar keeps 3 px of its own above and under it
            // for the focus ring.
            if (tagsHidden())
              const SizedBox(height: LgSpace.s5)
            else ...[
              const SizedBox(height: LgSpace.s3 - 3),
              _tagBar(context, l10n, overlays),
              const SizedBox(height: LgSpace.s5 - 3),
            ],
          ],
          if (banner != null) ...[
            LgBanner(
              tone: LgTone.error,
              text: banner.$1,
              slim: true,
              actionLabel: l10n.abRetry,
              actionIcon: LgIcons.refresh,
              onAction: banner.$2,
              dismissLabel: l10n.abDismiss,
              onDismiss: ab.dismissErrors,
            ),
            const SizedBox(height: LgSpace.s3),
          ],
        ],
      ),
    ),
    state: !ab.loaded || (ab.peers.isEmpty && ab.loading)
        ? AccountLoading(view: view, label: l10n.recentLoading)
        : ab.current == null
        ? const SizedBox.shrink()
        : ab.peers.isEmpty
        // Never answered: the banner says why, the list says nothing more.
        ? (ab.currentInitialized
              ? state(l10n.abEmpty, LgIcons.book)
              : const SizedBox.shrink())
        : ab.shownPeers.isEmpty
        ? state(l10n.abNoTagMatch, LgIcons.tag)
        : null,
  );
}

/// The book switcher with the "More" menu at the end of its row (`p1-ab-switch`).
Widget _bookSwitcher(AppLocalizations l10n, TabOverlays overlays) {
  final ab = appCore.addressBook;
  return LgBookSwitcher(
    books: [
      for (final b in ab.books)
        LgBook(
          id: b.guid,
          name: abBookName(l10n, b),
          detail: abBookRights(l10n, b),
        ),
    ],
    selectedId: ab.current!.guid,
    onSelect: (guid) => ab.select(ab.books.firstWhere((b) => b.guid == guid)),
    searchPlaceholder: l10n.abSearchBooks,
    noMatchLabel: l10n.abNoBookMatch,
    hint: l10n.abSharedNote,
    semanticLabel: l10n.abSwitchBook,
    trailing: LgListToolMenu(
      icon: LgIcons.more,
      label: l10n.abMore,
      items: _moreItems(l10n, overlays),
    ),
  );
}

const _untagged = '';

/// The tag filter bar (`p1-ab-tags`): "未标记" first (no menu, no colour), then the tags; a right
/// click on a tag opens its menu when the book can be written. Real tags never have an empty name.
Widget _tagBar(
  BuildContext context,
  AppLocalizations l10n,
  TabOverlays overlays,
) {
  final ab = appCore.addressBook;
  final selected = ab.selectedTags;
  return LgTagFilterBar(
    items: [
      LgTagToggleItem(
        id: _untagged,
        label: l10n.abUntagged,
        on: selected.contains(kAbUntagged),
      ),
      for (final t in ab.tags)
        LgTagToggleItem(
          id: t.name,
          label: t.name,
          color: Color(t.color),
          on: selected.contains(t.name),
        ),
    ],
    noMenu: const {_untagged},
    onToggle: (id) => ab.toggleTag(id == _untagged ? kAbUntagged : id),
    onContextMenu: ab.canWrite
        ? (id, at) => showLgMenuAt(
            context,
            globalPosition: at,
            items: _tagItems(l10n, overlays, id),
          )
        : null,
    semanticLabel: l10n.abTagFilter,
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

/// Whether [category]'s list view has the note column (01 P1 block F: the address book and the
/// team devices).
bool abNoteColumn(PeerCategory category) =>
    category == PeerCategory.addressBook || category == PeerCategory.group;

/// The note a card or a list row shows: in the address book and the team devices, '' for none
/// (the column is there); null elsewhere and in the search results, which have no such column.
String? abPeerNote(PeerItem item) =>
    item.source == null && abNoteColumn(item.category) ? item.peer.note : null;

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

/// Whether [item] is a device of the current book. The connect box lists the other loaded
/// books' devices as the address book's too, but the book's actions write the current one.
bool abInCurrentBook(PeerItem item) {
  final ab = appCore.addressBook;
  return item.category == PeerCategory.addressBook &&
      ab.current != null &&
      ab.contains(ab.current!, item.peer.id);
}

/// The category [item]'s device menu is built for: another book's device found in the connect
/// box gets the menu of "收藏", which has the local items and "加入地址簿" only.
PeerCategory abMenuCategory(PeerItem item) =>
    item.category == PeerCategory.addressBook && !abInCurrentBook(item)
    ? PeerCategory.favorites
    : item.category;

/// The device menu's item for [action] where the address book has its own: the six address book
/// actions and "清除保存的密码" (the personal book's hash as well) everywhere, and in the address book
/// category "重命名" (the book's alias). Null keeps the page's own item. The items
/// that write a read-only book are greyed (01 P1 block F); [abMenuGroupNote] says why.
Widget? abPeerMenuItem(
  AppLocalizations l10n,
  PeerItem item,
  PeerAction action, {
  required TabOverlays overlays,
}) {
  final ab = appCore.addressBook;
  final peer = item.peer;
  final inAb = abInCurrentBook(item);
  VoidCallback? unlessGreyed(VoidCallback run) =>
      inAb && ab.greyed(action) ? null : run;
  void toast(String key) => appCore.toasts.show(key);
  return switch (action) {
    PeerAction.addToAb => LgMenuItem(
      label: l10n.abAddToAb,
      onPressed: () async {
        if (await showAbAddToDialog(overlays, l10n, [
          peer,
        ], ab.addTargets(abMenuCategory(item)))) {
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
        if (ab.current == null) return; // Signed out meanwhile.
        final e = await ab.deletePeers([peer.id]);
        e == null ? toast('abToastDeleted') : _failed(e);
      }),
    ),
    PeerAction.rename when inAb => LgMenuItem(
      label: l10n.peerMenuRename,
      onPressed: unlessGreyed(() async {
        final alias = await askAlias(overlays, l10n, alias: peer.alias);
        if (alias == null || alias == peer.alias || ab.current == null) return;
        final e = await ab.setAlias(peer.id, alias);
        e == null ? toast('peerMenuToastRenamed') : _failed(e);
      }),
    ),
    // In every category: the personal book's hash as well, or Rust would still fill it in from
    // the cache (upstream `_unrememberPasswordAction`).
    PeerAction.clearPassword => LgMenuItem(
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
  if (!abInCurrentBook(item)) return null;
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
/// an address book that can be written "编辑标签" and "从地址簿中删除". In the address book and
/// the team devices they are the only actions; elsewhere they follow the page's own. [done]
/// shows a toast by its ARB key and ends the selection.
List<LgSelectionAction> abSelectionActions(
  AppLocalizations l10n,
  PeerCategory category,
  Set<String> ids, {
  required TabOverlays overlays,
  required void Function(String toast) done,
}) {
  final ab = appCore.addressBook;
  final targets = ab.addTargets(category);
  // A read-only book has neither (the bar has no place to say why they would be greyed).
  final editable = category == PeerCategory.addressBook && ab.canWrite;
  final writable = ids.isNotEmpty;
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
                  l10n,
                  _picked(category, ids),
                  targets,
                )) {
                  done('abToastAdded');
                }
              },
      ),
    if (editable && ab.tags.isNotEmpty)
      LgSelectionAction(
        label: l10n.abEditTags,
        icon: LgIcons.tag,
        onPressed: writable
            ? () => showAbEditTagsDialog(overlays, ids.toList(), const [])
            : null,
      ),
    if (editable)
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
                if (ab.current == null) return; // Signed out meanwhile.
                final e = await ab.deletePeers(ids.toList());
                e == null ? done('abToastDeleted') : _failed(e);
              }
            : null,
      ),
  ];
}
