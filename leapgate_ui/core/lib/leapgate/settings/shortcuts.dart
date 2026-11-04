// 上游：flutter/lib/common/widgets/keyboard_shortcuts/page_body.dart、recording_dialog.dart@bd9262397
// （去界面化改写：绑定的读写、恢复默认取自 page_body.dart 的 `_readJson`、`_setBinding`、
// `_resetToDefaults`；录制的按键归一和校验取自 recording_dialog.dart 的 `_onKeyEvent`、
// `_conflictActionId`、`_onSave`、`_keyDisplay`；界面、Linux GTK 的 AltGr 分支不搬）
//
// The shortcut list of the settings (02 §1.4.6): the bindings as stored under
// [kShortcutLocalConfigKey] ({enabled, pass_through, bindings: [{action, mods, key}]}), and what a
// recording dialog makes of the keys pressed. The master switch and "将组合键发送到远程设备" are
// upstream's [ShortcutModel.setEnabled] and [ShortcutModel.setPassThrough].
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../common/widgets/keyboard_shortcuts/shortcut_actions.dart';
import '../../common/widgets/keyboard_shortcuts/shortcut_utils.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';
import '../../models/shortcut_model.dart';

Map<String, dynamic> _readJson() {
  final raw = bind.mainGetLocalOption(key: kShortcutLocalConfigKey);
  if (raw.isEmpty) return {'enabled': false, 'bindings': <dynamic>[]};
  try {
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    parsed['bindings'] ??= <dynamic>[];
    parsed['enabled'] ??= false;
    return parsed;
  } catch (_) {
    return {'enabled': false, 'bindings': <dynamic>[]};
  }
}

/// Saves and has the matcher read it again, so the change counts at once.
Future<void> _writeJson(Map<String, dynamic> json) async {
  await bind.mainSetLocalOption(
      key: kShortcutLocalConfigKey, value: jsonEncode(json));
  bind.mainReloadKeyboardShortcuts();
}

/// The stored bindings, whether shortcuts are on or not (the list shows them either way).
List<Map<String, dynamic>> shortcutBindings() =>
    shortcutBindingMapsFrom(_readJson()['bindings']);

/// Binds [actionId] to [binding], or unbinds it when null. [clearActionId] is the action whose
/// binding the new one takes ("替换"); it loses it in the same write.
Future<void> setShortcutBinding(String actionId,
    {Map<String, dynamic>? binding, String? clearActionId}) async {
  final json = _readJson();
  final list = shortcutBindingMapsFrom(json['bindings'])
    ..removeWhere((b) => b['action'] == actionId || b['action'] == clearActionId);
  if (binding != null) list.add(binding);
  json['bindings'] = list;
  await _writeJson(json);
}

/// "恢复默认": the default bindings of this platform, keeping the two switches.
Future<void> resetShortcutBindings() async {
  final json = _readJson();
  json['bindings'] = filterDefaultBindingsForPlatform(
    jsonDecode(bind.mainGetDefaultKeyboardShortcuts()) as List,
    ShortcutModel.currentPlatformCapabilities(),
  );
  await _writeJson(json);
}

/// The actions this platform can run (the list leaves the others out).
Set<String> shortcutActionsForPlatform() => allActionEntries(
        filterKeyboardShortcutActionGroupsForPlatform(
            ShortcutModel.currentPlatformCapabilities()))
    .map((e) => e.id)
    .toSet();

bool get _isMac =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// A combination as its keys are written ("Ctrl", "Alt", "Shift", "Del"), in the order of
/// upstream's toolbar hints (`display.dart`).
List<String> shortcutKeyLabels(Set<String> mods, String? key) => [
      for (final m in const ['primary', 'ctrl', 'alt', 'shift'])
        if (mods.contains(m))
          switch (m) {
            'primary' => _isMac ? 'Cmd' : 'Ctrl',
            'ctrl' => _isMac ? 'Control' : 'Ctrl',
            'alt' => _isMac ? 'Option' : 'Alt',
            _ => 'Shift',
          },
      if (key != null) _keyDisplay(key),
    ];

/// A stored binding's keys; none when it has no key.
List<String> bindingKeyLabels(Map<String, dynamic> binding) {
  final key = binding['key'];
  if (key is! String) return const [];
  return shortcutKeyLabels(shortcutModSetFrom(binding['mods']), key);
}

