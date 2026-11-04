import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/common.dart' show isWindows;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/options.dart';
import 'package:flutter_hbb/leapgate/settings/access.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_selection.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';

/// `access-mode`: Rust takes anything but these two as custom (`connection.rs:2689-2738`);
/// custom is written as nothing.
const _full = 'full';
const _view = 'view';

/// A permission: its option key (the item id; `enable-tunnel` is fixed, the exit node section
/// links to it), name and description.
typedef _Permission = (String key, String name, String? description);

/// The twelve in 02's order, those this device shows.
List<_Permission> _permissions(AppLocalizations l10n) => [
  (kOptionEnableKeyboard, l10n.settingsPermKeyboard, null),
  (kOptionEnableClipboard, l10n.settingsPermClipboard, null),
  (
    kOptionEnableFileTransfer,
    l10n.settingsPermFileTransfer,
    l10n.settingsPermFileTransferNote,
  ),
  (kOptionEnableAudio, l10n.settingsPermAudio, null),
  (kOptionEnableCamera, l10n.settingsPermCamera, null),
  (kOptionEnableTerminal, l10n.settingsPermTerminal, null),
  (kOptionEnableTunnel, l10n.settingsPermTunnel, l10n.settingsPermTunnelNote),
  (kOptionEnableRemoteRestart, l10n.settingsPermRestart, null),
  (kOptionEnableRecordSession, l10n.settingsPermRecord, null),
  if (isWindows) (kOptionEnableBlockInput, l10n.settingsPermBlockInput, null),
  if (privacyModeSupported())
    (kOptionEnablePrivacyMode, l10n.settingsPermPrivacy, null),
  if (isWindows) (kOptionEnableRemotePrinter, l10n.settingsPermPrinter, null),
  // Apart from the twelve, last (02 §1.3.2).
  (
    kOptionAllowRemoteConfigModification,
    l10n.settingsPermRemoteConfig,
    l10n.settingsPermRemoteConfigNote,
  ),
];

/// 传入连接 › 权限 (02 §1.3.2). Coder A.
SettingsSection permissionsSection(AppLocalizations l10n) => SettingsSection(
  id: SettingsSectionId.permissions,
  title: l10n.settingsSectionPermissions,
  locked: true,
  items: () => [
    SettingsItem(
      kOptionAccessMode,
      l10n.settingsPermAccessMode,
      description: l10n.settingsAccessNewConnectionsOnly,
      options: [
        l10n.settingsPermCustom,
        l10n.settingsPermFull,
        l10n.settingsPermView,
      ],
    ),
    for (final (key, name, description) in _permissions(l10n))
      SettingsItem(key, name, description: description ?? ''),
  ],
  build: (context, ctx) => _Permissions(l10n: l10n, ctx: ctx),
);

class _Permissions extends StatelessWidget {
  const _Permissions({required this.l10n, required this.ctx});

  final AppLocalizations l10n;
  final SettingsSectionContext ctx;

  OptionScope get _config => appCore.options.config;

  @override
  Widget build(BuildContext context) {
    final mode = switch (_config.get(kOptionAccessMode)) {
      _full => _full,
      _view => _view,
      _ => '',
    };
    final open = !ctx.locked;
    final custom = open && mode == '';
    final permissions = _permissions(l10n);
    Widget toggle(_Permission p) {
      final (key, name, description) = p;
      return KeyedSubtree(
        key: ctx.keyOf(key),
        child: LgSettingsRow.toggle(
          name: name,
          description: description,
          marked: ctx.isMarked(key),
          error: ctx.errorOf(key),
          value: switch (mode) {
            _full => true,
            _view => false,
            _ => _config.getBool(key),
          },
          onChanged: custom
              ? (v) => ctx.save(key, () => _config.setBool(key, v))
              : null,
        ),
      );
    }

    return SettingsFlow(
      children: [
        LgSettingsBlock(
          children: [
            KeyedSubtree(
              key: ctx.keyOf(kOptionAccessMode),
              child: LgSettingsRow(
                name: l10n.settingsPermAccessMode,
                description: l10n.settingsAccessNewConnectionsOnly,
                wide: true,
                marked: ctx.isMarked(kOptionAccessMode),
                error: ctx.errorOf(kOptionAccessMode),
                control: LgSegmented<String>(
                  segments: [
                    LgSegment('', l10n.settingsPermCustom),
                    LgSegment(_full, l10n.settingsPermFull),
                    LgSegment(_view, l10n.settingsPermView),
                  ],
                  selected: mode,
                  onChanged: open
                      ? (v) {
                          if (v == mode) return;
                          ctx.save(
                            kOptionAccessMode,
                            () => _config.set(kOptionAccessMode, v),
                          );
                        }
                      : null,
                ),
              ),
            ),
          ],
        ),
        // The whole group shows what applies: all on with full access, all off with screen
        // sharing only (upstream `fakeValue`).
        if (mode != '')
          LgSettingsNote(
            l10n.settingsPermDecidedBy(
              mode == _full ? l10n.settingsPermFull : l10n.settingsPermView,
            ),
          ),
        LgSettingsBlock(
          disabled: mode != '',
          children: [
            for (final p in permissions.take(permissions.length - 1)) toggle(p),
          ],
        ),
        // Apart from the twelve (02 §1.3.2).
        LgSettingsBlock(
          gap: true,
          disabled: mode != '',
          children: [toggle(permissions.last)],
        ),
      ],
    );
  }
}
