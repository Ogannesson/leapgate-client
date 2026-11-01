// 上游：flutter/lib/models/chat_model.dart@bd9262397（改写：只留控制方会话的消息存储、未读数和语音通话状态；消息类型用自己的，不带 dash_chat_2；聊天窗口和图标浮层、窗口大小、CM 和手机的部分都不要，面板在 app 里。上游这个文件改了，合并时人工比对）
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import '../leapgate/session.dart';

/// One chat message of a session.
class ChatMessage {
  ChatMessage({required this.isOut, required this.text, required this.at});

  /// Sent from this device.
  final bool isOut;
  final String text;
  final DateTime at;
}

/// Upstream's states; `incoming` is the connection manager's only.
enum VoiceCallStatus { notStarted, waitingForResponse, connected, incoming }

/// The microphones for a voice call: [devices] by name, [loopback] when "System sound" can be
/// used, [current] the chosen one, '' for the default ("System sound" with [loopback]).
typedef VoiceInputs = ({List<String> devices, bool loopback, String current});

/// Text chat and the voice call of one session (01 P2 block F). Messages from the remote device
/// open the chat panel; while the session's tab is not shown they count as unread (upstream
/// counted them on a tab that was not selected).
class ChatModel with ChangeNotifier {
  ChatModel(this.parent);

  final WeakReference<FFI> parent;

  SessionID get _sessionId => parent.target!.sessionId;

  final _messages = <ChatMessage>[];
  var _unread = 0;
  var _open = false;
  var _voiceCallStatus = VoiceCallStatus.notStarted;

  /// Oldest first.
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  int get unread => _unread;

  /// The chat panel shows.
  bool get open => _open;
  VoiceCallStatus get voiceCallStatus => _voiceCallStatus;

  /// Upstream `receive(clientModeID, text)`, the `chat_client_mode` event.
  void receive(String text) {
    if (text.isEmpty) return;
    _messages.add(ChatMessage(isOut: false, text: text, at: clock.now()));
    _open = true;
    if (parent.target?.visible != true) _unread++;
    notifyListeners();
  }

  /// Upstream `send`: trimmed, nothing for blank text. Returns whether it went out.
  bool send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    _messages.add(ChatMessage(isOut: true, text: trimmed, at: clock.now()));
    bind.sessionSendChat(sessionId: _sessionId, text: trimmed);
    notifyListeners();
    return true;
  }

  /// Opening the panel reads what came.
  void setOpen(bool open) {
    _open = open;
    if (open) _unread = 0;
    notifyListeners();
  }

  /// The tab shows again with the panel open.
  void markRead() {
    if (_unread == 0) return;
    _unread = 0;
    notifyListeners();
  }

  void requestVoiceCall() =>
      bind.sessionRequestVoiceCall(sessionId: _sessionId);

  /// Cancels the request while waiting, or hangs up.
  void closeVoiceCall() => bind.sessionCloseVoiceCall(sessionId: _sessionId);

  void onVoiceCallWaiting() => _setVoice(VoiceCallStatus.waitingForResponse);

  void onVoiceCallStarted() => _setVoice(VoiceCallStatus.connected);

  void onVoiceCallClosed(String reason) =>
      _setVoice(VoiceCallStatus.notStarted);

  /// Only the connection manager is called; a session keeps its state, as upstream.
  void onVoiceCallIncoming() {}

  void _setVoice(VoiceCallStatus status) {
    _voiceCallStatus = status;
    notifyListeners();
  }

  /// Upstream `AudioInput.getDevicesInfo(isCm: false, isVoiceCall: true)`
  /// (`common/widgets/audio_input.dart`), with "System sound" as [VoiceInputs.loopback] instead
  /// of a translated name in the list.
  Future<VoiceInputs> voiceInputs() async {
    final devices = (await bind.mainGetSoundInputs()).toList();
    final current = await bind.getVoiceCallInputDevice(isCm: false);
    return (
      devices: devices,
      loopback: bind.mainAudioSupportLoopback(),
      current: current,
    );
  }

  /// '' chooses the default.
  Future<void> setVoiceInput(String device) =>
      bind.setVoiceCallInputDevice(isCm: false, device: device);
}
