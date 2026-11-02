import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/peer_list.dart';
import 'package:flutter_hbb/leapgate/peer_tabs.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../l10n/app_localizations.dart';
import '../../shell/navigation.dart';
import '../../shell/tab_overlays.dart';
import '../../widgets/lg_device.dart';
import '../../widgets/lg_device_card.dart';
import '../../widgets/lg_menu.dart';
import '../../widgets/lg_menu_items.dart';
import '../peer_platform.dart';
import 'address_book/address_book.dart';
import 'home_dialogs.dart';

// The device cards, the list view rows and the "⋯" menu of the devices page (01 P1 block F).

/// Opens [id]; from the address book with the shared password the book stores (01 P1 block F,
/// upstream `connectInPeerTab`). [category] is where the device is listed, null for what was
/// typed.
void connectPeer(String id, {PeerCategory? category, bool relay = false}) {
  final shared = category == PeerCategory.addressBook
      ? appCore.addressBook.sharedPasswordOf(id)
      : null;
  mainNavigation.connect(
    id,
    password: shared ?? '',
    isSharedPassword: shared != null,
    forceRelay: relay,
  );
}

/// What one device shows in a card or a row.
class PeerItem {
  const PeerItem({
    required this.peer,
    required this.category,
    required this.status,
    required this.statusLabel,
    required this.favorite,
    this.source,
  });

  final Peer peer;

  /// The category whose menu it gets: the one listed, or in the search results where it came
  /// from.
  final PeerCategory category;
  final LgDeviceStatus status;
  final String statusLabel;
  final bool favorite;

  /// The category name, in the search results only.
  final String? source;
}

/// What a card or row does when used.
class PeerItemActions {
  const PeerItemActions({
    required this.onTap,
    required this.onConnect,
    required this.overlays,
    this.selecting = false,
    this.selected = false,
    this.current = false,
  });

  /// A click: makes it current, or in multiple selection picks it.
  final VoidCallback onTap;
  final VoidCallback onConnect;
  final TabOverlays overlays;
  final bool selecting;

  /// Picked in multiple selection.
  final bool selected;

  /// The row Enter runs (clicked or reached with the arrow keys).
  final bool current;
}

/// A device as a card.
class PeerCard extends StatelessWidget {
  const PeerCard({super.key, required this.item, required this.actions});

  final PeerItem item;
  final PeerItemActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final a = actions;
    final peer = item.peer;
    final userHost = peerUserHost(peer);
    final keyLabel = abPeerKeyLabel(l10n, item);
    return LgDeviceCard(
      name: peerDisplayName(peer),
      id: formatPeerId(peer.id),
      platform: lgPlatformOf(peer.platform),
      status: item.status,
      statusLabel: item.statusLabel,
      userHost: userHost.isEmpty ? null : userHost,
      tags: abPeerTags(item),
      savedPassword: keyLabel != null,
      savedPasswordLabel: keyLabel,
      source: item.source,
      favorite: item.favorite,
      favoriteLabel: l10n.peersFavorite,
      selected: a.current,
      picked: a.selecting ? a.selected : null,
      onTap: a.onTap,
      onDoubleTap: a.selecting ? null : a.onConnect,
      onConnect: a.selecting ? null : a.onConnect,
      connectLabel: l10n.connectBoxConnect,
      // "⋯" sits at the card's top right corner; the menu opens there.
      onMore: () => _openAtCorner(context, item, a, (size) => size.topRight(Offset.zero)),
      moreLabel: l10n.peerMenu,
      onContextMenu: (at) => openPeerMenu(context, item, a.overlays, at),
    );
  }
}

/// A list view row. In a category list the tags column is there (empty until the address book,
/// M4); in the search results the source column takes its place.
class PeerTableRow extends StatelessWidget {
  const PeerTableRow({
    super.key,
    required this.item,
    required this.actions,
    required this.topDivider,
  });

