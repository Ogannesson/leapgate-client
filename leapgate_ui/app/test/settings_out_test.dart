import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/settings/print_jobs.dart' show PrintJobChoice;
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/l10n/app_localizations.dart';
import 'package:leapgate_ui/pages/settings/sections/about.dart';
import 'package:leapgate_ui/pages/settings/sections/new_device_defaults.dart';
import 'package:leapgate_ui/pages/settings/sections/other.dart';
import 'package:leapgate_ui/pages/settings/sections/print_jobs.dart';
import 'package:leapgate_ui/pages/settings/sections/rendering.dart';
import 'package:leapgate_ui/pages/settings/sections/shortcuts.dart';
import 'package:leapgate_ui/pages/settings/sections/toolbar.dart';
import 'package:leapgate_ui/pages/settings/settings_registry.dart';
import 'package:leapgate_ui/pages/settings/settings_section_state.dart';
import 'package:leapgate_ui/pages/settings/settings_status.dart';
import 'package:leapgate_ui/shell/navigation.dart' show settingsPageRequests;
import 'package:leapgate_ui/shell/tab_overlays.dart';
import 'package:leapgate_ui/theme/lg_theme.dart';
import 'package:leapgate_ui/theme/lg_tokens.dart';
import 'package:leapgate_ui/widgets/lg_button.dart';
import 'package:leapgate_ui/widgets/lg_panel_inputs.dart';
import 'package:leapgate_ui/widgets/lg_selection.dart';
import 'package:leapgate_ui/widgets/lg_settings_rows.dart';
import 'package:leapgate_ui/widgets/lg_shortcuts.dart';
import 'package:leapgate_ui/widgets/lg_slider.dart';

import 'home_fakes.dart';

// Coder D's settings sections (02 §1.4.2, §1.4.4~§1.4.7, §1.5.4, §1.5.5), one test per state of
// 02 §1.10, over a bridge that keeps the options as Rust does. The device ID and the fingerprint
// are made up; printers are made-up names.

/// LocalConfig and Config come from [FakeBind]; this keeps the defaults for new devices and
/// answers what the sections read from Rust beside the options.
class _Bind extends FakeBind {
  final defaults = <String, String>{};
  String hwDecodings = '{}';
  bool hwcodec = false;
  List<String> printers = const [];
  String fingerprint = '';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      // Rust's defaults (`config.rs` `UserDefaultConfig::get`).
      case #mainGetUserDefaultOption:
        final key = args[#key] as String;
        return defaults[key] ??
            switch (key) {
              kOptionViewStyle => 'original',
              kOptionScrollStyle => 'scrollauto',
              kOptionImageQuality => 'balanced',
              kOptionCodecPreference => 'auto',
              kOptionEnableFileCopyPaste => 'Y',
              _ => '',
            };
      case #mainSetUserDefaultOption:
        calls.add(invocation);
        defaults[args[#key] as String] = args[#value] as String;
        return Future<void>.value();
      case #mainGetUseTextureRender:
        return local[kOptionTextureRender] != 'N';
      case #mainSupportedHwdecodings:
        return hwDecodings;
      case #mainHasHwcodec:
        return hwcodec;
      case #mainHasVram:
        return false;
      case #mainCheckHwcodec:
        calls.add(invocation);
        return Future<void>.value();
      case #mainGetAppNameSync:
        return 'Leapgate';
      case #mainGetPrinterNames:
        return jsonEncode([...printers, 'Leapgate Printer']);
      case #mainGetDefaultKeyboardShortcuts:
        return jsonEncode(kDefaultShortcutBindings);
      case #mainReloadKeyboardShortcuts:
        return null;
      case #mainGetVersion:
        return Future.value('1.5.1');
      case #mainGetBuildDate:
        return Future.value('2026-10-29');
      case #mainGetFingerprint:
        return Future.value(fingerprint);
      case #mainGetLicense:
        return Future.value('');
    }
    return super.noSuchMethod(invocation);
  }
}

class _Leapgate extends FakeLeapgate {
  @override
  String leapgateVersion({dynamic hint}) => '0.4.0';
}

late _Bind _bind;

Finder _switch(String label) => find.byWidgetPredicate(
    (w) => w is LgSwitch && w.semanticLabel == label);

bool _on(WidgetTester tester, String label) =>
    tester.widget<LgSwitch>(_switch(label)).value;

Finder _button(String label) => find.widgetWithText(LgButton, label);

Finder _radio(String label) =>
    find.byWidgetPredicate((w) => w is LgRadio && w.label == label);

LgSelectField<String> _select(WidgetTester tester, String label) =>
    tester.widget(find.byWidgetPredicate(
        (w) => w is LgSelectField<String> && w.semanticLabel == label));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

/// [make]'s section in Chinese, with the home tab's overlay and this device's status.
Future<void> _pump(WidgetTester tester,
    SettingsSection Function(AppLocalizations l10n) make) async {
  tester.view.physicalSize = const Size(1280, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final overlays = TabOverlays();
  final state = SettingsSectionState(
      overlays: overlays, saveFailedText: '无法保存设置');
  addTearDown(state.dispose);
  final status = LocalStatusModel()..id = '135792468';
  addTearDown(status.dispose);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildLgTheme(brightness: Brightness.light, mode: LgMode.compact),
    home: Scaffold(
      body: SettingsStatus(
        status: status,
        child: Stack(children: [
          Positioned.fill(
            child: Builder(builder: (context) {
              final section = make(AppLocalizations.of(context)!);
              return ListenableBuilder(
                listenable: state,
                builder: (context, _) => SingleChildScrollView(
                    child: section.build(context, state)),
              );
            }),
          ),
          Positioned.fill(child: Overlay(key: overlays.keyOf(null))),
        ]),
      ),
    ),
  ));
  await _settle(tester);
}

