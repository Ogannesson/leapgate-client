// Behaviour of the M9a components (docs LEAPGATE.md §10.18, 14 §2.6): the install dialog with its
// location row, options, licence line and banners, the local notice card's button with the
// shield, and the three small additions to older components (an icon on `LgDialogAction`, a
// scrim that does not scroll, the medium banner). Callbacks are called, a greyed part does not
// respond, the keyboard reaches the parts, the names a screen reader gets are there. Nothing
// here compares pixels.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/widgets/lg_banner.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_feedback.dart';
import 'package:leapgate_ui/widgets/lg_form_dialog.dart';
import 'package:leapgate_ui/widgets/lg_install_dialog.dart';
import 'package:leapgate_ui/widgets/lg_list_chrome.dart';

import 'helpers.dart';

const _path = r'C:\Program Files\Leapgate';
const _longPath = r'D:\工作资料\常用软件\远程工具\公司内部\更长的文件夹名称\Leapgate';

LgInstallPathRow _row({
  String path = _path,
  VoidCallback? onChange,
  LgPathTone tone = LgPathTone.normal,
  String? message,
  String? messageTooltip,
}) => LgInstallPathRow(
  label: '安装位置',
  path: path,
  changeLabel: '修改',
  changeSemanticLabel: '修改安装位置',
  onChange: onChange,
  tone: tone,
  message: message,
  messageTooltip: messageTooltip,
);

LgInstallDialog _dialog({
  List<String>? log,
  bool busy = false,
  bool installEnabled = true,
  List<Widget> banners = const [],
  Widget? pathRow,
  List<bool>? printer,
  ScrollController? controller,
}) => LgInstallDialog(
  title: '安装 Leapgate',
  scrollController: controller,
  pathRow: pathRow ?? _row(onChange: busy ? null : () => log?.add('change')),
  options: [
    LgOptionCheck(
      value: true,
      label: '创建开始菜单快捷方式',
      onChanged: busy ? null : (_) => log?.add('menu'),
    ),
    LgOptionCheck(
      value: printer?.single ?? false,
      label: '安装 Leapgate 打印机',
      description: '远程控制本机时，对方在本机打印到“Leapgate Printer”的文件将发送到对方的设备上打印',
      onChanged: busy ? null : (v) => log?.add('printer $v'),
    ),
  ],
  license: LgLicenseLine(
    before: '开始安装即表示接受',
    link: '许可协议',
    after: '。',
    onOpen: () => log?.add('license'),
  ),
  banners: banners,
  actions: [
    LgDialogAction(
      label: '取消',
      onPressed: busy ? null : () => log?.add('cancel'),
    ),
    LgDialogAction(
      label: busy ? '正在安装…' : '安装',
      kind: LgButtonKind.primary,
      icon: LgIcons.uac,
      iconSize: 18,
      busy: busy,
      isDefault: true,
      onPressed: installEnabled ? () => log?.add('install') : null,
    ),
  ],
);

/// The dialog in a scrim of [height], the way the home tab's dialog layer holds it.
Widget _stage(Widget dialog, {double height = 700}) => SizedBox(
  width: 600,
  height: height,
  child: LgDialogScrim(scrollable: false, child: dialog),
);

