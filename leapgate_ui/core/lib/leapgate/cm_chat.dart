// The connection manager's text chat (01 §3.3 "聊天侧栏"): what upstream's `ChatModel` does in
// its server mode (`flutter/lib/models/chat_model.dart` `receive`, `send`, `MessageKey`). The
// messages are kept by the visitor's ID, as upstream's `MessageKey` compares them, so a visitor
// who reconnects finds the conversation; a message goes out on the connection it is written in.
// What a new message does to the window and the tabs is the page's.

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../models/chat_model.dart' show ChatMessage;
import '../models/platform_model.dart';
import '../models/server_model.dart';

class CmChatModel with ChangeNotifier {
  CmChatModel(this.serverModel);

  final ServerModel serverModel;
  final _messages = <String, List<ChatMessage>>{};

  /// Called after a message from [client] is stored (upstream shows the window and the chat).
  void Function(Client client)? onReceive;

  /// Oldest first.
  List<ChatMessage> messagesOf(Client client) =>
      List.unmodifiable(_messages[client.peerId] ?? const <ChatMessage>[]);

  /// The `chat_server_mode` event. A connection the window does not know is dropped, as
  /// upstream does.
  void receive(int id, String text) {
    if (text.isEmpty) return;
    final client = serverModel.clients.firstWhereOrNull((c) => c.id == id);
    if (client == null) return;
    _messages
        .putIfAbsent(client.peerId, () => [])
        .add(ChatMessage(isOut: false, text: text, at: clock.now()));
    notifyListeners();
    onReceive?.call(client);
  }

  /// Trimmed, nothing for blank text. Returns whether it went out.
  bool send(Client client, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    _messages
        .putIfAbsent(client.peerId, () => [])
        .add(ChatMessage(isOut: true, text: trimmed, at: clock.now()));
    bind.cmSendChat(connId: client.id, msg: trimmed);
    notifyListeners();
    return true;
  }
}
