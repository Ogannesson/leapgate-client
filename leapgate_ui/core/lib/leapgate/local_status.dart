import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../consts.dart';
import '../models/platform_model.dart';
import 'app_core.dart';
import 'bridge.dart';
import 'install_page.dart' show InstallOptions;
import 'settings/server_config.dart' show readSocks;

enum ServiceStatus { ready, connecting, notReady, stopped }

/// A proxy, WebSocket or UDP turned off: other devices can't connect to this one (M6-4,
/// measured with 02 §4.3 item 4). In the order the home page picks the first.
enum NetworkWarning { proxy, webSocket, udpDisabled }

// Values of kOptionVerificationMethod, as upstream `models/server_model.dart:22-24` names them.
// That file comes into core with the connection manager (M3); these move there then.
const kUseTemporaryPassword = 'use-temporary-password';
const kUsePermanentPassword = 'use-permanent-password';
const kUseBothPasswords = 'use-both-passwords';

/// What the password row of this device shows (01 P1 block A, the table of five).
enum PasswordRow {
  /// One-time password, its text.
  oneTime,

  /// One-time password, its text, and the note that the permanent password works as well.
  both,

  /// Permanent password: only that it is set.
  permanent,

  /// Approval mode: connections are accepted on this device.
  acceptOnly,

  /// One-time password, unavailable: the service is stopped.
  unavailable,
}

/// The hint card with a button (01 P1 block B, M8): installing the portable version, or
/// upgrading an installed one built earlier than this program.
enum InstallCard { install, upgrade }

/// Why the last "安装" or "升级" failed (`leapgate_install`, `LEAPGATE.md` §10.16).
@immutable
class InstallFailure {
  const InstallFailure(
      {required this.card, required this.uacDenied, required this.text});

  /// The card it failed on; another card does not show it.
  final InstallCard card;

  /// Administrator permission was not granted.
  final bool uacDenied;

  /// The installer's error otherwise, as it is; may be empty.
  final String text;
}

/// The sessions into this device (C1): how many, and whether one of them operates it (a remote
/// desktop or a terminal); the others (file transfer, camera, port forwarding, exit) do not.
@immutable
class IncomingSessions {
  const IncomingSessions(this.total, {required this.controlled});

  static const none = IncomingSessions(0, controlled: false);

  /// `leapgate_incoming_counts`; `{}` when the service did not answer.
  factory IncomingSessions.fromJson(String json) {
    final counts = jsonDecode(json) as Map<String, dynamic>;
    int n(String key) => counts[key] as int? ?? 0;
    return IncomingSessions(
      counts.values.fold(0, (sum, v) => sum + (v as int)),
      controlled: n('remote') + n('terminal') > 0,
    );
  }

  final int total;
  final bool controlled;

  @override
  bool operator ==(Object other) =>
      other is IncomingSessions &&
      other.total == total &&
      other.controlled == controlled;

  @override
  int get hashCode => Object.hash(total, controlled);
}

/// This device's ID and whether it can accept connections, polled once a second the way
/// upstream's desktop home page does (`flutter/lib/desktop/pages/connection_page.dart`
/// `updateStatus`, `desktop_home_page.dart` `fetchID`). A stand-in for the M0 placeholder page;
/// the options model (M1) takes it over.
class LocalStatusModel extends ChangeNotifier {
  String id = '';
  ServiceStatus status = ServiceStatus.connecting;

  /// The current one-time password; empty until Rust has made one.
  String oneTimePassword = '';

  /// `approve-mode`: 'password', 'click' or empty for both.
  String approveMode = '';

  /// `verification-method`: one of the kUse...Password values, or empty.
  String verificationMethod = '';

  /// What Rust reports as wrong with this device (`main_get_error`), shown as it is on the
  /// hint card (01 P1 block B); empty when nothing is.
  String systemError = '';

  /// Whether Leapgate is installed (`main_is_installed`), and built earlier than this program
  /// (`main_is_installed_lower_version`, the build time, 11 §4.4). True and false until the first
  /// poll, so no card shows before it.
  bool installed = true;
  bool installedLowerVersion = false;

