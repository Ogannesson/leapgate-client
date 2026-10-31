// The "会话" menu (01 P2 block B): switches the remote device has to allow. Upstream:
// `flutter/lib/common/widgets/toolbar.dart` `toolbarDisplayToggle` (:1072-1148) and
// `toolbarPrivacyMode` (:1224-1323), with the privacy mode rows of `_DisplayMenu`
// (`remote_toolbar.dart:1783-1811`). "同步剪贴板" is upstream's "Disable clipboard" turned
// round. As upstream, privacy mode stays usable while it is on even when its permission was
// taken back, so it can be turned off.

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/notices.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'entries.dart';
import 'toolbar_env.dart';

const kSessionMenuActions = [
  kShortcutActionToggleMute,
  kShortcutActionToggleDisableClipboard,
  kShortcutActionToggleEnableFileCopyPaste,
  kShortcutActionToggleLockAfterSessionEnd,
  kShortcutActionPrivacyMode1,
  kShortcutActionPrivacyMode2,
];

Future<List<TbEntry>> sessionMenuEntries(ToolbarEnv env) async {
  final l10n = env.l10n;
  final ffi = env.ffi;
  final model = env.model;
  final pi = env.pi;
  final noKeyboard = env.keyboardReason;
  final viewOnly = model.viewOnly ? l10n.menuViewOnlyUnavailable : null;
  final entries = <TbEntry>[];
  if (!env.isDefaultConn) return entries;

  TbItem toggle(
    String label,
    String option,
    String actionId,
    String? reason, {
    bool inverted = false,
  }) => TbItem(
    label: label,
    checked: inverted
        ? !(ffi.options.getToggle(option) || model.viewOnly)
        : ffi.options.getToggle(option),
    actionId: actionId,
    disabledReason: reason,
    onPressed: reason != null
        ? null
        : () async {
            await ffi.options.toggle(option);
            env.notifyChanged();
          },
  );

  entries.add(
    toggle(
      l10n.menuMute,
      'disable-audio',
      kShortcutActionToggleMute,
      env.permitted('audio') ? null : l10n.menuNoAudio,
    ),
  );
  entries.add(
    toggle(
      l10n.menuSyncClipboard,
      'disable-clipboard',
      kShortcutActionToggleDisableClipboard,
      noKeyboard ??
          (env.permitted('clipboard') ? null : l10n.menuNoClipboard) ??
          viewOnly,
      inverted: true,
    ),
  );

  // Files over the clipboard: Windows peers before 1.2.4, otherwise when both ends support it
  // (`toolbar.dart:1086-1098`).
  final supportedBefore124 =
      versionCmp(pi.version, '1.2.4') < 0 &&
      isWindows &&
      pi.platform == kPeerPlatformWindows;
  final supportedFrom124 =
      versionCmp(pi.version, '1.2.4') >= 0 &&
      bind.mainHasFileClipboard() &&
      pi.platformAdditions.containsKey(kPlatformAdditionsHasFileClipboard);
  if (supportedBefore124 || supportedFrom124) {
    entries.add(
      toggle(
        l10n.menuFileCopyPaste,
        kOptionEnableFileCopyPaste,
        kShortcutActionToggleEnableFileCopyPaste,
        noKeyboard ??
            (env.permitted('file') ? null : l10n.menuNoFile) ??
            viewOnly,
      ),
    );
  }
  if (!model.isPeerAndroid) {
    entries.add(
      toggle(
        l10n.menuLockAfterEnd,
        'lock-after-session-end',
        kShortcutActionToggleLockAfterSessionEnd,
        noKeyboard ?? viewOnly,
      ),
    );
  }
  entries.addAll(_privacyMode(env));
  return entries;
}

