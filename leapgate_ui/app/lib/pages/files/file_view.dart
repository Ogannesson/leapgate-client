import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_button.dart';
import '../session/connection_panel.dart';
import 'drag_drop.dart';
import 'pane.dart';
import 'queue_panel.dart';

/// The divider between the panes, and how far it goes to either side.
const kFileDividerWidth = 7.0;
const kFileSplitMin = 0.35;

/// The file transfer view in its session tab (02 §2.2): the view title bar, the two panes and
/// the queue panel (`queue_panel.dart`), the connection panel over them while not connected.
/// Coder C's; the shell (coder B) mounts it in the tab's view container and passes in what
/// belongs to the tab (`LEAPGATE.md` §10.15 "外壳和文件视图的接口"). It imports nothing from
/// `shell/`.
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
  final _localFocus = FocusNode(debugLabel: 'local files');
  final _remoteFocus = FocusNode(debugLabel: 'remote files');
  late PaneDropArea _local;
  late PaneDropArea _remote;

  /// The local pane's share of the width (02 §2.2 "布局": remembered on this device).
  late double _split = _savedSplit();

  @override
  void initState() {
    super.initState();
    _areas();
  }

  @override
  void didUpdateWidget(FileView old) {
    super.didUpdateWidget(old);
    if (!identical(old.model, widget.model)) {
      _local.dispose();
      _remote.dispose();
      _areas();
    }
    // Shown again: the keys work without a click first. Not while the connection panel is up,
    // which takes the focus for its own field.
    if (widget.active &&
        !old.active &&
        widget.ffi.connection.stage == ConnStage.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) _localFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _local.dispose();
    _remote.dispose();
    _localFocus.dispose();
    _remoteFocus.dispose();
    super.dispose();
  }

  void _areas() {
    _local = PaneDropArea(widget.model.local);
    _remote = PaneDropArea(widget.model.remote);
  }

  static double _savedSplit() {
    final v = double.tryParse(appCore.options.local.get(kOptionFtDivider));
    return v == null ? 0.5 : v.clamp(kFileSplitMin, 1 - kFileSplitMin);
  }

  Widget _titleBar(AppLocalizations l10n, LgTokens t) => Container(
    height: t.sizes.bar,
    padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: t.colors.border)),
    ),
    child: Row(
      children: [
        widget.viewSwitch,
        const SizedBox(width: LgSpace.s2),
        widget.route,
        const Spacer(),
        LgButton(label: l10n.filesDisconnect, onPressed: widget.onDisconnect),
      ],
    ),
  );

  Widget _panes(LgTokens t) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final left = (width - kFileDividerWidth) * _split;
      return Row(
        children: [
          SizedBox(
            width: left,
            child: FilePaneView(
              ffi: widget.ffi,
              pane: widget.model.local,
              other: widget.model.remote,
              area: _local,
              listFocus: _localFocus,
              otherListFocus: _remoteFocus,
            ),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => setState(() {
                _split = ((left + d.delta.dx) / (width - kFileDividerWidth))
                    .clamp(kFileSplitMin, 1 - kFileSplitMin);
              }),
              onHorizontalDragEnd: (_) => appCore.options.local.set(
                kOptionFtDivider,
                _split.toStringAsFixed(3),
              ),
              child: SizedBox(
                width: kFileDividerWidth,
                child: Center(
                  child: Container(width: 1, color: t.colors.border),
                ),
              ),
            ),
          ),
          Expanded(
            child: FilePaneView(
              ffi: widget.ffi,
              pane: widget.model.remote,
              other: widget.model.local,
              area: _remote,
              listFocus: _remoteFocus,
              otherListFocus: _localFocus,
            ),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final conn = widget.ffi.connection;
    return SystemDropTarget(
      enabled: widget.active,
      areas: [_local, _remote],
      onDrop: (paths, to) => widget.model.uploadPaths(paths, to: to),
      child: ExcludeFocus(
        excluding: !widget.active,
        child: ColoredBox(
          color: t.colors.surface,
          child: Column(
            children: [
              _titleBar(l10n, t),
              Expanded(
                child: ListenableBuilder(
                  listenable: conn,
                  builder: (context, _) => Stack(
                    children: [
                      Column(
                        children: [
                          Expanded(child: _panes(t)),
                          FileQueuePanel(jobs: widget.model.jobs),
                        ],
                      ),
                      if (conn.stage != ConnStage.connected) ...[
                        const ModalBarrier(dismissible: false),
                        ConnectionPanel(
                          ffi: widget.ffi,
                          active: widget.active,
                          lastView: widget.lastView,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
