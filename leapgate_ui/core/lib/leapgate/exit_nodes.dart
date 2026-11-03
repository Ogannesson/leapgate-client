// The exit nodes in use (01 P1 block I "正在使用", `LEAPGATE.md` §10.12): one card per device, in
// the order they were added, kept in memory only (not restored on restart).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../consts.dart';
import 'app_core.dart';
import 'exit_api.dart';
import 'exit_card.dart';

/// The first port offered; clear of the usual proxy ports (1080, 7890, 10808/10809, 8080) and
/// of Windows' dynamic range from 49152 (`flutter/lib/leapgate/exit_tunnel.dart`).
const kExitFirstPort = 21180;

enum ExitPortError {
  /// Not in 1~65535; 0 is refused as well, as the old UI did.
  invalid,

  /// Another card listens on it.
  taken,
}

final _idChars = RegExp(r'^[A-Za-z0-9_-]+$');

/// What "Use as exit node" takes (08 M5-12): a device ID or `ID@server`, the ID of letters,
/// digits, `_` and `-`, spaces ignored; not an IP address, a `domain:port` or `/r`. The server
/// takes no `?` or `/`: Rust rewrites `?key=…` and a trailing `/r` when it logs in, and the card
/// would not match its ID.
bool isExitId(String input) {
  final s = input.replaceAll(' ', '');
  final at = s.indexOf('@');
  if (at < 0) return _idChars.hasMatch(s);
  final server = s.substring(at + 1);
  return _idChars.hasMatch(s.substring(0, at)) &&
      server.isNotEmpty &&
      !server.contains(RegExp(r'[@?/]'));
}

class ExitNodesModel extends ChangeNotifier {
  ExitNodesModel(this._api);

  final ExitApi _api;
  final _cards = <ExitCard>[];
  StreamSubscription? _events;

  List<ExitCard> get cards => List.unmodifiable(_cards);

  ExitCard? cardOf(String id) => _cards.where((c) => c.id == id).firstOrNull;

  /// The cards whose local listener is open (M5-8): the navigation's and the home tab's
  /// number, and the close dialog's.
  int get runningCount => _cards.where((c) => c.running).length;

  /// A card waits for the user (M5-8).
  bool get needsAttention => _cards.any((c) => const {
        ExitCardState.password,
        ExitCardState.twoFactor,
        ExitCardState.waitAccept,
      }.contains(c.state));

  /// "Use" (01 P1 block I, Q10): the card listens and logs in at once; the device's card when
  /// it has one. [sharedPassword] is the address book's for the device.
  ExitCard use(String id, {String? name, String? sharedPassword}) {
    final existing = cardOf(id);
    if (existing != null) return existing;
    _events ??= _api.events().listen(_onEvent);
    final card = ExitCard(this, _api, id, _portFor(id),
        name: name, sharedPassword: sharedPassword);
    _cards.add(card);
    card.addListener(notifyListeners);
    card.start();
    notifyListeners();
    return card;
  }

  Future<void> remove(String id) async => cardOf(id)?.stop();

  /// For [ExitCard.stop]: the card leaves the list.
  void drop(ExitCard card) {
    card.removeListener(notifyListeners);
    if (_cards.remove(card)) notifyListeners();
  }

  /// By the session when E2 names it, so a card stopped and used again does not take the old
  /// session's events.
  void _onEvent(Map<String, dynamic> evt) {
    final session = evt['session_id'];
    final card = session == null
        ? cardOf('${evt['id']}')
        : _cards.where((c) => '${c.sessionId}' == '$session').firstOrNull;
    if (card == null) return;
    if (evt['state'] == 'closed') {
      card.ended();
      drop(card);
    } else {
      card.onExitEvent(evt);
    }
  }

  /// [port] for [card]'s listener, or why not.
  ExitPortError? portError(int port, ExitCard card) {
    if (port < 1 || port > 65535) return ExitPortError.invalid;
    if (_cards.any((c) => c != card && c.port == port)) {
      return ExitPortError.taken;
    }
    return null;
  }

  /// The port this device keeps (M5-6): the one it had, unless another card holds it; a new
  /// one from [kExitFirstPort] skips the cards' ports and those other devices keep.
  int _portFor(String id) {
    final ports = _ports();
    final used = {for (final c in _cards) c.port};
    final kept = ports[id];
    if (kept != null && !used.contains(kept)) return kept;
    final taken = {
      ...used,
      for (final e in ports.entries)
        if (e.key != id) e.value
    };
    var port = kExitFirstPort;
    while (taken.contains(port)) {
      port++;
    }
    savePort(id, port);
    return port;
  }

  Map<String, int> _ports() {
    try {
      final m = jsonDecode(appCore.options.local.get(kOptionLeapgateExitPorts))
          as Map;
      return {
        for (final e in m.entries)
          if (e.value is int) '${e.key}': e.value as int
      };
    } on FormatException {
      return {};
    } on TypeError {
      return {};
    }
  }

  void savePort(String id, int port) {
    final ports = _ports()..[id] = port;
    unawaited(
        appCore.options.local.set(kOptionLeapgateExitPorts, jsonEncode(ports)));
  }
}
