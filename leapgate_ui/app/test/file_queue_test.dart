// Behaviour of the transfer queue's panel and rows (docs LEAPGATE.md §10.15): the summary line,
// folding, the grip, every state of a row with its icon and its buttons, the list under a row,
// and the two layouts of a row. No pixels.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/widgets/lg_file_queue.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';

import 'helpers.dart';

/// The panel decides on its own width: the tests give it a window as wide as the real one.
Future<void> _pump(WidgetTester tester, Widget child) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return pumpLg(tester, child);
}

Finder _icon(LgIcons icon) =>
    find.byWidgetPredicate((w) => w is LgIcon && w.icon == icon);

LgQueueRow _row({
  LgQueueState state = LgQueueState.inProgress,
  String name = '照片',
  String status = '610 MB / 1.32 GB',
  String? lead = '45%',
  double? progress = .45,
  List<LgQueueAction> actions = const [],
  String? detailsLabel,
  bool detailsOpen = false,
  VoidCallback? onToggleDetails,
  List<LgQueueDetail> details = const [],
}) => LgQueueRow(
  direction: LgQueueDirection.download,
  directionLabel: '下载',
  name: name,
  path: r'D:\备份\照片 → C:\Users\zhangsan\Pictures',
  state: state,
  status: status,
  statusLead: lead,
  progress: progress,
  actions: actions,
  detailsLabel: detailsLabel,
  detailsOpen: detailsOpen,
  onToggleDetails: onToggleDetails,
  details: details,
);

Widget _rowIn(LgQueueRow row, {double width = 1240}) =>
    SizedBox(width: width, child: row);

LgQueuePanel _panel({
  bool expanded = true,
  VoidCallback? onToggle,
  List<LgQueueSpan> spans = const [LgQueueSpan('1 个进行中')],
  double? progress = .45,
  String? percent = '45%',
  String? emptyText,
  List<LgQueueSummaryAction> actions = const [],
  List<Widget> rows = const [],
  ValueChanged<double>? onResize,
}) => LgQueuePanel(
  title: '传输',
  spans: spans,
  progress: progress,
  percentText: percent,
  emptyText: emptyText,
  expanded: expanded,
  toggleLabel: expanded ? '收起' : '展开',
  onToggle: onToggle,
  actions: actions,
  rows: rows,
  onResize: onResize,
  resizeLabel: '调整传输面板的高度',
);

Widget _sized(Widget panel, {double width = 1240, double height = 300}) =>
    SizedBox(width: width, height: height, child: panel);