  /// The card whose button was clicked while the installer runs; on success this process exits.
  InstallCard? _installing;
  bool get installing => _installing != null;

  /// The last failure, shown on its card until the next click.
  InstallFailure? installFailure;

  /// Authorized sessions into this device of every type (C1, 06 M3-1): "正在被远程控制（N 个
  /// 会话）" while one of them is a remote desktop or a terminal, "‹N› 个传入会话进行中"
  /// otherwise (01 P1 block A).
  IncomingSessions incoming = IncomingSessions.none;

  /// What keeps other devices from connecting to this one while the service line still reads
  /// "正在连接服务器…" (M6-4, 01 P1 block A); the first one that is on, null for none.
  NetworkWarning? networkWarning;
  Timer? _timer;
  Timer? _incomingTimer;

  /// Upstream `ServerModel.updatePasswordModel` (`models/server_model.dart:249-258`) shows "-"
  /// for the stopped service, the permanent password alone and accepting on this device; any
  /// other verification method counts as both (`verificationMethod` getter, :71-81).
  PasswordRow get passwordRow {
    if (status == ServiceStatus.stopped) return PasswordRow.unavailable;
    if (approveMode == 'click') return PasswordRow.acceptOnly;
    return switch (verificationMethod) {
      kUsePermanentPassword => PasswordRow.permanent,
      kUseTemporaryPassword => PasswordRow.oneTime,
      _ => PasswordRow.both,
    };
  }

  /// The card with a button (01 P1 block B): one at a time, the system error first, as
  /// upstream's `desktop_home_page.dart` `buildHelpCards`. While the installer runs it stays
  /// the card that was clicked: the script uninstalls, copies and writes the build time in
  /// turn, so the registry passes through the other card and no card.
  InstallCard? get installCard {
    if (_installing case final card?) return card;
    if (systemError.isNotEmpty) return null;
    if (!installed) return InstallCard.install;
    if (installedLowerVersion) return InstallCard.upgrade;
    return null;
  }

  /// Installs or upgrades in a child process that Rust waits for (M8-1). Returns only on failure:
  /// on success this process is ended (by the install script, or by Rust) and the installed copy
  /// starts. A second click while it runs does nothing; the export
  /// throwing or answering something unreadable counts as `failed` with the error's text.
  /// [path] and [options] are the install page's (13 §4, M9a); "升级" passes neither and keeps
  /// the installed location and options (Rust ignores them for it). Without them it is the
  /// default location with both shortcuts, as M8's card installed.
  Future<void> install(InstallCard card,
      {String? path, InstallOptions? options}) async {
    if (installing) return;
    _installing = card;
    installFailure = null;
    notifyListeners();
    InstallFailure failure;
    final o =
        options ?? (startMenu: true, desktopShortcut: true, printer: false);
    try {
      final answer = jsonDecode(await lgBind.leapgateInstall(
        kind: card.name,
        path: path ?? '',
        startMenu: o.startMenu,
        desktopShortcut: o.desktopShortcut,
        printer: o.printer,
      )) as Map<String, dynamic>;
      failure = InstallFailure(
        card: card,
        uacDenied: answer['result'] == 'uac_denied',
        text: answer['text'] as String? ?? '',
      );
    } catch (e) {
      failure = InstallFailure(card: card, uacDenied: false, text: '$e');
    } finally {
      _installing = null;
    }
    installFailure = failure;
    notifyListeners();
  }

