// Three additions to the dialog and menu components for the file transfer view (M7a
// final visual check): a leading item on LgConfirmDialog, an LgFormDialog without
// the icon tile, and the check mark of an LgMenuItem said to a screen reader. The
// defaults draw what they drew before; those are pinned by the older tests of each
// component and by the gallery's pixel comparison.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_feedback.dart';
import 'package:leapgate_ui/widgets/lg_form_dialog.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_text_field.dart';

import 'helpers.dart';

/// The card is 28 px from its content on every side (`.sheet` padding).
const _pad = 28.0;

/// The replace question of the file transfer view: with [leading] the way out of
/// the whole transfer is that; without it, the first of the buttons.
Widget _replace({Widget? leading, void Function(String)? on}) =>
    LgConfirmDialog(
      title: '替换“年度报告.docx”？',
      body: '目标文件夹“D:\\备份”中已有同名文件。',
      width: 480,
      leading: leading,
      actions: [
        if (leading == null)
          LgDialogAction(
            label: '取消传输',
            kind: LgButtonKind.text,
            onPressed: () => on?.call('cancel'),
          ),
        LgDialogAction(label: '跳过', onPressed: () => on?.call('skip')),
        LgDialogAction(
          label: '替换',
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: () => on?.call('replace'),
        ),
      ],
    );

void main() {
  group('LgConfirmDialog.leading', () {
    testWidgets('sits at the lower left, the answers stay at the right', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _replace(
          leading: LgButton(
            label: '取消传输',
            kind: LgButtonKind.text,
            onPressed: () {},
          ),
        ),
      );
      final card = tester.getRect(find.byType(LgConfirmDialog));
      final lead = tester.getRect(find.widgetWithText(LgButton, '取消传输'));
      final skip = tester.getRect(find.widgetWithText(LgButton, '跳过'));
      final replace = tester.getRect(find.widgetWithText(LgButton, '替换'));
      // The text button's own padding is inside its rect, so its left edge is the
      // content edge, as the rest of the dialog's text.
      expect(lead.left, closeTo(card.left + _pad, 1));
      expect(replace.right, closeTo(card.right - _pad, 1));
      expect(lead.right, lessThan(skip.left));
      expect(skip.right, lessThan(replace.left));
      expect(lead.center.dy, closeTo(skip.center.dy, 1));
      expect(skip.center.dy, closeTo(replace.center.dy, 1));
    });

    testWidgets('is not an answer: Enter runs the default one, a tap its own', (
      tester,
    ) async {
      final calls = <String>[];
      await pumpLg(
        tester,
        _replace(
          leading: LgButton(
            label: '取消传输',
            kind: LgButtonKind.text,
            onPressed: () => calls.add('lead'),
          ),
          on: calls.add,
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, ['replace']);
      await tester.tap(find.text('取消传输'));
      expect(calls, ['replace', 'lead']);
    });

    testWidgets('without it the whole row of buttons is at the right', (
      tester,
    ) async {
      await pumpLg(tester, _replace(on: (_) {}));
      final card = tester.getRect(find.byType(LgConfirmDialog));
      final first = tester.getRect(find.widgetWithText(LgButton, '取消传输'));
      final last = tester.getRect(find.widgetWithText(LgButton, '替换'));
      expect(last.right, closeTo(card.right - _pad, 1));
      // Far from the left edge: nothing is pushed there.
      expect(first.left, greaterThan(card.left + _pad + 60));
    });
  });

  group('LgFormDialog without an icon', () {
    Widget form({LgIcons? icon}) => LgFormDialog(
      title: '新建文件夹',
      icon: icon,
      width: 440,
      actions: const [
        LgDialogAction(label: '取消', onPressed: null),
        LgDialogAction(
          label: '新建',
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: null,
        ),
      ],
      children: const [
        LgFormField(
          label: '名称',
          child: LgTextField(placeholder: '名称'),
        ),
      ],
    );

    Finder tiles() => find.descendant(
      of: find.byType(LgFormDialog),
      matching: find.byType(LgIcon),
    );

    testWidgets('draws no icon tile and the title starts at the left edge', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, form());
      expect(tiles(), findsNothing);
      final card = tester.getRect(find.byType(LgFormDialog));
      expect(
        tester.getTopLeft(find.text('新建文件夹')).dx,
        closeTo(card.left + _pad, 1),
      );
      // It is still the heading and still names the dialog.
      expect(find.bySemanticsLabel('新建文件夹'), findsWidgets);
      handle.dispose();
    });

    testWidgets('the head is the height of the title alone', (tester) async {
      await pumpLg(tester, form(icon: LgIcons.folder));
      expect(tiles(), findsOneWidget);
      final withIcon = tester.getSize(find.byType(LgFormDialog)).height;
      final titleLeft = tester.getTopLeft(find.text('新建文件夹')).dx;
      final cardLeft = tester.getRect(find.byType(LgFormDialog)).left;
      // The tile, 44 px, and its gap, 14 px, stand before the title.
      expect(titleLeft, closeTo(cardLeft + _pad + 44 + 14, 1));
      await pumpLg(tester, form());
      // The title row is 28 px high; with the tile it was 44.
      expect(
        tester.getSize(find.byType(LgFormDialog)).height,
        closeTo(withIcon - (44 - 28), 1),
      );
    });
  });

  group('LgMenuItem.checked and a screen reader', () {
    testWidgets('the row with the check mark is read as checked', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        LgMenuAnchor(
          items: [
            LgMenuItem(label: '名称', checked: true, onPressed: () {}),
            LgMenuItem(label: '修改日期', checked: false, onPressed: () {}),
            LgMenuItem(label: '类型', onPressed: () {}),
          ],
          builder: (context, c) => LgButton(label: '排序', onPressed: c.open),
        ),
      );
      await tester.tap(find.text('排序'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.bySemanticsLabel('名称')),
        isSemantics(
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
          hasCheckedState: true,
          isChecked: true,
        ),
      );
      // The rows without the mark say nothing about it, as before.
      for (final label in ['修改日期', '类型']) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(
            isButton: true,
            isEnabled: true,
            hasTapAction: true,
            hasCheckedState: false,
          ),
          reason: label,
        );
      }
      handle.dispose();
    });
  });
}
