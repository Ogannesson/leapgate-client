import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/camera_names.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show PeerCategory;
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/pages/home/peer_views.dart';
import 'package:leapgate_ui/pages/session/connection_panel.dart';
import 'package:leapgate_ui/pages/session/session_page.dart';
import 'package:leapgate_ui/pages/terminal/terminal_view.dart';
import 'package:leapgate_ui/shell/navigation.dart';
import 'package:leapgate_ui/shell/session_views.dart';
import 'package:leapgate_ui/shell/tab_overlays.dart';
import 'package:leapgate_ui/shell/tab_shortcuts.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_device.dart';
import 'package:leapgate_ui/widgets/lg_feedback.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_session_toolbar.dart';
import 'package:leapgate_ui/widgets/lg_title_bar.dart';

import '../../core/test/terminal_fakes.dart' show TerminalBindCalls;
import 'home_fakes.dart' show FakeNavigation;
import 'session_fakes.dart';

/// The app's fakes with the terminal's calls (`FFI.start` sets `IS_TERMINAL_ADMIN`, a terminal
/// view opens its terminals).
class _TerminalBind extends AppFakeBind with TerminalBindCalls {}

/// [child] in Chinese, light, compact.
Widget _app(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
  home: child,
);

// The session tab with four kinds of view (13 §0.4 ②, §2.1, §3; `LEAPGATE.md` §10.18): the view
// switch, the tab's menu and marks, full screen, closing, the camera view and the administrator
// account of the terminal's connection panel. The terminal view itself is coder B's placeholder
// here. Device IDs are made up.

const _id = '100200300';

