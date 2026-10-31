// The connection manager (CM): the small window the service starts with `--cm` when someone
// connects to this device (docs/新界面/01-内容与逻辑说明.md §3.3). What its page needs besides
// the copied `models/server_model.dart`; upstream keeps these in its page
// (`flutter/lib/desktop/pages/server_page.dart`) and in `flutter/lib/main.dart`.

import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:ui';

import 'package:clock/clock.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart' as win32;

import '../common.dart';
import '../consts.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';
import 'app_core.dart';
import 'app_window.dart';
import 'options.dart';

/// The CM's window as the copied [ServerModel] drives it. [bringToFront] (upstream
/// `windowOnTop(null)`, called for a new visitor and an incoming voice call) also brings a
/// collapsed window back to its full size: upstream's restores it from the taskbar.
abstract class CmWindow implements AppWindow {
  /// Upstream `showCmWindow`: shows the window when it is hidden; a collapsed one stays so.
  Future<void> show();

  /// Upstream `hideCmWindow`: there are no visitors. The window stays, transparent and hidden.
  Future<void> hide();

  /// Into the strip along the top of the screen; replaces upstream's minimize (01 §3.3, Q5).
  Future<void> collapse();

  /// Closes the window, which ends the process; the page disconnects the visitors first, as
  /// upstream's `onWindowClose` does.
  Future<void> close();
}

/// The global events the CM handles (upstream `models/model.dart:392-430`, `main.dart:556-567`).
/// `chat_server_mode` and `cm_file_transfer_log` join with the chat and the file log.
void registerCmEvents(ServerModel model, CmAppearance appearance) {
  final events = appCore.events;
  events.on('add_connection', model.addConnection);
  events.on('on_client_remove', model.onClientRemove);
  events.on('show_elevation', (evt) {
    final show = evt['show'].toString() == 'true';
    model.setShowElevation(show);
  });
  events.on('update_voice_call_state', model.updateVoiceCallState);
  events.on('theme', (evt) {
    String? dark = evt['dark'];
    if (dark != null) appearance.setTheme(dark);
  });
  // Rust has saved the language into this process's LocalConfig before it pushes the event
  // (`src/ui_cm_interface.rs`, `Data::Language`).
  events.on('language', (_) => appearance.reloadLanguage());
}

/// The CM's light / dark mode and language: read at start, changed when the main window
/// changes them (01 §3.3, 02 §1.5.1).
class CmAppearance extends ChangeNotifier {
  CmAppearance(this._local)
      : themeMode = cmThemeMode(_local.get(kCommConfKeyTheme)),
        locale = cmLocale(_local.get(kCommConfKeyLang));

  final OptionScope _local;
  ThemeMode themeMode;

  /// Null follows the system.
  Locale? locale;

  /// [dark] is what the main window sends: `light`, `dark` or `system`.
  void setTheme(String dark) {
    themeMode = cmThemeMode(dark);
    notifyListeners();
  }

  void reloadLanguage() {
    locale = cmLocale(_local.get(kCommConfKeyLang));
    notifyListeners();
  }
}

/// Upstream `MyTheme.themeModeFromString` (`common.dart:621-630`).
ThemeMode cmThemeMode(String v) => switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

/// The UI has Simplified Chinese and English only (03 IQ10): any Chinese is Chinese, any other
/// language set by the upstream UI is English, unset or `default` follows the system (whose
/// languages other than Chinese also end up in English).
Locale? cmLocale(String lang) {
  if (lang.isEmpty || lang == 'default') return null;
  return lang.startsWith('zh') ? const Locale('zh') : const Locale('en');
}

/// The session types the CM tells apart; an exit node is a port forward to the exit sentinel.
enum CmSessionKind {
  remoteDesktop,
  fileTransfer,
  camera,
  terminal,
  portForward,
  exit
}

/// The login target of an exit tunnel; same values as `leapgate::exit` in Rust and
/// `flutter/lib/leapgate/exit_tunnel.dart`. The CM gets the normalized `host:port`.
const String kLeapgateExitHost = 'leapgate-exit.invalid';
const int kLeapgateExitPort = 65536;

bool isLeapgateExitAddress(String addr) =>
    addr == '$kLeapgateExitHost:$kLeapgateExitPort';

CmSessionKind cmSessionKind(Client client) => switch (client.type_()) {
      ClientType.remote => CmSessionKind.remoteDesktop,
      ClientType.file => CmSessionKind.fileTransfer,
      ClientType.camera => CmSessionKind.camera,
      ClientType.terminal => CmSessionKind.terminal,
      ClientType.portForward => isLeapgateExitAddress(client.portForward)
          ? CmSessionKind.exit
          : CmSessionKind.portForward,
    };

/// A permission switch of the CM; [name] is what `cm_switch_permission` takes.
enum CmPermission {
  keyboard('keyboard'),
  clipboard('clipboard'),
  audio('audio'),
  file('file'),
  restart('restart'),
  recording('recording'),
  blockInput('block_input'),
  privacyMode('privacy_mode');

  const CmPermission(this.name);
  final String name;
}

/// The switches the page shows for [client], in upstream's order (`server_page.dart:705-862`):
/// a remote desktop has all eight (blocking input on Windows only, privacy mode when this
/// device supports it), a camera two, other sessions and a disconnected visitor none.
List<CmPermission> cmPermissionsOf(Client client) {
  if (client.disconnected) return const [];
  return switch (cmSessionKind(client)) {
    CmSessionKind.remoteDesktop => [
        CmPermission.keyboard,
        CmPermission.clipboard,
        CmPermission.audio,
        CmPermission.file,
        CmPermission.restart,
        CmPermission.recording,
        if (isWindows) CmPermission.blockInput,
        if (bind.mainSupportedPrivacyModeImpls() != '[]')
          CmPermission.privacyMode,
      ],
    CmSessionKind.camera => const [CmPermission.audio, CmPermission.recording],
    _ => const [],
  };
}