void main() {
  group('summary', () {
    testWidgets('title, count and the progress of all of it', (tester) async {
      await _pump(tester, _sized(_panel(), height: 60));
      expect(find.text('传输'), findsOneWidget);
      expect(find.text('1 个进行中'), findsOneWidget);
      expect(find.text('45%'), findsOneWidget);
      expect(find.byType(LgQueueBar), findsOneWidget);
    });

    testWidgets('the error and the warning pieces are bold in their colours', (
      tester,
    ) async {
      await _pump(
        tester,
        _sized(
          _panel(
            spans: const [
              LgQueueSpan('3 个进行中，'),
              LgQueueSpan('1 个失败', tone: LgQueueTone.error),
              LgQueueSpan('，'),
              LgQueueSpan('1 个等待确认', tone: LgQueueTone.warning),
            ],
          ),
          height: 60,
        ),
      );
      final text = tester.widget<RichText>(
        find.textContaining('1 个失败', findRichText: true),
      );
      final spans = <InlineSpan>[];
      text.text.visitChildren((s) {
        spans.add(s);
        return true;
      });
      TextStyle? style(String s) =>
          spans.whereType<TextSpan>().firstWhere((e) => e.text == s).style;
      expect(style('1 个失败')!.fontWeight, FontWeight.w700);
      expect(style('1 个等待确认')!.fontWeight, FontWeight.w700);
      expect(style('1 个失败')!.color, isNot(style('1 个等待确认')!.color));
      expect(style('3 个进行中，'), isNull);
    });

    testWidgets('no bar when nothing has a size', (tester) async {
      await _pump(
        tester,
        _sized(_panel(progress: null, percent: null), height: 60),
      );
      expect(find.byType(LgQueueBar), findsNothing);
    });

    testWidgets(
      'the buttons call their callbacks; folding asks to be toggled',
      (tester) async {
        final log = <String>[];
        await _pump(
          tester,
          _sized(
            _panel(
              expanded: false,
              onToggle: () => log.add('toggle'),
              actions: [
                LgQueueSummaryAction(
                  label: '全部继续',
                  icon: LgIcons.play,
                  onPressed: () => log.add('all'),
                ),
                LgQueueSummaryAction(
                  label: '清除已完成',
                  onPressed: () => log.add('clear'),
                ),
              ],
            ),
            height: 60,
          ),
        );
        await tester.tap(find.text('全部继续'));
        await tester.tap(find.text('清除已完成'));
        await tester.tap(find.text('展开'));
        expect(log, ['all', 'clear', 'toggle']);
      },
    );

    testWidgets('the fold button stands at the right end', (tester) async {
      await _pump(
        tester,
        _sized(_panel(expanded: false, onToggle: () {}), height: 60),
      );
      final panel = tester.getRect(find.byType(LgQueuePanel));
      final button = tester.getRect(find.text('展开'));
      // The panel's 8 and the button's 12 of padding stand between the word and the edge.
      expect(button.right, greaterThan(panel.right - 48));
    });

    testWidgets('an empty queue says so and has no fold button', (
      tester,
    ) async {
      await _pump(
        tester,
        _sized(
          _panel(
            emptyText: '暂无传输任务',
            expanded: false,
            onToggle: () {},
            spans: const [],
          ),
          height: 60,
        ),
      );
      expect(find.text('暂无传输任务'), findsOneWidget);
      expect(find.text('展开'), findsNothing);
      expect(find.byType(LgQueueBar), findsNothing);
    });

    testWidgets('the summary is a live region', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _sized(_panel(), height: 60));
      var live = false;
      void visit(SemanticsNode n) {
        if (n.getSemanticsData().flagsCollection.isLiveRegion) live = true;
        n.visitChildren((c) {
          visit(c);
          return true;
        });
      }

      visit(tester.getSemantics(find.byType(LgQueuePanel)));
      expect(live, isTrue);
      handle.dispose();
    });
  });

  group('panel', () {
    testWidgets('folded shows the summary and no rows', (tester) async {
      await _pump(
        tester,
        _sized(
          _panel(expanded: false, onToggle: () {}, rows: [_row()]),
          height: 60,
        ),
      );
      expect(find.text('照片'), findsNothing);
    });

    testWidgets('open shows the rows, scrolling when they do not fit', (
      tester,
    ) async {
      await _pump(
        tester,
        _sized(
          _panel(
            onToggle: () {},
            rows: [for (var i = 0; i < 12; i++) _row(name: '文件$i')],
          ),
          height: 200,
        ),
      );
      expect(find.text('文件0'), findsOneWidget);
      expect(find.text('文件11'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      expect(find.text('文件11'), findsOneWidget);
    });

    testWidgets(
      'the grip reports the drag, positive downwards, and only while open',
      (tester) async {
        final log = <double>[];
        await _pump(
          tester,
          _sized(_panel(onToggle: () {}, rows: [_row()], onResize: log.add)),
        );
        final top = tester.getTopLeft(find.byType(LgQueuePanel));
        await tester.dragFrom(
          Offset(top.dx + 400, top.dy + 4),
          const Offset(0, -40),
        );
        expect(log, isNotEmpty);
        expect(log.fold<double>(0, (s, e) => s + e), lessThan(0));
        log.clear();
        await _pump(
          tester,
          _sized(
            _panel(expanded: false, onToggle: () {}, onResize: log.add),
            height: 60,
          ),
        );
        final t2 = tester.getTopLeft(find.byType(LgQueuePanel));
        await tester.dragFrom(
          Offset(t2.dx + 400, t2.dy + 4),
          const Offset(0, -40),
        );
        expect(log, isEmpty);
      },
    );

    testWidgets('the grip is named', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        _sized(_panel(onToggle: () {}, rows: [_row()], onResize: (_) {})),
      );
      expect(find.bySemanticsLabel('调整传输面板的高度'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a row is separated from the one above it', (tester) async {
      await _pump(
        tester,
        _sized(
          _panel(
            onToggle: () {},
            rows: [
              _row(name: 'a'),
              _row(name: 'b'),
            ],
          ),
        ),
      );
      final a = tester.getRect(find.text('a'));
      final b = tester.getRect(find.text('b'));
      expect(b.top, greaterThan(a.bottom));
    });
  });

  group('row states', () {
    for (final (state, icon) in <(LgQueueState, LgIcons?)>[
      (LgQueueState.queued, null),
      (LgQueueState.waitingConfirm, LgIcons.warn),
      (LgQueueState.interrupted, LgIcons.wifiOff),
      (LgQueueState.done, LgIcons.checkCircle),
      (LgQueueState.doneWithIssues, LgIcons.warn),
      (LgQueueState.skipped, null),
      (LgQueueState.cancelled, LgIcons.ban),
      (LgQueueState.failed, LgIcons.err),
    ]) {
      testWidgets('${state.name} shows its icon, if it has one', (
        tester,
      ) async {
        await _pump(
          tester,
          _rowIn(
            _row(state: state, lead: null, progress: null, status: '状态文字'),
          ),
        );
        for (final i in [
          LgIcons.warn,
          LgIcons.wifiOff,
          LgIcons.checkCircle,
          LgIcons.ban,
          LgIcons.err,
        ]) {
          expect(
            _icon(i),
            i == icon ? findsOneWidget : findsNothing,
            reason: '${state.name} $i',
          );
        }
        expect(find.text('状态文字'), findsOneWidget);
        expect(find.byType(LgQueueBar), findsNothing);
      });
    }

    testWidgets('counting turns an arc', (tester) async {
      await _pump(
        tester,
        _rowIn(_row(state: LgQueueState.counting, lead: null, progress: null)),
      );
      expect(find.byType(LgSpinner), findsOneWidget);
    });

    testWidgets(
      'in progress, paused and deleting draw the bar; paused in the quiet colour',
      (tester) async {
        for (final s in [
          LgQueueState.inProgress,
          LgQueueState.paused,
          LgQueueState.deleting,
        ]) {
          await _pump(tester, _rowIn(_row(state: s)));
          expect(find.byType(LgQueueBar), findsOneWidget, reason: s.name);
        }
        await _pump(tester, _rowIn(_row(state: LgQueueState.paused)));
        expect(
          tester.widget<LgQueueBar>(find.byType(LgQueueBar)).paused,
          isTrue,
        );
        await _pump(tester, _rowIn(_row()));
        expect(
          tester.widget<LgQueueBar>(find.byType(LgQueueBar)).paused,
          isFalse,
        );
      },
    );

    testWidgets('a bar needs a size to draw', (tester) async {
      await _pump(tester, _rowIn(_row(progress: null)));
      expect(find.byType(LgQueueBar), findsNothing);
    });

    testWidgets('the lead of a transfer under way is bold, before the rest', (
      tester,
    ) async {
      await _pump(tester, _rowIn(_row()));
      final text = tester.widget<RichText>(
        find.textContaining('610 MB', findRichText: true),
      );
      final spans = <TextSpan>[];
      text.text.visitChildren((s) {
        if (s is TextSpan && s.text != null) spans.add(s);
        return true;
      });
      expect(
        [for (final s in spans) s.text],
        ['45%', ' · ', '610 MB / 1.32 GB'],
      );
      expect(spans.first.style!.fontWeight, FontWeight.w700);
      expect(spans.last.style, isNull);
    });

    testWidgets(
      'a failure is bold in the error colour, others in the ordinary one',
      (tester) async {
        await _pump(
          tester,
          _rowIn(
            _row(
              state: LgQueueState.failed,
              lead: null,
              progress: null,
              status: '失败：文件正被其他应用使用',
            ),
          ),
        );
        final failed = tester
            .widget<RichText>(find.textContaining('失败', findRichText: true))
            .text
            .style!;
        expect(failed.fontWeight, FontWeight.w700);
        await _pump(
          tester,
          _rowIn(
            _row(
              state: LgQueueState.done,
              lead: null,
              progress: null,
              status: '已完成',
            ),
          ),
        );
        final done = tester
            .widget<RichText>(find.textContaining('已完成', findRichText: true))
            .text
            .style!;
        expect(done.fontWeight, FontWeight.w400);
        expect(done.color, isNot(failed.color));
      },
    );

    testWidgets('the buttons at the end call back and carry names', (
      tester,
    ) async {
      final log = <String>[];
      await _pump(
        tester,
        _rowIn(
          _row(
            actions: [
              LgQueueAction(
                icon: LgIcons.pause,
                label: '暂停',
                onPressed: () => log.add('pause'),
              ),
              LgQueueAction(
                icon: LgIcons.x,
                label: '取消',
                onPressed: () => log.add('cancel'),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.byTooltip('暂停'));
      await tester.tap(find.byTooltip('取消'));
      expect(log, ['pause', 'cancel']);
    });

    testWidgets('a row says its direction, name and state to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        _rowIn(
          _row(
            actions: [
              LgQueueAction(icon: LgIcons.x, label: '取消', onPressed: () {}),
            ],
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(RegExp('下载 照片.*45%.*610 MB')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('取消'), findsOneWidget);
      handle.dispose();
    });
  });

  group('details', () {
    testWidgets(
      'the link shows on a finished-with-issues row only, and toggles the list',
      (tester) async {
        var toggles = 0;
        await _pump(
          tester,
          _rowIn(
            _row(
              state: LgQueueState.doneWithIssues,
              lead: null,
              progress: null,
              status: '已完成，2 个文件未传输',
              detailsLabel: '查看详情',
              onToggleDetails: () => toggles++,
            ),
          ),
        );
        await tester.tap(find.text('查看详情'));
        expect(toggles, 1);
        await _pump(tester, _rowIn(_row(detailsLabel: '查看详情')));
        expect(find.text('查看详情'), findsNothing);
      },
    );

    testWidgets(
      'open, the list shows the paths with the reasons in the error colour',
      (tester) async {
        await _pump(
          tester,
          _rowIn(
            _row(
              state: LgQueueState.doneWithIssues,
              lead: null,
              progress: null,
              status: '已完成，2 个文件未传输',
              detailsLabel: '查看详情',
              detailsOpen: true,
              onToggleDetails: () {},
              details: const [
                LgQueueDetail(r'项目资料\草稿.docx', reason: '没有访问权限'),
                LgQueueDetail('2 个空文件夹未创建'),
              ],
            ),
          ),
        );
        expect(
          find.textContaining('草稿.docx', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.textContaining('没有访问权限', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('2 个空文件夹未创建', findRichText: true), findsOneWidget);
        expect(_icon(LgIcons.chevU), findsOneWidget);
      },
    );

    testWidgets(
      'closed, no list; the link points down and says it is collapsed',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(
          tester,
          _rowIn(
            _row(
              state: LgQueueState.doneWithIssues,
              lead: null,
              progress: null,
              status: '已完成，2 个文件未传输',
              detailsLabel: '查看详情',
              onToggleDetails: () {},
              details: const [LgQueueDetail(r'项目资料\草稿.docx', reason: '没有访问权限')],
            ),
          ),
        );
        expect(
          find.textContaining('草稿.docx', findRichText: true),
          findsNothing,
        );
        expect(_icon(LgIcons.chevD), findsOneWidget);
        expect(find.bySemanticsLabel('查看详情'), findsOneWidget);
        handle.dispose();
      },
    );
  });

  group('layout', () {
    testWidgets(
      'a wide panel puts the path beside the name, a narrow one under it',
      (tester) async {
        await _pump(
          tester,
          _sized(
            _panel(onToggle: () {}, rows: [_row()]),
            width: 1240,
            height: 200,
          ),
        );
        final wideName = tester.getRect(find.text('照片'));
        final widePath = tester.getRect(find.textContaining(r'D:\备份\照片'));
        expect(widePath.left, greaterThan(wideName.right));
        await _pump(
          tester,
          _sized(
            _panel(onToggle: () {}, rows: [_row()]),
            width: 936,
            height: 200,
          ),
        );
        final name = tester.getRect(find.text('照片'));
        final path = tester.getRect(find.textContaining(r'D:\备份\照片'));
        expect(path.top, greaterThanOrEqualTo(name.bottom - 1));
      },
    );

    testWidgets('the summary is lower on a wide panel than on a narrow one', (
      tester,
    ) async {
      await _pump(
        tester,
        _sized(
          _panel(expanded: false, onToggle: () {}),
          width: 1240,
          height: 60,
        ),
      );
      final wide = tester.getSize(find.text('传输')).height;
      expect(wide, greaterThan(0));
      expect(tester.takeException(), isNull);
      await _pump(
        tester,
        _sized(
          _panel(expanded: false, onToggle: () {}),
          width: 936,
          height: 60,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('every state at the smallest window does not overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        _sized(
          _panel(
            onToggle: () {},
            actions: [
              LgQueueSummaryAction(
                label: '全部继续',
                icon: LgIcons.play,
                onPressed: () {},
              ),
              LgQueueSummaryAction(label: '清除已完成', onPressed: () {}),
            ],
            rows: [
              for (final s in LgQueueState.values)
                _row(
                  state: s,
                  lead: s == LgQueueState.inProgress ? '45%' : null,
                  progress:
                      s == LgQueueState.inProgress || s == LgQueueState.paused
                      ? .4
                      : null,
                  status: '一句比较长的状态说明，说明这一行现在是什么情况，放不下的时候不应该溢出',
                  actions: [
                    LgQueueAction(
                      icon: LgIcons.pause,
                      label: '暂停',
                      onPressed: () {},
                    ),
                    LgQueueAction(
                      icon: LgIcons.x,
                      label: '取消',
                      onPressed: () {},
                    ),
                  ],
                ),
            ],
          ),
          width: 936,
          height: 800,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
