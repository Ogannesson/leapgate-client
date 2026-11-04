// The exit node section (02 §1.3.6): the switch, the allowed networks, and whether this device
// is set up for unattended exits and keeps exit users off its local network.
import 'dart:convert';

import '../../consts.dart';
import '../bridge.dart';
import '../local_status.dart' show kUseTemporaryPassword;
import '../options.dart';
import '../permanent_password.dart';
import 'settings_api.dart';

/// Config: the networks the exit node may reach on this device's local network, in the form
/// Rust's `parse_allow_nets` reads (separated by commas or white space).
const kOptionLeapgateExitAllowNets = 'leapgate-exit-allow-nets';

/// Only "Y" is on (第四期 A5); `getBool` would take an unset key for on.
bool exitAllowed(OptionScope config) =>
    config.get(kOptionLeapgateAllowExit) == 'Y';

/// The stored networks as the dialog shows them, one a line.
String allowNetsText(String stored) =>
    stored.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).join('\n');

/// How many networks are allowed. A stored value Rust can't read allows none
/// (`exit/dial.rs:111-113`), so it counts as none.
int allowedNetCount(String stored) {
  final text = allowNetsText(stored);
  if (text.isEmpty) return 0;
  final check = settingsApi.allowNetsCheck(text);
  return check.valid ? check.count : 0;
}

/// The permanent password line of "无人值守".
enum FixedPassword {
  set,
  notSet,

  /// Set, but the password method is "仅一次性密码", so it is never asked for.
  oneTimeOnly,
}

/// The approval mode line: [password] and [both] pass (R2-Q6), [click] needs someone here.
enum Approval { password, both, click }

/// What the exit node section checks (02 §1.3.6).
class ExitPrerequisites {
  const ExitPrerequisites(
      {required this.fixedPassword,
      required this.approval,
      required this.tunnelAllowed});

  final FixedPassword fixedPassword;
  final Approval approval;

  /// TCP tunnels are allowed in effect: by the access mode, or by the switch when it is custom
  /// (02 §1.3.2).
  final bool tunnelAllowed;

  @override
  bool operator ==(Object other) =>
      other is ExitPrerequisites &&
      other.fixedPassword == fixedPassword &&
      other.approval == approval &&
      other.tunnelAllowed == tunnelAllowed;

  @override
  int get hashCode => Object.hash(fixedPassword, approval, tunnelAllowed);
}

/// The prerequisites from the options of 访问与密码 and 权限. `verification-method` and
/// `approve-mode` read as upstream's `ServerModel` does: empty is both.
ExitPrerequisites exitPrerequisites({
  required bool passwordSet,
  required String verificationMethod,
  required String approveMode,
  required String accessMode,
  required String enableTunnel,
}) =>
    ExitPrerequisites(
      fixedPassword: !passwordSet
          ? FixedPassword.notSet
          : verificationMethod == kUseTemporaryPassword
              ? FixedPassword.oneTimeOnly
              : FixedPassword.set,
      approval: switch (approveMode) {
        'password' => Approval.password,
        'click' => Approval.click,
        _ => Approval.both,
      },
      tunnelAllowed: switch (accessMode) {
        'full' => true,
        'view' => false,
        _ => enableTunnel != 'N',
      },
    );

Future<ExitPrerequisites> readExitPrerequisites(OptionScope config) async =>
    exitPrerequisites(
      passwordSet: (await readPermanentPasswordState()).isSet,
      verificationMethod: config.get(kOptionVerificationMethod),
      approveMode: config.get(kOptionApproveMode),
      accessMode: config.get(kOptionAccessMode),
      enableTunnel: config.get(kOptionEnableTunnel),
    );

/// How many sessions use this device as an exit node now (C1's `exit`); null when the service
/// did not answer.
Future<int?> exitSessionCount() async {
  final counts =
      jsonDecode(await lgBind.leapgateIncomingCounts()) as Map<String, dynamic>;
  return counts.isEmpty ? null : counts['exit'] as int? ?? 0;
}
