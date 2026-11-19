// Behaviour of the M9c tunnel components (docs LEAPGATE.md §10.18, 14 §2.6): the parts of the exit
// card made public, the table of forwards and the row that adds one, the question area, the tunnel
// and RDP cards, the page with three levels of headings, the RDP settings dialog and the pencil in
// a menu row. Callbacks are called, a greyed part does not respond, the keyboard reaches the parts,
// the names a screen reader gets are there. Nothing here compares pixels.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_banner.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_device.dart';
import 'package:leapgate_ui/widgets/lg_exit_card.dart';
import 'package:leapgate_ui/widgets/lg_exit_page.dart';
import 'package:leapgate_ui/widgets/lg_forward_list.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_page_section.dart';
import 'package:leapgate_ui/widgets/lg_rdp_dialog.dart';
import 'package:leapgate_ui/widgets/lg_text_field.dart';
import 'package:leapgate_ui/widgets/lg_tunnel_card.dart';

import 'helpers.dart';

/// A test in a window as wide as the app's smallest content plus its left column and then some, so
/// that a 1008 px card is laid out at 1008 and not squeezed to the test window's 800.
void _t(String description, Future<void> Function(WidgetTester tester) body) =>
    testWidgets(description, (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await body(tester);
    });

LgForwardRow _row({
  String port = '2222',
  LgExitStatusKind kind = LgExitStatusKind.direct,
  String? note,
  bool copy = true,
  VoidCallback? onCopy,
  List<LgForwardAction>? actions,
  LgExitNotice? notice,
}) => LgForwardRow(
  localHost: '127.0.0.1:',
  localPort: port,
  targetHost: 'localhost:',
  targetPort: '22',
  status: LgExitStatus(kind, '可用 · 直连', note: note),
  copyLabel: copy ? '复制 127.0.0.1:$port' : null,
  onCopy: copy ? (onCopy ?? () {}) : null,
  actions:
      actions ??
      [
        LgForwardAction(
          label: '删除',
          kind: LgForwardButtonKind.neutral,
          semanticLabel: '删除端口转发 $port',
          onPressed: () {},
        ),
      ],
  notice: notice,
);

Widget _list(List<LgForwardRow> rows, {double width = 1008}) => SizedBox(
  width: width,
  child: LgForwardList(
    localLabel: '本机',
    targetLabel: '目标',
    rows: rows,
    semanticLabel: '端口转发',
  ),
);

LgForwardAddRow _addRow({
  VoidCallback? onAdd,
  VoidCallback? onCancel,
  String? error,
  LgForwardField field = LgForwardField.local,
  TextEditingController? local,
  TextEditingController? host,
  TextEditingController? remote,
}) => LgForwardAddRow(
  localHost: '127.0.0.1:',
  localController: local ?? TextEditingController(),
  localLabel: '本机端口',
  hostController: host ?? TextEditingController(),
  hostLabel: '目标主机',
  remoteController: remote ?? TextEditingController(),
  remoteLabel: '远程端口',
  addLabel: '添加',
  cancelLabel: '取消',
  onAdd: onAdd,
  onCancel: onCancel ?? () {},
  errorText: error,
  errorField: field,
  semanticLabel: '添加端口转发',
);

LgExitAction _act(
  String label,
  VoidCallback? onPressed, {
  LgButtonKind kind = LgButtonKind.secondary,
  bool autofocus = false,
}) => LgExitAction(
  label: label,
  kind: kind,
  onPressed: onPressed,
  autofocus: autofocus,
);

LgExitPasswordArea _pw({String? error}) => LgExitPasswordArea(
  controller: TextEditingController(),
  semanticLabel: '密码',
  placeholder: '密码',
  showLabel: '显示密码',
  hideLabel: '隐藏密码',
  rememberLabel: '记住密码',
  remember: false,
  onRememberChanged: (_) {},
  errorText: error,
);

LgTunnelCard _card({
  LgTunnelQuestion? question,
  LgExitStatus? status,
  LgForwardList? forwards,
  String? empty,
  LgForwardAddRow? addRow,
  List<LgExitNotice> notices = const [],
  List<LgExitAction> leading = const [],
  List<LgExitAction> actions = const [],
}) => LgTunnelCard(
  name: '书房台式机',
  id: '123 456 789',
  platform: LgPlatform.windows,
  kindMark: const LgTunnelKindMark(icon: LgIcons.forward, label: 'TCP 隧道'),
  semanticLabel: '书房台式机 · TCP 隧道',
  question: question,
  status: status,
  forwards: forwards,
  emptyText: empty,
  addRow: addRow,
  notices: notices,
  leadingActions: leading,
  actions: actions,
);

