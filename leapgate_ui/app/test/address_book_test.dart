import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/account.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/pages/home/address_book/ab_dialogs.dart';
import 'package:leapgate_ui/pages/home/address_book/address_book.dart';
import 'package:leapgate_ui/pages/home/peer_views.dart';
import 'package:leapgate_ui/shell/navigation.dart';
import 'package:leapgate_ui/shell/tab_overlays.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_device.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';

import '../../core/test/account_fakes.dart';
import 'home_fakes.dart';

// The address book category's states and dialogs (01 P1 blocks F and G, 07 §5.1). The category
// tab is A's (`PeerTabs.isEnabled`), so its view is pumped here on its own.

class _Account extends AccountModel {
  _Account() : super(FakeAccountApi(), others: const []);

  AccountUser? signedIn = const AccountUser(name: 'zhangsan');
  ApiError? failed;

  @override
  AccountUser? get user => signedIn;

  @override
  bool get loggedIn => signedIn != null;

  @override
  ApiError? get error => failed;

  @override
  void signedOutByServer() {
    signedIn = null;
    appCore.addressBook.reset();
    notifyListeners();
  }
}

class _Core extends AppCore {
  _Core() : super(window: FakeWindow());

  final _account = _Account();

  @override
  AccountModel get account => _account;
}

class _Navigation extends FakeNavigation {
  final passwords = <String>[];

  @override
  void connect(
    String id, {
    String password = '',
    bool isSharedPassword = false,
    bool forceRelay = false,
    String switchUuid = '',
  }) {
    passwords.add('$id:$password:$isSharedPassword');
  }
}

late FakeAccountApi api;
late _Navigation _nav;
late FakeBind _bind;

/// The device menu of [item] drawn in place.
Future<void> _pumpMenu(
  WidgetTester tester,
  PeerItem item, {
  bool hasPassword = false,
}) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
    home: Builder(
      builder: (context) => SingleChildScrollView(
        child: LgMenuPanel(
          items: peerMenuItems(
            AppLocalizations.of(context)!,
            item,
            overlays: overlays,
            hasPassword: hasPassword,
          ),
        ),
      ),
    ),
  ),
);

PeerItem _item(Peer peer, PeerCategory category) => PeerItem(
  peer: peer,
  category: category,
  status: LgDeviceStatus.online,
  statusLabel: '在线',
  favorite: false,
);
final overlays = TabOverlays();

_Account get _signedIn => appCore.account as _Account;

Peer _peer(String id, {String alias = '', String password = ''}) =>
    Peer.fromJson({'id': id, 'alias': alias, 'password': password});

/// The personal book and, when given, the shared ones, each with the devices given.
void _serve({
  List<Peer> personal = const [],
  List<(AbProfile, List<Peer>)> shared = const [],
  List<AbTag> tags = const [AbTag('家里', 0xFFE91E63)],
}) {
  api.booksResult = ApiResult.ok(
    AbBooks(
      maxPeers: 0,
      personal: 'g-me',
      shared: [for (final (b, _) in shared) b],
    ),
  );
  api.bookResults['g-me'] = ApiResult.ok(
    AbBookData(peers: personal, tags: tags),
  );
  for (final (b, peers) in shared) {
    api.bookResults[b.guid] = ApiResult.ok(
      AbBookData(peers: peers, tags: tags),
    );
  }
}

const _friends = AbProfile(
  guid: 'g-friends',
  name: '朋友们',
  owner: 'lisi',
  rule: 1,
);

