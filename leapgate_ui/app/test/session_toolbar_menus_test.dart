import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/notices.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/pages/session/session_toolbar.dart';
import 'package:leapgate_ui/shell/navigation.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_menu_items.dart';
import 'package:leapgate_ui/widgets/lg_session_toolbar.dart';
import 'package:leapgate_ui/widgets/lg_title_bar.dart';
import 'package:leapgate_ui/widgets/lg_tooltip.dart';

import 'session_fakes.dart';

// The toolbar of M2b (LEAPGATE.md §10.9 coder A): what the menus offer and grey out, the
// shortcuts, the place of the toolbar, "更多", the monitors and the hints over the image.
// Device IDs here are made up.

const _id = '100200300';

Future<FFI> _open(
  WidgetTester tester,
  AppFakes fakes, {
  String id = _id,
  Map<String, dynamic>? info,
}) async {
  mainNavigation.connect(id);
  await tester.pump();
  await tester.pump();
  final s = appCore.sessions.sessionsOf(id).single;
  await emit(tester, fakes, s, connectionReady(direct: true));
  await emit(tester, fakes, s, info ?? peerInfo());
  await tester.pumpAndSettle();
  return s;
}

Future<void> _openMenu(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).first);
  await tester.pumpAndSettle();
}

/// A menu row by its label: a plain row or one with a switch.
Finder _item(String label) => find.byWidgetPredicate(
  (w) =>
      (w is LgMenuItem && w.label == label) ||
      (w is LgMenuSwitchItem && w.label == label),
);

/// Whether the row can be used; it is greyed out when not.
bool _enabled(WidgetTester tester, String label) =>
    switch (tester.widget(_item(label))) {
      LgMenuItem(:final onPressed) => onPressed != null,
      LgMenuSwitchItem(:final onChanged) => onChanged != null,
      _ => throw StateError(label),
    };

/// The note of a greyed row (beside the menu) or of a greyed button.
Finder _reason(String text) => find.byWidgetPredicate(
  (w) =>
      (w is LgNoteTip && w.message == text) ||
      (w is LgTooltip && w.message == text),
);

Map<String, dynamic> _withPrivacy(Map<String, dynamic> info) => {
  ...info,
  'features': jsonEncode({'privacy_mode': true}),
};

String _shortcuts(List<Map<String, Object>> bindings) =>
    jsonEncode({'enabled': true, 'bindings': bindings});

