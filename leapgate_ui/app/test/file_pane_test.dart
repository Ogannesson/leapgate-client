// Behaviour of the parts of a file pane (docs LEAPGATE.md §10.15): the header, the navigation row,
// the breadcrumb and the path input, the row of actions with its search, the status line, the
// "reading" state, the drag highlights. Callbacks are called, a greyed part does not answer, the
// right things show and hide, the names a screen reader gets are there. No pixels.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/widgets/lg_breadcrumb.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_device.dart';
import 'package:leapgate_ui/widgets/lg_file_pane.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';
import 'package:leapgate_ui/widgets/lg_text_field.dart';

import 'helpers.dart';

Finder _icon(LgIcons icon) =>
    find.byWidgetPredicate((w) => w is LgIcon && w.icon == icon);

Widget _crumb(
  List<String> segments, {
  double width = 600,
  List<Widget>? menu,
  VoidCallback? onRoot,
  ValueChanged<int>? onSegment,
  VoidCallback? onEdit,
}) => SizedBox(
  width: width,
  child: LgBreadcrumb(
    rootLabel: '此电脑',
    rootTip: '此电脑',
    segments: segments,
    rootMenu:
        menu ??
        const [LgMenuItem(label: 'C:', checked: true, onPressed: _noop)],
    onRoot: onRoot ?? () {},
    onSegment: onSegment ?? (_) {},
    onEdit: onEdit ?? () {},
  ),
);

void _noop() {}

