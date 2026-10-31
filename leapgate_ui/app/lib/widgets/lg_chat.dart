// The chat panel of a session (01 §3.2 block F; `u-chat` in A-P2.html): a card
// that floats over the picture, moved by its title, with the messages, the
// input and "发送". The voice call states are on the toolbar's chat button and
// its menu (`LgToolbarMenuButton.state`), not here.
//
// The panel only draws: the messages, the text controller and what "发送" does
// are the caller's. Put it in a `Positioned` and move it with [onDrag].

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_text_field.dart';

/// One message: the text, the time as written ("10:24") and whether this
/// computer sent it. Two messages with the same three values are equal.
@immutable
class LgChatMessage {
  const LgChatMessage({
    required this.text,
    required this.time,
    required this.mine,
  });

  final String text;
  final String time;
  final bool mine;

  @override
  bool operator ==(Object other) =>
      other is LgChatMessage &&
      other.text == text &&
      other.time == time &&
      other.mine == mine;

  @override
  int get hashCode => Object.hash(text, time, mine);
}

class LgChatPanel extends StatefulWidget {
  const LgChatPanel({
    super.key,
    required this.title,
    required this.messages,
    required this.controller,
    required this.placeholder,
    required this.sendLabel,
    required this.closeLabel,
    required this.mineLabel,
    required this.theirsLabel,
    required this.onSend,
    required this.onClose,
    this.onDrag,
    this.emptyText,
    this.focusNode,
    this.width = 360,
    this.listHeight = 230,
  });

  /// "聊天".
  final String title;
  final List<LgChatMessage> messages;
  final TextEditingController controller;
  final String placeholder;
  final String sendLabel;
  final String closeLabel;

  /// Who wrote a message, for a screen reader ("我", "对方").
  final String mineLabel;
  final String theirsLabel;

  /// Called with the text when "发送" or Enter is used and the text is not
  /// empty; the caller sends it and clears the controller.
  final ValueChanged<String> onSend;
  final VoidCallback onClose;

  /// How far the pointer moved while the title was dragged.
  final ValueChanged<Offset>? onDrag;

  /// Shown in the list while there are no messages.
  final String? emptyText;
  final FocusNode? focusNode;
  final double width;
  final double listHeight;

  @override
  State<LgChatPanel> createState() => _LgChatPanelState();
}

class _LgChatPanelState extends State<LgChatPanel> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _toEnd();
  }

  @override
  void didUpdateWidget(LgChatPanel old) {
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
    if (text.isEmpty) return;
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final w = widget;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: w.title,
      child: Container(
        width: w.width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.float,
          borderRadius: BorderRadius.circular(LgRadius.r20),
          boxShadow: c.shadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: w.onDrag == null ? null : (d) => w.onDrag!(d.delta),
              child: Container(
                height: t.sizes.row,
                padding: const EdgeInsets.only(
                  left: LgSpace.s5,
                  right: LgSpace.s2,
                ),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          w.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textN.copyWith(
                            color: c.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    LgIconButton(
                      icon: LgIcons.x,
                      label: w.closeLabel,
                      onPressed: w.onClose,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: w.listHeight,
              child: w.messages.isEmpty
                  ? Center(
                      child: w.emptyText == null
                          ? null
                          : Padding(
                              padding: const EdgeInsets.all(LgSpace.s4),
                              child: Text(
                                w.emptyText!,
                                textAlign: TextAlign.center,
                                style: t.textM.copyWith(color: c.text2),
                              ),
                            ),
                    )
                  : ListView.separated(
                      controller: _scroll,
                      padding: const EdgeInsets.all(LgSpace.s4),
                      itemCount: w.messages.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: LgSpace.s4),
                      itemBuilder: (context, i) => _Bubble(
                        message: w.messages[i],
                        who: w.messages[i].mine ? w.mineLabel : w.theirsLabel,
                        maxWidth: (w.width - 2 * LgSpace.s4) * .82,
                      ),
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(
                LgSpace.s4,
                LgSpace.s3,
                LgSpace.s3,
                LgSpace.s3,
              ),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: LgTextField(
                      controller: w.controller,
                      focusNode: w.focusNode,
                      placeholder: w.placeholder,
                      semanticLabel: w.placeholder,
                      dense: true,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: LgSpace.s2),
                  ListenableBuilder(
                    listenable: w.controller,
                    builder: (context, _) => LgButton(
                      label: w.sendLabel,
                      kind: LgButtonKind.primary,
                      onPressed: w.controller.text.trim().isEmpty
                          ? null
                          : _send,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.who,
    required this.maxWidth,
  });

  final LgChatMessage message;
  final String who;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final mine = message.mine;
    return Semantics(
      container: true,
      label: '$who, ${message.time}: ${message.text}',
      child: ExcludeSemantics(
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LgSpace.s4,
                    vertical: LgSpace.s2,
                  ),
                  decoration: BoxDecoration(
                    color: mine ? c.accent : c.surface2,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(LgRadius.r16),
                      topRight: const Radius.circular(LgRadius.r16),
                      bottomLeft: Radius.circular(
                        mine ? LgRadius.r16 : LgRadius.r6,
                      ),
                      bottomRight: Radius.circular(
                        mine ? LgRadius.r6 : LgRadius.r16,
                      ),
                    ),
                  ),
                  child: Text(
                    message.text,
                    style: t.text.copyWith(color: mine ? c.onAccent : c.text),
                  ),
                ),
                const SizedBox(height: LgSpace.s1),
                Text(message.time, style: t.textS.copyWith(color: c.text2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