void main() {
  late AppFakes fakes;

  setUp(() => fakes = installAppFakes());

  group('greyed out with the reason (01 P2 block B)', () {
    testMainWindow('no keyboard and mouse permission: the whole input menu', (
      tester,
    ) async {
      await pumpMainWindow(tester);
      final s = await _open(tester, fakes);
      await emit(tester, fakes, s, {'name': 'permission', 'keyboard': 'false'});
      await tester.pumpAndSettle();

      // Greyed with the reason, and still opens on its greyed rows (`x-no-perm`).
      final input = tester.widget<LgToolbarMenuButton>(
        find.byWidgetPredicate(
          (w) => w is LgToolbarMenuButton && w.label == '输入',
        ),
      );
      expect(input.enabled, false);
      expect(input.disabledNote, '未获得键盘和鼠标控制权限');
      await _openMenu(tester, '输入');
      for (final label in ['仅查看模式', '显示本机光标', '反转滚动方向', '交换鼠标左右键']) {
        expect(_enabled(tester, label), false, reason: label);
      }
    });

    testMainWindow(
      'several privacy modes: one that is off needs the keyboard permission',
      (tester) async {
        await pumpMainWindow(tester);
        final s = await _open(
          tester,
          fakes,
          info: {
            ..._withPrivacy(peerInfo()),
            'platform_additions': jsonEncode({
              kPlatformAdditionsSupportedPrivacyModeImpl: [
                [kPrivacyModeImplMag, 'privacy_mode_impl_mag_tip'],
                [
                  'privacy_mode_impl_virtual_display',
                  'privacy_mode_impl_virtual_display_tip',
                ],
              ],
            }),
          },
        );
        s.privacyMode.value = kPrivacyModeImplMag;
        await emit(tester, fakes, s, {
          'name': 'permission',
          'keyboard': 'false',
        });

        await _openMenu(tester, '会话');
        await tester.tap(find.text('隐私模式'));
        await tester.pumpAndSettle();
        expect(_enabled(tester, '遮挡屏幕'), true);
        expect(_enabled(tester, '使用虚拟显示器'), false);
        expect(
          tester.widget<LgMenuItem>(_item('使用虚拟显示器')).disabledNote,
          '未获得键盘和鼠标控制权限',
        );

        // Its shortcut does nothing either.
        await emit(tester, fakes, s, {
          'name': kShortcutEventName,
          'action': kShortcutActionPrivacyMode2,
        });
        await tester.pumpAndSettle();
        expect(callsTo(fakes, #sessionTogglePrivacyMode), isEmpty);
      },
    );

    testMainWindow(
      'choosing "custom" quality sends the quality and frame rate it starts from',
      (tester) async {
        await pumpMainWindow(tester);
        await _open(tester, fakes);
        await _openMenu(tester, '画面');
        // The scale has a "自定义" too, before the quality.
        await tester.tap(_item('自定义').last);
        await tester.pumpAndSettle();

        expect(
          callsTo(fakes, #sessionSetImageQuality).last[#value],
          kRemoteImageQualityCustom,
        );
        expect(
          callsTo(fakes, #sessionSetCustomImageQuality).single[#value],
          kDefaultQuality.toInt(),
        );
        expect(
          callsTo(fakes, #sessionSetCustomFps).single[#fps],
          kDefaultFps.toInt(),
        );
      },
    );

    testMainWindow(
      'view-only: input rows grey out, view-only and its cursor stay usable',
      (tester) async {
        await pumpMainWindow(tester);
        final s = await _open(tester, fakes);
        s.ffiModel.setViewOnly(s.id, true);
        await tester.pump();

        await _openMenu(tester, '输入');
        expect(_enabled(tester, '仅查看模式'), true);
        expect(_enabled(tester, '显示本机光标'), true);
        expect(_enabled(tester, '反转滚动方向'), false);
        expect(_reason('仅查看模式下不可用'), findsWidgets);
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();

        await _openMenu(tester, '操作');
        expect(_enabled(tester, '发送 Ctrl+Alt+Del'), false);
        expect(_enabled(tester, '刷新画面'), true);
      },
    );

    testMainWindow('permissions taken back: clipboard, restart', (
      tester,
    ) async {
      await pumpMainWindow(tester);
      final s = await _open(tester, fakes);
      await emit(tester, fakes, s, {
        'name': 'permission',
        'clipboard': 'false',
        'restart': 'false',
      });

      // A notice in the corner sends the notes of greyed rows to the left (`x-revoked`).
      s.notices.add(SessionNotice('Remote reboot'));
      await tester.pump();
      expect(
        tester.widget<LgSessionToolbar>(find.byType(LgSessionToolbar)).noteSide,
        LgNoteSide.left,
      );

      await _openMenu(tester, '会话');
      expect(_enabled(tester, '静音'), true);
      expect(_enabled(tester, '同步剪贴板'), false);
      expect(_reason('未获得剪贴板权限'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await _openMenu(tester, '操作');
      expect(_enabled(tester, '重启远程设备'), false);
      expect(_reason('未获得远程重启权限'), findsOneWidget);
    });

    testMainWindow(
      'privacy mode on stays usable without its permission (toolbar.dart:1225-1240)',
      (tester) async {
        await pumpMainWindow(tester);
        final s = await _open(tester, fakes, info: _withPrivacy(peerInfo()));
        await emit(tester, fakes, s, {
          'name': 'permission',
          'privacy_mode': 'false',
        });

        await _openMenu(tester, '会话');
        expect(_enabled(tester, '隐私模式'), false);
        expect(_reason('未获得隐私模式权限'), findsOneWidget);
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();

        s.privacyMode.value = kPrivacyModeImplMag;
        await tester.pump();
        await _openMenu(tester, '会话');
        expect(_enabled(tester, '隐私模式'), true);
        await tester.tap(_item('隐私模式'));
        await tester.pumpAndSettle();
        expect(
          callsTo(fakes, #sessionToggleOption).last[#value],
          'privacy-mode',
        );
      },
    );

    testMainWindow('rows hidden for the platform stay hidden', (tester) async {
      await pumpMainWindow(tester);
      await _open(tester, fakes, info: peerInfo(platform: 'Linux', sas: false));
      await _openMenu(tester, '操作');
      // Blocking local input is for Windows peers only.
      expect(_item('阻止远程设备的本地输入'), findsNothing);
      expect(_item('锁定远程设备'), findsOneWidget);
    });
  });

  group('shortcuts', () {
    testMainWindow(
      'a shortcut runs its menu row, not while the row is greyed out',
      (tester) async {
        await pumpMainWindow(tester);
        final s = await _open(tester, fakes);
        await emit(tester, fakes, s, {
          'name': kShortcutEventName,
          'action': kShortcutActionInsertLock,
        });
        await tester.pumpAndSettle();
        expect(callsTo(fakes, #sessionLockScreen), hasLength(1));

        s.ffiModel.setViewOnly(s.id, true);
        await emit(tester, fakes, s, {
          'name': kShortcutEventName,
          'action': kShortcutActionInsertLock,
        });
        await tester.pumpAndSettle();
        expect(callsTo(fakes, #sessionLockScreen), hasLength(1));
      },
    );

    testMainWindow('menu rows show their keys, only while shortcuts are on', (
      tester,
    ) async {
      await pumpMainWindow(tester);
      await _open(tester, fakes);
      await _openMenu(tester, '操作');
      expect(
        tester.widget<LgMenuItem>(_item('发送 Ctrl+Alt+Del')).shortcut,
        isNull,
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      fakes.bind.localOptions[kShortcutLocalConfigKey] = _shortcuts([
        {
          'action': kShortcutActionSendCtrlAltDel,
          'mods': ['primary', 'alt', 'shift'],
          'key': 'delete',
        },
      ]);
      await _openMenu(tester, '操作');
      expect(
        tester.widget<LgMenuItem>(_item('发送 Ctrl+Alt+Del')).shortcut,
        'Ctrl+Alt+Shift+Del',
      );
    });

    testMainWindow('next / previous tab go round, home first (01 §2.1)', (
      tester,
    ) async {
      await pumpMainWindow(tester);
      final a = await _open(tester, fakes);
      await _open(tester, fakes, id: '400500600');
      int selected() =>
          tester.widget<LgTitleBar>(find.byType(LgTitleBar)).selected;
      expect(selected(), 2);

      // In a session: its own matcher found the keys.
      await emit(tester, fakes, a, {
        'name': kShortcutEventName,
        'action': kShortcutActionSwitchTabNext,
      });
      await tester.pump();
      expect(selected(), 0);
      await emit(tester, fakes, a, {
        'name': kShortcutEventName,
        'action': kShortcutActionSwitchTabPrev,
      });
      await tester.pump();
      expect(selected(), 2);

      // Elsewhere, the window matches them.
      fakes.bind.localOptions[kShortcutLocalConfigKey] = _shortcuts([
        {
          'action': kShortcutActionSwitchTabNext,
          'mods': ['primary', 'alt', 'shift'],
          'key': 'arrow_right',
        },
      ]);
      Future<void> next() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        // Home keeps its loading rows moving, so no pumpAndSettle.
        await tester.pump();
        await tester.pump();
      }

      await next();
      expect(selected(), 0);
      await next();
      expect(selected(), 1);
    });
  });

  group('the toolbar', () {
    Finder grip() => find.byType(LgToolbarGrip);

    testMainWindow(
      'dragged along the top edge, the place is kept for the device',
      (tester) async {
        await pumpMainWindow(tester);
        final s = await _open(tester, fakes);
        final before = tester.getTopLeft(find.byType(LgSessionToolbar)).dx;
        await tester.drag(grip(), const Offset(-150, 0));
        await tester.pumpAndSettle();
        final after = tester.getTopLeft(find.byType(LgSessionToolbar)).dx;
        expect(after, lessThan(before));

        final saved = double.parse(
          fakes.bind.peerOptions[kOptionRemoteMenubarFraction]!,
        );
        expect(saved, lessThan(0.5));
        // Docking on any edge is off: still the top, and where the old UI looks too.
        expect(fakes.bind.peerOptions[kOptionRemoteMenubarEdge], 'top');
        expect(fakes.bind.peerOptions['remote-menubar-drag-x'], '$saved');

        // The next session of the device opens it there.
        await appCore.sessions.closeDevice(s.id);
        await tester.pump();
        await _open(tester, fakes);
        expect(
          tester.getTopLeft(find.byType(LgSessionToolbar)).dx,
          moreOrLessEquals(after, epsilon: 1),
        );
      },
    );

    testMainWindow(
      'a press on a button that slips a few pixels still opens its menu',
      (tester) async {
        await pumpMainWindow(tester);
        await _open(tester, fakes);
        final before = tester.getTopLeft(find.byType(LgSessionToolbar));
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('操作')),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(5, 0));
        await gesture.up();
        await gesture.removePointer();
        await tester.pumpAndSettle();
        expect(_item('刷新画面'), findsOneWidget);
        expect(tester.getTopLeft(find.byType(LgSessionToolbar)), before);
      },
    );

    testMainWindow(
      'docking on any edge: dropped near the left edge, it docks there',
      (tester) async {
        await pumpMainWindow(tester);
        fakes.bind.localOptions[kOptionAllowMultiEdgeToolbarDock] = 'Y';
        await _open(tester, fakes);
        final gesture = await tester.startGesture(tester.getCenter(grip()));
        await gesture.moveBy(const Offset(-20, 0));
        await gesture.moveTo(const Offset(20, 400));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(fakes.bind.peerOptions[kOptionRemoteMenubarEdge], 'left');
        expect(
          tester.getTopLeft(find.byType(LgSessionToolbar)).dx,
          lessThan(20),
        );
      },
    );

    testMainWindow('narrow: session, chat and recording go into "更多"', (
      tester,
    ) async {
      // A folded button stays in the tree, out of sight and out of reach.
      Finder shown(Finder f) => f.hitTestable();
      await pumpMainWindow(tester);
      await _open(tester, fakes);
      expect(shown(find.bySemanticsLabel('更多')), findsNothing);
      expect(shown(find.text('会话')), findsOneWidget);

      // A little short: recording goes first.
      tester.view.physicalSize = const Size(920, 600);
      await tester.pumpAndSettle();
      expect(shown(find.bySemanticsLabel('更多')), findsOneWidget);
      expect(shown(find.text('会话')), findsOneWidget);
      expect(shown(find.bySemanticsLabel('录制')), findsNothing);

      tester.view.physicalSize = const Size(700, 600);
      await tester.pumpAndSettle();
      expect(shown(find.text('会话')), findsNothing);
      await tester.tap(find.bySemanticsLabel('更多'));
      await tester.pumpAndSettle();
      // In the bar's order (A-P2 `min-s`).
      double row(String label) =>
          tester.getTopLeft(shown(find.text(label)).last).dy;
      expect(row('会话'), lessThan(row('聊天')));
      expect(row('聊天'), lessThan(row('录制')));
      // What always stays.
      for (final name in ['画面', '输入', '操作']) {
        expect(find.text(name), findsWidgets, reason: name);
      }
    });

    testMainWindow(
      'auto-collapse then unfold leaves the saved state alone (待调 29)',
      (tester) async {
        await pumpMainWindow(tester);
        await _open(tester, fakes);
        final bar = find.byType(LgSessionToolbar);
        // The page sets this while the pointer is on the image (there is no image here).
        tester
                .widget<SessionToolbar>(find.byType(SessionToolbar))
                .cursorOverImage
                .value =
            true;
        await tester.pump(
          kToolbarAutoCollapse + const Duration(milliseconds: 100),
        );
        expect(tester.widget<LgSessionToolbar>(bar).collapsed, true);

        await tester.tap(find.bySemanticsLabel('展开'));
        await tester.pump();
        expect(tester.widget<LgSessionToolbar>(bar).collapsed, false);
        expect(
          callsTo(
            fakes,
            #sessionToggleOption,
          ).where((c) => c[#value] == kOptionCollapseToolbar),
          isEmpty,
        );
      },
    );
  });

  group('monitors (01 P2 block B, 02 §1.4.4)', () {
    testMainWindow('one button each when tiled, and "next monitor"', (
      tester,
    ) async {
      fakes.bind.userDefaults[kKeyShowMonitorsToolbar] = 'Y';
      fakes.bind.localOptions[kOptionAllowMonitorSwitchMainToolbar] = 'Y';
      await pumpMainWindow(tester);
      await _open(tester, fakes, info: peerInfo(displays: 2));

      expect(find.bySemanticsLabel('显示器 1'), findsOneWidget);
      expect(find.bySemanticsLabel('显示器 2'), findsOneWidget);
      expect(find.text('显示器'), findsNothing);
      await tester.tap(find.bySemanticsLabel('下一个显示器（1/2）'));
      await tester.pumpAndSettle();
      expect(callsTo(fakes, #sessionSwitchDisplay).last[#value], [1]);
    });

    testMainWindow('one monitor: no monitor buttons', (tester) async {
      fakes.bind.localOptions[kOptionAllowMonitorSwitchMainToolbar] = 'Y';
      await pumpMainWindow(tester);
      await _open(tester, fakes);
      expect(find.text('显示器'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('下一个显示器')), findsNothing);
    });
  });

  testMainWindow(
    'relative mouse mode: the hint shows and the toolbar hides (01 P2 block C)',
    (tester) async {
      await pumpMainWindow(tester);
      final s = await _open(tester, fakes);
      expect(find.byType(LgSessionToolbar), findsOneWidget);
      s.inputModel.relativeMouseMode.value = true;
      await tester.pump();
      expect(find.text('按 Ctrl+Alt 退出鼠标锁定'), findsOneWidget);
      expect(find.byType(LgSessionToolbar), findsNothing);
      s.inputModel.relativeMouseMode.value = false;
      await tester.pump();
    },
  );

  testMainWindow(
    'an Android peer gets the navigation bar, switched in the input menu',
    (tester) async {
      await pumpMainWindow(tester);
      final s = await _open(tester, fakes, info: peerInfo(platform: 'Android'));
      s.ffiModel.waitForFirstImage.value = false;
      await tester.pump();
      expect(find.bySemanticsLabel('Android 导航浮条'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('返回'));
      await tester.pump();
      expect(callsTo(fakes, #sessionSendMouse), isNotEmpty);

      // The switch row leaves the menu open.
      await _openMenu(tester, '输入');
      await tester.tap(_item('显示导航浮条'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Android 导航浮条'), findsNothing);
      await tester.tap(_item('显示导航浮条'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Android 导航浮条'), findsOneWidget);
    },
  );
}
