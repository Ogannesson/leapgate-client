import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/settings/shortcuts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

// The shortcut list of coder D's settings (`LEAPGATE.md` §10.14, 02 §1.4.6): the bindings as
// stored, and what the recording dialog makes of a key press.

/// Keeps LocalConfig and counts the matcher reloads.
class _Bind extends FakeBind {
  final local = <String, String>{};
  int reloads = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      case #mainGetLocalOption:
        return local[args[#key]] ?? '';
      case #mainSetLocalOption:
        local[args[#key]] = args[#value];
        return Future<void>.value();
      case #mainReloadKeyboardShortcuts:
        reloads++;
        return null;
      case #mainGetDefaultKeyboardShortcuts:
        return jsonEncode(kDefaultShortcutBindings);
    }
    return super.noSuchMethod(invocation);
  }
}

Map<String, dynamic> _bind(String action, String key,
        [List<String> mods = const ['primary', 'alt', 'shift']]) =>
    {'action': action, 'mods': mods, 'key': key};

const _all = {'primary', 'alt', 'shift'};

void main() {
  late _Bind bind;
  setUp(() {
    bind = _Bind();
    platformFFI.setBindingForTesting(bind);
  });

  Map<String, dynamic> stored() =>
      jsonDecode(bind.local[kShortcutLocalConfigKey]!) as Map<String, dynamic>;

  group('bindings', () {
    test('replacing takes the keys from the other action in the same write', () async {
      bind.local[kShortcutLocalConfigKey] = jsonEncode({
        'enabled': true,
        'pass_through': true,
        'bindings': [_bind('screenshot', 'p'), _bind('refresh', 'r')],
      });
      await setShortcutBinding('refresh',
          binding: _bind('refresh', 'p'), clearActionId: 'screenshot');
      expect(stored()['bindings'], [_bind('refresh', 'p')]);
      // The switches stay as they were; the matcher reads the change at once.
      expect((stored()['enabled'], stored()['pass_through']), (true, true));
      expect(bind.reloads, 1);
      expect(bindingKeyLabels(shortcutBindings().single),
          ['Ctrl', 'Alt', 'Shift', 'P']);
    });

    test('clearing leaves an empty list, which turning on again keeps', () async {
      bind.local[kShortcutLocalConfigKey] =
          jsonEncode({'enabled': true, 'bindings': [_bind('screenshot', 'p')]});
      await setShortcutBinding('screenshot');
      expect(shortcutBindings(), isEmpty);
      expect(stored()['bindings'], isEmpty);
    });

    test('reset puts back the defaults of this platform', () async {
      bind.local[kShortcutLocalConfigKey] =
          jsonEncode({'enabled': true, 'bindings': [_bind('refresh', 'r')]});
      await resetShortcutBindings();
      final actions = [for (final b in shortcutBindings()) b['action']];
      expect(actions, hasLength(kDefaultShortcutBindings.length));
      expect(actions, isNot(contains('refresh')));
      expect(bindingKeyLabels(shortcutBindings()
              .firstWhere((b) => b['action'] == kShortcutActionSwitchDisplayNext)),
          ['Ctrl', 'Alt', 'Shift', '→']);
    });
  });

  group('recording', () {
    ShortcutRecorder recorder() => ShortcutRecorder(
        actionId: 'refresh',
        bindings: [_bind('screenshot', 'p'), _bind('refresh', 'r')]);

    test('waiting until a key that is not a modifier comes', () {
      final r = recorder();
      expect(r.state, ShortcutRecordState.waiting);
      r.keyDown(LogicalKeyboardKey.controlLeft, null, {'primary'});
      expect(r.state, ShortcutRecordState.waiting);
      expect(r.keyLabels, ['Ctrl']);
      expect(r.binding, isNull);
    });

    test('a key that has no name is refused, by its own name', () {
      final r = recorder()..keyDown(LogicalKeyboardKey.f13, null, {'primary'});
      expect(r.state, ShortcutRecordState.unsupported);
      expect(r.unsupportedKey, 'F13');
      expect(r.keyLabels, ['Ctrl', 'F13']);
      expect(r.binding, isNull);
      // AltGr can't be told from Ctrl+Alt.
      r.keyDown(LogicalKeyboardKey.keyQ, 'q', {'primary', 'alt'}, altGraph: true);
      expect(r.state, ShortcutRecordState.unsupported);
    });

    test('a key without Ctrl, Alt or Shift', () {
      final r = recorder()..keyDown(LogicalKeyboardKey.keyR, 'r', {});
      expect(r.state, ShortcutRecordState.missingModifier);
      expect(r.binding, isNull);
    });

    test('keys of another action: replacing, and saved without its binding', () {
      final r = recorder()..keyDown(LogicalKeyboardKey.keyP, 'p', _all);
      expect(r.state, ShortcutRecordState.conflict);
      expect(r.conflictActionId, 'screenshot');
      expect(r.binding, _bind('refresh', 'p'));
      // The same key with other modifiers is no conflict.
      r.keyDown(LogicalKeyboardKey.keyP, 'p', {'primary', 'shift'});
      expect(r.state, ShortcutRecordState.valid);
    });

    test('valid, and the action\'s own keys are no conflict', () {
      final r = recorder()..keyDown(LogicalKeyboardKey.keyR, 'r', _all);
      expect(r.state, ShortcutRecordState.valid);
      expect(r.keyLabels, ['Ctrl', 'Alt', 'Shift', 'R']);
      expect(r.binding, _bind('refresh', 'r'));
    });
  });
}