void main() {
  setUp(() {
    installHomeFakes();
    _bind = _Bind();
    platformFFI.setBindingForTesting(_bind);
    setLgBindForTesting(_Leapgate());
  });

  group('defaults for new devices', () {
    testWidgets('the line under the title, on the settings page', (tester) async {
      await pumpHome(tester, id: '135792468', status: ServiceStatus.ready);
      settingsPageRequests.request(SettingsSectionId.newDeviceDefaults);
      await _settle(tester);
      expect(find.text('新设备的默认设置'), findsWidgets);
      expect(find.text('连接新设备时使用以下设置。连接过的设备沿用各自保存的设置。'),
          findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the defaults: what a fresh install starts new devices with', (tester) async {
      await _pump(tester, newDeviceDefaultsSection);
      final segments = tester
          .widgetList<LgSegmented<String>>(find.byType(LgSegmented<String>))
          .map((s) => s.selected);
      expect(segments, ['original', 'scrollauto', 'balanced']);
      expect(_select(tester, '编码').value, 'auto');
      expect(find.text('边缘宽度'), findsNothing);
      expect(find.text('自定义画质'), findsNothing);
      expect(_on(tester, '同步剪贴板'), isTrue);
      expect(_on(tester, '允许复制粘贴文件'), isTrue);
      expect(_on(tester, '真彩色 4:4:4'), isFalse);
      expect(_on(tester, '断开连接后保持终端会话'), isFalse);

      await _tap(tester, _switch('真彩色 4:4:4'));
      await _tap(tester, _switch('同步剪贴板'));
      await _tap(tester, _switch('允许复制粘贴文件'));
      expect(_bind.defaults, {
        kOptionI444: 'Y',
        kOptionDisableClipboard: 'Y',
        kOptionEnableFileCopyPaste: 'N',
      });
      expect(_on(tester, '同步剪贴板'), isFalse);
    });

    testWidgets('custom quality: two sliders, saved a second after they stop', (tester) async {
      await _pump(tester, newDeviceDefaultsSection);
      await _tap(tester, find.text('自定义'));
      expect(_bind.defaults[kOptionImageQuality], 'custom');
      expect(find.text('自定义画质'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);

      final quality = find.byWidgetPredicate(
          (w) => w is LgSlider && w.semanticLabel == '画质');
      tester.widget<LgSlider>(quality).onChanged!(70);
      tester.widget<LgSlider>(quality).onChanged!(80);
      await tester.pump(const Duration(milliseconds: 900));
      expect(_bind.defaults[kOptionCustomImageQuality], isNull);
      expect(find.text('80%'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await _settle(tester);
      expect(_bind.defaults[kOptionCustomImageQuality], '80');
      expect(find.text('80%'), findsOneWidget);
    });

    testWidgets('edge scrolling shows the edge width', (tester) async {
      await _pump(tester, newDeviceDefaultsSection);
      await _tap(tester, find.text('边缘滚动'));
      expect(_bind.defaults[kOptionScrollStyle], 'scrolledge');
      expect(find.text('边缘宽度'), findsOneWidget);
      expect(find.text('100 像素'), findsOneWidget);
    });

    testWidgets('H264 and H265 only when this device decodes them in hardware', (tester) async {
      await _pump(tester, newDeviceDefaultsSection);
      expect(_select(tester, '编码').items.map((i) => i.label),
          ['自动', 'VP8', 'VP9', 'AV1']);

      _bind.hwDecodings = jsonEncode({'h264': true, 'h265': true});
      _bind.defaults[kOptionCodecPreference] = 'h265';
      await _pump(tester, newDeviceDefaultsSection);
      final codec = _select(tester, '编码');
      expect(codec.items.map((i) => i.label),
          ['自动', 'VP8', 'VP9', 'AV1', 'H264', 'H265']);
      expect(codec.value, 'h265');
    });

    testWidgets('trackpad speed: a wrong number is refused, a right one saved', (tester) async {
      await _pump(tester, newDeviceDefaultsSection);
      final box = find.byWidgetPredicate((w) =>
          w is LgSettingsNumberField && w.semanticLabel == '触控板速度');
      await tester.ensureVisible(box);
      await tester.enterText(
          find.descendant(of: box, matching: find.byType(EditableText)), '5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(find.text('须为 10~1000 之间的整数'), findsOneWidget);
      expect(_bind.defaults[kKeyTrackpadSpeed], isNull);

      await tester.enterText(
          find.descendant(of: box, matching: find.byType(EditableText)), '250');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(_bind.defaults[kKeyTrackpadSpeed], '250');
      expect(find.text('须为 10~1000 之间的整数'), findsNothing);
    });

    testWidgets('trackpad speed: the box follows the slider while it moves', (tester) async {
      await _pump(tester, newDeviceDefaultsSection);
      final box = find.descendant(
          of: find.byWidgetPredicate((w) =>
              w is LgSettingsNumberField && w.semanticLabel == '触控板速度'),
          matching: find.byType(EditableText));
      final slider = find.byWidgetPredicate(
          (w) => w is LgSlider && w.semanticLabel == '触控板速度');
      expect(tester.widget<EditableText>(box).controller.text, '100');
      tester.widget<LgSlider>(slider).onChanged!(300);
      await tester.pump();
      expect(tester.widget<EditableText>(box).controller.text, '300');
      expect(_bind.defaults[kKeyTrackpadSpeed], isNull);
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(_bind.defaults[kKeyTrackpadSpeed], '300');
      expect(tester.widget<EditableText>(box).controller.text, '300');
    });
  });

  group('toolbar and monitors', () {
    testWidgets('"next monitor" on brings its indented item; off takes both', (tester) async {
      await _pump(tester, toolbarSection);
      expect(find.text('工具栏收起时也显示'), findsNothing);
      await _tap(tester, _switch('在工具栏上显示“下一个显示器”按钮'));
      expect(_bind.local[kOptionAllowMonitorSwitchMainToolbar], 'Y');
      expect(find.text('工具栏收起时也显示'), findsOneWidget);
      await _tap(tester, _switch('工具栏收起时也显示'));
      expect(_bind.local[kOptionAllowMonitorSwitchMinToolbar], 'Y');

      await _tap(tester, _switch('在工具栏上显示“下一个显示器”按钮'));
      expect(_bind.local[kOptionAllowMonitorSwitchMainToolbar], 'N');
      expect(_bind.local[kOptionAllowMonitorSwitchMinToolbar], 'N');
      expect(find.text('工具栏收起时也显示'), findsNothing);

      await _tap(tester, _switch('在工具栏上平铺显示器按钮'));
      await _tap(tester, _switch('允许工具栏停靠在窗口任意一边'));
      expect(_bind.defaults[kKeyShowMonitorsToolbar], 'Y');
      expect(_bind.local[kOptionAllowMultiEdgeToolbarDock], 'Y');
    });
  });

  group('rendering', () {
    testWidgets('the defaults; switching goes through the call that tells the sessions', (tester) async {
      await _pump(tester, renderingSection);
      expect(_on(tester, '使用纹理渲染'), isTrue);
      expect(_on(tester, '使用 D3D 渲染'), isFalse);
      expect(find.text('与“硬件编解码”同时开启时，硬件解码的画面直接在显卡中绘制'),
          findsOneWidget);
      await _tap(tester, _switch('使用纹理渲染'));
      await _tap(tester, _switch('使用 D3D 渲染'));
      expect(
          _bind.callsTo(#mainSetLocalOption).map((c) =>
              (c.namedArguments[#key], c.namedArguments[#value])),
          [(kOptionTextureRender, 'N'), (kOptionD3DRender, 'Y')]);
      expect(_on(tester, '使用纹理渲染'), isFalse);
    });
  });

  group('shortcuts', () {
    void bindings(List<Map<String, Object>> list, {bool passThrough = false}) =>
        _bind.local[kShortcutLocalConfigKey] = jsonEncode(
            {'enabled': true, 'pass_through': passThrough, 'bindings': list});

    Map<String, Object> binding(String action, String key) => {
          'action': action,
          'mods': ['primary', 'alt', 'shift'],
          'key': key,
        };

    LgShortcutRow row(WidgetTester tester, String action) => tester.widget(
        find.byWidgetPredicate((w) => w is LgShortcutRow && w.action == action));

    testWidgets('off: the switch alone; on writes the default bindings', (tester) async {
      await _pump(tester, shortcutsSection);
      expect(find.text('在远程会话中使用快捷键'), findsOneWidget);
      expect(find.text('将组合键发送到远程设备'), findsNothing);
      expect(find.byType(LgShortcutGroup), findsNothing);

      await _tap(tester, _switch('在远程会话中使用快捷键'));
      final groups = tester
          .widgetList<LgShortcutGroup>(find.byType(LgShortcutGroup))
          .map((g) => g.title);
      expect(groups, ['显示器', '画面', '输入', '操作', '会话', '聊天', '窗口和标签']);
      expect(row(tester, '下一个显示器').keys, ['Ctrl', 'Alt', 'Shift', 'Right']);
      expect(row(tester, '截图').keys, ['Ctrl', 'Alt', 'Shift', 'P']);
      expect(row(tester, '刷新画面').keys, isEmpty);
      expect(find.text('编码：VP9'), findsOneWidget);
      expect(find.text('已暂停全部快捷键'), findsNothing);
    });

    testWidgets('sending the keys to the remote device greys the list', (tester) async {
      bindings([binding(kShortcutActionScreenshot, 'p')]);
      await _pump(tester, shortcutsSection);
      expect(tester.widget<LgShortcutGroup>(find.byType(LgShortcutGroup).first).disabled,
          isFalse);
      await _tap(tester, _switch('将组合键发送到远程设备'));
      expect(jsonDecode(_bind.local[kShortcutLocalConfigKey]!)['pass_through'], isTrue);
      expect(find.text('已暂停全部快捷键'), findsOneWidget);
      expect(
          tester
              .widgetList<LgShortcutGroup>(find.byType(LgShortcutGroup))
              .every((g) => g.disabled),
          isTrue);
      // Out of use, not only dimmed: a screen reader can't reach "修改", "清除" or the reset.
      expect(
          tester
              .widgetList<LgShortcutRow>(find.byType(LgShortcutRow))
              .every((r) => r.onEdit == null && r.onClear == null),
          isTrue);
      expect(tester.widget<LgButton>(_button('恢复默认')).onPressed, isNull);
    });

    testWidgets('recording: the five states, and replacing', (tester) async {
      bindings([binding(kShortcutActionScreenshot, 'p')]);
      await _pump(tester, shortcutsSection);
      await _tap(tester, find.bySemanticsLabel('修改快捷键：刷新画面'));
      expect(find.text('设置快捷键：刷新画面'), findsOneWidget);

      LgShortcutRecordDialog dialog() =>
          tester.widget(find.byType(LgShortcutRecordDialog));
      expect(dialog().state, LgShortcutRecordState.waiting);
      expect(find.text('请按下组合键'), findsOneWidget);

      Future<void> press(List<LogicalKeyboardKey> keys) async {
        for (final k in keys) {
          await tester.sendKeyDownEvent(k, platform: 'windows');
        }
        for (final k in keys.reversed) {
          await tester.sendKeyUpEvent(k, platform: 'windows');
        }
        await tester.pump();
      }

      const mods = [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.shiftLeft,
      ];
      await press([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.f13]);
      expect(dialog().state, LgShortcutRecordState.unsupported);
      expect(find.text('“F13”不能用作快捷键'), findsOneWidget);

      await press([LogicalKeyboardKey.keyR]);
      expect(dialog().state, LgShortcutRecordState.missingModifier);
      expect(find.text('组合键须包含 Ctrl、Alt 或 Shift'), findsOneWidget);

      await press([...mods, LogicalKeyboardKey.keyR]);
      expect(dialog().state, LgShortcutRecordState.valid);
      expect(dialog().keys, ['Ctrl', 'Alt', 'Shift', 'R']);

      await press([...mods, LogicalKeyboardKey.keyP]);
      expect(dialog().state, LgShortcutRecordState.conflict);
      expect(find.text('已用于“截图”，替换后该操作将没有快捷键'), findsOneWidget);
      await _tap(tester, _button('替换'));
      expect(find.byType(LgShortcutRecordDialog), findsNothing);
      expect(row(tester, '刷新画面').keys, ['Ctrl', 'Alt', 'Shift', 'P']);
      expect(row(tester, '截图').keys, isEmpty);
    });

    testWidgets('Esc cancels the recording; clearing needs no question', (tester) async {
      bindings([binding(kShortcutActionScreenshot, 'p')]);
      await _pump(tester, shortcutsSection);
      await _tap(tester, find.bySemanticsLabel('修改快捷键：截图'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(find.byType(LgShortcutRecordDialog), findsNothing);
      expect(row(tester, '截图').keys, ['Ctrl', 'Alt', 'Shift', 'P']);

      await _tap(tester, find.bySemanticsLabel('清除快捷键：截图'));
      expect(row(tester, '截图').keys, isEmpty);
    });

    testWidgets('reset asks first, then puts the defaults back', (tester) async {
      bindings([binding(kShortcutActionRefresh, 'r')]);
      await _pump(tester, shortcutsSection);
      await _tap(tester, _button('恢复默认'));
      expect(find.text('恢复默认快捷键？'), findsOneWidget);
      expect(find.text('当前的全部快捷键设置将被默认设置替换。'), findsOneWidget);
      await _tap(tester, _button('取消'));
      expect(row(tester, '刷新画面').keys, isNotEmpty);

      await _tap(tester, _button('恢复默认'));
      await _tap(tester, _button('恢复默认').last);
      expect(row(tester, '刷新画面').keys, isEmpty);
      expect(row(tester, '截图').keys, ['Ctrl', 'Alt', 'Shift', 'P']);
    });
  });

  group('incoming print jobs', () {
    testWidgets('four choices; a chosen printer shows its drop-down', (tester) async {
      _bind.printers = ['书房打印机', '客厅打印机'];
      await _pump(tester, printJobsSection);
      expect(tester.widget<LgRadio<Object?>>(_radio('每次询问')).groupValue,
          PrintJobChoice.ask);
      expect(find.text('打印机'), findsNothing);
      expect(find.text('系统中没有可用的打印机'), findsNothing);

      await _tap(tester, _radio('使用指定的打印机打印'));
      expect(
          (
            _bind.local[kKeyPrinterIncomingJobAction],
            _bind.local[kKeyPrinterAllowAutoPrint],
            _bind.local[kKeyPrinterSelected],
          ),
          ('selected', 'Y', '书房打印机'));
      final printer = _select(tester, '打印机');
      expect(printer.items.map((i) => i.label), ['书房打印机', '客厅打印机']);
      expect(printer.value, '书房打印机');

      await _tap(tester, _radio('不打印'));
      expect(_bind.local[kKeyPrinterIncomingJobAction], 'dismiss');
      await _tap(tester, _radio('每次询问'));
      expect(
          (
            _bind.local[kKeyPrinterIncomingJobAction],
            _bind.local[kKeyPrinterAllowAutoPrint],
          ),
          ('', 'N'));
    });

    testWidgets('no printer: the two printing choices are greyed, and why', (tester) async {
      await _pump(tester, printJobsSection);
      expect(find.text('系统中没有可用的打印机'), findsOneWidget);
      bool usable(String label) =>
          tester.widget<LgRadio<PrintJobChoice>>(_radio(label)).onChanged !=
          null;
      expect(
          [for (final l in ['每次询问', '使用默认打印机打印', '使用指定的打印机打印', '不打印']) usable(l)],
          [true, false, false, true]);
    });
  });

  group('other', () {
    testWidgets('portable: three choices for closing, each explained', (tester) async {
      await _pump(tester, otherSection);
      expect(_on(tester, '关闭窗口前确认断开会话'), isTrue);
      expect(find.text('本机将无法接受远程连接，正在使用的出口也将停止'), findsOneWidget);
      expect(find.text('服务和正在使用的出口将继续运行。再次启动 Leapgate 即可恢复窗口。'),
          findsOneWidget);
      expect(find.text('硬件编解码'), findsNothing);

      await _tap(tester, _radio('在后台运行'));
      expect(_bind.local['leapgate-close-action'], 'background');
      await _tap(tester, _radio('每次询问'));
      expect(_bind.local['leapgate-close-action'], '');
      await _tap(tester, _switch('关闭窗口前确认断开会话'));
      expect(_bind.local[kOptionEnableConfirmClosingTabs], 'N');
    });

    testWidgets('installed: no closing choice; the hardware codec when there is one', (tester) async {
      _bind
        ..installed = true
        ..hwcodec = true;
      await _pump(tester, otherSection);
      expect(find.text('关闭主窗口时'), findsNothing);
      expect(_on(tester, '硬件编解码'), isTrue);
      await _tap(tester, _switch('硬件编解码'));
      await _tap(tester, _switch('硬件编解码'));
      expect(_bind.config[kOptionEnableHwcodec], 'Y');
      expect(_bind.callsTo(#mainCheckHwcodec), hasLength(1));
    });
  });

  group('about', () {
    testWidgets('one screen: versions, build, fingerprint, ID, source', (tester) async {
      _bind.fingerprint =
          '3f2a 9c41 7b0e d5a8 6c1e 04d7 b93a f582 1a2b 3c4d 5e6f 7a8b 9c0d 1e2f 3a4b 5c6d';
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      await _pump(tester, aboutSection);
      expect(find.text('Leapgate（跃门）'), findsOneWidget);
      expect(find.text('0.4.0'), findsOneWidget);
      expect(find.text('基于 RustDesk 1.5.1'), findsOneWidget);
      expect(find.text('2026-10-29'), findsOneWidget);
      expect(
          find.text('3f2a 9c41 7b0e d5a8 6c1e 04d7 b93a f582\n'
              '1a2b 3c4d 5e6f 7a8b 9c0d 1e2f 3a4b 5c6d'),
          findsOneWidget);
      expect(find.text('135 792 468'), findsOneWidget);
      expect(find.text('源代码'), findsOneWidget);
      expect(find.textContaining('Purslane Tech Pte. Ltd.'), findsOneWidget);

      await _tap(tester, find.bySemanticsLabel('复制版本'));
      expect(copied, '0.4.0');
      await _tap(tester, find.bySemanticsLabel('复制本机 ID'));
      expect(copied, '135792468');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('no fingerprint: said so, nothing to copy', (tester) async {
      await _pump(tester, aboutSection);
      expect(find.text('无法获取'), findsOneWidget);
      expect(find.bySemanticsLabel('复制指纹'), findsNothing);
    });
  });
}
