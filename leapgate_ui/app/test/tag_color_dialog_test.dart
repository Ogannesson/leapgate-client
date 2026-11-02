import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_banner.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_color_wheel.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';
import 'package:leapgate_ui/widgets/lg_tag_color_dialog.dart';

import 'helpers.dart';

const _labels = LgTagColorDialogLabels(
  title: '修改标签颜色',
  colorLabel: '颜色',
  customLabel: '自定义',
  valueLabel: '颜色值',
  hexPlaceholder: '#RRGGBB',
  hexError: '颜色值格式不正确',
  brightnessLabel: '明度',
  wheelLabel: '色轮',
  cancel: '取消',
  save: '保存',
  busySave: '正在保存…',
);

const _pink = Color(0xFFA65B80);
const _teal = Color(0xFF009184);

class _Calls {
  final saved = <int>[];
  var cancelled = 0;
}

Future<void> _pump(
  WidgetTester tester,
  _Calls calls, {
  Color initial = _pink,
  bool custom = false,
  bool busy = false,
  String? error,
  LgMode mode = LgMode.compact,
}) {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return pumpLg(
    tester,
    LgTagColorDialog(
      labels: _labels,
      tagName: '家里',
      previewName: '书房台式机',
      initialColor: initial,
      startCustom: custom,
      busy: busy,
      error: error,
      onSave: calls.saved.add,
      onCancel: () => calls.cancelled++,
    ),
    mode: mode,
  );
}

Finder get _save => find.widgetWithText(LgButton, '保存');
Finder get _hexField => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == '#RRGGBB',
);
Finder _swatch(String hex) => find.bySemanticsLabel(hex);

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<LgButton>(find.byType(LgButton).last).onPressed != null;

String _hex(WidgetTester tester) =>
    tester.widget<TextField>(_hexField).controller!.text;

