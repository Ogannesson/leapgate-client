// The tunnel cards of the exit page (13 §1.3, `LEAPGATE.md` §10.18): a device's TCP tunnel card
// and its RDP card, in the order they were opened, kept in memory only (not restored on restart,
// as the exit cards).
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_core.dart';
import 'tunnel_api.dart';
import 'tunnel_card.dart';

class TunnelsModel extends ChangeNotifier {
  TunnelsModel(this._api);

  final TunnelApi _api;
  final _cards = <TunnelCard>[];
  StreamSubscription? _events;

  List<TunnelCard> get cards => List.unmodifiable(_cards);

  TunnelCard? cardOf(String id, TunnelKind kind) =>
      _cards.where((c) => c.id == id && c.kind == kind).firstOrNull;

  /// The cards with a listener open (13 §1.3 block F), counted by card, not by forward.
  int get runningCount => _cards.where((c) => c.running).length;

  /// A card's question waits for the user.
  bool get needsAttention => _cards.any((c) => c.needsAttention);

  /// "TCP 隧道" and "RDP" (13 §1.1.2): the card listens and logs in at once; the device's card of
  /// [kind] when it has one. [platform] is the device list's, empty when not known;
  /// [sharedPassword] is the address book's for the device, [password] and [forceRelay] a link's.
  TunnelCard open(String id, TunnelKind kind,
      {String? name,
      String platform = '',
      String? sharedPassword,
      String password = '',
      bool forceRelay = false}) {
    final existing = cardOf(id, kind);
    if (existing != null) return existing;
    _events ??= _api.events().listen(_onEvent);
    final card = TunnelCard(this, _api, id, kind,
        name: name,
        platform: platform,
        sharedPassword: sharedPassword,
        password: password,
        forceRelay: forceRelay);
    _cards.add(card);
    card.addListener(notifyListeners);
    card.start();
    notifyListeners();
    return card;
  }

  /// For [TunnelCard.stop]: the card leaves the list.
  void drop(TunnelCard card) {
    card.removeListener(notifyListeners);
    if (_cards.remove(card)) notifyListeners();
  }

  /// By the session: a card stopped and opened again does not take the old session's events.
  void _onEvent(Map<String, dynamic> evt) {
    final session = '${evt['session_id']}';
    final card = _cards.where((c) => '${c.sessionId}' == session).firstOrNull;
    if (card == null) return;
    if (evt['state'] == 'closed') {
      card.ended();
      drop(card);
    } else {
      card.onTunnelEvent(evt);
    }
  }

  /// The local ports the tunnels listen on, but [except]'s: an exit card and another tunnel card
  /// stay off them (13 §1.3 block B, 01 P1 block I).
  Set<int> portsInUse({TunnelCard? except}) => {
        for (final c in _cards)
          if (c != except && c.kind == TunnelKind.tcp)
            for (final r in c.rows)
              if (r.listening) r.localPort
      };

  /// [port] is another tunnel card's or an exit card's (13 §1.3 block B).
  bool portTaken(int port, TunnelCard card) =>
      portsInUse(except: card).contains(port) ||
      appCore.exitNodes.cards.any((c) => c.port == port);
}