void main() {
  group('LgInstallDialog', () {
    testWidgets('the buttons call back; Enter runs the answer', (tester) async {
      final log = <String>[];
      await pumpLg(tester, _stage(_dialog(log: log)));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('取消'));
      await tester.tap(find.text('修改'));
      await tester.tap(find.text('许可协议'));
      expect(log, ['cancel', 'change', 'license']);

      // The answer is the default: it holds the keyboard when the dialog opens.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(log.last, 'install');
    });

    testWidgets('while it runs nothing answers and the answer says so', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final log = <String>[];
      await pumpLg(tester, _stage(_dialog(log: log, busy: true)));
      await tester.pump(const Duration(milliseconds: 200));

      for (final label in ['取消', '修改', '创建开始菜单快捷方式']) {
        await tester.tap(find.text(label), warnIfMissed: false);
      }
      await tester.tap(find.text('正在安装…'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(log, isEmpty);
      expect(find.bySemanticsLabel('正在安装…'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a greyed answer does not run on Enter', (tester) async {
      final log = <String>[];
      await pumpLg(tester, _stage(_dialog(log: log, installEnabled: false)));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.tap(find.text('安装'));
      expect(log, isEmpty);
    });

    testWidgets('the middle scrolls, the head and the buttons stay in view', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const stageHeight = 380.0;
      await pumpLg(
        tester,
        _stage(
          _dialog(
            controller: controller,
            banners: const [
              LgInstallBanner(
                tone: LgTone.warning,
                text: 'Leapgate 将关闭并重新打开，所有会话和正在使用的出口、隧道都将断开。',
              ),
              LgInstallBanner(
                tone: LgTone.error,
                text:
                    '安装失败：Cannot install the EXE package over an existing MSI installation',
              ),
            ],
          ),
          height: stageHeight,
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(controller.position.maxScrollExtent, greaterThan(0));
      final card = tester.getRect(find.byType(LgInstallDialog));
      // Within the area less 24 px on every side.
      expect(card.height, lessThanOrEqualTo(stageHeight - 48));
      expect(
        tester.getRect(find.text('安装 Leapgate')).top,
        greaterThanOrEqualTo(card.top),
      );
      expect(
        tester.getRect(find.text('安装')).bottom,
        lessThanOrEqualTo(card.bottom),
      );

      // Scrolled to the end, the last banner is in view.
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(
        tester.getRect(find.textContaining('安装失败')).bottom,
        lessThanOrEqualTo(tester.getRect(find.text('取消')).top),
      );
    });

    testWidgets('names the dialog and its parts for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, _stage(_dialog(banners: const [])));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.bySemanticsLabel('安装 Leapgate'), findsWidgets);
      expect(find.bySemanticsLabel('修改安装位置'), findsOneWidget);
      expect(find.bySemanticsLabel('安装'), findsOneWidget);
      // The location is one node named by its label and valued with the path; the folder's
      // parts are not read one by one.
      expect(
        tester.getSemantics(find.bySemanticsLabel('安装位置')),
        isSemantics(label: '安装位置', value: _path),
      );
      handle.dispose();
    });
  });

  group('LgInstallPathRow', () {
    testWidgets('"修改" calls back, and is greyed without a callback', (
      tester,
    ) async {
      var n = 0;
      await pumpLg(
        tester,
        SizedBox(width: 480, child: _row(onChange: () => n++)),
      );
      await tester.tap(find.text('修改'));
      expect(n, 1);

      await pumpLg(tester, SizedBox(width: 480, child: _row()));
      await tester.tap(find.text('修改'), warnIfMissed: false);
      expect(n, 1);
    });

    testWidgets('the message shows only with a warning or an error', (
      tester,
    ) async {
      const text = '无法安装到网络位置或可移动磁盘。请选择本机磁盘上的文件夹。';
      await pumpLg(tester, SizedBox(width: 480, child: _row(message: text)));
      expect(find.text(text), findsNothing);

      for (final tone in [LgPathTone.error, LgPathTone.warning]) {
        await pumpLg(
          tester,
          SizedBox(
            width: 480,
            child: _row(tone: tone, message: text),
          ),
        );
        expect(find.text(text), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is LgIcon &&
                w.icon ==
                    (tone == LgPathTone.error ? LgIcons.err : LgIcons.warn),
          ),
          findsOneWidget,
        );
      }
    });

    group('messageTooltip', () {
      const text = '无法安装到 Leapgate 当前所在的文件夹。请选择其他位置。';
      const folder = r'C:\Users\zhangsan\Downloads\leapgate-0.4.0';

      Widget row({String? tooltip, String path = _path}) => SizedBox(
        width: 640,
        child: _row(
          path: path,
          tone: LgPathTone.error,
          message: text,
          messageTooltip: tooltip,
        ),
      );

      testWidgets('shows the folder while the pointer is on the red line', (
        tester,
      ) async {
        await pumpLg(tester, row(tooltip: folder));
        await hover(tester, find.text(text));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text(folder), findsOneWidget);
        // The text is still there once, and the line looks as it did: icon, then the text.
        expect(find.text(text), findsOneWidget);
      });

      testWidgets('without it the line has no tooltip', (tester) async {
        await pumpLg(tester, row());
        await hover(tester, find.text(text));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text(folder), findsNothing);
      });

      testWidgets('does not stack on the tooltip of a cut path', (
        tester,
      ) async {
        await pumpLg(
          tester,
          SizedBox(
            width: 480,
            child: _row(
              path: _longPath,
              tone: LgPathTone.error,
              message: text,
              messageTooltip: folder,
            ),
          ),
        );
        await hover(tester, find.text(text));
        await tester.pump(const Duration(seconds: 1));
        // The pointer is on the line: the folder shows, the cut path does not.
        expect(find.text(folder), findsOneWidget);
        expect(find.text(_longPath), findsNothing);
      });

      testWidgets('the folder is read after the message', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpLg(tester, row(tooltip: folder));
        expect(find.bySemanticsLabel('$text $folder'), findsOneWidget);
        handle.dispose();
      });

      testWidgets('the message is read as before without it', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpLg(tester, row());
        expect(find.bySemanticsLabel(text), findsOneWidget);
        handle.dispose();
      });
    });

    testWidgets(
      'a long path is cut in the middle: the last folder stays whole',
      (tester) async {
        await pumpLg(
          tester,
          SizedBox(width: 480, child: _row(path: _longPath)),
        );
        expect(find.text(r'\Leapgate'), findsOneWidget);
        final head = tester.widget<Text>(
          find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? '').startsWith(r'D:\工作资料'),
          ),
        );
        expect(head.overflow, TextOverflow.ellipsis);
        // The tail is not cut: it has its whole width.
        expect(tester.getSize(find.text(r'\Leapgate')).width, greaterThan(60));
      },
    );

    testWidgets('a cut path shows in full while the pointer is on it', (
      tester,
    ) async {
      await pumpLg(tester, SizedBox(width: 480, child: _row(path: _longPath)));
      await hover(tester, find.byType(LgInstallPathRow));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(_longPath), findsOneWidget);
    });

    testWidgets('a path that fits has no tooltip', (tester) async {
      // The test font's letters are as wide as they are tall: room for 25 of them at 15 px.
      await pumpLg(tester, SizedBox(width: 640, child: _row()));
      await hover(tester, find.byType(LgInstallPathRow));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(_path), findsNothing);
    });

    testWidgets('the change button can take the keyboard at the start', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await pumpLg(
        tester,
        SizedBox(
          width: 480,
          child: LgInstallPathRow(
            label: '安装位置',
            path: _path,
            changeLabel: '修改',
            onChange: () {},
            changeFocusNode: node,
            changeAutofocus: true,
          ),
        ),
      );
      await tester.pump();
      expect(node.hasFocus, isTrue);
    });
  });

  group('LgOptionCheck', () {
    Widget option(ValueChanged<bool>? on, {bool value = false}) => SizedBox(
      width: 448,
      child: LgOptionCheck(
        value: value,
        label: '安装 Leapgate 打印机',
        description: '文件将发送到对方的设备上打印',
        onChanged: on,
      ),
    );

    testWidgets('the whole row toggles, by mouse and by Space', (tester) async {
      final seen = <bool>[];
      await pumpLg(tester, option(seen.add));
      await tester.tap(find.text('文件将发送到对方的设备上打印'));
      await tester.tap(find.text('安装 Leapgate 打印机'));
      expect(seen, [true, true]);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(seen, [true, true, true]);
    });

    const spoken = '安装 Leapgate 打印机. 文件将发送到对方的设备上打印';

    testWidgets('without a callback it is greyed and does not respond', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, option(null));
      await tester.tap(find.text('安装 Leapgate 打印机'), warnIfMissed: false);
      expect(
        tester.getSemantics(find.bySemanticsLabel(spoken)),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
      handle.dispose();
    });

    testWidgets('read as label and description, with the state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, option((_) {}, value: true));
      expect(
        tester.getSemantics(find.bySemanticsLabel(spoken)),
        isSemantics(
          label: spoken,
          isButton: true,
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('draws the 24 px box of the mockup', (tester) async {
      await pumpLg(tester, option((_) {}, value: true));
      final check = find.byWidgetPredicate(
        (w) => w is LgIcon && w.icon == LgIcons.check,
      );
      expect(tester.getSize(check), const Size(16, 16));
      expect(
        tester.getSize(
          find.ancestor(of: check, matching: find.byType(Container)).first,
        ),
        const Size(24, 24),
      );
    });
  });

  group('LgLicenseLine', () {
    testWidgets('only the link responds; the text around it is plain', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var n = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 448,
          child: LgLicenseLine(
            before: '开始安装即表示接受',
            link: '许可协议',
            after: '。',
            onOpen: () => n++,
            linkSemanticLabel: '许可协议（在浏览器中打开）',
          ),
        ),
      );
      await tester.tap(find.text('许可协议'));
      expect(n, 1);
      // A button of its own, not the whole sentence.
      expect(
        tester.getSemantics(find.bySemanticsLabel('许可协议（在浏览器中打开）')),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: true),
      );
      expect(find.bySemanticsLabel(RegExp('开始安装即表示接受')), findsOneWidget);
      // The arrow that leaves the window is there.
      expect(
        find.byWidgetPredicate(
          (w) => w is LgIcon && w.icon == LgIcons.externalLink,
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('LgLocalNotice action icon', () {
    Widget card({LgIcons? icon, LgButtonKind? kind}) => SizedBox(
      width: 192,
      child: kind == null
          ? LgLocalNotice(
              tone: LgTone.info,
              text: '已安装的 Leapgate 版本低于当前版本。',
              actionLabel: '升级',
              onAction: () {},
              actionIcon: icon,
            )
          : LgLocalNotice(
              tone: LgTone.info,
              text: '已安装的 Leapgate 版本低于当前版本。',
              actionLabel: '升级',
              onAction: () {},
              actionIcon: icon,
              actionKind: kind,
            ),
    );

    testWidgets('the shield goes before the label, 18 px', (tester) async {
      await pumpLg(tester, card(icon: LgIcons.uac, kind: LgButtonKind.primary));
      final shield = find.byWidgetPredicate(
        (w) => w is LgIcon && w.icon == LgIcons.uac,
      );
      expect(shield, findsOneWidget);
      expect(tester.getSize(shield), const Size(18, 18));
      expect(
        tester.getCenter(shield).dx,
        lessThan(tester.getCenter(find.text('升级')).dx),
      );
    });

    testWidgets('the arrow of "安装" is 20 px', (tester) async {
      await pumpLg(
        tester,
        card(icon: LgIcons.download, kind: LgButtonKind.primary),
      );
      final arrow = find.byWidgetPredicate(
        (w) => w is LgIcon && w.icon == LgIcons.download,
      );
      expect(tester.getSize(arrow), const Size(20, 20));
    });

    testWidgets('without the new parameters the button is what it was', (
      tester,
    ) async {
      await pumpLg(tester, card());
      final button = tester.widget<LgButton>(find.byType(LgButton));
      expect(button.kind, LgButtonKind.secondary);
      expect(button.icon, isNull);
      expect(button.iconSize, 20);
    });

    testWidgets('busy shows the spinner and does not respond', (tester) async {
      var n = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 192,
          child: LgLocalNotice(
            tone: LgTone.info,
            text: '已安装的 Leapgate 版本低于当前版本。',
            actionLabel: '正在升级…',
            onAction: () => n++,
            actionIcon: LgIcons.uac,
            actionKind: LgButtonKind.primary,
            actionBusy: true,
          ),
        ),
      );
      await tester.tap(find.text('正在升级…'));
      expect(n, 0);
      expect(
        find.byWidgetPredicate((w) => w is LgIcon && w.icon == LgIcons.uac),
        findsNothing,
      );
    });
  });

  group('older components, new optional parameters', () {
    testWidgets(
      'LgDialogAction.icon reaches the buttons of the other dialogs',
      (tester) async {
        await pumpLg(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LgConfirmDialog(
                title: '安装？',
                actions: [
                  LgDialogAction(
                    label: '安装',
                    kind: LgButtonKind.primary,
                    icon: LgIcons.uac,
                    iconSize: 18,
                    onPressed: () {},
                  ),
                ],
              ),
              LgFormDialog(
                title: '登录',
                actions: [
                  LgDialogAction(
                    label: '登录',
                    kind: LgButtonKind.primary,
                    icon: LgIcons.uac,
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
        );
        final shields = find.byWidgetPredicate(
          (w) => w is LgIcon && w.icon == LgIcons.uac,
        );
        expect(shields, findsNWidgets(2));
        expect(tester.getSize(shields.first), const Size(18, 18));
        expect(tester.getSize(shields.last), const Size(20, 20));
      },
    );

    testWidgets(
      'the banner in the medium size is the slim one with 14 px text',
      (tester) async {
        await pumpLg(
          tester,
          const SizedBox(
            width: 400,
            child: Column(
              children: [
                LgBanner(tone: LgTone.warning, text: '一', slim: true),
                LgBanner(
                  tone: LgTone.warning,
                  text: '二',
                  slim: true,
                  medium: true,
                ),
              ],
            ),
          ),
        );
        final plain = tester.widget<Text>(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.textSpan != null &&
                w.textSpan!.toPlainText() == '一',
          ),
        );
        final medium = tester.widget<Text>(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.textSpan != null &&
                w.textSpan!.toPlainText() == '二',
          ),
        );
        expect(plain.style!.fontSize, 15);
        expect(medium.style!.fontSize, 14);
      },
    );

    testWidgets('a scrim that does not scroll keeps its child within the area', (
      tester,
    ) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 400,
          height: 300,
          child: LgDialogScrim(
            scrollable: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Whatever the child is given, it is the area less 24 px all round.
                  expect(constraints.maxHeight, 300 - 48);
                  expect(constraints.maxWidth, 300);
                  return const SizedBox(height: 10, key: ValueKey('inner'));
                },
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('inner')), findsOneWidget);
    });

    testWidgets('the default scrim still scrolls a tall child', (tester) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 400,
          height: 200,
          child: LgDialogScrim(child: SizedBox(width: 100, height: 500)),
        ),
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
