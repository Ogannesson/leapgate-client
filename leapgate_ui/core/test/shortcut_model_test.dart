import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/local_flutter_shortcuts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

// The session shortcuts put back with `shortcut_model` (LEAPGATE.md §10.6): Rust's matcher and
// the input model's both run what the toolbar registered.

/// Shortcuts on, Ctrl+Alt+Shift+P bound to the screenshot (the config upstream's settings
/// write, `shortcut_model.dart:158-180`).
class _ShortcutsBind extends FakeBind {
  String config = jsonEncode({
    'enabled': true,
    'bindings': [
      {
        'action': 'screenshot',
        'mods': ['primary', 'alt', 'shift'],
        'key': 'p'
      },
    ],
  });

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #mainGetLocalOption &&
        invocation.namedArguments[#key] == kShortcutLocalConfigKey) {
      return config;
    }
    return super.noSuchMethod(invocation);
  }
}

Future<FFI> _open(FakeBind bind) async {
  appCore.sessions.open('100200300', ConnType.defaultConn);
  await settle();
  return appCore.sessions.sessionsOf('100200300').single;
}

void _emit(FakeBind bind, FFI s, Map<String, dynamic> evt) =>
    bind.streams[s.sessionId]!.add(EventToUI.event(jsonEncode(evt)));

void main() {
  late _ShortcutsBind bind;

  setUp(() {
    installFakes();
    bind = _ShortcutsBind();
    platformFFI.setBindingForTesting(bind);
  });

  test(
      'a shortcut matched by Rust runs what the toolbar registered (model.dart:473-477)',
      () async {
    final s = await _open(bind);
    var shots = 0;
    s.shortcutModel.register(kShortcutActionScreenshot, () => shots++);

    _emit(bind, s, {'name': kShortcutEventName, 'action': 'screenshot'});
    await settle();
    expect(shots, 1);

    // Unregistered: the keys do nothing.
    s.shortcutModel.unregister(kShortcutActionScreenshot);
    _emit(bind, s, {'name': kShortcutEventName, 'action': 'screenshot'});
    await settle();
    expect(shots, 1);
  });

  test('a refresher builds the actions again before they run', () async {
    final s = await _open(bind);
    var enabled = false;
    var shots = 0;
    s.shortcutModel.registerRefresher([kShortcutActionScreenshot], () {
      if (enabled) {
        s.shortcutModel.register(kShortcutActionScreenshot, () => shots++);
      } else {
        s.shortcutModel.unregister(kShortcutActionScreenshot);
      }
    });
    _emit(bind, s, {'name': kShortcutEventName, 'action': 'screenshot'});
    await settle();
    expect(shots, 0);
    enabled = true;
    _emit(bind, s, {'name': kShortcutEventName, 'action': 'screenshot'});
    await settle();
    expect(shots, 1);
  });

  testWidgets(
      'keys matched in Flutter reach the shortcut too (input_model.dart:426, :1212-1236)',
      (tester) async {
    final s = appCore.sessions.open('100200300', ConnType.defaultConn);
    await tester.pump();
    var shots = 0;
    s.shortcutModel.register(kShortcutActionScreenshot, () => shots++);
    // View-only mode matches in Flutter whatever the input source.
    s.ffiModel.pi.version = '1.4.6';
    s.ffiModel.setViewOnly(s.id, true);
    addTearDown(LocalFlutterShortcutDispatcher.resetFiredKeys);

    Future<void> press(
        LogicalKeyboardKey key, PhysicalKeyboardKey physical) async {
      await tester.sendKeyDownEvent(key);
      s.inputModel.handleKeyEvent(KeyDownEvent(
          physicalKey: physical, logicalKey: key, timeStamp: Duration.zero));
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await press(LogicalKeyboardKey.keyP, PhysicalKeyboardKey.keyP);
    await tester.pump();
    expect(shots, 1);

    // Shortcuts turned off: the same keys run nothing.
    bind.config = jsonEncode({'enabled': false, 'bindings': []});
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
    s.inputModel.handleKeyEvent(const KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyP,
        logicalKey: LogicalKeyboardKey.keyP,
        timeStamp: Duration.zero));
    await press(LogicalKeyboardKey.keyP, PhysicalKeyboardKey.keyP);
    await tester.pump();
    expect(shots, 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  test('the resolution menu remembers its choice until the next peer info',
      () async {
    final s = await _open(bind);
    stateGlobal.setLastResolutionGroupValue('100200300', 0, 'custom');
    stateGlobal.setLastResolutionGroupValue('400500600', 0, 'custom');
    expect(stateGlobal.getLastResolutionGroupValue('100200300', 0), 'custom');
    expect(stateGlobal.getLastResolutionGroupValue('100200300', 1), isNull);

    // A new peer info starts this device over (upstream `model.dart:1487`).
    _emit(bind, s, {
      'name': 'peer_info',
      'version': '1.4.6',
      'username': 'user',
      'hostname': 'host',
      'platform': 'Windows',
      'sas_enabled': 'false',
      'current_display': '0',
      'displays': jsonEncode([
        {'x': 0, 'y': 0, 'width': 1920, 'height': 1080, 'cursor_embedded': 0},
      ]),
      'features': jsonEncode({'privacy_mode': false}),
      'resolutions': jsonEncode([]),
      'platform_additions': '',
    });
    await settle();
    expect(s.ffiModel.pi.isSet.value, true);
    expect(stateGlobal.getLastResolutionGroupValue('100200300', 0), isNull);
    expect(stateGlobal.getLastResolutionGroupValue('400500600', 0), 'custom');
    stateGlobal.resetLastResolutionGroupValues('400500600');
  });
}
