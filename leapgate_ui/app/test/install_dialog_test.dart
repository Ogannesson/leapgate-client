import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/install_page.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/pages/home/install_dialog.dart';
import 'package:leapgate_ui/pages/settings/sections/remote_printing.dart';
import 'package:leapgate_ui/pages/settings/settings_section_state.dart';
import 'package:leapgate_ui/pages/settings/settings_status.dart';
import 'package:leapgate_ui/shell/tab_overlays.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_feedback.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';
import 'package:win32/win32.dart' as win32;

import 'home_fakes.dart';

/// Drives and folders as the location checks see them. The paths here are made up.
class _System implements InstallSystem {
  @override
  String defaultPath = r'C:\Program Files\Leapgate';

  @override
  String get appName => 'Leapgate';

  @override
  String programFolder = r'C:\Apps\Leap gate\leapgate-0.4.0';

  @override
  int driveType(String root) =>
      root == r'Z:\' ? win32.DRIVE_REMOTE : win32.DRIVE_FIXED;

  @override
  bool isSubst(String root) => false;

  @override
  String resolveFolder(String folder) => folder;

  @override
  bool hasFiles(String folder) => false;
}

/// The line about what ends, whatever M9c makes of its wording.
final _sessionsLine = find.textContaining('Leapgate 将关闭并重新打开');

LgCheckbox _checkbox(String label) =>
    find
            .byWidgetPredicate((w) => w is LgCheckbox && w.label == label)
            .evaluate()
            .single
            .widget
        as LgCheckbox;

const _options = ['创建开始菜单快捷方式', '创建桌面快捷方式', '安装 Leapgate 打印机'];

/// A button of the install page (the hint card has an "安装" too).
Finder _button(String label) => find.descendant(
  of: find.byType(LgConfirmDialog),
  matching: find.widgetWithText(LgButton, label),
);

bool _ticked(String label) => _checkbox(label).value;

