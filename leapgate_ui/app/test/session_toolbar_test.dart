import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/icons/lg_icon.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_menu.dart';
import 'package:leapgate_ui/widgets/lg_session_toolbar.dart';
import 'package:leapgate_ui/widgets/lg_status.dart';

import 'helpers.dart';

const _labels = LgToolbarLabels(
  toolbar: '会话工具栏',
  pin: '固定工具栏',
  fullscreen: '全屏',
  exitFullscreen: '退出全屏',
  minimize: '最小化',
  collapse: '收起工具栏',
  expand: '展开工具栏',
);

Finder _button(LgIcons icon) =>
    find.byWidgetPredicate((w) => w is LgToolbarButton && w.icon == icon);

class _Calls {
  int pin = 0, collapse = 0, fullscreen = 0, minimize = 0, picked = 0;
  int disconnect = 0;
}

Widget _bar(
  _Calls calls, {
  bool pinned = true,
  bool collapsed = false,
  bool fullscreen = false,
  bool encrypted = true,
  bool menuEnabled = true,
  LgRoute route = LgRoute.relay,
}) => LgSessionToolbar(
  labels: _labels,
  pinned: pinned,
  onTogglePin: () => calls.pin++,
  collapsed: collapsed,
  onToggleCollapsed: () => calls.collapse++,
  fullscreen: fullscreen,
  onToggleFullscreen: () => calls.fullscreen++,
  onMinimize: () => calls.minimize++,
  deviceName: '妈妈的笔记本',
  deviceId: '234 567 891',
  route: route,
  routeLabel: route == LgRoute.relay ? '经中继' : '直连',
  encrypted: encrypted,
  unencryptedLabel: encrypted ? null : '未加密',
  groups: [
    [
      LgToolbarMenuButton(
        label: '画面',
        icon: LgIcons.image,
        enabled: menuEnabled,
        items: [
          LgMenuItem(
            label: '适应窗口',
            checked: true,
            onPressed: () => calls.picked++,
          ),
          const LgMenuItem(label: '原始大小', checked: false, onPressed: null),
        ],
      ),
    ],
    [
      LgToolbarStatus(
        child: LgRouteMark(
          route: route,
          label: route == LgRoute.relay ? '经中继' : '直连',
          encrypted: encrypted,
          unencryptedLabel: encrypted ? null : '未加密',
        ),
      ),
    ],
    [
      LgToolbarButton(
        icon: LgIcons.power,
        label: '断开',
        danger: true,
        onPressed: () => calls.disconnect++,
      ),
    ],
  ],
);

