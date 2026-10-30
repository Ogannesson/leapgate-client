import 'package:flutter/foundation.dart';

/// How the home page and links open sessions and switch tabs (M2a, `LEAPGATE.md` §10.8). The
/// session block implements it in the main window; the home block only calls it.
abstract class MainNavigation {
  /// Opens the remote desktop view of [id], or switches to its tab when it is already open
  /// (01 §4.1 stage 1). [id] is as typed: spaces and a `/r` suffix (which turns into
  /// [forceRelay]) are handled here, the way upstream `common.dart` `connect` does.
  void connect(String id,
      {String password = '',
      bool isSharedPassword = false,
      bool forceRelay = false});

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
