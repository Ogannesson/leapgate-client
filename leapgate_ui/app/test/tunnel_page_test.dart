import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/exit_api.dart';
import 'package:flutter_hbb/leapgate/tunnel_api.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/pages/home/exit/open_tunnel.dart';
import 'package:leapgate_ui/pages/home/exit/tunnel_section.dart';
import 'package:leapgate_ui/shell/links.dart';
import 'package:leapgate_ui/shell/window_close.dart';
import 'package:leapgate_ui/widgets/lg_panel_inputs.dart';
import 'package:leapgate_ui/widgets/lg_rdp_dialog.dart';
import 'package:leapgate_ui/widgets/lg_title_bar.dart';
import 'package:leapgate_ui/widgets/lg_tooltip.dart';
import 'package:leapgate_ui/widgets/lg_tunnel_card.dart';

import '../../core/test/exit_fakes.dart' show FakeExitApi;
import 'session_fakes.dart';
import 'tunnel_fakes.dart';

// The tunnels on the "出口与隧道" page (13 §1.3, `LEAPGATE.md` §10.18) in the main window, with the
// tunnel events and the card's session played from the test. Device IDs and names are made up,
// addresses from the documentation ranges.

const _id = '100200300';
const _tcp = TunnelKind.tcp;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _text(String text) => find.textContaining(text, findRichText: true);

/// Gives the RDP settings dialog its password limit.
class _TunnelBind extends AppFakeBind {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.memberName == #mainMaxEncryptLen
      ? 128
      : super.noSuchMethod(invocation);
}

