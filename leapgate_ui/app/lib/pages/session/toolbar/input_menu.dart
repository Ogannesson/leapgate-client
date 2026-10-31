// The "输入" menu (01 P2 block B). Upstream: `flutter/lib/desktop/widgets/remote_toolbar.dart`
// `_KeyboardMenu` (:2547-2818) and `flutter/lib/common/widgets/toolbar.dart`
// `toolbarKeyboardToggles` (:1325-1419), rewritten into 01's order. Without the keyboard and
// mouse permission the whole menu is greyed out instead of hidden. The trackpad speed is a
// slider in the menu instead of upstream's dialog (`dialog.dart:1957-2006`), and the Android
// navigation bar is switched here instead of by its own toolbar button
// (`remote_toolbar.dart:956-976`).

import 'dart:convert';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';

import 'dialogs.dart';
import 'entries.dart';
import 'toolbar_env.dart';

const kInputMenuActions = [
  kShortcutActionKeyboardModeLegacy,
  kShortcutActionKeyboardModeMap,
  kShortcutActionKeyboardModeTranslate,
  kShortcutActionToggleViewOnly,
  kShortcutActionToggleShowMyCursor,
  kShortcutActionToggleSwapCtrlCmd,
  kShortcutActionToggleRelativeMouseMode,
  kShortcutActionToggleReverseMouseWheel,
  kShortcutActionToggleSwapLeftRightMouse,
];

/// Whether the Android navigation bar shows over the image (upstream keeps it in the Flutter
/// options, `common.dart:794-806`; shown unless turned off).
bool androidNavBarShown() =>
    appCore.options.flutter.get(kOptionShowMobileAction) != 'N';

void setAndroidNavBarShown(bool shown) =>
    appCore.options.flutter.set(kOptionShowMobileAction, shown ? 'Y' : 'N');

/// The local platform asked about ANSI or ISO, '' when the peer is not a Mac
/// (`kb_layout_type_chooser.dart:167-181`; the new UI runs on Windows).
String _kbLayoutPlatform(String peerPlatform) =>
    peerPlatform == kPeerPlatformMacOS && isWindows ? kPeerPlatformWindows : '';

