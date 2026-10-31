import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/ui_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/main.dart' show LeapgateApp;
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';

import 'home_fakes.dart';

// This device's block in M2b (01 P1 blocks A, B, J, K) and the interface mode (01 §2.3).

late FakeBind bind;

Future<LocalStatusModel> pumpWith(
  WidgetTester tester, {
  String method = kUseTemporaryPassword,
  ServiceStatus status = ServiceStatus.ready,
  int remoteSessions = 0,
  String systemError = '',
}) => pumpHome(
  tester,
  id: '135792468',
  status: status,
  setUp: (m) => m
    ..oneTimePassword = 'a1b2c3'
    ..verificationMethod = method
    ..remoteSessions = remoteSessions
    ..systemError = systemError,
);

/// After a click: dialogs fade in, and they read Rust before they open.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Builds first, so a button enabled by the text just entered takes the click.
Future<void> tapText(WidgetTester tester, String text) async {
  await tester.pump();
  await tester.tap(find.text(text).last);
  await settle(tester);
}

void main() {
  setUp(() => bind = installHomeFakes().bind);

  testWidgets('"Refresh" asks Rust for a new one-time password', (
    tester,
  ) async {
    await pumpWith(tester);
    await tapText(tester, '刷新');
    expect(bind.callsTo(#mainUpdateTemporaryPassword), hasLength(1));
    await unmount(tester);
  });

  testWidgets('"Change" only on the portable version', (tester) async {
    bind.installed = true;
    await pumpWith(tester, method: kUsePermanentPassword);
    expect(find.text('修改'), findsNothing);
    await unmount(tester);

    bind.installed = false;
    await pumpWith(tester, method: kUsePermanentPassword);
    expect(find.bySemanticsLabel('修改固定密码'), findsOneWidget);
    await unmount(tester);
  });

  group('set permanent password (01 P1 block K)', () {
    Future<void> open(WidgetTester tester) async {
      await pumpWith(tester, method: kUsePermanentPassword);
      await tapText(tester, '修改');
      expect(find.text('设置固定密码'), findsOneWidget);
    }

    Finder field(int i) => find.byType(EditableText).at(1 + i);

    bool okEnabled(WidgetTester tester) =>
        tester
            .widget<LgButton>(find.widgetWithText(LgButton, '确定'))
            .onPressed !=
        null;

    testWidgets('"OK" waits for input; the rules pass as they are met', (
      tester,
    ) async {
      await open(tester);
      expect(okEnabled(tester), isFalse);
      expect(find.text('移除'), findsNothing);

      await tester.enterText(field(0), 'abc12');
      await tester.pump();
      expect(okEnabled(tester), isTrue);
      expect(
        tester.getSemantics(find.bySemanticsLabel('包含数字')),
        isSemantics(isChecked: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('包含大写字母')),
        isSemantics(isChecked: false),
      );
      await unmount(tester);
    });

    testWidgets('the rules, then the confirmation, then saving', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(field(0), 'abc12');
      await tapText(tester, '确定');
      expect(find.text('密码不符合要求'), findsOneWidget);

      await tester.enterText(field(0), 'Abcdefg1');
      await tester.enterText(field(1), 'Abcdefg2');
      await tapText(tester, '确定');
      expect(find.text('两次输入的密码不一致'), findsOneWidget);
      expect(bind.callsTo(#mainSetPermanentPasswordWithResult), isEmpty);

      bind.passwordSaves = false;
      await tester.enterText(field(1), 'Abcdefg1');
      await tapText(tester, '确定');
      expect(find.text('无法保存密码'), findsOneWidget);

      bind.passwordSaves = true;
      await tapText(tester, '确定');
      expect(find.text('设置固定密码'), findsNothing);
      expect(
        bind
            .callsTo(#mainSetPermanentPasswordWithResult)
            .last
            .namedArguments[#password],
        'Abcdefg1',
      );
      await unmount(tester);
    });

    testWidgets('one already set: not shown, and "Remove"', (tester) async {
      bind.passwordSet = true;
      await open(tester);
      expect(find.text('已设置的密码不会显示'), findsOneWidget);
      await tapText(tester, '移除');
      expect(
        bind
            .callsTo(#mainSetPermanentPasswordWithResult)
            .single
            .namedArguments[#password],
        '',
      );
      expect(find.text('设置固定密码'), findsNothing);
      await unmount(tester);
    });
  });

  testWidgets('a stopped service: "Start service"', (tester) async {
    await pumpWith(tester, status: ServiceStatus.stopped);
    await tapText(tester, '启动服务');
    final set = bind.callsTo(#mainSetOption).single.namedArguments;
    expect((set[#key], set[#value]), ('stop-service', 'N'));
    await unmount(tester);
  });

  testWidgets('remote sessions into this device and the system error', (
    tester,
  ) async {
    await pumpWith(tester);
    expect(find.textContaining('正在被远程控制'), findsNothing);
    await unmount(tester);

    await pumpWith(tester, remoteSessions: 2, systemError: '无法写入配置文件');
    expect(find.text('正在被远程控制（2 个会话）'), findsOneWidget);
    expect(find.text('无法写入配置文件'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
    'the remote user moving in: the cover, unless allowed (01 P1 block J)',
    (tester) async {
      bind.accessMode = 'view';
      await pumpWith(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);

      // Remote input "now or later" as the page sees it (its clock may be a test clock).
      bind.lastRemoteInput = DateTime(2100);
      await mouse.moveTo(const Offset(640, 400));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('远程控制期间无法修改设置'), findsOneWidget);

      await mouse.moveTo(const Offset(-10, -10));
      await tester.pump();
      expect(find.text('远程控制期间无法修改设置'), findsNothing);

      // Local input: no cover.
      bind.lastRemoteInput = DateTime(2000);
      await mouse.moveTo(const Offset(640, 400));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('远程控制期间无法修改设置'), findsNothing);
      await unmount(tester);
    },
  );

  testWidgets('the interface mode switches the theme at once (01 §2.3)', (
    tester,
  ) async {
    await tester.pumpWidget(
      LeapgateApp(
        local: appCore.options.local,
        home: Builder(
          builder: (context) => Text(LgTokens.of(context).mode.name),
        ),
      ),
    );
    expect(find.text('compact'), findsOneWidget);
    await setDetailMode(appCore.options.local, true);
    await tester.pump();
    expect(find.text('detail'), findsOneWidget);
    expect(bind.local[kOptionLeapgateUiMode], 'detail');
  });
}
