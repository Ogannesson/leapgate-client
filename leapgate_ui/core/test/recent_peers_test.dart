import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Peer peer(String id, {String alias = '', String hostname = ''}) =>
    Peer.fromJson({'id': id, 'alias': alias, 'hostname': hostname});

void main() {
  group('RecentPeers', () {
    late FakeBind bind;
    late RecentPeers recent;
    setUp(() {
      bind = installFakes().bind;
      recent = appCore.recentPeers;
      addTearDown(recent.dispose);
    });

    test('loading until Rust pushes the list, even an empty one', () async {
      var notified = 0;
      recent.addListener(() => notified++);
      recent.load();
      expect(bind.callsTo(#mainLoadRecentPeers), hasLength(1));
      expect(recent.loaded, isFalse);

      await platformFFI.tryHandle({'name': 'load_recent_peers', 'peers': ''});
      expect(recent.loaded, isTrue);
      expect(recent.peers, isEmpty);
      expect(notified, greaterThan(0));

      await platformFFI.tryHandle({
        'name': 'load_recent_peers',
        'peers': jsonEncode([
          {'id': '123456789', 'alias': '书房台式机'},
          {'id': '234567891'},
        ]),
      });
      expect(recent.peers.map((p) => p.id), ['123456789', '234567891']);
    });

    test('a device has no online state until a query answers for it', () async {
      await platformFFI.tryHandle({
        'name': 'load_recent_peers',
        'peers': jsonEncode([
          {'id': '123456789'},
          {'id': '234567891'},
          {'id': '345678912'},
        ]),
      });
      expect(recent.hasOnlineState('123456789'), isFalse);

      await platformFFI.tryHandle({
        'name': 'callback_query_onlines',
        'onlines': '123456789',
        'offlines': '234567891',
      });
      expect(recent.hasOnlineState('123456789'), isTrue);
      expect(recent.peers[0].online, isTrue);
      expect(recent.hasOnlineState('234567891'), isTrue);
      expect(recent.peers[1].online, isFalse);
      expect(recent.hasOnlineState('345678912'), isFalse);
    });
  });

  group('OnlineQuery (peers_view.dart:313-346)', () {
    test(
        'asks for the rows on screen once they stood for a second, '
        'then every 6 s while active', () {
      fakeAsync((async) {
        final asked = <List<String>>[];
        final q = OnlineQuery(asked.add)..start();
        q
          ..show('123456789')
          ..show('234567891');
        async.elapse(const Duration(milliseconds: 900));
        expect(asked, isEmpty);
        async.elapse(const Duration(milliseconds: 600));
        expect(asked, [
          ['123456789', '234567891']
        ]);

        async.elapse(const Duration(seconds: 6));
        expect(asked, hasLength(2));

        // The window lost focus: no more repeats.
        q.active = false;
        async.elapse(const Duration(seconds: 30));
        expect(asked, hasLength(2));

        // Back in focus.
        q.active = true;
        async.elapse(const Duration(milliseconds: 300));
        expect(asked, hasLength(3));
        q.dispose();
      });
    });

    test('rows scrolled off are not asked about', () {
      fakeAsync((async) {
        final asked = <List<String>>[];
        final q = OnlineQuery(asked.add)..start();
        q
          ..show('123456789')
          ..show('234567891');
        async.elapse(const Duration(seconds: 2));
        q.hide('123456789');
        async.elapse(const Duration(seconds: 2));
        expect(asked.last, ['234567891']);
        q.dispose();
      });
    });
  });

  test('the row name: alias, host name, then the formatted ID', () {
    expect(
        peerDisplayName(peer('123456789', alias: '书房', hostname: 'PC')), '书房');
    expect(peerDisplayName(peer('123456789', hostname: 'PC')), 'PC');
    expect(peerDisplayName(peer('123456789')), '123 456 789');
    expect(formatPeerId('1234567890'), '1 234 567 890');
    expect(formatPeerId('123456789/r'), '123 456 789/r');
    expect(formatPeerId('office-pc'), 'office-pc');
  });
}