void main() {
  late FakeTunnelApi api;
  late FakeExitApi exits;

  setUp(() {
    installAppFakes();
    platformFFI.setBindingForTesting(_TunnelBind());
    api = FakeTunnelApi();
    tunnelApi = api;
    exits = FakeExitApi();
    exitApi = exits;
    api.forwards[_id] = [
      (localPort: 2222, host: 'localhost', remotePort: 22),
      (localPort: 15432, host: '192.0.2.20', remotePort: 5432),
    ];
  });

  Future<void> row(
    WidgetTester tester,
    String state,
    int port, [
    Map<String, dynamic> extra = const {},
    TunnelKind kind = _tcp,
  ]) async {
    api.push(_id, kind, state, port: port, extra: extra);
    await _settle(tester);
  }

  Future<void> session(
    WidgetTester tester,
    Map<String, dynamic> evt, {
    TunnelKind kind = _tcp,
  }) async {
    final card = appCore.tunnels.cardOf(_id, kind)!;
    (bind as FakeBind).streams[card.sessionId]!.add(
      EventToUI.event(jsonEncode(evt)),
    );
    await _settle(tester);
  }

  Future<void> open(WidgetTester tester, {TunnelKind kind = _tcp}) async {
    await pumpMainWindow(tester);
    openTunnel(_id, kind, name: '书房台式机');
    await _settle(tester);
  }

  testMainWindow(
    'a TCP tunnel card: the saved forwards log in at once, then each row says how it is',
    (tester) async {
      await open(tester);
      expect(find.text('出口与隧道'), findsNWidgets(2));
      expect(find.text('隧道'), findsOneWidget);
      expect(find.text('将本机端口转发到远程设备或其所在网络中的地址。'), findsOneWidget);
      expect(find.text('书房台式机'), findsOneWidget);
      expect(find.text('TCP 隧道'), findsOneWidget);
      expect(api.callsTo('sessionAdd').single.sublist(1), [
        _id,
        _tcp,
        '',
        false,
        null,
        false,
      ]);
      expect(_text('正在连接…'), findsNWidgets(2));
      expect(find.bySemanticsLabel('出口与隧道，1 个正在使用'), findsOneWidget);
      expect(tester.widget<LgTitleBar>(find.byType(LgTitleBar)).homeBadge, 1);
      expect(find.bySemanticsLabel('主页，1 个出口或隧道正在使用'), findsOneWidget);

      await row(tester, 'in_use', 2222, {'transport': 'direct'});
      expect(_text('可用 · 直连'), findsOneWidget);
      await row(tester, 'interrupted', 15432, {
        'cause': 'login_failed',
        'reason': {'code': 'peer_offline'},
      });
      expect(_text('连接已中断'), findsOneWidget);
      expect(_text('下次有应用使用此端口时将自动重新连接'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('重新连接端口转发 15432'));
      await tester.pump();
      expect(api.callsTo('retry').single.sublist(1), [15432]);

      await row(tester, 'port_in_use', 15432);
      expect(_text('本机端口 15432 已被其他应用占用'), findsOneWidget);
      // Nothing listens: no address to copy on that row.
      expect(find.bySemanticsLabel('复制 127.0.0.1:15432'), findsNothing);
      expect(find.bySemanticsLabel('复制 127.0.0.1:2222'), findsOneWidget);

      await row(tester, 'stopped', 2222, {
        'reason': {'code': 'no_permission', 'feature': 'port_forward'},
      });
      expect(_text('已停止：'), findsOneWidget);
      expect(_text('远程设备不允许建立 TCP 隧道'), findsOneWidget);
      expect(find.bySemanticsLabel('重试端口转发 2222'), findsOneWidget);
      // Nothing runs any more: "移除" instead of "停止", no number.
      expect(find.bySemanticsLabel('移除 书房台式机 的 TCP 隧道'), findsOneWidget);
      expect(tester.widget<LgTitleBar>(find.byType(LgTitleBar)).homeBadge, 0);

      await tester.tap(find.bySemanticsLabel('删除端口转发 2222'));
      await tester.pump();
      expect(api.callsTo('removeForward').single.sublist(1), [2222]);
      await row(tester, 'removed', 2222);
      expect(find.bySemanticsLabel('删除端口转发 2222'), findsNothing);

      await tester.tap(find.bySemanticsLabel('移除 书房台式机 的 TCP 隧道'));
      await _settle(tester);
      expect(api.callsTo('close'), hasLength(1));
      expect(find.text('暂无正在使用的隧道'), findsOneWidget);
    },
  );

  testMainWindow(
    'the question: the password field takes the keyboard, and goes once no row logs in',
    (tester) async {
      await open(tester);
      await session(tester, msgbox('input-password', 'Password Required', ''));
      expect(_text('输入密码'), findsOneWidget);
      final field = find.descendant(
        of: find.byType(TunnelCardView),
        matching: find.byType(EditableText),
      );
      expect(
        tester.widget<EditableText>(field.first).focusNode.hasFocus,
        isTrue,
      );
      await tester.enterText(field.first, 'pw');
      await tester.pump();
      await tester.tap(find.text('连接'));
      await _settle(tester);
      expect(
        (bind as FakeBind)
            .callsTo(#sessionLogin)
            .single
            .namedArguments[#password],
        'pw',
      );
      expect(_text('正在验证…'), findsOneWidget);

      await row(tester, 'in_use', 2222, {'transport': 'relay'});
      expect(_text('正在验证…'), findsOneWidget);
      await row(tester, 'in_use', 15432, {'transport': 'relay'});
      expect(_text('正在验证…'), findsNothing);
      expect(_text('可用 · 经中继'), findsNWidgets(2));
      // Each row says why on hover.
      expect(
        find.byWidgetPredicate(
          (w) => w is LgTooltip && w.message == '流量由中继服务器转发，速度可能较慢',
        ),
        findsNWidgets(2),
      );
    },
  );

  testMainWindow(
    'a forward added and in use at once: a later question keeps away from the keyboard',
    (tester) async {
      await open(tester);
      await row(tester, 'in_use', 2222, {'transport': 'direct'});
      await row(tester, 'in_use', 15432, {'transport': 'direct'});
      await tester.ensureVisible(find.text('添加端口转发'));
      await tester.tap(find.text('添加端口转发'));
      await _settle(tester);
      final fields = find.descendant(
        of: find.byType(TunnelCardView),
        matching: find.byType(EditableText),
      );
      await tester.enterText(fields.at(0), '8080');
      await tester.enterText(fields.at(2), '80');
      await tester.pump();
      await tester.tap(find.text('添加'));
      await _settle(tester);
      // Logged in with what the session had: no question.
      await row(tester, 'in_use', 8080, {'transport': 'direct'});

      // Later the tunnel ends and the next local connection logs in again, asking by itself.
      await row(tester, 'connecting', 2222);
      await session(tester, msgbox('input-password', 'Password Required', ''));
      expect(_text('输入密码'), findsOneWidget);
      final password = find.descendant(
        of: find.byType(LgTunnelQuestion),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(password).focusNode.hasFocus, isFalse);
    },
  );

  testMainWindow('an unencrypted connection is asked about; "继续" goes on', (
    tester,
  ) async {
    await open(tester);
    await session(tester, msgbox('insecure-connection', '', ''));
    expect(_text('未加密'), findsOneWidget);
    expect(_text('此连接未使用端到端加密，传输的内容可能被第三方读取。'), findsOneWidget);
    expect(
      tester.widget<LgTitleBar>(find.byType(LgTitleBar)).homeAlert,
      isTrue,
    );
    await tester.tap(find.text('继续'));
    await _settle(tester);
    final set = (bind as FakeBind)
        .callsTo(#sessionSetCommon)
        .single
        .namedArguments;
    expect(set[#value], 'Y');
    expect(_text('未加密'), findsNothing);
  });

  testMainWindow(
    'adding: open at once without forwards; the three checks; then the row logs in',
    (tester) async {
      api.forwards.remove(_id);
      exits.addError = const ExitAddError('already');
      await pumpMainWindow(tester);
      appCore.exitNodes.use('400500600');
      openTunnel(_id, _tcp);
      await _settle(tester);
      expect(find.text('暂无端口转发'), findsOneWidget);
      // Opened with no forward: the add line is there and nothing runs.
      expect(find.bySemanticsLabel('移除 100 200 300 的 TCP 隧道'), findsOneWidget);
      final fields = find.descendant(
        of: find.byType(TunnelCardView),
        matching: find.byType(EditableText),
      );
      expect(fields, findsNWidgets(3));
      // Nothing to fold back to: no "取消".
      final cancel = find.descendant(
        of: find.byType(TunnelCardView),
        matching: find.text('取消'),
      );
      expect(cancel, findsNothing);

      Future<void> add(String local, String host, String remote) async {
        await tester.enterText(fields.at(0), local);
        await tester.enterText(fields.at(1), host);
        await tester.enterText(fields.at(2), remote);
        await tester.pump();
        await tester.ensureVisible(find.text('添加'));
        await tester.tap(find.text('添加'));
        await _settle(tester);
      }

      await add('70000', '', '22');
      expect(find.text('端口无效。端口应为 1~65535。'), findsOneWidget);
      final exitPort = appCore.exitNodes.cards.single.port;
      await add('$exitPort', '', '22');
      expect(find.text('此端口已被另一个出口或隧道使用'), findsOneWidget);
      await add('2222', '', '22');
      expect(api.callsTo('addForward').single.sublist(1), [
        2222,
        'localhost',
        22,
      ]);
      expect(_text('正在连接…'), findsOneWidget);
      expect(cancel, findsOneWidget);
      await add('2222', '192.0.2.30', '80');
      expect(find.text('此端口已有一条端口转发'), findsOneWidget);
      // The add line stays open for the next one; the card runs now.
      expect(find.bySemanticsLabel('停止 100 200 300 的 TCP 隧道'), findsOneWidget);
    },
  );

  testMainWindow(
    'an exit card to the device: the conflict until it is gone, then "重试"',
    (tester) async {
      exits.addError = const ExitAddError('already');
      api.addError = const TunnelAddError('already');
      await pumpMainWindow(tester);
      appCore.exitNodes.use(_id);
      openTunnel(_id, _tcp);
      await _settle(tester);
      expect(
        find.descendant(
          of: find.byType(TunnelCardView),
          matching: _text('已停止：本机已有连接此设备的出口'),
        ),
        findsOneWidget,
      );
      expect(find.text('添加端口转发'), findsNothing);
      api.addError = null;
      // The exit card has a "重试" by the same name.
      final retry = find.descendant(
        of: find.byType(TunnelCardView),
        matching: find.bySemanticsLabel('重试 100 200 300'),
      );
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await _settle(tester);
      expect(api.callsTo('sessionAdd'), hasLength(2));
      expect(_text('正在连接…'), findsNWidgets(2));
    },
  );

  testMainWindow(
    'an RDP card: in use, a notice, a new connection, its settings',
    (tester) async {
      api.rdp[_id] = (port: '3390', username: 'mama', password: '');
      await open(tester, kind: TunnelKind.rdp);
      expect(find.text('RDP · 端口 3390'), findsOneWidget);
      expect(_text('正在连接 书房台式机…'), findsOneWidget);
      await row(tester, 'in_use', 0, {'transport': 'relay'}, TunnelKind.rdp);
      expect(_text('可用 · 经中继'), findsOneWidget);
      expect(_text('流量由中继服务器转发，速度可能较慢'), findsOneWidget);
      await row(tester, 'notice', 0, {
        'reason': {'code': 'tunnel_unreachable', 'target': 'localhost:3390'},
      }, TunnelKind.rdp);
      expect(_text('无法访问远程设备的 RDP 服务。请确认远程设备已开启远程桌面。'), findsOneWidget);
      await tester.ensureVisible(find.text('新建 RDP 连接'));
      await tester.tap(find.text('新建 RDP 连接'));
      await tester.pump();
      expect(api.callsTo('newRdp'), hasLength(1));

      await tester.tap(find.text('RDP 设置'));
      await _settle(tester);
      expect(find.text('停止后重新打开 RDP，新的设置才会生效。'), findsOneWidget);
      final port = find
          .descendant(
            of: find.byType(LgRdpSettingsDialog),
            matching: find.byType(EditableText),
          )
          .first;
      await tester.enterText(port, '70000');
      await tester.pump();
      expect(find.text('端口无效。端口应为 1~65535。'), findsOneWidget);
      await tester.enterText(port, '3391');
      await tester.pump();
      await tester.tap(find.text('确定'));
      await _settle(tester);
      expect(api.callsTo('setRdpSettings').single, [
        _id,
        (port: '3391', username: 'mama', password: ''),
      ]);
    },
  );

  testMainWindow('a row\'s notice names its target and can be closed', (
    tester,
  ) async {
    await open(tester);
    await row(tester, 'in_use', 15432, {'transport': 'direct'});
    await row(tester, 'notice', 15432, {
      'reason': {'code': 'tunnel_unreachable', 'target': '192.0.2.20:5432'},
    });
    const text = '无法访问 192.0.2.20:5432。请确认远程设备可以访问该地址，且端口已开放。';
    expect(_text(text), findsOneWidget);
    // The newest shows; closing it brings back the one before.
    await row(tester, 'notice', 15432, {
      'reason': {'code': 'tunnel_too_many_channels'},
    });
    expect(_text('经此隧道的连接数已达上限。'), findsOneWidget);
    expect(_text(text), findsNothing);
    await tester.tap(find.bySemanticsLabel('关闭通知'));
    await _settle(tester);
    expect(_text('经此隧道的连接数已达上限。'), findsNothing);
    expect(_text(text), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('关闭通知'));
    await _settle(tester);
    expect(_text(text), findsNothing);
  });

  testMainWindow(
    'the RDP settings of a device without a name show its ID once',
    (tester) async {
      await pumpMainWindow(tester);
      expect(handleLink(Uri.parse('leapgate://rdp/$_id')), true);
      await _settle(tester);
      await row(tester, 'in_use', 0, {'transport': 'direct'}, TunnelKind.rdp);
      await tester.ensureVisible(find.text('RDP 设置'));
      await tester.tap(find.text('RDP 设置'));
      await _settle(tester);
      final dialog = find.byType(LgRdpSettingsDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('100 200 300')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<LgPasswordField>(
              find.descendant(
                of: dialog,
                matching: find.byType(LgPasswordField),
              ),
            )
            .maxLength,
        128,
      );
    },
  );

  testMainWindow('a link opens the card; opened again it is only shown', (
    tester,
  ) async {
    await pumpMainWindow(tester);
    expect(
      handleLink(Uri.parse('leapgate://port-forward/$_id?relay=true')),
      true,
    );
    await _settle(tester);
    expect(api.callsTo('sessionAdd').single.last, true);
    expect(find.text('TCP 隧道'), findsOneWidget);
    expect(handleLink(Uri.parse('leapgate://port-forward/$_id')), true);
    await _settle(tester);
    expect(api.callsTo('sessionAdd'), hasLength(1));
    expect(handleLink(Uri.parse('leapgate://rdp/$_id')), true);
    await _settle(tester);
    expect(appCore.tunnels.cardOf(_id, TunnelKind.rdp), isNotNull);
  });

  test('closing with exit nodes and tunnels: one sentence for both', () {
    final l10n = lookupAppLocalizations(const Locale('zh'));
    String says(int exits, int tunnels, bool quit) =>
        backgroundSentence(l10n, exits: exits, tunnels: tunnels, quit: quit);
    expect(says(2, 0, false), '2 个出口将在后台继续运行。');
    expect(says(0, 1, false), '1 个隧道将在后台继续运行。');
    expect(says(1, 2, false), '1 个出口和 2 个隧道将在后台继续运行。');
    expect(says(0, 3, true), '3 个隧道将停止。');
    expect(says(1, 1, true), '1 个出口和 1 个隧道将停止。');
  });
}
