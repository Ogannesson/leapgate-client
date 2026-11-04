import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/settings/incoming_sessions.dart'
    show wallpaperSupported;
import 'package:flutter_hbb/leapgate/settings/unlock.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/shell/main_window.dart';
import 'package:leapgate_ui/shell/navigation.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';

import 'session_fakes.dart';

// The two incoming settings that ask for administrator permission themselves stay usable on
// the real settings page while the installed version is locked (02 §1.2.6): RDP session sharing
// and installing the Leapgate printer. The rest of their sections is not.

/// The installed version: RDP sharing on, no printer, no unlock PIN.
class _Bind extends AppFakeBind {
  final config = <String, String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      case #mainGetUnlockPin:
        return '';
      case #mainGetOptionSync:
        return config[args[#key]] ?? '';
      case #mainSetOption:
      case #mainSetShareRdp:
      case #mainSetCommon:
        calls.add(invocation);
        return Future<void>.value();
      case #mainIsShareRdp:
        return true;
      case #mainGetCommonSync when args[#key] == 'is-printer-installed':
        return 'false';
      case #mainSupportedPrivacyModeImpls:
        return '[]';
      case #mainSupportRemoveWallpaper:
        return Future.value(false);
      case #mainAudioSupportLoopback:
        return true;
      case #mainGetSoundInputs:
        return Future.value(const <String>[]);
      case #mainVideoSaveDirectory:
        return r'C:\Leapgate-test-folder-that-does-not-exist';
      case #mainGetSocks:
        return Future.value(const <String>[]);
    }
    return super.noSuchMethod(invocation);
  }
}

Future<void> _turns(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _open(WidgetTester tester, SettingsSectionId section) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
      home: MainWindow(status: LocalStatusModel()),
    ),
  );
  mainNavigation.showSettings(section);
  await _turns(tester);
  expect(find.text('已锁定。修改这些设置需要管理员权限。'), findsOneWidget);
}

Finder _switch(String label) => find.byWidgetPredicate(
    (w) => w is LgSwitch && w.semanticLabel == label);

void main() {
  late _Bind bind;

  setUp(() {
    installAppFakes();
    bind = _Bind()..installed = true;
    platformFFI.setBindingForTesting(bind);
    wallpaperSupported = null;
    addTearDown(settingsUnlock.lock);
  });

  testMainWindow('locked: RDP session sharing still asks, the rest of 会话 does not',
      (tester) async {
    await _open(tester, SettingsSectionId.sessions);
    await tester.tap(_switch('允许 RDP 会话共享'));
    await _turns(tester);
    expect(bind.callsTo(#mainSetShareRdp).single.namedArguments[#enable],
        isFalse);

    expect(tester.widget<LgSwitch>(_switch('自适应码率')).onChanged, isNull);
    await tester.tap(_switch('自适应码率'), warnIfMissed: false);
    await _turns(tester);
    expect(bind.callsTo(#mainSetOption), isEmpty);
    expect(bind.config[kOptionEnableAbr], isNull);
  });

  testMainWindow('locked: installing the printer still asks', (tester) async {
    await _open(tester, SettingsSectionId.remotePrinting);
    await tester.tap(find.widgetWithText(LgButton, '安装打印机'));
    await _turns(tester);
    expect(bind.callsTo(#mainSetCommon).single.namedArguments[#key],
        'install-printer');
    expect(find.text('正在安装…'), findsOneWidget);
  });
}
