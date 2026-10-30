import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/generated_bridge_leapgate.dart' as lg;
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/app_window.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/prompts.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Block 1 of the bridge: records the calls and plays the session streams from the test.
class FakeBind implements RustdeskImpl {
  final calls = <Invocation>[];
  final streams = <SessionID, StreamController<EventToUI>>{};
  final tokens = <SessionID, String>{};

  /// Calls that throw, to see what still happens after them.
  final failing = <Symbol>{};

  /// What `sessionReadLocalDirSync` answers, as Rust's JSON.
  String localDir = '{"id":0,"path":"","entries":[]}';

  List<Invocation> callsTo(Symbol name) =>
      calls.where((c) => c.memberName == name).toList();

  // Rust's `transfer-job-id` counter.
  var _jobId = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    if (failing.contains(invocation.memberName)) {
      throw StateError('failing ${invocation.memberName}');
    }
    final sessionId = invocation.namedArguments[#sessionId] as SessionID?;
    switch (invocation.memberName) {
      case #sessionAddSync:
        return '';
      case #sessionStart:
        return (streams[sessionId!] = StreamController<EventToUI>()).stream;
      case #sessionGetConnToken:
        return tokens[sessionId];
      case #sessionClose:
        return Future<void>.value();
      // What the copied models call while a session starts, handles peer info and closes.
      // Values are those of a fresh session without saved options.
      case #getNextTextureKey:
        return 0;
      case #mainGetUseTextureRender:
      case #mainHasGpuTextureRender:
      case #sessionGetToggleOptionSync:
      case #sessionIsKeyboardModeSupported:
        return false;
      case #isSupportMultiUiSession:
        return true;
      case #peerGetSessionsCount:
      case #versionToNumber:
        return 1;
      case #mainGetLocalOption:
      case #mainGetInputSource:
        return '';
      case #sessionGetUseAllMyDisplaysForTheRemoteSession:
        return null;
      case #sessionGetTrackpadSpeed:
        return Future<int?>.value();
      case #sessionGetOption:
      case #sessionGetKeyboardMode:
      case #sessionGetFlutterOption:
      case #sessionGetViewStyle:
      case #sessionGetScrollStyle:
        return Future<String?>.value();
      case #sessionGetToggleOption:
        return Future<bool?>.value(false);
      case #sessionRegisterPixelbufferTexture:
        return null;
      case #translate:
        return invocation.namedArguments[#name];
      // File transfer.
      case #mainGetCommonSync:
        return '${++_jobId}';
      case #sessionReadLocalDirSync:
        return Future<String>.value(localDir);
      case #sessionSetConfirmOverrideFile:
      case #sessionCancelJob:
      case #sessionReadDirToRemoveRecursive:
      case #sessionRemoveFile:
      case #sessionRemoveAllEmptyDirs:
      case #sessionRenameFile:
      case #mainLoadRecentPeers:
      case #sessionSendMouse:
      case #sessionPeerOption:
      case #sessionSetSize:
      case #sessionSwitchDisplay:
      case #sessionSetKeyboardMode:
      case #sessionSetFlutterOption:
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

/// Block 2: keeps the log lines.
class FakeLeapgate implements lg.Leapgate {
  final logged = <String>[];

  @override
  void leapgateLog({required int level, required String msg, dynamic hint}) =>
      logged.add(msg);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class FakeWindow implements AppWindow {
  @override
  Future<void> bringToFront() async {}

  @override
  Future<Rect> getFrame() async => Rect.zero;

  @override
  Future<void> setFullscreen(bool fullscreen) async {}
}

/// Answers with [answer] and remembers where each question was asked.
class FakePrompter implements Prompter {
  FakePrompter(this.answer);

  final Object? answer;
  final asked = <(Prompt, FFI?)>[];

  @override
  Future<T?> ask<T>(Prompt<T> prompt, {FFI? session}) async {
    asked.add((prompt, session));
    return answer as T?;
  }
}

/// Fresh fakes behind `bind`, `lgBind` and `appCore` for one test.
({FakeBind bind, FakeLeapgate lg}) installFakes({bool singleSession = false}) {
  final bind = FakeBind();
  final leapgate = FakeLeapgate();
  // A desktop session makes a pixel buffer texture through the plugin's channel when it starts
  // (`TextureModel.updateCurrentDisplay`); -1 is the plugin's "not created".
  TestWidgetsFlutterBinding.ensureInitialized()
      .defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('texture_rgba_renderer'),
          (call) async => call.method == 'createTexture' ? -1 : null);
  platformFFI.setBindingForTesting(bind);
  setLgBindForTesting(leapgate);
  appCore = AppCore(window: FakeWindow(), singleSession: singleSession);
  return (bind: bind, lg: leapgate);
}

/// Lets the stream listeners and the handlers they start run.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
