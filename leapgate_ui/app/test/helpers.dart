import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';

Future<void> pumpLg(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  LgMode mode = LgMode.compact,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildLgTheme(brightness: brightness, mode: mode),
      themeAnimationDuration: Duration.zero,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// Moves a mouse pointer onto [finder] and keeps it there.
Future<TestGesture> hover(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pump();
  return gesture;
}
