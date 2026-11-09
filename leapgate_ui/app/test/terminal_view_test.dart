import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/pages/terminal/terminal_view.dart';
import 'package:leapgate_ui/shell/tab_shortcuts.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_feedback.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';

import '../../core/test/terminal_fakes.dart';
import 'session_fakes.dart';

// The terminal view (13 §2.2.6 "P9 桌面要画的状态"), alone in a test window: the shell is
// coder A's. Device IDs are made up.

class _Bind extends AppFakeBind with TerminalBindCalls {}

class _View {
  _View(this.ffi, this.bind);

  final FFI ffi;
  final _Bind bind;
  var disconnects = 0;
  var nextTabs = 0;

  List<String> get sent => [
    for (final c in bind.callsTo(#sessionSendTerminalInput))
      c.namedArguments[#data] as String,
  ];
}

Map<String, dynamic> _peerInfo() => {
  ...peerInfo(platform: 'Linux'),
  'displays': jsonEncode([]),
};

Future<_View> _pump(WidgetTester tester, {bool connected = true}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  installAppFakes();
  final bind = _Bind();
  platformFFI.setBindingForTesting(bind);
  final ffi = appCore.sessions.open('456789123', ConnType.terminal);
  final v = _View(ffi, bind);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
      home: Scaffold(
        body: TabShortcuts(
          onNext: () => v.nextTabs++,
          onPrevious: () {},
          child: TerminalViewPage(
            ffi: ffi,
            active: true,
            lastView: true,
            viewSwitch: const Text('视图切换'),
            route: const Text('直连'),
            onDisconnect: () => v.disconnects++,
          ),
        ),
      ),
    ),
  );
  if (connected) await _connect(tester, v);
  return v;
}

Future<void> _connect(WidgetTester tester, _View v) async {
  await v.ffi.events.dispatch(_peerInfo());
  await tester.pump();
  await tester.pump();
}

Future<void> _opened(WidgetTester tester, _View v, int id) async {
  await terminalOpened(v.ffi, id);
  await tester.pump();
}

Future<void> _keys(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  List<LogicalKeyboardKey> held = const [],
}) async {
  for (final k in held) {
    await tester.sendKeyDownEvent(k);
  }
  await tester.sendKeyEvent(key);
  for (final k in held.reversed) {
    await tester.sendKeyUpEvent(k);
  }
  await tester.pump();
  await tester.pump();
}

const _ctrl = LogicalKeyboardKey.controlLeft;
const _shift = LogicalKeyboardKey.shiftLeft;
const _alt = LogicalKeyboardKey.altLeft;

Finder _button(String label) => find.bySemanticsLabel(label);

LgIconButton _plus(WidgetTester tester) => tester.widget<LgIconButton>(
  find.byWidgetPredicate((w) => w is LgIconButton && w.label == '新建终端'),
);