  final PeerItem item;
  final PeerItemActions actions;
  final bool topDivider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final a = actions;
    final peer = item.peer;
    final userHost = peerUserHost(peer);
    final keyLabel = abPeerKeyLabel(l10n, item);
    return LgDeviceRow(
      name: peerDisplayName(peer),
      id: formatPeerId(peer.id),
      platform: lgPlatformOf(peer.platform),
      status: item.status,
      statusLabel: item.statusLabel,
      userHost: userHost.isEmpty ? null : userHost,
      source: item.source,
      tags: item.source == null ? abPeerTags(item) : null,
      savedPassword: keyLabel != null,
      savedPasswordLabel: keyLabel,
      favorite: item.favorite,
      favoriteLabel: l10n.peersFavorite,
      selected: a.selected || (a.current && item.source == null),
      highlighted: a.current && item.source != null,
      picked: a.selecting ? a.selected : null,
      topDivider: topDivider,
      connectLabel: l10n.connectBoxConnect,
      onTap: a.onTap,
      onDoubleTap: a.selecting ? null : a.onConnect,
      onConnect: a.selecting ? null : a.onConnect,
      // "⋯" is at the row's right end; the menu opens under it.
      onMore: () =>
          _openAtCorner(context, item, a, (size) => size.bottomRight(Offset.zero)),
      moreLabel: l10n.peerMenu,
      onContextMenu: (at) => openPeerMenu(context, item, a.overlays, at),
    );
  }
}

void _openAtCorner(
  BuildContext context,
  PeerItem item,
  PeerItemActions actions,
  Offset Function(Size size) corner,
) {
  final box = context.findRenderObject()! as RenderBox;
  openPeerMenu(
    context,
    item,
    actions.overlays,
    box.localToGlobal(corner(box.size)),
  );
}

/// The device menu at [globalPosition]. Rust is asked first whether a password is saved, as
/// upstream builds its menu (`peer_card.dart` `_buildMenuItems`).
Future<void> openPeerMenu(
  BuildContext context,
  PeerItem item,
  TabOverlays overlays,
  Offset globalPosition,
) async {
  final hasPassword = await peerHasPassword(item.peer.id);
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  showLgMenuAt(
    context,
    globalPosition: globalPosition,
    items: peerMenuItems(
      l10n,
      item,
      overlays: overlays,
      hasPassword: hasPassword,
    ),
  );
}