Future<List<TbEntry>> inputMenuEntries(ToolbarEnv env) async {
  final l10n = env.l10n;
  final ffi = env.ffi;
  final model = env.model;
  final pi = env.pi;
  final sid = env.sessionId;
  final noKeyboard = model.keyboard ? null : l10n.menuNoKeyboard;
  // Rows that send input: greyed out without the permission or in view-only mode.
  final inputReason = env.inputReason;
  final entries = <TbEntry>[];

  // Keyboard mode (`remote_toolbar.dart:2615-2676`).
  final mode =
      await bind.sessionGetKeyboardMode(sessionId: sid) ?? kKeyLegacyMode;
  String? modeOnly;
  if (isInputSourceFlutter && isDesktop) {
    if (bind.sessionIsKeyboardModeSupported(
      sessionId: sid,
      mode: kKeyMapMode,
    )) {
      modeOnly = kKeyMapMode;
    } else if (bind.sessionIsKeyboardModeSupported(
      sessionId: sid,
      mode: kKeyLegacyMode,
    )) {
      modeOnly = kKeyLegacyMode;
    }
  }
  final modes = [
    for (final (key, label, action) in [
      (
        kKeyLegacyMode,
        l10n.menuKeyboardLegacy,
        kShortcutActionKeyboardModeLegacy,
      ),
      (kKeyMapMode, l10n.menuKeyboardMap, kShortcutActionKeyboardModeMap),
      (
        kKeyTranslateMode,
        l10n.menuKeyboardTranslate,
        kShortcutActionKeyboardModeTranslate,
      ),
    ])
      if ((modeOnly == null || key == modeOnly) &&
          bind.sessionIsKeyboardModeSupported(sessionId: sid, mode: key) &&
          !(pi.isWayland && key != kKeyMapMode))
        TbItem(
          label: label,
          checked: mode == key,
          actionId: action,
          disabledReason: inputReason,
          onPressed: inputReason != null
              ? null
              : () async {
                  await bind.sessionSetKeyboardMode(sessionId: sid, value: key);
                  await ffi.inputModel.updateKeyboardMode();
                  env.notifyChanged();
                },
        ),
  ];
  if (modes.isNotEmpty) {
    entries.add(TbGroup(l10n.menuKeyboardMode));
    entries.addAll(modes);
  }

  // ANSI / ISO for a macOS peer (`remote_toolbar.dart:2678-2697`).
  final kbPlatform = _kbLayoutPlatform(pi.platform);
  if (kbPlatform.isNotEmpty) {
    final type = bind.getLocalKbLayoutType();
    entries.add(
      TbItem(
        label: l10n.menuKbLayout,
        hint: switch (type) {
          kKbLayoutIso => 'ISO',
          kKbLayoutNotIso => 'ANSI',
          _ => l10n.menuNotSet,
        },
        disabledReason: inputReason,
        onPressed: inputReason != null
            ? null
            : () async {
                await showKbLayoutDialog(env.overlays, ffi, l10n);
                env.notifyChanged();
              },
      ),
    );
  }

  // Input source, when this device has more than one (`remote_toolbar.dart:2699-2734`).
  List<dynamic> sources = const [];
  try {
    final s = bind.mainSupportedInputSource();
    if (s.isNotEmpty) sources = jsonDecode(s);
  } catch (e) {
    sources = const [];
  }
  if (sources.length >= 2) {
    final current = stateGlobal.getInputSource();
    entries.add(TbGroup(l10n.menuInputSource));
    for (final s in sources) {
      final value = s[0] as String;
      final name = s[1] as String;
      final n = RegExp(r'^Input source (\d+)$').firstMatch(name)?.group(1);
      entries.add(
        TbItem(
          label: n == null ? translate(name) : l10n.menuInputSourceN(n),
          checked: current == value,
          disabledReason: inputReason,
          onPressed: inputReason != null
              ? null
              : () async {
                  await stateGlobal.setInputSource(sid, value);
                  await model.checkDesktopKeyboardMode();
                  await ffi.inputModel.updateKeyboardMode();
                  env.notifyChanged();
                },
        ),
      );
    }
  }

  entries.add(const TbDivider());
  entries.addAll(viewOnlyEntries(env, noKeyboard));

  // Swap Ctrl and Command, when exactly one end is a Mac (`toolbar.dart:1332-1350`).
  if ((isMacOS && pi.platform != kPeerPlatformMacOS) ||
      (!isMacOS && pi.platform == kPeerPlatformMacOS)) {
    entries.add(
      _toggle(
        env,
        l10n.menuSwapCtrlCmd,
        'allow_swap_key',
        kShortcutActionToggleSwapCtrlCmd,
        inputReason,
      ),
    );
  }

  // Relative mouse mode, for peers from 1.4.5 on (`toolbar.dart:1352-1378`).
  if (isDesktop &&
      env.isDefaultConn &&
      !(isLinux && bind.mainCurrentIsWayland()) &&
      ffi.inputModel.isRelativeMouseModeSupported) {
    entries.add(
      TbItem(
        label: l10n.menuRelativeMouse,
        checked: ffi.inputModel.relativeMouseMode.value,
        actionId: kShortcutActionToggleRelativeMouseMode,
        disabledReason: inputReason,
        onPressed: inputReason != null
            ? null
            : () {
                final input = ffi.inputModel;
                final previous = input.relativeMouseMode.value;
                if (!input.setRelativeMouseMode(!previous)) {
                  input.relativeMouseMode.value = previous;
                }
                env.notifyChanged();
              },
      ),
    );
  }

  // Reverse the wheel: the session's value, else the default for new devices
  // (`toolbar.dart:1380-1398`).
  var reverse = bind.sessionGetReverseMouseWheelSync(sessionId: sid) ?? '';
  if (reverse == '') {
    reverse = bind.mainGetUserDefaultOption(key: kKeyReverseMouseWheel);
  }
  entries.add(
    TbItem(
      label: l10n.menuReverseWheel,
      checked: reverse == 'Y',
      actionId: kShortcutActionToggleReverseMouseWheel,
      disabledReason: inputReason,
      onPressed: inputReason != null
          ? null
          : () async {
              await bind.sessionSetReverseMouseWheel(
                sessionId: sid,
                value: reverse == 'Y' ? 'N' : 'Y',
              );
              env.notifyChanged();
            },
    ),
  );
  entries.add(
    _toggle(
      env,
      l10n.menuSwapMouseButtons,
      'swap-left-right-mouse',
      kShortcutActionToggleSwapLeftRightMouse,
      inputReason,
    ),
  );

  // Trackpad speed, 10%~1000% (`dialog.dart:1902-1926`).
  entries.add(TbGroup(l10n.menuTrackpadSpeed));
  entries.add(
    TbSlider(
      label: l10n.menuTrackpadSpeed,
      value: ffi.inputModel.trackpadSpeed,
      min: kMinTrackpadSpeed,
      max: kMaxTrackpadSpeed,
      format: (v) => '$v%',
      disabledReason: inputReason,
      onChanged: inputReason != null
          ? null
          : (v) async {
              await bind.sessionSetTrackpadSpeed(sessionId: sid, value: v);
              await ffi.inputModel.updateTrackpadSpeed();
            },
    ),
  );

  // Android navigation keys, peers from 1.2.7 on (`remote_toolbar.dart:2786-2817`).
  if (pi.platform == kPeerPlatformAndroid) {
    entries.add(TbGroup(l10n.menuAndroidNav));
    if (versionCmp(pi.version, '1.2.7') >= 0) {
      final input = ffi.inputModel;
      for (final (label, action) in [
        (l10n.menuNavBack, input.onMobileBack),
        (l10n.menuNavHome, input.onMobileHome),
        (l10n.menuNavRecents, input.onMobileApps),
        (l10n.menuVolumeUp, input.onMobileVolumeUp),
        (l10n.menuVolumeDown, input.onMobileVolumeDown),
        (l10n.menuPower, input.onMobilePower),
      ]) {
        entries.add(
          TbItem(
            label: label,
            disabledReason: noKeyboard,
            onPressed: noKeyboard != null ? null : action,
          ),
        );
      }
    }
    final shown = androidNavBarShown();
    entries.add(
      TbItem(
        label: l10n.menuShowNavBar,
        checked: shown,
        onPressed: () {
          setAndroidNavBarShown(!shown);
          env.notifyChanged();
        },
      ),
    );
  }
  return entries;
}

