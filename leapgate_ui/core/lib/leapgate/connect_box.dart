import '../models/peer_model.dart';
import 'recent_peers.dart';

// Rust's own patterns (hbb_common `lib.rs` `is_ipv4_str`, `is_ipv6_str`, `is_domain_port_str`).
final _ipv4 = RegExp(
    r'^(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(:\d+)?$');
final _ipv6 = RegExp(
    r'^((([a-fA-F0-9]{1,4}:{1,2})+[a-fA-F0-9]{1,4})|(\[([a-fA-F0-9]{1,4}:{1,2})+[a-fA-F0-9]{1,4}\]:\d+))$');
final _domainPort = RegExp(
    r'^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z-]{0,61}[a-z]:\d{1,5}$',
    caseSensitive: false);
final _digits = RegExp(r'^\d+$');
// A device ID in front of `@server`: numeric, or a custom ID from that server.
final _idBeforeServer = RegExp(r'^[A-Za-z0-9_-]+$');

/// Takes off the `/r` (or `\r`) that asks for a relay (`src/ui_interface.rs` `handle_relay_id`).
String _withoutRelaySuffix(String s) =>
    s.endsWith('/r') || s.endsWith(r'\r') ? s.substring(0, s.length - 2) : s;

/// Whether the connect box input reads as something to connect to rather than a name to search
/// for (01 P1 block E, Q2): a numeric ID, an IPv4 or IPv6 address (with or without a port), a
/// `domain:port`, or `‹ID›@‹server›`. Spaces are ignored (IDs are shown in groups of three) and
/// a `/r` suffix is allowed, in front of `@` as Rust reads it (`src/client.rs` `initialize`).
bool looksLikeAddress(String input) {
  final s = input.replaceAll(' ', '');
  final at = s.indexOf('@');
  if (at >= 0) {
    return _idBeforeServer.hasMatch(_withoutRelaySuffix(s.substring(0, at))) &&
        at + 1 < s.length;
  }
  final target = _withoutRelaySuffix(s);
  return _digits.hasMatch(target) ||
      _ipv4.hasMatch(target) ||
      _ipv6.hasMatch(target) ||
      _domainPort.hasMatch(target);
}

/// Whether [peer] matches the connect box input: ID, alias, host name, user name or note
/// contains it, ignoring case. One rule for every category; upstream's connect box left out the
/// note and its list search only looked at it in the address book
/// (`flutter/lib/desktop/pages/connection_page.dart:393-404`, `flutter/lib/common.dart:1680-1700`).
/// The ID is compared without spaces, so "123 456" finds 123456789; `user@host` as a row shows
/// it counts as user name and host name together.
bool peerMatches(Peer peer, String input) {
  final q = input.trim().toLowerCase();
  if (q.isEmpty) return true;
  return peer.id.toLowerCase().contains(q.replaceAll(' ', '')) ||
      peerUserHost(peer).toLowerCase().contains(q) ||
      peer.alias.toLowerCase().contains(q) ||
      peer.hostname.toLowerCase().contains(q) ||
      peer.username.toLowerCase().contains(q) ||
      peer.note.toLowerCase().contains(q);
}

/// The connect box results for a non-empty [input]: row 0 is "Connect to ‹input›", row i is
/// `matches[i - 1]`.
class ConnectBoxSearch {
  ConnectBoxSearch(String input, List<Peer> peers)
      : matches = peers.where((p) => peerMatches(p, input)).toList() {
    defaultRow = _defaultRow(input);
  }

  /// Matching devices in the order they came (recent: most recent first).
  final List<Peer> matches;

  /// The row Enter runs before the arrow keys move (01 P1 block E): the device whose ID (or
  /// whole `user@host`) is the input; otherwise "Connect to" when the input looks like an address; otherwise the first
  /// match; "Connect to" when nothing matches.
  late final int defaultRow;

  int get rowCount => matches.length + 1;

  int _defaultRow(String input) {
    final id = input.replaceAll(' ', '');
    final userHost = input.trim().toLowerCase();
    // `user@host` copied from a row is that device, not `‹ID›@‹server›`.
    final exact = matches.indexWhere((p) =>
        p.id == id || (userHost.isNotEmpty && peerUserHost(p).toLowerCase() == userHost));
    if (exact >= 0) return exact + 1;
    if (looksLikeAddress(input) || matches.isEmpty) return 0;
    return 1;
  }
}
