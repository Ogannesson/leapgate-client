// Behaviour of the file list's header and rows (docs LEAPGATE.md §10.15): sorting and the width
// handles of the header, and the clicks, the keyboard and the states of a row. The rows report
// what the pointer did; selecting and opening are the caller's. No pixels.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/widgets/lg_file_list.dart';

import 'helpers.dart';

const _labels = LgFileHeaderLabels(
  name: '名称',
  modified: '修改日期',
  type: '类型',
  size: '大小',
  ascending: '升序',
  descending: '降序',
);

Widget _header({
  LgFileColumn? sort = LgFileColumn.name,
  bool ascending = true,
  ValueChanged<LgFileColumn>? onSort,
  bool showType = true,
  LgFileColumns columns = const LgFileColumns(),
  void Function(LgFileColumn, double)? onResize,
  double width = 618,
}) => SizedBox(
  width: width,
  child: LgFileListHeader(
    labels: _labels,
    sortColumn: sort,
    ascending: ascending,
    onSort: onSort ?? (_) {},
    showType: showType,
    columns: columns,
    onResize: onResize,
  ),
);

Finder _icon(LgIcons icon) =>
    find.byWidgetPredicate((w) => w is LgIcon && w.icon == icon);

Widget _row({
  LgFileKind kind = LgFileKind.file,
  String name = '年度报告.docx',
  bool link = false,
  bool hidden = false,
  bool selected = false,
  bool focused = false,
  bool dropTarget = false,
  bool showType = true,
  VoidCallback? onTap,
  VoidCallback? onDoubleTap,
  ValueChanged<Offset>? onSecondaryTap,
  double width = 618,
}) => SizedBox(
  width: width,
  child: LgFileRow(
    kind: kind,
    name: name,
    modified: '2026/10/28 14:05',
    type: 'DOCX 文件',
    size: '2.4 MB',
    link: link,
    hidden: hidden,
    selected: selected,
    focused: focused,
    dropTarget: dropTarget,
    showType: showType,
    onTap: onTap,
    onDoubleTap: onDoubleTap,
    onSecondaryTap: onSecondaryTap,
  ),
);

