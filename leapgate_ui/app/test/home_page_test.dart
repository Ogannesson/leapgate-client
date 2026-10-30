import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/pages/home/home_page.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';

Future<LocalStatusModel> _pump(
  WidgetTester tester, {
  String id = '',
  ServiceStatus status = ServiceStatus.connecting,
  Size size = const Size(1280, 760),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final model = LocalStatusModel()
    ..id = id
    ..status = status;
  addTearDown(model.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
      home: Scaffold(body: HomePage(status: model)),
    ),
  );
  return model;
}

void main() {
  testWidgets(
    'shows "generating" until the ID arrives, then the ID in groups of three',
    (tester) async {
      final model = await _pump(tester);
      expect(find.text('正在生成…'), findsOneWidget);

      model
        ..id = '135792468'
        ..notifyListeners();
      await tester.pump();
      expect(find.text('正在生成…'), findsNothing);
      expect(find.text('135'), findsOneWidget);
      expect(find.text('792'), findsOneWidget);
      expect(find.text('468'), findsOneWidget);
      // Read out in the same groups.
      expect(find.bySemanticsLabel('135 792 468'), findsOneWidget);
    },
  );

  testWidgets('service status line follows the status', (tester) async {
    final model = await _pump(
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
  });

  testWidgets('navigation switches the page title', (tester) async {
    await _pump(tester, id: '135792468');
    // "设备" is both the selected nav item and the page title.
    expect(find.text('设备'), findsNWidgets(2));
    await tester.tap(find.text('出口'));
    await tester.pump();
    expect(find.text('出口'), findsNWidgets(2));
    expect(find.text('设备'), findsOneWidget);
  });

  testWidgets(
    'a window shorter than the column scrolls instead of overflowing',
    (tester) async {
      await _pump(
        tester,
        id: '135792468',
        status: ServiceStatus.notReady,
        size: const Size(960, 260),
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.text('ID'), const Offset(0, -200));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
