import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/shell/tab_overlays.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_login_dialog.dart';

import '../../core/test/account_fakes.dart';
import 'home_fakes.dart';

// The account area, the login dialog and the team devices (01 P1 blocks D, H, K; M4).

/// Calls that wait for the test while their gate is set.
class GatedAccountApi extends FakeAccountApi {
  Completer<void>? loginGate;
  Completer<void>? groupGate;

  @override
  Future<ApiResult<AccountUser>> login(String username, String password) async {
    await loginGate?.future;
    return super.login(username, password);
  }

  @override
  Future<ApiResult<GroupData>> group() async {
    await groupGate?.future;
    return super.group();
  }
}

const _alice = AccountUser(name: 'alice', displayName: '张三');

GroupData _team({bool onlyMe = false}) => GroupData(
  users: [
    if (!onlyMe) const AccountUser(name: 'bob', displayName: '李四'),
    _alice,
  ],
  peers: [
    groupPeer({
      'id': '123456789',
      'user_name': 'alice',
      'info': {'device_name': 'DESKTOP-ZHANG'},
    }),
    if (!onlyMe)
      groupPeer({
        'id': '234567891',
        'user_name': 'bob',
        'info': {'device_name': 'LAPTOP-LI'},
      }),
  ],
);

late FakeBind bind;
late GatedAccountApi api;

/// The home page's timers never let `pumpAndSettle` finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _inDialog(Finder f) =>
    find.descendant(of: find.byType(LgLoginDialog), matching: f);

Finder _button(String label) => find.widgetWithText(LgButton, label);

/// The home page; signed in as alice when [signedIn], with the team devices as [team] answers.
Future<void> pumpAccount(
  WidgetTester tester, {
  bool signedIn = false,
  ApiResult<GroupData>? team,
}) async {
  if (team != null) api.groupResult = team;
  if (signedIn) {
    api
      ..local = _alice
      ..currentUserResult = const ApiResult.ok(_alice);
  }
  await pumpHome(tester, overlays: TabOverlays());
  appCore.account.start();
  await settle(tester);
}

Future<void> openGroup(WidgetTester tester) async {
  await tester.tap(find.text('同组设备'));
  await settle(tester);
}

Future<void> openLoginDialog(WidgetTester tester) async {
  await tester.tap(_button('登录').first);
  await settle(tester);
}

Future<void> fillLogin(
  WidgetTester tester,
  String user,
  String password,
) async {
  final fields = _inDialog(find.byType(EditableText));
  await tester.enterText(fields.first, user);
  await tester.enterText(fields.last, password);
  await tester.tap(_inDialog(_button('登录')));
  await settle(tester);
}

