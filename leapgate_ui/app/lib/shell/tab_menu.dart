import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../l10n/app_localizations.dart';
import '../pages/terminal/terminal_view.dart';
import '../widgets/lg_button.dart';
import '../widgets/lg_feedback.dart';
import '../widgets/lg_menu.dart';
import 'navigation.dart';
import 'session_views.dart';
import 'tab_overlays.dart';

/// Unread chat messages shown on a session tab (01 §2.1).
int tabUnread(FFI view) => view.chatModel.unread;

/// The session tab's context menu at the pointer (01 P2 block A, `tabs-ctx`): "打开文件传输",
/// "打开终端", "查看摄像头" for the views the tab does not have yet and offers ([viewKinds],
/// R3-Q12), "复制设备 ID", "关闭其他标签", "关闭". [onClose] and [onCloseOthers] confirm as the
/// tab's "×" does ([closeSessionTab], [closeOtherTabs]).
void showSessionTabMenu(
  BuildContext context,
  String device,
  Offset globalPosition, {
  required VoidCallback onClose,
  required VoidCallback onCloseOthers,
}) {
  final l10n = AppLocalizations.of(context)!;
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  void close() => entry.remove();
  void run(VoidCallback action) {
    close();
    action();
  }

  final views = appCore.sessions.sessionsOf(device);
  bool missing(ConnType kind) =>
      !views.any((v) => v.connType == kind) && viewKinds(device).contains(kind);
  final items = [
    if (!views.any(isFileView))
      LgMenuItem(
        label: l10n.tabMenuOpenFileTransfer,
        onPressed: () => run(() => mainNavigation.openFileTransfer(device)),
      ),
    if (missing(ConnType.terminal))
      LgMenuItem(
        label: l10n.tabMenuOpenTerminal,
        onPressed: () =>
            run(() => mainNavigation.openView(device, ConnType.terminal)),
      ),
    if (missing(ConnType.viewCamera))
      LgMenuItem(
        label: l10n.tabMenuViewCamera,
        onPressed: () =>
            run(() => mainNavigation.openView(device, ConnType.viewCamera)),
      ),
    LgMenuItem(
      label: l10n.tabMenuCopyId,
      onPressed: () => run(() {
        Clipboard.setData(ClipboardData(text: device));
        appCore.toasts.show('Copied');
      }),
    ),
    LgMenuItem(
      label: l10n.tabMenuCloseOthers,
      onPressed: appCore.sessions.devices.length < 2
          ? null
          : () => run(onCloseOthers),
    ),
    LgMenuItem(
      label: l10n.tabMenuClose,
      onPressed: () => run(onClose),
    ),
  ];
  final box = overlay.context.findRenderObject() as RenderBox;
  final at = box.globalToLocal(globalPosition);
  entry = OverlayEntry(
    builder: (context) => Stack(children: [
      // A click anywhere else closes it.
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: close,
          onSecondaryTap: close,
        ),
      ),
      Positioned(
        left: at.dx.clamp(0, (box.size.width - kLgMenuWidth).clamp(0, double.infinity)),
        top: at.dy,
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
          child: FocusScope(
            autofocus: true,
            child: LgMenuPanel(items: items),
          ),
        ),
      ),
    ]),
  );
  overlay.insert(entry);
}

/// The tabs whose [closeSessionTab] question is open, by their first view: another "×" meanwhile
/// does nothing. Keyed by the session rather than the device ID, so a question whose tab went
/// away unanswered (its overlay goes with it) cannot block a later tab of the same device.
final _asking = Expando<bool>();

/// The tab's "×", "关闭" and the "关闭标签" shortcut (01 §3.2 block G, 02 §3.1): one view closes
/// at once, unless it is a file transfer view with unfinished transfers or a terminal view,
/// which ask as their "断开" does (R2-Q28, R3-Q15); several views ask "断开与此设备的 ‹N› 个会话？",
/// with the transfers sentence when there are any. With "关闭窗口前确认断开会话" off, several
/// views close at once too, and unfinished transfers still ask, with that sentence alone. [show]
/// selects the tab first, so the question is seen over it.
Future<void> closeSessionTab(TabOverlays overlays, String device,
    {required VoidCallback show}) async {
  final views = appCore.sessions.sessionsOf(device);
  if (views.isEmpty || views.any((v) => _asking[v] == true)) return;
  final unfinished = unfinishedTransfers(views);
  final confirm = views.length > 1 &&
      appCore.options.local.getBool(kOptionEnableConfirmClosingTabs);
  // Whether the terminal asks is the terminal view's ([disconnectTerminalView]): the tab is
  // selected only when it will ask, otherwise it closes where it is.
  final terminal = views.length == 1 &&
      views.single.connType == ConnType.terminal &&
      views.single.terminals?.needsDisconnectConfirm == true;
  if (!confirm && unfinished == 0 && !terminal) {
    return appCore.sessions.closeDevice(device);
  }
  show();
  final asking = views.first;
  _asking[asking] = true;
  try {
    if (terminal) return await disconnectTerminalView(views.single);
    if (views.length == 1) return await disconnectFileView(views.single);
    final ok = await overlays.show<bool>(
      device,
      (context, close) {
        final l10n = AppLocalizations.of(context)!;
        return LgDialogScrim(
          onEscape: () => close(null),
          child: LgConfirmDialog(
            title: confirm
                ? l10n.tabCloseViewsTitle(views.length)
                : l10n.tabCloseTitle,
            body: unfinished > 0 ? l10n.ftUnfinished(unfinished) : null,
            actions: [
              LgDialogAction(
                  label: l10n.connCancel, onPressed: () => close(null)),
              LgDialogAction(
                label: confirm ? l10n.closingDisconnect : l10n.closingClose,
                kind: LgButtonKind.primary,
                isDefault: true,
                onPressed: () => close(true),
              ),
            ],
          ),
        );
      },
    );
    if (ok == true) await appCore.sessions.closeDevice(device);
  } finally {
    _asking[asking] = null;
  }
}

/// "关闭其他标签": asks once, over the whole window, only when the other tabs have unfinished
/// transfers (01 §3.2 block G).
Future<void> closeOtherTabs(TabOverlays overlays, String device) async {
  final others = [
    for (final d in appCore.sessions.devices)
      if (d != device) d
  ];
  final unfinished =
      unfinishedTransfers(others.expand(appCore.sessions.sessionsOf));
  if (unfinished > 0) {
    final ok = await overlays.show<bool>(
      kWindowScope,
      (context, close) {
        final l10n = AppLocalizations.of(context)!;
        return LgDialogScrim(
          onEscape: () => close(null),
          child: LgConfirmDialog(
            title: l10n.tabCloseOthersTitle,
            body: l10n.ftUnfinished(unfinished),
            actions: [
              LgDialogAction(
                  label: l10n.connCancel, onPressed: () => close(null)),
              LgDialogAction(
                label: l10n.closingClose,
                kind: LgButtonKind.primary,
                isDefault: true,
                onPressed: () => close(true),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return;
  }
  await Future.wait(others.map(appCore.sessions.closeDevice));
}
