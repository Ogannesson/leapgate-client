// The terminal view's tabs (13 §2.2; `LEAPGATE.md` §10.18). Coder B fills in [TerminalTabs];
// [TerminalOpen] and [terminalOpenState] are step 0's and stay as they are.
import 'package:flutter/foundation.dart';

import '../app_core.dart';
import '../session.dart';

/// The terminals of one `ConnType.terminal` session (`FFI.terminals`): numbering, closing,
/// keeping and restoring them, the clipboard requests.
// TODO(M9b terminal): coder B builds it.
class TerminalTabs extends ChangeNotifier {}

/// Whether the tab of a device has a terminal view, and which (R3-Q9): the device menu and the
/// view switch offer only one of the normal and the administrator terminal at a time.
enum TerminalOpen { none, normal, admin }

/// [TerminalOpen] for device [id], from the views open in its tab.
TerminalOpen terminalOpenState(String id) {
  final terminal = appCore.sessions
      .sessionsOf(id)
      .where((s) => s.connType == ConnType.terminal)
      .firstOrNull;
  if (terminal == null) return TerminalOpen.none;
  return terminal.terminalAdmin ? TerminalOpen.admin : TerminalOpen.normal;
}
