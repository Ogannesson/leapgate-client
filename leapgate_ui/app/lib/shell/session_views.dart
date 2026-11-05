import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/leapgate/prompts.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../icons/lg_icon.dart';
import '../l10n/app_localizations.dart';
import '../pages/files/file_route_details.dart';
import '../pages/files/file_view.dart';
import '../pages/session/reasons.dart';
import '../pages/session/session_names.dart';
import '../pages/session/session_page.dart';
import '../widgets/lg_menu.dart';
import '../widgets/lg_session_toolbar.dart';
import 'navigation.dart';
import 'tab_overlays.dart';

// The views of one session tab (01 §2.1 "会话标签的内容", §3.2 block A; `LEAPGATE.md` §10.15
// "外壳和文件视图的接口"): the remote desktop and the file transfer of one device, one shown at a
// time. M7a opens these two kinds; the terminal and the camera are round 3.

/// The file transfer model of a `ConnType.fileTransfer` view; tests set fakes.
FileTransferModel Function(FFI view) fileTransferFor = fileTransferOf;

bool isFileView(FFI view) => view.connType == ConnType.fileTransfer;

/// Queued, counting, in progress and waiting for confirmation, over the file transfer views of
/// [views]: the "‹N› 个传输尚未完成" of the close confirmations (02 §3.1).
int unfinishedTransfers(Iterable<FFI> views) => views
    .where(isFileView)
    .fold(0, (n, v) => n + fileTransferFor(v).jobs.unfinished);

/// The name of a view in the view switch and the tab's hover.
String viewName(AppLocalizations l10n, ConnType type) =>
    type == ConnType.fileTransfer
    ? l10n.ftFileTransfer
    : l10n.toolbarRemoteDesktop;

/// "断开" of the file transfer view, and the tab's "×" when it is the tab's only view: with
/// unfinished transfers it asks first (R2-Q28), then closes this view (the tab goes with its
/// last view).
Future<void> disconnectFileView(FFI view) async {
  final unfinished = fileTransferFor(view).jobs.unfinished;
  if (unfinished > 0 &&
      await appCore.prompter.ask(
            FtDisconnectPrompt(unfinished),
            session: view,
          ) !=
          true) {
    return;
  }
  await appCore.sessions.close(view);
}

/// The views of the tab, in the order they opened, [current] shown (an [IndexedStack] keeps the
/// others). Only the current view of the selected tab takes the keyboard: the remote desktop
/// gets `active` false otherwise, which releases the keyboard hook and, through V1, stops the
/// frames (`SessionPage.didUpdateWidget`).
class SessionTabView extends StatelessWidget {
  const SessionTabView({
    super.key,
    required this.views,
    required this.current,
    required this.selected,
    required this.overlays,
  });

  final List<FFI> views;
  final FFI current;

  /// The tab is the selected one.
  final bool selected;
  final TabOverlays overlays;

  Widget _view(FFI view) {
    final active = selected && view == current;
    if (!isFileView(view)) {
      return SessionPage(ffi: view, active: active, overlays: overlays);
    }
    return FileView(
      ffi: view,
      model: fileTransferFor(view),
      active: active,
      lastView: views.length == 1,
      viewSwitch: SessionViewSwitch(ffi: view),
      route: FileRouteMark(ffi: view),
      onDisconnect: () => disconnectFileView(view),
    );
  }

  @override
  Widget build(BuildContext context) => IndexedStack(
    index: views.indexOf(current),
    sizing: StackFit.expand,
    children: [
      for (final v in views)
        KeyedSubtree(
          key: ObjectKey(v),
          child: TickerMode(
            enabled: v == current,
            child: ExcludeFocus(excluding: v != current, child: _view(v)),
          ),
        ),
    ],
  );
}

/// The view switch (01 §2.1, P2 block B item 2; 02 §2.2 block A item 1), the same control on the
/// remote desktop toolbar and the file transfer view's title bar: every kind of view, the one
/// shown ([ffi]'s) checked, an open one with its connection method, the file transfer with its
/// progress (02 §3.2), one not open "未打开". Picking one shows it, opening it first when needed.
class SessionViewSwitch extends StatelessWidget {
  const SessionViewSwitch({super.key, required this.ffi});

  /// The view it is shown in.
  final FFI ffi;

  static const _kinds = [ConnType.defaultConn, ConnType.fileTransfer];

  String _state(AppLocalizations l10n, FFI? view) {
    if (view == null) return l10n.ftViewNotOpen;
    final conn = view.connection;
    final String route;
    if (conn.stage == ConnStage.failed) {
      route = conn.retryCountdown != null
          ? l10n.sessionInterrupted
          : isDisconnected(conn.reason!)
          ? l10n.sessionDisconnected
          : l10n.sessionFailed;
    } else if (!showsRoute(conn)) {
      route = l10n.sessionConnecting;
    } else {
      route = conn.direct! ? l10n.sessionDirect : l10n.sessionRelayed;
    }
    final progress = isFileView(view)
        ? fileTransferFor(view).jobs.summary.progress
        : null;
    return [
      route,
      if (conn.secure == false && showsRoute(conn)) l10n.sessionUnencrypted,
      if (progress != null) '${(progress * 100).floor()}%',
    ].join(' · ');
  }

  void _show(ConnType kind) {
    if (kind == ffi.connType) return;
    kind == ConnType.fileTransfer
        ? mainNavigation.openFileTransfer(ffi.id)
        : mainNavigation.connect(ffi.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: appCore.sessions,
      builder: (context, _) {
        final views = appCore.sessions.sessionsOf(ffi.id);
        return ListenableBuilder(
          listenable: Listenable.merge([
            for (final v in views) ...[
              v.connection,
              if (isFileView(v)) fileTransferFor(v).jobs,
            ],
          ]),
          builder: (context, _) => LgToolbarMenuButton(
            label: viewName(l10n, ffi.connType),
            icon: isFileView(ffi) ? LgIcons.files : LgIcons.monitor,
            items: [
              for (final kind in _kinds)
                LgMenuItem(
                  label: viewName(l10n, kind),
                  checked: kind == ffi.connType,
                  hint: _state(
                    l10n,
                    views.where((v) => v.connType == kind).firstOrNull,
                  ),
                  onPressed: () => _show(kind),
                ),
            ],
          ),
        );
      },
    );
  }
}
