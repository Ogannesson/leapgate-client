import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_session_toolbar.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';
import 'package:leapgate_ui/widgets/lg_tooltip.dart';

import 'helpers.dart';

const _labels = LgToolbarLabels(
  toolbar: '会话工具栏',
  pin: '固定工具栏',
  fullscreen: '全屏',
  exitFullscreen: '退出全屏',
  minimize: '最小化',
  collapse: '收起工具栏',
  expand: '展开工具栏',
  drag: '移动工具栏',
  more: '更多',
);

Future<void> _stage(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1000, 600),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return pumpLg(tester, SizedBox.expand(child: child));
}

LgSessionToolbar _bar({
  LgToolbarDock dock = LgToolbarDock.top,
  bool collapsed = false,
  int unread = 1,
  LgToolbarMenuState chat = LgToolbarMenuState.normal,
  List<String>? log,
  String? note,
  LgNoteSide? noteSide,
}) => LgSessionToolbar(
  labels: _labels,
  dock: dock,
  noteSide: noteSide,
  pinned: true,
  onTogglePin: () => log?.add('pin'),
  collapsed: collapsed,
  onToggleCollapsed: () => log?.add('collapse'),
  fullscreen: false,
  onToggleFullscreen: () {},
  route: LgRoute.direct,
  routeLabel: '直连',
  collapsedActions: [
    LgToolbarButton(
      icon: LgIcons.displays,
      label: '2/3',
      showText: true,
      semanticLabel: '切换显示器，当前第 2 个，共 3 个',
      onPressed: () => log?.add('switch display'),
    ),
  ],
  groups: [
    [
      LgToolbarMenuButton(
        label: '画面',
        icon: LgIcons.image,
        items: [
          LgMenuItem(
            label: '适应窗口',
            checked: true,
            onPressed: () => log?.add('fit'),
          ),
          LgMenuItem(label: '原始大小', onPressed: null, disabledNote: note),
        ],
      ),
      const LgToolbarFoldable(
        inline: LgToolbarMenuButton(
          label: '会话',
          icon: LgIcons.toggles,
          items: [LgMenuItem(label: '静音', onPressed: null)],
        ),
        menuItem: LgSubmenu(
          label: '会话',
          icon: LgIcons.toggles,
          items: [LgMenuItem(label: '静音', onPressed: null)],
        ),
      ),
      LgToolbarFoldable(
        badge: unread,
        inline: LgToolbarMenuButton(
          label: switch (chat) {
            LgToolbarMenuState.normal => '聊天',
            LgToolbarMenuState.pending => '等待接听…',
            LgToolbarMenuState.live => '通话中',
          },
          icon: LgIcons.chat,
          state: chat,
          badge: unread,
          items: const [LgMenuItem(label: '文字聊天', onPressed: null)],
        ),
        menuItem: LgSubmenu(
          label: '聊天',
          icon: LgIcons.chat,
          badge: unread,
          items: const [LgMenuItem(label: '文字聊天', onPressed: null)],
        ),
      ),
    ],
    [
      LgToolbarFoldable(
        inline: LgToolbarButton(
          icon: LgIcons.record,
          label: '录制',
          onPressed: () => log?.add('record'),
        ),
        menuItem: LgMenuItem(
          label: '录制',
          icon: LgIcons.record,
          onPressed: () => log?.add('record from menu'),
        ),
      ),
      LgToolbarRouteButton(
        route: LgRoute.direct,
        label: '直连',
        onPressed: () => log?.add('route'),
      ),
    ],
    [
      LgToolbarButton(
        icon: LgIcons.power,
        label: '断开',
        danger: true,
        onPressed: () => log?.add('disconnect'),
      ),
    ],
  ],
);

Widget _placed(
  Widget bar, {
  LgToolbarPlacement placement = const LgToolbarPlacement(LgToolbarDock.top),
  bool anyEdge = true,
  ValueChanged<LgToolbarPlacement>? onMove,
  ValueChanged<LgToolbarPlacement>? onMoveEnd,
}) => LgToolbarPlacer(
  placement: placement,
  anyEdge: anyEdge,
  onMove: onMove,
  onMoveEnd: onMoveEnd,
  child: bar,
);

