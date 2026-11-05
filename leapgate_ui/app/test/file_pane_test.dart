// Behaviour of the parts of a file pane (docs LEAPGATE.md §10.15): the header, the navigation row,
// the breadcrumb and the path input, the row of actions with its search, the status line, the
// "reading" state, the drag highlights. Callbacks are called, a greyed part does not answer, the
// right things show and hide, the names a screen reader gets are there. No pixels.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
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

/// Every node of the semantics tree under [root].
List<SemanticsNode> _semanticsNodes(SemanticsNode root) {
  final all = <SemanticsNode>[];
  void visit(SemanticsNode n) {
    all.add(n);
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(root);
  return all;
}

/// Counts how often the State under it is made and thrown away: a rebuild that moves a subtree
/// shows up as a second `created`.
class _ProbeLog {
  int created = 0;
  int disposed = 0;
}

class _Probe extends StatefulWidget {
  const _Probe({required this.log, required this.child});

  final _ProbeLog log;
  final Widget child;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.log.created++;
  }

  @override
  void dispose() {
    widget.log.disposed++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// What a page does with a row of actions: it owns the "search is open" flag, and the width is
/// the pane's, changed from outside.
class _OpsHost extends StatefulWidget {
  const _OpsHost({
    super.key,
    required this.controller,
    required this.focus,
    required this.width,
    required this.open,
    required this.compact,
    this.log,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final double width;
  final bool open;
  final bool compact;

  /// Every value the row asked the page to set the flag to.
  final List<bool>? log;
  final ValueChanged<String>? onChanged;

  @override
  State<_OpsHost> createState() => _OpsHostState();
}

class _OpsHostState extends State<_OpsHost> {
  late double _width = widget.width;
  late bool _open = widget.open;

  void setWidth(double width) => setState(() => _width = width);

  void setOpen(bool open) => setState(() => _open = open);

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _width,
    child: LgFileOpRow(
      actions: [
        LgButton(label: '上传', kind: LgButtonKind.primary, onPressed: () {}),
        LgButton(label: '新建文件夹', onPressed: () {}),
      ],
      searchController: widget.controller,
      searchFocusNode: widget.focus,
      searchPlaceholder: '搜索当前文件夹',
      searchClearLabel: '清除搜索',
      searchOpenLabel: '搜索',
      searchActiveLabel: '搜索，正在过滤',
      searchOpen: _open,
      onSearchOpenChanged: (open) {
        widget.log?.add(open);
        setOpen(open);
      },
      onSearchChanged: widget.onChanged,
      compact: widget.compact,
    ),
  );
}

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

    testWidgets(
      'the smallest window\'s header is lower, and nothing overflows',
      (tester) async {
        Widget header(bool compact) => SizedBox(
          width: 400,
          child: LgFilePaneHeader(
            title: '远程设备',
            subtitle: '书房台式机 · Windows',
            platform: LgPlatform.windows,
            remoteId: '456 789 123',
            compact: compact,
          ),
        );
        await pumpLg(tester, header(false));
        final normal = tester.getSize(find.byType(LgFilePaneHeader)).height;
        await pumpLg(tester, header(true));
        expect(
          tester.getSize(find.byType(LgFilePaneHeader)).height,
          lessThan(normal),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('navigation row', () {
    LgFileNavRow row(
      List<String> log, {
      bool canGoUp = true,
      bool compact = false,
    }) => LgFileNavRow(
      compact: compact,
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

    testWidgets('the smallest window\'s row is 4 px lower', (tester) async {
      await pumpLg(tester, SizedBox(width: 600, child: row([])));
      final normal = tester.getSize(find.byType(LgFileNavRow)).height;
      await pumpLg(tester, SizedBox(width: 600, child: row([], compact: true)));
      expect(tester.getSize(find.byType(LgFileNavRow)).height, normal - 4);
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

    testWidgets('a click on the … is not a click on the row: no path input', (
      tester,
    ) async {
      var edit = 0;
      await pumpLg(
        tester,
        _crumb(
          ['D:', '备份', '2026', '十月', '家庭', '照片', '原图'],
          width: 330,
          onEdit: () => edit++,
        ),
      );
      await tester.tap(find.text('…'));
      await tester.pump();
      expect(edit, 0);
      // The rest of the row still does what it did.
      await tester.tap(find.text('原图'));
      expect(edit, 1);
    });

    testWidgets('the … that takes the press is no button to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        _crumb(['D:', '备份', '2026', '十月', '家庭', '照片', '原图'], width: 330),
      );
      // The press it takes would be a second tap action next to the row's own, which the
      // semantics tree cannot merge: the "…" would come out as a node of its own, a button that
      // does nothing.
      var root = tester.getSemantics(find.byType(LgBreadcrumb));
      while (root.parent != null) {
        root = root.parent!;
      }
      final alone = _semanticsNodes(root).where((n) => n.label == '…');
      expect(alone, isEmpty);
      handle.dispose();
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
    (TextEditingController, FocusNode) holders() {
      final c = TextEditingController();
      final f = FocusNode();
      addTearDown(c.dispose);
      addTearDown(f.dispose);
      return (c, f);
    }

    Widget host(
      TextEditingController c,
      FocusNode f, {
      GlobalKey<_OpsHostState>? key,
      double width = 618,
      bool open = false,
      bool compact = false,
      List<bool>? log,
      ValueChanged<String>? onChanged,
    }) => _OpsHost(
      key: key,
      controller: c,
      focus: f,
      width: width,
      open: open,
      compact: compact,
      log: log,
      onChanged: onChanged,
    );

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a pane wide enough shows the actions and the field', (
      tester,
    ) async {
      final (c, f) = holders();
      await pumpLg(tester, host(c, f));
      expect(find.text('上传'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('搜索'), findsNothing);
    });

    testWidgets('a narrow pane shows the search as an icon', (tester) async {
      final (c, f) = holders();
      await pumpLg(tester, host(c, f, width: 468));
      expect(find.text('上传'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('搜索'), findsOneWidget);
    });

    testWidgets(
      'the icon asks the page to open the field; the field takes the row and the keyboard',
      (tester) async {
        final (c, f) = holders();
        final log = <bool>[];
        await pumpLg(tester, host(c, f, width: 468, log: log));
        await tester.tap(find.byTooltip('搜索'));
        await settle(tester);
        expect(log, [true]);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('上传'), findsNothing);
        expect(f.hasFocus, isTrue);
      },
    );

    testWidgets(
      'the page opens it too, as Ctrl+F does, and the field gets the keyboard',
      (tester) async {
        final (c, f) = holders();
        final key = GlobalKey<_OpsHostState>();
        await pumpLg(tester, host(c, f, key: key, width: 468));
        expect(find.byType(TextField), findsNothing);
        key.currentState!.setOpen(true);
        await settle(tester);
        expect(find.byType(TextField), findsOneWidget);
        expect(f.hasFocus, isTrue);
      },
    );

    testWidgets(
      'focus leaving the field gives the icon back, with text or without',
      (tester) async {
        final (c, f) = holders();
        final log = <bool>[];
        await pumpLg(tester, host(c, f, width: 468, log: log));
        await tester.tap(find.byTooltip('搜索'));
        await settle(tester);
        await tester.enterText(find.byType(TextField), '报告');
        await tester.pump();
        f.unfocus();
        await settle(tester);
        expect(log, [true, false]);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('上传'), findsOneWidget);
        expect(c.text, '报告');
      },
    );

    testWidgets(
      'a folder that is filtered says so on the icon, and the icon opens on the same text',
      (tester) async {
        final handle = tester.ensureSemantics();
        final (c, f) = holders();
        c.text = '报告';
        await pumpLg(tester, host(c, f, width: 468));
        expect(find.byType(TextField), findsNothing);
        expect(find.bySemanticsLabel('搜索，正在过滤'), findsOneWidget);
        final colors = LgTokens.of(
          tester.element(find.byType(LgFileOpRow)),
        ).colors;
        LgIcon searchIcon() => tester.widget<LgIcon>(
          find.descendant(
            of: find.byTooltip('搜索，正在过滤'),
            matching: _icon(LgIcons.search),
          ),
        );
        expect(searchIcon().color, colors.accent);
        await tester.tap(find.byTooltip('搜索，正在过滤'));
        await settle(tester);
        expect(c.text, '报告');
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          '报告',
        );
        handle.dispose();
      },
    );

    testWidgets('an empty search is the quiet icon under its plain name', (
      tester,
    ) async {
      final (c, f) = holders();
      await pumpLg(tester, host(c, f, width: 468));
      final colors = LgTokens.of(
        tester.element(find.byType(LgFileOpRow)),
      ).colors;
      final icon = tester.widget<LgIcon>(
        find.descendant(
          of: find.byTooltip('搜索'),
          matching: _icon(LgIcons.search),
        ),
      );
      expect(icon.color, colors.text2);
      expect(find.byTooltip('搜索，正在过滤'), findsNothing);
    });

    testWidgets(
      'crossing the width with the field open keeps the same field, its text and its focus',
      (tester) async {
        final (c, f) = holders();
        final key = GlobalKey<_OpsHostState>();
        await pumpLg(tester, host(c, f, key: key, open: true));
        await tester.tap(find.byType(TextField));
        await tester.enterText(find.byType(TextField), '报告');
        await tester.pump();
        expect(f.hasFocus, isTrue);
        final before = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        key.currentState!.setWidth(468);
        await settle(tester);
        expect(
          find.text('上传'),
          findsNothing,
          reason: 'narrow and open: the field has the row',
        );
        expect(
          tester.state<EditableTextState>(find.byType(EditableText)),
          same(before),
        );
        expect(c.text, '报告');
        expect(f.hasFocus, isTrue);
        key.currentState!.setWidth(618);
        await settle(tester);
        expect(find.text('上传'), findsOneWidget);
        expect(
          tester.state<EditableTextState>(find.byType(EditableText)),
          same(before),
        );
        expect(c.text, '报告');
        expect(f.hasFocus, isTrue);
      },
    );

    testWidgets(
      'a wide field the page opened and the user left: narrowing shows the buttons, not a field',
      (tester) async {
        final (c, f) = holders();
        final key = GlobalKey<_OpsHostState>();
        final log = <bool>[];
        await pumpLg(tester, host(c, f, key: key, log: log));
        // Ctrl+F in a wide pane: the page sets the flag, the field takes the keyboard.
        key.currentState!.setOpen(true);
        await settle(tester);
        expect(f.hasFocus, isTrue);
        // A press elsewhere takes the keyboard away; the flag has to follow.
        f.unfocus();
        await settle(tester);
        expect(log, [false]);
        key.currentState!.setWidth(468);
        await settle(tester);
        expect(find.text('上传'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.byTooltip('搜索'), findsOneWidget);
      },
    );

    testWidgets(
      'typing in the wide field and then narrowing keeps the field, the keyboard and the connection',
      (tester) async {
        final (c, f) = holders();
        final key = GlobalKey<_OpsHostState>();
        final log = <bool>[];
        await pumpLg(tester, host(c, f, key: key, log: log));
        await tester.tap(find.byType(TextField));
        await settle(tester);
        // The press into the field is the flag coming on, by itself.
        expect(log, [true]);
        tester.testTextInput.enterText('报');
        await tester.pump();
        final before = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        key.currentState!.setWidth(468);
        await settle(tester);
        expect(
          find.text('上传'),
          findsNothing,
          reason: 'narrow, and the field has the row',
        );
        expect(
          tester.state<EditableTextState>(find.byType(EditableText)),
          same(before),
        );
        expect(f.hasFocus, isTrue);
        expect(tester.testTextInput.hasAnyClients, isTrue);
        tester.testTextInput.enterText('报告');
        await tester.pump();
        expect(c.text, '报告');
      },
    );

    testWidgets('in a wide pane the open flag means nothing', (tester) async {
      final (c, f) = holders();
      await pumpLg(tester, host(c, f, open: true));
      expect(find.text('上传'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets(
      'typing reports the text; the clear button empties it and the field stays open and focused',
      (tester) async {
        final (c, f) = holders();
        final texts = <String>[];
        final opens = <bool>[];
        await pumpLg(
          tester,
          host(c, f, width: 468, log: opens, onChanged: texts.add),
        );
        await tester.tap(find.byTooltip('搜索'));
        await settle(tester);
        expect(find.byTooltip('清除搜索'), findsNothing);
        await tester.enterText(find.byType(TextField), '报告');
        await tester.pump();
        expect(texts, ['报告']);
        await tester.tap(find.byTooltip('清除搜索'));
        await settle(tester);
        expect(c.text, '');
        expect(texts.last, '');
        expect(find.byTooltip('清除搜索'), findsNothing);
        // A press on the button is not a press outside the field: the field was not folded.
        expect(opens, [true]);
        expect(find.byType(TextField), findsOneWidget);
        expect(f.hasFocus, isTrue);
      },
    );

    testWidgets('the smallest window\'s row is 4 px lower', (tester) async {
      final (c, f) = holders();
      await pumpLg(tester, host(c, f));
      final normal = tester.getSize(find.byType(LgFileOpRow)).height;
      await pumpLg(tester, host(c, f, compact: true));
      expect(tester.getSize(find.byType(LgFileOpRow)).height, normal - 4);
    });
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

    testWidgets(
      'the wait does not rebuild the list under it: scroll position and State stay',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final probe = _ProbeLog();
        Widget view(bool reading) => SizedBox(
          width: 300,
          height: 200,
          child: LgReadingOverlay(
            reading: reading,
            label: '正在读取…',
            child: _Probe(
              log: probe,
              child: ListView(
                controller: scroll,
                children: [
                  for (var i = 0; i < 40; i++)
                    SizedBox(height: 40, child: Text('项 $i')),
                ],
              ),
            ),
          ),
        );
        await pumpLg(tester, view(false));
        scroll.jumpTo(360);
        await tester.pump();
        expect(scroll.offset, 360);
        await pumpLg(tester, view(true));
        expect(find.text('正在读取…'), findsOneWidget);
        expect(scroll.offset, 360);
        await pumpLg(tester, view(false));
        expect(find.text('正在读取…'), findsNothing);
        expect(scroll.offset, 360);
        expect(probe.created, 1);
        expect(probe.disposed, 0);
      },
    );

    testWidgets(
      'while it reads, a screen reader finds the label and not the list',
      (tester) async {
        final handle = tester.ensureSemantics();
        Widget view(bool reading) => SizedBox(
          width: 300,
          height: 200,
          child: LgReadingOverlay(
            reading: reading,
            label: '正在读取…',
            child: const Text('内容'),
          ),
        );
        List<String> labels() {
          var root = tester.getSemantics(find.byType(LgReadingOverlay));
          while (root.parent != null) {
            root = root.parent!;
          }
          return [for (final n in _semanticsNodes(root)) n.label];
        }

        await pumpLg(tester, view(false));
        expect(labels().where((l) => l.contains('内容')), hasLength(1));
        await pumpLg(tester, view(true));
        expect(labels().where((l) => l.contains('内容')), isEmpty);
        expect(labels().where((l) => l.contains('正在读取')), hasLength(1));
        handle.dispose();
      },
    );
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

    testWidgets(
      'a drag coming and going does not rebuild the list under it: scroll position and State stay',
      (tester) async {
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final probe = _ProbeLog();
        Widget view(LgDropState state) => SizedBox(
          width: 400,
          height: 300,
          child: LgDropZone(
            state: state,
            message: '上传到“备份”',
            child: _Probe(
              log: probe,
              child: ListView(
                controller: scroll,
                children: [
                  for (var i = 0; i < 40; i++)
                    SizedBox(height: 40, child: Text('项 $i')),
                ],
              ),
            ),
          ),
        );
        await pumpLg(tester, view(LgDropState.none));
        scroll.jumpTo(360);
        await tester.pump();
        for (final state in [
          LgDropState.accept,
          LgDropState.reject,
          LgDropState.accept,
          LgDropState.none,
        ]) {
          await pumpLg(tester, view(state));
          expect(scroll.offset, 360, reason: '$state');
        }
        expect(probe.created, 1);
        expect(probe.disposed, 0);
      },
    );

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
    // One test for each: a field that is already focused would not show the frame coming.
    for (final quiet in [false, true]) {
      testWidgets(
        '${quiet ? 'a quiet' : 'an ordinary'} text field takes typing from the first tap',
        (tester) async {
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
          // As a user does it: a press on the field, then the keyboard's text. (`enterText` of
          // the finder would attach the keyboard itself.) The press brings the frame, and a
          // frame that appears must not rebuild what is inside it: the field under the press
          // is the field that takes the text, with the keyboard connection it opened.
          final before = tester.state<EditableTextState>(
            find.byType(EditableText),
          );
          await tester.tap(find.byType(TextField));
          await tester.pump();
          expect(
            tester.state<EditableTextState>(find.byType(EditableText)),
            same(before),
          );
          tester.testTextInput.enterText('abc');
          await tester.pump();
          expect(controller.text, 'abc');
        },
      );
    }

    testWidgets('a quiet field is round by 10, an ordinary one by 12', (
      tester,
    ) async {
      BorderRadius? radius() =>
          (tester
                          .widget<Container>(
                            find
                                .descendant(
                                  of: find.byType(LgTextField),
                                  matching: find.byWidgetPredicate(
                                    (w) =>
                                        w is Container &&
                                        w.foregroundDecoration != null,
                                  ),
                                )
                                .first,
                          )
                          .foregroundDecoration!
                      as BoxDecoration)
                  .borderRadius
              as BorderRadius?;
      await pumpLg(
        tester,
        const SizedBox(
          width: 300,
          child: LgTextField(dense: true, quiet: true),
        ),
      );
      expect(radius(), BorderRadius.circular(10));
      await pumpLg(
        tester,
        const SizedBox(width: 300, child: LgTextField(dense: true)),
      );
      expect(radius(), BorderRadius.circular(12));
    });

    testWidgets('the path input is a quiet field, like the search beside it', (
      tester,
    ) async {
      final controller = TextEditingController(text: r'D:\备份');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await pumpLg(
        tester,
        SizedBox(
          width: 500,
          child: LgPathInput(
            controller: controller,
            focusNode: focus,
            semanticLabel: '路径',
            onSubmitted: (_) {},
            onCancel: () {},
          ),
        ),
      );
      expect(
        tester
            .widget<LgTextField>(
              find.descendant(
                of: find.byType(LgPathInput),
                matching: find.byType(LgTextField),
              ),
            )
            .quiet,
        isTrue,
      );
    });

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

    testWidgets(
      'one way out is laid out as it always was: the button is not in a row',
      (tester) async {
        await pumpLg(
          tester,
          SizedBox(
            width: 500,
            child: LgEmptyState('空', actionLabel: '重试', onAction: () {}),
          ),
        );
        expect(find.byType(LgButton), findsOneWidget);
        // No Row of the state's own around the button: a Row hands its child an unbounded
        // width, and a long label would overflow where it never did.
        Finder rowAround() => find.descendant(
          of: find.byType(LgEmptyState),
          matching: find.ancestor(
            of: find.byType(LgButton),
            matching: find.byType(Row),
          ),
        );
        expect(rowAround(), findsNothing);
        await pumpLg(
          tester,
          SizedBox(
            width: 500,
            child: LgEmptyState(
              '空',
              actionLabel: '重试',
              onAction: () {},
              secondaryActionLabel: '转到主文件夹',
              onSecondaryAction: () {},
            ),
          ),
        );
        expect(rowAround().evaluate().toSet(), hasLength(1));
      },
    );

    testWidgets(
      'a long label on a single button in a narrow room does not overflow',
      (tester) async {
        await pumpLg(
          tester,
          SizedBox(
            width: 180,
            child: LgEmptyState(
              '空',
              actionLabel: '转到主文件夹并重新读取这个很长的位置',
              onAction: () {},
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('two ways out each give way when the room is narrow', (
      tester,
    ) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 220,
          child: LgEmptyState(
            '空',
            actionLabel: '重新读取这个很长的位置',
            onAction: () {},
            secondaryActionLabel: '转到主文件夹并重新读取',
            onSecondaryAction: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
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
