import 'dart:convert';

import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/leapgate/terminal/terminals.dart';
import 'package:flutter_hbb/models/terminal_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_fakes.dart';

// The terminals of a terminal view (13 §2.2.2 blocks B, C, E, F; R3-Q11, R3-Q15). Device IDs
// are made up.

const _id = '100200300';

final _peerInfo = {
  'name': 'peer_info',
  'version': '1.4.6',
  'username': 'media',
  'hostname': 'minipc',
  'platform': 'Linux',
  'sas_enabled': 'false',
  'current_display': '0',
  'displays': jsonEncode([]),
  'features': jsonEncode({}),
  'resolutions': jsonEncode([]),
  'platform_additions': '',
};

/// A terminal view whose connection is up: terminal 1 asked to open.
Future<({FFI ffi, TerminalTabs tabs, TerminalFakeBind bind})> _connected(
    {bool admin = false}) async {
  final bind = installTerminalFakes();
  final ffi =
      appCore.sessions.open(_id, ConnType.terminal, terminalAdmin: admin);
  await ffi.events.dispatch({..._peerInfo});
  return (ffi: ffi, tabs: ffi.terminals!, bind: bind);
}

/// What terminal [m] shows, once a view of it has a size.
Future<String> _text(WidgetTester tester, TerminalModel m) async {
  m.terminal.resize(80, 24, 640, 480);
  await tester.pump();
  return m.terminal.buffer.getText();
}