void main() {
  group('header', () {
    testWidgets('the four names are there, the type column can be left out', (
      tester,
    ) async {
      await pumpLg(tester, _header());
      for (final n in ['名称', '修改日期', '类型', '大小']) {
        expect(find.text(n), findsOneWidget);
      }
      await pumpLg(tester, _header(showType: false));
      expect(find.text('类型'), findsNothing);
    });

    testWidgets('a click on a name sorts by that column', (tester) async {
      final log = <LgFileColumn>[];
      await pumpLg(tester, _header(onSort: log.add));
      await tester.tap(find.text('修改日期'));
      await tester.tap(find.text('大小'));
      await tester.tap(find.text('名称'));
      expect(log, [
        LgFileColumn.modified,
        LgFileColumn.size,
        LgFileColumn.name,
      ]);
    });

    testWidgets(
      'the arrow stands on the sorted column and turns with the direction',
      (tester) async {
        await pumpLg(tester, _header(sort: LgFileColumn.modified));
        expect(_icon(LgIcons.chevU), findsOneWidget);
        expect(_icon(LgIcons.chevD), findsNothing);
        final arrow = tester.getCenter(_icon(LgIcons.chevU)).dx;
        expect(arrow > tester.getCenter(find.text('修改日期')).dx, isTrue);
        await pumpLg(
          tester,
          _header(sort: LgFileColumn.modified, ascending: false),
        );
        expect(_icon(LgIcons.chevD), findsOneWidget);
        await pumpLg(tester, _header(sort: null));
        expect(_icon(LgIcons.chevU), findsNothing);
        expect(_icon(LgIcons.chevD), findsNothing);
      },
    );

    testWidgets(
      'a screen reader hears the direction of the sorted column only',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpLg(
          tester,
          _header(sort: LgFileColumn.size, ascending: false),
        );
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('大小'))
              .getSemanticsData()
              .hint,
          '降序',
        );
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('名称'))
              .getSemanticsData()
              .hint,
          isEmpty,
        );
        handle.dispose();
      },
    );

    testWidgets('dragging a column\'s left edge to the left makes it wider', (
      tester,
    ) async {
      final log = <(LgFileColumn, double)>[];
      await pumpLg(tester, _header(onResize: (c, d) => log.add((c, d))));
      // The left edge of the size column: its width, the gap and half a gap from the right
      // padding of 16.
      final box = tester.getRect(find.byType(LgFileListHeader));
      final edge = Offset(box.right - 16 - 76 - 6, box.center.dy);
      await tester.dragFrom(edge, const Offset(-20, 0));
      expect(log, isNotEmpty);
      expect(log.every((e) => e.$1 == LgFileColumn.size), isTrue);
      expect(log.fold<double>(0, (s, e) => s + e.$2), greaterThan(0));
    });

    testWidgets('without a resize callback there are no handles', (
      tester,
    ) async {
      await pumpLg(tester, _header());
      expect(
        find.byType(MouseRegion).evaluate().where((e) {
          final m = e.widget as MouseRegion;
          return m.cursor == SystemMouseCursors.resizeColumn;
        }),
        isEmpty,
      );
    });

    test('widths grow with the drag and stop at the smallest', () {
      const c = LgFileColumns();
      expect(c.resized(LgFileColumn.modified, 20).modified, 160);
      expect(c.resized(LgFileColumn.size, -500).size, LgFileColumns.minSize);
      expect(c.resized(LgFileColumn.type, 1000).type, 400);
      expect(c.resized(LgFileColumn.name, 20), c);
      expect(c.resized(LgFileColumn.modified, 20).type, c.type);
    });

    testWidgets('a header that is narrow with its widths is not overflowed', (
      tester,
    ) async {
      await pumpLg(tester, _header(width: 470, showType: false));
      expect(tester.takeException(), isNull);
    });
  });

  group('row', () {
    testWidgets('a press selects at once, with no wait for a second click', (
      tester,
    ) async {
      var taps = 0;
      await pumpLg(tester, _row(onTap: () => taps++, onDoubleTap: () {}));
      await tester.tap(find.text('年度报告.docx'));
      expect(taps, 1);
    });

    testWidgets('a second press soon after is a double click', (tester) async {
      final log = <String>[];
      await pumpLg(
        tester,
        _row(onTap: () => log.add('tap'), onDoubleTap: () => log.add('double')),
      );
      await tester.tap(find.text('年度报告.docx'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('年度报告.docx'));
      expect(log, ['tap', 'tap', 'double']);
    });

    testWidgets('two presses far apart in time are two clicks', (tester) async {
      final log = <String>[];
      await pumpLg(
        tester,
        _row(onTap: () => log.add('tap'), onDoubleTap: () => log.add('double')),
      );
      // The events of the test carry no clock of their own: give them one.
      final at = tester.getCenter(find.text('年度报告.docx'));
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.down(at);
      await g.up();
      await g.down(at, timeStamp: const Duration(milliseconds: 600));
      await g.up(timeStamp: const Duration(milliseconds: 650));
      expect(log, ['tap', 'tap']);
    });

    testWidgets('a third press after a double click starts over', (
      tester,
    ) async {
      final log = <String>[];
      await pumpLg(
        tester,
        _row(onTap: () => log.add('tap'), onDoubleTap: () => log.add('double')),
      );
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('年度报告.docx'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(log.where((e) => e == 'double').length, 1);
    });

    testWidgets(
      'the right button reports where the pointer is, and does not select',
      (tester) async {
        var taps = 0;
        Offset? at;
        await pumpLg(
          tester,
          _row(onTap: () => taps++, onSecondaryTap: (p) => at = p),
        );
        final centre = tester.getCenter(find.text('年度报告.docx'));
        final g = await tester.startGesture(
          centre,
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await g.up();
        expect(at, centre);
        expect(taps, 0);
      },
    );

    testWidgets(
      'a link has the small chain, a drive and a folder their icons',
      (tester) async {
        await pumpLg(tester, _row(link: true));
        expect(_icon(LgIcons.link), findsOneWidget);
        expect(_icon(LgIcons.file), findsOneWidget);
        await pumpLg(tester, _row(kind: LgFileKind.folder));
        expect(_icon(LgIcons.folder), findsOneWidget);
        expect(_icon(LgIcons.link), findsNothing);
        await pumpLg(tester, _row(kind: LgFileKind.drive));
        expect(_icon(LgIcons.drive), findsOneWidget);
      },
    );

    testWidgets('a hidden item is drawn at 70 %', (tester) async {
      await pumpLg(tester, _row(hidden: true));
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text('年度报告.docx'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, .7);
      await pumpLg(tester, _row());
      final plain = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text('年度报告.docx'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(plain.opacity, 1);
    });

    testWidgets(
      'the cells show what the caller formatted; the type column can be left out',
      (tester) async {
        await pumpLg(tester, _row());
        for (final t in ['2026/10/28 14:05', 'DOCX 文件', '2.4 MB']) {
          expect(find.text(t), findsOneWidget);
        }
        await pumpLg(tester, _row(showType: false));
        expect(find.text('DOCX 文件'), findsNothing);
      },
    );

    testWidgets('the cells line up with the header', (tester) async {
      await pumpLg(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: EdgeInsets.zero, child: _header()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _row(width: 602),
            ),
          ],
        ),
      );
      expect(
        tester.getTopLeft(find.text('修改日期')).dx,
        closeTo(tester.getTopLeft(find.text('2026/10/28 14:05')).dx, 1),
      );
      expect(
        tester.getTopLeft(find.text('类型')).dx,
        closeTo(tester.getTopLeft(find.text('DOCX 文件')).dx, 1),
      );
    });

    testWidgets('a long name is cut with room for the cells', (tester) async {
      await pumpLg(
        tester,
        _row(
          name: '一个名字很长很长很长很长很长很长很长很长很长很长很长很长很长的文件.docx',
          width: 470,
          showType: false,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('tinted and framed states build without a pointer', (
      tester,
    ) async {
      for (final w in [
        _row(selected: true),
        _row(focused: true),
        _row(dropTarget: true),
        _row(selected: true, link: true),
      ]) {
        await pumpLg(tester, w);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
      'a row is a button with its cells in the name, and says when selected',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpLg(tester, _row(selected: true, onTap: () {}));
        final node = tester.getSemantics(
          find.bySemanticsLabel(RegExp('年度报告.docx')),
        );
        final data = node.getSemanticsData();
        expect(data.label, contains('DOCX 文件'));
        expect(data.label, contains('2.4 MB'));
        expect(data.flagsCollection.isSelected.name, 'isTrue');
        expect(data.flagsCollection.isButton, isTrue);
        handle.dispose();
      },
    );

    testWidgets('a row with its own name uses it', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        const SizedBox(
          width: 618,
          child: LgFileRow(
            kind: LgFileKind.folder,
            name: '照片',
            semanticLabel: '文件夹 照片',
          ),
        ),
      );
      expect(find.bySemanticsLabel('文件夹 照片'), findsOneWidget);
      handle.dispose();
    });

    testWidgets(
      'the divider shows above a plain row and not above a hovered one',
      (tester) async {
        Finder divider() => find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color != Colors.transparent,
        );
        await pumpLg(
          tester,
          const SizedBox(
            width: 618,
            child: LgFileRow(
              kind: LgFileKind.file,
              name: '说明.txt',
              topDivider: true,
            ),
          ),
        );
        final withDivider = divider().evaluate().length;
        await pumpLg(
          tester,
          const SizedBox(
            width: 618,
            child: LgFileRow(kind: LgFileKind.file, name: '说明.txt'),
          ),
        );
        expect(withDivider, greaterThan(divider().evaluate().length));
        await pumpLg(
          tester,
          const SizedBox(
            width: 618,
            child: LgFileRow(
              kind: LgFileKind.file,
              name: '说明.txt',
              topDivider: true,
              selected: true,
            ),
          ),
        );
        expect(divider().evaluate().length, lessThan(withDivider));
      },
    );
  });
}