void main() {
  group('header', () {
    testWidgets('the title, the device after it and the platform tile', (
      tester,
    ) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 600,
          child: LgFilePaneHeader(
            title: '远程设备',
            subtitle: '书房台式机 · Windows',
            platform: LgPlatform.windows,
            remoteId: '456 789 123',
          ),
        ),
      );
      expect(find.text('远程设备'), findsOneWidget);
      expect(find.text('书房台式机 · Windows'), findsOneWidget);
      expect(find.byType(LgDeviceAvatar), findsOneWidget);
    });

    testWidgets('the local pane has a neutral tile, not the identity avatar', (
      tester,
    ) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 600,
          child: LgFilePaneHeader(
            title: '本机',
            subtitle: 'LAPTOP-ZHANGSAN',
            platform: LgPlatform.windows,
          ),
        ),
      );
      expect(find.byType(LgDeviceAvatar), findsNothing);
      expect(_icon(LgIcons.windows), findsOneWidget);
    });

    testWidgets('no tile while the remote platform is not known', (
      tester,
    ) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 600,
          child: LgFilePaneHeader(
            title: '远程设备',
            subtitle: '',
            remoteId: '456 789 123',
          ),
        ),
      );
      expect(find.byType(LgDeviceAvatar), findsNothing);
      expect(find.byType(LgSpinner), findsNothing);
      expect(find.text('远程设备'), findsOneWidget);
    });

    testWidgets('a long device name is cut, not overflowed', (tester) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 300,
          child: LgFilePaneHeader(
            title: '远程设备',
            subtitle: '一个名字很长很长很长很长很长很长很长很长很长的设备 · Windows',
            platform: LgPlatform.windows,
            remoteId: '456 789 123',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('navigation row', () {
    LgFileNavRow row(List<String> log, {bool canGoUp = true}) => LgFileNavRow(
      back: LgFileNavButton(
        icon: LgIcons.arrowL,
        label: '后退',
        onPressed: () => log.add('back'),
      ),
      up: LgFileNavButton(
        icon: LgIcons.arrowU,
        label: '上一级',
        onPressed: canGoUp ? () => log.add('up') : null,
      ),
      home: LgFileNavButton(
        icon: LgIcons.home,
        label: '主文件夹',
        onPressed: () => log.add('home'),
      ),
      refresh: LgFileNavButton(
        icon: LgIcons.refresh,
        label: '刷新',
        onPressed: () => log.add('refresh'),
      ),
      path: const Text('路径'),
    );

    testWidgets('the four buttons call their callbacks', (tester) async {
      final log = <String>[];
      await pumpLg(tester, SizedBox(width: 600, child: row(log)));
      for (final name in ['后退', '上一级', '主文件夹', '刷新']) {
        await tester.tap(find.byTooltip(name));
      }
      expect(log, ['back', 'up', 'home', 'refresh']);
    });

    testWidgets('a button with no callback is greyed and does not answer', (
      tester,
    ) async {
      final log = <String>[];
      await pumpLg(
        tester,
        SizedBox(width: 600, child: row(log, canGoUp: false)),
      );
      await tester.tap(find.byTooltip('上一级'));
      expect(log, isEmpty);
    });

    testWidgets('the path takes the room between the buttons', (tester) async {
      await pumpLg(tester, SizedBox(width: 600, child: row([])));
      final path = tester.getRect(find.text('路径'));
      expect(path.left > tester.getRect(find.byTooltip('主文件夹')).right, isTrue);
      expect(path.right < tester.getRect(find.byTooltip('刷新')).left, isTrue);
    });
  });

  group('breadcrumb', () {
    List<String> shown(WidgetTester tester) => find
        .descendant(of: find.byType(LgBreadcrumb), matching: find.byType(Text))
        .evaluate()
        .map((e) => (e.widget as Text).data!)
        .toList();

    testWidgets('every folder but the last can be clicked', (tester) async {
      final log = <String>[];
      await pumpLg(
        tester,
        _crumb(
          ['C:', 'Users', 'Documents'],
          onRoot: () => log.add('root'),
          onSegment: (i) => log.add('seg $i'),
        ),
      );
      await tester.tap(find.text('此电脑'));
      await tester.tap(find.text('C:'));
      await tester.tap(find.text('Users'));
      expect(log, ['root', 'seg 0', 'seg 1']);
    });

    testWidgets(
      'the open folder is not a button, a click on it asks for the path',
      (tester) async {
        var edit = 0;
        final log = <String>[];
        await pumpLg(
          tester,
          _crumb(
            ['C:', 'Documents'],
            onSegment: (i) => log.add('seg $i'),
            onEdit: () => edit++,
          ),
        );
        await tester.tap(find.text('Documents'));
        expect(log, isEmpty);
        expect(edit, 1);
      },
    );

    testWidgets('a click past the last folder asks for the path', (
      tester,
    ) async {
      var edit = 0;
      await pumpLg(tester, _crumb(['C:', 'Documents'], onEdit: () => edit++));
      final box = tester.getRect(find.byType(LgBreadcrumb));
      await tester.tapAt(Offset(box.right - 10, box.center.dy));
      expect(edit, 1);
    });

    testWidgets('nothing folds while it fits', (tester) async {
      await pumpLg(tester, _crumb(['C:', 'Users', 'zhangsan', 'Documents']));
      expect(shown(tester), ['此电脑', 'C:', 'Users', 'zhangsan', 'Documents']);
    });

    testWidgets(
      'the middle folds into … and the root, the drive and the last stay',
      (tester) async {
        await pumpLg(
          tester,
          _crumb(['D:', '备份', '2026', '十月', '家庭', '照片', '原图'], width: 330),
        );
        final text = shown(tester);
        expect(text.first, '此电脑');
        expect(text, contains('D:'));
        expect(text, contains('…'));
        expect(text.last, '原图');
        expect(text, isNot(contains('备份')));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the tooltip of the … lists the folders that are folded', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _crumb(['D:', '备份', '2026', '十月', '家庭', '照片', '原图'], width: 330),
      );
      await hover(tester, find.text('…'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('备份 › 2026'), findsOneWidget);
    });

    testWidgets('narrower still, the drive folds too and the last is kept', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _crumb(['C:', 'Users', 'zhangsan', 'Documents', '工作文件夹'], width: 230),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('C:'), findsNothing);
      expect(
        find.byTooltip('C: › Users › zhangsan › Documents'),
        findsOneWidget,
      );
    });

    testWidgets('the root has a drop-down of its own that lists the drives', (
      tester,
    ) async {
      await pumpLg(tester, _crumb(['C:', 'Users']));
      await tester.tap(find.byTooltip('此电脑'));
      await tester.pumpAndSettle();
      expect(find.text('C:'), findsWidgets);
    });

    testWidgets('no arrow without rows for the drop-down', (tester) async {
      await pumpLg(tester, _crumb(['usr'], menu: const []));
      expect(find.byTooltip('此电脑'), findsNothing);
    });

    testWidgets('the root and its arrow are two buttons with names', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, _crumb(['C:', 'Users']));
      expect(find.bySemanticsLabel('此电脑'), findsNWidgets(2));
      handle.dispose();
    });
  });

  group('path input', () {
    testWidgets('Enter opens what was typed, Esc gives the breadcrumb back', (
      tester,
    ) async {
      final controller = TextEditingController(text: r'D:\备份');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      final log = <String>[];
      await pumpLg(
        tester,
        SizedBox(
          width: 500,
          child: LgPathInput(
            controller: controller,
            focusNode: focus,
            semanticLabel: '路径',
            onSubmitted: (s) => log.add('open $s'),
            onCancel: () => log.add('cancel'),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(log, ['cancel']);
      await tester.enterText(find.byType(TextField), r'D:\备份\2026');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(log, ['cancel', r'open D:\备份\2026']);
    });

    testWidgets(
      'the error is in a card under the field and in the field\'s name',
      (tester) async {
        final handle = tester.ensureSemantics();
        final controller = TextEditingController(text: r'D:\备份\2025');
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        Widget field(String? error) => SizedBox(
          width: 500,
          child: LgPathInput(
            controller: controller,
            focusNode: focus,
            semanticLabel: '路径',
            errorText: error,
            onSubmitted: (_) {},
            onCancel: () {},
          ),
        );
        await pumpLg(tester, field(null));
        await tester.pump();
        expect(find.byType(LgPathError), findsNothing);
        await pumpLg(tester, field(r'未找到“D:\备份\2025”。'));
        await tester.pump();
        await tester.pump();
        expect(find.byType(LgPathError), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp(r'路径[\s\S]*未找到')), findsOneWidget);
        await pumpLg(tester, field(null));
        await tester.pump();
        await tester.pump();
        expect(find.byType(LgPathError), findsNothing);
        handle.dispose();
      },
    );
  });

  group('row of actions', () {
    Widget row({
      required TextEditingController controller,
      required FocusNode focus,
      double width = 618,
      GlobalKey<LgFileOpRowState>? key,
      ValueChanged<String>? onChanged,
    }) => SizedBox(
      width: width,
      child: LgFileOpRow(
        key: key,
        actions: [
          LgButton(label: '上传', kind: LgButtonKind.primary, onPressed: () {}),
          LgButton(label: '新建文件夹', onPressed: () {}),
        ],
        searchController: controller,
        searchFocusNode: focus,
        searchPlaceholder: '搜索当前文件夹',
        searchClearLabel: '清除搜索',
        searchOpenLabel: '搜索',
        onSearchChanged: onChanged,
      ),
    );

    (TextEditingController, FocusNode) holders() {
      final c = TextEditingController();
      final f = FocusNode();
      addTearDown(c.dispose);
      addTearDown(f.dispose);
      return (c, f);
    }

    testWidgets('a pane wide enough shows the actions and the field', (
      tester,
    ) async {
      final (c, f) = holders();
      await pumpLg(tester, row(controller: c, focus: f));
      expect(find.text('上传'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('搜索'), findsNothing);
    });

    testWidgets('a narrow pane shows the search as an icon', (tester) async {
      final (c, f) = holders();
      await pumpLg(tester, row(controller: c, focus: f, width: 468));
      expect(find.text('上传'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('搜索'), findsOneWidget);
    });

    testWidgets(
      'the icon opens the field over the whole row and gives it the keyboard',
      (tester) async {
        final (c, f) = holders();
        await pumpLg(tester, row(controller: c, focus: f, width: 468));
        await tester.tap(find.byTooltip('搜索'));
        await tester.pump();
        await tester.pump();
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('上传'), findsNothing);
        expect(f.hasFocus, isTrue);
      },
    );

    testWidgets('the field gives the icon back when focus leaves it empty', (
      tester,
    ) async {
      final (c, f) = holders();
      await pumpLg(tester, row(controller: c, focus: f, width: 468));
      await tester.tap(find.byTooltip('搜索'));
      await tester.pump();
      await tester.pump();
      f.unfocus();
      await tester.pump();
      expect(find.byTooltip('搜索'), findsOneWidget);
      expect(find.text('上传'), findsOneWidget);
    });

    testWidgets('text in the field keeps it open, whatever the focus', (
      tester,
    ) async {
      final (c, f) = holders();
      c.text = '报告';
      await pumpLg(tester, row(controller: c, focus: f, width: 468));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('上传'), findsNothing);
    });

    testWidgets('openSearch does the same from the keyboard', (tester) async {
      final (c, f) = holders();
      final key = GlobalKey<LgFileOpRowState>();
      await pumpLg(tester, row(controller: c, focus: f, width: 468, key: key));
      key.currentState!.openSearch();
      await tester.pump();
      await tester.pump();
      expect(f.hasFocus, isTrue);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets(
      'typing reports the text; the clear button empties it and keeps the focus',
      (tester) async {
        final (c, f) = holders();
        final log = <String>[];
        await pumpLg(tester, row(controller: c, focus: f, onChanged: log.add));
        expect(find.byTooltip('清除搜索'), findsNothing);
        await tester.enterText(find.byType(TextField), '报告');
        await tester.pump();
        expect(log, ['报告']);
        await tester.tap(find.byTooltip('清除搜索'));
        await tester.pump();
        expect(c.text, '');
        expect(log.last, '');
        expect(find.byTooltip('清除搜索'), findsNothing);
      },
    );
  });

  group('status line, reading state', () {
    testWidgets('the status line is a live region', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        const SizedBox(width: 400, child: LgFileStatusRow('已选择 2 个项目，2.48 MB')),
      );
      final node = tester.getSemantics(
        find.bySemanticsLabel('已选择 2 个项目，2.48 MB'),
      );
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('nothing changes while it is not reading', (tester) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 300,
          height: 200,
          child: LgReadingOverlay(
            reading: false,
            label: '正在读取…',
            child: Text('内容'),
          ),
        ),
      );
      expect(find.text('正在读取…'), findsNothing);
      expect(find.text('内容'), findsOneWidget);
    });

    testWidgets('reading dims the content, takes its clicks and says so', (
      tester,
    ) async {
      var taps = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 300,
          height: 200,
          child: LgReadingOverlay(
            reading: true,
            label: '正在读取…',
            child: GestureDetector(
              onTap: () => taps++,
              child: const SizedBox.expand(child: Text('内容')),
            ),
          ),
        ),
      );
      expect(find.text('正在读取…'), findsOneWidget);
      expect(find.byType(LgSpinner), findsOneWidget);
      await tester.tapAt(
        tester.getTopLeft(find.byType(LgReadingOverlay)) + const Offset(20, 20),
      );
      expect(taps, 0);
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: find.text('内容'), matching: find.byType(Opacity)),
      );
      expect(opacity.opacity, lessThan(1));
    });
  });

  group('drag highlights', () {
    Widget zone(LgDropState state, {String? message}) => SizedBox(
      width: 400,
      height: 300,
      child: LgDropZone(
        state: state,
        message: message,
        child: const ColoredBox(
          color: Colors.white,
          child: Center(child: Text('栏')),
        ),
      ),
    );

    testWidgets('nothing over the pane, nothing added', (tester) async {
      await pumpLg(tester, zone(LgDropState.none, message: '上传到“备份”'));
      expect(find.text('上传到“备份”'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(LgDropZone),
          matching: find.byType(IgnorePointer),
        ),
        findsNothing,
      );
    });

    testWidgets('accepted: the target is named in the middle', (tester) async {
      await pumpLg(tester, zone(LgDropState.accept, message: '上传到“备份”'));
      expect(find.text('上传到“备份”'), findsOneWidget);
      expect(_icon(LgIcons.upload), findsOneWidget);
    });

    testWidgets('rejected: a frame only, no message', (tester) async {
      await pumpLg(tester, zone(LgDropState.reject, message: '上传到“备份”'));
      expect(find.text('上传到“备份”'), findsNothing);
      expect(find.text('栏'), findsOneWidget);
    });

    testWidgets('the highlight lets every pointer event through', (
      tester,
    ) async {
      var taps = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 400,
          height: 300,
          child: LgDropZone(
            state: LgDropState.accept,
            message: '上传到“备份”',
            child: GestureDetector(
              onTap: () => taps++,
              child: const ColoredBox(
                color: Colors.white,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.tapAt(tester.getCenter(find.byType(LgDropZone)));
      expect(taps, 1);
    });

    testWidgets('the chip shows the number when there is more than one', (
      tester,
    ) async {
      await pumpLg(tester, const LgDragChip(label: '年度报告.docx', count: 1));
      expect(find.text('年度报告.docx'), findsOneWidget);
      expect(find.byType(LgBadge), findsNothing);
      await pumpLg(tester, const LgDragChip(label: '年度报告.docx', count: 3));
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('a rejected chip carries the "not allowed" mark', (
      tester,
    ) async {
      await pumpLg(
        tester,
        const LgDragChip(label: '年度报告.docx', count: 2, rejected: true),
      );
      expect(_icon(LgIcons.ban), findsOneWidget);
      await pumpLg(tester, const LgDragChip(label: '年度报告.docx', count: 2));
      expect(_icon(LgIcons.ban), findsNothing);
    });
  });

  group('what the file view added to shared parts', () {
    testWidgets(
      'a quiet text field takes typing from the first tap, as an ordinary one does',
      (tester) async {
        for (final quiet in [false, true]) {
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          await pumpLg(
            tester,
            SizedBox(
              width: 300,
              child: LgTextField(
                controller: controller,
                dense: true,
                quiet: quiet,
              ),
            ),
          );
          await tester.enterText(find.byType(TextField), 'abc');
          expect(controller.text, 'abc', reason: 'quiet: $quiet');
        }
      },
    );

    testWidgets(
      'a quiet field at rest has no frame and takes the window ground',
      (tester) async {
        await pumpLg(
          tester,
          const SizedBox(
            width: 300,
            child: LgTextField(dense: true, quiet: true),
          ),
        );
        final box = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(LgTextField),
                matching: find.byWidgetPredicate(
                  (w) => w is Container && w.foregroundDecoration != null,
                ),
              )
              .first,
        );
        final border =
            (box.foregroundDecoration! as BoxDecoration).border! as Border;
        expect(border.top.color.a, 0);
        await pumpLg(
          tester,
          const SizedBox(width: 300, child: LgTextField(dense: true)),
        );
        final plain = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(LgTextField),
                matching: find.byWidgetPredicate(
                  (w) => w is Container && w.foregroundDecoration != null,
                ),
              )
              .first,
        );
        expect(
          ((plain.foregroundDecoration! as BoxDecoration).border! as Border)
              .top
              .color
              .a,
          1,
        );
      },
    );

    testWidgets(
      'the empty state can have two ways out, the outlined one first',
      (tester) async {
        final log = <String>[];
        await pumpLg(
          tester,
          SizedBox(
            width: 500,
            child: LgEmptyState(
              '无法打开“备份”：没有访问权限。',
              actionLabel: '重试',
              onAction: () => log.add('retry'),
              secondaryActionLabel: '转到主文件夹',
              onSecondaryAction: () => log.add('home'),
            ),
          ),
        );
        expect(
          tester.getTopLeft(find.text('转到主文件夹')).dx <
              tester.getTopLeft(find.text('重试')).dx,
          isTrue,
        );
        await tester.tap(find.text('转到主文件夹'));
        await tester.tap(find.text('重试'));
        expect(log, ['home', 'retry']);
      },
    );

    testWidgets('one way out is what it always was', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 500,
          child: LgEmptyState('空', actionLabel: '重试', onAction: () {}),
        ),
      );
      expect(find.byType(LgButton), findsOneWidget);
    });
  });

  group('pane frame', () {
    testWidgets('it is a group of its own with a name', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        const SizedBox(
          width: 300,
          height: 200,
          child: LgFilePaneFrame(semanticLabel: '远程设备', child: Text('内容')),
        ),
      );
      expect(find.bySemanticsLabel(RegExp('远程设备')), findsOneWidget);
      handle.dispose();
    });
  });
}