void main() {
  test('the administrator flag is set just before the session is added', () {
    final bind = installTerminalFakes();
    appCore.sessions.open('400500600', ConnType.terminal, terminalAdmin: true);
    appCore.sessions.open(_id, ConnType.terminal);

    final names = [
      for (final c in bind.calls)
        if (c.memberName == #mainSetEnv || c.memberName == #sessionAddSync)
          c.memberName
    ];
    expect(names, [#mainSetEnv, #sessionAddSync, #sessionAddSync]);
    final env = bind.callsTo(#mainSetEnv).single.namedArguments;
    expect([env[#key], env[#value]], ['IS_TERMINAL_ADMIN', 'Y']);
  });

  test('no terminal before the connection is up; numbers only grow', () async {
    final bind = installTerminalFakes();
    final ffi = appCore.sessions.open(_id, ConnType.terminal);
    final tabs = ffi.terminals!;
    tabs.add();
    expect(tabs.terminals, isEmpty);
    expect(tabs.canAdd, isFalse);

    await ffi.events.dispatch({..._peerInfo});
    expect(tabs.canAdd, isTrue);
    tabs.add();
    tabs.add();
    await terminalOpened(ffi, 2);
    await tabs.closeTerminal(tabs.terminals[1]);
    tabs.add();

    expect([for (final m in tabs.terminals) m.terminalId], [1, 3, 4]);
    expect(tabs.selected, 2);
    expect(bind.terminalIds(#sessionOpenTerminal), [1, 2, 3, 4]);
    expect(bind.terminalIds(#sessionCloseTerminal), [2]);
  });

  test('kept shells come back as tabs of their own, numbers after them',
      () async {
    final t = await _connected();
    await terminalOpened(t.ffi, 1,
        message: 'Reconnected to existing terminal', persistent: [7, 1, 4]);

    expect([for (final m in t.tabs.terminals) m.terminalId], [1, 4, 7]);
    expect(t.tabs.selected, 0);
    t.tabs.add();
    expect(t.tabs.terminals.last.terminalId, 8);
  });

  test('a shell that exits closes its tab, the last one the view', () async {
    final t = await _connected();
    t.tabs.add();
    await terminalEvent(
        t.ffi, {'type': 'closed', 'terminal_id': 2, 'exit_code': 0});
    expect([for (final m in t.tabs.terminals) m.terminalId], [1]);

    await terminalEvent(
        t.ffi, {'type': 'closed', 'terminal_id': 1, 'exit_code': 0});
    await settle();
    expect(appCore.sessions.sessionsOf(_id), isEmpty);
    expect(t.ffi.closed, isTrue);
  });

  test('closing the view ends the shells unless they are kept', () async {
    for (final keep in [false, true]) {
      final t = await _connected();
      t.tabs.add();
      await terminalOpened(t.ffi, 1);
      await terminalOpened(t.ffi, 2);
      if (keep) await t.tabs.togglePersistent();
      expect(t.tabs.persistent, keep);
      expect(t.tabs.needsDisconnectConfirm, !keep);

      await appCore.sessions.close(t.ffi);

      expect(t.bind.terminalIds(#sessionCloseTerminal), keep ? [] : [1, 2]);
      expect(t.bind.callsTo(#sessionClose), hasLength(1));
    }
  });

  test('one terminal disconnects without asking; the question is answered once',
      () async {
    final t = await _connected();
    expect(t.tabs.needsDisconnectConfirm, isFalse);
    t.tabs.add();
    expect(t.tabs.needsDisconnectConfirm, isTrue);

    final first = t.tabs.askDisconnect();
    final second = t.tabs.askDisconnect();
    expect(t.tabs.askingDisconnect, isTrue);
    t.tabs.answerDisconnect(true);
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(t.tabs.askingDisconnect, isFalse);
  });

  testWidgets('R3-Q11: a reconnect that gets a new shell says so',
      (tester) async {
    final t = await _connected();
    final m = t.tabs.terminals.single;
    await terminalOpened(t.ffi, 1);
    expect(await _text(tester, m), isNot(contains('Reconnected.')));

    // The connection came back and the remote device kept the shell.
    await t.ffi.events.dispatch({..._peerInfo});
    await terminalOpened(t.ffi, 1, message: 'Reconnected to existing terminal');
    await tester.pump();
    expect(m.terminal.buffer.getText(), isNot(contains('Reconnected.')));

    // Again, and this time it did not.
    await t.ffi.events.dispatch({..._peerInfo});
    await terminalOpened(t.ffi, 1);
    await tester.pump();
    expect(m.terminal.buffer.getText(),
        contains('Reconnected. The previous terminal session ended'));
    expect(t.bind.terminalIds(#sessionOpenTerminal), [1, 1, 1]);
  });

  testWidgets('the remote device\'s text in a line is cut to 200 characters',
      (tester) async {
    final t = await _connected();
    final m = t.tabs.terminals.single;
    await terminalEvent(t.ffi, {
      'type': 'opened',
      'terminal_id': 1,
      'success': false,
      'message': 'x' * 300,
    });
    final text = (await _text(tester, m)).replaceAll(RegExp(r'\s'), '');
    expect(text, 'Failedtoopenterminal:${'x' * 200}');
  });

  group('clipboard write requests', () {
    Future<
        ({
          FFI ffi,
          TerminalTabs tabs,
          TerminalFakeBind bind,
          TerminalModel m
        })> request(String setting, {bool remoteClipboard = true}) async {
      final t = await _connected();
      t.bind.local[kOptionAllowTerminalClipboardWrite] = setting;
      t.ffi.ffiModel.setPermissions({'clipboard': remoteClipboard});
      // Made after the setting, as upstream decides per tab whether it may ask.
      t.tabs.add();
      final m = t.tabs.terminals.last;
      m.terminal.write(osc52('first'));
      m.terminal.write(osc52('latest'));
      await Future<void>.delayed(Duration.zero);
      return (ffi: t.ffi, tabs: t.tabs, bind: t.bind, m: m);
    }

    test('ignored when the remote device turned the clipboard off', () async {
      final clipboard = FakeClipboard();
      final r = await request(kTerminalClipboardWriteUnconfigured,
          remoteClipboard: false);
      expect(r.tabs.clipboardRequest, isNull);
      expect(clipboard.written, isEmpty);
    });

    test('"deny" ignores, "allow" writes without asking', () async {
      var clipboard = FakeClipboard();
      var r = await request(kTerminalClipboardWriteDenied);
      expect(r.tabs.clipboardRequest, isNull);
      expect(clipboard.written, isEmpty);

      clipboard = FakeClipboard();
      r = await request(kTerminalClipboardWriteAllowed);
      expect(r.tabs.clipboardRequest, isNull);
      expect(clipboard.written, ['first', 'latest']);
    });

    test('"allow" whose write fails offers to copy, without a setting',
        () async {
      final clipboard = FakeClipboard(fail: true);
      final r = await request(kTerminalClipboardWriteAllowed);
      expect(r.tabs.clipboardRequest?.persistAllowed, isFalse);
      expect(clipboard.written, isEmpty);
    });

    test('"ask": one banner, "允许" writes the latest and saves the choice',
        () async {
      final clipboard = FakeClipboard();
      final r = await request(kTerminalClipboardWriteUnconfigured);
      expect(r.tabs.clipboardRequest?.persistAllowed, isTrue);
      expect(clipboard.written, isEmpty);

      await r.tabs.allowClipboard();

      expect(clipboard.written, ['latest']);
      expect(r.bind.local[kOptionAllowTerminalClipboardWrite],
          kTerminalClipboardWriteAllowed);
      expect(r.tabs.clipboardRequest, isNull);
    });

    test(
        '"ask": "拒绝" saves it; the banner goes with its terminal or the connection',
        () async {
      final clipboard = FakeClipboard();
      var r = await request(kTerminalClipboardWriteUnconfigured);
      await r.tabs.denyClipboard();
      expect(r.bind.local[kOptionAllowTerminalClipboardWrite],
          kTerminalClipboardWriteDenied);
      expect(r.tabs.clipboardRequest, isNull);
      expect(clipboard.written, isEmpty);

      r = await request(kTerminalClipboardWriteUnconfigured);
      await r.tabs.closeTerminal(r.m);
      expect(r.tabs.clipboardRequest, isNull);

      r = await request(kTerminalClipboardWriteUnconfigured);
      await r.ffi.events.dispatch({
        'name': 'msgbox',
        'type': 'error',
        'title': 'Connection Error',
        'text': 'Connection reset by peer',
        'link': '',
        'hasRetry': 'true',
      });
      expect(r.tabs.canAdd, isFalse);
      expect(r.tabs.clipboardRequest, isNull);
    });
  });
}
