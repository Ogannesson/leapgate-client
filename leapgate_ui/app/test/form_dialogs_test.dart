import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_add_device_dialog.dart';
import 'package:leapgate_ui/widgets/lg_banner.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_feedback.dart';
import 'package:leapgate_ui/widgets/lg_form_dialog.dart';
import 'package:leapgate_ui/widgets/lg_login_dialog.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';
import 'package:leapgate_ui/widgets/lg_tag_chips.dart';
import 'package:leapgate_ui/widgets/lg_text_field.dart';

import 'helpers.dart';

const _loginLabels = LgLoginDialogLabels(
  title: '登录',
  usernameLabel: '用户名',
  usernamePlaceholder: '输入用户名',
  passwordLabel: '密码',
  passwordPlaceholder: '输入密码',
  showPassword: '显示密码',
  hidePassword: '隐藏密码',
  cancel: '取消',
  submit: '登录',
  busySubmit: '正在登录…',
  retry: '重试',
);

const _addLabels = LgAddDeviceLabels(
  title: '添加设备',
  idLabel: 'ID',
  idPlaceholder: '输入设备 ID',
  aliasLabel: '别名',
  aliasPlaceholder: '输入别名',
  passwordLabel: '密码',
  passwordPlaceholder: '输入密码',
  showPassword: '显示密码',
  hidePassword: '隐藏密码',
  noteLabel: '备注',
  notePlaceholder: '最多 300 字',
  tagsLabel: '标签',
  cancel: '取消',
  submit: '添加',
  busySubmit: '正在添加…',
);

