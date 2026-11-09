// Behaviour of what the camera view needs of the components (docs LEAPGATE.md §10.18, 14 §2.6;
// `A-P10-摄像头.html`): the two-line hover of a camera's flat button, the recording button with
// the time, and the name of a camera at the end of a menu row. Callbacks are called, the names a
// screen reader gets are there, and a button without the new parameters is what it was.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_session_toolbar.dart';

import 'helpers.dart';

LgToolbarTextButton _tile({
  String? tooltip,
  String? tooltipNote,
  VoidCallback? onPressed,
}) => LgToolbarTextButton(
  label: '1',
  selected: true,
  semanticLabel: '摄像头 1，Integrated Camera',
  tooltip: tooltip,
  tooltipNote: tooltipNote,
  onPressed: onPressed ?? () {},
);

void main() {
  group('LgToolbarTextButton hover', () {
    testWidgets('two lines: the camera in bold, its name under it', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _tile(tooltip: '摄像头 1', tooltipNote: 'Integrated Camera'),
      );
      await hover(tester, find.byType(LgToolbarTextButton));
      await tester.pump(const Duration(seconds: 1));

      final first = tester.widget<Text>(find.text('摄像头 1'));
      expect(first.style!.fontWeight, FontWeight.w700);
      final second = tester.widget<Text>(find.text('Integrated Camera'));
      expect(second.style!.color, LgColors.light.text2);
      // One under the other.
      expect(
        tester.getTopLeft(find.text('Integrated Camera')).dy,
        greaterThan(tester.getBottomLeft(find.text('摄像头 1')).dy - 1),
      );
      // The old hover text is not shown as well.
      expect(find.text('摄像头 1，Integrated Camera'), findsNothing);
    });

    testWidgets('no name: the first line alone', (tester) async {
      await pumpLg(tester, _tile(tooltip: '摄像头 1'));
      await hover(tester, find.byType(LgToolbarTextButton));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('摄像头 1'), findsOneWidget);
      expect(find.text('Integrated Camera'), findsNothing);
    });

    testWidgets('without the new parameters the hover is the name, as before', (
      tester,
    ) async {
      await pumpLg(tester, _tile());
      await hover(tester, find.byType(LgToolbarTextButton));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('摄像头 1，Integrated Camera'), findsOneWidget);
    });

    testWidgets('a screen reader still gets the whole name and a button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        _tile(tooltip: '摄像头 1', tooltipNote: 'Integrated Camera'),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('摄像头 1，Integrated Camera')),
        isSemantics(
          label: '摄像头 1，Integrated Camera',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('the button still presses', (tester) async {
      var n = 0;
      await pumpLg(
        tester,
        _tile(
          tooltip: '摄像头 1',
          tooltipNote: 'Integrated Camera',
          onPressed: () => n++,
        ),
      );
      await tester.tap(find.text('1'));
      expect(n, 1);
    });

    test('a note needs a first line', () {
      expect(
        () => LgToolbarTextButton(
          label: '1',
          semanticLabel: 'x',
          tooltipNote: 'Integrated Camera',
          onPressed: () {},
        ),
        throwsAssertionError,
      );
    });
  });

  group('LgToolbarButton with the time of a recording', () {
    Widget button({String? recording, bool showText = false}) =>
        LgToolbarButton(
          icon: LgIcons.record,
          label: recording == null ? '录制' : '停止录制',
          semanticLabel: recording == null ? null : '停止录制，$recording',
          recordingText: recording,
          showText: showText,
          toggled: recording != null,
          onPressed: () {},
        );

    testWidgets('shows the time in bold after the icon', (tester) async {
      await pumpLg(tester, button(recording: '00:42'));
      final time = tester.widget<Text>(find.text('00:42'));
      expect(time.style!.fontWeight, FontWeight.w700);
      expect(time.style!.color, LgColors.light.error);
      expect(
        tester.getCenter(find.text('00:42')).dx,
        greaterThan(
          tester
              .getCenter(
                find.byWidgetPredicate(
                  (w) => w is LgIcon && w.icon == LgIcons.record,
                ),
              )
              .dx,
        ),
      );
    });

    testWidgets('the ground is the error tint, the icon the error colour', (
      tester,
    ) async {
      await pumpLg(tester, button(recording: '00:42'));
      final ground = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(LgToolbarButton),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .whereType<Color>();
      expect(ground, contains(LgColors.light.errorBg));
      final icon = tester.widget<LgIcon>(
        find.byWidgetPredicate((w) => w is LgIcon && w.icon == LgIcons.record),
      );
      expect(icon.color, LgColors.light.error);
    });

    testWidgets('both themes: the dark tint and colour', (tester) async {
      await pumpLg(
        tester,
        button(recording: '00:42'),
        brightness: Brightness.dark,
      );
      expect(
        tester.widget<Text>(find.text('00:42')).style!.color,
        LgColors.dark.error,
      );
    });

    testWidgets(
      'its name and tooltip are the action; the reader gets the time',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpLg(tester, button(recording: '00:42'));
        expect(find.bySemanticsLabel('停止录制，00:42'), findsOneWidget);
        await hover(tester, find.byType(LgToolbarButton));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('停止录制'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('without the time it is the icon alone, as it was', (
      tester,
    ) async {
      await pumpLg(tester, button());
      expect(find.text('录制'), findsNothing);
      expect(find.text('00:42'), findsNothing);
      final ground = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(LgToolbarButton),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color);
      expect(ground, isNot(contains(LgColors.light.errorBg)));
    });

    testWidgets('the written name of the detail mode is kept without a time', (
      tester,
    ) async {
      await pumpLg(tester, button(showText: true));
      expect(find.text('录制'), findsOneWidget);
    });

    testWidgets('it still presses while recording', (tester) async {
      var n = 0;
      await pumpLg(
        tester,
        LgToolbarButton(
          icon: LgIcons.record,
          label: '停止录制',
          recordingText: '00:05',
          onPressed: () => n++,
        ),
      );
      await tester.tap(find.text('00:05'));
      expect(n, 1);
    });
  });

  group('LgMenuRowNote', () {
    Widget row(String name, {double width = 330}) => SizedBox(
      width: width,
      child: LgMenuPanel(
        width: width,
        items: [
          LgMenuItem(
            label: '摄像头 1',
            checked: true,
            trailing: LgMenuRowNote(name),
            onPressed: () {},
          ),
        ],
      ),
    );

    testWidgets('a short name stands at the end of the row, small and grey', (
      tester,
    ) async {
      await pumpLg(tester, row('USB Camera'));
      final note = tester.widget<Text>(find.text('USB Camera'));
      expect(note.style!.color, LgColors.light.text2);
      expect(note.style!.fontSize, 13);
      expect(note.style!.fontWeight, FontWeight.w400);
      final panel = tester.getRect(find.byType(LgMenuPanel));
      expect(
        tester.getRect(find.text('USB Camera')).right,
        lessThanOrEqualTo(panel.right - LgSpace.s4),
      );
    });

    testWidgets(
      'a long name ends in "…" within 170 px and shows whole on hover',
      (tester) async {
        const name = 'Integrated Camera with a very long vendor name';
        await pumpLg(tester, row(name));
        final shown = tester.widget<Text>(find.text(name));
        expect(shown.overflow, TextOverflow.ellipsis);
        expect(shown.maxLines, 1);
        expect(tester.getSize(find.text(name)).width, lessThanOrEqualTo(170));

        await hover(tester, find.text(name));
        await tester.pump(const Duration(seconds: 1));
        // The same text twice: the cut one in the row, the whole one in the tooltip.
        expect(find.text(name), findsNWidgets(2));
      },
    );

    testWidgets('the row is read with the name', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, row('USB Camera'));
      expect(
        find.bySemanticsLabel(RegExp('摄像头 1.*USB Camera', dotAll: true)),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the row presses and the name does not get in the way', (
      tester,
    ) async {
      var n = 0;
      // In an open menu, as the camera switch has it (a panel drawn in place has no menu
      // around it to answer a press).
      await pumpLg(
        tester,
        LgMenuAnchor(
          width: 330,
          items: [
            LgMenuItem(
              label: '摄像头 2',
              trailing: const LgMenuRowNote('USB Camera'),
              onPressed: () => n++,
            ),
          ],
          builder: (context, controller) =>
              TextButton(onPressed: controller.open, child: const Text('open')),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USB Camera'));
      await tester.pumpAndSettle();
      expect(n, 1);
    });
  });
}
