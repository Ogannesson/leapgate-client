import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/settings/settings_api.dart';
import 'package:flutter_hbb/leapgate/settings/unlock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/pages/settings/settings_section_state.dart';
import 'package:leapgate_ui/shell/navigation.dart';
import 'package:leapgate_ui/shell/tab_overlays.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';
import 'package:leapgate_ui/widgets/lg_settings_layout.dart';
import 'package:leapgate_ui/widgets/lg_settings_rows.dart';

import 'home_fakes.dart';
import 'settings_fakes.dart';

// The settings page's frame, search and lock, and the sections 访问与密码, 权限, 服务与 ID
// (02 §1.2, §1.3.1, §1.3.2, §1.3.8, §1.10; M6a coder A).

late FakeBind bind;

Future<LocalStatusModel> pumpSettings(
  WidgetTester tester, {
  SettingsSectionId? section,
  String? item,
  ServiceStatus status = ServiceStatus.ready,
  Size size = const Size(1280, 760),
}) async {
  final model = await pumpHome(
    tester,
    id: '135792468',
    status: status,
    size: size,
    setUp: (m) => m.oneTimePassword = 'a1b2c3',
  );
  if (section == null) {
    await tester.tap(find.text('设置'));
  } else {
    settingsPageRequests.request(section, item: item);
  }
  await settle(tester);
  return model;
}

/// Dialogs fade in; marks and scrolling take their time.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Scrolls [finder] into view and taps it.
Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) =>
    tapOn(tester, find.text(text).last);

Finder switchFinder(String label) =>
    find.byWidgetPredicate((w) => w is LgSwitch && w.semanticLabel == label);

LgSwitch switchOf(WidgetTester tester, String label) =>
    tester.widget<LgSwitch>(switchFinder(label));

bool enabled(WidgetTester tester, String label) =>
    tester
        .widget<LgButton>(find.widgetWithText(LgButton, label).last)
        .onPressed !=
    null;

LgButtonKind kindOf(WidgetTester tester, String label) =>
    tester.widget<LgButton>(find.widgetWithText(LgButton, label).last).kind;

/// Whether the row of [name] is marked.
bool isMarked(WidgetTester tester, String name) => tester
    .widget<LgSettingsRow>(
      find
          .ancestor(of: find.text(name), matching: find.byType(LgSettingsRow))
          .first,
    )
    .marked;

/// Ends the 2-second mark and takes the page down.
Future<void> done(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await unmount(tester);
}

Future<void> unlockWithAdmin(WidgetTester tester) async {
  await tapText(tester, '解锁');
  expect(find.text('已锁定。修改这些设置需要管理员权限。'), findsNothing);
}

