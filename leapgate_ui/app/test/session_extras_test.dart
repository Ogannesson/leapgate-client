import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/notices.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/leapgate/session_route.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/pages/session/session_notices.dart';
import 'package:leapgate_ui/shell/navigation.dart';
import 'package:leapgate_ui/shell/tab_menu.dart';
import 'package:leapgate_ui/shell/toast_view.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';
import 'package:leapgate_ui/widgets/lg_session_toolbar.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';

import 'session_fakes.dart';

// The rest of the session tab (LEAPGATE.md §10.9, coder B): connection details, the server's
// refusal, notices with buttons, chat, recording, the tab menu and the connection panel's
// additions. Device IDs and server names here are made up.

const _id = '100200300';

/// [AppFakeBind] with session toggles and peer options kept, and what chat, recording and
/// screenshots call.
class _Bind extends AppFakeBind {
  final toggles = <String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      case #sessionToggleOption:
        calls.add(invocation);
        final v = args[#value] as String;
        if (!toggles.remove(v)) toggles.add(v);
        return Future<void>.value();
      case #sessionGetToggleOptionSync:
        return toggles.contains(args[#arg]);
      case #sessionGetToggleOption:
        return Future<bool?>.value(toggles.contains(args[#arg]));
      case #sessionPeerOption:
        calls.add(invocation);
        if (args[#value] == 'Y') {
          toggles.add(args[#name]);
        } else {
          toggles.remove(args[#name]);
        }
        return Future<void>.value();
      case #sessionSendChat:
      case #sessionRecordScreen:
      case #sessionTakeScreenshot:
      case #sessionRequestVoiceCall:
        calls.add(invocation);
        return Future<void>.value();
      case #sessionHandleScreenshot:
        calls.add(invocation);
        return Future.value('');
      case #mainGetSoundInputs:
        return Future.value(['Headset microphone']);
      case #getVoiceCallInputDevice:
        return Future.value('');
      case #mainAudioSupportLoopback:
        return true;
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  late AppFakes fakes;
  late _Bind bind;

  setUp(() {
    fakes = installAppFakes();
    bind = _Bind();
    platformFFI.setBindingForTesting(bind);
    fakes = (bind: bind, lg: fakes.lg, window: fakes.window);
  });
  tearDown(() {
    readSessionConnection = (_) => '{}';
    readLocalDisplayName = () => '';
  });

  Future<FFI> open(WidgetTester tester, {String id = _id}) async {
    mainNavigation.connect(id);
    await tester.pump();
    await tester.pump();
    return appCore.sessions.sessionsOf(id).single;
  }

  Future<FFI> connected(WidgetTester tester, {String id = _id}) async {
    final s = await open(tester, id: id);
    await emit(tester, fakes, s, connectionReady());
    await emit(tester, fakes, s, peerInfo());
    return s;
  }

  group('connection details', () {
    Future<void> openDetails(WidgetTester tester) async {
      // The toolbar's mark ("经中继") opens them.
      await tester.tap(find.byType(LgToolbarRouteButton));
      await tester.pumpAndSettle();
    }

    testMainWindow(
      'without an answer from Q3: no path and no relay server rows',
      (tester) async {
        await pumpMainWindow(tester);
        final s = await connected(tester);
        await emit(tester, fakes, s, {
          'name': 'fingerprint',
          'fingerprint': '3F2A9C417B0ED5A86C1E04D7B93AF582',
        });
        // The remote side's first delay of a connection is its initial 0, not counted.
        await emit(tester, fakes, s, {
          'name': 'update_quality_status',
          'delay': '0',
        });
        await emit(tester, fakes, s, {
          'name': 'update_quality_status',
          'delay': '45',
          'codec_format': 'H264',
        });
        await openDetails(tester);

        expect(find.text('路径'), findsNothing);
        expect(find.text('中继服务器'), findsNothing);
        expect(find.text('TCP'), findsOneWidget);
        expect(find.text('已加密'), findsOneWidget);
        expect(
          find.text('3F2A 9C41 7B0E D5A8\n6C1E 04D7 B93A F582'),
          findsOneWidget,
        );
        expect(find.text('H264'), findsOneWidget);
        expect(find.text('端到端'), findsOneWidget);
        expect(find.text('45 ms'), findsOneWidget);
      },
    );

    testMainWindow('with Q3: the path and the relay server', (tester) async {
      readSessionConnection = (_) =>
          '{"path":"relay","transport":"tcp","relay":"relay-1.example.com"}';
      await pumpMainWindow(tester);
      await connected(tester);
      await openDetails(tester);

      expect(find.text('路径'), findsOneWidget);
      expect(find.text('经中继'), findsWidgets);
      expect(find.text('relay-1.example.com'), findsOneWidget);
    });

    testMainWindow(
      'the switch shows the quality data and is kept for the device',
      (tester) async {
        await pumpMainWindow(tester);
        final s = await connected(tester);
        await emit(tester, fakes, s, {
          'name': 'update_quality_status',
          'speed': '1.20kB/s',
          'fps': '{"0":30}',
        });
        expect(find.text('1.20kB/s'), findsNothing);

        await openDetails(tester);
        await tester.tap(find.byType(LgSwitch));
        await tester.pumpAndSettle();

        expect(
          bind.toggles,
          containsAll(['show-quality-monitor', kOptionQualityMonitorChosen]),
        );
        expect(find.text('1.20kB/s'), findsWidgets);
      },
    );
  });

  group('connection panel', () {
    testMainWindow('a refusal of the server is said to be the server\'s', (
      tester,
    ) async {
      readSessionConnection = (_) => '{"refused":"Banned by policy"}';
      await pumpMainWindow(tester);
      final s = await open(tester);
      await emit(
        tester,
        fakes,
        s,
        msgbox('error', 'Connection Error', 'Banned by policy'),
      );

      expect(find.text('服务器拒绝了此连接：Banned by policy'), findsOneWidget);
    });

    testMainWindow('waiting for the remote user shows the name it sees', (
      tester,
    ) async {
      readLocalDisplayName = () => '张三';
      await pumpMainWindow(tester);
      final s = await open(tester);
      await emit(tester, fakes, s, connectionReady());
      await emit(
        tester,
        fakes,
        s,
        msgbox('wait-remote-accept-nook', 'Prompt', ''),
      );

      expect(find.textContaining('显示给对方的名称：张三'), findsOneWidget);
    });

    testMainWindow('a wrong password keeps what was typed (待调 30)', (
      tester,
    ) async {
      fakes.lg.reasons['Wrong Password'] = 'wrong_password';
      await pumpMainWindow(tester);
      final s = await open(tester);
      await emit(tester, fakes, s, connectionReady());
      await emit(
        tester,
        fakes,
        s,
        msgbox('input-password', 'Password Required', ''),
      );
      expect(find.text('输入密码'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'pw-1');
      await tester.tap(find.text('连接'));
      await tester.pump();
      await emit(
        tester,
        fakes,
        s,
        msgbox('re-input-password', 'Login Error', 'Wrong Password'),
      );

      expect(find.text('密码错误'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'pw-1',
      );
    });
  });

  group('notices', () {
    testMainWindow('a screenshot stays until answered; copying answers it', (
      tester,
    ) async {
      await pumpMainWindow(tester);
      final s = await connected(tester);
      await emit(tester, fakes, s, {'name': 'screenshot', 'msg': ''});
      await tester.pump(const Duration(seconds: 6));

      expect(find.text('截图已完成'), findsOneWidget);
      await tester.tap(find.text('复制到剪贴板'));
      await tester.pumpAndSettle();

      expect(callsTo(fakes, #sessionHandleScreenshot).single[#action], '1');
      expect(find.text('截图已完成'), findsNothing);
    });

    testMainWindow('a notice that only informs goes by itself', (tester) async {
      await pumpMainWindow(tester);
      final s = await connected(tester);
      s.notices.add(SessionNotice('display_is_plugged_out_msg'));
      await tester.pump();
      expect(find.text('远程设备的一台显示器已断开，已切换到主显示器'), findsOneWidget);

      await tester.pump(kNoticeDuration);
      await tester.pump();
      expect(find.text('远程设备的一台显示器已断开，已切换到主显示器'), findsNothing);
    });

    testMainWindow('a print job offers the three answers and remembering', (
      tester,
    ) async {
      await pumpMainWindow(tester);
      final s = await connected(tester);
      await emit(tester, fakes, s, {
        'name': 'printer_request',
        'id': 3,
        'path': 'job',
      });

      expect(find.text('收到来自远程设备的打印任务'), findsOneWidget);
      for (final label in ['使用默认打印机', '选择打印机', '不打印']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.bySemanticsLabel('记住此选择'), findsOneWidget);
    });

    testMainWindow('UAC on the remote device: wait or request elevation', (
      tester,
    ) async {
      await pumpMainWindow(tester);
      final s = await connected(tester);
      await emit(
        tester,
        fakes,
        s,
        msgbox('on-uac', 'Prompt', 'Please wait for confirmation of UAC...'),
      );

      expect(find.text('远程设备上正在显示用户账户控制（UAC）窗口'), findsOneWidget);
      expect(find.text('请求提升权限'), findsOneWidget);
      await tester.tap(find.text('等待'));
      await tester.pump();
      expect(find.text('远程设备上正在显示用户账户控制（UAC）窗口'), findsNothing);
    });

    testMainWindow('"请求提升权限" on the UAC notice opens the elevation dialog', (
      tester,
    ) async {
      await pumpMainWindow(tester);
      final s = await connected(tester);
      await emit(
        tester,
        fakes,
        s,
        msgbox('on-uac', 'Prompt', 'Please wait for confirmation of UAC...'),
      );
      await tester.tap(find.text('请求提升权限'));
      await tester.pumpAndSettle();

      expect(find.text('请对方确认'), findsOneWidget);
      expect(find.text('输入管理员账户和密码'), findsOneWidget);
    });

    testMainWindow('blocking user input that failed says which and why', (
      tester,
    ) async {
      await pumpMainWindow(tester);
      final s = await connected(tester);
      await emit(
        tester,
        fakes,
        s,
        msgbox('custom-error', 'Block user input', 'Failed'),
      );
      await emit(
        tester,
        fakes,
        s,
        msgbox('custom-error', 'Unblock user input', 'Driver missing'),
      );

      expect(find.text('无法阻止远程设备的本地输入'), findsOneWidget);
      expect(find.text('无法取消阻止远程设备的本地输入（Driver missing）'), findsOneWidget);
    });

    testMainWindow('privacy mode that failed says so, with the reason when given', (
      tester,
    ) async {
      await pumpMainWindow(tester);
      final s = await connected(tester);
      await emit(
        tester,
        fakes,
        s,
        msgbox('custom-error', 'Privacy mode', 'Failed'),
      );
      await emit(
        tester,
        fakes,
        s,
        msgbox('custom-error', 'Privacy mode', 'Not supported'),
      );

      expect(find.text('无法开启隐私模式'), findsOneWidget);
      expect(find.text('无法切换隐私模式（Not supported）'), findsOneWidget);
      expect(find.text('失败'), findsNothing);
    });

    testMainWindow('a permission taken away is told', (tester) async {
      await pumpMainWindow(tester);
      // Given permissions are never sent; the remote user turns one off after the login.
      final s = await connected(tester);
      await emit(tester, fakes, s, {
        'name': 'permission',
        'clipboard': 'false',
      });

      expect(find.text('对方已关闭剪贴板同步'), findsOneWidget);
    });
  });

  group('chat', () {
    testMainWindow(
      'the pointer back on the image leaves the keyboard to the chat input; a click takes it',
      (tester) async {
        await pumpMainWindow(tester);
        final s = await connected(tester);
        await emit(tester, fakes, s, {
          'name': 'chat_client_mode',
          'text': '你好',
        });
        await tester.tap(find.byType(EditableText));
        await tester.pump();
        final input = tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode;
        expect(input.hasFocus, true);

        // A frame, so the image takes the pointer.
        await tester.runAsync(() async {
          s.canvasModel.updateSize();
          await s.imageModel.update(
            await createTestImage(width: 1920, height: 1080),
          );
        });
        await tester.pump();

        // A spot of the image, away from the toolbar and the panel.
        const spot = Offset(80, 500);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(1270, 790));
        await mouse.moveTo(spot);
        await tester.pump();
        expect(input.hasFocus, true);

        await tester.tapAt(spot);
        await tester.pump();
        expect(input.hasFocus, false);
        expect(callsTo(fakes, #sessionEnterOrLeave).last[#enter], true);
        await mouse.removePointer();
      },
    );

    testMainWindow(
      'a message opens the panel; sending shows it on the right side',
      (tester) async {
        await pumpMainWindow(tester);
        final s = await connected(tester);
        await emit(tester, fakes, s, {
          'name': 'chat_client_mode',
          'text': '你好',
        });

        expect(find.text('你好'), findsOneWidget);
        await tester.enterText(find.byType(EditableText), ' 好的 ');
        // "发送" turns on with the text.
        await tester.pump();
        await tester.tap(find.text('发送'));
        await tester.pump();

        expect(callsTo(fakes, #sessionSendChat).single[#text], '好的');
        expect(find.text('好的'), findsOneWidget);
      },
    );

    testMainWindow('messages to a tab out of sight are unread until it shows', (
      tester,
    ) async {
      await pumpMainWindow(tester);
      final s = await connected(tester);
      mainNavigation.showHome();
      await tester.pump();
      await emit(tester, fakes, s, {'name': 'chat_client_mode', 'text': 'a'});
      await emit(tester, fakes, s, {'name': 'chat_client_mode', 'text': 'b'});
      Finder badge(String n) =>
          find.descendant(of: find.byType(LgBadge), matching: find.text(n));
      expect(badge('2'), findsOneWidget);

      await tester.tap(find.text('host')); // its tab, named after the peer info
      await tester.pump();
      await tester.pump();
      expect(badge('2'), findsNothing);
      expect(tabUnread(s), 0);
    });

    testMainWindow('the chat stays at hand during a call', (tester) async {
      await pumpMainWindow(tester);
      final s = await connected(tester);
      await emit(tester, fakes, s, {'name': 'on_voice_call_started'});
      await tester.tap(find.text('通话中'));
      await tester.pumpAndSettle();

      expect(find.text('文字聊天'), findsOneWidget);
      expect(find.text('挂断'), findsOneWidget);
    });

    testMainWindow('waiting for the answer: "正在等待接听…" with "取消"', (tester) async {
      await pumpMainWindow(tester);
      final s = await connected(tester);
      await tester.tap(find.text('聊天'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('语音通话'));
      await tester.pumpAndSettle();
      expect(callsTo(fakes, #sessionRequestVoiceCall), hasLength(1));

      await emit(tester, fakes, s, {'name': 'on_voice_call_waiting'});
      expect(find.text('正在等待接听…'), findsOneWidget);
    });
  });

  testMainWindow('recording: the button starts it', (tester) async {
    await pumpMainWindow(tester);
    await connected(tester);
    await tester.tap(find.bySemanticsLabel('录制'));
    await tester.pump();

    expect(callsTo(fakes, #sessionRecordScreen).single[#start], true);
  });

  group('tab menu', () {
    Future<void> rightClickTab(WidgetTester tester, String label) async {
      await tester.tap(find.text(label).first, buttons: kSecondaryButton);
      await tester.pump();
    }

    testMainWindow('"关闭其他标签" leaves this one', (tester) async {
      await pumpMainWindow(tester);
      await open(tester);
      await open(tester, id: '400500600');
      await rightClickTab(tester, '400 500 600');

      await tester.tap(find.text('关闭其他标签'));
      await tester.pump();
      expect(appCore.sessions.devices, ['400500600']);
    });

    testMainWindow('"复制设备 ID" copies the ID', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await pumpMainWindow(tester);
      await open(tester);
      await rightClickTab(tester, '100 200 300');

      await tester.tap(find.text('复制设备 ID'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(copied, _id);
      expect(find.text('已复制'), findsOneWidget);
    });
  });

  test('the relative mouse mode toasts have their own copy', () {
    final l10n = lookupAppLocalizations(const Locale('zh'));
    expect(toastText(l10n, 'rel-mouse-not-supported-peer-tip'), '远程设备不支持相对鼠标模式');
    expect(toastText(l10n, 'rel-mouse-exit-{Ctrl+Alt}-tip'), '按 Ctrl+Alt 退出鼠标锁定');
  });
}