/// The dialog's fade; the home page and a busy button keep animating, so no pumpAndSettle.
Future<void> _pumps(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The label of the button the keyboard is on.
String? _focusedButton() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<LgButton>()
    ?.label;

void main() {
  late _System system;
  late FakeLeapgate lg;
  setUp(() {
    lg = installHomeFakes().lg;
    system = _System();
    installSystem = system;
    addTearDown(() => installSystem = const WindowsInstallSystem());
  });

  /// The portable home page with the install page opened from its card.
  Future<LocalStatusModel> openFromCard(
    WidgetTester tester, {
    void Function(LocalStatusModel model)? setUp,
  }) async {
    final model = await pumpHome(
      tester,
      id: '135792468',
      setUp: (m) {
        m.installed = false;
        setUp?.call(m);
      },
    );
    await tester.tap(find.widgetWithText(LgButton, '安装'));
    await _pumps(tester);
    expect(find.text('安装 Leapgate'), findsOneWidget);
    return model;
  }

  testWidgets(
    'the card opens the page: default location, both shortcuts, no printer; '
    'busy, then the failure on the page and not on the card (R3-Q20)',
    (tester) async {
      lg.installAnswer = Completer();
      await openFromCard(tester);
      // Read out whole, however much of it fits.
      expect(
        find.bySemanticsLabel(r'C:\Program Files\Leapgate'),
        findsOneWidget,
      );
      expect(_ticked('创建开始菜单快捷方式'), isTrue);
      expect(_ticked('创建桌面快捷方式'), isTrue);
      expect(_ticked('安装 Leapgate 打印机'), isFalse);
      expect(_sessionsLine, findsNothing);

      // The keyboard is on "安装": Enter starts it.
      expect(_focusedButton(), '安装');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(lg.installs, ['install']);
      expect(_button('正在安装…'), findsOneWidget);
      expect(tester.widget<LgButton>(_button('取消')).onPressed, isNull);
      // Nothing on the page changes while it runs.
      expect(tester.widget<LgButton>(_button('修改')).onPressed, isNull);
      for (final option in _options) {
        expect(_checkbox(option).onChanged, isNull, reason: option);
      }
      // Esc does nothing while it runs.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('安装 Leapgate'), findsOneWidget);

      lg.installAnswer.complete('{"result":"uac_denied","text":""}');
      await tester.pump();
      expect(find.text('未获得管理员权限，未安装。'), findsOneWidget);
      await tester.tap(_button('取消'));
      await _pumps(tester);
      expect(find.text('安装 Leapgate'), findsNothing);
      expect(find.text('未获得管理员权限，未安装。'), findsNothing);
      await unmount(tester);
    },
  );

  testWidgets(
    'with a session into this device: the line, and the keyboard on "取消"',
    (tester) async {
      await openFromCard(
        tester,
        setUp: (m) => m.incoming = const IncomingSessions(1, controlled: true),
      );
      expect(_sessionsLine, findsOneWidget);
      expect(_focusedButton(), '取消');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _pumps(tester);
      expect(find.text('安装 Leapgate'), findsNothing);
      expect(lg.installs, isEmpty);
      await unmount(tester);
    },
  );

  testWidgets('the line follows the sessions while the page is open', (
    tester,
  ) async {
    final status = await openFromCard(tester);
    status
      ..incoming = const IncomingSessions(2, controlled: false)
      ..notifyListeners();
    await tester.pump();
    expect(_sessionsLine, findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a failure without the installer\'s text, then with it', (
    tester,
  ) async {
    lg.installAnswer = Completer();
    await openFromCard(tester);
    await tester.tap(_button('安装'));
    await tester.pump();
    lg.installAnswer.complete('{"result":"failed","text":""}');
    await tester.pump();
    expect(find.text('安装失败。'), findsOneWidget);

    lg.installAnswer = Completer();
    await tester.tap(_button('安装'));
    await tester.pump();
    // Clicking again clears the line until the answer.
    expect(find.text('安装失败。'), findsNothing);
    lg.installAnswer.complete(
      '{"result":"failed","text":"Cannot install the EXE package over an existing MSI installation"}',
    );
    await tester.pump();
    expect(
      find.text(
        '安装失败：Cannot install the EXE package over an existing MSI installation',
      ),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('a long location is cut in the middle and read out whole', (
    tester,
  ) async {
    const long = r'D:\工作资料\常用软件\远程工具\公司内部\某个很长的文件夹名称\Leapgate';
    system.defaultPath = long;
    await openFromCard(tester);
    final shown = tester
        .widget<Text>(
          find.byWidgetPredicate(
            (w) => w is Text && (w.data?.startsWith(r'D:\') ?? false),
          ),
        )
        .data!;
    expect(shown, contains('…'));
    expect(shown, endsWith('Leapgate'));
    expect(shown.length, lessThan(long.length));
    expect(find.bySemanticsLabel(long), findsOneWidget);
    await unmount(tester);
  });

  test('the cut never splits a surrogate pair', () {
    // a b 😀 c d: a head of three units would end inside the pair.
    expect(cutMiddle('ab😀cd', 5), 'ab…cd');
    // a b c 😀 d: a tail of two units would start inside the pair.
    expect(cutMiddle('abc😀d', 4), 'ab…d');
    expect(cutMiddle('abcdef', 4), 'ab…ef');
  });

  testWidgets('a location in the program folder greys "安装" and says why', (
    tester,
  ) async {
    system.defaultPath = r'C:\apps\leap gate\leapgate-0.4.0\Leapgate';
    await openFromCard(tester);
    expect(find.text('无法安装到 Leapgate 当前所在的文件夹。请选择其他位置。'), findsOneWidget);
    expect(tester.widget<LgButton>(_button('安装')).onPressed, isNull);
    expect(_focusedButton(), '修改');
    await unmount(tester);
  });

  testWidgets(
    '远程打印 on the portable version opens the page with the printer ticked',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final overlays = TabOverlays();
      final state = SettingsSectionState(
        overlays: overlays,
        saveFailedText: '无法保存设置',
        locked: false,
      );
      addTearDown(state.dispose);
      final status = LocalStatusModel()..installed = false;
      addTearDown(status.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildLgTheme(
            brightness: Brightness.light,
            mode: LgMode.compact,
          ),
          home: Scaffold(
            body: SettingsStatus(
              status: status,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Builder(
                      builder: (context) => SingleChildScrollView(
                        child: remotePrintingSection(
                          AppLocalizations.of(context)!,
                        ).build(context, state),
                      ),
                    ),
                  ),
                  Positioned.fill(child: Overlay(key: overlays.keyOf(null))),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('仅安装版支持远程打印'), findsOneWidget);
      await tester.tap(find.widgetWithText(LgButton, '安装'));
      await _pumps(tester);
      expect(find.text('安装 Leapgate'), findsOneWidget);
      expect(_ticked('安装 Leapgate 打印机'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
