import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/leapgate/session.dart';

/// The file transfer view in its session tab (02 §2.2): the view title bar, the two panes and
/// the queue panel (`queue_panel.dart`), the connection panel over them while not connected.
/// Coder C's; the shell (coder B) mounts it in the tab's view container and passes in what
/// belongs to the tab (`LEAPGATE.md` §10.15 "外壳和文件视图的接口"). It imports nothing from
/// `shell/`.
// TODO(M7a panes): coder C builds the view.
class FileView extends StatefulWidget {
  const FileView({
    super.key,
    required this.ffi,
    required this.model,
    required this.active,
    required this.lastView,
    required this.viewSwitch,
    required this.route,
    required this.onDisconnect,
  });

  /// The `ConnType.fileTransfer` session: its connection for the connection panel, the remote
  /// device's name and platform for the pane header.
  final FFI ffi;

  /// `fileTransferOf(ffi)`; tests pass a fake.
  final FileTransferModel model;

  /// This view is the one shown in the selected tab: it may take the keyboard.
  final bool active;

  /// No other view is open in the tab: the connection panel's close button reads "关闭标签"
  /// instead of "关闭文件传输" (`ConnectionPanel.lastView`).
  final bool lastView;

  /// The view switch, the same control as on the remote desktop toolbar (B).
  final Widget viewSwitch;

  /// The connection method mark that opens the file transfer details (B).
  final Widget route;

  /// "断开" on the view title bar; the shell confirms with unfinished transfers (R2-Q28) and
  /// closes the view.
  final VoidCallback onDisconnect;

  @override
  State<FileView> createState() => _FileViewState();
}

class _FileViewState extends State<FileView> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