/// The privacy mode rows: one switch, or one per implementation in a submenu
/// (`remote_toolbar.dart:1783-1811`, `toolbar.dart:1224-1323`).
List<TbEntry> _privacyMode(ToolbarEnv env) {
  final l10n = env.l10n;
  final ffi = env.ffi;
  final model = env.model;
  final pi = env.pi;
  final active = ffi.privacyMode.value;
  if (!pi.features.privacyMode && active.isEmpty) return const [];
  final permitted = env.permitted('privacy_mode');
  final reason = active.isNotEmpty
      ? (model.viewOnly ? l10n.menuViewOnlyUnavailable : null)
      : env.keyboardReason ??
            (permitted ? null : l10n.menuNoPrivacy) ??
            (model.viewOnly ? l10n.menuViewOnlyUnavailable : null);

  /// Upstream turns it on only from display 1, unless switching displays keeps it private.
  bool displayAllowed(String implKey, bool turnOn) {
    if (!turnOn ||
        allowDisplaySwitchInPrivacyMode(pi, implKey) ||
        (pi.currentDisplay == 0 &&
            !bind.sessionIsMultiUiSession(sessionId: env.sessionId))) {
      return true;
    }
    late final SessionNotice notice;
    notice = SessionNotice(
      'Please switch to Display 1 first',
      args: const {'type': 'custom-nook-nocancel-hasclose', 'title': 'info'},
      tag: 'privacy-mode-display-1',
      actions: [
        NoticeAction('Switch to Display 1', () {
          ffi.notices.dismiss(notice);
          openMonitorInTheSameTab(0, ffi, pi);
        }),
      ],
    );
    ffi.notices.add(notice);
    return false;
  }

  String actionOf(String name) =>
      name == 'privacy_mode_impl_virtual_display_tip'
      ? kShortcutActionPrivacyMode2
      : kShortcutActionPrivacyMode1;

  final impls =
      pi.platformAdditions[kPlatformAdditionsSupportedPrivacyModeImpl]
          as List<dynamic>?;
  if (impls == null) {
    // Older peers: the legacy option, as the magnifier implementation.
    return [
      TbItem(
        label: l10n.menuPrivacyMode,
        checked: active.isNotEmpty,
        actionId: kShortcutActionPrivacyMode1,
        disabledReason: reason,
        onPressed: reason != null
            ? null
            : () {
                if (!displayAllowed(kPrivacyModeImplMag, active.isEmpty)) {
                  return;
                }
                bind.sessionToggleOption(
                  sessionId: env.sessionId,
                  value: 'privacy-mode',
                );
                env.notifyChanged();
              },
      ),
    ];
  }
  if (impls.isEmpty) return const [];
  if (impls.length == 1) {
    final implKey = (impls[0] as List<dynamic>)[0] as String;
    final name = (impls[0] as List<dynamic>)[1] as String;
    return [
      TbItem(
        label: l10n.menuPrivacyMode,
        checked: active.isNotEmpty,
        actionId: actionOf(name),
        disabledReason: reason,
        onPressed: reason != null
            ? null
            : () {
                if (!displayAllowed(implKey, active.isEmpty)) return;
                bind.sessionTogglePrivacyMode(
                  sessionId: env.sessionId,
                  implKey: implKey,
                  on: active.isEmpty,
                );
                env.notifyChanged();
              },
      ),
    ];
  }
  // Without the permission only the one that is on is listed, so it can be turned off.
  final rows = <TbEntry>[];
  for (final e in impls) {
    final implKey = (e as List<dynamic>)[0] as String;
    final name = e[1] as String;
    if (!permitted && active != implKey) continue;
    final on = active == implKey;
    final rowReason = model.viewOnly
        ? l10n.menuViewOnlyUnavailable
        : (permitted || on ? null : l10n.menuNoPrivacy);
    rows.add(
      TbItem(
        label: switch (name) {
          'privacy_mode_impl_mag_tip' => l10n.menuPrivacyMag,
          'privacy_mode_impl_virtual_display_tip' => l10n.menuPrivacyVirtual,
          _ => translate(name),
        },
        checked: on,
        actionId: actionOf(name),
        disabledReason: rowReason,
        onPressed: rowReason != null
            ? null
            : () {
                if (!on && !permitted) return;
                if (!displayAllowed(implKey, !on)) return;
                bind.sessionTogglePrivacyMode(
                  sessionId: env.sessionId,
                  implKey: implKey,
                  on: !on,
                );
                env.notifyChanged();
              },
      ),
    );
  }
  return [
    TbSubmenu(
      label: l10n.menuPrivacyMode,
      items: rows,
      disabledReason: rows.isEmpty ? reason ?? l10n.menuNoPrivacy : null,
    ),
  ];
}
