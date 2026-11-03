import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/exit_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/pages/home/exit/exit_card_view.dart';
import 'package:leapgate_ui/widgets/lg_title_bar.dart';

import '../../core/test/account_fakes.dart';
import '../../core/test/exit_fakes.dart' show FakeExitApi;
import 'session_fakes.dart';

// The exit page (01 P1 block I) in the main window, with E2 and the exit session played from the
// test. Device IDs and names are made up.

const _id = '100200300';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openExitPage(WidgetTester tester) async {
  await pumpMainWindow(tester);
  await tester.tap(find.text('出口'));
  await _settle(tester);
}

Finder _cardField() => find.descendant(
  of: find.byType(ExitCardView),
  matching: find.byType(EditableText),
);

void main() {
  late AppFakes fakes;
  late FakeExitApi api;

  setUp(() {
    fakes = installAppFakes();
    api = FakeExitApi();
    exitApi = api;
  });

  Future<void> e2(
    WidgetTester tester,
    String state, [
    Map<String, dynamic> extra = const {},
  ]) async {
    api.push(_id, state, extra);
    await _settle(tester);
  }

  Future<void> session(WidgetTester tester, Map<String, dynamic> evt) async {
    final card = appCore.exitNodes.cards.single;
    fakes.bind.streams[card.sessionId]!.add(EventToUI.event(jsonEncode(evt)));
    await _settle(tester);
  }

  testMainWindow(
    'by ID: the card logs in, takes the password, shows the proxy, stops',
    (tester) async {
      await _openExitPage(tester);
      expect(
        find.text('通过其他设备的网络访问互联网。仅对已配置代理的应用生效，且只支持 TCP 连接。'),
        findsOneWidget,
      );
      expect(find.text('暂无正在使用的出口'), findsOneWidget);
      expect(find.text('登录后可查看出口目录'), findsOneWidget);
      expect(api.callsTo('directory'), isEmpty);

      final idField = find.byType(EditableText).last;
      await tester.enterText(idField, '192.168.1.2');
      await tester.pump();
      await tester.tap(find.text('使用'));
      await tester.pump();
      expect(find.text('ID 格式不正确'), findsOneWidget);
      expect(appCore.exitNodes.cards, isEmpty);

      await tester.enterText(idField, '100 200 300');
      await tester.pump();
      await tester.tap(find.text('使用'));
      await _settle(tester);
      expect(
        find.textContaining('正在连接 100 200 300…', findRichText: true),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('出口，1 个正在使用'), findsOneWidget);
      expect(tester.widget<LgTitleBar>(find.byType(LgTitleBar)).homeBadge, 1);

      await session(tester, msgbox('input-password', 'Password Required', ''));
      expect(find.text('输入密码'), findsOneWidget);
      await tester.enterText(_cardField(), 'pw');
      await tester.pump();
      await tester.tap(find.text('连接'));
      await _settle(tester);
      expect(
        fakes.bind.callsTo(#sessionLogin).single.namedArguments[#password],
        'pw',
      );
      expect(find.textContaining('正在验证…', findRichText: true), findsOneWidget);

      await e2(tester, 'in_use', {'transport': 'relay'});
      expect(
        find.textContaining('可用 · 经中继', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('流量由中继服务器转发，速度可能较慢'), findsOneWidget);
      expect(find.text('socks5h://127.0.0.1:21180'), findsOneWidget);
      expect(find.text('http://127.0.0.1:21180'), findsOneWidget);
      await tester.tap(find.text('浏览器设置说明'));
      await tester.pump();
      expect(
        find.text(
          '• Chrome、Edge：使用代理扩展，或添加启动参数 --proxy-server=socks5://127.0.0.1:21180。',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('停止'));
      await _settle(tester);
      expect(api.callsTo('close'), hasLength(1));
      expect(find.text('暂无正在使用的出口'), findsOneWidget);
      expect(find.bySemanticsLabel('出口，1 个正在使用'), findsNothing);
    },
  );

  testMainWindow('the mark asks to come back while another page shows', (
    tester,
  ) async {
    await pumpMainWindow(tester);
    appCore.exitNodes.use(_id);
    await _settle(tester);
    await session(tester, msgbox('wait-remote-accept-nook', '', ''));
    expect(find.bySemanticsLabel('出口，1 个正在使用，需要处理'), findsOneWidget);

    await tester.tap(find.text('出口'));
    await _settle(tester);
    expect(find.bySemanticsLabel('出口，1 个正在使用'), findsOneWidget);
    expect(
      find.textContaining('正在等待对方接受…（已等待 0:0', findRichText: true),
      findsOneWidget,
    );
  });

  testMainWindow('stopped: the reason, and Retry only where it can help', (
    tester,
  ) async {
    fakes.lg.reasons['Exit not enabled'] = 'exit_not_enabled';
    await _openExitPage(tester);
    appCore.exitNodes.use(_id);
    await _settle(tester);
    await session(tester, msgbox('error', 'Login Error', 'Exit not enabled'));
    await e2(tester, 'stopped');
    expect(
      find.textContaining('已停止：远程设备未开启“允许作为出口”', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('移除'), findsOneWidget);

    await e2(tester, 'stopped', {
      'reason': {'code': 'exit_need_encryption'},
    });
    expect(
      find.textContaining('已停止：此连接未加密，无法用作出口', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('重试'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^出口，')), findsNothing);

    await e2(tester, 'port_in_use', {'port': 21180});
    expect(
      find.textContaining('本机端口 21180 已被其他应用占用', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.text('修改端口'));
    await tester.pump();
    await tester.enterText(_cardField(), '21190');
    await tester.tap(find.text('确定'));
    await tester.pump();
    expect(api.callsTo('setPort'), [
      [_id, 21190],
    ]);
  });

  testMainWindow('the directory: "Use" makes the card, the row says "In use"', (
    tester,
  ) async {
    accountApi = FakeAccountApi()
      ..loginResult = const ApiResult.ok(AccountUser(name: 'zhang'));
    await appCore.account.login('zhang', 'pw');
    api.directoryAnswer = (
      status: ExitDirectoryStatus.ok,
      exits: [
        const ExitNode(id: _id, hostname: '书房台式机', own: true),
        const ExitNode(id: '400500600', owner: 'lisi'),
      ],
    );
    await _openExitPage(tester);
    expect(find.text('书房台式机'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('所有者：lisi'), findsOneWidget);
    expect(find.text('使用中'), findsNothing);

    await tester.tap(find.text('使用').first);
    await _settle(tester);
    expect(find.text('使用中'), findsOneWidget);
    expect(
      find.textContaining('正在连接 书房台式机…', findRichText: true),
      findsOneWidget,
    );
    expect(appCore.exitNodes.cards.single.id, _id);
  });
}