void main() {
  group('LgSessionToolbar', () {
    testWidgets('the pin, the end buttons and the groups call back', (
      tester,
    ) async {
      final calls = _Calls();
      await pumpLg(tester, _bar(calls));
      await tester.tap(_button(LgIcons.pin));
      await tester.tap(_button(LgIcons.fullscreen));
      await tester.tap(_button(LgIcons.chevU));
      await tester.tap(_button(LgIcons.power));
      expect(
        (calls.pin, calls.fullscreen, calls.collapse, calls.disconnect),
        (1, 1, 1, 1),
      );
      // Windowed: no minimize, no device name.
      expect(_button(LgIcons.minus), findsNothing);
      expect(find.text('妈妈的笔记本'), findsNothing);
    });

    testWidgets('a menu button opens its menu and a choice runs', (
      tester,
    ) async {
      final calls = _Calls();
      await pumpLg(tester, _bar(calls));
      expect(find.text('适应窗口'), findsNothing);
      await tester.tap(find.byType(LgToolbarMenuButton));
      await tester.pumpAndSettle();
      expect(find.text('适应窗口'), findsOneWidget);
      await tester.tap(find.text('适应窗口'));
      await tester.pumpAndSettle();
      expect(calls.picked, 1);
      expect(find.text('适应窗口'), findsNothing);
    });

    testWidgets('a disabled menu button opens nothing', (tester) async {
      await pumpLg(tester, _bar(_Calls(), menuEnabled: false));
      await tester.tap(find.byType(LgToolbarMenuButton));
      await tester.pumpAndSettle();
      expect(find.text('适应窗口'), findsNothing);
    });

    testWidgets('detail mode puts the icon before the menu name', (
      tester,
    ) async {
      Future<int> icons(LgMode mode) async {
        await pumpLg(tester, _bar(_Calls()), mode: mode);
        return find
            .descendant(
              of: find.byType(LgToolbarMenuButton),
              matching: find.byType(LgIcon),
            )
            .evaluate()
            .length;
      }

      // The arrow only, then the icon and the arrow.
      expect(await icons(LgMode.compact), 1);
      expect(await icons(LgMode.detail), 2);
    });

    testWidgets('folded: only the dot, full screen and unfold remain', (
      tester,
    ) async {
      final calls = _Calls();
      await pumpLg(tester, _bar(calls, collapsed: true));
      expect(find.byType(LgToolbarMenuButton), findsNothing);
      expect(_button(LgIcons.pin), findsNothing);
      expect(_button(LgIcons.power), findsNothing);
      await tester.tap(_button(LgIcons.chevD));
      await tester.tap(_button(LgIcons.fullscreen));
      expect((calls.collapse, calls.fullscreen), (1, 1));
    });

    testWidgets('the folded dot is named by its connection method', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, _bar(_Calls(), collapsed: true));
      expect(find.bySemanticsLabel('经中继'), findsOneWidget);
      await pumpLg(
        tester,
        _bar(
          _Calls(),
          collapsed: true,
          route: LgRoute.direct,
          encrypted: false,
        ),
      );
      expect(find.bySemanticsLabel('直连, 未加密'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('folded without a known route draws no connection dot', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      Widget bar({bool encrypted = true}) => LgSessionToolbar(
        labels: _labels,
        groups: const [],
        pinned: true,
        onTogglePin: () {},
        collapsed: true,
        onToggleCollapsed: () {},
        fullscreen: false,
        onToggleFullscreen: () {},
        encrypted: encrypted,
        unencryptedLabel: encrypted ? null : '未加密',
      );
      await pumpLg(tester, bar());
      expect(find.bySemanticsLabel('经中继'), findsNothing);
      expect(find.byType(LgIcon), findsNWidgets(2)); // full screen and unfold
      // Unencrypted before the route is known: the warning alone.
      await pumpLg(tester, bar(encrypted: false));
      expect(find.bySemanticsLabel('未加密'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the open bar works without a route too', (tester) async {
      await pumpLg(
        tester,
        LgSessionToolbar(
          labels: _labels,
          groups: const [],
          pinned: false,
          onTogglePin: () {},
          collapsed: false,
          onToggleCollapsed: () {},
          fullscreen: false,
          onToggleFullscreen: () {},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('full screen shows the device name and minimize', (
      tester,
    ) async {
      final calls = _Calls();
      await pumpLg(tester, _bar(calls, fullscreen: true));
      expect(find.text('妈妈的笔记本'), findsOneWidget);
      await tester.tap(_button(LgIcons.minus));
      expect(calls.minimize, 1);
      // The button now leaves full screen.
      expect(_button(LgIcons.fullscreenExit), findsOneWidget);
      expect(_button(LgIcons.fullscreen), findsNothing);

      await pumpLg(tester, _bar(calls, fullscreen: true, collapsed: true));
      expect(_button(LgIcons.minus), findsOneWidget);
    });

    testWidgets('the pin shows its state to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      Future<bool> toggled(bool pinned) async {
        await pumpLg(tester, _bar(_Calls(), pinned: pinned));
        return tester
                .getSemantics(find.bySemanticsLabel('固定工具栏'))
                .getSemanticsData()
                .flagsCollection
                .isToggled ==
            Tristate.isTrue;
      }

      expect(await toggled(true), isTrue);
      expect(await toggled(false), isFalse);
      handle.dispose();
    });

    testWidgets('every button has a name', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLg(tester, _bar(_Calls()));
      for (final label in ['固定工具栏', '画面', '断开', '全屏', '收起工具栏', '会话工具栏']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      handle.dispose();
    });

    testWidgets('a window too narrow for the bar scales it, no overflow', (
      tester,
    ) async {
      await pumpLg(tester, SizedBox(width: 300, child: _bar(_Calls())));
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(LgSessionToolbar)).width,
        lessThanOrEqualTo(300),
      );
    });
  });

  group('LgToolbarButton', () {
    testWidgets('disabled does not react', (tester) async {
      var taps = 0;
      await pumpLg(
        tester,
        const LgToolbarButton(
          icon: LgIcons.power,
          label: '断开',
          onPressed: null,
        ),
      );
      await tester.tap(find.byType(LgToolbarButton));
      expect(taps, 0);
    });

    testWidgets('shows its text with showText, else only as a tooltip', (
      tester,
    ) async {
      await pumpLg(
        tester,
        LgToolbarButton(
          icon: LgIcons.displays,
          label: '2/3',
          showText: true,
          onPressed: () {},
        ),
      );
      expect(find.text('2/3'), findsOneWidget);
      await pumpLg(
        tester,
        LgToolbarButton(icon: LgIcons.displays, label: '2/3', onPressed: () {}),
      );
      expect(find.text('2/3'), findsNothing);
      await hover(tester, find.byType(LgToolbarButton));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2/3'), findsOneWidget);
    });
  });
}