String _keyDisplay(String key) {
  switch (key) {
    case 'delete':     return 'Del';
    case 'backspace':  return 'Backspace';
    case 'enter':      return 'Enter';
    case 'tab':        return 'Tab';
    case 'space':      return 'Space';
    case 'arrow_left': return 'Left';
    case 'arrow_right':return 'Right';
    case 'arrow_up':   return 'Up';
    case 'arrow_down': return 'Down';
    case 'home':       return 'Home';
    case 'end':        return 'End';
    case 'page_up':    return 'PgUp';
    case 'page_down':  return 'PgDn';
    case 'insert':     return 'Ins';
  }
  if (key.startsWith('digit')) return key.substring(5);
  return key.toUpperCase();
}

/// What the recording dialog says about the keys pressed (02 §1.4.6).
enum ShortcutRecordState { waiting, unsupported, missingModifier, conflict, valid }

/// One recording: the keys of the last key press, checked against the other bindings.
class ShortcutRecorder {
  ShortcutRecorder({required this.actionId, required this.bindings});

  /// The action being set; its own binding is no conflict.
  final String actionId;
  final List<Map<String, dynamic>> bindings;

  Set<String> _mods = {};
  String? _key;

  /// The name of the last key pressed when it can't be a shortcut.
  String? unsupportedKey;

  /// Modifiers pressed alone build a combination; they are not unsupported keys.
  static final _modifierKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.numLock,
    LogicalKeyboardKey.scrollLock,
    LogicalKeyboardKey.fn,
    LogicalKeyboardKey.fnLock,
  };

  /// The modifiers held now, named as Rust's `normalize_modifiers` names them: on Windows and
  /// Linux Ctrl is `primary`; on macOS Cmd is `primary` and Ctrl is `ctrl`.
  static Set<String> heldModifiers() {
    final k = HardwareKeyboard.instance;
    return {
      if (k.isAltPressed) 'alt',
      if (k.isShiftPressed) 'shift',
      if (_isMac) ...[
        if (k.isMetaPressed) 'primary',
        if (k.isControlPressed) 'ctrl',
      ] else if (k.isControlPressed)
        'primary',
    };
  }

  /// A key went down with [mods] held. [keyName] is its name in saved bindings
  /// ([physicalKeyName]), null for a key that has none. AltGr can't be told from Ctrl+Alt by
  /// the matcher, so it is refused ([altGraph]).
  void keyDown(LogicalKeyboardKey logical, String? keyName, Set<String> mods,
      {bool altGraph = false}) {
    _mods = mods;
    if (!_isMac && altGraph) {
      _key = null;
      unsupportedKey = LogicalKeyboardKey.altGraph.keyLabel;
      return;
    }
    // As at run time: modifiers added after a held letter make no new combination.
    _key = keyName;
    unsupportedKey = null;
    if (keyName == null && !_modifierKeys.contains(logical)) {
      unsupportedKey = logical.keyLabel.isNotEmpty
          ? logical.keyLabel
          : (logical.debugName ?? '?');
    }
  }

  /// [keyDown] for a key event, with the keyboard's state as it is now.
  void onKeyDown(KeyDownEvent event) => keyDown(
        event.logicalKey,
        shortcutKeyNameForEvent(event),
        heldModifiers(),
        altGraph: HardwareKeyboard.instance.logicalKeysPressed
            .contains(LogicalKeyboardKey.altGraph),
      );

  /// The action that has these keys now, other than [actionId].
  String? get conflictActionId {
    if (_key == null || _mods.isEmpty) return null;
    for (final b in bindings) {
      final other = b['action'] as String?;
      if (other == null || other == actionId) continue;
      final otherMods = shortcutModSetFrom(b['mods']);
      if (b['key'] == _key &&
          otherMods.length == _mods.length &&
          otherMods.containsAll(_mods)) {
        return other;
      }
    }
    return null;
  }

  /// The last key press that can't be a shortcut is reported over what was recorded before it.
  ShortcutRecordState get state {
    if (unsupportedKey != null) return ShortcutRecordState.unsupported;
    if (_key == null) return ShortcutRecordState.waiting;
    if (_mods.isEmpty) return ShortcutRecordState.missingModifier;
    if (conflictActionId != null) return ShortcutRecordState.conflict;
    return ShortcutRecordState.valid;
  }

  /// The keys to show: the modifiers held, then the key (the unsupported one by its name).
  List<String> get keyLabels => [
        ...shortcutKeyLabels(_mods, _key),
        if (unsupportedKey != null) unsupportedKey!,
      ];

  /// The binding to save, null while there is nothing to save.
  Map<String, dynamic>? get binding => switch (state) {
        ShortcutRecordState.conflict || ShortcutRecordState.valid => {
            'action': actionId,
            'mods': canonicalShortcutModsForSave(_mods),
            'key': _key!,
          },
        _ => null,
      };
}
