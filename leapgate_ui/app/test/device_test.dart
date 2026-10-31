import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/identity_color.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_device.dart';

import 'helpers.dart';

Widget _row({
  VoidCallback? onTap,
  VoidCallback? onDoubleTap,
  VoidCallback? onConnect,
  bool selected = false,
  bool highlighted = false,
  FocusNode? focusNode,
  String? source,
  LgDeviceStatus status = LgDeviceStatus.online,
}) => SizedBox(
  width: 800,
  child: LgDeviceRow(
    name: '书房台式机',
    id: '123 456 789',
    platform: LgPlatform.windows,
    status: status,
    statusLabel: '在线',
    userHost: 'zhangsan@DESKTOP-SHUFANG',
    source: source,
    selected: selected,
    highlighted: highlighted,
    onTap: onTap,
    onDoubleTap: onDoubleTap,
    onConnect: onConnect,
    connectLabel: onConnect == null ? null : '连接',
    focusNode: focusNode,
  ),
);

void main() {
  group('LgDeviceRow', () {
    testWidgets('a click selects, a second click soon after connects', (
      tester,
    ) async {
      var taps = 0, doubles = 0;
      await pumpLg(
        tester,
        _row(onTap: () => taps++, onDoubleTap: () => doubles++),
      );
      await tester.tap(find.text('书房台式机'));
      // The selection is not held back to wait for a double click.
      expect((taps, doubles), (1, 0));
      await tester.tap(find.text('书房台式机'));
      expect((taps, doubles), (2, 1));
    });

    testWidgets('a click on a row with a connect callback only selects', (
      tester,
    ) async {
      var taps = 0, connects = 0;
      await pumpLg(
        tester,
        _row(onTap: () => taps++, onConnect: () => connects++),
      );
      await tester.tap(find.text('书房台式机'));
      expect((taps, connects), (1, 0));
    });

    testWidgets('the row of the arrow keys is read as selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      bool selected() =>
          tester
              .getSemantics(find.bySemanticsLabel(RegExp('书房台式机')))
              .getSemanticsData()
              .flagsCollection
              .isSelected ==
          Tristate.isTrue;
      await pumpLg(tester, _row(onTap: () {}));
      expect(selected(), isFalse);
      await pumpLg(tester, _row(onTap: () {}, highlighted: true));
      expect(selected(), isTrue);
      await pumpLg(tester, _row(onTap: () {}, selected: true));
      expect(selected(), isTrue);
      handle.dispose();
    });

    testWidgets('two clicks far apart are not a double click', (tester) async {
      var doubles = 0;
      await pumpLg(tester, _row(onTap: () {}, onDoubleTap: () => doubles++));
      final at = tester.getCenter(find.text('书房台式机'));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      Future<void> click(int milliseconds) async {
        final time = Duration(milliseconds: milliseconds);
        await gesture.down(at, timeStamp: time);
        await gesture.up(timeStamp: time);
      }

      await click(1000);
      await click(3000);
      expect(doubles, 0);
      await click(3200);
      expect(doubles, 1);
    });

    testWidgets('the connect button shows under the pointer and connects', (
      tester,
    ) async {
      // A desktop platform: only there the pointer highlights what it is on.
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        var connects = 0, taps = 0;
        await pumpLg(
          tester,
          _row(onTap: () => taps++, onConnect: () => connects++),
        );
        expect(find.text('连接'), findsNothing);
        await hover(tester, find.byType(LgDeviceRow));
        expect(find.text('连接'), findsOneWidget);
        await tester.tap(find.text('连接'));
        expect((connects, taps), (1, 0));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Tab reaches the row and Enter connects', (tester) async {
      var connects = 0, taps = 0;
      await pumpLg(
        tester,
        _row(onTap: () => taps++, onConnect: () => connects++),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      // Focused: the connect button shows although nothing hovers the row.
      expect(find.text('连接'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect((connects, taps), (1, 0));
    });

    testWidgets('the whole row is one semantics node with the connect action', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, _row(onTap: () {}, onConnect: () {}));
      final label = tester
          .getSemantics(find.bySemanticsLabel(RegExp('书房台式机, 在线')))
          .label;
      expect(label, contains('123 456 789'));
      expect(label, contains('zhangsan@DESKTOP-SHUFANG'));
      expect(find.bySemanticsLabel(RegExp('连接 书房台式机')), findsNothing);
      handle.dispose();
    });

    testWidgets('a row without callbacks is disabled', (tester) async {
      await pumpLg(tester, _row());
      await hover(tester, find.byType(LgDeviceRow));
      await tester.tap(find.text('书房台式机'));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('long names and addresses end in an ellipsis', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 640,
          child: LgDeviceRow(
            name: 'DESKTOP-ABCDEFGHIJKLMNOPQRSTUVWXYZ-很长很长的设备名称放不下时省略',
            id: '123 456 789',
            platform: LgPlatform.linux,
            status: LgDeviceStatus.querying,
            statusLabel: '正在查询…',
            userHost:
                'administrator@DESKTOP-ABCDEFGHIJKLMNOPQRSTUVWXYZ-0123456789',
            source: '最近',
            onTap: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('LgDeviceAvatar takes the colour of the ID, spaces or not', (
    tester,
  ) async {
    Color? tint(WidgetTester t) =>
        (t
                    .widget<Container>(
                      find
                          .descendant(
                            of: find.byType(LgDeviceAvatar),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration)
            .color;
    await pumpLg(
      tester,
      const LgDeviceAvatar(id: '123 456 789', platform: LgPlatform.windows),
    );
    final spaced = tint(tester);
    await pumpLg(
      tester,
      const LgDeviceAvatar(id: '123456789', platform: LgPlatform.macos),
    );
    expect(tint(tester), spaced);
    expect(spaced, LgColors.light.identity[identityGroup('123456789')].tint);
  });

  group('LgConnectToRow', () {
    testWidgets('taps, and the typed part of the line is bold', (tester) async {
      var taps = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 600,
          child: LgConnectToRow(
            text: '连接到 6789',
            emphasis: '6789',
            onTap: () => taps++,
          ),
        ),
      );
      await tester.tap(find.byType(LgConnectToRow));
      expect(taps, 1);
      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byType(LgConnectToRow),
          matching: find.byType(RichText),
        ),
      );
      final weights = <String, FontWeight?>{};
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) {
          weights[span.text!] = span.style?.fontWeight;
        }
        return true;
      });
      expect(weights['6789'], FontWeight.w700);
      expect(weights['连接到 '], isNull);
    });

    testWidgets('the highlighted "connect to" row is read as selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      bool selected(WidgetTester t) =>
          t
              .getSemantics(find.bySemanticsLabel('连接到 6789'))
              .getSemanticsData()
              .flagsCollection
              .isSelected ==
          Tristate.isTrue;
      Widget row({required bool highlighted}) => SizedBox(
        width: 600,
        child: LgConnectToRow(
          text: '连接到 6789',
          highlighted: highlighted,
          onTap: () {},
        ),
      );
      await pumpLg(tester, row(highlighted: false));
      expect(selected(tester), isFalse);
      await pumpLg(tester, row(highlighted: true));
      expect(selected(tester), isTrue);
      handle.dispose();
    });

    testWidgets('Enter on the focused row taps it', (tester) async {
      var taps = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 600,
          child: LgConnectToRow(text: '连接到 1', onTap: () => taps++),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(taps, 1);
    });
  });

  testWidgets('the states of a list name themselves for a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpLg(
      tester,
      const SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LgEmptyState('暂无最近连接的设备'),
            LgDeviceSkeleton(semanticLabel: '正在加载'),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('暂无最近连接的设备'), findsOneWidget);
    expect(find.bySemanticsLabel('正在加载'), findsOneWidget);
    handle.dispose();
  });
}
