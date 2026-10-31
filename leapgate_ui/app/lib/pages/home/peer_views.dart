import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/peer_list.dart';
import 'package:flutter_hbb/leapgate/peer_tabs.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/navigation.dart';
import '../../shell/tab_overlays.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_device.dart';
import '../../widgets/lg_menu.dart';
import '../../widgets/lg_selection.dart';
import '../peer_platform.dart';
import 'home_dialogs.dart';

// The device cards, the list view rows and the "⋯" menu of the devices page (01 P1 block F).
// The card, the row's extra controls and the menu's group style are placeholders until the
// designer's `LgDeviceCard`, `LgDeviceTable` and menu groups replace them (LEAPGATE.md §10.9);
// what they show and do is final.

/// Each card column is at least this wide (01 P1 block F: 3 columns at 1280, 2 at 960).
const kMinCardWidth = 300.0;

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

/// Placeholder for `LgDeviceCard`.
class PeerCard extends StatefulWidget {
  const PeerCard({super.key, required this.item, required this.actions});

  final PeerItem item;
  final PeerItemActions actions;

  @override
  State<PeerCard> createState() => _PeerCardState();
}

class _PeerCardState extends State<PeerCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final c = t.colors;
    final item = widget.item;
    final a = widget.actions;
    final peer = item.peer;
    final userHost = peerUserHost(peer);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Semantics(
        container: true,
        selected: a.selected || a.current,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: a.onTap,
          onDoubleTap: a.selecting ? null : a.onConnect,
          child: Container(
            padding: const EdgeInsets.all(LgSpace.s4),
            decoration: BoxDecoration(
              color: a.selected || a.current ? c.active : c.surface,
              borderRadius: BorderRadius.circular(LgRadius.r16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (a.selecting)
                      Semantics(
                        checked: a.selected,
                        child: LgIcon(
                          a.selected ? LgIcons.checkCircle : LgIcons.square,
                          size: 20,
                          color: c.accent,
                        ),
                      ),
                    LgDeviceAvatar(
                      id: peer.id,
                      platform: lgPlatformOf(peer.platform),
                    ),
                    const SizedBox(width: LgSpace.s3),
                    Expanded(
                      child: Text(
                        peerDisplayName(peer),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.copyWith(
                          color: c.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (item.favorite)
                      Semantics(
                        label: l10n.peersFavorite,
                        child: LgIcon(LgIcons.star, size: 16, color: c.text2),
                      ),
                    if (!a.selecting) PeerMoreButton(item: item, actions: a),
                  ],
                ),
                Text(
                  formatPeerId(peer.id),
                  style: t.textS.copyWith(color: c.text2),
                ),
                if (userHost.isNotEmpty)
                  Text(
                    userHost,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textS.copyWith(color: c.text2),
                  ),
                Row(
                  children: [
                    Text(
                      item.statusLabel,
                      style: t.textS.copyWith(
                        color: item.status == LgDeviceStatus.online
                            ? c.online
                            : c.text2,
                      ),
                    ),
                    if (item.source != null) ...[
                      const SizedBox(width: LgSpace.s2),
                      Text(
                        item.source!,
                        style: t.textS.copyWith(color: c.text2),
                      ),
                    ],
                    const Spacer(),
                    if (_hover && !a.selecting)
                      LgButton(
                        label: l10n.connectBoxConnect,
                        kind: LgButtonKind.secondary,
                        onPressed: a.onConnect,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A list view row: M2a's `LgDeviceRow` with the pick box, the star and "⋯" beside it
/// (placeholder for `LgDeviceTable`'s row).
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
    final c = LgTokens.of(context).colors;
    final a = actions;
    final peer = item.peer;
    final userHost = peerUserHost(peer);
    return Row(
      children: [
        if (a.selecting)
          Semantics(
            checked: a.selected,
            child: LgIcon(
              a.selected ? LgIcons.checkCircle : LgIcons.square,
              size: 20,
              color: c.accent,
            ),
          ),
        Expanded(
          child: LgDeviceRow(
            name: peerDisplayName(peer),
            id: formatPeerId(peer.id),
            platform: lgPlatformOf(peer.platform),
            status: item.status,
            statusLabel: item.statusLabel,
            userHost: userHost.isEmpty ? null : userHost,
            source: item.source,
            selected: a.selected || (a.current && item.source == null),
            highlighted: a.current && item.source != null,
            topDivider: topDivider,
            connectLabel: l10n.connectBoxConnect,
            onTap: a.onTap,
            onDoubleTap: a.selecting ? null : a.onConnect,
            onConnect: a.selecting ? null : a.onConnect,
          ),
        ),
        if (item.favorite)
          Semantics(
            label: l10n.peersFavorite,
            child: LgIcon(LgIcons.star, size: 16, color: c.text2),
          ),
        if (!a.selecting) PeerMoreButton(item: item, actions: a),
      ],
    );
  }
}

/// "⋯" and the device menu (01 P1 block F): asks Rust whether a password is saved before it
/// opens, as upstream builds its menu (`peer_card.dart` `_buildMenuItems`).
class PeerMoreButton extends StatefulWidget {
  const PeerMoreButton({super.key, required this.item, required this.actions});

  final PeerItem item;
  final PeerItemActions actions;

  @override
  State<PeerMoreButton> createState() => _PeerMoreButtonState();
}

class _PeerMoreButtonState extends State<PeerMoreButton> {
  final _menu = MenuController();
  bool _hasPassword = false;

  Future<void> _open() async {
    final has = await peerHasPassword(widget.item.peer.id);
    if (!mounted) return;
    setState(() => _hasPassword = has);
    _menu.open();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LgMenuAnchor(
      controller: _menu,
      items: peerMenuItems(
        context,
        l10n,
        widget.item,
        overlays: widget.actions.overlays,
        hasPassword: _hasPassword,
      ),
      builder: (context, controller) => LgIconButton(
        icon: LgIcons.more,
        label: l10n.peerMenu,
        onPressed: () => controller.isOpen ? controller.close() : _open(),
      ),
    );
  }
}

/// The groups of [peerMenu] as menu items.
List<Widget> peerMenuItems(
  BuildContext context,
  AppLocalizations l10n,
  PeerItem item, {
  required TabOverlays overlays,
  required bool hasPassword,
}) {
  final id = item.peer.id;
  final name = peerDisplayName(item.peer);
  void done() => appCore.toasts.show('Successful');
  final groups = peerMenu(
    item.category,
    favorite: item.favorite,
    hasPassword: hasPassword,
    windows: Platform.isWindows,
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
    PeerAction.delete || PeerAction.remove => titles[3],
    _ => titles[2],
  };
  Widget itemOf(PeerAction action) => switch (action) {
    PeerAction.remoteDesktop => LgMenuItem(
      label: l10n.connectBoxRemoteDesktop,
      onPressed: () => mainNavigation.connect(id),
    ),
    PeerAction.viaRelay => LgMenuItem(
      label: l10n.connectBoxViaRelay,
      description: l10n.connectBoxViaRelayNote,
      onPressed: () => mainNavigation.connect(id, forceRelay: true),
    ),
    PeerAction.alwaysRelay => LgMenuItem(
      label: l10n.peerMenuAlwaysRelay,
      checked: alwaysRelay(id),
      onPressed: () async {
        await setAlwaysRelay(id, !alwaysRelay(id));
        done();
      },
    ),
    PeerAction.wakeOnLan => LgMenuItem(
      label: l10n.peerMenuWakeOnLan,
      onPressed: () => wakeOnLan(id),
    ),
    PeerAction.createShortcut => LgMenuItem(
      label: l10n.peerMenuCreateShortcut,
      onPressed: () async {
        await createShortcut(id);
        done();
      },
    ),
    PeerAction.rename => LgMenuItem(
      label: l10n.peerMenuRename,
      onPressed: () async {
        final old = peerAlias(id);
        final alias = await askAlias(overlays, l10n, alias: old);
        if (alias == null || alias == old) return;
        await renamePeer(id, alias);
        done();
      },
    ),
    PeerAction.addFavorite => LgMenuItem(
      label: l10n.peersAddFavorites,
      onPressed: () async {
        await addFavorites([id]);
        done();
      },
    ),
    PeerAction.removeFavorite => LgMenuItem(
      label: l10n.peersRemoveFavorites,
      onPressed: () async {
        await removeFavorites([id]);
        done();
      },
    ),
    PeerAction.clearPassword => LgMenuItem(
      label: l10n.peerMenuClearPassword,
      onPressed: () async {
        await clearSavedPassword(id);
        done();
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
        done();
      },
    ),
  };
  return [
    for (final group in groups) ...[
      LgMenuGroup(titleOf(group)),
      for (final action in group) itemOf(action),
    ],
  ];
}

/// Shift held while clicking, for picking a run of devices.
bool get shiftPressed => HardwareKeyboard.instance.isShiftPressed;

/// The "Adjust the categories shown and their order" list (placeholder for the designer's
/// menu list with drag handles): a box per category and a handle to drag it.
class CategoryOrderList extends StatelessWidget {
  const CategoryOrderList({
    super.key,
    required this.tabs,
    required this.names,
    required this.enabled,
  });

  final PeerTabs tabs;
  final String Function(PeerCategory) names;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = LgTokens.of(context).colors;
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
              Row(
                key: ValueKey(cat),
                children: [
                  Expanded(
                    child: LgCheckbox(
                      value: tabs.isVisible(cat),
                      label: names(cat),
                      onChanged: enabled
                          ? (v) => tabs.setVisible(cat, v)
                          : null,
                    ),
                  ),
                  ReorderableDragStartListener(
                    index: i,
                    enabled: enabled,
                    child: Semantics(
                      label: l10n.peersMoveCategory(names(cat)),
                      child: LgIcon(LgIcons.grip, size: 20, color: c.text2),
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
