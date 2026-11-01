// Behaviour of the chat in the connection manager's side panel (`LgCmChat`,
// 06 §2.2): the send paths call back, a read-only chat stays inert, the newest
// message is in view, and every control and message has a name for a screen
// reader. No pixels are compared.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_chat.dart';
import 'package:leapgate_ui/widgets/lg_cm_chat.dart';
import 'package:leapgate_ui/widgets/lg_cm_frame.dart';
import 'package:leapgate_ui/widgets/lg_pressable.dart';

import 'helpers.dart';

const _talk = [
  LgChatMessage(
    text: '你好，我帮你看一下打印机。',
    time: '14:02',
    mine: false,
    sender: '李四',
  ),
  LgChatMessage(text: '好的，谢谢！', time: '14:03', mine: true),
];

/// The chat as the side panel holds it (380 × 500, its tab over it).
Widget _chat(
  TextEditingController controller,
  List<String> log, {
  List<LgChatMessage> messages = const [],
  bool readOnly = false,
  String? emptyText,
  FocusNode? focusNode,
}) => SizedBox(
  width: kLgCmSideWidth,
  height: kLgCmHeight,
  child: LgCmSidePanel(
    icon: LgIcons.chat,
    title: '聊天',
    child: LgCmChat(
      messages: messages,
      controller: controller,
      focusNode: focusNode,
      placeholder: '输入消息',
      sendLabel: '发送',
      mineLabel: '我',
      theirsLabel: '对方',
      emptyText: emptyText,
      readOnly: readOnly,
      readOnlyText: '对方已断开连接',
      onSend: (text) {
        log.add('send $text');
        controller.clear();
      },
    ),
  ),
);

/// The icon-only send button: the one pressable in the chat.
Finder get _send => find.byType(LgPressable);

/// Needs the semantics of the test to be switched on.
void _expectSendOn(WidgetTester tester, {required bool on}) => expect(
  tester.getSemantics(find.bySemanticsLabel('发送')),
  isSemantics(isButton: true, hasEnabledState: true, isEnabled: on),
);

