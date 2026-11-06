import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Scrollable;
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/pages/home/password_row.dart';

import 'home_fakes.dart';

/// The password row's "Copy"; the ID has one of its own.
final _passwordCopy = find.descendant(
  of: find.byType(PasswordRowView),
  matching: find.text('复制'),
);

/// Keeps what the page puts on the clipboard.
class _Clipboard {
  String? text;
}

_Clipboard _mockClipboard(WidgetTester tester) {
  final clipboard = _Clipboard();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.text = (call.arguments as Map)['text'] as String;
      }
      return null;
    },
  );
  return clipboard;
}

void main() {
  setUp(installHomeFakes);

  testWidgets(
    'shows "generating" until the ID arrives, then the ID in groups of three',
    (tester) async {
      final model = await pumpHome(tester);
      // The ID and the one-time password both wait for Rust.
      expect(find.text('正在生成…'), findsNWidgets(2));

      model
        ..id = '135792468'
        ..oneTimePassword = 'a1b2c3'
        ..notifyListeners();
      await tester.pump();
      expect(find.text('正在生成…'), findsNothing);
      expect(find.text('135'), findsOneWidget);
      expect(find.text('792'), findsOneWidget);
      expect(find.text('468'), findsOneWidget);
      // Read out in the same groups.
      expect(find.bySemanticsLabel('135 792 468'), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets('a 10-digit ID stays on one line, grouped from the right', (
    tester,
  ) async {
    await pumpHome(tester, id: '1078877965');
    await tester.pump();
    expect(find.bySemanticsLabel('1 078 877 965'), findsOneWidget);
    final first = tester.getTopLeft(find.text('1')).dy;
    expect(tester.getTopLeft(find.text('965')).dy, first);
    await unmount(tester);
  });

  testWidgets('service status line follows the status', (tester) async {
    final model = await pumpHome(
      tester,
      id: '135792468',
      status: ServiceStatus.ready,
    );
    expect(find.textContaining('已就绪', findRichText: true), findsOneWidget);
    model
      ..status = ServiceStatus.stopped
      ..notifyListeners();
    await tester.pump();
    expect(
      find.textContaining('服务已停止，本机无法接受远程连接', findRichText: true),
      findsOneWidget,
    );
    await unmount(tester);
  });

  group('password row (01 P1 block A)', () {
    Future<LocalStatusModel> pumpRow(
      WidgetTester tester, {
      ServiceStatus status = ServiceStatus.ready,
      String approve = '',
      String method = '',
    }) => pumpHome(tester, id: '135792468', status: status).then(
      (m) => m
        ..oneTimePassword = 'a1b2c3'
        ..approveMode = approve
        ..verificationMethod = method
        ..notifyListeners(),
    );

    testWidgets('one-time password: its text and "Copy"', (tester) async {
      await pumpRow(tester, method: kUseTemporaryPassword);
      await tester.pump();
      expect(find.text('一次性密码'), findsOneWidget);
      expect(find.text('a1b2c3'), findsOneWidget);
      expect(_passwordCopy, findsOneWidget);
      expect(find.bySemanticsLabel('复制密码'), findsOneWidget);
      expect(find.text('也可使用固定密码'), findsNothing);
      await unmount(tester);
    });

    testWidgets('both passwords: the note under it', (tester) async {
      await pumpRow(tester, approve: 'password', method: kUseBothPasswords);
      await tester.pump();
      expect(find.text('一次性密码'), findsOneWidget);
      expect(find.text('a1b2c3'), findsOneWidget);
      expect(find.text('也可使用固定密码'), findsOneWidget);
      expect(_passwordCopy, findsOneWidget);
      await unmount(tester);
    });

    testWidgets('permanent password only: "set", nothing to copy', (
      tester,
    ) async {
      await pumpRow(tester, method: kUsePermanentPassword);
      await tester.pump();
      expect(find.text('固定密码'), findsOneWidget);
      expect(find.text('已设置'), findsOneWidget);
      expect(find.text('a1b2c3'), findsNothing);
      expect(_passwordCopy, findsNothing);
      await unmount(tester);
    });

    testWidgets('accept on this device: the approval mode', (tester) async {
      await pumpRow(tester, approve: 'click', method: kUseTemporaryPassword);
      await tester.pump();
      expect(find.text('审批方式'), findsOneWidget);
      expect(find.text('需在本机接受连接请求'), findsOneWidget);
      expect(_passwordCopy, findsNothing);
      await unmount(tester);
    });

    testWidgets('service stopped: unavailable', (tester) async {
      await pumpRow(tester, status: ServiceStatus.stopped);
      await tester.pump();
      expect(find.text('一次性密码'), findsOneWidget);
      expect(find.text('不可用'), findsOneWidget);
      expect(find.text('a1b2c3'), findsNothing);
      expect(_passwordCopy, findsNothing);
      await unmount(tester);
    });

    testWidgets('"Copy" puts the password on the clipboard and says so', (
      tester,
    ) async {
      final clipboard = _mockClipboard(tester);
      await pumpRow(tester, method: kUseTemporaryPassword);
      await tester.pump();
      await tester.tap(_passwordCopy);
      await tester.pump();
      expect(clipboard.text, 'a1b2c3');
      expect(appCore.toasts.current?.key, 'Copied');
      await unmount(tester);
      // The toast's own timer.
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('copying the ID (01 P1 block A)', () {
    testWidgets('"Copy" beside it', (tester) async {
      final clipboard = _mockClipboard(tester);
      await pumpHome(tester, id: '135792468');
      final idCopy = find.text('复制').first;
      expect(
        find.descendant(of: find.byType(PasswordRowView), matching: idCopy),
        findsNothing,
      );
      // Shown as "复制" twice; read out as what each copies.
      expect(find.bySemanticsLabel('复制 ID'), findsOneWidget);
      expect(find.bySemanticsLabel('复制'), findsNothing);
      await tester.tap(idCopy);
      await tester.pump();
      expect(clipboard.text, '135792468');
      expect(appCore.toasts.current?.key, 'Copied');
      await unmount(tester);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a double click on it', (tester) async {
      final clipboard = _mockClipboard(tester);
      await pumpHome(tester, id: '135792468');
      await tester.tap(find.text('792'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('792'));
      await tester.pump();
      expect(clipboard.text, '135792468');
      expect(appCore.toasts.current?.key, 'Copied');
      await unmount(tester);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('nothing to copy while it is generated', (tester) async {
      await pumpHome(tester);
      expect(find.text('复制'), findsNothing);
      await unmount(tester);
    });
  });

  testWidgets('navigation switches the page title', (tester) async {
    await pumpHome(tester, id: '135792468');
    // "设备" is both the selected nav item and the page title.
    expect(find.text('设备'), findsNWidgets(2));
    await tester.tap(find.text('出口'));
    await tester.pump();
    expect(find.text('出口'), findsNWidgets(2));
    expect(find.text('设备'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
    'a window shorter than the column scrolls instead of overflowing',
    (tester) async {
      await pumpHome(
        tester,
        id: '135792468',
        status: ServiceStatus.notReady,
        size: const Size(960, 260),
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.text('ID'), const Offset(0, -200));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  group('install card (01 P1 block B, M8)', () {
    testWidgets('portable: "安装" is busy while it runs, then says why it failed', (
      tester,
    ) async {
      // Made in the test's zone, so its answer arrives on the next pump.
      final lg = lgBind as FakeLeapgate..installAnswer = Completer();
      await pumpHome(tester, id: '135792468', setUp: (m) => m.installed = false);
      expect(find.textContaining('建议安装 Leapgate'), findsOneWidget);
      await tester.tap(find.text('安装'));
      await tester.pump();
      expect(lg.installs, ['install']);
      expect(find.text('正在安装…'), findsOneWidget);

      lg.installAnswer.complete(
        '{"result":"uac_denied","text":"The operation was canceled by the user. (0x800704C7)"}',
      );
      await tester.pump();
      expect(find.text('未获得管理员权限，未安装。'), findsOneWidget);
      expect(find.text('安装'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('an older installed version: "升级", a failure with its text', (
      tester,
    ) async {
      // Made in the test's zone, so its answer arrives on the next pump.
      final lg = lgBind as FakeLeapgate..installAnswer = Completer();
      await pumpHome(
        tester,
        id: '135792468',
        setUp: (m) => m.installedLowerVersion = true,
      );
      expect(find.text('已安装的 Leapgate 版本低于当前版本。'), findsOneWidget);
      await tester.tap(find.text('升级'));
      await tester.pump();
      expect(lg.installs, ['upgrade']);
      lg.installAnswer.complete(
        '{"result":"failed","text":"Cannot install the EXE package over an existing MSI installation"}',
      );
      await tester.pump();
      expect(
        find.text(
          '升级失败：Cannot install the EXE package over an existing MSI installation',
        ),
        findsOneWidget,
      );
      await unmount(tester);
    });

    // 01 §2.1: with a card the column scrolls, the account area stays at the bottom.
    for (final size in const [Size(1280, 760), Size(960, 560)]) {
      testWidgets('the mouse wheel brings the navigation into view at $size', (
        tester,
      ) async {
        await pumpHome(
          tester,
          id: '135792468',
          size: size,
          setUp: (m) => m.installed = false,
        );
        final column = find
            .ancestor(
              of: find.textContaining('建议安装 Leapgate'),
              matching: find.byType(Scrollable),
            )
            .first;
        final mouse = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(
          mouse.hover(tester.getCenter(find.textContaining('建议安装 Leapgate'))),
        );
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, 1000)));
        await tester.pump();
        final viewport = tester.getRect(column);
        final login = tester.getRect(find.text('登录'));
        for (final label in ['设备', '出口', '设置']) {
          final item = tester.getRect(
            find.descendant(of: column, matching: find.text(label)),
          );
          expect(viewport.contains(item.topLeft), isTrue, reason: label);
          expect(viewport.contains(item.bottomRight), isTrue, reason: label);
          expect(item.bottom, lessThanOrEqualTo(login.top), reason: label);
        }
        await tester.tap(find.text('出口'));
        await tester.pump();
        expect(find.text('出口'), findsNWidgets(2));
        await unmount(tester);
      });
    }
  });
}
