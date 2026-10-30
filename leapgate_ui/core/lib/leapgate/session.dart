// 上游：flutter/lib/models/model.dart@bd9262397（改写：`ConnType` 和会话对象 `FFI`。上游这两段改了，合并时人工移植到这里）
import 'dart:convert';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import 'app_core.dart';
import 'notices.dart';
import 'prompts.dart';
import 'session_events.dart';

/// `index` goes to Rust as the connection type (upstream `FfiModel`), so the order stays
/// upstream's. A session tab shows `defaultConn` (remote desktop) and `fileTransfer`; camera and
/// terminal come in round 3.
enum ConnType {
  defaultConn,
  fileTransfer,
  portForward,
  rdp,
  viewCamera,
  terminal
}

/// One session: one view of one device (03 §3.3 item 1). Keeps upstream's class and member
/// names, so the copied models reach it through `WeakReference<FFI>` unchanged. Only
/// [SessionRegistry] creates, starts and closes it.
///
/// Unlike upstream, it holds only the session's own models; the global ones are on [AppCore].
class FFI {
  FFI(this.id, this.connType) : sessionId = const Uuid().v4obj();

  final SessionID sessionId;

  /// The device ID.
  final String id;

  final ConnType connType;

  /// Set by [close] and by Rust's `close` event.
  var closed = false;

  final events = SessionEvents();
  final notices = SessionNotices();

  // State upstream kept per device ID in GetX registries (`common/shared_state.dart`): two views
  // of one device in one engine would share it, and closing one would delete the other's.
  // Upstream class in each comment; initial values are upstream's.
  final keyboardEnabled = true.obs; // KeyboardEnabledState
  final currentDisplay = 0.obs; // CurrentDisplayState
  final privacyMode = ''.obs; // PrivacyModeState
  final blockInput = false.obs; // BlockInputState
  final fingerprint = ''.obs; // FingerprintState
  final showRemoteCursor = false.obs; // ShowRemoteCursorState
  final remoteCursorMoved = false.obs; // RemoteCursorMovedState

  /// The token that lets another view of this device log in without the password again
  /// (upstream `common/widgets/toolbar.dart:580`).
  String? get connToken => bind.sessionGetConnToken(sessionId: sessionId);

  /// Asks the user over this session's tab.
  Future<T?> ask<T>(Prompt<T> prompt) =>
      appCore.prompter.ask(prompt, session: this);

  /// Upstream `FFI.start` without the tab-to-window path.
  void start({bool forceRelay = false, String? connToken}) {
    bind.sessionAddSync(
      sessionId: sessionId,
      id: id,
      isFileTransfer: connType == ConnType.fileTransfer,
      isViewCamera: connType == ConnType.viewCamera,
      // Upstream starts RDP as a port forward with isRdp set.
      isPortForward:
          connType == ConnType.portForward || connType == ConnType.rdp,
      isRdp: connType == ConnType.rdp,
      isTerminal: connType == ConnType.terminal,
      switchUuid: '',
      forceRelay: forceRelay,
      password: '',
      isSharedPassword: false,
      connToken: connToken,
    );
    // Like upstream, messages are not awaited one after another.
    bind.sessionStart(sessionId: sessionId, id: id).listen((message) {
      if (closed) return;
      _onMessage(message);
    });
  }

  Future<void> _onMessage(EventToUI message) async {
    if (message is EventToUI_Event) {
      if (message.field0 == 'close') {
        closed = true;
        return;
      }
      await events.dispatch(json.decode(message.field0));
    }
  }

  Future<void> close() async {
    closed = true;
    await bind.sessionClose(sessionId: sessionId);
  }
}