void main() {
  setUp(() {
    bind = installHomeFakes().bind;
    settingsApi = FakeSettingsApi()..writeThrough = true;
  });

  group('frame (02 §1.2.1~§1.2.3)', () {
    // First in the file: the section is remembered for the run.
    testWidgets('opens at 访问与密码 first, then where it was left', (tester) async {
      await pumpSettings(tester);
      expect(find.text('传入连接'), findsOneWidget);
      expect(find.text('通用'), findsOneWidget);
      expect(find.text('审批方式'), findsOneWidget);

      await tapText(tester, '权限');
      expect(find.text('访问模式'), findsOneWidget);
      await done(tester);

      await pumpSettings(tester);
      expect(find.text('访问模式'), findsOneWidget);
      await done(tester);
    });

    testWidgets('a link opens the section scrolled to the item', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        section: SettingsSectionId.permissions,
        item: kOptionEnableTunnel,
        size: const Size(1280, 600),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final row = tester.getRect(find.text('允许建立 TCP 隧道'));
      expect(row.bottom, lessThan(600));
      expect(row.top, greaterThan(0));
      // Marked for about 2 seconds (02 §1.2.4), and only that item.
      expect(isMarked(tester, '允许建立 TCP 隧道'), isTrue);
      expect(isMarked(tester, '允许远程重启'), isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(isMarked(tester, '允许建立 TCP 隧道'), isFalse);
      await done(tester);
    });
  });

  testWidgets('the three sections fit the 960×600 window, locked', (
    tester,
  ) async {
    bind.installed = true;
    for (final section in [
      SettingsSectionId.access,
      SettingsSectionId.permissions,
      SettingsSectionId.service,
    ]) {
      await pumpSettings(tester, section: section, size: const Size(960, 600));
      expect(tester.takeException(), isNull);
      await done(tester);
    }
  });

  group('search (02 §1.2.4)', () {
    testWidgets('results with where they are, or none', (tester) async {
      await pumpSettings(tester, section: SettingsSectionId.access);
      await tester.enterText(find.byType(EditableText).first, '密码');
      await tester.pump();
      expect(find.text('传入连接 › 访问与密码'), findsWidgets);
      expect(find.text('固定密码'), findsOneWidget);
      // A choice matched by its options lists them.
      expect(find.text('输入密码 · 在本机接受 · 输入密码或在本机接受'), findsOneWidget);
      expect(find.text('审批方式'), findsOneWidget);

      await tester.enterText(find.byType(EditableText).first, 'zzz');
      await tester.pump();
      expect(find.text('未找到匹配的设置'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('未找到匹配的设置'), findsNothing);
      expect(find.text('审批方式'), findsOneWidget);
      await done(tester);
    });

    testWidgets('ignores case; arrows and Enter open a result', (tester) async {
      await pumpSettings(tester);
      await tester.enterText(find.byType(EditableText).first, 'tcp');
      await tester.pump();
      expect(find.text('传入连接 › 权限'), findsOneWidget);

      // The exit node and connection sections match too ("仅 TCP", "TCP 打洞"): down to the
      // second result and back up to the first.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.text('传入连接 › 权限'), findsNothing);
      expect(find.text('访问模式'), findsOneWidget);
      expect(find.text('允许建立 TCP 隧道'), findsOneWidget);
      await done(tester);
    });

    testWidgets('a click on a result opens it and clears the box', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tester.enterText(find.byType(EditableText).first, '解锁');
      await tester.pump();
      // The portable version has no unlock PIN.
      expect(find.text('未找到匹配的设置'), findsOneWidget);
      await tester.enterText(find.byType(EditableText).first, '本机 ID');
      await tester.pump();
      await tapText(tester, '本机 ID');
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .controller
            .text,
        isEmpty,
      );
      expect(find.text('服务'), findsOneWidget);
      await done(tester);
    });

    testWidgets(
      'a section\'s name finds the section; it opens with nothing marked',
      (tester) async {
        await pumpSettings(tester, section: SettingsSectionId.access);
        await tester.enterText(find.byType(EditableText).first, '外观');
        await tester.pump();
        final hit = find.bySemanticsLabel('通用, 外观');
        expect(hit, findsOneWidget);
        await tapOn(tester, hit);
        expect(
          tester
              .widget<LgSettingsNavItem>(
                find.widgetWithText(LgSettingsNavItem, '外观'),
              )
              .selected,
          isTrue,
        );
        expect(
          find.byWidgetPredicate((w) => w is LgSettingsRow && w.marked),
          findsNothing,
        );
        await done(tester);
      },
    );
  });

  group('lock (02 §1.2.6)', () {
    testWidgets('the portable version is never locked', (tester) async {
      await pumpSettings(tester, section: SettingsSectionId.access);
      expect(find.text('已锁定。修改这些设置需要管理员权限。'), findsNothing);
      await tapText(tester, '在本机接受');
      expect(bind.config[kOptionApproveMode], 'click');
      await done(tester);
    });

    testWidgets('installed: greyed until administrator permission unlocks it', (
      tester,
    ) async {
      bind.installed = true;
      await pumpSettings(tester, section: SettingsSectionId.access);
      expect(find.text('已锁定。修改这些设置需要管理员权限。'), findsOneWidget);
      await tapText(tester, '在本机接受');
      expect(bind.config, isEmpty);

      await unlockWithAdmin(tester);
      expect(bind.callsTo(#mainCheckSuperUserPermission), hasLength(1));
      await tapText(tester, '在本机接受');
      expect(bind.config[kOptionApproveMode], 'click');
      await done(tester);
    });

    testWidgets(
      'administrator permission refused: the red line, still locked',
      (tester) async {
        bind
          ..installed = true
          ..superUser = false;
        await pumpSettings(tester, section: SettingsSectionId.permissions);
        await tapText(tester, '解锁');
        expect(find.text('未获得管理员权限，设置仍处于锁定状态'), findsOneWidget);
        expect(find.text('已锁定。修改这些设置需要管理员权限。'), findsOneWidget);
        await done(tester);
      },
    );

    testWidgets(
      'with a PIN: "PIN 错误", the right one, or administrator permission',
      (tester) async {
        bind
          ..installed = true
          ..unlockPin = '2468';
        await pumpSettings(tester, section: SettingsSectionId.access);
        await tapText(tester, '解锁');
        expect(find.text('输入解锁 PIN'), findsWidgets);
        expect(bind.callsTo(#mainCheckSuperUserPermission), isEmpty);

        await tester.enterText(find.byType(EditableText).last, '1357');
        await tapText(tester, '解锁');
        expect(find.text('PIN 错误'), findsOneWidget);
        await tester.enterText(find.byType(EditableText).last, ' 2468 ');
        await tapText(tester, '解锁');
        expect(find.text('已锁定。修改这些设置需要管理员权限。'), findsNothing);

        settingsUnlock.lock();
        await settle(tester);
        await tapText(tester, '解锁');
        await tapText(tester, '改用管理员权限解锁');
        expect(bind.callsTo(#mainCheckSuperUserPermission), hasLength(1));
        expect(find.text('已锁定。修改这些设置需要管理员权限。'), findsNothing);
        await done(tester);
      },
    );

    testWidgets('one unlock for every section; another home page locks again', (
      tester,
    ) async {
      bind.installed = true;
      await pumpSettings(tester, section: SettingsSectionId.access);
      await unlockWithAdmin(tester);
      await tapText(tester, '权限');
      expect(find.text('已锁定。修改这些设置需要管理员权限。'), findsNothing);

      await tapText(tester, '设备');
      await tapText(tester, '设置');
      expect(find.text('已锁定。修改这些设置需要管理员权限。'), findsOneWidget);
      await done(tester);
    });
  });

  test('"无法保存设置" already shown follows a change of language', () async {
    final state = SettingsSectionState(
      overlays: TabOverlays(),
      saveFailedText: '无法保存设置',
    );
    addTearDown(state.dispose);
    await state.save('x', () async => false);
    expect(state.errorOf('x'), '无法保存设置');
    state.saveFailedText = "Couldn't save the setting";
    expect(state.errorOf('x'), "Couldn't save the setting");
    await state.save('x', () async => true);
    expect(state.errorOf('x'), isNull);
  });

  group('访问与密码 (02 §1.3.1)', () {
    testWidgets('a save the service refuses: "无法保存设置", the value stays', (
      tester,
    ) async {
      (settingsApi as FakeSettingsApi).saveResult = SaveResult.failed;
      await pumpSettings(tester, section: SettingsSectionId.access);
      await tapText(tester, '在本机接受');
      expect(find.text('无法保存设置'), findsOneWidget);
      expect(bind.config.containsKey(kOptionApproveMode), isFalse);
      final click = tester.widget<LgRadio<String>>(
        find.byWidgetPredicate(
          (w) => w is LgRadio<String> && w.label == '在本机接受',
        ),
      );
      expect(click.groupValue == click.value, isFalse);
      expect(find.text('审批方式为“在本机接受”时不使用密码'), findsNothing);

      (settingsApi as FakeSettingsApi).saveResult = SaveResult.saved;
      await tapText(tester, '在本机接受');
      expect(find.text('无法保存设置'), findsNothing);
      await done(tester);
    });

    testWidgets('"在本机接受" greys the passwords and says why', (tester) async {
      await pumpSettings(tester, section: SettingsSectionId.access);
      expect(find.text('审批方式为“在本机接受”时不使用密码'), findsNothing);
      await tapText(tester, '在本机接受');
      expect(find.text('审批方式为“在本机接受”时不使用密码'), findsOneWidget);
      await tapText(tester, '仅一次性密码');
      expect(bind.config.containsKey(kOptionVerificationMethod), isFalse);

      await tapText(tester, '输入密码或在本机接受');
      // Both is written as nothing, as Rust's default.
      expect(bind.config.containsKey(kOptionApproveMode), isFalse);
      await done(tester);
    });

    testWidgets(
      'permanent password only, none set: the dialog first, cancelled',
      (tester) async {
        await pumpSettings(tester, section: SettingsSectionId.access);
        await tapText(tester, '仅固定密码');
        expect(find.text('设置固定密码'), findsNWidgets(2));
        await tapText(tester, '取消');
        expect(bind.config.containsKey(kOptionVerificationMethod), isFalse);

        bind.passwordSet = true;
        await tapText(tester, '仅固定密码');
        expect(bind.config[kOptionVerificationMethod], kUsePermanentPassword);
        // The one-time password greys, with the reason.
        expect(find.text('密码方式为“仅固定密码”时不使用一次性密码'), findsOneWidget);
        expect(switchOf(tester, '仅使用数字').onChanged, isNull);
        await done(tester);
      },
    );

    testWidgets('length and digits only make a new one-time password at once', (
      tester,
    ) async {
      await pumpSettings(tester, section: SettingsSectionId.access);
      await tapText(tester, '8');
      expect(bind.config[kOptionTemporaryPasswordLength], '8');
      expect(bind.callsTo(#mainUpdateTemporaryPassword), hasLength(1));

      await tapOn(tester, switchFinder('仅使用数字'));
      expect(bind.config[kOptionAllowNumericOneTimePassword], 'Y');
      expect(bind.callsTo(#mainUpdateTemporaryPassword), hasLength(2));
      await done(tester);
    });

    testWidgets('the permanent password: not set, or set', (tester) async {
      await pumpSettings(tester, section: SettingsSectionId.access);
      expect(find.text('未设置'), findsOneWidget);
      expect(find.text('设置固定密码'), findsOneWidget);
      await done(tester);

      bind.passwordSet = true;
      await pumpSettings(tester, section: SettingsSectionId.access);
      expect(find.text('已设置'), findsOneWidget);
      expect(find.bySemanticsLabel('修改固定密码'), findsOneWidget);
      await done(tester);
    });
  });

  group('权限 (02 §1.3.2)', () {
    testWidgets('custom: each switch writes its option', (tester) async {
      await pumpSettings(tester, section: SettingsSectionId.permissions);
      expect(switchOf(tester, '允许建立 TCP 隧道').value, isTrue);
      await tapOn(tester, switchFinder('允许建立 TCP 隧道'));
      expect(bind.config[kOptionEnableTunnel], 'N');
      expect(switchOf(tester, '允许建立 TCP 隧道').value, isFalse);
      // Off unless "Y".
      expect(switchOf(tester, '允许对方操作本机 Leapgate 的主页和设置').value, isFalse);
      await done(tester);
    });

    testWidgets(
      'full access: all on and greyed; screen sharing only: all off',
      (tester) async {
        bind.config[kOptionEnableClipboard] = 'N';
        await pumpSettings(tester, section: SettingsSectionId.permissions);
        await tapText(tester, '完全访问');
        expect(bind.config[kOptionAccessMode], 'full');
        expect(find.text('由访问模式“完全访问”决定'), findsOneWidget);
        final clipboard = switchOf(tester, '允许同步剪贴板');
        expect(clipboard.value, isTrue);
        expect(clipboard.onChanged, isNull);

        await tapText(tester, '仅共享屏幕');
        expect(find.text('由访问模式“仅共享屏幕”决定'), findsOneWidget);
        expect(switchOf(tester, '允许控制键盘和鼠标').value, isFalse);

        await tapText(tester, '自定义');
        expect(bind.config.containsKey(kOptionAccessMode), isFalse);
        expect(switchOf(tester, '允许同步剪贴板').value, isFalse);
        expect(switchOf(tester, '允许同步剪贴板').onChanged, isNotNull);
        await done(tester);
      },
    );
  });

  group('what is typed is saved before the content changes', () {
    // The box of "等待直连的时间" (coder B's section) saves when it loses the focus.
    Future<void> typeWait(WidgetTester tester, String text) async {
      await pumpSettings(tester, section: SettingsSectionId.connection);
      await tester.enterText(find.byType(EditableText).at(1), text);
      await tester.pump();
    }

    testWidgets('a link to another section', (tester) async {
      await typeWait(tester, '5');
      settingsPageRequests.request(SettingsSectionId.access);
      await settle(tester);
      expect(find.text('审批方式'), findsOneWidget);
      expect(bind.local[kOptionRelayFallbackDelay], '5');
      await done(tester);
    });

    testWidgets('another page of the home tab', (tester) async {
      await typeWait(tester, '7.5');
      connectBoxFocusRequests.request();
      await settle(tester);
      expect(find.text('搜索设置'), findsNothing);
      expect(bind.local[kOptionRelayFallbackDelay], '7.5');
      await done(tester);
    });
  });

  group('home page: why no one can connect (M6-4)', () {
    Future<void> pumpWarning(
      WidgetTester tester,
      NetworkWarning? warning, {
      ServiceStatus status = ServiceStatus.connecting,
    }) => pumpHome(
      tester,
      id: '135792468',
      status: status,
      setUp: (m) => m.networkWarning = warning,
    );

    testWidgets('one line for the first that is on, with the link', (
      tester,
    ) async {
      final nav = mainNavigation as FakeNavigation;
      await pumpWarning(tester, NetworkWarning.webSocket);
      expect(find.text('已使用 WebSocket，其他设备无法连接本机'), findsOneWidget);
      await tapText(tester, '网络和服务器');
      expect(nav.settings.single.section, SettingsSectionId.network);
      await done(tester);

      await pumpWarning(tester, NetworkWarning.proxy);
      expect(find.text('已设置代理，其他设备无法连接本机'), findsOneWidget);
      expect(find.text('已使用 WebSocket，其他设备无法连接本机'), findsNothing);
      await done(tester);
    });

    testWidgets('none when nothing is on or the service is stopped', (
      tester,
    ) async {
      await pumpWarning(tester, null);
      expect(find.text('网络和服务器'), findsNothing);
      await done(tester);

      await pumpWarning(
        tester,
        NetworkWarning.udpDisabled,
        status: ServiceStatus.stopped,
      );
      expect(find.text('已禁用 UDP，其他设备无法连接本机'), findsNothing);
      await done(tester);
    });
  });

  group('服务与 ID (02 §1.3.8)', () {
    testWidgets('the service line is the home page\'s, and the ID', (
      tester,
    ) async {
      await pumpSettings(tester, section: SettingsSectionId.service);
      expect(find.textContaining('已就绪', findRichText: true), findsNWidgets(2));
      expect(find.text('135 792 468'), findsOneWidget);
      expect(find.text('解锁 PIN'), findsNothing);
      await done(tester);
    });

    testWidgets(
      'installed, stop: the warning, then the red line when it stays',
      (tester) async {
        bind.installed = true;
        await pumpSettings(tester, section: SettingsSectionId.service);
        // Not under the lock: it asks for administrator permission itself.
        await tapText(tester, '停止服务');
        expect(find.text('停止服务？'), findsOneWidget);
        expect(
          find.text('本机将无法接受远程连接。Leapgate 将关闭并重新打开，所有会话和正在使用的出口都将断开。'),
          findsOneWidget,
        );
        expect(kindOf(tester, '停止服务'), LgButtonKind.dangerSolid);
        await tapText(tester, '停止服务');
        expect(bind.config[kOptionStopService], 'Y');
        expect(find.text('未获得管理员权限，服务未停止'), findsOneWidget);
        await done(tester);
      },
    );

    testWidgets('portable, stop: its own warning, no red line', (tester) async {
      await pumpSettings(tester, section: SettingsSectionId.service);
      await tapText(tester, '停止服务');
      expect(find.text('本机将无法接受远程连接，正在进行的传入会话将断开。'), findsOneWidget);
      // Only the installed version's stop takes everything down (02 §3.5).
      expect(kindOf(tester, '停止服务'), LgButtonKind.primary);
      await tapText(tester, '取消');
      expect(bind.config, isEmpty);

      await tapText(tester, '停止服务');
      await tapText(tester, '停止服务');
      expect(bind.config[kOptionStopService], 'Y');
      expect(find.text('未获得管理员权限，服务未停止'), findsNothing);
      await done(tester);
    });

    testWidgets('installed, start with nothing in use: no question', (
      tester,
    ) async {
      bind
        ..installed = true
        ..config[kOptionStopService] = 'Y';
      await pumpSettings(
        tester,
        section: SettingsSectionId.service,
        status: ServiceStatus.stopped,
      );
      // The home page has its own "启动服务"; the section's is the last.
      await tapText(tester, '启动服务');
      expect(find.text('启动服务？'), findsNothing);
      expect(bind.config.containsKey(kOptionStopService), isFalse);
      expect(find.text('未获得管理员权限，服务未启动'), findsOneWidget);
      await done(tester);
    });

    testWidgets('the home page\'s "启动服务" takes the same way', (tester) async {
      bind
        ..installed = true
        ..config[kOptionStopService] = 'Y';
      await pumpHome(tester, id: '135792468', status: ServiceStatus.stopped);
      await tapText(tester, '启动服务');
      expect(find.text('启动服务？'), findsNothing);
      expect(bind.config.containsKey(kOptionStopService), isFalse);
      expect(find.text('未获得管理员权限，服务未启动'), findsOneWidget);
      await done(tester);
    });

    testWidgets('unlock PIN: set, two that differ, remove', (tester) async {
      bind.installed = true;
      await pumpSettings(tester, section: SettingsSectionId.service);
      // Not read while locked (09 §4.3): the name and description alone (02 §1.3.8).
      expect(find.text('解锁 PIN'), findsOneWidget);
      expect(find.text('未设置'), findsNothing);
      expect(find.text('设置 PIN'), findsNothing);
      expect(bind.callsTo(#mainGetUnlockPin), isEmpty);
      await unlockWithAdmin(tester);
      expect(find.text('未设置'), findsOneWidget);
      // The verbs carry the setting's name for a reader.
      expect(find.bySemanticsLabel('设置解锁 PIN'), findsOneWidget);

      await tapText(tester, '设置 PIN');
      expect(find.text('设置解锁 PIN'), findsOneWidget);
      expect(find.text('至少 4 个字符'), findsOneWidget);
      await tester.enterText(find.byType(EditableText).at(1), '24');
      await tester.pump();
      expect(enabled(tester, '确定'), isFalse);
      await tester.enterText(find.byType(EditableText).at(1), '2468');
      await tester.enterText(find.byType(EditableText).at(2), '2469');
      await tester.pump();
      expect(find.text('两次输入的 PIN 不一致'), findsOneWidget);
      expect(enabled(tester, '确定'), isFalse);
      await tester.enterText(find.byType(EditableText).at(2), '2468');
      await tester.pump();
      await tapText(tester, '确定');
      expect(bind.unlockPin, '2468');
      expect(find.text('已设置'), findsOneWidget);
      expect(find.text('修改 PIN'), findsOneWidget);

      await tapText(tester, '移除 PIN');
      expect(find.text('移除解锁 PIN？'), findsOneWidget);
      await tapText(tester, '移除');
      expect(bind.unlockPin, isEmpty);
      expect(find.text('未设置'), findsOneWidget);
      await done(tester);
    });

    testWidgets('a PIN longer than Rust keeps is refused in the dialog', (
      tester,
    ) async {
      bind.installed = true;
      await pumpSettings(tester, section: SettingsSectionId.service);
      await unlockWithAdmin(tester);
      await tapText(tester, '设置 PIN');
      final long = '1' * 129;
      await tester.enterText(find.byType(EditableText).at(1), long);
      await tester.enterText(find.byType(EditableText).at(2), long);
      await tester.pump();
      expect(find.text('PIN 不能超过 128 个字符'), findsOneWidget);
      expect(enabled(tester, '确定'), isFalse);
      await done(tester);
    });
  });
}
