// Skeleton (`LEAPGATE.md` §10.11); coder A rewrites upstream `models/group_model.dart` here and
// adds its source line.
import 'package:flutter/foundation.dart';

import '../models/peer_model.dart';
import 'account.dart';
import 'account_api.dart';

/// The team devices category (01 P1 block H): the people who share devices with this user and
/// their devices. Coder A fills it.
class GroupModel extends ChangeNotifier implements AccountData {
  GroupModel(this._api);

  // ignore: unused_field
  final AccountApi _api;

  /// Hidden by the built-in `disable-group-panel` option.
  bool get disabled => false;

  /// Until the first answer or cache.
  bool get loaded => false;
  bool get loading => false;

  /// Why the last pull failed; the list keeps what it had.
  ApiError? get error => null;

  /// This user first.
  List<AccountUser> get users => const [];

  /// Every device of every person, with [Peer.online] kept up to date.
  List<Peer> get peers => const [];

  /// The person picked in the list ([AccountUser.name]); null shows everyone's devices.
  String? get selectedUser => null;

  void selectUser(String? name) {}

  /// What the category lists: [peers] of [selectedUser].
  List<Peer> get shownPeers => const [];

  @override
  Future<void> loadCache() async {}

  @override
  Future<void> pull() async {}

  @override
  void reset() {}
}
