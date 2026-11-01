import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/keyboard_shortcuts/shortcut_utils.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/shortcut_model.dart';

/// The "next tab" and "previous tab" shortcuts, the home tab counted first (01 §2.1, 02
/// §1.4.6), with upstream's bindings (`flutter/lib/models/shortcut_model.dart`, action
/// `switch_tab_next` / `switch_tab_prev`).
///
/// A session that holds the keyboard matches its keys itself (Rust's matcher, or the input
/// model's for the Flutter input source) and runs [of]'s callbacks, registered with its other
/// shortcuts. Everywhere else, the home tab and a session tab whose image does not have the
/// keyboard, the keys reach the focus tree unhandled and are matched here.
class TabShortcuts extends StatefulWidget {
  const TabShortcuts({
    super.key,
    required this.onNext,
    required this.onPrevious,
    required this.child,
  });

  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final Widget child;

  /// The tab switch of the window, for the sessions' shortcuts; look it up when the keys are
  /// pressed.
  static ({VoidCallback next, VoidCallback previous})? of(
    BuildContext context,
  ) {
    final scope = context.getInheritedWidgetOfExactType<_Scope>();
    return scope == null ? null : (next: scope.next, previous: scope.previous);
  }

  @override
  State<TabShortcuts> createState() => _TabShortcutsState();
}

class _TabShortcutsState extends State<TabShortcuts> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addLateKeyEventHandler(_onKey);
  }

  @override
  void dispose() {
    FocusManager.instance.removeLateKeyEventHandler(_onKey);
    super.dispose();
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    switch (matchShortcut(
      event.physicalKey,
      ctrl: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
      meta: keyboard.isMetaPressed,
    )) {
      case kShortcutActionSwitchTabNext:
        widget.onNext();
        return KeyEventResult.handled;
      case kShortcutActionSwitchTabPrev:
        widget.onPrevious();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => _Scope(
    next: widget.onNext,
    previous: widget.onPrevious,
    child: widget.child,
  );
}

/// The action bound to [key] with these modifiers, as the input model matches a session's keys
/// (`models/input_model.dart` `_matchFlutterShortcut`); null when shortcuts are off or passed
/// to the remote device.
String? matchShortcut(
  PhysicalKeyboardKey key, {
  required bool ctrl,
  required bool alt,
  required bool shift,
  required bool meta,
}) {
  final keyName = physicalKeyName(key);
  if (keyName == null) return null;
  final config = ShortcutModel.config(active: true);
  if (!config.enabled || config.passThrough) return null;
  final mods = <String>[
    if (defaultTargetPlatform == TargetPlatform.macOS) ...[
      if (meta) 'primary',
      if (ctrl) 'ctrl',
    ] else if (ctrl)
      'primary',
    if (alt) 'alt',
    if (shift) 'shift',
  ];
  for (final binding in config.bindings) {
    final action = binding['action'];
    final bindingMods = canonicalShortcutModsForSave(
      shortcutModSetFrom(binding['mods']),
    );
    if (action is String &&
        binding['key'] == keyName &&
        bindingMods.isNotEmpty &&
        listEquals(bindingMods, mods)) {
      return action;
    }
  }
  return null;
}

class _Scope extends InheritedWidget {
  const _Scope({
    required this.next,
    required this.previous,
    required super.child,
  });

  final VoidCallback next;
  final VoidCallback previous;

  @override
  bool updateShouldNotify(_Scope old) => false;
}
