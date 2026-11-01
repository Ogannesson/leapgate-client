// The chat of the connection manager (CM), drawn inside its side panel
// (`LgCmSidePanel`, 01 §3.3 "聊天侧栏"; `.msgs`, `.compose` in A-P3.html): the
// messages over the whole height, the input and a send button with an icon only
// at the bottom. Unlike the session's floating [LgChatPanel] it has no title,
// no close button and no shadow; the side panel's tab is its title.
//
// The panel only draws: the messages, the text controller and what sending
// does are the caller's.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_chat.dart';
import 'lg_pressable.dart';
import 'lg_text_field.dart';
import 'lg_tooltip.dart';

/// The messages (newest at the bottom, the list follows new ones) and the
/// input. With [readOnly] (the other side has left) the input is greyed and
/// shows [readOnlyText], and nothing can be sent.
class LgCmChat extends StatefulWidget {
  const LgCmChat({
    super.key,
    required this.messages,
    required this.controller,
    required this.placeholder,
    required this.sendLabel,
    required this.mineLabel,
    required this.theirsLabel,
    required this.onSend,
    this.focusNode,
    this.emptyText,
    this.readOnly = false,
    this.readOnlyText,
  });

  /// Oldest first. Set [LgChatMessage.sender] to show the name of who wrote a
  /// message under the other person's bubble.
  final List<LgChatMessage> messages;
  final TextEditingController controller;

  /// "输入消息".
  final String placeholder;

  /// The name of the icon-only send button ("发送"), also its hover tip.
  final String sendLabel;

  /// Who wrote a message, for a screen reader ("我", "对方"); a message with a
  /// sender is announced with the name instead of [theirsLabel].
  final String mineLabel;
  final String theirsLabel;

  /// Called with the trimmed text when the button or Enter is used and the text
  /// is not empty; the caller sends it and clears the controller.
  final ValueChanged<String> onSend;
  final FocusNode? focusNode;

  /// Shown in the list while there are no messages ("暂无聊天消息"); without
  /// it the list is blank.
  final String? emptyText;

  /// The other side has left: the input is greyed, the send button is off.
  final bool readOnly;

  /// What the greyed input says ("对方已断开连接"); [placeholder] when null. A
  /// draft in [controller] is not shown while read-only.
  final String? readOnlyText;

  @override
  State<LgCmChat> createState() => _LgCmChatState();
}

class _LgCmChatState extends State<LgCmChat> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _toEnd();
  }

  @override
  void didUpdateWidget(LgCmChat old) {
    super.didUpdateWidget(old);
    // The caller may keep only the last N messages, so the count can stay the
    // same while the list moves on: look at the last one too.
    final before = old.messages;
    final now = widget.messages;
    if (before.length != now.length ||
        (now.isNotEmpty && before.last != now.last)) {
      _toEnd();
    }
  }

  // Open at the newest message and follow new ones. The extent of a long list
  // is an estimate until its end has been laid out, so go on until the jump
  // lands (each jump schedules the next frame itself).
  void _toEnd([int again = 3]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (_scroll.position.pixels == end) return;
      _scroll.jumpTo(end);
      if (again > 0) _toEnd(again - 1);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = widget.controller.text.trim();
    if (text.isEmpty || widget.readOnly) return;
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: w.messages.isEmpty
                ? _Empty(text: w.emptyText)
                : LayoutBuilder(
                    builder: (context, box) => ListView.separated(
                      controller: _scroll,
                      // `.msgs`: 20 over the first message, 16 elsewhere.
                      padding: const EdgeInsets.fromLTRB(
                        LgSpace.s4,
                        LgSpace.s5,
                        LgSpace.s4,
                        LgSpace.s4,
                      ),
                      itemCount: w.messages.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: LgSpace.s4),
                      itemBuilder: (context, i) => LgChatBubble(
                        message: w.messages[i],
                        who: w.messages[i].mine ? w.mineLabel : w.theirsLabel,
                        // `.msg`: at most 84 % of the list inside its padding.
                        maxWidth: (box.maxWidth - 2 * LgSpace.s4) * .84,
                        // `.bub`: 10 and 14, a little roomier than the
                        // session panel's bubble.
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        showSender: true,
                      ),
                    ),
                  ),
          ),
          Padding(
            // `.compose`
            padding: const EdgeInsets.fromLTRB(
              LgSpace.s4,
              LgSpace.s3,
              LgSpace.s4,
              LgSpace.s4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: w.readOnly
                      // No controller: the greyed field shows the hint, not
                      // what was typed before the other side left.
                      ? LgTextField(
                          enabled: false,
                          focusNode: w.focusNode,
                          placeholder: w.readOnlyText ?? w.placeholder,
                          semanticLabel: w.readOnlyText ?? w.placeholder,
                        )
                      : LgTextField(
                          controller: w.controller,
                          focusNode: w.focusNode,
                          placeholder: w.placeholder,
                          semanticLabel: w.placeholder,
                          onSubmitted: (_) => _send(),
                        ),
                ),
                const SizedBox(width: LgSpace.s2),
                ListenableBuilder(
                  listenable: w.controller,
                  builder: (context, _) => _SendButton(
                    label: w.sendLabel,
                    onPressed: w.readOnly || w.controller.text.trim().isEmpty
                        ? null
                        : _send,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// No message yet: a quiet icon and [text], like the file record panel's.
class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      container: true,
      label: text,
      child: ExcludeSemantics(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(LgSpace.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(LgRadius.r12),
                  ),
                  child: LgIcon(LgIcons.chat, size: 24, color: c.text2),
                ),
                const SizedBox(height: LgSpace.s3),
                Text(
                  text!,
                  textAlign: TextAlign.center,
                  style: t.text.copyWith(color: c.text2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.compose .btn.pri.h48`: a square primary button, as high as the input,
/// with the send icon only. Off it takes the greyed ground of `.btn.dis`.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final side = t.sizes.main;
    final radius = BorderRadius.circular(LgRadius.r12);
    return LgTooltip(
      message: label,
      child: LgPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, states) {
          final disabled = states.contains(WidgetState.disabled);
          final ground = disabled ? c.disabled : c.accent;
          final overlay = lgStateOverlay(c, states);
          return LgFocusRing(
            show: states.contains(WidgetState.focused),
            radius: radius,
            child: Container(
              width: side,
              height: side,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: overlay == null
                    ? ground
                    : Color.alphaBlend(overlay, ground),
                borderRadius: radius,
              ),
              child: LgIcon(
                LgIcons.send,
                size: t.sizes.icon,
                color: disabled ? c.text2 : c.onAccent,
              ),
            ),
          );
        },
      ),
    );
  }
}