/// The groups of [peerMenu] as menu items.
List<Widget> peerMenuItems(
  AppLocalizations l10n,
  PeerItem item, {
  required TabOverlays overlays,
  required bool hasPassword,
}) {
  final id = item.peer.id;
  final name = peerDisplayName(item.peer);
  // The toast keys are ARB keys; the shell's `toastText` shows them.
  void done(String toast) => appCore.toasts.show(toast);
  final groups = peerMenu(
    item.category,
    favorite: item.favorite,
    // In the personal book the hash it stores counts as well (`AddressBookPeerCard`).
    hasPassword: hasPassword ||
        (item.category == PeerCategory.addressBook && item.peer.hash.isNotEmpty),
    windows: Platform.isWindows,
    ab: appCore.addressBook.menuFlags(item.category),
  );
  final titles = [
    l10n.connectBoxConnectionType,
    l10n.peerMenuDevice,
    l10n.peerMenuManage,
    l10n.peerMenuDanger,
  ];
  // The danger group is the last of [peerMenu]'s four; a group left out shifts the rest.
  String titleOf(List<PeerAction> group) => switch (group.first) {
    PeerAction.remoteDesktop => titles[0],
    PeerAction.alwaysRelay => titles[1],
    PeerAction.delete || PeerAction.remove || PeerAction.deleteFromAb =>
      titles[3],
    _ => titles[2],
  };
  Widget itemOf(PeerAction action) =>
      abPeerMenuItem(l10n, item, action, overlays: overlays) ??
      switch (action) {
    PeerAction.remoteDesktop => LgMenuItem(
      label: l10n.connectBoxRemoteDesktop,
      onPressed: () => connectPeer(id, category: item.category),
    ),
    PeerAction.viaRelay => LgMenuItem(
      label: l10n.connectBoxViaRelay,
      description: l10n.connectBoxViaRelayNote,
      onPressed: () =>
          connectPeer(id, category: item.category, relay: true),
    ),
    // The menu stays open, so the box follows the value it set.
    PeerAction.alwaysRelay => StatefulBuilder(
      builder: (context, setState) => LgMenuCheckItem(
        label: l10n.peerMenuAlwaysRelay,
        value: alwaysRelay(id),
        onChanged: (v) async {
          await setAlwaysRelay(id, v);
          setState(() {});
        },
      ),
    ),
    PeerAction.wakeOnLan => LgMenuItem(
      label: l10n.peerMenuWakeOnLan,
      onPressed: () => wakeOnLan(id),
    ),
    PeerAction.createShortcut => LgMenuItem(
      label: l10n.peerMenuCreateShortcut,
      onPressed: () async {
        await createShortcut(id);
        done('peerMenuToastShortcutCreated');
      },
    ),
    PeerAction.rename => LgMenuItem(
      label: l10n.peerMenuRename,
      onPressed: () async {
        final old = peerAlias(id);
        final alias = await askAlias(overlays, l10n, alias: old);
        if (alias == null || alias == old) return;
        await renamePeer(id, alias);
        done('peerMenuToastRenamed');
      },
    ),
    PeerAction.addFavorite => LgMenuItem(
      label: l10n.peersAddFavorites,
      onPressed: () async {
        await addFavorites([id]);
        done('peersToastAddedFavorites');
      },
    ),
    PeerAction.removeFavorite => LgMenuItem(
      label: l10n.peersRemoveFavorites,
      onPressed: () async {
        await removeFavorites([id]);
        done('peersToastRemovedFavorites');
      },
    ),
    PeerAction.clearPassword => LgMenuItem(
      label: l10n.peerMenuClearPassword,
      onPressed: () async {
        await clearSavedPassword(id);
        done('peerMenuToastPasswordCleared');
      },
    ),
    PeerAction.delete || PeerAction.remove => LgMenuItem(
      label: action == PeerAction.delete ? l10n.peersDelete : l10n.peersRemove,
      danger: true,
      onPressed: () async {
        final delete = action == PeerAction.delete;
        if (!await confirmOnHome(
          overlays,
          title: delete ? l10n.peersDeleteOne(name) : l10n.peersRemoveOne(name),
          action: delete ? l10n.peersDelete : l10n.peersRemove,
          cancel: l10n.homeCancel,
        )) {
          return;
        }
        await deletePeers(item.category, [id]);
        done(delete ? 'peersToastDeleted' : 'peersToastRemoved');
      },
    ),
    // [abPeerMenuItem] builds these.
    PeerAction.addToAb ||
    PeerAction.editTags ||
    PeerAction.editNote ||
    PeerAction.setSharedPassword ||
    PeerAction.showBooks ||
    PeerAction.deleteFromAb => const SizedBox.shrink(),
  };
  return [
    for (final group in groups) ...[
      LgMenuGroup(
        titleOf(group),
        note: abMenuGroupNote(l10n, item, group, groups),
      ),
      for (final action in group) itemOf(action),
    ],
  ];
}

/// Shift held while clicking, for picking a run of devices.
bool get shiftPressed => HardwareKeyboard.instance.isShiftPressed;

/// The rows under "Adjust the categories shown and their order" (`p1-menu-view`): a check per
/// category, and the grip to drag it to another place. The component draws the grip; the
/// dragging is this list's.
class CategoryOrderList extends StatelessWidget {
  const CategoryOrderList({
    super.key,
    required this.tabs,
    required this.names,
    required this.fixedNote,
  });

  final PeerTabs tabs;
  final String Function(PeerCategory) names;

  /// Greys the rows when the categories are fixed by built-in settings, saying why.
  final String? fixedNote;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: tabs,
      builder: (context, _) {
        final ordered = tabs.ordered;
        return ReorderableListView(
          shrinkWrap: true,
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) => tabs.move(ordered[from], to),
          children: [
            for (final (i, cat) in ordered.indexed)
              KeyedSubtree(
                key: ValueKey(cat),
                child: LgMenuItem(
                  label: names(cat),
                  checked: tabs.isVisible(cat),
                  keepOpen: true,
                  disabledNote: fixedNote,
                  onPressed: fixedNote != null
                      ? null
                      : () => tabs.setVisible(cat, !tabs.isVisible(cat)),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    enabled: fixedNote == null,
                    child: Semantics(
                      label: l10n.peersMoveCategory(names(cat)),
                      child: const LgMenuGrip(),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
