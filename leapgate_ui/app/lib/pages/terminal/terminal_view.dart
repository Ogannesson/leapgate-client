import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';

/// The terminal view in its session tab (13 §2.2): the view title bar, the terminal tabs and the
/// terminal, the connection panel over them while not connected. Coder B's; the shell mounts it
/// in the tab's view container as it mounts `FileView` (`LEAPGATE.md` §10.18). It imports nothing
/// from `shell/`.
// TODO(M9b terminal): coder B builds the view.
class TerminalViewPage extends StatefulWidget {
  const TerminalViewPage({
    super.key,
    required this.ffi,
    required this.active,
    required this.lastView,
    required this.viewSwitch,
    required this.route,
    required this.onDisconnect,
  });

  /// The `ConnType.terminal` session; `ffi.terminals` holds its tabs.
  final FFI ffi;

  /// This view is the one shown in the selected tab: it may take the keyboard.
  final bool active;

  /// No other view is open in the tab (`ConnectionPanel.lastView`).
  final bool lastView;

  /// The view switch, the same control as on the remote desktop toolbar.
  final Widget viewSwitch;

  /// The connection method mark.
  final Widget route;

  /// "断开" on the view title bar ([disconnectTerminalView]).
  final VoidCallback onDisconnect;

  @override
  State<TerminalViewPage> createState() => _TerminalViewPageState();
}

class _TerminalViewPageState extends State<TerminalViewPage> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// "断开" of the terminal view, and the tab's "×" when it is the tab's only view: closes this
/// view (the tab goes with its last view).
// TODO(M9b terminal): coder B asks first (R3-Q15).
Future<void> disconnectTerminalView(FFI view) => appCore.sessions.close(view);
