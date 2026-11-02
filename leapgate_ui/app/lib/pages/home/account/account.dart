import 'package:flutter/material.dart';

import '../../../shell/tab_overlays.dart';

// The account area and the login dialog (01 P1 blocks D and K, M4, coder A; `LEAPGATE.md`
// §10.11).

/// The account area at the bottom of the home page's left column.
Widget accountArea(BuildContext context, TabOverlays overlays) =>
    const SizedBox.shrink();

/// The login dialog over the home tab; true when it signed in. The address book and the team
/// devices call it from their "signed out" state.
Future<bool> showLoginDialog(TabOverlays overlays) async => false;
