import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../consts.dart';
import '../models/platform_model.dart';
import 'bridge.dart';

enum ServiceStatus { ready, connecting, notReady, stopped }

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
  Timer? _timer;

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

  void start() {
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
        verificationMethod != this.verificationMethod) {
      this.id = id;
      this.status = status;
      this.oneTimePassword = oneTimePassword;
      this.approveMode = approveMode;
      this.verificationMethod = verificationMethod;
      notifyListeners();
    }
  }
}
