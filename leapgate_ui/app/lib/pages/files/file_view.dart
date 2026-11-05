import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_view_bar.dart';
import '../session/connection_panel.dart';
import 'drag_drop.dart';
import 'pane.dart';
import 'queue_panel.dart';

/// The gap between the panes, which is the divider that drags (`.cols` gap in the mockup), and
/// how far it goes to either side.
const kFileDividerWidth = LgSpace.s3;
const kFileDividerWidthCompact = LgSpace.s2;
const kFileSplitMin = 0.35;
const kFileDividerKey = ValueKey('file pane divider');

/// Lower windows get the smallest window's rows, a step lower (`.frame.mn` of the mockup, drawn
/// at 960 × 600); the same line as the home page's short window.
const kFileCompactBelowHeight = 700.0;

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

  /// The connection was up at the last look: the list takes the keys when it comes up.
  late bool _connected = _isConnected;

  bool get _isConnected => widget.ffi.connection.stage == ConnStage.connected;

  @override
  void initState() {
    super.initState();
    _areas();
    widget.ffi.connection.addListener(_onConnection);
    if (_connected) _focusLocal();
  }

  @override
  void didUpdateWidget(FileView old) {
    super.didUpdateWidget(old);
    if (!identical(old.model, widget.model)) {
      _local.dispose();
      _remote.dispose();
      _areas();
    }
    if (!identical(old.ffi.connection, widget.ffi.connection)) {
      old.ffi.connection.removeListener(_onConnection);
      widget.ffi.connection.addListener(_onConnection);
      _connected = _isConnected;
    }
    // Shown again: the keys work without a click first. Not while the connection panel is up,
    // which takes the focus for its own field.
    if (widget.active && !old.active && _isConnected) _focusLocal();
  }

  @override
  void dispose() {
    widget.ffi.connection.removeListener(_onConnection);
    _local.dispose();
    _remote.dispose();
    _localFocus.dispose();
    _remoteFocus.dispose();
    super.dispose();
  }

  /// Connected (the first time, or again after the panel): the local list has the keys.
  void _onConnection() {
    final connected = _isConnected;
    if (connected && !_connected) _focusLocal();
    _connected = connected;
  }

  void _focusLocal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) _localFocus.requestFocus();
    });
  }

  void _areas() {
    _local = PaneDropArea(widget.model.local);
    _remote = PaneDropArea(widget.model.remote);
  }

  static double _savedSplit() {
    final v = double.tryParse(appCore.options.local.get(kOptionFtDivider));
    return v == null ? 0.5 : v.clamp(kFileSplitMin, 1 - kFileSplitMin);
  }

  Widget _panes(bool compact) => LayoutBuilder(
    builder: (context, constraints) {
      final divider = compact ? kFileDividerWidthCompact : kFileDividerWidth;
      final width = constraints.maxWidth;
      final left = (width - divider) * _split;
      return Row(
        children: [
          SizedBox(
            width: left,
            child: FilePaneView(
              ffi: widget.ffi,
              pane: widget.model.local,
              other: widget.model.remote,
              area: _local,
              otherArea: _remote,
              listFocus: _localFocus,
              otherListFocus: _remoteFocus,
              compact: compact,
            ),
          ),
          MouseRegion(
            key: kFileDividerKey,
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => setState(() {
                _split = ((left + d.delta.dx) / (width - divider)).clamp(
                  kFileSplitMin,
                  1 - kFileSplitMin,
                );
              }),
              onHorizontalDragEnd: (_) => appCore.options.local.set(
                kOptionFtDivider,
                _split.toStringAsFixed(3),
              ),
              child: SizedBox(width: divider, height: double.infinity),
            ),
          ),
          Expanded(
            child: FilePaneView(
              ffi: widget.ffi,
              pane: widget.model.remote,
              other: widget.model.local,
              area: _remote,
              otherArea: _local,
              listFocus: _remoteFocus,
              otherListFocus: _localFocus,
              compact: compact,
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
    final compact = MediaQuery.sizeOf(context).height < kFileCompactBelowHeight;
    // The page's padding and the gap above the queue (`.vb`, `.frame.mn .vb`).
    final gap = compact ? LgSpace.s1 : LgSpace.s3;
    final padding = compact
        ? const EdgeInsets.fromLTRB(
            LgSpace.s2,
            LgSpace.s1,
            LgSpace.s2,
            LgSpace.s2,
          )
        : const EdgeInsets.fromLTRB(
            LgSpace.s4,
            LgSpace.s3,
            LgSpace.s4,
            LgSpace.s4,
          );
    return SystemDropTarget(
      enabled: widget.active,
      areas: [_local, _remote],
      onDrop: (paths, to) => widget.model.uploadPaths(paths, to: to),
      child: ExcludeFocus(
        excluding: !widget.active,
        child: ColoredBox(
          color: t.colors.bg,
          child: Column(
            children: [
              LgViewBar(
                viewSwitch: widget.viewSwitch,
                route: widget.route,
                disconnectLabel: l10n.filesDisconnect,
                onDisconnect: widget.onDisconnect,
                compact: compact,
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: conn,
                  builder: (context, _) => Stack(
                    children: [
                      Padding(
                        padding: padding,
                        child: Column(
                          children: [
                            Expanded(child: _panes(compact)),
                            SizedBox(height: gap),
                            FileQueuePanel(
                              jobs: widget.model.jobs,
                              connection: conn,
                            ),
                          ],
                        ),
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