void main() {
  group('the parts of the exit card', () {
    _t('the card frame puts its parts 12 px apart, addresses 4', (
      tester,
    ) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 400,
          child: LgExitCardFrame(
            semanticLabel: '卡片',
            parts: [
              LgExitAddressRow(
                LgExitAddress(address: 'a', copyLabel: '复制 a', onCopy: () {}),
              ),
              LgExitAddressRow(
                LgExitAddress(address: 'b', copyLabel: '复制 b', onCopy: () {}),
              ),
              const SizedBox(height: 10, key: ValueKey('third')),
            ],
          ),
        ),
      );
      final rows = find.byType(LgExitAddressRow);
      final first = tester.getRect(rows.at(0));
      final second = tester.getRect(rows.at(1));
      final third = tester.getRect(find.byKey(const ValueKey('third')));
      expect(second.top - first.bottom, LgSpace.s1);
      expect(third.top - second.bottom, LgSpace.s3);
    });

    _t('the header has room for a mark at its end', (tester) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 500,
          child: LgExitCardHeader(
            name: '书房台式机',
            id: '123 456 789',
            platform: LgPlatform.windows,
            trailing: LgTunnelKindMark(icon: LgIcons.forward, label: 'TCP 隧道'),
          ),
        ),
      );
      final mark = tester.getRect(find.byType(LgTunnelKindMark));
      expect(mark.right, tester.getRect(find.byType(LgExitCardHeader)).right);
      expect(find.text('书房台式机'), findsOneWidget);
    });

    _t('an action can take the keyboard when it is built', (tester) async {
      await pumpLg(
        tester,
        LgExitActionRow(
          trailing: [_act('断开', () {}, autofocus: true), _act('继续', () {})],
        ),
      );
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus;
      expect(focus, isNotNull);
      expect(
        find.descendant(
          of: find.byType(LgButton).first,
          matching: find.byWidgetPredicate((w) => w is Focus),
        ),
        findsWidgets,
      );
      expect(
        tester
            .getRect(find.byType(LgButton).first)
            .contains(tester.getCenter(find.text('断开'))),
        isTrue,
      );
      // Enter is the first button's press.
      var pressed = false;
      await pumpLg(
        tester,
        LgExitActionRow(
          trailing: [
            _act('断开', () => pressed = true, autofocus: true),
            _act('继续', () {}),
          ],
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(pressed, isTrue);
    });
  });

  group('LgForwardRow and LgForwardList', () {
    _t('the copy button is there when it can be used', (tester) async {
      var copied = 0;
      await pumpLg(tester, _list([_row(onCopy: () => copied++)]));
      await tester.tap(find.bySemanticsLabel('复制 127.0.0.1:2222'));
      expect(copied, 1);
      await pumpLg(tester, _list([_row(copy: false)]));
      expect(find.byType(LgIconButton), findsNothing);
    });

    _t('the buttons call back and say which forward they are for', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final log = <String>[];
      await pumpLg(
        tester,
        _list([
          _row(
            port: '8080',
            actions: [
              LgForwardAction(
                label: '重试',
                semanticLabel: '重试端口转发 8080',
                onPressed: () => log.add('retry'),
              ),
              LgForwardAction(
                label: '删除',
                kind: LgForwardButtonKind.neutral,
                semanticLabel: '删除端口转发 8080',
                onPressed: () => log.add('delete'),
              ),
            ],
          ),
        ]),
      );
      await tester.tap(find.text('重试'));
      await tester.tap(find.text('删除'));
      expect(log, ['retry', 'delete']);
      expect(
        tester.getSemantics(find.bySemanticsLabel('重试端口转发 8080')),
        isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
      );
      handle.dispose();
    });

    _t('wide: one line; narrow: the status under the addresses', (
      tester,
    ) async {
      final rows = [_row(kind: LgExitStatusKind.warning, note: '远程设备不在线')];
      await pumpLg(tester, _list(rows));
      final wideTarget = tester.getRect(find.text('localhost:'));
      final wideStatus = tester.getRect(find.text('可用 · 直连'));
      expect(wideStatus.left, greaterThan(wideTarget.right));
      expect((wideStatus.center.dy - wideTarget.center.dy).abs(), lessThan(20));

      await pumpLg(tester, _list(rows, width: 656));
      final target = tester.getRect(find.text('localhost:'));
      final status = tester.getRect(find.text('可用 · 直连'));
      expect(status.top, greaterThan(target.bottom - 4));
      expect(status.left, lessThan(target.left));
      // The buttons stay at the right.
      expect(tester.getRect(find.text('删除')).right, greaterThan(target.right));
    });

    _t('the small note hangs under the line and can be closed', (tester) async {
      var closed = 0;
      await pumpLg(
        tester,
        _list([
          _row(
            notice: LgExitNotice(
              id: 'x',
              text: '无法访问 192.0.2.40:3306。',
              dismissLabel: '关闭',
              onDismiss: () => closed++,
            ),
          ),
        ]),
      );
      final banner = tester.getRect(find.byType(LgBanner));
      expect(banner.top, greaterThan(tester.getRect(find.text('删除')).bottom));
      // `.fl-n .bnr`: 8 px above and under, 12 at the sides, a 20 px icon.
      expect(banner.height, 44);
      await tester.tap(find.bySemanticsLabel('关闭'));
      expect(closed, 1);
    });

    _t('the status is a live region; the second line is its own', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        _list([_row(kind: LgExitStatusKind.warning, note: '远程设备不在线')]),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('可用 · 直连')),
        matchesSemantics(label: '可用 · 直连', isLiveRegion: true),
      );
      expect(find.bySemanticsLabel('远程设备不在线'), findsOneWidget);
      handle.dispose();
    });

    _t('a forward is a group named by its addresses', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, _list([_row()]));
      expect(
        find.bySemanticsLabel('127.0.0.1:2222 → localhost:22'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('端口转发'), findsOneWidget);
      handle.dispose();
    });

    _t('a long host ends in … and the port stays', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 1008,
          child: LgForwardList(
            localLabel: '本机',
            targetLabel: '目标',
            rows: [
              LgForwardRow(
                localHost: '127.0.0.1:',
                localPort: '2222',
                targetHost: '${'very-long-host-name-' * 6}.example.test:',
                targetPort: '5432',
                status: const LgExitStatus(LgExitStatusKind.direct, '可用 · 直连'),
                actions: const [],
              ),
            ],
          ),
        ),
      );
      expect(find.text('5432'), findsOneWidget);
      // The port is whole: its box is as wide as its text.
      expect(tester.getRect(find.text('5432')).right, lessThan(1008));
    });
  });

  group('LgForwardAddRow', () {
    _t('Enter in a field adds, Escape cancels', (tester) async {
      final log = <String>[];
      await pumpLg(
        tester,
        SizedBox(
          width: 976,
          child: _addRow(
            onAdd: () => log.add('add'),
            onCancel: () => log.add('cancel'),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '15432');
      // Escape in a field (the first one has the keyboard).
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(log, ['cancel']);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(log, ['cancel', 'add']);
    });

    _t('the first field takes the keyboard, "添加" is greyed', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, SizedBox(width: 976, child: _addRow()));
      await tester.pump();
      final first = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      expect(first.focusNode.hasFocus, isTrue);
      expect(find.bySemanticsLabel('本机端口'), findsOneWidget);
      expect(find.bySemanticsLabel('目标主机'), findsOneWidget);
      expect(find.bySemanticsLabel('远程端口'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('添加')),
        isSemantics(isButton: true, isEnabled: false),
      );
      handle.dispose();
    });

    _t('the ports take digits only, five at most', (tester) async {
      final local = TextEditingController();
      await pumpLg(tester, SizedBox(width: 976, child: _addRow(local: local)));
      await tester.enterText(find.byType(TextField).first, '12a3456789');
      expect(local.text, '12345');
    });

    _t('the error turns the named field red and is read with it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        SizedBox(
          width: 976,
          child: _addRow(error: '端口无效。', field: LgForwardField.remote),
        ),
      );
      expect(find.text('端口无效。'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^远程端口\n端口无效。$')), findsOneWidget);
      // The other fields are not named wrong.
      expect(find.bySemanticsLabel(RegExp('^本机端口')), findsOneWidget);
      expect(find.bySemanticsLabel('本机端口'), findsOneWidget);
      handle.dispose();
    });

    _t('the columns are those of the table; narrow drops the status '
        'column', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 1008,
          child: Column(
            children: [
              _list([_row()]),
              _addRow(onAdd: () {}),
            ],
          ),
        ),
      );
      // The target field starts where the table's target does (12 px of padding in both).
      final target = tester.getRect(find.text('localhost:')).left;
      final field = tester.getRect(find.byType(LgTextField).at(1)).left;
      expect(field, target);

      await pumpLg(tester, SizedBox(width: 656, child: _addRow(onAdd: () {})));
      final box = tester.getRect(find.byType(LgForwardAddRow));
      // Narrow: "取消" is at the row's end, not in a column of its own that is 176 wide after an
      // empty one of 280.
      expect(box.right - tester.getRect(find.text('取消')).right, lessThan(30));
    });
  });

  group('LgTunnelQuestion', () {
    _t('password: confirm and cancel at the end, Enter confirms', (
      tester,
    ) async {
      final log = <String>[];
      final area = _pw();
      await pumpLg(
        tester,
        SizedBox(
          width: 700,
          child: LgTunnelQuestion.password(
            title: '输入密码',
            password: LgExitPasswordArea(
              controller: area.controller,
              semanticLabel: '密码',
              placeholder: '密码',
              showLabel: '显示密码',
              hideLabel: '隐藏密码',
              rememberLabel: '记住密码',
              remember: false,
              onRememberChanged: (_) {},
              onSubmitted: (_) => log.add('submit'),
            ),
            confirm: _act(
              '连接',
              () => log.add('connect'),
              kind: LgButtonKind.primary,
            ),
            cancel: _act('取消', () => log.add('cancel')),
          ),
        ),
      );
      // At most 520 wide, at the left.
      final box = tester.getRect(find.byType(LgTunnelQuestion));
      expect(box.width, 700);
      final frame = tester.getRect(
        find
            .descendant(
              of: find.byType(LgTunnelQuestion),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(frame.width, lessThanOrEqualTo(700));
      expect(
        tester.getRect(find.text('连接')).right,
        lessThan(box.left + kLgTunnelQuestionMaxWidth),
      );
      await tester.tap(find.text('连接'));
      await tester.tap(find.text('取消'));
      expect(log, ['connect', 'cancel']);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(log.last, 'submit');
    });

    _t('a wrong password turns the field red', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        SizedBox(
          width: 700,
          child: LgTunnelQuestion.password(
            title: '输入密码',
            password: _pw(error: '密码错误'),
            confirm: _act('连接', () {}, kind: LgButtonKind.primary),
            cancel: _act('取消', () {}),
          ),
        ),
      );
      expect(find.text('密码错误'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^密码\n密码错误$')), findsOneWidget);
      handle.dispose();
    });

    _t('code: "验证" greyed until the code is complete', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 700,
          child: LgTunnelQuestion.code(
            title: '输入验证码',
            code: const LgExitCodeArea(
              semanticLabel: '验证码',
              trustLabel: '信任本机',
              trust: false,
            ),
            confirm: _act('验证', null, kind: LgButtonKind.primary),
            cancel: _act('取消', () {}),
          ),
        ),
      );
      expect(find.text('信任本机'), findsOneWidget);
      final verify = tester.widget<LgButton>(
        find.widgetWithText(LgButton, '验证'),
      );
      expect(verify.onPressed, isNull);
    });

    _t('busy: one line, the time after the words, "取消" at the end', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var cancelled = 0;
      await pumpLg(
        tester,
        SizedBox(
          width: 700,
          child: LgTunnelQuestion.busy(
            text: '正在等待对方接受…',
            elapsed: '（已等待 0:12）',
            cancel: _act('取消', () => cancelled++),
          ),
        ),
      );
      final text = find.textContaining('正在等待对方接受…', findRichText: true);
      expect(text, findsOneWidget);
      // One line: the words and their time are not split over two.
      expect(tester.getSize(text).height, lessThan(30));
      expect(
        tester.getRect(find.text('取消')).right,
        lessThan(tester.getRect(find.byType(LgTunnelQuestion)).left + 520),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('正在等待对方接受…（已等待 0:12）')),
        matchesSemantics(label: '正在等待对方接受…（已等待 0:12）', isLiveRegion: true),
      );
      await tester.tap(find.text('取消'));
      expect(cancelled, 1);
      handle.dispose();
    });

    _t('insecure: the answer that gives up takes the keyboard', (tester) async {
      final handle = tester.ensureSemantics();
      final log = <String>[];
      await pumpLg(
        tester,
        SizedBox(
          width: 700,
          child: LgTunnelQuestion.insecure(
            title: '未加密',
            message: '此连接未使用端到端加密。',
            confirm: _act(
              '断开',
              () => log.add('disconnect'),
              kind: LgButtonKind.primary,
              autofocus: true,
            ),
            cancel: _act('继续', () => log.add('continue')),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('未加密', findRichText: true), findsOneWidget);
      // Enter is "断开", not "继续".
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(log, ['disconnect']);
      await tester.tap(find.text('继续'));
      expect(log, ['disconnect', 'continue']);
      // A live region named by its title.
      expect(
        tester.getSemantics(find.bySemanticsLabel('未加密')),
        isSemantics(label: '未加密', isLiveRegion: true),
      );
      handle.dispose();
    });
  });

  group('LgTunnelCard', () {
    _t('the parts stand in the order of the mockup', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 1008,
          child: _card(
            question: LgTunnelQuestion.busy(
              text: '正在验证…',
              cancel: _act('取消', () {}),
            ),
            status: const LgExitStatus(LgExitStatusKind.relay, '可用 · 经中继'),
            forwards: LgForwardList(
              localLabel: '本机',
              targetLabel: '目标',
              rows: [_row()],
            ),
            addRow: _addRow(),
            notices: [
              LgExitNotice(
                id: 'n',
                text: '一条通知',
                dismissLabel: '关闭',
                onDismiss: () {},
              ),
            ],
            leading: [_act('添加端口转发', () {})],
            actions: [_act('停止', () {})],
          ),
        ),
      );
      double top(Finder f) => tester.getRect(f).top;
      final order = [
        top(find.text('书房台式机')),
        top(find.byType(LgTunnelQuestion)),
        top(find.textContaining('可用 · 经中继', findRichText: true)),
        top(find.byType(LgForwardList)),
        top(find.byType(LgForwardAddRow)),
        top(find.textContaining('一条通知', findRichText: true)),
        top(find.text('停止')),
      ];
      expect(order, [...order]..sort());
      expect(order.toSet().length, order.length);
    });

    _t('the empty note stands where the table would be', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 1008,
          child: _card(empty: '暂无端口转发', addRow: _addRow()),
        ),
      );
      expect(find.text('暂无端口转发'), findsOneWidget);
      expect(find.byType(LgForwardList), findsNothing);
      expect(
        tester.getRect(find.text('暂无端口转发')).bottom,
        lessThan(tester.getRect(find.byType(LgForwardAddRow)).top),
      );
    });

    _t('the group is named by the card and its kind', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        SizedBox(width: 1008, child: _card(empty: '暂无端口转发')),
      );
      expect(find.bySemanticsLabel('书房台式机 · TCP 隧道'), findsOneWidget);
      handle.dispose();
    });

    _t('the kind mark is a button high less 8', (tester) async {
      await pumpLg(
        tester,
        const LgTunnelKindMark(icon: LgIcons.rdp, label: 'RDP · 端口 3389'),
      );
      expect(tester.getSize(find.byType(LgTunnelKindMark)).height, 28);
      await pumpLg(
        tester,
        const LgTunnelKindMark(icon: LgIcons.rdp, label: 'RDP · 端口 3389'),
        mode: LgMode.detail,
      );
      expect(tester.getSize(find.byType(LgTunnelKindMark)).height, 24);
    });

    _t('the stack puts cards 12 px apart and shows its empty note', (
      tester,
    ) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 600,
          child: LgTunnelStack(
            children: [
              SizedBox(height: 40, key: ValueKey('a')),
              SizedBox(height: 40, key: ValueKey('b')),
            ],
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('b'))).top -
            tester.getRect(find.byKey(const ValueKey('a'))).bottom,
        LgSpace.s3,
      );
      await pumpLg(
        tester,
        const SizedBox(
          width: 600,
          child: LgTunnelStack(emptyText: '暂无正在使用的隧道', children: []),
        ),
      );
      expect(find.text('暂无正在使用的隧道'), findsOneWidget);
    });
  });

  group('the page', () {
    Widget page({bool threeLevels = true}) => SizedBox(
      width: 1040,
      height: 1200,
      child: LgExitPage(
        lede: '通过其他设备的网络访问互联网。',
        inUseTitle: '正在使用',
        inUse: const LgExitEmptyNote('暂无正在使用的出口'),
        directoryTitle: '可用的出口',
        refreshLabel: '刷新',
        onRefresh: () {},
        directory: const SizedBox(height: 20),
        byIdTitle: '按 ID 指定出口',
        byId: const SizedBox(height: 20),
        sectionTitle: threeLevels ? '出口' : null,
        sectionIcon: LgIcons.exit,
        tunnels: const LgPageSection(
          icon: LgIcons.forward,
          title: '隧道',
          lede: '将本机端口转发到远程设备。',
          children: [LgTunnelStack(emptyText: '暂无正在使用的隧道', children: [])],
        ),
      ),
    );

    _t('three levels: section, parts as small titles, tunnels', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, page());
      expect(find.text('出口'), findsOneWidget);
      expect(find.text('隧道'), findsOneWidget);
      // The lede is under the section title.
      expect(
        tester.getRect(find.text('通过其他设备的网络访问互联网。')).top,
        greaterThan(tester.getRect(find.text('出口')).bottom - 1),
      );
      // The parts are smaller than the section title and in the second colour.
      final sub = tester.widget<Text>(find.text('正在使用'));
      final section = tester.widget<Text>(find.text('出口'));
      expect(sub.style!.fontSize, lessThan(section.style!.fontSize!));
      expect(sub.style!.fontWeight, FontWeight.w700);
      // Headings for a reader, with their levels.
      expect(
        tester.getSemantics(find.text('出口')).flagsCollection.isHeader,
        isTrue,
      );
      expect(tester.getSemantics(find.text('出口')).headingLevel, 2);
      expect(tester.getSemantics(find.text('正在使用')).headingLevel, 3);
      // The second section is below a line, further down than the first.
      expect(
        tester.getRect(find.text('隧道')).top,
        greaterThan(tester.getRect(find.text('按 ID 指定出口')).bottom),
      );
      expect(find.text('暂无正在使用的隧道'), findsOneWidget);
      handle.dispose();
    });

    _t('without the section title the page is as it was', (tester) async {
      await pumpLg(tester, page(threeLevels: false));
      expect(find.text('出口'), findsNothing);
      expect(find.text('隧道'), findsNothing);
      final lede = tester.getRect(find.text('通过其他设备的网络访问互联网。'));
      final inUse = tester.getRect(find.text('正在使用'));
      expect(inUse.top - lede.bottom, greaterThanOrEqualTo(LgSpace.s6));
      final text = tester.widget<Text>(find.text('正在使用'));
      expect(text.style!.fontWeight, FontWeight.w700);
    });

    _t('a section that is not the first has a line above it', (tester) async {
      await pumpLg(
        tester,
        const SizedBox(
          width: 500,
          child: Column(
            children: [
              LgPageSection(title: '出口', first: true),
              LgPageSection(title: '隧道'),
            ],
          ),
        ),
      );
      final first = tester.getRect(find.text('出口'));
      final second = tester.getRect(find.text('隧道'));
      // 48 above the line, 1.5 for it, 24 below it.
      expect(second.top - first.bottom, greaterThan(48 + 24));
    });
  });

  group('LgRdpSettingsDialog', () {
    Widget dialog({
      String? portError,
      String? running,
      VoidCallback? onConfirm,
      VoidCallback? onCancel,
      TextEditingController? port,
    }) => LgRdpSettingsDialog(
      title: 'RDP 设置',
      deviceName: '妈妈的笔记本',
      deviceId: '234 567 891',
      portLabel: '端口',
      portController: port ?? TextEditingController(),
      portPlaceholder: '3389',
      portError: portError,
      usernameLabel: '用户名',
      usernameController: TextEditingController(),
      passwordLabel: '密码',
      passwordController: TextEditingController(),
      showPasswordLabel: '显示密码',
      hidePasswordLabel: '隐藏密码',
      runningNote: running,
      cancelLabel: '取消',
      confirmLabel: '确定',
      onCancel: onCancel ?? () {},
      onConfirm: onConfirm,
    );

    _t('the head names the dialog and the device; the tile is the '
        "device's colour with the RDP icon", (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, dialog());
      expect(find.text('RDP 设置'), findsOneWidget);
      expect(find.text('妈妈的笔记本'), findsOneWidget);
      expect(find.text('234 567 891'), findsOneWidget);
      final tile = tester.widget<LgDeviceAvatar>(find.byType(LgDeviceAvatar));
      expect(tile.icon, LgIcons.rdp);
      expect(tester.getSize(find.byType(LgDeviceAvatar)), const Size(44, 44));
      // The dialog is named by its title; the subtitle is not part of it.
      expect(find.bySemanticsLabel('RDP 设置'), findsWidgets);
      handle.dispose();
    });

    _t('the fields are named by their labels; the port asks for the '
        'keyboard', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, dialog());
      await tester.pump();
      for (final label in ['端口', '用户名', '密码']) {
        expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
      }
      final port = tester.widget<EditableText>(find.byType(EditableText).first);
      expect(port.focusNode.hasFocus, isTrue);
      handle.dispose();
    });

    _t('Enter in a field confirms, the buttons call back', (tester) async {
      final log = <String>[];
      await pumpLg(
        tester,
        dialog(
          onConfirm: () => log.add('ok'),
          onCancel: () => log.add('cancel'),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '3390');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(log, ['ok']);
      await tester.tap(find.text('取消'));
      expect(log, ['ok', 'cancel']);
    });

    _t('"确定" is greyed without a callback', (tester) async {
      await pumpLg(tester, dialog());
      final ok = tester.widget<LgButton>(find.widgetWithText(LgButton, '确定'));
      expect(ok.onPressed, isNull);
    });

    _t('the port error shows under the port field; the note under the '
        'fields only when given', (tester) async {
      await pumpLg(tester, dialog(portError: '端口无效。端口应为 1~65535。'));
      expect(find.text('端口无效。端口应为 1~65535。'), findsOneWidget);
      expect(find.byType(LgBanner), findsNothing);
      await pumpLg(tester, dialog(running: '停止后重新打开 RDP，新的设置才会生效。'));
      expect(find.text('停止后重新打开 RDP，新的设置才会生效。'), findsOneWidget);
      expect(
        tester.getRect(find.byType(LgBanner)).top,
        greaterThan(tester.getRect(find.text('密码').last).bottom),
      );
    });

    _t('the port takes digits only', (tester) async {
      final port = TextEditingController();
      await pumpLg(tester, dialog(port: port));
      await tester.enterText(find.byType(TextField).first, '33a89');
      expect(port.text, '3389');
    });
  });

  group('LgMenuRowButton', () {
    Widget menu({required List<String> log, bool greyed = false}) =>
        LgMenuAnchor(
          items: [
            LgMenuItem(
              label: 'RDP',
              icon: LgIcons.rdp,
              onPressed: greyed ? null : () => log.add('row'),
              trailing: LgMenuRowButton(
                label: '编辑 RDP 设置',
                onPressed: greyed ? null : () => log.add('pencil'),
              ),
            ),
            LgMenuItem(label: '用作出口', onPressed: () => log.add('exit')),
          ],
          builder: (context, c) => LgButton(label: '连接', onPressed: c.open),
        );

    _t('a click on the pencil does not use the row, and closes the '
        'menu', (tester) async {
      final log = <String>[];
      await pumpLg(tester, menu(log: log));
      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(LgMenuRowButton));
      await tester.pumpAndSettle();
      expect(log, ['pencil']);
      expect(find.text('用作出口'), findsNothing);
    });

    _t('a click on the row does not use the pencil', (tester) async {
      final log = <String>[];
      await pumpLg(tester, menu(log: log));
      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RDP'));
      await tester.pumpAndSettle();
      expect(log, ['row']);
    });

    _t('its own node with its own name; the row is not renamed', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final log = <String>[];
      await pumpLg(tester, menu(log: log));
      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();
      final pencil = tester.getSemantics(find.bySemanticsLabel('编辑 RDP 设置'));
      expect(
        pencil,
        isSemantics(
          label: '编辑 RDP 设置',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      // The row keeps "RDP"; it does not read "RDP 编辑 RDP 设置".
      expect(find.bySemanticsLabel('RDP'), findsOneWidget);
      // The pencil's node is not the row's node.
      expect(
        tester.getSemantics(find.bySemanticsLabel('RDP')).id,
        isNot(pencil.id),
      );
      // A screen reader presses it by its action.
      tester.semantics.tap(find.semantics.byLabel('编辑 RDP 设置'));
      await tester.pumpAndSettle();
      expect(log, ['pencil']);
      handle.dispose();
    });

    _t('the keyboard reaches it: Down enters the menu, Tab moves from the row '
        'to the pencil, Enter presses it', (tester) async {
      final log = <String>[];
      await pumpLg(tester, menu(log: log));
      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();
      bool onPencil() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<LgMenuRowButton>() !=
          null;
      Rect? focused() => FocusManager.instance.primaryFocus?.rect;
      // The first Down enters the menu, the second is at the first row ("RDP").
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final row = tester.getRect(find.widgetWithText(MenuItemButton, 'RDP'));
      expect(row.overlaps(focused()!), isTrue, reason: '${focused()} in $row');
      expect(onPencil(), isFalse);
      // Tab goes on to the pencil, which stands at the row's end.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(onPencil(), isTrue, reason: '${focused()}');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(log, ['pencil']);
    });

    _t('a greyed row has a greyed pencil that does not respond', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final log = <String>[];
      await pumpLg(tester, menu(log: log, greyed: true));
      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(LgMenuRowButton), warnIfMissed: false);
      await tester.pump();
      expect(log, isEmpty);
      expect(
        tester.getSemantics(find.bySemanticsLabel('编辑 RDP 设置')),
        isSemantics(label: '编辑 RDP 设置', isButton: true, isEnabled: false),
      );
      handle.dispose();
    });

    _t('the row has 8 px of padding after the pencil, 16 otherwise', (
      tester,
    ) async {
      final log = <String>[];
      await pumpLg(tester, menu(log: log));
      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();
      final row = tester.getRect(find.widgetWithText(MenuItemButton, 'RDP'));
      final pencil = tester.getRect(find.byType(LgMenuRowButton));
      expect(row.right - pencil.right, LgSpace.s2);
      final other = tester.getRect(find.widgetWithText(MenuItemButton, '用作出口'));
      expect(other.width, row.width);
    });
  });

  group('small additions to existing components', () {
    _t('the compact banner is 44 high with a closing button', (tester) async {
      await pumpLg(
        tester,
        SizedBox(
          width: 600,
          child: LgBanner(
            tone: LgTone.info,
            slim: true,
            compact: true,
            text: '一条通知',
            dismissLabel: '关闭',
            onDismiss: () {},
          ),
        ),
      );
      expect(tester.getSize(find.byType(LgBanner)).height, 44);
      final icon = tester.getSize(find.byType(LgIcon).first);
      expect(icon, const Size(20, 20));
      // The text is the body text, not the medium one.
      final text = tester.widget<RichText>(
        find
            .descendant(
              of: find.byType(LgBanner),
              matching: find.byType(RichText),
            )
            .first,
      );
      expect(text.text.style!.fontSize, 15);
    });

    _t('a field with the body text is as high as a dense one', (tester) async {
      await pumpLg(
        tester,
        const Column(
          children: [
            SizedBox(
              width: 200,
              child: LgTextField(dense: true, placeholder: 'a'),
            ),
            SizedBox(
              width: 200,
              child: LgTextField(dense: true, bodyText: true, placeholder: 'b'),
            ),
          ],
        ),
      );
      final fields = find.byType(LgTextField);
      expect(
        tester.getSize(fields.at(0)).height,
        tester.getSize(fields.at(1)).height,
      );
      expect(tester.getSize(fields.at(1)).height, 36);
    });

    _t('the dialog avatar can carry another icon', (tester) async {
      await pumpLg(
        tester,
        const LgDeviceAvatar(
          id: '234 567 891',
          platform: LgPlatform.unknown,
          icon: LgIcons.rdp,
        ),
      );
      final icon = tester.widget<LgIcon>(find.byType(LgIcon));
      expect(icon.icon, LgIcons.rdp);
    });
  });
}
