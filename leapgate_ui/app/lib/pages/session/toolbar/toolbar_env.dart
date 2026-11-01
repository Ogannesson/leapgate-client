// What the toolbar menus share. The conditions below are upstream's
// (`flutter/lib/common/widgets/toolbar.dart`, rewritten, not copied); where upstream hides a row
// for a permission the remote device did not give, the menus grey it out and say why (01 P2
// block B).

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';

class ToolbarEnv {
  ToolbarEnv({required this.ffi, required this.l10n, required this.overlays});

  final FFI ffi;
  final AppLocalizations l10n;

  /// The dialogs of the menus show over this session's tab only (01 §4.5).
  final TabOverlays overlays;

  /// Fired after a menu action, so an open menu builds its rows again.
  final changed = ValueNotifier(0);

  FfiModel get model => ffi.ffiModel;
  PeerInfo get pi => ffi.ffiModel.pi;
  SessionID get sessionId => ffi.sessionId;
  bool get isDefaultConn => ffi.connType == ConnType.defaultConn;

  void notifyChanged() => changed.value++;

  /// Why a row that sends input is greyed out: no keyboard and mouse permission, or view-only
  /// mode (upstream hides the first, disables the second).
  String? get inputReason {
    if (!model.keyboard) return l10n.menuNoKeyboard;
    if (model.viewOnly) return l10n.menuViewOnlyUnavailable;
    return null;
  }

  String? get keyboardReason => model.keyboard ? null : l10n.menuNoKeyboard;

  bool permitted(String name) => model.permissions[name] != false;
}

bool _isWindowsMode1PrivacyImpl(String privacyModeImpl) =>
    privacyModeImpl == kPrivacyModeImplMag ||
    privacyModeImpl == kPrivacyModeImplExcludeFromCapture;

/// Upstream `toolbar.dart:89-94`: switching displays does not weaken the privacy mode.
bool allowDisplaySwitchInPrivacyMode(PeerInfo pi, String privacyModeImpl) =>
    pi.platform == kPeerPlatformMacOS ||
    (pi.platform == kPeerPlatformWindows &&
        _isWindowsMode1PrivacyImpl(privacyModeImpl) &&
        versionCmp(pi.version, '1.4.8') >= 0);

/// Whether the display buttons show while privacy mode may be on (`remote_toolbar.dart:808-811`).
bool displaySwitchAllowed(FFI ffi) {
  final privacy = ffi.privacyMode.value;
  return privacy.isEmpty ||
      allowDisplaySwitchInPrivacyMode(ffi.ffiModel.pi, privacy);
}

/// Upstream `toolbar.dart:1461-1472`.
bool showVirtualDisplayMenu(FFI ffi) {
  final pi = ffi.ffiModel.pi;
  return pi.platform == kPeerPlatformWindows &&
      pi.isInstalled &&
      (pi.isRustDeskIdd || pi.isAmyuniIdd);
}
