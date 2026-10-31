import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/cm_core.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/cm/cm_page.dart';
import 'package:leapgate_ui/cm/cm_window.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';

// The connection manager's page, one test per state of 06 §5.1 in the first stage (A-P3.html).
// Device IDs and names here are made up.

class CmBind implements RustdeskImpl {
  final calls = <Invocation>[];
  String approveMode = '';
  bool canElevate = false;
  String privacyModeImpls = '[]';
  final buildinOptions = <String, String>{};

  /// What `cm_get_click_time` answers: the remote user's last input. 0 lets every click through.
  double clickTime = 0;
  int clientsLength = 0;

  List<Invocation> callsTo(Symbol name) =>
      calls.where((c) => c.memberName == name).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    switch (invocation.memberName) {
      case #optionSynced:
        return Future<bool>.value(false);
      case #cmCheckClientsLength:
        return Future<String?>.value();
      case #cmGetClientsState:
        return Future<String>.value('[]');
      case #mainGetOption:
        return Future<String>.value(approveMode);
      case #mainGetLocalOption:
        return '';
      case #mainGetBuildinOption:
        return buildinOptions[invocation.namedArguments[#key]] ?? '';
      case #cmCanElevate:
        return canElevate;
      case #mainSupportedPrivacyModeImpls:
        return privacyModeImpls;
      case #cmGetClickTime:
        return Future<double>.value(clickTime);
      case #cmGetClientsLength:
        return Future<int>.value(clientsLength);
      case #cmCheckClickTime:
      case #cmLoginRes:
      case #cmCloseConnection:
      case #cmElevatePortable:
      case #cmSwitchBack:
      case #cmSwitchPermission:
      case #cmHandleIncomingVoiceCall:
      case #cmCloseVoiceCall:
      case #cmRemoveDisconnectedConnection:
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeCmShell implements CmShellWindow {
  final _view = ValueNotifier(CmView.full);
  final calls = <String>[];

  @override
  ValueListenable<CmView> get view => _view;

  set viewForTest(CmView v) => _view.value = v;

  @override
  Future<void> show() async {
    if (_view.value == CmView.hidden) _view.value = CmView.full;
  }

  @override
  Future<void> hide() async => _view.value = CmView.hidden;

  @override
  Future<void> collapse() async {
    calls.add('collapse');
    if (_view.value == CmView.full) _view.value = CmView.strip;
  }

  @override
  Future<void> expand() async {
    calls.add('expand');
    if (_view.value == CmView.strip) _view.value = CmView.full;
  }

  @override
  Future<void> bringToFront() async => _view.value = CmView.full;

  @override
  Future<void> close() async => calls.add('close');

  @override
  Future<void> startDragging() async {}

  @override
  void startStripDrag() => calls.add('dragStart');

  @override
  Future<void> dragStrip() async => calls.add('drag');

  @override
  Future<void> endStripDrag() async => calls.add('dragEnd');

  @override
  Future<Rect> getFrame() async => Rect.zero;

  @override
  Future<void> setFullscreen(bool fullscreen) async {}
}

typedef Cm = ({CmBind bind, FakeCmShell window, ServerModel model});

Map<String, dynamic> visitor(
  int id, {
  String name = '李四',
  String peerId = '912345678',
  bool authorized = true,
  bool fileTransfer = false,
  bool camera = false,
  bool terminal = false,
  String portForward = '',
  bool disconnected = false,
  bool fromSwitch = false,
  bool inVoiceCall = false,
  bool incomingVoiceCall = false,
}) => {
  'id': id,
  'authorized': authorized,
  'is_file_transfer': fileTransfer,
  'is_view_camera': camera,
  'is_terminal': terminal,
  'port_forward': portForward,
  'name': name,
  'peer_id': peerId,
  'keyboard': true,
  'clipboard': true,
  'audio': true,
  'file': true,
  'restart': true,
  'recording': false,
  'block_input': false,
  'privacy_mode': false,
  'disconnected': disconnected,
  'from_switch': fromSwitch,
  'in_voice_call': inVoiceCall,
  'incoming_voice_call': incomingVoiceCall,
};

/// Rust pushing [evt]; the model brings the window up on the next turn of the event loop.
Future<void> send(WidgetTester tester, Map<String, dynamic> evt) async {
  await appCore.events.dispatch(evt);
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> arrive(WidgetTester tester, Map<String, dynamic> v) =>
    send(tester, {'name': 'add_connection', 'client': jsonEncode(v)});

Future<Cm> pumpCm(WidgetTester tester, {void Function(CmBind)? setUp}) async {
  tester.view.physicalSize = const Size(300, 490);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final bind = CmBind();
  setUp?.call(bind);
  platformFFI.setBindingForTesting(bind);
  desktopType = DesktopType.cm;
  final window = FakeCmShell();
  appCore = AppCore(window: window);
  addTearDown(appCore.recentPeers.dispose);
  final model = ServerModel(window);
  registerCmEvents(model, CmAppearance(appCore.options.local));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
      home: CmPage(model: model, window: window),
    ),
  );
  return (bind: bind, window: window, model: model);
}

/// Takes the page down and stops the model's timers before the test ends. A second visitor's
/// collapse timer replaces the first's handle, as upstream's does, so the first one is left to
/// run out.
Future<void> finish(WidgetTester tester, Cm cm) async {
  await tester.pumpWidget(const SizedBox());
  cm.model.dispose();
  await tester.pump(const Duration(seconds: 3));
}

/// A guarded click: the check takes 120 ms.
Future<void> click(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 200));
}

Finder iconButton(String label) =>
    find.byWidgetPredicate((w) => w is LgIconButton && w.label == label);

Finder switchNamed(String label) =>
    find.byWidgetPredicate((w) => w is LgSwitch && w.semanticLabel == label);

List<String> switchLabels(WidgetTester tester) => [
  for (final s in tester.widgetList<LgSwitch>(find.byType(LgSwitch)))
    s.semanticLabel!,
];

void main() {
  testWidgets(
    'remote desktop: header, eight permissions with labels, Disconnect',
    (tester) async {
      final cm = await pumpCm(
        tester,
        setUp: (b) => b.privacyModeImpls = '["x"]',
      );
      await arrive(tester, visitor(1));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('李四'), findsWidgets);
      expect(find.text('912 345 678'), findsOneWidget);
      expect(find.text('远程桌面'), findsOneWidget);
      expect(find.text('已连接 00:00:02'), findsOneWidget);
      expect(find.text('允许对方'), findsOneWidget);
      expect(switchLabels(tester), [
        '键盘和鼠标',
        '剪贴板',
        '声音',
        '文件复制粘贴',
        '远程重启',
        '录制',
        '阻止本地输入',
        '隐私模式',
      ]);
      expect(iconButton('聊天'), findsOneWidget);
      expect(find.text('断开'), findsOneWidget);

      await click(tester, find.text('断开'));
      expect(
        cm.bind.callsTo(#cmCloseConnection).single.namedArguments[#connId],
        1,
      );
      await finish(tester, cm);
    },
  );

  testWidgets(
    'a permission switch tells the connection; read-only when a built-in setting says so',
    (tester) async {
      var cm = await pumpCm(tester);
      await arrive(tester, visitor(1));
      await click(tester, switchNamed('剪贴板'));
      final call = cm.bind.callsTo(#cmSwitchPermission).single.namedArguments;
      expect(
        (call[#connId], call[#name], call[#enabled]),
        (1, 'clipboard', false),
      );
      expect(tester.widget<LgSwitch>(switchNamed('剪贴板')).value, false);
      await finish(tester, cm);

      cm = await pumpCm(
        tester,
        setUp: (b) =>
            b.buildinOptions[kOptionEnablePermChangeInAcceptWindow] = 'N',
      );
      await arrive(tester, visitor(1));
      expect(
        tester
            .widgetList<LgSwitch>(find.byType(LgSwitch))
            .every((s) => s.onChanged == null),
        true,
      );
      await finish(tester, cm);
    },
  );

  testWidgets('camera: audio and recording only', (tester) async {
    final cm = await pumpCm(tester);
    await arrive(tester, visitor(1, camera: true));
    expect(find.text('查看摄像头'), findsOneWidget);
    expect(switchLabels(tester), ['声音', '录制']);
    expect(iconButton('聊天'), findsOneWidget);
    await finish(tester, cm);
  });

  testWidgets('file transfer: no permissions, the file log button', (
    tester,
  ) async {
    final cm = await pumpCm(tester);
    await arrive(tester, visitor(1, fileTransfer: true));
    expect(find.text('文件传输'), findsOneWidget);
    expect(find.byType(LgSwitch), findsNothing);
    expect(iconButton('文件记录'), findsOneWidget);
    await finish(tester, cm);
  });

  testWidgets(
    'terminal and port forwarding: the type, no permissions, no side button',
    (tester) async {
      final cm = await pumpCm(tester);
      await arrive(tester, visitor(1, terminal: true));
      expect(find.text('终端'), findsOneWidget);
      await arrive(
        tester,
        visitor(2, name: '王五', portForward: '192.0.2.5:8080'),
      );
      expect(find.text('端口转发：192.0.2.5:8080'), findsOneWidget);
      expect(find.byType(LgSwitch), findsNothing);
      expect(iconButton('聊天'), findsNothing);
      await finish(tester, cm);
    },
  );

  testWidgets('exit node: its note, no permissions, no chat', (tester) async {
    final cm = await pumpCm(tester);
    await arrive(
      tester,
      visitor(1, portForward: 'leapgate-exit.invalid:65536'),
    );
    expect(find.text('作为出口'), findsOneWidget);
    expect(find.text('对方正在通过本机访问网络（仅 TCP），无法查看本机屏幕。'), findsOneWidget);
    expect(find.byType(LgSwitch), findsNothing);
    expect(iconButton('聊天'), findsNothing);
    expect(find.text('断开'), findsOneWidget);
    await finish(tester, cm);
  });

  testWidgets(
    'waiting, accepted here: Accept tells Rust and collapses at once',
    (tester) async {
      final cm = await pumpCm(tester);
      await arrive(tester, visitor(1, authorized: false));
      expect(find.text('正在请求连接本机…'), findsOneWidget);
      expect(find.text('接受'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);
      expect(find.text('接受并提升权限'), findsNothing);

      await click(tester, find.text('接受'));
      final res = cm.bind.callsTo(#cmLoginRes).single.namedArguments;
      expect((res[#connId], res[#res]), (1, true));
      expect(cm.window.calls, contains('collapse'));
      await finish(tester, cm);
    },
  );

  testWidgets('waiting, the portable version can elevate: Accept and elevate', (
    tester,
  ) async {
    final cm = await pumpCm(tester, setUp: (b) => b.canElevate = true);
    await arrive(tester, visitor(1, authorized: false));
    await send(tester, {'name': 'show_elevation', 'show': 'true'});
    await click(tester, find.text('接受并提升权限'));
    expect(cm.bind.callsTo(#cmLoginRes), hasLength(1));
    expect(
      cm.bind.callsTo(#cmElevatePortable).single.namedArguments[#connId],
      1,
    );
    expect(cm.window.calls, contains('collapse'));
    await finish(tester, cm);
  });

  testWidgets(
    'waiting, approval by password: the remote user is entering it, Decline',
    (tester) async {
      final cm = await pumpCm(tester, setUp: (b) => b.approveMode = 'password');
      await tester.pump(const Duration(milliseconds: 500));
      await arrive(tester, visitor(1, authorized: false));
      expect(find.text('对方正在输入密码…'), findsOneWidget);
      expect(find.text('接受'), findsNothing);

      await click(tester, find.text('拒绝'));
      expect(
        cm.bind.callsTo(#cmCloseConnection).single.namedArguments[#connId],
        1,
      );
      await finish(tester, cm);
    },
  );

  testWidgets('voice call: incoming, then in a call', (tester) async {
    final cm = await pumpCm(tester);
    await arrive(tester, visitor(1));
    await send(tester, {
      'name': 'update_voice_call_state',
      'client': jsonEncode(visitor(1, incomingVoiceCall: true)),
    });
    expect(find.text('正在请求语音通话… 00:00:00'), findsOneWidget);
    await click(tester, find.text('接听'));
    final answer = cm.bind
        .callsTo(#cmHandleIncomingVoiceCall)
        .single
        .namedArguments;
    expect((answer[#id], answer[#accept]), (1, true));

    await send(tester, {
      'name': 'update_voice_call_state',
      'client': jsonEncode(visitor(1, inVoiceCall: true)),
    });
    expect(find.text('语音通话中 00:00:00'), findsOneWidget);
    await click(tester, find.text('挂断'));
    expect(cm.bind.callsTo(#cmCloseVoiceCall).single.namedArguments[#id], 1);
    await finish(tester, cm);
  });

  testWidgets('switched sides and elevation offered once connected', (
    tester,
  ) async {
    final cm = await pumpCm(tester, setUp: (b) => b.canElevate = true);
    await arrive(tester, visitor(1, fromSwitch: true));
    await send(tester, {'name': 'show_elevation', 'show': 'true'});
    await click(tester, find.text('撤销交换'));
    expect(cm.bind.callsTo(#cmSwitchBack), hasLength(1));
    await click(tester, find.text('提升权限'));
    expect(cm.bind.callsTo(#cmElevatePortable), hasLength(1));
    expect(cm.window.calls, contains('collapse'));
    await finish(tester, cm);
  });

  testWidgets(
    'disconnected: Close removes it, and the window goes with the last one',
    (tester) async {
      final cm = await pumpCm(tester);
      await arrive(tester, visitor(1));
      await send(tester, {
        'name': 'on_client_remove',
        'id': '1',
        'close': 'false',
      });
      expect(find.text('已断开'), findsOneWidget);
      expect(find.byType(LgSwitch), findsNothing);

      await click(tester, find.text('关闭'));
      expect(cm.bind.callsTo(#cmRemoveDisconnectedConnection), hasLength(1));
      expect(cm.window.calls, contains('close'));
      await finish(tester, cm);
    },
  );

  testWidgets(
    'several visitors: a tab each, the newest selected, another one on a click',
    (tester) async {
      final cm = await pumpCm(tester);
      await arrive(tester, visitor(1));
      await arrive(tester, visitor(2, name: '王五', peerId: '147258369'));
      expect(find.text('147 258 369'), findsOneWidget);
      await tester.tap(find.text('李四'));
      await tester.pump();
      expect(find.text('912 345 678'), findsOneWidget);
      await finish(tester, cm);
    },
  );

  testWidgets('a remote click is dropped with a hint', (tester) async {
    final cm = await pumpCm(tester, setUp: (b) => b.clickTime = 1e15);
    await arrive(tester, visitor(1));
    await click(tester, find.text('断开'));
    expect(cm.bind.callsTo(#cmCloseConnection), isEmpty);
    expect(find.text('无法远程执行此操作'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('无法远程执行此操作'), findsNothing);
    await finish(tester, cm);
  });

  testWidgets('closing with more than one visitor asks first', (tester) async {
    final cm = await pumpCm(tester);
    await arrive(tester, visitor(1));
    final close = iconButton('关闭');
    await click(tester, close);
    expect(cm.window.calls, ['close']);

    await arrive(tester, visitor(2, name: '王五', peerId: '147258369'));
    await click(tester, close);
    expect(find.text('断开全部会话？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(find.text('断开全部会话？'), findsNothing);
    expect(cm.window.calls, ['close']);

    await click(tester, close);
    await click(
      tester,
      find
          .descendant(of: find.byType(LgButton), matching: find.text('断开'))
          .last,
    );
    expect(cm.window.calls, ['close', 'close']);
    await finish(tester, cm);
  });

  testWidgets(
    'a remote click on Close is dropped with a hint under the header',
    (tester) async {
      final cm = await pumpCm(tester, setUp: (b) => b.clickTime = 1e15);
      await arrive(tester, visitor(1));
      await click(tester, iconButton('关闭'));
      expect(cm.window.calls, isEmpty);
      expect(find.text('无法远程执行此操作'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await finish(tester, cm);
    },
  );

  testWidgets(
    'moving the mouse in the window cancels the collapse after a password login',
    (tester) async {
      final cm = await pumpCm(tester);
      await arrive(tester, visitor(1));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(150, 200));
      addTearDown(gesture.removePointer);
      await gesture.moveTo(const Offset(160, 210));
      await tester.pump(const Duration(seconds: 4));
      expect(cm.window.calls, isNot(contains('collapse')));
      await finish(tester, cm);
    },
  );

  testWidgets(
    'the strip, one visitor: what they are doing, the time and Disconnect',
    (tester) async {
      final cm = await pumpCm(tester);
      await arrive(tester, visitor(1));
      await tester.pump(const Duration(seconds: 3));
      expect(cm.window.view.value, CmView.strip);
      expect(find.text('李四 正在远程控制本机'), findsOneWidget);
      expect(find.text('00:00:03'), findsOneWidget);

      await click(tester, find.text('断开'));
      expect(cm.bind.callsTo(#cmCloseConnection), hasLength(1));
      await tester.tap(find.text('李四 正在远程控制本机'));
      await tester.pump();
      expect(cm.window.view.value, CmView.full);
      await finish(tester, cm);
    },
  );

  testWidgets(
    'the strip, several visitors: how many are connected and Expand; dragging moves it',
    (tester) async {
      final cm = await pumpCm(tester);
      await arrive(tester, visitor(1));
      await arrive(tester, visitor(2, name: '王五', peerId: '147258369'));
      await arrive(
        tester,
        visitor(3, name: '赵六', peerId: '258369147', authorized: false),
      );
      cm.window.viewForTest = CmView.strip;
      await tester.pump();
      expect(find.text('2 个会话进行中'), findsOneWidget);
      expect(find.text('断开'), findsNothing);

      await tester.drag(find.text('2 个会话进行中'), const Offset(-40, 0));
      expect(cm.window.calls, containsAll(['dragStart', 'drag', 'dragEnd']));
      await tester.tap(find.text('展开'));
      await tester.pump();
      expect(cm.window.view.value, CmView.full);
      await finish(tester, cm);
    },
  );

  testWidgets(
    'a remote click on the strip is dropped with the hint in place of the time',
    (tester) async {
      final cm = await pumpCm(tester, setUp: (b) => b.clickTime = 1e15);
      await arrive(tester, visitor(1, terminal: true));
      cm.window.viewForTest = CmView.strip;
      await tester.pump();
      expect(find.text('李四 正在使用终端'), findsOneWidget);
      await click(tester, find.text('断开'));
      expect(cm.bind.callsTo(#cmCloseConnection), isEmpty);
      expect(find.text('无法远程执行此操作'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await finish(tester, cm);
    },
  );

  testWidgets('the strip, one visitor waiting: the name, then the state', (
    tester,
  ) async {
    final cm = await pumpCm(tester);
    await arrive(tester, visitor(1, authorized: false));
    cm.window.viewForTest = CmView.strip;
    await tester.pump();
    expect(find.text('李四'), findsOneWidget);
    expect(find.text('李四 正在远程控制本机'), findsNothing);
    expect(find.text('正在请求连接本机…'), findsOneWidget);
    expect(find.text('拒绝'), findsOneWidget);
    await finish(tester, cm);
  });
}