bool cmPermissionValue(Client client, CmPermission p) => switch (p) {
      CmPermission.keyboard => client.keyboard,
      CmPermission.clipboard => client.clipboard,
      CmPermission.audio => client.audio,
      CmPermission.file => client.file,
      CmPermission.restart => client.restart,
      CmPermission.recording => client.recording,
      CmPermission.blockInput => client.blockInput,
      CmPermission.privacyMode => client.privacyMode,
    };

/// Upstream's switch handlers: tell the connection, then show the new value.
void cmSwitchPermission(Client client, CmPermission p, bool enabled) {
  bind.cmSwitchPermission(connId: client.id, name: p.name, enabled: enabled);
  switch (p) {
    case CmPermission.keyboard:
      client.keyboard = enabled;
    case CmPermission.clipboard:
      client.clipboard = enabled;
    case CmPermission.audio:
      client.audio = enabled;
    case CmPermission.file:
      client.file = enabled;
    case CmPermission.restart:
      client.restart = enabled;
    case CmPermission.recording:
      client.recording = enabled;
    case CmPermission.blockInput:
      client.blockInput = enabled;
    case CmPermission.privacyMode:
      client.privacyMode = enabled;
  }
}

/// A built-in setting can forbid changing the permissions here; the switches are then
/// read-only (`server_page.dart:671-673`).
bool cmCanModifyPermissions() =>
    bind.mainGetBuildinOption(key: kOptionEnablePermChangeInAcceptWindow) !=
    'N';

/// Upstream `buildAuthorized` (`server_page.dart:888-892`): the portable version can run
/// elevated and the service asked for it.
bool cmShowElevate(ServerModel model, Client client) =>
    bind.cmCanElevate() &&
    model.showElevation &&
    client.type_() == ClientType.remote;

/// Upstream `buildUnAuthorized` (`server_page.dart:1077-1084`): the same, unless a built-in
/// setting hides it while the visitor waits.
bool cmShowAcceptAndElevate(ServerModel model, Client client) =>
    cmShowElevate(model, client) &&
    bind.mainGetBuildinOption(key: kOptionHideElevateButtonInAcceptWindow) !=
        'Y';

/// Upstream `handleDisconnect`; also what "拒绝" does while the visitor waits.
void cmDisconnect(Client client) => bind.cmCloseConnection(connId: client.id);

/// Upstream `handleElevate`.
void cmElevate(ServerModel model, Client client) {
  model.setShowElevation(false);
  bind.cmElevatePortable(connId: client.id);
}

void cmSwitchBack(Client client) => bind.cmSwitchBack(connId: client.id);

void cmCloseVoiceCall(Client client) => bind.cmCloseVoiceCall(id: client.id);

/// Upstream `handleClose` for a disconnected visitor; true when it was the last one, and the
/// window is to close.
Future<bool> cmRemoveDisconnected(Client client) async {
  await bind.cmRemoveDisconnectedConnection(connId: client.id);
  return await bind.cmGetClientsLength() == 0;
}

/// Upstream `allowRemoteCMModification` (`server_page.dart:1250-1253`): a setting without UI
/// that lets the remote user operate the CM.
bool allowRemoteCmModification() =>
    appCore.options.local.getBool(kOptionAllowRemoteCmModification);

/// Upstream `checkClickTime` (`server_page.dart:1237-1248`): runs [callback] only if this click
/// came 120 ms or more after the remote user's last input on connection [id], so that the
/// remote user cannot operate the CM from the session. Upstream drops a blocked click without a
/// word; [onBlocked] lets the page say so (01 §3.3).
Future<void> cmCheckClickTime(int id, void Function() callback,
    {void Function()? onBlocked}) async {
  if (allowRemoteCmModification()) {
    callback();
    return;
  }
  var clickCallbackTime = clock.now().millisecondsSinceEpoch;
  await bind.cmCheckClickTime(connId: id);
  Timer(const Duration(milliseconds: 120), () async {
    var d = clickCallbackTime - await bind.cmGetClickTime();
    if (d > 120) {
      callback();
    } else {
      onBlocked?.call();
    }
  });
}

/// The primary display's work area in physical pixels and its scale: the CM and its strip sit
/// at its top right (01 §3.3). Windows only.
({Rect work, double scale}) cmPrimaryWorkArea() => using((arena) {
      final monitor = win32.MonitorFromPoint(
          arena<win32.POINT>().ref, win32.MONITOR_DEFAULTTOPRIMARY);
      final info = arena<win32.MONITORINFO>();
      info.ref.cbSize = sizeOf<win32.MONITORINFO>();
      win32.GetMonitorInfo(monitor, info);
      final dpiX = arena<Uint32>();
      final dpiY = arena<Uint32>();
      win32.GetDpiForMonitor(monitor, win32.MDT_EFFECTIVE_DPI, dpiX, dpiY);
      final r = info.ref.rcWork;
      return (
        work: Rect.fromLTRB(r.left.toDouble(), r.top.toDouble(),
            r.right.toDouble(), r.bottom.toDouble()),
        scale: dpiX.value / 96,
      );
    });