  void start() {
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    // C1 asks the service over a new IPC connection and can take up to 2 s, so it is not on the
    // one-second poll. The main window gets no event when a session starts or ends.
    _pollIncoming();
    _incomingTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _pollIncoming());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _incomingTimer?.cancel();
    super.dispose();
  }

  /// "查看": brings the connection manager to the front (C2).
  Future<void> showConnectionManager() => lgBind.leapgateShowCm();

  Future<void> _pollIncoming() async {
    final incoming =
        IncomingSessions.fromJson(await lgBind.leapgateIncomingCounts());
    if (incoming != this.incoming) {
      this.incoming = incoming;
      notifyListeners();
    }
  }

  /// "Refresh" on the one-time password, and after its length or "仅使用数字" changed (02
  /// §1.3.1); the next poll shows the new one.
  Future<void> refreshOneTimePassword() => bind.mainUpdateTemporaryPassword();

  /// Whether "停止服务" / "启动服务" asks first (02 §1.3.8, §3.5): stopping always; starting on
  /// the installed version while sessions or exit nodes are in use, since Leapgate closes and
  /// reopens.
  bool serviceAsksFirst({required bool stop}) =>
      stop ||
      bind.mainIsInstalled() &&
          (appCore.sessions.devices.isNotEmpty ||
              appCore.backgroundCount > 0);

  /// Stops or starts the service: Rust stops or starts it when `stop-service` is set or cleared
  /// (upstream `common.dart` `start_service`; the superuser check there is macOS only). Not
  /// through S9. On the installed version Rust removes or installs the Windows service under UAC
  /// and Leapgate restarts, so a call that returns did not do it, cancelled and failed alike
  /// (09 §4.4): false then.
  Future<bool> toggleService({required bool stop}) async {
    await bind.mainSetOption(key: kOptionStopService, value: stop ? 'Y' : '');
    return !bind.mainIsInstalled();
  }

  /// Polls since [start]; the proxy is read on the first and every tenth.
  int _polls = 0;
  bool _proxy = false;

  /// The three of [NetworkWarning] only, not the whole of `readConnectionNotes`: WebSocket and
  /// UDP from the options cache on every poll, the proxy (`mainGetSocks`, a new connection to
  /// the service each time) every 10 polls. A failure keeps the last warning and leaves the rest
  /// of the poll alone.
  Future<NetworkWarning?> _readNetworkWarning() async {
    try {
      if (_polls++ % 10 == 0) _proxy = (await readSocks()).proxy.isNotEmpty;
      final config = appCore.options.config;
      if (_proxy) return NetworkWarning.proxy;
      if (config.getBool(kOptionAllowWebSocket)) return NetworkWarning.webSocket;
      if (config.get(kOptionDisableUdp) == 'Y') return NetworkWarning.udpDisabled;
      return null;
    } catch (e) {
      lgBind.leapgateLog(
          level: 2, msg: 'leapgate ui: network warning not read: ${e.runtimeType}');
      return networkWarning;
    }
  }

  Future<void> _poll() async {
    final id = await bind.mainGetMyId();
    final connect =
        jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
    final stopped = await bind.mainGetOption(key: kOptionStopService) == 'Y';
    final oneTimePassword = await bind.mainGetTemporaryPassword();
    final approveMode = await bind.mainGetOption(key: kOptionApproveMode);
    final verificationMethod =
        await bind.mainGetOption(key: kOptionVerificationMethod);
    final systemError = await bind.mainGetError();
    final installed = bind.mainIsInstalled();
    final installedLowerVersion =
        installed && bind.mainIsInstalledLowerVersion();
    final networkWarning = await _readNetworkWarning();
    final status = stopped
        ? ServiceStatus.stopped
        : switch (connect['status_num']) {
            1 => ServiceStatus.ready,
            0 => ServiceStatus.connecting,
            _ => ServiceStatus.notReady,
          };
    if (id != this.id && id.isNotEmpty) {
      lgBind.leapgateLog(level: 3, msg: 'leapgate ui: this device id $id');
    }
    if (id != this.id ||
        status != this.status ||
        oneTimePassword != this.oneTimePassword ||
        approveMode != this.approveMode ||
        verificationMethod != this.verificationMethod ||
        systemError != this.systemError ||
        installed != this.installed ||
        installedLowerVersion != this.installedLowerVersion ||
        networkWarning != this.networkWarning) {
      this.id = id;
      this.status = status;
      this.oneTimePassword = oneTimePassword;
      this.approveMode = approveMode;
      this.verificationMethod = verificationMethod;
      this.systemError = systemError;
      this.installed = installed;
      this.installedLowerVersion = installedLowerVersion;
      this.networkWarning = networkWarning;
      notifyListeners();
    }
  }
}
