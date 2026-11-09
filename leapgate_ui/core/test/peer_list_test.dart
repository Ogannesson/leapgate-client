import 'dart:convert';

import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/peer_list.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Peer peer(String id,
        {String alias = '', String username = '', bool online = false}) =>
    Peer.fromJson({'id': id, 'alias': alias, 'username': username})
      ..online = online;

List<String> ids(List<Peer> peers) => [for (final p in peers) p.id];

void main() {
  group('sortPeers (01 P1 block F)', () {
    final peers = [
      peer('300000000', alias: 'b', username: 'Zed'),
      peer('100000000', alias: 'C', username: 'amy', online: true),
      peer('200000000', username: 'bob'),
      peer('400000000', alias: 'a', online: true),
    ];

    test('name (alias, else the ID), ID and user name, ignoring case', () {
      expect(ids(sortPeers(peers, PeerSort.name)),
          ['200000000', '400000000', '300000000', '100000000']);
      expect(ids(sortPeers(peers, PeerSort.id)),
          ['100000000', '200000000', '300000000', '400000000']);
      expect(ids(sortPeers(peers, PeerSort.username)),
          ['400000000', '100000000', '200000000', '300000000']);
    });

    test(
        'online first, each state in the order it came '
        '(upstream peers_view.dart:389-391 was no comparator)', () {
      expect(ids(sortPeers(peers, PeerSort.status)),
          ['100000000', '400000000', '300000000', '200000000']);
      // The same input gives the same result every time.
      expect(ids(sortPeers(peers.reversed.toList(), PeerSort.status)),
          ['400000000', '100000000', '200000000', '300000000']);
    });
  });

  group('searchablePeers (01 P1 block E)', () {
    setUp(() {
      installFakes();
      addTearDown(appCore.recentPeers.dispose);
      addTearDown(appCore.favPeers.dispose);
      addTearDown(appCore.lanPeers.dispose);
    });

    Future<void> load(String event, List<String> ids) => platformFFI.tryHandle({
          'name': event,
          'peers': jsonEncode([
            for (final id in ids) {'id': id}
          ]),
        });

    test('every category, each ID once under the first category that has it',
        () async {
      await load('load_recent_peers', ['111111111', '222222222']);
      await load('load_fav_peers', ['222222222', '333333333']);
      await load('load_lan_peers', ['333333333', '444444444']);
      final found = searchablePeers(
          [appCore.recentPeers, appCore.favPeers, appCore.lanPeers]);
      expect([
        for (final f in found) (f.peer.id, f.source)
      ], [
        ('111111111', PeerCategory.recent),
        ('222222222', PeerCategory.recent),
        ('333333333', PeerCategory.favorites),
        ('444444444', PeerCategory.lan),
      ]);
    });
  });

  group('peerMenu (01 P1 block F, peer_card.dart:958-1100)', () {
    List<List<PeerAction>> menu(PeerCategory c,
            {bool favorite = false, bool hasPassword = true}) =>
        peerMenu(c,
            favorite: favorite, hasPassword: hasPassword, windows: true);
    // A device whose platform is not known offers every connection type but the administrator
    // terminal (R3-Q12).
    const connect = [
      PeerAction.remoteDesktop,
      PeerAction.fileTransfer,
      PeerAction.terminal,
      PeerAction.camera,
      PeerAction.tcpTunnel,
      PeerAction.useAsExit,
      PeerAction.rdp,
      PeerAction.viaRelay,
    ];

    test('Recent: rename, favorites, saved password, "Delete"', () {
      expect(menu(PeerCategory.recent), [
        connect,
        [PeerAction.alwaysRelay, PeerAction.createShortcut],
        [PeerAction.rename, PeerAction.addFavorite, PeerAction.clearPassword],
        [PeerAction.delete],
      ]);
      expect(menu(PeerCategory.recent, favorite: true, hasPassword: false)[2],
          [PeerAction.rename, PeerAction.removeFavorite]);
    });

    test('Favorites: no danger group, "Remove from favorites" does it', () {
      expect(menu(PeerCategory.favorites, favorite: true), [
        connect,
        [PeerAction.alwaysRelay, PeerAction.createShortcut],
        [
          PeerAction.rename,
          PeerAction.removeFavorite,
          PeerAction.clearPassword
        ],
      ]);
    });

    test('LAN: wake-on-LAN and "Remove", no rename or saved password', () {
      expect(menu(PeerCategory.lan), [
        connect,
        [
          PeerAction.alwaysRelay,
          PeerAction.wakeOnLan,
          PeerAction.createShortcut
        ],
        [PeerAction.addFavorite],
        [PeerAction.remove],
      ]);
    });

    test('desktop shortcuts only on Windows', () {
      expect(
          peerMenu(PeerCategory.recent,
              favorite: false, hasPassword: false, windows: false)[1],
          [PeerAction.alwaysRelay]);
    });
  });

  group('connection types by the remote platform (LEAPGATE.md §10.18, A-P1.html)', () {
    List<PeerAction> group(String platform, {bool windows = true}) =>
        peerMenu(PeerCategory.recent,
            favorite: false,
            hasPassword: false,
            windows: windows,
            peerPlatform: platform)[0];
    const rd = PeerAction.remoteDesktop;
    const ft = PeerAction.fileTransfer;
    const relay = PeerAction.viaRelay;

    test('Windows: all, the administrator terminal after the terminal', () {
      final all = [
        rd,
        ft,
        PeerAction.terminal,
        PeerAction.terminalAdmin,
        PeerAction.camera,
        PeerAction.tcpTunnel,
        PeerAction.useAsExit,
        PeerAction.rdp,
        relay,
      ];
      expect(group(kPeerPlatformWindows), all);
      // The connect box's menu has no administrator terminal (14 §1.2).
      expect(connectMenu(kPeerPlatformWindows, windows: true),
          [for (final a in all) if (a != PeerAction.terminalAdmin) a]);
    });

    test('Linux: no administrator terminal, exit node or RDP', () {
      const linux = [
        rd,
        ft,
        PeerAction.terminal,
        PeerAction.camera,
        PeerAction.tcpTunnel,
        relay,
      ];
      expect(group(kPeerPlatformLinux), linux);
      expect(connectMenu(kPeerPlatformLinux, windows: true), linux);
    });

    test('macOS: no camera either', () {
      const mac = [rd, ft, PeerAction.terminal, PeerAction.tcpTunnel, relay];
      expect(group(kPeerPlatformMacOS), mac);
      expect(connectMenu(kPeerPlatformMacOS, windows: true), mac);
    });

    test('Android: no terminal, camera or TCP tunnel', () {
      expect(group(kPeerPlatformAndroid), [rd, ft, relay]);
      expect(connectMenu(kPeerPlatformAndroid, windows: true), [rd, ft, relay]);
    });

    test('not known: all but the administrator terminal; RDP only from Windows', () {
      const unknown = [
        rd,
        ft,
        PeerAction.terminal,
        PeerAction.camera,
        PeerAction.tcpTunnel,
        PeerAction.useAsExit,
        PeerAction.rdp,
        relay,
      ];
      expect(group(''), unknown);
      expect(connectMenu('', windows: true), unknown);
      expect(connectMenu('', windows: false),
          [for (final a in unknown) if (a != PeerAction.rdp) a]);
      expect(group(kPeerPlatformWindows, windows: false),
          isNot(contains(PeerAction.rdp)));
    });
  });

  group('PeerSelection (peer_tab_model.dart select, selectAll)', () {
    const shown = ['a', 'b', 'c', 'd', 'e'];

    test('a click flips one device', () {
      final s = PeerSelection()..start();
      s.tap('b', shown);
      s.tap('d', shown);
      expect(s.ids, {'b', 'd'});
      s.tap('b', shown);
      expect(s.ids, {'d'});
    });

    test('Shift extends from the last click with the new state', () {
      final s = PeerSelection()..start();
      s.tap('b', shown);
      s.tap('d', shown, shift: true);
      expect(s.ids, {'b', 'c', 'd'});
      s.tap('c', shown, shift: true);
      expect(s.ids, {'b'});
    });

    test('select all, and "Done" clears', () {
      final s = PeerSelection()..start();
      s.selectAll(shown);
      expect(s.ids, shown.toSet());
      s.finish();
      expect(s.active, isFalse);
      expect(s.ids, isEmpty);
    });
  });
}