void main() {
  group('LgCmChat sending', () {
    testWidgets('the send button is off while there is nothing to send', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final log = <String>[];
      final controller = TextEditingController();
      await pumpLg(tester, _chat(controller, log));
      _expectSendOn(tester, on: false);
      await tester.tap(_send);
      expect(log, isEmpty);
      await tester.enterText(find.byType(EditableText), '   ');
      await tester.pump();
      _expectSendOn(tester, on: false);
      await tester.tap(_send);
      expect(log, isEmpty);
      await tester.enterText(find.byType(EditableText), '收到');
      await tester.pump();
      _expectSendOn(tester, on: true);
      handle.dispose();
    });

    testWidgets('the button sends the trimmed text and the caller clears it', (
      tester,
    ) async {
      final log = <String>[];
      final controller = TextEditingController();
      await pumpLg(tester, _chat(controller, log));
      await tester.enterText(find.byType(EditableText), '  你好  ');
      await tester.pump();
      await tester.tap(_send);
      await tester.pump();
      expect(log, ['send 你好']);
      expect(controller.text, isEmpty);
    });

    testWidgets('Enter in the field sends too, an empty Enter does not', (
      tester,
    ) async {
      final log = <String>[];
      final controller = TextEditingController();
      await pumpLg(tester, _chat(controller, log));
      await tester.tap(find.byType(EditableText));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(log, isEmpty);
      await tester.enterText(find.byType(EditableText), '收到');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(log, ['send 收到']);
    });

    testWidgets('the button can be reached and used with the keyboard', (
      tester,
    ) async {
      final log = <String>[];
      final controller = TextEditingController(text: '好');
      await pumpLg(tester, _chat(controller, log));
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(log, ['send 好']);
    });
  });

  group('LgCmChat read-only', () {
    testWidgets('the input is greyed, says why, and nothing can be sent', (
      tester,
    ) async {
      final log = <String>[];
      // A draft typed before the other side left.
      final controller = TextEditingController(text: '还没发出去');
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pumpLg(
        tester,
        _chat(controller, log, readOnly: true, focusNode: focus),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
      expect(find.text('对方已断开连接'), findsOneWidget);
      expect(find.text('输入消息'), findsNothing);
      expect(find.text('还没发出去'), findsNothing);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      await tester.tap(_send);
      await tester.pump();
      expect(log, isEmpty);
      expect(controller.text, '还没发出去');
    });

    testWidgets('without a hint of its own it keeps the placeholder', (
      tester,
    ) async {
      await pumpLg(
        tester,
        SizedBox(
          width: kLgCmSideWidth,
          height: kLgCmHeight,
          child: LgCmChat(
            messages: const [],
            controller: TextEditingController(),
            placeholder: '输入消息',
            sendLabel: '发送',
            mineLabel: '我',
            theirsLabel: '对方',
            readOnly: true,
            onSend: (_) {},
          ),
        ),
      );
      expect(find.text('输入消息'), findsOneWidget);
    });

    testWidgets('the send button is off and the messages stay readable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        _chat(
          TextEditingController(text: '草稿'),
          [],
          messages: _talk,
          readOnly: true,
        ),
      );
      _expectSendOn(tester, on: false);
      expect(find.text('你好，我帮你看一下打印机。'), findsOneWidget);
      expect(find.bySemanticsLabel('李四, 14:02: 你好，我帮你看一下打印机。'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('it goes read-only and back to input in place', (tester) async {
      final log = <String>[];
      final controller = TextEditingController();
      await pumpLg(tester, _chat(controller, log, messages: _talk));
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      await pumpLg(
        tester,
        _chat(controller, log, messages: _talk, readOnly: true),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.text('对方已断开连接'), findsOneWidget);
    });
  });

  group('LgCmChat messages', () {
    testWidgets('the other person is named under the bubble, not me', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _chat(
          TextEditingController(),
          [],
          messages: const [
            LgChatMessage(text: '在吗', time: '14:02', mine: false, sender: '李四'),
            // A sender on my own message is not shown.
            LgChatMessage(text: '在', time: '14:03', mine: true, sender: '我自己'),
          ],
        ),
      );
      expect(find.text('李四'), findsOneWidget);
      expect(find.text('14:02'), findsOneWidget);
      expect(find.text('我自己'), findsNothing);
      expect(find.text('14:03'), findsOneWidget);
    });

    testWidgets('without a sender only the time is shown', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(
        tester,
        _chat(
          TextEditingController(),
          [],
          messages: const [
            LgChatMessage(text: '在吗', time: '14:02', mine: false),
            LgChatMessage(text: '在', time: '14:03', mine: true),
          ],
        ),
      );
      expect(find.text('14:02'), findsOneWidget);
      // The reader falls back to the caller's words for who wrote it.
      expect(find.bySemanticsLabel('对方, 14:02: 在吗'), findsOneWidget);
      expect(find.bySemanticsLabel('我, 14:03: 在'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a screen reader hears who, when and what', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, _chat(TextEditingController(), [], messages: _talk));
      expect(find.bySemanticsLabel('李四, 14:02: 你好，我帮你看一下打印机。'), findsOneWidget);
      expect(find.bySemanticsLabel('我, 14:03: 好的，谢谢！'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the send button and the input have names', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, _chat(TextEditingController(), []));
      expect(find.bySemanticsLabel('发送'), findsOneWidget);
      final input = tester.getSemantics(find.byType(EditableText));
      expect(input.flagsCollection.isTextField, isTrue);
      expect(input.label, contains('输入消息'));
      handle.dispose();
    });

    testWidgets('a read-only input is announced as off, with its reason', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, _chat(TextEditingController(), [], readOnly: true));
      final input = tester.getSemantics(find.byType(EditableText));
      expect(input.label, contains('对方已断开连接'));
      expect(
        input,
        isSemantics(isTextField: true, hasEnabledState: true, isEnabled: false),
      );
      handle.dispose();
    });

    testWidgets('an empty chat says so only when told to', (tester) async {
      await pumpLg(tester, _chat(TextEditingController(), []));
      expect(find.text('暂无聊天消息'), findsNothing);
      await pumpLg(
        tester,
        _chat(TextEditingController(), [], emptyText: '暂无聊天消息'),
      );
      expect(find.text('暂无聊天消息'), findsOneWidget);
      await pumpLg(
        tester,
        _chat(
          TextEditingController(),
          [],
          emptyText: '暂无聊天消息',
          messages: _talk,
        ),
      );
      expect(find.text('暂无聊天消息'), findsNothing);
    });

    testWidgets('long text wraps inside the panel, a long name is cut', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _chat(
          TextEditingController(),
          [],
          messages: [
            LgChatMessage(
              text: '很长的一句话。' * 20,
              time: '14:02',
              mine: false,
              sender: 'Alexandra Konstantinopoulos-Wang-Papadopoulos',
            ),
            LgChatMessage(
              text: 'https://example.com/${'path/' * 30}file.exe',
              time: '14:03',
              mine: true,
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      final panel = tester.getRect(find.byType(LgCmChat));
      for (final b in tester.widgetList<LgChatBubble>(
        find.byType(LgChatBubble),
      )) {
        expect(b.maxWidth, lessThanOrEqualTo(panel.width * .84));
      }
    });

    testWidgets('it works in the detailed size and in dark', (tester) async {
      await pumpLg(
        tester,
        _chat(TextEditingController(), [], messages: _talk),
        brightness: Brightness.dark,
        mode: LgMode.detail,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('李四'), findsOneWidget);
    });
  });

  group('LgCmChat scrolling', () {
    List<LgChatMessage> numbered(int from, int to) => [
      for (var i = from; i < to; i++)
        LgChatMessage(
          text: '消息 $i',
          time: '10:${10 + i % 40}',
          mine: i.isEven,
          sender: i.isEven ? null : '李四',
        ),
    ];

    bool atBottom(WidgetTester tester, String text) {
      final list = tester.getRect(find.byType(ListView));
      final last = tester.getRect(find.text(text));
      return last.bottom <= list.bottom && last.top >= list.top;
    }

    testWidgets('it opens on the newest message, not the oldest', (
      tester,
    ) async {
      await pumpLg(
        tester,
        _chat(TextEditingController(), [], messages: numbered(0, 40)),
      );
      await tester.pump();
      await tester.pump();
      expect(atBottom(tester, '消息 39'), isTrue);
      expect(find.text('消息 0'), findsNothing);
    });

    testWidgets('a new message scrolls the list to the end', (tester) async {
      final controller = TextEditingController();
      await pumpLg(tester, _chat(controller, [], messages: numbered(0, 30)));
      await pumpLg(tester, _chat(controller, [], messages: numbered(0, 31)));
      await tester.pump();
      await tester.pump();
      expect(atBottom(tester, '消息 30'), isTrue);
    });

    testWidgets('a list that keeps only the last N still follows the end', (
      tester,
    ) async {
      final controller = TextEditingController();
      await pumpLg(tester, _chat(controller, [], messages: numbered(0, 40)));
      await tester.pump();
      await tester.pump();
      // The user reads upwards.
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pump();
      expect(find.text('消息 39'), findsNothing);
      // The model drops the oldest and appends one: the count is the same.
      await pumpLg(tester, _chat(controller, [], messages: numbered(1, 41)));
      await tester.pump();
      await tester.pump();
      expect(atBottom(tester, '消息 40'), isTrue);
    });
  });

  group('LgChatMessage', () {
    test('the sender is part of what makes two messages equal', () {
      const a = LgChatMessage(text: 'x', time: '1', mine: false, sender: '李四');
      const same = LgChatMessage(
        text: 'x',
        time: '1',
        mine: false,
        sender: '李四',
      );
      const other = LgChatMessage(text: 'x', time: '1', mine: false);
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(other));
    });
  });
}
