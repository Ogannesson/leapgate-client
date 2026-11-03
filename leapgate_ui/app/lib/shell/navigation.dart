import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/exit_nodes.dart' show isExitId;
import 'package:flutter_hbb/leapgate/recent_peers.dart' show PeerCategory;

/// How the home page and links open sessions and switch tabs (M2a, `LEAPGATE.md` §10.8). The
/// session block implements it in the main window; the home block only calls it.
abstract class MainNavigation {
  /// Opens the remote desktop view of [id], or switches to its tab when it is already open
  /// (01 §4.1 stage 1). [id] is as typed: spaces and a `/r` suffix (which turns into
  /// [forceRelay]) are handled here, the way upstream `common.dart` `connect` does.
  /// [switchUuid] comes only with a link (switch sides).
  void connect(String id,
      {String password = '',
      bool isSharedPassword = false,
      bool forceRelay = false,
      String switchUuid = ''});

  /// Switches to the home tab. With [focusConnectBox] the cursor goes into the connect box
  /// ("+" on the title bar, 01 §2.1); [connectBoxText], when given, replaces its text, all
  /// selected ("修改 ID" on the connection panel, `04-M2a拆法.md` §5.1).
  void showHome({bool focusConnectBox = false, String? connectBoxText});
}

/// Set by the main window; tests set a fake.
late MainNavigation mainNavigation;

/// Requests to put the cursor into the connect box. The home page listens; [MainNavigation]
/// implementations call [request].
class ConnectBoxFocusRequests extends ChangeNotifier {
  /// Text to put into the box, all selected; null keeps what is there.
  String? text;

  void request({String? text}) {
    this.text = text;
    notifyListeners();
  }
}

final connectBoxFocusRequests = ConnectBoxFocusRequests();

/// Requests to show the exit page scrolled to a card. The home page switches to the exit page;
/// the exit page takes [id] once it is built.
class ExitPageRequests extends ChangeNotifier {
  ({String id, bool highlight})? _request;

  /// The card to scroll to, and whether to mark it, once; null when there is none.
  ({String id, bool highlight})? take() {
    final request = _request;
    _request = null;
    return request;
  }

  void request(String id, {bool highlight = false}) {
    _request = (id: id, highlight: highlight);
    notifyListeners();
  }
}

final exitPageRequests = ExitPageRequests();

/// "Use as exit node" in a device menu or the connect box (08 M5-9): as "Use" in the
/// directory, the card is made and logs in at once; a device with a card already is only
/// shown, marked. From the address book with the shared password the book stores, as
/// [category] says (`connectPeer`).
void useAsExit(String id, {String? name, PeerCategory? category}) {
  if (!isExitId(id)) return;
  id = id.replaceAll(' ', '');
  final had = appCore.exitNodes.cardOf(id) != null;
  appCore.exitNodes.use(id,
      name: name,
      sharedPassword: category == PeerCategory.addressBook
          ? appCore.addressBook.sharedPasswordOf(id)
          : null);
  mainNavigation.showHome();
  exitPageRequests.request(id, highlight: had);
}
