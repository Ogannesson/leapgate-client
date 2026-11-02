// Skeleton (`LEAPGATE.md` §10.11); coder B rewrites upstream `models/ab_model.dart` here (no
// `LegacyAb`, IQ8) and adds its source line.
import 'package:flutter/foundation.dart';

import '../models/peer_model.dart';
import 'account.dart';
import 'account_api.dart';

/// The address book category (01 P1 block G): the personal book and the shared ones, the
/// current book's devices and tags. Coder B fills it; the members below are what the other lanes
/// use, B adds the rest.
class AddressBookModel extends ChangeNotifier implements AccountData {
  AddressBookModel(this._api);

  // ignore: unused_field
  final AccountApi _api;

  /// Hidden by the built-in `disable-ab` option.
  bool get disabled => false;

  /// Until the first answer or cache.
  bool get loaded => false;
  bool get loading => false;

  /// The server has no address book (`ab/personal` 404, 07 §4.4).
  bool get unsupported => false;

  /// Why the last pull failed; the list keeps what it had.
  ApiError? get pullError => null;

  /// The personal book first, then the shared ones by name.
  List<AbProfile> get books => const [];

  /// Null until the list arrives.
  AbProfile? get current => null;

  bool isPersonal(AbProfile book) => false;

  /// The current book's devices, with [Peer.online] kept up to date.
  List<Peer> get peers => const [];

  /// What the category lists: [peers] through the tag filter.
  List<Peer> get shownPeers => const [];

  /// Every loaded book's devices, each ID once, for the connect box (01 P1 block E).
  List<Peer> get allPeers => const [];

  bool get canWrite => false;

  /// The books "Add to address book" offers.
  List<AbProfile> get writableBooks => const [];

  /// The shared password of [id] in the current shared book, to connect with; null in the
  /// personal book or when none is stored (upstream `getdefaultSharedPassword`).
  String? sharedPasswordOf(String id) => null;

  /// Rust's `sync_peer_hash_password_to_personal_ab`: stores [hash] for [id] in the personal book
  /// when [id] is in it (upstream `changePersonalHashPassword`).
  Future<void> syncPeerHash(String id, String hash) async {}

  @override
  Future<void> loadCache() async {}

  @override
  Future<void> pull() async {}

  @override
  void reset() {}
}