/// The category's tools, header and state (or its devices by ID) over the home tab's overlay.
Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  appCore.account,
                  appCore.addressBook,
                ]),
                builder: (context, _) {
                  final view = addressBookCategory(context, overlays);
                  return Column(
                    children: [
                      Row(children: view.tools),
                      ?view.header,
                      Expanded(
                        child:
                            view.state ??
                            ListView(
                              children: [
                                for (final p in appCore.addressBook.shownPeers)
                                  Text('device ${p.id}'),
                              ],
                            ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Positioned.fill(child: Overlay(key: overlays.keyOf(null))),
          ],
        ),
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  // The whole home page, signed in through the account model.
  testWidgets('the connect box finds address book devices, by their note too', (
    tester,
  ) async {
    installHomeFakes();
    api = FakeAccountApi();
    accountApi = api;
    const me = AccountUser(name: 'zhangsan');
    api.local = me;
    api.currentUserResult = const ApiResult.ok(me);
    api.groupResult = const ApiResult.ok(GroupData(users: [], peers: []));
    _serve(
      personal: [
        Peer.fromJson({'id': '987654321', 'alias': '阳台电脑', 'note': '显卡驱动别升级'}),
      ],
    );
    await appCore.account.start();
    await pumpHome(tester, id: '135792468');
    await loadRecent([]);
    await loadCategory('load_fav_peers', []);
    await loadCategory('load_lan_peers', []);
    await tester.enterText(find.byType(EditableText), '显卡');
    await tester.pump();
    expect(find.text('阳台电脑'), findsOneWidget);
    expect(find.text('正在加载其他分类…'), findsNothing);
    await unmount(tester);
  });

  group('the category', _categoryTests);
}

void _categoryTests() {
  setUp(() {
    _bind = FakeBind();
    platformFFI.setBindingForTesting(_bind);
    setLgBindForTesting(FakeLeapgate());
    api = FakeAccountApi();
    accountApi = api;
    appCore = _Core();
    addTearDown(appCore.recentPeers.dispose);
    addTearDown(appCore.favPeers.dispose);
    addTearDown(appCore.lanPeers.dispose);
    _nav = _Navigation();
    mainNavigation = _nav;
  });

  testWidgets('signed out: a sentence and "登录"', (tester) async {
    _signedIn.signedIn = null;
    await _pump(tester);
    expect(find.text('登录后可查看地址簿'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets('loading, then the books and their devices, then empty', (
    tester,
  ) async {
    _serve(personal: [_peer('123456789')]);
    await _pump(tester);
    expect(find.bySemanticsLabel('正在加载…'), findsOneWidget);

    await appCore.addressBook.pull();
    await tester.pump();
    expect(find.text('我的地址簿'), findsOneWidget);
    expect(find.text('完全控制'), findsOneWidget);
    expect(find.text('device 123456789'), findsOneWidget);

    _serve(personal: []);
    await tester.tap(find.text('刷新'));
    await tester.pump();
    await tester.pump();
    expect(find.text('此地址簿中暂无设备'), findsOneWidget);
  });

  testWidgets(
    'a server without an address book says so, with nothing to retry',
    (tester) async {
      api.booksResult = const ApiResult.error(
        ApiError(ApiErrorKind.unsupported),
      );
      await appCore.addressBook.pull();
      await _pump(tester);
      expect(find.text('当前服务器不提供地址簿。'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
    },
  );

  testWidgets('no server: "无法连接服务器" and "重试" pulls again', (tester) async {
    api.booksResult = const ApiResult.error(ApiError(ApiErrorKind.network));
    await appCore.addressBook.pull();
    await _pump(tester);
    expect(find.text('无法连接服务器'), findsOneWidget);

    _serve(personal: [_peer('123456789')]);
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    expect(find.text('device 123456789'), findsOneWidget);
  });

  testWidgets('a server error: the banner over the list, closable', (
    tester,
  ) async {
    _serve(personal: [_peer('123456789')]);
    await appCore.addressBook.pull();
    api.booksResult = const ApiResult.error(
      ApiError(ApiErrorKind.server, '服务暂时不可用'),
    );
    await appCore.addressBook.pull();
    await _pump(tester);
    expect(
      find.textContaining('无法加载地址簿。服务器返回：服务暂时不可用。', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('device 123456789'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('关闭'));
    await tester.pump();
    expect(find.textContaining('无法加载地址簿', findRichText: true), findsNothing);
  });

  testWidgets(
    'a read-only book: its "更多" keeps the filter, the device menu greys what writes and says why once',
    (tester) async {
      _serve(
        shared: [
          (_friends, [_peer('345678912', alias: '李四的台式机')]),
        ],
      );
      await appCore.addressBook.pull();
      await appCore.addressBook.select(appCore.addressBook.books[1]);
      await _pump(tester);
      expect(find.text('只读 · 所有者：lisi'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('更多'));
      await _settle(tester);
      expect(find.text('添加设备'), findsNothing);
      expect(find.text('匹配全部所选标签'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await _settle(tester);

      final item = PeerItem(
        peer: appCore.addressBook.peers.single,
        category: PeerCategory.addressBook,
        status: LgDeviceStatus.online,
        statusLabel: '在线',
        favorite: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildLgTheme(
            brightness: Brightness.light,
            mode: LgMode.compact,
          ),
          home: Builder(
            builder: (context) => SingleChildScrollView(
              child: LgMenuPanel(
                items: peerMenuItems(
                  AppLocalizations.of(context)!,
                  item,
                  overlays: overlays,
                  hasPassword: false,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('此地址簿为只读'), findsOneWidget);
      MenuItemButton button(String label) => tester.widget<MenuItemButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(MenuItemButton),
        ),
      );
      for (final greyed in ['重命名', '编辑备注', '设置共享密码', '从地址簿中删除']) {
        expect(button(greyed).onPressed, isNull, reason: greyed);
      }
      for (final usable in ['加入收藏', '加入地址簿', '查看所在地址簿']) {
        expect(button(usable).onPressed, isNotNull, reason: usable);
      }
    },
  );

  testWidgets(
    'the server refusing the sign-in check: the whole list says so, "重试" checks again',
    (tester) async {
      _signedIn.failed = const ApiError(ApiErrorKind.server, '服务暂时不可用');
      await _pump(tester);
      expect(find.text('无法加载地址簿。服务器返回：服务暂时不可用。'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    },
  );

  testWidgets('a failed change: the banner, gone once "重试" pulls again', (
    tester,
  ) async {
    _serve(personal: [_peer('123456789')]);
    await appCore.addressBook.pull();
    await _pump(tester);
    api.writeResult = const ApiResult.error(
      ApiError(ApiErrorKind.server, '服务暂时不可用'),
    );
    await tester.tap(find.text('家里'), buttons: 2);
    await _settle(tester);
    await tester.tap(find.text('删除'));
    await _settle(tester);
    expect(
      find.textContaining('无法保存地址簿的更改。服务器返回：服务暂时不可用。', findRichText: true),
      findsOneWidget,
    );
    api.writeResult = const ApiResult.ok(null);
    await tester.tap(find.text('重试'));
    await _settle(tester);
    expect(find.textContaining('无法保存地址簿的更改', findRichText: true), findsNothing);
  });

  testWidgets('"清除保存的密码" in "最近" clears the personal book\'s copy too', (
    tester,
  ) async {
    _serve(
      personal: [
        Peer.fromJson({'id': '123456789', 'hash': 'h'}),
      ],
    );
    await appCore.addressBook.pull();
    await _pumpMenu(
      tester,
      _item(_peer('123456789'), PeerCategory.recent),
      hasPassword: true,
    );
    await tester.tap(find.text('清除保存的密码'));
    await _settle(tester);
    expect(api.callsTo('updatePeer'), [
      [
        'g-me',
        '123456789',
        {'hash': ''},
      ],
    ]);
    expect(_bind.callsTo(#mainForgetPassword), hasLength(1));
    await toastGone(tester);
  });

  testWidgets(
    'adding straight into the only book: a failure opens the dialog to say so',
    (tester) async {
      _serve();
      await appCore.addressBook.pull();
      await _pump(tester);
      api.writeResult = const ApiResult.error(
        ApiError(ApiErrorKind.server, '服务暂时不可用'),
      );
      final l10n = lookupAppLocalizations(const Locale('zh'));
      unawaited(
        showAbAddToDialog(overlays, l10n, [
          _peer('987654321'),
        ], appCore.addressBook.addTargets(PeerCategory.recent)),
      );
      await _settle(tester);
      expect(
        find.textContaining('无法添加设备。服务器返回：服务暂时不可用。', findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets('a token found expired while a dialog submits closes it', (
    tester,
  ) async {
    _serve();
    await appCore.addressBook.pull();
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('更多'));
    await _settle(tester);
    await tester.tap(find.text('添加设备'));
    await _settle(tester);
    api.writeResult = const ApiResult.error(
      ApiError(ApiErrorKind.unauthorized),
    );
    await tester.enterText(find.bySemanticsLabel('ID').last, '246813579');
    await tester.pump();
    await tester.tap(find.text('添加').last);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('添加到：我的地址簿'), findsNothing);
    expect(find.text('登录后可查看地址簿'), findsOneWidget);
  });

  testWidgets('connecting from a shared book takes its stored password', (
    tester,
  ) async {
    _serve(
      shared: [
        (_friends, [_peer('345678912', password: 'pw')]),
      ],
    );
    await appCore.addressBook.pull();
    await appCore.addressBook.select(appCore.addressBook.books[1]);
    connectPeer('345678912', category: PeerCategory.addressBook);
    connectPeer('345678912', category: PeerCategory.recent);
    expect(_nav.passwords, ['345678912:pw:true', '345678912::false']);
  });

  group('add device (p1-dlg-add)', () {
    Future<void> open(WidgetTester tester) async {
      await appCore.addressBook.pull();
      await _pump(tester);
      await tester.tap(find.bySemanticsLabel('更多'));
      await _settle(tester);
      await tester.tap(find.text('添加设备'));
      await _settle(tester);
    }

    Future<void> add(WidgetTester tester, String id) async {
      await tester.enterText(find.bySemanticsLabel('ID').last, id);
      await tester.pump();
      await tester.tap(find.text('添加').last);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('an ID already in the book', (tester) async {
      _serve(personal: [_peer('123456789')]);
      await open(tester);
      await add(tester, '123 456 789');
      expect(find.text('该 ID 已在此地址簿中'), findsOneWidget);
      expect(api.callsTo('addPeer'), isEmpty);
    });

    testWidgets('the server refuses: two sentences, the dialog stays', (
      tester,
    ) async {
      _serve();
      await open(tester);
      api.writeResult = const ApiResult.error(
        ApiError(ApiErrorKind.server, '服务暂时不可用'),
      );
      await add(tester, '246813579');
      expect(
        find.textContaining('无法添加设备。服务器返回：服务暂时不可用。', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('添加设备'), findsOneWidget);
    });

    testWidgets('added: the list shows it', (tester) async {
      _serve();
      await open(tester);
      api.bookResults['g-me'] = ApiResult.ok(
        AbBookData(peers: [_peer('246813579')], tags: const []),
      );
      await add(tester, '246813579');
      await _settle(tester);
      expect(api.callsTo('addPeer').single[1], containsPair('id', '246813579'));
      expect(find.text('device 246813579'), findsOneWidget);
    });
  });

  group('tag colour (p1-tagcolor-*)', () {
    Future<void> open(WidgetTester tester) async {
      _serve();
      await appCore.addressBook.pull();
      await _pump(tester);
      await tester.tap(find.text('家里'), buttons: 2);
      await _settle(tester);
      await tester.tap(find.text('修改颜色'));
      await _settle(tester);
    }

    testWidgets('a bad colour value can not be saved', (tester) async {
      await open(tester);
      await tester.enterText(find.bySemanticsLabel('颜色值').last, '#C4527');
      await tester.pump();
      expect(find.text('颜色值格式不正确'), findsOneWidget);
    });

    testWidgets('the server refuses: the dialog says so and stays', (
      tester,
    ) async {
      await open(tester);
      api.writeResult = const ApiResult.error(
        ApiError(ApiErrorKind.server, '服务暂时不可用'),
      );
      await tester.enterText(find.bySemanticsLabel('颜色值').last, '#E0852B');
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('无法修改标签颜色。服务器返回：服务暂时不可用。', findRichText: true),
        findsOneWidget,
      );
      expect(api.callsTo('setTagColor').single, ['g-me', '家里', 0xFFE0852B]);
    });
  });
}