Future<void> _tall(WidgetTester tester, Widget child, {LgMode? mode}) {
  tester.view.physicalSize = const Size(1280, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return pumpLg(tester, child, mode: mode ?? LgMode.compact);
}

void main() {
  group('LgLoginDialog', () {
    late TextEditingController user;
    late TextEditingController pass;
    late List<String> calls;

    setUp(() {
      user = TextEditingController(text: 'zhangsan');
      pass = TextEditingController();
      calls = [];
    });

    Widget dialog({
      String? userError,
      String? passError,
      String? loadError,
      bool busy = false,
      bool canSubmit = true,
    }) => LgLoginDialog(
      labels: _loginLabels,
      usernameController: user,
      passwordController: pass,
      usernameError: userError,
      passwordError: passError,
      loadError: loadError,
      onRetry: loadError == null ? null : () => calls.add('retry'),
      busy: busy,
      onSubmit: canSubmit ? () => calls.add('submit') : null,
      onCancel: () => calls.add('cancel'),
    );

    testWidgets('has the title, two labelled fields and two buttons', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _tall(tester, dialog());
      expect(find.bySemanticsLabel('登录'), findsWidgets);
      expect(find.text('用户名'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
      expect(find.bySemanticsLabel('用户名'), findsOneWidget);
      expect(find.bySemanticsLabel('密码'), findsOneWidget);
      await tester.tap(find.widgetWithText(LgButton, '取消'));
      await tester.tap(find.widgetWithText(LgButton, '登录'));
      expect(calls, ['cancel', 'submit']);
      handle.dispose();
    });

    testWidgets('the key goes to the password when the user name is there, '
        'and Enter in a field logs in', (tester) async {
      await _tall(tester, dialog());
      await tester.pump();
      final passField = tester.widget<EditableText>(
        find.byType(EditableText).last,
      );
      expect(passField.focusNode.hasFocus, isTrue);
      await tester.enterText(find.byType(TextField).last, 'secret');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, ['submit']);
    });

    testWidgets('an empty user name has the key first', (tester) async {
      user.clear();
      await _tall(tester, dialog());
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isTrue,
      );
    });

    testWidgets('errors stand under the field they are about', (tester) async {
      await _tall(tester, dialog(userError: '请输入用户名', passError: '用户名或密码错误'));
      final userError = tester.getTopLeft(find.text('请输入用户名')).dy;
      final passLabel = tester.getTopLeft(find.text('密码')).dy;
      final passError = tester.getTopLeft(find.text('用户名或密码错误')).dy;
      expect(userError, lessThan(passLabel));
      expect(passError, greaterThan(passLabel));
      // In a dialog the line is regular, not bold.
      expect(
        tester.widget<Text>(find.text('用户名或密码错误')).style?.fontWeight ??
            DefaultTextStyle.of(
              tester.element(find.text('用户名或密码错误')),
            ).style.fontWeight,
        FontWeight.w400,
      );
    });

    testWidgets('busy: the button turns, the fields and Enter are still', (
      tester,
    ) async {
      pass.text = 'secret';
      await _tall(tester, dialog(busy: true));
      expect(find.text('正在登录…'), findsOneWidget);
      expect(find.byType(LgSpinner), findsOneWidget);
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((f) => f.enabled == false),
        isTrue,
      );
      await tester.tap(find.text('正在登录…'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, isEmpty);
      // Cancelling stays possible.
      await tester.tap(find.widgetWithText(LgButton, '取消'));
      expect(calls, ['cancel']);
    });

    testWidgets('no login options: a banner with a retry, the form greyed', (
      tester,
    ) async {
      await _tall(tester, dialog(loadError: '无法获取登录选项。请检查网络连接。'));
      expect(find.text('无法获取登录选项。请检查网络连接。'), findsOneWidget);
      await tester.tap(find.widgetWithText(LgButton, '重试'));
      expect(calls, ['retry']);
      expect(
        tester.widget<LgButton>(find.widgetWithText(LgButton, '登录')).onPressed,
        isNull,
      );
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((f) => f.enabled == false),
        isTrue,
      );
      await tester.tap(find.byType(TextField).last, warnIfMissed: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, ['retry']);
    });

    testWidgets('a disabled field keeps the white ground of the dialog', (
      tester,
    ) async {
      await _tall(tester, dialog(busy: true));
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(LgTextField).first,
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(
        decoration.color,
        LgTokens.of(
          tester.element(find.byType(LgTextField).first),
        ).colors.surface,
      );
    });

    testWidgets('English labels and the detail mode fit', (tester) async {
      await _tall(
        tester,
        LgLoginDialog(
          labels: const LgLoginDialogLabels(
            title: 'Sign in',
            usernameLabel: 'Username',
            usernamePlaceholder: 'Enter your username',
            passwordLabel: 'Password',
            passwordPlaceholder: 'Enter your password',
            showPassword: 'Show password',
            hidePassword: 'Hide password',
            cancel: 'Cancel',
            submit: 'Sign in',
            busySubmit: 'Signing in…',
            retry: 'Retry',
          ),
          usernameController: user,
          passwordController: pass,
          loadError: 'Could not get the sign-in options. Check your network.',
          onRetry: () {},
          onSubmit: () {},
          onCancel: () {},
        ),
        mode: LgMode.detail,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('LgAddDeviceDialog', () {
    late TextEditingController id;
    late TextEditingController alias;
    late TextEditingController password;
    late TextEditingController note;
    late List<String> calls;

    setUp(() {
      id = TextEditingController(text: '246 813 579');
      alias = TextEditingController();
      password = TextEditingController();
      note = TextEditingController();
      calls = [];
    });

    List<LgTagToggleItem> tags({Set<String> on = const {}}) => [
      LgTagToggleItem(
        id: 'home',
        label: '家里',
        color: const Color(0xFFA65B80),
        on: on.contains('home'),
      ),
      LgTagToggleItem(
        id: 'work',
        label: '工作',
        color: const Color(0xFF2F7FB0),
        on: on.contains('work'),
      ),
    ];

    Widget dialog({
      bool shared = true,
      String? idError,
      String? error,
      bool busy = false,
      Set<String> on = const {},
      bool canSubmit = true,
    }) => LgAddDeviceDialog(
      labels: _addLabels,
      target: '添加到：家里的电脑',
      idController: id,
      aliasController: alias,
      passwordController: shared ? password : null,
      passwordHint: shared ? '这些内容对此地址簿的其他成员可见' : null,
      noteController: note,
      tags: tags(on: on),
      onToggleTag: (t) => calls.add('tag $t'),
      idError: idError,
      error: error,
      busy: busy,
      onSubmit: canSubmit ? () => calls.add('add') : null,
      onCancel: () => calls.add('cancel'),
    );

    testWidgets('has the five fields, the target and the tags', (tester) async {
      await _tall(tester, dialog());
      expect(find.text('添加到：家里的电脑'), findsOneWidget);
      for (final label in ['ID', '别名', '密码', '备注', '标签']) {
        expect(find.textContaining(label), findsWidgets);
      }
      expect(find.text('这些内容对此地址簿的其他成员可见'), findsOneWidget);
      expect(find.text('家里'), findsOneWidget);
      expect(find.text('工作'), findsOneWidget);
      expect(find.text('0 / 300'), findsOneWidget);
    });

    testWidgets('ID is marked as required', (tester) async {
      await _tall(tester, dialog());
      final label = tester.widget<RichText>(
        find
            .descendant(
              of: find.byType(LgFormField).first,
              matching: find.byType(RichText),
            )
            .first,
      );
      expect(label.text.toPlainText(), 'ID*');
    });

    testWidgets('a personal book has no password field', (tester) async {
      await _tall(tester, dialog(shared: false));
      expect(find.text('密码'), findsNothing);
      expect(find.text('这些内容对此地址簿的其他成员可见'), findsNothing);
    });

    testWidgets('the counter follows the note and the note stops at 300', (
      tester,
    ) async {
      await _tall(tester, dialog());
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == '最多 300 字',
        ),
        '放在阳台',
      );
      await tester.pump();
      expect(find.text('4 / 300'), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == '最多 300 字',
        ),
        '字' * 400,
      );
      await tester.pump();
      expect(note.text.length, 300);
      expect(find.text('300 / 300'), findsOneWidget);
    });

    testWidgets('Enter in the note is a new line, in the ID it adds', (
      tester,
    ) async {
      await _tall(tester, dialog());
      final noteField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '最多 300 字',
      );
      await tester.tap(noteField);
      await tester.enterText(noteField, 'a');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, isEmpty);
      await tester.tap(find.byType(TextField).first);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, ['add']);
    });

    testWidgets('tags toggle and report their id; the buttons answer', (
      tester,
    ) async {
      await _tall(tester, dialog(on: const {'home'}));
      await tester.tap(find.text('工作'));
      await tester.tap(find.text('家里'));
      await tester.tap(find.widgetWithText(LgButton, '取消'));
      await tester.tap(find.widgetWithText(LgButton, '添加'));
      expect(calls, ['tag work', 'tag home', 'cancel', 'add']);
    });

    testWidgets('the add button is grey without a handler', (tester) async {
      await _tall(tester, dialog(canSubmit: false));
      expect(
        tester.widget<LgButton>(find.widgetWithText(LgButton, '添加')).onPressed,
        isNull,
      );
    });

    testWidgets('a duplicate ID is told under the ID field', (tester) async {
      await _tall(tester, dialog(idError: '该 ID 已在此地址簿中'));
      expect(find.text('该 ID 已在此地址簿中'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('该 ID 已在此地址簿中')).dy,
        lessThan(tester.getTopLeft(find.text('别名')).dy),
      );
    });

    testWidgets('a banner tells what the server said, the dialog stays', (
      tester,
    ) async {
      await _tall(tester, dialog(error: '已达到此地址簿的设备数量上限'));
      expect(find.text('已达到此地址簿的设备数量上限'), findsOneWidget);
      expect(find.byType(LgBanner), findsOneWidget);
      expect(find.widgetWithText(LgButton, '添加'), findsOneWidget);
    });

    testWidgets('busy: every field, the tags and Enter are still', (
      tester,
    ) async {
      await _tall(tester, dialog(busy: true, on: const {'home'}));
      expect(find.text('正在添加…'), findsOneWidget);
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((f) => f.enabled == false),
        isTrue,
      );
      await tester.tap(find.text('工作'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, isEmpty);
      await tester.tap(find.widgetWithText(LgButton, '取消'));
      expect(calls, ['cancel']);
    });

    testWidgets('fits in the detail mode with a long alias', (tester) async {
      alias.text = 'A very long alias that goes on and on' * 3;
      await _tall(tester, dialog(), mode: LgMode.detail);
      expect(tester.takeException(), isNull);
    });
  });

  group('LgFormDialog shell', () {
    testWidgets('the title names the dialog and the buttons keep their order', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final calls = <String>[];
      await _tall(
        tester,
        LgFormDialog(
          title: '重命名标签',
          icon: LgIcons.tag,
          width: 400,
          actions: [
            LgDialogAction(label: '取消', onPressed: () => calls.add('cancel')),
            LgDialogAction(
              label: '保存',
              kind: LgButtonKind.primary,
              isDefault: true,
              onPressed: () => calls.add('save'),
            ),
          ],
          children: [
            LgFormField(
              label: '标签名称',
              required: true,
              hint: '最多 20 个字符',
              child: LgTextField(
                controller: TextEditingController(text: '家里'),
                semanticLabel: '标签名称',
              ),
            ),
          ],
        ),
      );
      expect(find.bySemanticsLabel('重命名标签'), findsWidgets);
      expect(find.text('最多 20 个字符'), findsOneWidget);
      expect(
        tester.getTopLeft(find.widgetWithText(LgButton, '取消')).dx,
        lessThan(tester.getTopLeft(find.widgetWithText(LgButton, '保存')).dx),
      );
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, ['save']);
      handle.dispose();
    });

    testWidgets('a text area is a field of several lines of its own height', (
      tester,
    ) async {
      final c = TextEditingController();
      await _tall(
        tester,
        LgFormDialog(
          title: '编辑备注',
          icon: LgIcons.note,
          actions: const [LgDialogAction(label: '取消', onPressed: null)],
          children: [
            LgFormField(
              label: '备注',
              counter: '0 / 300',
              child: LgTextArea(
                controller: c,
                placeholder: '最多 300 字',
                maxLength: 300,
                semanticLabel: '备注',
              ),
            ),
          ],
        ),
      );
      expect(tester.getSize(find.byType(LgTextArea)).height, 72);
      await tester.enterText(find.byType(TextField), '第一行\n第二行');
      expect(c.text, '第一行\n第二行');
    });
  });
}
