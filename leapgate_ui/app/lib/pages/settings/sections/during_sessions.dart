import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/incoming_sessions.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_selection.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../../../widgets/lg_tooltip.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';

/// Item id of the recording folder.
const _folder = 'recording-folder';

/// `allow-terminal-clipboard-write`: empty asks each time (upstream
/// `kTerminalClipboardWrite*`).
const _ask = '';
const _allow = 'Y';
const _deny = 'N';

/// 传出连接 › 会话期间 (02 §1.4.3). Coder C.
SettingsSection duringSessionsSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.duringSessions,
      title: l10n.settingsSectionDuringSessions,
      items: () => [
        SettingsItem(kOptionAllowSyncClipboardBetweenSessions,
            l10n.settingsDuringSyncClipboard,
            description: l10n.settingsDuringSyncClipboardNote),
        SettingsItem(
            kOptionKeepAwakeDuringOutgoingSessions, l10n.settingsDuringKeepAwake),
        SettingsItem(kOptionAllowTerminalClipboardWrite,
            l10n.settingsDuringTerminalClipboard,
            description: l10n.settingsDuringTerminalClipboardNote,
            options: [
              l10n.settingsDuringTerminalAsk,
              l10n.settingsDuringTerminalAllow,
              l10n.settingsDuringTerminalDeny,
            ]),
        SettingsItem(
            kOptionAllowAutoRecordOutgoing, l10n.settingsDuringAutoRecord),
        SettingsItem(_folder, l10n.settingsSessionsRecordDir),
      ],
      build: (context, ctx) => _DuringSessions(ctx: ctx),
    );

class _DuringSessions extends StatelessWidget {
  const _DuringSessions({required this.ctx});

  final SettingsSectionContext ctx;

  Future<void> _changeFolder(RecordingFolder folder) async {
    final path = await FilePicker.platform.getDirectoryPath(
        initialDirectory: folder.exists ? folder.path : null);
    if (path == null) return;
    await ctx.save(_folder, () => setRecordingFolder(appCore.options.local, path));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final local = appCore.options.local;

    Widget toggle(String key, String name, {String? note}) =>
        LgSettingsRow.toggle(
          key: ctx.keyOf(key),
          name: name,
          description: note,
          value: local.getBool(key),
          onChanged: (v) => ctx.save(key, () => local.setBool(key, v)),
          marked: ctx.isMarked(key),
          error: ctx.errorOf(key),
        );

    final terminal = switch (local.get(kOptionAllowTerminalClipboardWrite)) {
      _allow => _allow,
      _deny => _deny,
      _ => _ask,
    };
    final folder = readRecordingFolder(service: false);
    final actions = LgSettingsValueActions(
      actions: [
        LgSettingsAction(
          label: l10n.settingsSessionsOpen,
          semanticLabel: l10n.settingsSessionsOpenLabel,
          onPressed: folder.exists ? () => openFolder(folder.path) : null,
        ),
        LgSettingsAction(
          label: l10n.settingsSessionsChange,
          semanticLabel: l10n.settingsSessionsChangeLabel,
          onPressed: () => _changeFolder(folder),
        ),
      ],
    );
    return SettingsFlow([
      LgSettingsBlock(children: [
        toggle(kOptionAllowSyncClipboardBetweenSessions,
            l10n.settingsDuringSyncClipboard,
            note: l10n.settingsDuringSyncClipboardNote),
        toggle(kOptionKeepAwakeDuringOutgoingSessions,
            l10n.settingsDuringKeepAwake),
        LgSettingsRow(
          key: ctx.keyOf(kOptionAllowTerminalClipboardWrite),
          name: l10n.settingsDuringTerminalClipboard,
          description: l10n.settingsDuringTerminalClipboardNote,
          wide: true,
          marked: ctx.isMarked(kOptionAllowTerminalClipboardWrite),
          error: ctx.errorOf(kOptionAllowTerminalClipboardWrite),
          control: LgSegmented<String>(
            segments: [
              LgSegment(_ask, l10n.settingsDuringTerminalAsk),
              LgSegment(_allow, l10n.settingsDuringTerminalAllow),
              LgSegment(_deny, l10n.settingsDuringTerminalDeny),
            ],
            selected: terminal,
            onChanged: (v) => ctx.save(kOptionAllowTerminalClipboardWrite,
                () => local.set(kOptionAllowTerminalClipboardWrite, v)),
          ),
        ),
      ]),
      LgSettingsSubtitle(l10n.settingsSessionsRecording),
      LgSettingsBlock(children: [
        toggle(kOptionAllowAutoRecordOutgoing, l10n.settingsDuringAutoRecord),
        LgSettingsRow(
          key: ctx.keyOf(_folder),
          name: l10n.settingsSessionsRecordDir,
          // On the installed version incoming sessions go to the service's own folder.
          description:
              serviceRecordsIncoming() ? null : l10n.settingsDuringRecordDirShared,
          body: Text(folder.path),
          wide: true,
          marked: ctx.isMarked(_folder),
          error: ctx.errorOf(_folder),
          control: folder.exists
              ? actions
              : LgTooltip(
                  message: l10n.settingsSessionsFolderMissing, child: actions),
        ),
      ]),
    ]);
  }
}
