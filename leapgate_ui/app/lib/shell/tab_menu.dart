import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../l10n/app_localizations.dart';
import '../widgets/lg_button.dart';
import '../widgets/lg_feedback.dart';
import '../widgets/lg_menu.dart';
import 'navigation.dart';
import 'session_views.dart';
import 'tab_overlays.dart';

/// Unread chat messages shown on a session tab (01 §2.1).
int tabUnread(FFI view) => view.chatModel.unread;

/// The session tab's context menu at the pointer (01 P2 block A, `tabs-ctx`): "打开文件传输"
/// while the tab has no file transfer view, "复制设备 ID", "关闭其他标签", "关闭". [onClose] and
/// [onCloseOthers] confirm as the tab's "×" does ([closeSessionTab], [closeOtherTabs]). The
/// terminal and the camera come with their views (round 3).
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

  final items = [
    if (!appCore.sessions.sessionsOf(device).any(isFileView))
      LgMenuItem(
        label: l10n.tabMenuOpenFileTransfer,
        onPressed: () => run(() => mainNavigation.openFileTransfer(device)),
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

/// The tab's "×" and "关闭" (01 §3.2 block G, 02 §3.1): one view closes at once, unless it is a
/// file transfer view with unfinished transfers, which asks as its "断开" does; several views
/// ask "断开与此设备的 ‹N› 个会话？", with the transfers sentence when there are any. [show]
/// selects the tab first, so the question is seen over it.
Future<void> closeSessionTab(TabOverlays overlays, String device,
    {required VoidCallback show}) async {
  final views = appCore.sessions.sessionsOf(device);
  if (views.isEmpty) return;
  if (views.length == 1) {
    if (isFileView(views.single) && unfinishedTransfers(views) > 0) {
      show();
      return disconnectFileView(views.single);
    }
    return appCore.sessions.closeDevice(device);
  }
  show();
  final unfinished = unfinishedTransfers(views);
  final ok = await overlays.show<bool>(
    device,
    (context, close) {
      final l10n = AppLocalizations.of(context)!;
      return LgDialogScrim(
        onEscape: () => close(null),
        child: LgConfirmDialog(
          title: l10n.tabCloseViewsTitle(views.length),
          body: unfinished > 0 ? l10n.ftUnfinished(unfinished) : null,
          actions: [
            LgDialogAction(label: l10n.connCancel, onPressed: () => close(null)),
            LgDialogAction(
              label: l10n.closingDisconnect,
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