Finder _grip() => find.byType(LgToolbarGrip);

void main() {
  group('the grip', () {
    testWidgets('only a bar in a placer has one', (tester) async {
      await _stage(
        tester,
        Align(alignment: Alignment.topCenter, child: _bar()),
      );
      expect(find.bySemanticsLabel('移动工具栏'), findsNothing);
      await _stage(tester, _placed(_bar()));
      expect(find.byIcon(Icons.abc), findsNothing);
      expect(
        find.descendant(of: _grip(), matching: find.byType(LgIcon)),
        findsOneWidget,
      );
    });

    testWidgets('dragging reports the nearest edge and the share along it', (
      tester,
    ) async {
      final moves = <LgToolbarPlacement>[];
      final ends = <LgToolbarPlacement>[];
      await _stage(
        tester,
        _placed(_bar(), onMove: moves.add, onMoveEnd: ends.add),
      );
      final from = tester.getCenter(_grip());
      final gesture = await tester.startGesture(from);
      await gesture.moveBy(const Offset(-30, 0)); // past the touch slop
      await tester.pump();
      await gesture.moveTo(const Offset(30, 300));
      await tester.pump();
      expect(moves.last.dock, LgToolbarDock.left);
      expect(moves.last.position, closeTo(.5, .06));
      await gesture.moveTo(const Offset(500, 570));
      await tester.pump();
      expect(moves.last.dock, LgToolbarDock.bottom);
      await gesture.up();
      await tester.pump();
      expect(ends, hasLength(1));
      expect(ends.single.dock, LgToolbarDock.bottom);
    });

    testWidgets('without anyEdge the bar slides along its own edge', (
      tester,
    ) async {
      final ends = <LgToolbarPlacement>[];
      await _stage(
        tester,
        _placed(_bar(), anyEdge: false, onMoveEnd: ends.add),
      );
      final from = tester.getCenter(_grip());
      await tester.dragFrom(from, const Offset(-200, 400));
      await tester.pump();
      expect(ends.single.dock, LgToolbarDock.top);
      expect(ends.single.position, lessThan(.5));
    });

    testWidgets('a drag does not jump the bar by half its width', (
      tester,
    ) async {
      final moves = <LgToolbarPlacement>[];
      await _stage(tester, _placed(_bar(), anyEdge: false, onMove: moves.add));
      final from = tester.getCenter(_grip());
      final gesture = await tester.startGesture(from);
      await gesture.moveBy(const Offset(30, 0)); // past the touch slop
      await tester.pump();
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      await gesture.up();
      // 50 px on a 1000 px wide stage after the drag began: about five
      // hundredths further, not a jump by where the grip sits in the bar.
      expect(moves.last.position, closeTo(.55, .04));
    });

    testWidgets('arrow keys on the grip move the bar a step', (tester) async {
      final ends = <LgToolbarPlacement>[];
      await _stage(tester, _placed(_bar(), onMoveEnd: ends.add));
      tester
          .widget<FocusableActionDetector>(
            find.descendant(
              of: _grip(),
              matching: find.byType(FocusableActionDetector),
            ),
          )
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(ends.map((e) => e.position), [
        closeTo(.55, .001),
        closeTo(.45, .001),
      ]);
    });

    testWidgets('the grip has its name', (tester) async {
      final handle = tester.ensureSemantics();
      await _stage(tester, _placed(_bar()));
      expect(find.bySemanticsLabel('移动工具栏'), findsOneWidget);
      handle.dispose();
    });
  });

  group('docking', () {
    Future<Rect> barAt(WidgetTester tester, LgToolbarPlacement place) async {
      await _stage(tester, _placed(_bar(dock: place.dock), placement: place));
      return tester.getRect(find.byType(LgSessionToolbar));
    }

    testWidgets('the bar hangs on its edge, 12 px from it', (tester) async {
      final top = await barAt(
        tester,
        const LgToolbarPlacement(LgToolbarDock.top),
      );
      expect(top.top, 0);
      final bottom = await barAt(
        tester,
        const LgToolbarPlacement(LgToolbarDock.bottom),
      );
      expect(bottom.bottom, 600);
      final left = await barAt(
        tester,
        const LgToolbarPlacement(LgToolbarDock.left),
      );
      expect(left.left, 0);
      final right = await barAt(
        tester,
        const LgToolbarPlacement(LgToolbarDock.right),
      );
      expect(right.right, 1000);
    });

    testWidgets('the share along the edge puts the middle of the bar there', (
      tester,
    ) async {
      final r = await barAt(
        tester,
        const LgToolbarPlacement(LgToolbarDock.top, 0),
      );
      expect(r.left, 12);
      final mid = await barAt(
        tester,
        const LgToolbarPlacement(LgToolbarDock.top, .5),
      );
      expect(mid.center.dx, closeTo(500, 1));
      final end = await barAt(
        tester,
        const LgToolbarPlacement(LgToolbarDock.top, 1),
      );
      expect(end.right, 988);
    });

    testWidgets('a bar at a side runs up and down with icons only', (
      tester,
    ) async {
      await _stage(
        tester,
        _placed(
          _bar(dock: LgToolbarDock.left),
          placement: const LgToolbarPlacement(LgToolbarDock.left),
        ),
      );
      final r = tester.getRect(find.byType(LgSessionToolbar));
      expect(r.height, greaterThan(r.width * 3));
      expect(find.text('画面'), findsNothing);
      expect(find.text('直连'), findsNothing);
    });

    testWidgets('a menu of a bar at the left opens beside it', (tester) async {
      await _stage(
        tester,
        _placed(
          _bar(dock: LgToolbarDock.left),
          placement: const LgToolbarPlacement(LgToolbarDock.left, .2),
        ),
      );
      await tester.tap(find.bySemanticsLabel('画面'));
      await tester.pumpAndSettle();
      final button = tester.getRect(find.bySemanticsLabel('画面'));
      final item = tester.getRect(find.text('适应窗口'));
      expect(item.left, greaterThan(button.right));
    });

    testWidgets('a menu of a bar at the right opens on its left side', (
      tester,
    ) async {
      await _stage(
        tester,
        _placed(
          _bar(dock: LgToolbarDock.right),
          placement: const LgToolbarPlacement(LgToolbarDock.right, .2),
        ),
      );
      await tester.tap(find.bySemanticsLabel('画面'));
      await tester.pumpAndSettle();
      final button = tester.getRect(find.bySemanticsLabel('画面'));
      final item = tester.getRect(find.text('适应窗口'));
      expect(item.right, lessThan(button.left));
    });

    testWidgets('a menu of a bar at the bottom opens over it', (tester) async {
      await _stage(
        tester,
        _placed(
          _bar(dock: LgToolbarDock.bottom),
          placement: const LgToolbarPlacement(LgToolbarDock.bottom),
        ),
      );
      await tester.tap(find.text('画面'));
      await tester.pumpAndSettle();
      final button = tester.getRect(find.text('画面'));
      final item = tester.getRect(find.text('适应窗口'));
      expect(item.bottom, lessThan(button.top));
    });

    testWidgets('a folded bar hangs on every edge', (tester) async {
      for (final dock in LgToolbarDock.values) {
        await _stage(
          tester,
          _placed(
            _bar(dock: dock, collapsed: true),
            placement: LgToolbarPlacement(dock),
          ),
        );
        expect(tester.takeException(), isNull, reason: dock.name);
        // Grip, dot, the display switch, full screen and unfold.
        expect(find.text('2/3'), findsOneWidget, reason: dock.name);
        final bar = tester.getRect(find.byType(LgSessionToolbar));
        switch (dock) {
          case LgToolbarDock.top:
            expect(bar.top, 0);
          case LgToolbarDock.bottom:
            expect(bar.bottom, 600);
          case LgToolbarDock.left:
            expect(bar.left, 0);
          case LgToolbarDock.right:
            expect(bar.right, 1000);
        }
      }
    });

    testWidgets('the unfold button points away from the edge', (tester) async {
      Future<LgIcons> unfold(LgToolbarDock dock) async {
        await _stage(
          tester,
          _placed(
            _bar(dock: dock, collapsed: true),
            placement: LgToolbarPlacement(dock),
          ),
        );
        return tester
            .widget<LgToolbarButton>(
              find.byWidgetPredicate(
                (w) => w is LgToolbarButton && w.label == '展开工具栏',
              ),
            )
            .icon;
      }

      expect(await unfold(LgToolbarDock.top), LgIcons.chevD);
      expect(await unfold(LgToolbarDock.bottom), LgIcons.chevU);
      expect(await unfold(LgToolbarDock.left), LgIcons.chevR);
      expect(await unfold(LgToolbarDock.right), LgIcons.chevL);
    });

    testWidgets('the ghost of a preview is drawn at the other edge', (
      tester,
    ) async {
      await _stage(
        tester,
        LgToolbarPlacer(
          placement: const LgToolbarPlacement(LgToolbarDock.top),
          preview: const LgToolbarPlacement(LgToolbarDock.left, .5),
          child: _bar(),
        ),
      );
      expect(tester.takeException(), isNull);
      // The ghost is the size the placer assumes for a bar at a side, 12 px
      // in from the left edge.
      final ghost = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints ==
                const BoxConstraints.tightFor(width: 60, height: 360),
      );
      expect(ghost, findsOneWidget);
      expect(tester.getRect(ghost).left, 12);
    });
  });

  group('folding into "更多"', () {
    // The menu is in the overlay, after the bar in the tree; a folded button
    // is still in the bar, laid out but not drawn.
    Finder inMenu(String text) => find.text(text).last;

    Future<double> natural(WidgetTester tester) async {
      await _stage(
        tester,
        Align(alignment: Alignment.topLeft, child: _bar()),
        size: const Size(2000, 400),
      );
      return tester.getSize(find.byType(LgSessionToolbar)).width;
    }

    Future<void> atWidth(WidgetTester tester, double w, {int unread = 1}) =>
        _stage(
          tester,
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: w,
              child: _bar(unread: unread),
            ),
          ),
          size: const Size(2000, 400),
        );

    testWidgets('nothing folds while everything fits', (tester) async {
      final w = await natural(tester);
      await atWidth(tester, w + 20);
      await tester.pump();
      expect(find.bySemanticsLabel('更多'), findsNothing);
      expect(find.text('录制'), findsNothing); // an icon button: only a tooltip
      expect(find.bySemanticsLabel('录制'), findsOneWidget);
    });

    testWidgets('the last foldable goes first, the rest stay', (tester) async {
      final handle = tester.ensureSemantics();
      final w = await natural(tester);
      await atWidth(tester, w - 30);
      await tester.pump();
      expect(find.bySemanticsLabel('更多'), findsOneWidget);
      expect(find.bySemanticsLabel('录制'), findsNothing);
      expect(find.text('会话'), findsOneWidget); // the first one stays
      await tester.tap(find.bySemanticsLabel('更多'));
      await tester.pumpAndSettle();
      expect(find.text('录制'), findsOneWidget);
      expect(find.text('会话'), findsOneWidget); // still only the bar's
      handle.dispose();
    });

    testWidgets('a narrower bar folds more, in the order of the row', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final w = await natural(tester);
      await atWidth(tester, w - 190);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('更多'));
      await tester.pumpAndSettle();
      // 聊天 and 录制 folded; the menu lists them in the order of the bar.
      final chat = tester.getTopLeft(inMenu('聊天')).dy;
      final record = tester.getTopLeft(inMenu('录制')).dy;
      expect(chat, lessThan(record));
      handle.dispose();
    });

    testWidgets('a folded button is out of the Tab order and the semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final w = await natural(tester);
      await atWidth(tester, w - 30);
      await tester.pump();
      await tester.pump();
      expect(find.bySemanticsLabel('录制'), findsNothing);
      final record = find.byWidgetPredicate(
        (w) => w is LgToolbarButton && w.label == '录制',
        skipOffstage: false,
      );
      final scope = tester
          .widgetList<ExcludeFocus>(
            find.ancestor(of: record, matching: find.byType(ExcludeFocus)),
          )
          .any((e) => e.excluding);
      expect(scope, isTrue);
      handle.dispose();
    });

    testWidgets('the unread count of a folded chat shows on "更多"', (
      tester,
    ) async {
      final w = await natural(tester);
      await atWidth(tester, w + 20, unread: 3);
      await tester.pump();
      // The count on the chat button itself.
      final whole = find.text('3').evaluate().length;
      expect(whole, 1);
      await atWidth(tester, w - 190, unread: 3);
      await tester.pump();
      await tester.pump();
      // The hidden chat button keeps its count; "更多" shows one of its own.
      expect(find.text('3').evaluate().length, 2);
    });

    testWidgets('a folded item runs from the "更多" menu', (tester) async {
      final log = <String>[];
      await _stage(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 560, child: _bar(log: log)),
        ),
        size: const Size(2000, 400),
      );
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('录制'));
      await tester.pumpAndSettle();
      expect(log, ['record from menu']);
    });

    testWidgets('a bar with nothing foldable scales instead', (tester) async {
      await _stage(
        tester,
        SizedBox(
          width: 300,
          child: LgSessionToolbar(
            labels: _labels,
            groups: const [
              [
                LgToolbarMenuButton(
                  label: '画面',
                  icon: LgIcons.image,
                  items: [],
                ),
              ],
            ],
            pinned: true,
            onTogglePin: () {},
            collapsed: false,
            onToggleCollapsed: () {},
            fullscreen: false,
            onToggleFullscreen: () {},
          ),
        ),
        size: const Size(300, 200),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tall stage keeps a bar at a side whole', (tester) async {
      await _stage(
        tester,
        _placed(
          _bar(dock: LgToolbarDock.left),
          placement: const LgToolbarPlacement(LgToolbarDock.left),
        ),
        size: const Size(800, 900),
      );
      expect(find.bySemanticsLabel('更多'), findsNothing);
      await _stage(
        tester,
        _placed(
          _bar(dock: LgToolbarDock.left),
          placement: const LgToolbarPlacement(LgToolbarDock.left),
        ),
        size: const Size(800, 300),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('the buttons of the bar', () {
    testWidgets('the route button runs and names the route', (tester) async {
      final handle = tester.ensureSemantics();
      final log = <String>[];
      await _stage(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: _bar(log: log),
        ),
      );
      await tester.tap(find.bySemanticsLabel('直连'));
      expect(log, ['route']);
      handle.dispose();
    });

    testWidgets('a call in progress shows in the button itself', (
      tester,
    ) async {
      await _stage(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: _bar(chat: LgToolbarMenuState.pending),
        ),
      );
      expect(find.text('等待接听…'), findsOneWidget);
      expect(find.byType(LgSpinner), findsOneWidget);
    });

    testWidgets('a call that is on shows its words and no spinner', (
      tester,
    ) async {
      await _stage(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: _bar(chat: LgToolbarMenuState.live),
        ),
      );
      expect(find.text('通话中'), findsOneWidget);
      expect(find.byType(LgSpinner), findsNothing);
    });

    testWidgets('the display number buttons pick and show the current', (
      tester,
    ) async {
      final log = <String>[];
      await pumpLg(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LgToolbarTextButton(
              label: '1',
              semanticLabel: '显示器 1',
              selected: true,
              onPressed: () => log.add('1'),
            ),
            LgToolbarTextButton(
              label: '2',
              semanticLabel: '显示器 2',
              onPressed: () => log.add('2'),
            ),
          ],
        ),
      );
      await tester.tap(find.text('2'));
      expect(log, ['2']);
    });

    testWidgets('the switch button of the folded bar has a spoken name', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final log = <String>[];
      await _stage(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: _bar(collapsed: true, log: log),
        ),
      );
      await tester.tap(find.bySemanticsLabel('切换显示器，当前第 2 个，共 3 个'));
      expect(log, ['switch display']);
      expect(find.text('2/3'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the bar tells its parts apart to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _stage(tester, _placed(_bar()));
      for (final label in ['固定工具栏', '画面', '断开', '全屏', '收起工具栏', '移动工具栏']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      handle.dispose();
    });
  });

  group('moving the bar to another edge', () {
    final recordButton = find.byWidgetPredicate(
      (w) => w is LgToolbarButton && w.label == '录制',
      skipOffstage: false,
    );

    Future<void> narrow(WidgetTester tester, LgToolbarDock dock) => _stage(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 560, child: _bar(dock: dock)),
      ),
      size: const Size(2000, 400),
    );

    testWidgets('keeps "更多" and the Tab order in step with what is folded', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await narrow(tester, LgToolbarDock.top);
      await tester.pump();
      await tester.pump();
      expect(find.bySemanticsLabel('更多'), findsOneWidget);
      // The same number folds on the other edge, so the row has nothing new
      // to report, but the bar has dropped its count on the move.
      await narrow(tester, LgToolbarDock.bottom);
      await tester.pump();
      await tester.pump();
      expect(find.bySemanticsLabel('更多'), findsOneWidget);
      expect(
        tester
            .widgetList<ExcludeFocus>(
              find.ancestor(
                of: recordButton,
                matching: find.byType(ExcludeFocus),
              ),
            )
            .any((e) => e.excluding),
        isTrue,
      );
      await tester.tap(find.bySemanticsLabel('更多'));
      await tester.pumpAndSettle();
      expect(find.text('录制'), findsOneWidget); // the menu is not empty
      handle.dispose();
    });

    testWidgets('and back to the first edge', (tester) async {
      final handle = tester.ensureSemantics();
      await narrow(tester, LgToolbarDock.top);
      await tester.pump();
      await narrow(tester, LgToolbarDock.bottom);
      await tester.pump();
      await tester.pump();
      await narrow(tester, LgToolbarDock.top);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('更多'));
      await tester.pumpAndSettle();
      expect(find.text('录制'), findsOneWidget);
      handle.dispose();
    });
  });

  group('the unread count on a bar at a side', () {
    final chat = find.byWidgetPredicate(
      (w) => w is LgToolbarMenuButton && w.label == '聊天',
    );

    testWidgets('sits on the corner of the chat icon', (tester) async {
      await _stage(
        tester,
        _placed(
          _bar(dock: LgToolbarDock.left, unread: 3),
          placement: const LgToolbarPlacement(LgToolbarDock.left),
        ),
        size: const Size(800, 900),
      );
      expect(find.text('3'), findsOneWidget);
      final button = tester.getRect(chat);
      final badge = tester.getRect(find.text('3'));
      expect(badge.center.dx, greaterThan(button.center.dx));
      expect(badge.center.dy, lessThan(button.center.dy));
      expect(button.overlaps(badge), isTrue);
    });

    testWidgets('a folded chat shows it on "更多"', (tester) async {
      await _stage(
        tester,
        _placed(
          _bar(dock: LgToolbarDock.left, unread: 3),
          placement: const LgToolbarPlacement(LgToolbarDock.left),
        ),
        size: const Size(800, 300),
      );
      await tester.pump();
      await tester.pump();
      // The hidden chat button keeps its own count; "更多" shows one too.
      expect(find.text('3').evaluate().length, 2);
    });
  });

  group('a menu button that is greyed', () {
    LgToolbarMenuButton button({String? note}) => LgToolbarMenuButton(
      label: '输入',
      icon: LgIcons.sliders,
      enabled: false,
      disabledNote: note,
      items: [
        LgMenuItem(
          label: '映射',
          checked: true,
          onPressed: null,
          disabledNote: note,
        ),
      ],
    );

    testWidgets('with a note it still opens', (tester) async {
      await _stage(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: button(note: '未获得键盘和鼠标控制权限'),
        ),
      );
      await tester.tap(find.text('输入'));
      await tester.pumpAndSettle();
      expect(find.text('映射'), findsOneWidget);
    });

    testWidgets('it is dimmed and says why on hover and to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _stage(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: button(note: '未获得键盘和鼠标控制权限'),
        ),
      );
      expect(
        find.ancestor(
          of: find.text('输入'),
          matching: find.byWidgetPredicate(
            (w) => w is Opacity && w.opacity < 1,
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.text('输入')).hint,
        contains('未获得键盘和鼠标控制权限'),
      );
      await hover(tester, find.text('输入'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('未获得键盘和鼠标控制权限'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('without a note it stays shut, as before', (tester) async {
      await _stage(
        tester,
        Align(alignment: Alignment.topCenter, child: button()),
      );
      await tester.tap(find.text('输入'));
      await tester.pumpAndSettle();
      expect(find.text('映射'), findsNothing);
    });
  });

  group('the note of a greyed row in the bar\'s menu', () {
    Future<(Rect row, Rect tip)> open(
      WidgetTester tester,
      Widget bar, {
      LgToolbarPlacement? at,
    }) async {
      await _stage(
        tester,
        at == null
            ? Align(alignment: Alignment.topCenter, child: bar)
            : _placed(bar, placement: at),
      );
      await tester.tap(
        find.text('画面').evaluate().isNotEmpty
            ? find.text('画面')
            : find.byWidgetPredicate(
                (w) => w is LgToolbarMenuButton && w.label == '画面',
              ),
      );
      await tester.pumpAndSettle();
      await hover(tester, find.text('原始大小'));
      await tester.pump(const Duration(seconds: 1));
      return (
        tester.getRect(find.byType(MenuItemButton).at(1)),
        tester.getRect(find.byType(LgTooltipBox)),
      );
    }

    testWidgets('opens on the right of the menu, level with the row', (
      tester,
    ) async {
      final (row, tip) = await open(tester, _bar(note: '无权限'));
      expect(tip.left, row.right + 8);
      expect(tip.top, row.top);
    });

    testWidgets('opens on the left when a notice sits at the right', (
      tester,
    ) async {
      final (row, tip) = await open(
        tester,
        _bar(note: '无权限', noteSide: LgNoteSide.left),
      );
      expect(tip.right, row.left - 8);
    });

    testWidgets('a bar on the right edge puts it on the left by itself', (
      tester,
    ) async {
      final (row, tip) = await open(
        tester,
        _bar(note: '无权限', dock: LgToolbarDock.right),
        at: const LgToolbarPlacement(LgToolbarDock.right, .1),
      );
      expect(tip.right, row.left - 8);
    });
  });

  group('the grip for a screen reader', () {
    testWidgets('"increase" and "decrease" move the bar a step', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final ends = <LgToolbarPlacement>[];
      await _stage(tester, _placed(_bar(), onMoveEnd: ends.add));
      tester.semantics.performAction(
        find.semantics.byLabel('移动工具栏'),
        SemanticsAction.increase,
      );
      tester.semantics.performAction(
        find.semantics.byLabel('移动工具栏'),
        SemanticsAction.decrease,
      );
      expect(ends.map((e) => e.position), [
        closeTo(.55, .001),
        closeTo(.45, .001),
      ]);
      handle.dispose();
    });
  });

  group('the labels of a bar with foldable buttons', () {
    LgSessionToolbar bare(LgToolbarLabels labels) => LgSessionToolbar(
      labels: labels,
      pinned: true,
      onTogglePin: () {},
      collapsed: false,
      onToggleCollapsed: () {},
      fullscreen: false,
      onToggleFullscreen: () {},
      groups: const [
        [
          LgToolbarFoldable(
            inline: LgToolbarButton(
              icon: LgIcons.record,
              label: '录制',
              onPressed: null,
            ),
            menuItem: LgMenuItem(label: '录制', onPressed: null),
          ),
        ],
      ],
    );

    testWidgets('must name "更多" and the grip', (tester) async {
      await _stage(
        tester,
        bare(
          const LgToolbarLabels(
            toolbar: '会话工具栏',
            pin: '固定工具栏',
            fullscreen: '全屏',
            exitFullscreen: '退出全屏',
            minimize: '最小化',
            collapse: '收起工具栏',
            expand: '展开工具栏',
          ),
        ),
      );
      expect(tester.takeException(), isA<AssertionError>());
    });

    testWidgets('with both given it builds', (tester) async {
      await _stage(tester, bare(_labels));
      expect(tester.takeException(), isNull);
    });
  });
}
