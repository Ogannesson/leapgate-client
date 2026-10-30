import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_fakes.dart';

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
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('也可使用固定密码'), findsNothing);
      await unmount(tester);
    });

    testWidgets('both passwords: the note under it', (tester) async {
      await pumpRow(tester, approve: 'password', method: kUseBothPasswords);
      await tester.pump();
      expect(find.text('一次性密码'), findsOneWidget);
      expect(find.text('a1b2c3'), findsOneWidget);
      expect(find.text('也可使用固定密码'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
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
      expect(find.text('复制'), findsNothing);
      await unmount(tester);
    });

    testWidgets('accept on this device: the approval mode', (tester) async {
      await pumpRow(tester, approve: 'click', method: kUseTemporaryPassword);
      await tester.pump();
      expect(find.text('审批方式'), findsOneWidget);
      expect(find.text('需在本机接受连接请求'), findsOneWidget);
      expect(find.text('复制'), findsNothing);
      await unmount(tester);
    });

    testWidgets('service stopped: unavailable', (tester) async {
      await pumpRow(tester, status: ServiceStatus.stopped);
      await tester.pump();
      expect(find.text('一次性密码'), findsOneWidget);
      expect(find.text('不可用'), findsOneWidget);
      expect(find.text('a1b2c3'), findsNothing);
      expect(find.text('复制'), findsNothing);
      await unmount(tester);
    });

    testWidgets('"Copy" puts the password on the clipboard and says so', (
      tester,
    ) async {
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
      await pumpRow(tester, method: kUseTemporaryPassword);
      await tester.pump();
      await tester.tap(find.text('复制'));
      await tester.pump();
      expect(copied, 'a1b2c3');
      expect(appCore.toasts.current?.key, 'Copied');
      await unmount(tester);
      // The toast's own timer.
      await tester.pump(const Duration(seconds: 3));
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
}
