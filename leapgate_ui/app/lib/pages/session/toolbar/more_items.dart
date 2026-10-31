// What "录制" and "聊天" become once folded into "更多" (A-P2 `min-s`): a row each, doing what the
// buttons of `recording.dart` and `chat/chat.dart` do. The microphone choice of a call stays on
// the chat button; a folded one shows the call's state and its hang-up.

import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/chat_model.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_menu.dart';

/// The record row: on while recording, greyed with the reason without the permission (the
/// same exception as the button: a recording can always be stopped).
Widget recordMoreItem(FFI ffi) => ListenableBuilder(
  listenable: Listenable.merge([ffi.recordingModel, ffi.ffiModel]),
  builder: (context, _) {
    final l10n = AppLocalizations.of(context)!;
    final recording = ffi.recordingModel.start;
    final allowed = recording || ffi.ffiModel.permissions['recording'] != false;
    return LgMenuItem(
      label: recording ? l10n.recordStop : l10n.recordStart,
      icon: LgIcons.record,
      onPressed: allowed ? ffi.requests.toggleRecording : null,
      disabledNote: l10n.recordNoPermission,
    );
  },
);

/// The chat row: a submenu with text chat and the voice call as the chat button's menu has
/// them; [ChatModel.unread] as its count.
Widget chatMoreItem(FFI ffi) => ListenableBuilder(
  listenable: ffi.chatModel,
  builder: (context, _) {
    final l10n = AppLocalizations.of(context)!;
    final chat = ffi.chatModel;
    final call = switch (chat.voiceCallStatus) {
      VoiceCallStatus.waitingForResponse => LgMenuItem(
        label: l10n.connCancel,
        description: l10n.chatWaitingAnswer,
        icon: LgIcons.call,
        onPressed: chat.closeVoiceCall,
      ),
      VoiceCallStatus.connected => LgMenuItem(
        label: l10n.chatHangUp,
        icon: LgIcons.callEnd,
        danger: true,
        onPressed: chat.closeVoiceCall,
      ),
      VoiceCallStatus.notStarted || VoiceCallStatus.incoming => LgMenuItem(
        label: l10n.chatVoiceCall,
        onPressed: chat.requestVoiceCall,
      ),
    };
    return LgSubmenu(
      label: l10n.chatMenu,
      icon: LgIcons.chat,
      badge: chat.unread,
      items: [
        LgMenuItem(
          label: l10n.chatText,
          checked: chat.open,
          onPressed: () => chat.setOpen(!chat.open),
        ),
        call,
      ],
    );
  },
);
