import 'package:flutter/foundation.dart';

import '../models/platform_model.dart';
import 'account.dart';
import 'account_api.dart';
import 'address_book.dart';
import 'app_window.dart';
import 'exit_api.dart';
import 'exit_directory.dart';
import 'exit_nodes.dart';
import 'group.dart';
import 'notices.dart';
import 'options.dart';
import 'prompts.dart';
import 'recent_peers.dart';
import 'session_events.dart';
import 'session_registry.dart';

/// What exists once per process (03 §3.3 item 2). Upstream built the global models inside
/// every session object (`models/model.dart:4068-4097`), timers included; here the app holds
/// them. The service, account and address book models join it with M3 and M4.
class AppCore {
  /// Made before `platformFFI.init` starts the global event stream, so none of its events is
  /// missed.
  AppCore({required this.window, bool singleSession = false})
      : sessions = SessionRegistry(singleSession: singleSession) {
    // What `PlatformFFI.tryHandle` does not take (`models/native_model.dart:274-277`).
    platformFFI.setEventCallback(events.dispatch);
    // After a login with a typed password (`src/client.rs`), upstream `models/model.dart:433-441`.
    events.on('sync_peer_hash_password_to_personal_ab', (evt) {
      final id = evt['id'];
      final hash = evt['hash'];
      if (id != null && hash != null) {
        return addressBook.syncPeerHash(id.toString(), hash.toString());
      }
    });
  }

  final AppWindow window;
  final SessionRegistry sessions;
  final toasts = Toasts();
  final options = OptionsModel();

  /// The home page's categories (M2a, M2b); the address book and team devices join with M4.
  final recentPeers = CategoryPeers.recent();
  final favPeers = CategoryPeers.favorites();
  final lanPeers = CategoryPeers.lan();

  /// The account, the address book and the team devices (M4, `LEAPGATE.md` §10.11). Built on
  /// first use; nothing reaches Rust until `account.start()`.
  late final addressBook = AddressBookModel(accountApi);
  late final group = GroupModel(accountApi);
  late final account = AccountModel(accountApi,
      others: [addressBook, group, exitDirectory]);

  /// The exit node page (M5, `LEAPGATE.md` §10.12). Nothing reaches Rust until the page opens
  /// or a device is used as an exit node.
  late final exitDirectory = ExitDirectoryModel(exitApi);
  late final exitNodes = ExitNodesModel(exitApi);

  /// What runs on the home tab's exit page (M9, `LEAPGATE.md` §10.18): the number in the
  /// navigation and on the home tab, the close and service confirmations. Only the exit nodes
  /// until M9c adds the tunnels.
  int get backgroundCount => exitNodes.runningCount;

  /// One of them waits for the user.
  bool get backgroundAttention => exitNodes.needsAttention;

  /// Notifies when [backgroundCount] or [backgroundAttention] may have changed.
  Listenable get backgroundListenable => exitNodes;

  /// The global event stream's table. The connection manager (M3) and the address book (M4)
  /// register their events here, not on a session's.
  final events = SessionEvents(stream: 'global');

  /// Set by the app once it can show dialogs (the session pages, M2a).
  late Prompter prompter;
}

/// Set once by the app's `main`; tests set their own.
late AppCore appCore;
