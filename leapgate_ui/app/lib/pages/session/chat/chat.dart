import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/chat_model.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_menu.dart';
import '../../../widgets/lg_session_toolbar.dart';
import '../../../widgets/lg_text_field.dart';

/// Chat and voice calls (01 P2 block F). The toolbar places [chatToolbarButtons] after the
/// "会话" menu; the session page stacks [ChatLayer] above the notices (01 P2 block C).
///
/// One button whose menu follows the voice call (upstream had a chat menu and a separate voice
/// call button, `desktop/widgets/remote_toolbar.dart` `_ChatMenu`, `_VoiceCallMenu`): text chat
/// and voice call; while waiting for an answer "等待接听…" with "取消"; in a call "通话中" with
/// the microphones and "挂断" (`u-voice-wait`, `u-voice-call`).
List<Widget> chatToolbarButtons(
  BuildContext context,
  FFI ffi,
  TabOverlays overlays,
) =>
    [_ChatButton(chat: ffi.chatModel)];

/// The chat and voice call shortcuts (upstream `shortcut_model.dart:455-474`): text chat opens
/// or closes the panel as "文字聊天" does; voice call hangs up or cancels while one is waiting or
/// on, and asks for one otherwise.
void registerChatShortcuts(FFI ffi) {
  final chat = ffi.chatModel;
  ffi.shortcutModel
    ..register(kShortcutActionToggleChat, () => chat.setOpen(!chat.open))
    ..register(kShortcutActionToggleVoiceCall, () {
      switch (chat.voiceCallStatus) {
        case VoiceCallStatus.connected:
        case VoiceCallStatus.waitingForResponse:
          chat.closeVoiceCall();
        case VoiceCallStatus.notStarted:
        case VoiceCallStatus.incoming:
          chat.requestVoiceCall();
      }
    });
}

class _ChatButton extends StatelessWidget {
  const _ChatButton({required this.chat});

  final ChatModel chat;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        // The number is a stand-in for the designer's badge.
        final unread = chat.unread;
        String withUnread(String label) =>
            unread > 0 ? '$label $unread' : label;
        final textChat = LgMenuItem(
          label: l10n.chatText,
          checked: chat.open,
          onPressed: () => chat.setOpen(!chat.open),
        );
        switch (chat.voiceCallStatus) {
          case VoiceCallStatus.waitingForResponse:
            return LgToolbarMenuButton(
              label: withUnread(l10n.chatWaitingAnswer),
              icon: LgIcons.call,
              items: [
                LgMenuItem(label: l10n.connCancel, onPressed: chat.closeVoiceCall),
              ],
            );
          case VoiceCallStatus.connected:
            // Text chat stays at hand during a call, as upstream's separate chat menu.
            return LgToolbarMenuButton(
              label: withUnread(l10n.chatInCall),
              icon: LgIcons.call,
              items: [
                textChat,
                LgMenuGroup(l10n.chatMicrophone),
                _Microphones(chat: chat),
                LgMenuItem(
                  label: l10n.chatHangUp,
                  icon: LgIcons.callEnd,
                  danger: true,
                  onPressed: chat.closeVoiceCall,
                ),
              ],
            );
          case VoiceCallStatus.notStarted:
          case VoiceCallStatus.incoming:
            return LgToolbarMenuButton(
              label: withUnread(l10n.chatMenu),
              icon: LgIcons.chat,
              items: [
                textChat,
                LgMenuItem(
                    label: l10n.chatVoiceCall,
                    onPressed: chat.requestVoiceCall),
              ],
            );
        }
      },
    );
  }
}

/// The microphones of the call; "系统声音" first where it can be used (upstream `AudioInput`).
class _Microphones extends StatefulWidget {
  const _Microphones({required this.chat});

  final ChatModel chat;

  @override
  State<_Microphones> createState() => _MicrophonesState();
}

class _MicrophonesState extends State<_Microphones> {
  VoiceInputs? _inputs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inputs = await widget.chat.voiceInputs();
    if (mounted) setState(() => _inputs = inputs);
  }

  Future<void> _choose(String device) async {
    await widget.chat.setVoiceInput(device);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final inputs = _inputs;
    if (inputs == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (inputs.loopback)
          LgMenuItem(
            label: l10n.chatSystemSound,
            checked: inputs.current.isEmpty,
            onPressed: () => _choose(''),
          ),
        for (final d in inputs.devices)
          LgMenuItem(
            label: d,
            checked: inputs.current == d,
            onPressed: () => _choose(d),
          ),
      ],
    );
  }
}

