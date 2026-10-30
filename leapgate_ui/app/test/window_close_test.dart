import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/shell/navigation.dart';
import 'package:leapgate_ui/shell/window_close.dart';

import 'session_fakes.dart';

// Closing the main window (01 §2.1 "窗口关闭", §8.1 Q6): sessions or not × portable or
// installed × "Don't show again" / a remembered choice. Device IDs here are made up.

/// The connecting spinner never settles; the close flow needs a few turns for its awaits.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _withSession(WidgetTester tester) async {
  mainNavigation.connect('100200300');
  await tester.pump();
  await tester.pump();
}

Future<void> _closeWindow(WidgetTester tester) async {
  await tester.tap(find.byWidgetPredicate(
      (w) => w is LgIcon && w.icon == LgIcons.windowClose));
  await _settle(tester);
}

void main() {
  late AppFakes fakes;

  setUp(() => fakes = installAppFakes());

  test('what is asked', () {
    expect(
        planWindowClose(
            sessions: 2, installed: false, confirmSessions: true, remembered: null),
        (askSessions: true, askAction: true, action: CloseAction.exit));
    expect(
        planWindowClose(
            sessions: 2,
            installed: false,
            confirmSessions: false,
            remembered: CloseAction.background),
        (askSessions: false, askAction: false, action: CloseAction.background));
    expect(
        planWindowClose(
            sessions: 1, installed: true, confirmSessions: true, remembered: null),
        (askSessions: true, askAction: false, action: CloseAction.background));
    expect(
        planWindowClose(
            sessions: 0, installed: true, confirmSessions: true, remembered: null),
        (askSessions: false, askAction: false, action: CloseAction.background));
  });

  testMainWindow('portable with a session: one dialog asks both, Quit closes',
      (tester) async {
    await pumpMainWindow(tester);
    await _withSession(tester);

    await _closeWindow(tester);
    expect(find.text('断开全部 1 个会话并关闭窗口？'), findsOneWidget);
    expect(find.text('退出 Leapgate'), findsOneWidget);
    expect(find.text('本机将无法接受远程连接，正在使用的出口也将停止'), findsOneWidget);
    expect(find.text('在后台运行'), findsOneWidget);
    expect(find.text('服务和正在使用的出口将继续运行。再次启动 Leapgate 即可恢复窗口。'),
        findsOneWidget);
    expect(find.text('记住此选择'), findsOneWidget);
    expect(find.text('不再提示'), findsOneWidget);

    await tester.tap(find.text('断开'));
    await _settle(tester);
    expect(appCore.sessions.devices, isEmpty);
    expect(fakes.bind.callsTo(#mainOnMainWindowClose), hasLength(1));
    expect(fakes.window, containsAllInOrder(['setPreventClose', 'close']));
    expect(fakes.bind.localOptions, isEmpty);
  });

  testMainWindow('run in background, remembered, no more session question',
      (tester) async {
    await pumpMainWindow(tester);
    await _withSession(tester);

    // Alt+F4 and the taskbar come as the plugin's close event.
    await windowEvent(tester, 'close');
    await _settle(tester);
    await tester.tap(find.text('在后台运行'));
    await tester.tap(find.text('记住此选择'));
    await tester.tap(find.text('不再提示'));
    await tester.pump();
    await tester.tap(find.text('断开'));
    await _settle(tester);

    expect(fakes.window, contains('hide'));
    expect(fakes.window, isNot(contains('close')));
    expect(fakes.bind.localOptions, {
      kOptionEnableConfirmClosingTabs: 'N',
      kOptionLeapgateCloseAction: 'background',
    });
  });

  testMainWindow('remembered and not asked again: closes at once', (tester) async {
    fakes.bind.localOptions[kOptionEnableConfirmClosingTabs] = 'N';
    fakes.bind.localOptions[kOptionLeapgateCloseAction] = 'exit';
    await pumpMainWindow(tester);
    await _withSession(tester);

    await _closeWindow(tester);
    expect(find.text('关闭窗口？'), findsNothing);
    expect(appCore.sessions.devices, isEmpty);
    expect(fakes.window, contains('close'));
  });

  testMainWindow('portable without sessions asks only Q6', (tester) async {
    await pumpMainWindow(tester);

    await _closeWindow(tester);
    expect(find.text('关闭窗口？'), findsOneWidget);
    expect(find.text('退出 Leapgate'), findsOneWidget);
    expect(find.text('不再提示'), findsNothing);

    await tester.tap(find.text('取消'));
    await _settle(tester);
    expect(find.text('关闭窗口？'), findsNothing);
    expect(fakes.window, isNot(contains('close')));
    expect(fakes.window, isNot(contains('hide')));
  });

  testMainWindow('installed: confirms the sessions, then hides to the tray',
      (tester) async {
    fakes.bind.installed = true;
    await pumpMainWindow(tester);
    await _withSession(tester);

    await _closeWindow(tester);
    expect(find.text('断开全部 1 个会话并关闭窗口？'), findsOneWidget);
    expect(find.text('退出 Leapgate'), findsNothing);
    expect(find.text('不再提示'), findsOneWidget);
    await tester.tap(find.text('断开'));
    await _settle(tester);
    expect(fakes.window, contains('hide'));
    expect(appCore.sessions.devices, isEmpty);
  });

  testMainWindow('installed without sessions hides at once', (tester) async {
    fakes.bind.installed = true;
    await pumpMainWindow(tester);

    await _closeWindow(tester);
    expect(find.text('关闭窗口？'), findsNothing);
    expect(fakes.window, contains('hide'));
  });
}
