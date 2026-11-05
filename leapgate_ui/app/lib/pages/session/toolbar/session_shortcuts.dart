// The session's shortcut actions (02 §1.4.6). Upstream: `registerSessionShortcutActions` and
// `registerToolbarShortcuts` (`flutter/lib/models/shortcut_model.dart:279-669`,
// `flutter/lib/common/widgets/toolbar.dart:1421-1459`), rewritten for one window with tabs:
// the menu actions run the rows of the menus (built again when the keys are pressed), the
// others are wired here. "收起 / 展开工具栏" takes the place of upstream's hide-the-toolbar
// (02 §1.4.6). The chat, voice call and quality monitor actions live beside what they toggle.

import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/state_model.dart';

import '../../../shell/tab_menu.dart';
import '../chat/chat.dart';
import '../route_details.dart';

import 'action_menu.dart';
import 'display_menu.dart';
import 'input_menu.dart';
import 'monitor_menu.dart';
import 'session_menu.dart';
import 'entries.dart';
import 'toolbar_env.dart';

void registerSessionShortcuts(
  ToolbarEnv env, {
  required void Function() onNextTab,
  required void Function() onPreviousTab,
  required void Function() onToggleCollapsed,
  required void Function() onTogglePin,
  required bool Function() detailMode,
}) {
  final ffi = env.ffi;
  final shortcuts = ffi.shortcutModel;
  registerMenuShortcuts(
    shortcuts,
    kDisplayMenuActions,
    () => displayMenuEntries(env),
  );
  registerMenuShortcuts(
    shortcuts,
    kInputMenuActions,
    () => inputMenuEntries(env),
  );
  registerMenuShortcuts(
    shortcuts,
    kActionMenuActions,
    () => actionMenuEntries(env),
  );
  registerMenuShortcuts(
    shortcuts,
    kSessionMenuActions,
    () => sessionMenuEntries(env),
  );

  shortcuts.register(
    kShortcutActionToggleFullscreen,
    () => stateGlobal.setFullscreen(!stateGlobal.fullscreen.value),
  );
  shortcuts.register(
    kShortcutActionToggleRecording,
    () => ffi.requests.toggleRecording(),
  );
  shortcuts.register(
    kShortcutActionSwitchDisplayNext,
    () => switchMonitorBy(ffi, 1, updateCursorPos: false),
  );
  shortcuts.register(
    kShortcutActionSwitchDisplayPrev,
    () => switchMonitorBy(ffi, -1, updateCursorPos: false),
  );
  shortcuts.register(kShortcutActionSwitchDisplayAll, () {
    final pi = ffi.ffiModel.pi;
    if (!displaySwitchAllowed(ffi) ||
        !pi.isSupportMultiDisplay ||
        pi.displays.length <= 1 ||
        pi.currentDisplay == kAllDisplayValue) {
      return;
    }
    openMonitor(ffi, kAllDisplayValue);
  });
  shortcuts.register(kShortcutActionSwitchTabNext, onNextTab);
  shortcuts.register(kShortcutActionSwitchTabPrev, onPreviousTab);
  // As the tab's "×" (M7a): asks with several views or unfinished transfers. The keys reach a
  // session only while its tab is the selected one.
  shortcuts.register(
    kShortcutActionCloseTab,
    () => closeSessionTab(env.overlays, ffi.id, show: () {}),
  );
  shortcuts.register(kShortcutActionToggleToolbar, onToggleCollapsed);
  shortcuts.register(kShortcutActionPinToolbar, onTogglePin);
  registerQualityMonitorShortcut(ffi, detailMode);
  registerChatShortcuts(ffi);
}
