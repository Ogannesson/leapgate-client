import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../l10n/app_localizations.dart';
import '../widgets/lg_menu.dart';

/// Unread chat messages shown on a session tab (01 §2.1).
int tabUnread(FFI view) => view.chatModel.unread;

/// The session tab's context menu at the pointer (01 P2 block A, `tabs-ctx`): "复制设备 ID",
/// "关闭其他标签", "关闭". Opening another view of the device comes with those views (M7a, round
/// 3). Closing goes as the tab's "×" and upstream's "Close others" do, without asking.
void showSessionTabMenu(
  BuildContext context,
  String device,
  Offset globalPosition,
) {
  final l10n = AppLocalizations.of(context)!;
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  void close() => entry.remove();
  void run(VoidCallback action) {
    close();
    action();
  }

  final items = [
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
          : () => run(() {
                for (final d in appCore.sessions.devices) {
                  if (d != device) appCore.sessions.closeDevice(d);
                }
              }),
    ),
    LgMenuItem(
      label: l10n.tabMenuClose,
      onPressed: () => run(() => appCore.sessions.closeDevice(device)),
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