void main() {
  group('LgTagColorDialog', () {
    testWidgets('shows the tag as a card does, in the colour it has now', (
      tester,
    ) async {
      await _pump(tester, _Calls());
      expect(find.text('修改标签颜色'), findsOneWidget);
      expect(find.text('书房台式机'), findsOneWidget);
      expect(find.text('家里'), findsOneWidget);
      expect(find.text('颜色'), findsOneWidget);
      // The wheel is folded away.
      expect(find.byType(LgColorWheel), findsNothing);
      expect(find.text('自定义'), findsOneWidget);
    });

    testWidgets('the ready colours are fixed numbers, whatever the theme', (
      tester,
    ) async {
      expect(lgTagPresetColors, hasLength(8));
      await _pump(tester, _Calls());
      final dark = lgTagPresetColors.map((c) => c.toARGB32()).toList();
      expect(dark.first, 0xFFA65B80);
      expect(dark, everyElement(isNot(0)));
    });

    testWidgets('save is grey until another colour is taken', (tester) async {
      final calls = _Calls();
      await _pump(tester, calls);
      expect(_saveEnabled(tester), isFalse);
      await tester.tap(_save, warnIfMissed: false);
      expect(calls.saved, isEmpty);
    });

    testWidgets('the colour in use is the one with the check', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _Calls());
      expect(
        tester.getSemantics(_swatch('#A65B80')),
        isSemantics(isButton: true, hasSelectedState: true, isSelected: true),
      );
      expect(
        tester.getSemantics(_swatch('#009184')),
        isSemantics(isButton: true, hasSelectedState: true, isSelected: false),
      );
      handle.dispose();
    });

    testWidgets('a ready colour moves the check, enables save and saves the '
        'number', (tester) async {
      final handle = tester.ensureSemantics();
      final calls = _Calls();
      await _pump(tester, calls);
      await tester.tap(_swatch('#009184'));
      await tester.pump();
      expect(
        tester.getSemantics(_swatch('#009184')),
        isSemantics(isButton: true, hasSelectedState: true, isSelected: true),
      );
      expect(_saveEnabled(tester), isTrue);
      await tester.tap(_save);
      expect(calls.saved, [0xFF009184]);
      handle.dispose();
    });

    testWidgets('taking the old colour back greys save again', (tester) async {
      final calls = _Calls();
      await _pump(tester, calls, initial: _teal);
      await tester.tap(_swatch('#A65B80'));
      await tester.pump();
      expect(_saveEnabled(tester), isTrue);
      await tester.tap(_swatch('#009184'));
      await tester.pump();
      expect(_saveEnabled(tester), isFalse);
    });

    testWidgets('"自定义" opens the wheel, the field and the bar, and closes '
        'them', (tester) async {
      await _pump(tester, _Calls());
      await tester.tap(find.text('自定义'));
      await tester.pump();
      expect(find.byType(LgColorWheel), findsOneWidget);
      expect(find.byType(LgValueBar), findsOneWidget);
      expect(_hex(tester), '#A65B80');
      await tester.tap(find.text('自定义'));
      await tester.pump();
      expect(find.byType(LgColorWheel), findsNothing);
    });

    testWidgets('a typed colour is taken: save sends it', (tester) async {
      final calls = _Calls();
      await _pump(tester, calls, custom: true);
      await tester.enterText(_hexField, '#E0852B');
      await tester.pump();
      expect(find.text('颜色值格式不正确'), findsNothing);
      expect(_saveEnabled(tester), isTrue);
      await tester.tap(_save);
      expect(calls.saved, [0xFFE0852B]);
    });

    testWidgets('the # may be left out and the case does not matter', (
      tester,
    ) async {
      final calls = _Calls();
      await _pump(tester, calls, custom: true);
      await tester.enterText(_hexField, 'e0852b');
      await tester.pump();
      expect(_saveEnabled(tester), isTrue);
      await tester.tap(_save);
      expect(calls.saved, [0xFFE0852B]);
    });

    testWidgets('what is not a colour is told under the field and cannot be '
        'saved', (tester) async {
      final calls = _Calls();
      await _pump(tester, calls, custom: true);
      await tester.tap(_hexField);
      await tester.enterText(_hexField, '#C4527');
      await tester.pump();
      expect(find.text('颜色值格式不正确'), findsOneWidget);
      expect(_saveEnabled(tester), isFalse);
      // Enter does not save it either.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls.saved, isEmpty);
      // Typing it right takes the error away.
      await tester.enterText(_hexField, '#C45278');
      await tester.pump();
      expect(find.text('颜色值格式不正确'), findsNothing);
      expect(_saveEnabled(tester), isTrue);
    });

    testWidgets('Enter in the field saves a changed colour', (tester) async {
      final calls = _Calls();
      await _pump(tester, calls, custom: true);
      await tester.tap(_hexField);
      await tester.enterText(_hexField, '#336699');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls.saved, [0xFF336699]);
    });

    testWidgets('a click on the wheel sets the hex: the top is red, the '
        'bottom is cyan', (tester) async {
      await _pump(tester, _Calls(), custom: true);
      final wheel = tester.getRect(find.byType(LgColorWheel));
      await tester.tapAt(Offset(wheel.center.dx, wheel.top + 8));
      await tester.pump();
      var hex = _hex(tester);
      var r = int.parse(hex.substring(1, 3), radix: 16);
      var g = int.parse(hex.substring(3, 5), radix: 16);
      var b = int.parse(hex.substring(5, 7), radix: 16);
      expect(r, greaterThan(g));
      expect(r, greaterThan(b));
      await tester.tapAt(Offset(wheel.center.dx, wheel.bottom - 8));
      await tester.pump();
      hex = _hex(tester);
      r = int.parse(hex.substring(1, 3), radix: 16);
      g = int.parse(hex.substring(3, 5), radix: 16);
      b = int.parse(hex.substring(5, 7), radix: 16);
      expect(r, lessThan(g));
      expect(r, lessThan(b));
      expect(_saveEnabled(tester), isTrue);
    });

    testWidgets('dragging on the wheel follows the pointer', (tester) async {
      await _pump(tester, _Calls(), custom: true);
      final wheel = tester.getRect(find.byType(LgColorWheel));
      final g = await tester.startGesture(
        Offset(wheel.center.dx, wheel.top + 8),
      );
      await g.moveTo(Offset(wheel.right - 8, wheel.center.dy));
      await g.up();
      await tester.pump();
      // The right edge is between yellow and green: red and green high.
      final hex = _hex(tester);
      final b = int.parse(hex.substring(5, 7), radix: 16);
      final g2 = int.parse(hex.substring(3, 5), radix: 16);
      expect(g2, greaterThan(b));
    });

    testWidgets('the bar sets the lightness: left is black, right is the '
        'full colour', (tester) async {
      await _pump(tester, _Calls(), custom: true);
      final bar = tester.getRect(find.byType(LgValueBar));
      await tester.tapAt(Offset(bar.left + 1, bar.center.dy));
      await tester.pump();
      expect(_hex(tester), '#000000');
      await tester.tapAt(Offset(bar.right - 1, bar.center.dy));
      await tester.pump();
      expect(_hex(tester), isNot('#000000'));
      expect(_saveEnabled(tester), isTrue);
    });

    testWidgets('the bar answers the arrow keys and Home', (tester) async {
      await _pump(tester, _Calls(), custom: true);
      // Tab: swatch..., custom toggle, wheel, hex field, bar.
      final bar = find.byType(LgValueBar);
      await tester.tap(bar);
      await tester.pump();
      final before = _hex(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(_hex(tester), isNot(before));
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(_hex(tester), '#000000');
    });

    testWidgets('the wheel answers the arrow keys when it has the focus', (
      tester,
    ) async {
      await _pump(tester, _Calls(), custom: true);
      // Off the middle, where the hue means something.
      await tester.tapAt(
        tester.getCenter(find.byType(LgColorWheel)) + const Offset(40, 0),
      );
      await tester.pump();
      final before = _hex(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(_hex(tester), isNot(before));
      final once = _hex(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(_hex(tester), isNot(once));
    });

    testWidgets('the wheel and the bar are named, the bar with its value', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _Calls(), custom: true);
      expect(find.bySemanticsLabel('色轮'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('明度')),
        isSemantics(
          isSlider: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('busy: nothing can be changed, save turns, cancel works', (
      tester,
    ) async {
      final calls = _Calls();
      await _pump(tester, calls, busy: true, custom: true);
      expect(find.text('正在保存…'), findsOneWidget);
      expect(find.byType(LgSpinner), findsOneWidget);
      await tester.tap(_swatch('#009184'), warnIfMissed: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls.saved, isEmpty);
      expect(tester.widget<TextField>(_hexField).enabled, isFalse);
      await tester.tap(find.widgetWithText(LgButton, '取消'));
      expect(calls.cancelled, 1);
    });

    testWidgets('a refusal is a banner under the title, the dialog stays', (
      tester,
    ) async {
      await _pump(tester, _Calls(), error: '无法修改标签颜色。\n服务器返回：服务暂不可用。');
      expect(find.byType(LgBanner), findsOneWidget);
      expect(find.textContaining('服务器返回：服务暂不可用。'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(LgBanner)).dy,
        lessThan(tester.getTopLeft(find.text('书房台式机')).dy),
      );
    });

    testWidgets('fits in the detail mode', (tester) async {
      await _pump(tester, _Calls(), custom: true, mode: LgMode.detail);
      expect(tester.takeException(), isNull);
    });
  });
}
