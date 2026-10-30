import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/shell/navigation.dart';

import 'session_fakes.dart';

// The session tab: the connection panel in each state of 01 P2 block D, the tab's status, the
// keyboard rules of 04-M2a拆法.md §4 and the toolbar. Device IDs here are made up.

const _id = '100200300';

/// Opens a remote desktop of [id] the way the home page does and returns its session.
Future<FFI> _open(WidgetTester tester, {String id = _id}) async {
  mainNavigation.connect(id);
  await tester.pump();
  await tester.pump();
  return appCore.sessions.sessionsOf(id.replaceAll(' ', '')).single;
}

/// Status marks draw their label as rich text after the mark.
Finder _mark(String label) => find.textContaining(
    RegExp('^￼+${RegExp.escape(label)}\$'),
    findRichText: true);

FocusNode _imageFocus(WidgetTester tester, FFI s) => tester
    .widgetList<Focus>(find.byWidgetPredicate(
        (w) => w is Focus && w.focusNode?.debugLabel == 'rawkeyFocusNode'))
    .map((w) => w.focusNode!)
    .first;

void main() {
  late AppFakes fakes;

  setUp(() => fakes = installAppFakes());

  group('the connection panel', () {
    testMainWindow('connecting: two steps, cancel closes the tab (01 §4.1 stage 1)',
        (tester) async {
      await pumpMainWindow(tester);
      mainNavigation.connect('100 200 300');
      await tester.pump();
      await tester.pump();

      expect(callsTo(fakes, #sessionAddSync).single[#id], _id);
      expect(find.text('正在连接 100 200 300…'), findsOneWidget);
      expect(_mark('建立连接'), findsOneWidget);
      expect(_mark('验证身份'), findsOneWidget);
      expect(_mark('正在连接…'), findsOneWidget); // the tab
      expect(fakes.window, contains('setTitle'));

      await tester.tap(find.text('取消'));
      await tester.pump();
      expect(appCore.sessions.devices, isEmpty);
    });

    testMainWindow('password: Connect is off while empty, then logs in', (tester) async {
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s, connectionReady());
      await emit(tester, fakes, s, msgbox('input-password', 'Password Required', ''));

      // The route shows from "waiting for the image" on (01 P2 block A).
      expect(_mark('正在连接…'), findsOneWidget);
      expect(_mark('经中继'), findsNothing);
      expect(find.text('记住密码'), findsOneWidget);
      await tester.tap(find.text('连接'));
      await tester.pump();
      expect(callsTo(fakes, #sessionLogin), isEmpty);
      await tester.enterText(find.byType(EditableText), ' pw-1 ');
      await tester.pump();
      await tester.tap(find.text('连接'));
      await tester.pump();

      expect(callsTo(fakes, #sessionLogin).single[#password], 'pw-1');
      expect(find.text('正在验证…'), findsOneWidget);
    });

    testMainWindow('wrong password: the error under the field', (tester) async {
      fakes.lg.reasons['Wrong Password'] = 'wrong_password';
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s, connectionReady());
      await emit(tester, fakes, s,
          msgbox('re-input-password', 'Login Error', 'Wrong Password'));

      expect(find.text('密码错误'), findsOneWidget);
    });

    testMainWindow('2FA: six digits submit, a wrong code says so', (tester) async {
      fakes.lg.reasons['Wrong 2FA Code'] = 'wrong_2fa';
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s, connectionReady());
      await emit(tester, fakes, s, msgbox('input-2fa', '2FA Required', ''));

      expect(find.text('验证'), findsOneWidget);
      expect(find.text('验证码错误或已过期'), findsNothing);
      await tester.enterText(find.byType(EditableText), '123456');
      await tester.pump();
      expect(callsTo(fakes, #sessionSend2Fa).single[#code], '123456');

      await emit(tester, fakes, s,
          msgbox('input-2fa', 'Wrong 2FA Code', 'Wrong 2FA Code'));
      expect(find.text('验证码错误或已过期'), findsOneWidget);
    });

    testMainWindow('waiting for the remote user counts the time', (tester) async {
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s, connectionReady());
      await emit(tester, fakes, s, msgbox('wait-remote-accept-nook', 'Prompt', ''));

      expect(find.text('正在等待对方接受…'), findsOneWidget);
      expect(find.text('已等待 0 秒'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('已等待 3 秒'), findsOneWidget);
      await tester.pump(const Duration(seconds: 62));
      expect(find.text('已等待 1 分 5 秒'), findsOneWidget);
    });

    testMainWindow('Windows user sessions: pick one, no cancel', (tester) async {
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s, connectionReady());
      await emit(tester, fakes, s, {
        'name': 'set_multiple_windows_session',
        'windows_sessions': jsonEncode([
          {'sid': '1', 'name': 'alice'},
          {'sid': '2', 'name': 'bob'},
        ]),
      });

      expect(find.text('远程设备上有多个用户已登录，请选择要连接的用户。'), findsOneWidget);
      expect(find.text('取消'), findsNothing);
      await tester.tap(find.text('bob'));
      await tester.pump();
      await tester.tap(find.text('连接'));
      await tester.pump();
      expect(callsTo(fakes, #sessionSendSelectedSessionId).single[#sid], '2');
    });

    testMainWindow('insecure: Enter disconnects (01 P2 block D)', (tester) async {
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s,
          msgbox('custom-nocancel-nook-hasclose-insecure-connection', '', ''));

      expect(find.text('此连接未使用端到端加密，传输的内容可能被第三方读取。'), findsOneWidget);
      expect(find.text('继续'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(callsTo(fakes, #sessionSetCommon).single[#value], 'N');
      expect(appCore.sessions.devices, isEmpty);
    });

    testMainWindow('insecure: Enter on "Continue" continues, not the default',
        (tester) async {
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s,
          msgbox('custom-nocancel-nook-hasclose-insecure-connection', '', ''));

      // From the card, Tab goes to "Disconnect", then to "Continue".
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(callsTo(fakes, #sessionSetCommon).single[#value], 'Y');
      expect(appCore.sessions.devices, [_id]);
    });

    testMainWindow('an error: Enter does nothing, "Use relay" is not saved by it',
        (tester) async {
      fakes.lg.reasons[''] = 'direct_reset';
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s, msgbox('relay-hint', 'Connection Error', ''));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(callsTo(fakes, #sessionReconnect), isEmpty);
    });

    testMainWindow('waiting for the image: a hint after a few seconds', (tester) async {
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s, connectionReady());
      await emit(tester, fakes, s, peerInfo());
      await emit(tester, fakes, s,
          msgbox('success', 'Successful', 'Connected, waiting for image...'));

      expect(find.text('已连接，正在等待画面…'), findsOneWidget);
      expect(find.text('远程设备可能已锁屏或未连接显示器。'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('远程设备可能已锁屏或未连接显示器。'), findsOneWidget);
    });

    testMainWindow('an error that retries: countdown, "已中断" on the tab', (tester) async {
      fakes.lg.reasons['Timeout'] = 'timeout';
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s,
          msgbox('error', 'Connection Error', 'Timeout', hasRetry: true));

      expect(find.text('连接超时。'), findsOneWidget);
      expect(find.text('1 秒后重试（第 1 次）'), findsOneWidget);
      expect(_mark('已中断'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(callsTo(fakes, #sessionReconnect).single[#forceRelay], false);
    });

    testMainWindow('direct connection reset: "Use relay" forces the relay', (tester) async {
      fakes.lg.reasons[''] = 'direct_reset';
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s, msgbox('relay-hint', 'Connection Error', ''));

      expect(find.textContaining('直连已中断'), findsOneWidget);
      expect(_mark('连接失败'), findsOneWidget);
      await tester.tap(find.text('改用中继'));
      await tester.pump();
      expect(callsTo(fakes, #sessionReconnect).single[#forceRelay], true);
    });

    testMainWindow('unknown ID: "Change ID" puts it into the connect box', (tester) async {
      fakes.lg.reasons['ID does not exist'] = 'id_not_exist';
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(
          tester, fakes, s, msgbox('error', 'Connection Error', 'ID does not exist'));

      expect(
          find.text('未找到 ID 为 100 200 300 的设备。请确认 ID 正确，且该设备与本机使用同一服务器。'),
          findsOneWidget);
      await tester.tap(find.text('修改 ID'));
      await tester.pump();
      expect(connectBoxFocusRequests.text, _id);
      // The failed tab is closed.
      expect(appCore.sessions.devices, isEmpty);
      expect(find.text('修改 ID'), findsNothing);
    });

    testMainWindow('closed by the remote user: "已断开", reconnect or close', (tester) async {
      fakes.lg.reasons['Closed manually by the peer'] = 'closed_by_peer';
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s,
          msgbox('error', 'Connection Error', 'Closed manually by the peer'));

      expect(find.text('对方已断开连接。'), findsOneWidget);
      expect(_mark('已断开'), findsOneWidget);
      expect(find.text('重新连接'), findsOneWidget);
      expect(find.text('关闭标签'), findsOneWidget);
    });

    testMainWindow('a reason without a code shows the text as sent', (tester) async {
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s,
          msgbox('error', 'Connection Error', 'Refused by the server policy'));

      expect(find.text('Refused by the server policy'), findsOneWidget);
    });

    testMainWindow('restarting: last frame dimmed, close the tab', (tester) async {
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s, msgbox('restarting', 'Restarting remote device',
          'Connection in progress. Please wait.'));

      expect(find.text('远程设备正在重启，完成后将自动重新连接。'), findsOneWidget);
      expect(find.text('关闭标签'), findsOneWidget);
    });

    testMainWindow('connected: the panel goes, the toolbar and a toast come', (tester) async {
      await pumpMainWindow(tester);
      final s = await _open(tester);
      await emit(tester, fakes, s, connectionReady());
      await emit(tester, fakes, s, peerInfo());

      expect(_mark('建立连接'), findsNothing);
      expect(find.text('已建立中继连接'), findsOneWidget);
      expect(_mark('经中继'), findsNWidgets(2)); // tab and toolbar
      expect(find.text('画面'), findsOneWidget);
      expect(find.text('断开'), findsOneWidget);
      // One monitor: no monitor menu.
      expect(find.text('显示器'), findsNothing);
      expect(fakes.window.last, 'setTitle');
    });
  });

  group('keyboard', () {
    testMainWindow('switching tabs lets go before the other tab can take it', (tester) async {
      await pumpMainWindow(tester);
      final a = await _open(tester);
      await emit(tester, fakes, a, connectionReady());
      await emit(tester, fakes, a, peerInfo());
      _imageFocus(tester, a).requestFocus();
      await tester.pump();
      expect(callsTo(fakes, #sessionEnterOrLeave).single[#enter], true);

      final before = fakes.bind.calls.length;
      final b = await _open(tester, id: '400500600');
      final calls = [
        for (final c in fakes.bind.calls.skip(before))
          if (c.memberName == #sessionEnterOrLeave)
            (c.namedArguments[#sessionId], c.namedArguments[#enter])
          else if (c.memberName == #hostStopSystemKeyPropagate)
            (#hostStop, c.namedArguments[#stopped])
      ];
      // The old tab lets go first and nothing takes the keyboard on its own.
      expect(calls.take(2), [(a.sessionId, false), (#hostStop, true)]);
      expect(calls.where((c) => c.$2 == true && c.$1 != #hostStop), isEmpty);
      expect(calls.where((c) => c.$1 == b.sessionId), isEmpty);
    });

    testMainWindow('closing the tab releases the keys before the session closes',
        (tester) async {
      await pumpMainWindow(tester);
      final a = await _open(tester);
      await emit(tester, fakes, a, connectionReady());
      await emit(tester, fakes, a, peerInfo());
      _imageFocus(tester, a).requestFocus();
      await tester.pump();

      await tester.tap(find.text('断开'));
      await tester.pump();

      final order = [
        for (final c in fakes.bind.calls)
          if (c.memberName == #sessionEnterOrLeave)
            c.namedArguments[#enter]
          else if (c.memberName == #sessionClose)
            #sessionClose
      ];
      expect(order.indexOf(false), lessThan(order.indexOf(#sessionClose)));
      expect(order.first, true);
      expect(appCore.sessions.devices, isEmpty);
    });

    testMainWindow('a panel coming up, or the window losing focus, lets go', (tester) async {
      await pumpMainWindow(tester);
      final a = await _open(tester);
      await emit(tester, fakes, a, connectionReady());
      await emit(tester, fakes, a, peerInfo());
      final image = _imageFocus(tester, a);

      image.requestFocus();
      await tester.pump();
      await windowEvent(tester, 'blur');
      expect(image.hasFocus, false);
      expect(callsTo(fakes, #sessionEnterOrLeave).last[#enter], false);

      await windowEvent(tester, 'focus');
      image.requestFocus();
      await tester.pump();
      expect(callsTo(fakes, #sessionEnterOrLeave).last[#enter], true);
      await emit(tester, fakes, a,
          msgbox('error', 'Connection Error', 'Timeout', hasRetry: true));
      expect(image.hasFocus, false);
      expect(callsTo(fakes, #sessionEnterOrLeave).last[#enter], false);
    });
  });

  group('the toolbar', () {
    testMainWindow('restart asks over this tab only, then restarts', (tester) async {
      await pumpMainWindow(tester);
      final a = await _open(tester);
      await emit(tester, fakes, a, connectionReady(direct: true));
      await emit(tester, fakes, a, peerInfo());

      await tester.tap(find.text('操作'));
      await tester.pumpAndSettle();
      expect(find.text('发送 Ctrl+Alt+Del'), findsOneWidget);
      await tester.tap(find.text('重启远程设备'));
      await tester.pumpAndSettle();
      expect(find.text('重启远程设备？'), findsOneWidget);
      expect(find.text('远程设备重启期间连接将中断，完成后将自动重新连接。'), findsOneWidget);

      await tester.tap(find.text('重启'));
      await tester.pumpAndSettle();
      expect(callsTo(fakes, #sessionRestartRemoteDevice), hasLength(1));
      expect(find.text('重启远程设备？'), findsNothing);
    });

    testMainWindow('restart: Enter on "Cancel" cancels', (tester) async {
      await pumpMainWindow(tester);
      final a = await _open(tester);
      await emit(tester, fakes, a, connectionReady(direct: true));
      await emit(tester, fakes, a, peerInfo());
      await tester.tap(find.text('操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重启远程设备'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('重启远程设备？'), findsNothing);
      expect(callsTo(fakes, #sessionRestartRemoteDevice), isEmpty);
    });

    testMainWindow('pin is saved where upstream keeps it', (tester) async {
      await pumpMainWindow(tester);
      final a = await _open(tester);
      await emit(tester, fakes, a, connectionReady(direct: true));
      await emit(tester, fakes, a, peerInfo());

      await tester.tap(find.bySemanticsLabel('固定'));
      await tester.pump();
      expect(fakes.bind.flutterOptions['remoteMenubarState'], '{"pin":true}');
      expect(find.bySemanticsLabel('取消固定'), findsOneWidget);
    });

    testMainWindow('a connection lost in full screen leaves full screen', (tester) async {
      await pumpMainWindow(tester);
      final a = await _open(tester);
      await emit(tester, fakes, a, connectionReady(direct: true));
      await emit(tester, fakes, a, peerInfo());
      await tester.tap(find.bySemanticsLabel('全屏'));
      await tester.pump();
      expect(find.text('主页'), findsNothing);
      expect(find.bySemanticsLabel('最小化'), findsOneWidget);

      await emit(tester, fakes, a,
          msgbox('error', 'Connection Error', 'Timeout', hasRetry: true));
      expect(find.text('主页'), findsOneWidget);
    });

    testMainWindow('display menu: scale and image quality', (tester) async {
      await pumpMainWindow(tester);
      final a = await _open(tester);
      await emit(tester, fakes, a, connectionReady(direct: true));
      await emit(tester, fakes, a, peerInfo(displays: 2));

      expect(find.text('显示器'), findsOneWidget);
      await tester.tap(find.text('画面'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('原始大小'));
      await tester.pumpAndSettle();
      expect(callsTo(fakes, #sessionSetViewStyle).single[#value], 'original');

      await tester.tap(find.text('画面'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('速度优先'));
      await tester.pumpAndSettle();
      expect(callsTo(fakes, #sessionSetImageQuality).single[#value], 'low');
    });

    testMainWindow('full screen hides the title bar and shows the name in the toolbar',
        (tester) async {
      await pumpMainWindow(tester);
      final a = await _open(tester);
      await emit(tester, fakes, a, connectionReady(direct: true));
      await emit(tester, fakes, a, peerInfo());

      await tester.tap(find.bySemanticsLabel('全屏'));
      await tester.pump();
      expect(find.text('主页'), findsNothing);
      expect(find.text('host'), findsOneWidget); // the name in the toolbar

      await tester.tap(find.bySemanticsLabel('退出全屏'));
      await tester.pump();
      expect(find.text('主页'), findsOneWidget);
    });
  });

  testMainWindow('a tab out of sight gets no frames, shown again it asks for one (V1)',
      (tester) async {
    await pumpMainWindow(tester);
    final a = await _open(tester);
    final b = await _open(tester, id: '400500600');
    expect(fakes.lg.visible, [(a.sessionId, false)]);

    await tester.tap(find.text('100 200 300'));
    await tester.pump();
    expect(fakes.lg.visible.skip(1),
        unorderedEquals([(b.sessionId, false), (a.sessionId, true)]));
    expect(callsTo(fakes, #sessionRefresh).single[#sessionId], a.sessionId);
  });

  testMainWindow(
      'waiting for the image, away and back: no error, one wake 1.5 s later (V1)',
      (tester) async {
    await pumpMainWindow(tester);
    final a = await _open(tester);
    await emit(tester, fakes, a, connectionReady());
    await emit(tester, fakes, a, peerInfo());
    await emit(tester, fakes, a,
        msgbox('success', 'Successful', 'Connected, waiting for image...'));
    await _open(tester, id: '400500600');
    await tester.pump(const Duration(seconds: 5));
    expect(callsTo(fakes, #sessionInputOsPassword), isEmpty);

    await tester.tap(find.text('host')); // the tab, named after the peer info

    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('已连接，正在等待画面…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(callsTo(fakes, #sessionInputOsPassword), hasLength(1));
  });

  testMainWindow('an IME composition is dropped when the tab is left (§4 item 4)',
      (tester) async {
    await pumpMainWindow(tester);
    final s = await _open(tester);
    await emit(tester, fakes, s, connectionReady());
    await emit(tester, fakes, s, msgbox('input-password', 'Password Required', ''));
    await tester.showKeyboard(find.byType(EditableText));
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'xab',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 1, end: 3),
    ));
    await tester.pump();

    await tester.tap(find.text('主页'));
    await tester.pump();
    await tester.tap(find.text('100 200 300'));
    await tester.pump();
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'x');
  });

  testMainWindow('"/r" alone opens nothing', (tester) async {
    await pumpMainWindow(tester);
    mainNavigation.connect('/r');
    await tester.pump();
    await tester.pump();
    expect(appCore.sessions.devices, isEmpty);
  });

  testMainWindow('"+" goes home and asks for the connect box', (tester) async {
    await pumpMainWindow(tester);
    await _open(tester);
    var asked = 0;
    void count() => asked++;
    connectBoxFocusRequests.addListener(count);
    addTearDown(() => connectBoxFocusRequests.removeListener(count));

    await tester.tap(find.bySemanticsLabel('新建连接'));
    await tester.pump();
    expect(asked, 1);
    expect(connectBoxFocusRequests.text, null);
    expect(_mark('建立连接').hitTestable(), findsNothing);
  });

  testMainWindow('"/r" connects through the relay, the tab keyed by the ID', (tester) async {
    await pumpMainWindow(tester);
    mainNavigation.connect('100200300/r', password: 'pw');
    await tester.pump();
    await tester.pump();

    final add = callsTo(fakes, #sessionAddSync).single;
    expect(add[#id], _id);
    expect(add[#forceRelay], true);
    expect(add[#password], 'pw');
    expect(appCore.sessions.devices, [_id]);
  });
}