/// The chat panel over the image (01 P2 block F, `u-chat`): shown while [ChatModel.open], below
/// the toolbar until dragged. Messages from the remote device open it without taking the
/// keyboard from the image; "文字聊天" opens it with the focus in the input. While its tab shows,
/// what came is read. A stand-in for the designer's `LgChatPanel`.
class ChatLayer extends StatefulWidget {
  const ChatLayer({super.key, required this.ffi});

  final FFI ffi;

  @override
  State<ChatLayer> createState() => _ChatLayerState();
}

class _ChatLayerState extends State<ChatLayer> {
  static const _width = 320.0;
  static const _height = 400.0;

  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  Offset? _position;
  var _wasOpen = false;
  var _count = 0;

  ChatModel get _chat => widget.ffi.chatModel;

  @override
  void initState() {
    super.initState();
    _chat.addListener(_onChat);
  }

  @override
  void dispose() {
    _chat.removeListener(_onChat);
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _readIfShown();
  }

  /// After the frame: marking read rebuilds this layer. The tab's ticker mode is read first, so
  /// its changes always come here.
  void _readIfShown() {
    final shown = TickerMode.valuesOf(context).enabled;
    if (shown && _chat.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _chat.markRead());
    }
  }

  void _onChat() {
    final open = _chat.open;
    final count = _chat.messages.length;
    // Opened without a new message: the user opened it from the menu.
    if (open && !_wasOpen && count == _count) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _inputFocus.context != null) _inputFocus.requestFocus();
      });
    }
    _wasOpen = open;
    _count = count;
    if (mounted) setState(() {});
  }

  void _send() {
    if (_chat.send(_input.text)) _input.clear();
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (!_chat.open) return const SizedBox.shrink();
    final t = LgTokens.of(context);
    final c = t.colors;
    final l10n = AppLocalizations.of(context)!;
    return LayoutBuilder(builder: (context, box) {
      final pos = _position ??
          Offset((box.maxWidth - _width) / 2 + 120,
              LgSpace.s3 + t.sizes.bar + LgSpace.s2);
      return Stack(children: [
        Positioned(
          left: pos.dx.clamp(0, (box.maxWidth - _width).clamp(0, double.infinity)),
          top: pos.dy.clamp(0, (box.maxHeight - _height).clamp(0, double.infinity)),
          width: _width,
          height: _height,
          child: Material(
            color: c.float,
            elevation: 8,
            borderRadius: BorderRadius.circular(LgRadius.r16),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              GestureDetector(
                onPanUpdate: (d) => setState(() => _position = pos + d.delta),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.only(left: LgSpace.s4),
                  child: Row(children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(l10n.chatMenu,
                            style: t.text.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    LgIconButton(
                      icon: LgIcons.x,
                      label: l10n.chatClose,
                      onPressed: () => _chat.setOpen(false),
                    ),
                  ]),
                ),
              ),
              Expanded(
                child: ListView(
                  reverse: true,
                  padding: const EdgeInsets.all(LgSpace.s3),
                  children: [
                    for (final m in _chat.messages.reversed) _bubble(t, m),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(LgSpace.s3),
                child: Row(children: [
                  Expanded(
                    child: LgTextField(
                      controller: _input,
                      focusNode: _inputFocus,
                      placeholder: l10n.chatPlaceholder,
                      semanticLabel: l10n.chatPlaceholder,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: LgSpace.s2),
                  LgButton(
                    label: l10n.chatSend,
                    kind: LgButtonKind.primary,
                    onPressed: _send,
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]);
    });
  }

  Widget _bubble(LgTokens t, ChatMessage m) {
    final c = t.colors;
    String two(int v) => v.toString().padLeft(2, '0');
    return Align(
      alignment: m.isOut ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: LgSpace.s1),
        padding: const EdgeInsets.symmetric(
            horizontal: LgSpace.s3, vertical: LgSpace.s2),
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          color: m.isOut ? c.active : c.surface2,
          borderRadius: BorderRadius.circular(LgRadius.r12),
        ),
        child: Column(
          crossAxisAlignment:
              m.isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(m.text, style: t.text),
            Text('${two(m.at.hour)}:${two(m.at.minute)}',
                style: t.textS.copyWith(color: c.text2)),
          ],
        ),
      ),
    );
  }
}
