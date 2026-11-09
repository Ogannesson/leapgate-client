import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

export 'fakes.dart';

/// The terminal's calls on block 1, on top of a [FakeBind] (core's, or the app's).
mixin TerminalBindCalls on FakeBind {
  /// The session toggle options by name ("terminal-persistent").
  final toggles = <String, bool>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      case #sessionOpenTerminal:
      case #sessionCloseTerminal:
      case #sessionSendTerminalInput:
      case #sessionResizeTerminal:
        calls.add(invocation);
        return Future<void>.value();
      case #mainSetEnv:
        calls.add(invocation);
        return null;
      case #isDisableSettings:
      case #mainIsOptionFixed:
        return false;
      case #sessionGetToggleOptionSync:
        return toggles[args[#arg]] ?? false;
      case #sessionToggleOption:
        calls.add(invocation);
        final option = args[#value] as String;
        toggles[option] = !(toggles[option] ?? false);
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }

  /// The terminal IDs [name] was called with, in order.
  List<int> terminalIds(Symbol name) =>
      [for (final c in callsTo(name)) c.namedArguments[#terminalId] as int];
}

/// Core's [FakeBind] with the terminal's calls and LocalConfig.
class TerminalFakeBind extends FakeBind with TerminalBindCalls {
  final local = <String, String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      case #mainGetLocalOption:
        return local[args[#key]] ?? '';
      case #mainSetLocalOption:
        calls.add(invocation);
        local[args[#key] as String] = args[#value] as String;
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

/// [installFakes] with a [TerminalFakeBind] behind `bind`.
TerminalFakeBind installTerminalFakes() {
  installFakes();
  final bind = TerminalFakeBind();
  platformFFI.setBindingForTesting(bind);
  return bind;
}

/// A `terminal_response` event as Rust sends it (`src/flutter.rs`).
Future<void> terminalEvent(FFI ffi, Map<String, dynamic> evt) =>
    ffi.events.dispatch({...evt, 'name': 'terminal_response'});

/// "opened" for terminal [id]; [persistent] are the shells the remote device kept.
Future<void> terminalOpened(FFI ffi, int id,
        {String message = 'Terminal opened',
        List<int> persistent = const []}) =>
    terminalEvent(ffi, {
      'type': 'opened',
      'terminal_id': id,
      'success': true,
      'message': message,
      if (persistent.isNotEmpty) 'persistent_sessions': persistent,
    });

/// The system clipboard: what was written, or a failure for every write.
class FakeClipboard {
  FakeClipboard({this.fail = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method != 'Clipboard.setData') return null;
      if (fail) throw PlatformException(code: 'clipboard');
      written.add((call.arguments as Map)['text'] as String);
      return null;
    });
  }

  final bool fail;
  final written = <String>[];
}

/// An OSC 52 write of [text] to the system clipboard, as vim or tmux send it.
String osc52(String text) =>
    '\x1b]52;c;${base64.encode(utf8.encode(text))}\x07';
