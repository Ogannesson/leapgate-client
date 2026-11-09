import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/file_transfer/jobs.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/leapgate/peer_list.dart' show PeerAction, connectMenu;
import 'package:flutter_hbb/leapgate/prompts.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../icons/lg_icon.dart';
import '../l10n/app_localizations.dart';
import '../pages/files/file_route_details.dart';
import '../pages/files/file_view.dart';
import '../pages/session/reasons.dart';
import '../pages/session/session_names.dart';
import '../pages/session/session_page.dart';
import '../pages/terminal/terminal_view.dart';
import '../widgets/lg_file_marks.dart';
import '../widgets/lg_menu.dart';
import '../widgets/lg_session_toolbar.dart';
import '../widgets/lg_status.dart';
import 'navigation.dart';
import 'tab_menu.dart';
import 'tab_overlays.dart';

// The views of one session tab (01 §2.1 "会话标签的内容", §3.2 block A; `LEAPGATE.md` §10.15
// "外壳和文件视图的接口", §10.18): the remote desktop, file transfer, terminal and camera of one
// device, one shown at a time (13 §0.4 ②).

/// The file transfer model of a `ConnType.fileTransfer` view; tests set fakes.
FileTransferModel Function(FFI view) fileTransferFor = fileTransferOf;

bool isFileView(FFI view) => view.connType == ConnType.fileTransfer;

/// A view whose content is the remote image: the floating toolbar, full screen and a chat of its
/// own (13 §0.4 ③). The remote desktop and the camera.
bool hasImage(FFI view) => switch (view.connType) {
  ConnType.defaultConn || ConnType.viewCamera => true,
  _ => false,
};

/// A view with the view title bar (`LgViewBar`): the file transfer and the terminal.
bool usesViewBar(FFI view) => switch (view.connType) {
  ConnType.fileTransfer || ConnType.terminal => true,
  _ => false,
};

/// The kinds of view the tab of device [id] offers, in the view switch's order: the terminal
/// and the camera only where the remote platform is not known to lack them (R3-Q12, the device
/// menu's rule); the platform is known once a view of the tab has its peer info. A view that is
/// open stays listed.
List<ConnType> viewKinds(String id) {
  final views = appCore.sessions.sessionsOf(id);
  final platform = views
      .map((v) => v.ffiModel.pi.platform)
      .firstWhere((p) => p.isNotEmpty, orElse: () => '');
  final offered = connectMenu(platform);
  bool open(ConnType kind) => views.any((v) => v.connType == kind);
  return [
    ConnType.defaultConn,
    ConnType.fileTransfer,
    if (offered.contains(PeerAction.terminal) || open(ConnType.terminal))
      ConnType.terminal,
    if (offered.contains(PeerAction.camera) || open(ConnType.viewCamera))
      ConnType.viewCamera,
  ];
}

LgIcons viewIcon(ConnType type) => switch (type) {
  ConnType.fileTransfer => LgIcons.files,
  ConnType.terminal => LgIcons.terminal,
  ConnType.viewCamera => LgIcons.camera,
  _ => LgIcons.monitor,
};

/// Queued, counting, in progress and waiting for confirmation, over the file transfer views of
/// [views]: the "‹N› 个传输尚未完成" of the close confirmations (02 §3.1).
int unfinishedTransfers(Iterable<FFI> views) => views
    .where(isFileView)
    .fold(0, (n, v) => n + fileTransferFor(v).jobs.unfinished);

/// The name of a view in the view switch and the tab's hover; [terminalAdmin] names the
/// administrator terminal (13 §2.2.2 block A).
String viewName(
  AppLocalizations l10n,
  ConnType type, {
  bool terminalAdmin = false,
}) => switch (type) {
  ConnType.fileTransfer => l10n.ftFileTransfer,
  ConnType.terminal =>
    terminalAdmin ? l10n.viewTerminalAdmin : l10n.viewTerminal,
  ConnType.viewCamera => l10n.viewCamera,
  _ => l10n.toolbarRemoteDesktop,
};