void main() {
  testWidgets(
    'connecting: no terminal tabs, "+" off, the panel over the view',
    (tester) async {
      final v = await _pump(tester, connected: false);
      expect(find.text('终端 1'), findsNothing);
      expect(_plus(tester).onPressed, isNull);

      await _connect(tester, v);
      expect(find.text('终端 1'), findsOneWidget);
      expect(_plus(tester).onPressed, isNotNull);
      expect(v.bind.terminalIds(#sessionOpenTerminal), [1]);
    },
  );

  testWidgets(
    'tabs: "+", Ctrl+Shift+T/W, Ctrl+number, Alt+arrows, × on the last',
    (tester) async {
      final v = await _pump(tester);
      await tester.tap(_button('新建终端'));
      await tester.pump();
      await _keys(tester, LogicalKeyboardKey.keyT, held: [_ctrl, _shift]);
      expect(find.text('终端 3'), findsOneWidget);
      final tabs = v.ffi.terminals!;
      expect(tabs.selected, 2);

      await _keys(tester, LogicalKeyboardKey.digit1, held: [_ctrl]);
      expect(tabs.selected, 0);
      await _keys(tester, LogicalKeyboardKey.arrowRight, held: [_alt]);
      expect(tabs.selected, 1);

      await _keys(tester, LogicalKeyboardKey.keyW, held: [_ctrl, _shift]);
      expect([for (final m in tabs.terminals) m.terminalId], [1, 3]);

      await tester.tap(find.text('终端 1'));
      await tester.pump();
      expect(tabs.selected, 0);
      await tester.tap(_button('关闭终端').first);
      await tester.pump();
      await tester.tap(_button('关闭终端'));
      await tester.pump();
      expect([for (final m in tabs.terminals) m.terminalId], [3]);
      expect(v.disconnects, 1);
    },
  );

  testWidgets('Ctrl+A goes to the remote terminal, Ctrl+Shift+A selects all', (
    tester,
  ) async {
    final v = await _pump(tester);
    await _opened(tester, v, 1);
    await _keys(tester, LogicalKeyboardKey.keyA, held: [_ctrl]);
    expect(v.sent, ['\x01']);

    await _keys(tester, LogicalKeyboardKey.keyA, held: [_ctrl, _shift]);
    expect(v.sent, ['\x01']);
    expect(v.ffi.terminals!.current!.terminalController.selection, isNotNull);
  });

  testWidgets('the session shortcuts reach the window, not the terminal', (
    tester,
  ) async {
    final v = await _pump(tester);
    await _opened(tester, v, 1);
    v.bind.localOptions[kShortcutLocalConfigKey] = jsonEncode({
      'enabled': true,
      'bindings': [
        {
          'action': kShortcutActionSwitchTabNext,
          // A key xterm would send on (`ESC [1;5C`).
          'mods': ['primary'],
          'key': 'arrow_right',
        },
      ],
    });
    await _keys(tester, LogicalKeyboardKey.arrowRight, held: [_ctrl]);
    expect(v.nextTabs, 1);
    expect(v.sent, isEmpty);
  });

  testWidgets('"⋯": new terminal, keep sessions', (tester) async {
    final v = await _pump(tester);
    await tester.tap(_button('更多'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('断开连接后保持终端会话'));
    await tester.pump();
    expect(v.bind.toggles[kOptionTerminalPersistent], isTrue);

    await tester.tap(_button('更多'));
    await tester.pump();
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate((w) => w is LgMenuItem && w.label == '新建终端'),
    );
    // The menu runs the item after it has closed.
    await tester.pump();
    await tester.pump();
    expect(find.text('终端 2'), findsOneWidget);
  });

  testWidgets('a clipboard request: the banner, "允许" saves and writes', (
    tester,
  ) async {
    final clipboard = FakeClipboard();
    final v = await _pump(tester);
    v.ffi.terminals!.current!.terminal.write(osc52('make'));
    await tester.pump();
    expect(find.textContaining('远程终端中的应用请求写入本机剪贴板'), findsOneWidget);

    await tester.tap(find.text('允许'));
    await tester.pump();
    await tester.pump();
    expect(clipboard.written, ['make']);
    expect(
      v.bind.localOptions[kOptionAllowTerminalClipboardWrite],
      kTerminalClipboardWriteAllowed,
    );
    expect(find.textContaining('远程终端中的应用请求写入本机剪贴板'), findsNothing);
  });

  testWidgets('"断开" asks with two terminals; "取消" keeps them', (tester) async {
    final v = await _pump(tester);
    await disconnectTerminalView(v.ffi);
    expect(appCore.sessions.sessionsOf('456789123'), isEmpty);

    final w = await _pump(tester);
    w.ffi.terminals!.add();
    await tester.pump();
    final done = disconnectTerminalView(w.ffi);
    await tester.pump();
    expect(find.text('断开终端？'), findsOneWidget);
    expect(find.text('2 个终端将关闭。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    await done;
    expect(appCore.sessions.sessionsOf('456789123'), [w.ffi]);

    final again = disconnectTerminalView(w.ffi);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(LgConfirmDialog),
        matching: find.text('断开'),
      ),
    );
    await tester.pump();
    await again;
    expect(appCore.sessions.sessionsOf('456789123'), isEmpty);
  });

  testWidgets('the lines the terminal writes are in the UI\'s language', (
    tester,
  ) async {
    final v = await _pump(tester);
    await terminalEvent(v.ffi, {
      'type': 'opened',
      'terminal_id': 1,
      'success': false,
      'message': 'no shell found',
    });
    await tester.pump();
    await tester.pump();
    expect(
      v.ffi.terminals!.current!.terminal.buffer.getText(),
      contains('无法打开终端：no shell found'),
    );
  });
}