void main() {
  late AppFakes fakes;
  final realDisplayNames = sessionDisplayNames;

  setUp(() {
    final app = installAppFakes();
    final bind = _TerminalBind();
    platformFFI.setBindingForTesting(bind);
    fakes = (bind: bind, lg: app.lg, window: app.window);
  });
  tearDown(() => sessionDisplayNames = realDisplayNames);

  Future<FFI> open(
    WidgetTester tester,
    ConnType kind, {
    String id = _id,
    bool terminalAdmin = false,
  }) async {
    kind == ConnType.defaultConn
        ? mainNavigation.connect(id)
        : mainNavigation.openView(id, kind, terminalAdmin: terminalAdmin);
    await tester.pump();
    await tester.pump();
    return appCore.sessions
        .sessionsOf(id)
        .firstWhere((v) => v.connType == kind);
  }

  Future<void> ready(
    WidgetTester tester,
    FFI s, {
    String platform = 'Windows',
    int displays = 1,
  }) async {
    await emit(tester, fakes, s, connectionReady(direct: true));
    await emit(
      tester,
      fakes,
      s,
      peerInfo(platform: platform, displays: displays),
    );
  }

  LgTitleBar titleBar(WidgetTester tester) =>
      tester.widget<LgTitleBar>(find.byType(LgTitleBar));

  /// A view still connecting keeps a spinner turning, which `pumpAndSettle` waits out forever.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder toolbarButton(String label) => find.byWidgetPredicate(
    (w) => w is LgToolbarMenuButton && w.label == label,
  );

  group('the view switch and the tab (13 §0.4 ②)', () {
    testMainWindow(
      'four views on a Windows device; a Mac has no camera (R3-Q12)',
      (tester) async {
        await pumpMainWindow(tester);
        await ready(tester, await open(tester, ConnType.defaultConn));
        await tester.tap(toolbarButton('远程桌面'));
        await settle(tester);
        for (final name in ['文件传输', '终端', '摄像头']) {
          expect(find.text(name), findsOneWidget);
        }
        expect(find.text('未打开'), findsNWidgets(3));

        // Picking the camera opens it in the tab, on the session page.
        await tester.tap(find.text('摄像头'));
        await tester.pump();
        await tester.pump();
        final camera = appCore.sessions.sessionsOf(_id).last;
        expect(camera.connType, ConnType.viewCamera);
        expect(
          tester
              .widgetList<SessionPage>(
                find.byType(SessionPage, skipOffstage: false),
              )
              .singleWhere((p) => p.ffi == camera)
              .active,
          true,
        );

        await ready(
          tester,
          await open(tester, ConnType.defaultConn, id: '400500600'),
          platform: 'Mac OS',
        );
        await tester.tap(toolbarButton('远程桌面'));
        await settle(tester);
        expect(find.text('终端'), findsOneWidget);
        expect(find.text('摄像头'), findsNothing);
      },
    );

    testMainWindow(
      'the tab menu offers the terminal and the camera the tab has not opened, not the camera '
      'of a Mac',
      (tester) async {
        await pumpMainWindow(tester);
        await ready(
          tester,
          await open(tester, ConnType.defaultConn),
          platform: 'Mac OS',
        );
        titleBar(tester).onTabContextMenu!(1, const Offset(300, 20));
        await settle(tester);
        expect(find.text('打开文件传输'), findsOneWidget);
        expect(find.text('查看摄像头'), findsNothing);
        await tester.tap(find.text('打开终端'));
        await tester.pump();
        await tester.pump();
        expect(appCore.sessions.sessionsOf(_id).map((v) => v.connType), [
          ConnType.defaultConn,
          ConnType.terminal,
        ]);

        titleBar(tester).onTabContextMenu!(1, const Offset(300, 20));
        await settle(tester);
        expect(find.text('打开终端'), findsNothing);
      },
    );

    testMainWindow(
      'unread messages of the remote desktop and the camera add up on the tab (R3-Q17)',
      (tester) async {
        await pumpMainWindow(tester);
        final desk = await open(tester, ConnType.defaultConn);
        final camera = await open(tester, ConnType.viewCamera);
        desk.chatModel.receive('a');
        await tester.pump();
        expect(titleBar(tester).sessions.single.unread, 1);
        mainNavigation.showHome();
        await tester.pump();
        camera.chatModel.receive('b');
        await tester.pump();
        expect(titleBar(tester).sessions.single.unread, 2);
      },
    );

    testMainWindow(
      'full screen belongs to the view it was entered in: the camera\'s ends when it closes, '
      'not when another view does (13 §2.2.2 block I)',
      (tester) async {
        await pumpMainWindow(tester);
        final desk = await open(tester, ConnType.defaultConn);
        final camera = await open(tester, ConnType.viewCamera);
        stateGlobal.setFullscreen(true);
        await tester.pump();
        await appCore.sessions.close(camera);
        await tester.pump();
        expect(stateGlobal.fullscreen.value, false);

        final terminal = await open(tester, ConnType.terminal);
        mainNavigation.connect(_id);
        await tester.pump();
        stateGlobal.setFullscreen(true);
        await tester.pump();
        await appCore.sessions.close(terminal);
        await tester.pump();
        expect(stateGlobal.fullscreen.value, true);
        await appCore.sessions.close(desk);
        await tester.pump();
        stateGlobal.setFullscreen(false);
      },
    );

    testMainWindow(
      'the terminal: the view switch names the administrator\'s and goes to it; the tab '
      'shortcut "关闭标签" is the shell\'s while it shows',
      (tester) async {
        await pumpMainWindow(tester);
        final terminal = await open(
          tester,
          ConnType.terminal,
          terminalAdmin: true,
        );
        expect(terminal.terminalAdmin, true);
        expect(usesViewBar(terminal), true);
        final page = tester.widget<TerminalViewPage>(
          find.byType(TerminalViewPage),
        );
        expect(page.active, true);
        expect(page.lastView, true);
        expect(
          tester.widget<TabShortcuts>(find.byType(TabShortcuts)).onCloseTab,
          isNotNull,
        );

        // From the remote desktop beside it, the switch has "终端（管理员）"; "终端" goes to it.
        await ready(tester, await open(tester, ConnType.defaultConn));
        expect(
          tester.widget<TabShortcuts>(find.byType(TabShortcuts)).onCloseTab,
          isNull,
        );
        await tester.tap(toolbarButton('远程桌面'));
        await settle(tester);
        await tester.tap(find.text('终端（管理员）'));
        await tester.pump();
        await tester.pump();
        expect(appCore.sessions.sessionsOf(_id), hasLength(2));
        expect(
          tester.widget<TerminalViewPage>(find.byType(TerminalViewPage)).active,
          true,
        );
        expect(
          tester.widget<TabShortcuts>(find.byType(TabShortcuts)).onCloseTab,
          isNotNull,
        );
      },
    );

    /// The terminal view of [_id] with [count] terminals, in a background tab: the remote
    /// desktop of another device is opened after it and selected.
    Future<FFI> backgroundTerminal(WidgetTester tester, int count) async {
      await pumpMainWindow(tester);
      final terminal = await open(tester, ConnType.terminal);
      await ready(tester, terminal, platform: 'Linux');
      for (var i = 1; i < count; i++) {
        terminal.terminals!.add();
      }
      await tester.pump();
      expect(terminal.terminals!.terminals, hasLength(count));
      await ready(
        tester,
        await open(tester, ConnType.defaultConn, id: '100200301'),
      );
      expect(titleBar(tester).selected, 2);
      return terminal;
    }

    testMainWindow(
      'a background tab of the terminal alone, two terminals not kept: "×" selects it and '
      'asks as its "断开" (R3-Q15)',
      (tester) async {
        final terminal = await backgroundTerminal(tester, 2);
        expect(terminal.terminals!.needsDisconnectConfirm, true);
        titleBar(tester).onCloseTab(1);
        await tester.pump();
        await tester.pump();
        expect(titleBar(tester).selected, 1);
        expect(find.text('断开终端？'), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(LgConfirmDialog),
            matching: find.text('断开'),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(appCore.sessions.sessionsOf(_id), isEmpty);
      },
    );

    testMainWindow(
      'a background tab of the terminal alone that does not ask: "×" closes it where it is, '
      'the selected tab stays',
      (tester) async {
        await backgroundTerminal(tester, 1);
        titleBar(tester).onCloseTab(1);
        await tester.pump();
        await tester.pump();
        expect(appCore.sessions.sessionsOf(_id), isEmpty);
        expect(find.text('断开终端？'), findsNothing);
        // Selecting it first would have left the home page selected once it closed.
        expect(titleBar(tester).selected, 1);
        expect(titleBar(tester).sessions, hasLength(1));
        expect(appCore.sessions.devices, ['100200301']);
      },
    );
  });

  group('the camera view (13 §3.2)', () {
    testMainWindow(
      'the toolbar has no "输入" or "会话"; the panel says why and closes the camera alone',
      (tester) async {
        await pumpMainWindow(tester);
        await open(tester, ConnType.defaultConn);
        final camera = await open(tester, ConnType.viewCamera);
        await ready(tester, camera);
        expect(toolbarButton('摄像头'), findsOneWidget);
        expect(toolbarButton('画面'), findsOneWidget);
        expect(toolbarButton('输入'), findsNothing);
        expect(toolbarButton('会话'), findsNothing);

        fakes.lg.reasons['No cameras'] = 'no_cameras';
        await emit(
          tester,
          fakes,
          camera,
          msgbox('error', 'Connection Error', 'No cameras'),
        );
        expect(find.text('远程设备上未找到可用的摄像头。'), findsOneWidget);
        expect(find.text('重试'), findsNothing);
        await tester.tap(find.text('关闭摄像头'));
        await settle(tester);
        expect(
          appCore.sessions.sessionsOf(_id).single.connType,
          ConnType.defaultConn,
        );
      },
    );

    testMainWindow('waiting for the image: the hint is about the camera', (
      tester,
    ) async {
      await pumpMainWindow(tester);
      final camera = await open(tester, ConnType.viewCamera);
      await ready(tester, camera);
      await emit(
        tester,
        fakes,
        camera,
        msgbox('success', 'Successful', 'Connected, waiting for image...'),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('远程设备的摄像头可能正被其他应用使用。'), findsOneWidget);
      expect(find.text('远程设备可能已锁屏或未连接显示器。'), findsNothing);
    });

    testMainWindow(
      'two cameras: the switch names the one shown and lists them with their names (R3-Q18)',
      (tester) async {
        var reads = 0;
        sessionDisplayNames = (_) {
          reads++;
          return '["Integrated Camera", ""]';
        };
        await pumpMainWindow(tester);
        final camera = await open(tester, ConnType.viewCamera);
        await ready(tester, camera, displays: 2);
        final button = tester.widget<LgToolbarMenuButton>(
          toolbarButton('摄像头 1'),
        );
        expect(button.semanticLabel, '切换摄像头，当前为摄像头 1');

        await tester.tap(toolbarButton('摄像头 1'));
        await settle(tester);
        expect(find.text('Integrated Camera'), findsOneWidget);
        expect(find.text('摄像头 2'), findsOneWidget);
        // Read once for the peer info, however often the toolbar builds, as long as no other
        // camera was switched to (that may make a new first display and read again).
        expect(reads, 1);
      },
    );

    testMainWindow(
      'a permission withheld after the login is no revocation for a camera',
      (tester) async {
        await pumpMainWindow(tester);
        final camera = await open(tester, ConnType.viewCamera);
        await ready(tester, camera);
        await emit(tester, fakes, camera, {
          'name': 'permission',
          'keyboard': 'false',
        });
        expect(find.text('对方已关闭键盘和鼠标控制权限'), findsNothing);
        await emit(tester, fakes, camera, {
          'name': 'permission',
          'recording': 'false',
        });
        expect(find.text('对方已关闭录制权限'), findsOneWidget);
      },
    );

    testMainWindow(
      'the input menu\'s shortcuts are the remote desktop\'s: in the camera they do nothing '
      '(13 §3.2 "键盘")',
      (tester) async {
        await pumpMainWindow(tester);
        final desk = await open(tester, ConnType.defaultConn);
        await ready(tester, desk);
        final camera = await open(tester, ConnType.viewCamera);
        await ready(tester, camera);
        for (final s in [desk, camera]) {
          s.shortcutModel.onTriggered(kShortcutActionToggleReverseMouseWheel);
          await settle(tester);
        }
        expect(
          callsTo(
            fakes,
            #sessionSetReverseMouseWheel,
          ).map((c) => c[#sessionId]),
          [desk.sessionId],
        );
      },
    );

    testMainWindow(
      'a screenshot while all cameras show: the notice says cameras (13 §3.2 block E)',
      (tester) async {
        sessionDisplayNames = (_) => '[]';
        await pumpMainWindow(tester);
        final camera = await open(tester, ConnType.viewCamera);
        await ready(tester, camera, displays: 2);
        camera.ffiModel.pi.currentDisplay = kAllDisplayValue;
        camera.requests.takeScreenshot();
        await tester.pump();
        expect(find.text('显示全部摄像头时无法截图，请先切换到单个摄像头'), findsOneWidget);
        expect(find.text('显示全部显示器时无法截图，请先切换到单个显示器'), findsNothing);
      },
    );
  });

  group('the terminal\'s connection panel (13 §2.2.2 block H, §2.2.3)', () {
    Future<FFI> panel(WidgetTester tester) async {
      final s = appCore.sessions.open(
        _id,
        ConnType.terminal,
        terminalAdmin: true,
      );
      addTearDown(() => appCore.sessions.closeDevice(_id));
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(Scaffold(body: ConnectionPanel(ffi: s, active: true))),
      );
      await emit(tester, fakes, s, connectionReady());
      return s;
    }

    testWidgets('Enter in the username moves on to the system password, no login', (
      tester,
    ) async {
      final s = await panel(tester);
      await emit(
        tester,
        fakes,
        s,
        msgbox('terminal-admin-login', 'Terminal', ''),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), 'admin');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(callsTo(fakes, #sessionLogin), isEmpty);
      expect(tester.widget<EditableText>(fields.at(1)).focusNode.hasFocus, true);

      // Enter in the system password signs in.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(callsTo(fakes, #sessionLogin).single[#osUsername], 'admin');
    });

    testWidgets('the administrator account: "登录" once the username is in', (
      tester,
    ) async {
      final s = await panel(tester);
      await emit(
        tester,
        fakes,
        s,
        msgbox('terminal-admin-login', 'Terminal', ''),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('远程设备上的管理员账户'), findsOneWidget);
      expect(find.text('终端将以 SYSTEM 账户运行'), findsOneWidget);
      expect(find.text('记住密码'), findsNothing);

      await tester.tap(find.text('登录'));
      await tester.pump();
      expect(callsTo(fakes, #sessionLogin), isEmpty);
      final fields = find.byType(EditableText);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), 'admin');
      await tester.enterText(fields.at(1), 'os-pw');
      await tester.pump();
      await tester.tap(find.text('登录'));
      await tester.pump();
      final login = callsTo(fakes, #sessionLogin).single;
      expect(login[#osUsername], 'admin');
      expect(login[#osPassword], 'os-pw');
      expect(login[#password], '');
    });

    testWidgets(
      'without a saved password: the connection password first, both needed',
      (tester) async {
        final s = await panel(tester);
        await emit(
          tester,
          fakes,
          s,
          msgbox('terminal-admin-login-password', 'Terminal', ''),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('记住密码'), findsOneWidget);
        final fields = find.byType(EditableText);
        expect(fields, findsNWidgets(3));
        await tester.enterText(fields.at(1), 'admin');
        await tester.pump();
        await tester.tap(find.text('登录'));
        await tester.pump();
        expect(callsTo(fakes, #sessionLogin), isEmpty);
        await tester.enterText(fields.at(0), 'pw-1');
        await tester.pump();
        await tester.tap(find.text('登录'));
        await tester.pump();
        final login = callsTo(fakes, #sessionLogin).single;
        expect(login[#password], 'pw-1');
        expect(login[#osUsername], 'admin');
        expect(login[#osPassword], '');
      },
    );

    testWidgets(
      'a wrong connection password asks again with the account: the shell stays the '
      'administrator\'s',
      (tester) async {
        final s = await panel(tester);
        fakes.lg.reasons['Wrong Password'] = 'wrong_password';
        await emit(
          tester,
          fakes,
          s,
          msgbox('terminal-admin-login-password', 'Terminal', ''),
        );
        await tester.pump(const Duration(milliseconds: 200));
        final fields = find.byType(EditableText);
        await tester.enterText(fields.at(0), 'bad');
        await tester.enterText(fields.at(1), 'admin');
        await tester.pump();
        await tester.tap(find.text('登录'));
        await tester.pump();

        await emit(
          tester,
          fakes,
          s,
          msgbox('re-input-password', 'Login Error', 'Wrong Password'),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('远程设备上的管理员账户'), findsOneWidget);
        expect(find.text('密码错误'), findsOneWidget);
        expect(fields, findsNWidgets(3));
        // Without the username nothing goes.
        await tester.enterText(fields.at(1), '');
        await tester.enterText(fields.at(0), 'pw-2');
        await tester.pump();
        await tester.tap(find.text('登录'));
        await tester.pump();
        expect(callsTo(fakes, #sessionLogin), hasLength(1));
        await tester.enterText(fields.at(1), 'admin');
        await tester.pump();
        await tester.tap(find.text('登录'));
        await tester.pump();
        final login = callsTo(fakes, #sessionLogin).last;
        expect(login[#osUsername], 'admin');
        expect(login[#password], 'pw-2');
      },
    );

    testWidgets('a wrong account: the reason, "重试" and the close button', (
      tester,
    ) async {
      final s = await panel(tester);
      fakes.lg.reasons['Incorrect username or password.'] = 'os_login_failed';
      await emit(
        tester,
        fakes,
        s,
        msgbox('error', 'Connection Error', 'Incorrect username or password.'),
      );
      expect(find.text('用户名或密码错误，或该账户不是管理员。'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('关闭标签'), findsOneWidget);
    });
  });

  group('the device menu (13 §2.1.1, §3.1.1)', () {
    Future<FakeNavigation> menu(WidgetTester tester, String platform) async {
      final nav = FakeNavigation();
      mainNavigation = nav;
      final item = PeerItem(
        peer: Peer.fromJson({'id': _id, 'platform': platform}),
        category: PeerCategory.recent,
        status: LgDeviceStatus.online,
        statusLabel: '在线',
        favorite: false,
      );
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => SingleChildScrollView(
              child: LgMenuPanel(
                items: peerMenuItems(
                  AppLocalizations.of(context)!,
                  item,
                  overlays: TabOverlays(),
                  hasPassword: false,
                ),
              ),
            ),
          ),
        ),
      );
      return nav;
    }

    LgMenuItem row(WidgetTester tester, String label) =>
        tester.widget<LgMenuItem>(find.widgetWithText(LgMenuItem, label));

    testWidgets(
      'a Windows device: the terminals and the camera; the administrator\'s greyed '
      'while a terminal is open (R3-Q9)',
      (tester) async {
        var nav = await menu(tester, 'Windows');
        expect(find.text('终端'), findsOneWidget);
        expect(find.text('摄像头'), findsOneWidget);
        row(tester, '终端（管理员）').onPressed!();
        row(tester, '摄像头').onPressed!();
        expect(nav.views, [
          (id: _id, kind: ConnType.terminal, terminalAdmin: true),
          (id: _id, kind: ConnType.viewCamera, terminalAdmin: false),
        ]);

        appCore.sessions.open(_id, ConnType.terminal);
        nav = await menu(tester, 'Windows');
        final admin = row(tester, '终端（管理员）');
        expect(admin.onPressed, isNull);
        expect(admin.disabledNote, '已打开终端');
        await appCore.sessions.closeDevice(_id);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      },
    );

    testWidgets('a Mac: neither the camera nor the administrator terminal', (
      tester,
    ) async {
      await menu(tester, 'Mac OS');
      expect(find.text('终端'), findsOneWidget);
      expect(find.text('终端（管理员）'), findsNothing);
      expect(find.text('摄像头'), findsNothing);
    });
  });
}