/// What the transfer ring or the reminder mark of [summary] means to a screen reader ("文件传输
/// 45%", "有替换确认等待处理"), on the tab and the view switch; null when neither shows.
String? transferMarkLabel(AppLocalizations l10n, FileJobSummary summary) {
  if (summary.waitingConfirm > 0) return l10n.ftMarkAttention;
  final progress = summary.progress;
  return progress == null
      ? null
      : l10n.ftMarkProgress((progress * 100).floor());
}

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
    switch (view.connType) {
      // The terminal view's connection mark and its details are the file transfer's (13 §2.2.2
      // block A item 2); it keeps the keyboard off under a dialog as the file view does.
      case ConnType.terminal:
        return ListenableBuilder(
          listenable: overlays,
          builder: (context, _) => TerminalViewPage(
            ffi: view,
            active: active &&
                !overlays.isOpen(view.id) &&
                !overlays.isOpen(kWindowScope),
            lastView: views.length == 1,
            viewSwitch: SessionViewSwitch(ffi: view),
            route: FileRouteMark(ffi: view),
            onDisconnect: () => disconnectTerminalView(view),
          ),
        );
      case ConnType.fileTransfer:
        break;
      // The remote desktop, and the camera on the same page (R3-Q16).
      default:
        return SessionPage(
          ffi: view,
          active: active,
          overlays: overlays,
          lastView: views.length == 1,
        );
    }
    // Not under a dialog of the tab or the window either: the file view would put the keyboard
    // on its list behind it (Enter there would transfer again); closed, the list gets it back.
    return ListenableBuilder(
      listenable: overlays,
      builder: (context, _) => FileView(
        ffi: view,
        model: fileTransferFor(view),
        active: active &&
            !overlays.isOpen(view.id) &&
            !overlays.isOpen(kWindowScope),
        lastView: views.length == 1,
        viewSwitch: SessionViewSwitch(ffi: view),
        route: FileRouteMark(ffi: view),
        onDisconnect: () => disconnectFileView(view),
      ),
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
/// image views' toolbar and the title bar of the file transfer and terminal views: every kind of
/// view the tab offers ([viewKinds]), the one shown ([ffi]'s) checked, an open one with its
/// connection method, the file transfer with its progress (02 §3.2), the remote desktop and the
/// camera with their unread messages (R3-Q17), one not open "未打开". Picking one shows it,
/// opening it first when needed.
class SessionViewSwitch extends StatelessWidget {
  const SessionViewSwitch({super.key, required this.ffi});

  /// The view it is shown in.
  final FFI ffi;

  /// The connection method of an open view, or the state it is in.
  Widget _state(AppLocalizations l10n, FFI view) {
    final conn = view.connection;
    if (conn.stage == ConnStage.failed) {
      return conn.retryCountdown != null
          ? LgStatusText(LgStatus.warning, l10n.sessionInterrupted)
          : isDisconnected(conn.reason!)
          ? LgStatusText(LgStatus.offline, l10n.sessionDisconnected)
          : LgStatusText(LgStatus.warning, l10n.sessionFailed);
    }
    if (!showsRoute(conn)) {
      return LgStatusText(LgStatus.connecting, l10n.sessionConnecting);
    }
    final direct = conn.direct!;
    return LgRouteMark(
      route: direct ? LgRoute.direct : LgRoute.relay,
      label: direct ? l10n.sessionDirect : l10n.sessionRelayed,
      encrypted: conn.secure != false,
      unencryptedLabel: l10n.sessionUnencrypted,
    );
  }

  /// The row of one kind of view: "未打开", or its connection method after the file
  /// transfer's ring and percentage (or the reminder mark, 02 §3.2).
  LgMenuItem _item(AppLocalizations l10n, ConnType kind, FFI? view) {
    final summary = view != null && isFileView(view)
        ? fileTransferFor(view).jobs.summary
        : null;
    final progress = summary?.progress;
    final alert = (summary?.waitingConfirm ?? 0) > 0;
    final Widget? tail = view == null
        ? null
        : LgViewMenuTail(
            progress: progress,
            percentText: progress == null
                ? null
                : '${(progress * 100).floor()}%',
            alert: alert,
            status: _state(l10n, view),
          );
    final unread = view != null && hasImage(view) ? tabUnread(view) : 0;
    return LgMenuItem(
      label: viewName(l10n, kind, terminalAdmin: view?.terminalAdmin ?? false),
      checked: kind == ffi.connType,
      hint: view == null ? l10n.ftViewNotOpen : null,
      badge: unread > 0 ? unread : null,
      // The reminder mark is an icon: the row says what it means.
      trailing: alert
          ? Semantics(label: l10n.ftMarkAttention, child: tail)
          : tail,
      onPressed: () => _show(kind),
    );
  }

  /// "终端" goes to the terminal view that is open, the administrator's too (R3-Q9).
  void _show(ConnType kind) {
    if (kind == ffi.connType) return;
    switch (kind) {
      case ConnType.fileTransfer:
        mainNavigation.openFileTransfer(ffi.id);
      case ConnType.defaultConn:
        mainNavigation.connect(ffi.id);
      default:
        mainNavigation.openView(ffi.id, kind);
    }
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
              // The platform ([viewKinds]) comes with the peer info.
              v.ffiModel,
              if (isFileView(v)) fileTransferFor(v).jobs,
              if (hasImage(v)) v.chatModel,
            ],
          ]),
          builder: (context, _) {
            // The ring and the reminder mark only while the device has a file view.
            final files = views.where(isFileView).firstOrNull;
            final summary = files == null
                ? null
                : fileTransferFor(files).jobs.summary;
            final alert = (summary?.waitingConfirm ?? 0) > 0;
            final name = viewName(l10n, ffi.connType,
                terminalAdmin: ffi.terminalAdmin);
            // On the file view's own bar the name already says "文件传输": "文件传输，45%".
            final mark = summary == null
                ? null
                : isFileView(ffi) && !alert && summary.progress != null
                ? '${(summary.progress! * 100).floor()}%'
                : transferMarkLabel(l10n, summary);
            return LgToolbarMenuButton(
              label: name,
              icon: viewIcon(ffi.connType),
              // A view title bar names the view it shows (`.vt .ti.on`); the image views'
              // toolbar stays as it was.
              highlighted: usesViewBar(ffi),
              progress: summary?.progress,
              alert: alert,
              semanticLabel: mark == null
                  ? null
                  : l10n.ftViewSwitchLabel(name, mark),
              items: [
                for (final kind in viewKinds(ffi.id))
                  _item(
                    l10n,
                    kind,
                    views.where((v) => v.connType == kind).firstOrNull,
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