/// "仅查看模式" and "显示本机光标" (`remote_toolbar.dart:2736-2784`). The cursor row is an
/// option of view-only mode: it stays usable, and turning it on turns view-only mode on too.
List<TbEntry> viewOnlyEntries(ToolbarEnv env, String? noKeyboard) {
  final l10n = env.l10n;
  final model = env.model;
  final pi = env.pi;
  final viewOnlyAllowed =
      versionCmp(pi.version, '1.2.0') >= 0 && model.keyboard;
  return [
    TbItem(
      label: l10n.menuViewOnly,
      checked: model.viewOnly,
      actionId: kShortcutActionToggleViewOnly,
      disabledReason: noKeyboard,
      onPressed: viewOnlyAllowed ? () => _toggleViewOnly(env) : null,
    ),
    if (const [
      kPeerPlatformWindows,
      kPeerPlatformMacOS,
      kPeerPlatformLinux,
    ].contains(pi.platform))
      TbItem(
        label: l10n.menuShowMyCursor,
        checked: model.showMyCursor,
        indent: true,
        actionId: kShortcutActionToggleShowMyCursor,
        disabledReason: noKeyboard,
        onPressed: noKeyboard != null ? null : () => _toggleShowMyCursor(env),
      ),
  ];
}

Future<void> _toggleViewOnly(ToolbarEnv env) async {
  final ffi = env.ffi;
  await ffi.options.toggle(kOptionToggleViewOnly);
  ffi.ffiModel.setViewOnly(
    ffi.id,
    ffi.options.getToggle(kOptionToggleViewOnly),
  );
  ffi.ffiModel.setShowMyCursor(
    ffi.options.getToggle(kOptionToggleShowMyCursor),
  );
  env.notifyChanged();
}

Future<void> _toggleShowMyCursor(ToolbarEnv env) async {
  final ffi = env.ffi;
  await ffi.options.toggle(kOptionToggleShowMyCursor);
  final showMyCursor = ffi.options.getToggle(kOptionToggleShowMyCursor);
  ffi.ffiModel.setShowMyCursor(showMyCursor);
  if (showMyCursor && !ffi.ffiModel.viewOnly) {
    await ffi.options.toggle(kOptionToggleViewOnly);
    ffi.ffiModel.setViewOnly(
      ffi.id,
      ffi.options.getToggle(kOptionToggleViewOnly),
    );
  }
  env.notifyChanged();
}

/// A session toggle option.
TbItem _toggle(
  ToolbarEnv env,
  String label,
  String option,
  String actionId,
  String? reason,
) {
  final ffi = env.ffi;
  return TbItem(
    label: label,
    checked: ffi.options.getToggle(option),
    actionId: actionId,
    disabledReason: reason,
    onPressed: reason != null
        ? null
        : () async {
            await ffi.options.toggle(option);
            env.notifyChanged();
          },
  );
}

/// The image of an Android peer takes the navigation bar only once it shows.
bool androidNavBarApplies(FFI ffi) =>
    ffi.ffiModel.isPeerAndroid &&
    ffi.ffiModel.pi.isSet.isTrue &&
    ffi.ffiModel.waitForFirstImage.isFalse;