void main() {
  setUp(() {
    bind = installHomeFakes().bind;
    api = GatedAccountApi();
    accountApi = api;
  });

  testWidgets(
    'signed out: the account area and the team devices offer to sign in',
    (tester) async {
      await pumpAccount(tester);
      expect(find.text('登录后可使用地址簿、同组设备和出口目录'), findsOneWidget);
      await openGroup(tester);
      expect(find.text('登录后可查看同组设备'), findsOneWidget);
      await tester.tap(_button('登录').last);
      await settle(tester);
      expect(find.byType(LgLoginDialog), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets(
    'the built-in option hides the account area and the team devices',
    (tester) async {
      bind.disabledOptions.add(#isDisableAccount);
      await pumpAccount(tester);
      expect(find.text('登录后可使用地址簿、同组设备和出口目录'), findsNothing);
      expect(find.text('同组设备'), findsNothing);
      await unmount(tester);
    },
  );

  group('login dialog', () {
    testWidgets('a missing user name, then a missing password', (tester) async {
      await pumpAccount(tester);
      await openLoginDialog(tester);
      await fillLogin(tester, '  ', '');
      expect(find.text('请输入用户名'), findsOneWidget);
      await fillLogin(tester, 'alice', '');
      expect(find.text('请输入密码'), findsOneWidget);
      expect(api.callsTo('login'), isEmpty);
      await unmount(tester);
    });

    testWidgets("the server's refusals show under the password", (
      tester,
    ) async {
      await pumpAccount(tester);
      await openLoginDialog(tester);
      for (final (error, text) in [
        (const ApiError(ApiErrorKind.wrongCredentials, 'x'), '用户名或密码错误'),
        (
          const ApiError(ApiErrorKind.verificationRequired),
          '此服务器要求验证码登录，Leapgate 暂不支持',
        ),
        (const ApiError(ApiErrorKind.network, 'timed out'), '无法连接服务器。请检查网络连接。'),
        (
          const ApiError(ApiErrorKind.server, 'Too many requests'),
          '无法登录。服务器返回：Too many requests。',
        ),
      ]) {
        api.loginResult = ApiResult.error(error);
        await fillLogin(tester, 'alice', 'secret');
        expect(find.text(text), findsOneWidget);
      }
      expect(find.byType(LgLoginDialog), findsOneWidget);
      expect(appCore.account.loggedIn, isFalse);
      await unmount(tester);
    });

    testWidgets(
      'signing in: busy, then closed and signed in; the name comes back next time',
      (tester) async {
        api
          ..loginGate = Completer()
          ..loginResult = const ApiResult.ok(_alice)
          ..groupResult = ApiResult.ok(_team());
        await pumpAccount(tester);
        await openLoginDialog(tester);
        final fields = _inDialog(find.byType(EditableText));
        await tester.enterText(fields.first, ' alice ');
        await tester.enterText(fields.last, 'secret');
        await tester.tap(_inDialog(_button('登录')));
        await tester.pump();
        expect(find.text('正在登录…'), findsOneWidget);

        api.loginGate!.complete();
        await settle(tester);
        expect(find.byType(LgLoginDialog), findsNothing);
        expect(api.callsTo('login'), [
          ['alice', 'secret'],
        ]);
        expect(find.text('张三'), findsOneWidget);

        await appCore.account.logout();
        await settle(tester);
        await openLoginDialog(tester);
        expect(find.text('alice'), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets('without the login options: the note and a retry', (
      tester,
    ) async {
      api.loginOptionsResult = const ApiResult.error(
        ApiError(ApiErrorKind.network, 'timed out'),
      );
      await pumpAccount(tester);
      await openLoginDialog(tester);
      expect(find.text('无法获取登录选项。请检查网络连接。'), findsOneWidget);
      api.loginOptionsResult = const ApiResult.ok(null);
      await tester.tap(_inDialog(_button('重试')));
      await settle(tester);
      expect(find.text('无法获取登录选项。请检查网络连接。'), findsNothing);
      expect(api.callsTo('loginOptions'), hasLength(2));
      await unmount(tester);
    });
  });

  testWidgets(
    'a confirmation open when the server signs out is gone next time',
    (tester) async {
      await pumpAccount(tester, signedIn: true, team: ApiResult.ok(_team()));
      await tester.tap(find.text('张三'));
      await settle(tester);
      await tester.tap(find.text('退出登录'));
      await settle(tester);
      expect(find.text('退出登录？'), findsOneWidget);
      appCore.account.signedOutByServer();
      await settle(tester);
      api.loginResult = const ApiResult.ok(_alice);
      await appCore.account.login('alice', 'secret');
      await settle(tester);
      expect(find.text('退出登录？'), findsNothing);
      expect(find.text('张三'), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets('signing out asks in the page first', (tester) async {
    await pumpAccount(tester, signedIn: true, team: ApiResult.ok(_team()));
    await tester.tap(find.text('张三'));
    await settle(tester);
    expect(find.text('账号信息'), findsOneWidget);
    await tester.tap(find.text('退出登录'));
    await settle(tester);
    expect(find.text('退出登录？'), findsOneWidget);
    expect(find.text('退出后，地址簿、同组设备和出口目录将不可用。'), findsOneWidget);

    await tester.tap(_button('取消'));
    await settle(tester);
    expect(find.text('退出登录？'), findsNothing);
    expect(api.callsTo('logout'), isEmpty);

    await tester.tap(find.text('张三'));
    await settle(tester);
    await tester.tap(find.text('退出登录'));
    await settle(tester);
    await tester.tap(_button('退出登录'));
    await settle(tester);
    expect(api.callsTo('logout'), hasLength(1));
    expect(find.text('登录后可使用地址簿、同组设备和出口目录'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a token the server no longer takes signs out everywhere', (
    tester,
  ) async {
    await pumpAccount(tester, signedIn: true, team: ApiResult.ok(_team()));
    await openGroup(tester);
    expect(find.text('LAPTOP-LI'), findsOneWidget);
    api.groupResult = const ApiResult.error(
      ApiError(ApiErrorKind.unauthorized),
    );
    await tester.tap(find.bySemanticsLabel('刷新'));
    await settle(tester);
    expect(find.text('LAPTOP-LI'), findsNothing);
    expect(find.text('登录后可查看同组设备'), findsOneWidget);
    expect(find.text('登录后可使用地址簿、同组设备和出口目录'), findsOneWidget);
    await unmount(tester);
  });

  group('team devices', () {
    testWidgets('loading until the first answer', (tester) async {
      api.groupGate = Completer();
      await pumpAccount(tester, signedIn: true, team: ApiResult.ok(_team()));
      await openGroup(tester);
      expect(find.bySemanticsLabel('正在加载…'), findsOneWidget);
      api.groupGate!.complete();
      await settle(tester);
      expect(find.text('LAPTOP-LI'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('picking a person shows their devices; again shows everyone', (
      tester,
    ) async {
      await pumpAccount(tester, signedIn: true, team: ApiResult.ok(_team()));
      await openGroup(tester);
      // This user first, marked.
      expect(
        tester.getTopLeft(find.text('张三').last).dy <
            tester.getTopLeft(find.text('李四')).dy,
        isTrue,
      );
      expect(find.text('（我）'), findsOneWidget);
      await tester.tap(find.text('李四'));
      await settle(tester);
      expect(find.text('DESKTOP-ZHANG'), findsNothing);
      expect(find.text('LAPTOP-LI'), findsOneWidget);
      await tester.tap(find.text('李四'));
      await settle(tester);
      expect(find.text('DESKTOP-ZHANG'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('only this user: the list has "我" alone', (tester) async {
      await pumpAccount(
        tester,
        signedIn: true,
        team: ApiResult.ok(_team(onlyMe: true)),
      );
      await openGroup(tester);
      expect(find.text('（我）'), findsOneWidget);
      expect(find.text('李四'), findsNothing);
      expect(find.text('DESKTOP-ZHANG'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('empty', (tester) async {
      await pumpAccount(
        tester,
        signedIn: true,
        team: const ApiResult.ok(GroupData(users: [_alice], peers: [])),
      );
      await openGroup(tester);
      expect(find.bySemanticsLabel('暂无同组设备'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a network error offers to retry', (tester) async {
      await pumpAccount(
        tester,
        signedIn: true,
        team: const ApiResult.error(
          ApiError(ApiErrorKind.network, 'timed out'),
        ),
      );
      await openGroup(tester);
      expect(find.text('无法连接服务器'), findsOneWidget);
      api.groupResult = ApiResult.ok(_team());
      await tester.tap(_button('重试'));
      await settle(tester);
      expect(find.text('LAPTOP-LI'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the account check failing offers to retry it', (tester) async {
      api.currentUserResult = const ApiResult.error(
        ApiError(ApiErrorKind.network, 'timed out'),
      );
      api
        ..local = _alice
        ..groupResult = ApiResult.ok(_team());
      await pumpHome(tester, overlays: TabOverlays());
      appCore.account.start();
      await settle(tester);
      await openGroup(tester);
      expect(find.text('无法连接服务器'), findsOneWidget);
      api.currentUserResult = const ApiResult.ok(_alice);
      await tester.tap(_button('重试'));
      await settle(tester);
      expect(find.text('LAPTOP-LI'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets(
      "the account check refused by the server says why and retries it",
      (tester) async {
        api.currentUserResult = const ApiResult.error(
          ApiError(ApiErrorKind.server, 'HTTP 502'),
        );
        api
          ..local = _alice
          ..groupResult = ApiResult.ok(_team());
        await pumpHome(tester, overlays: TabOverlays());
        appCore.account.start();
        await settle(tester);
        await openGroup(tester);
        expect(find.text('无法加载同组设备。服务器返回：HTTP 502。'), findsOneWidget);
        api.currentUserResult = const ApiResult.ok(_alice);
        await tester.tap(_button('重试'));
        await settle(tester);
        expect(find.text('LAPTOP-LI'), findsOneWidget);
        await unmount(tester);
      },
    );

    testWidgets("the server's error: a banner over what the list had", (
      tester,
    ) async {
      await pumpAccount(tester, signedIn: true, team: ApiResult.ok(_team()));
      await openGroup(tester);
      api.groupResult = const ApiResult.error(
        ApiError(ApiErrorKind.server, 'HTTP 500'),
      );
      await tester.tap(find.bySemanticsLabel('刷新'));
      await settle(tester);
      expect(find.text('无法加载同组设备。服务器返回：HTTP 500。'), findsOneWidget);
      expect(find.text('LAPTOP-LI'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('关闭'));
      await settle(tester);
      expect(find.text('无法加载同组设备。服务器返回：HTTP 500。'), findsNothing);
      await unmount(tester);
    });
  });
}
