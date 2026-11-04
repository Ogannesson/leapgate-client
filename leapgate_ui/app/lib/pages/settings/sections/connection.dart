import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/connection_settings.dart';
import 'package:flutter_hbb/leapgate/settings/settings_api.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shell/navigation.dart';
import '../../../widgets/lg_banner.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';

/// Item ids of this section.
const kConnItemPunch = 'punch';
const kConnItemTcpPunch = kOptionEnableTcpPunch;
const kConnItemWait = kOptionRelayFallbackDelay;

/// 传出连接 › 连接方式 (02 §1.4.1). Coder B.
SettingsSection connectionSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.connection,
      title: l10n.settingsSectionConnection,
      items: () => [
        SettingsItem(kConnItemPunch, l10n.settingsConnPunch,
            description: l10n.settingsConnPunchNote),
        SettingsItem(kConnItemTcpPunch, l10n.settingsConnTcpPunch),
        SettingsItem(kConnItemWait, l10n.settingsConnWait,
            description: l10n.settingsConnWaitNote),
      ],
      build: (context, ctx) => _ConnectionBody(ctx: ctx),
    );

class _ConnectionBody extends StatefulWidget {
  const _ConnectionBody({required this.ctx});

  final SettingsSectionContext ctx;

  @override
  State<_ConnectionBody> createState() => _ConnectionBodyState();
}

class _ConnectionBodyState extends State<_ConnectionBody> {
  ConnectionNotes _notes = const ConnectionNotes();

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(_ConnectionBody old) {
    super.didUpdateWidget(old);
    _read();
  }

  Future<void> _read() async {
    final notes = await readConnectionNotes(appCore.options.config);
    if (!mounted) return;
    setState(() => _notes = notes);
    // S2 settles with no event, and the page reads again only on open, refocus and save
    // (09 §4.2): while it is still checking, read again a second later.
    if (settingsApi.serverKind() == ServerKind.checking) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _read();
      });
    }
  }

  /// Enter or leaving the box saves; a wrong value is not saved and says so (02 §1.2.5).
  Future<void> _saveWait(AppLocalizations l10n, String typed) async {
    final value = parseFallbackDelay(typed);
    if (value == null) {
      widget.ctx.setError(kConnItemWait, l10n.settingsConnWaitInvalid);
      return;
    }
    await widget.ctx.save(kConnItemWait,
        () => appCore.options.local.set(kOptionRelayFallbackDelay, value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ctx = widget.ctx;
    final local = appCore.options.local;
    final punch = punchOn(local);
    final waitError = ctx.errorOf(kConnItemWait);
    return SettingsFlow([
      for (final (shown, text) in [
        (_notes.proxy, l10n.settingsConnNoteProxy),
        (_notes.webSocket, l10n.settingsConnNoteWebSocket),
        (_notes.udpDisabled, l10n.settingsConnNoteUdp),
        (_notes.keyUnusable, l10n.settingsConnNoteKey),
        (_notes.compatServer, l10n.settingsConnNoteCompat),
      ])
        if (shown)
          LgBanner(
            tone: LgTone.warning,
            slim: true,
            dense: true,
            text: text,
            actionLabel: l10n.settingsSectionNetwork,
            onAction: () =>
                mainNavigation.showSettings(SettingsSectionId.network),
          ),
      LgSettingsBlock(children: [
        LgSettingsRow.toggle(
          key: ctx.keyOf(kConnItemPunch),
          name: l10n.settingsConnPunch,
          description: l10n.settingsConnPunchNote,
          value: punch,
          onChanged: (v) => ctx.save(kConnItemPunch, () => setPunch(local, v)),
          marked: ctx.isMarked(kConnItemPunch),
          error: ctx.errorOf(kConnItemPunch),
        ),
      ]),
      LgSettingsSubtitle(l10n.settingsConnAdvanced),
      LgSettingsBlock(children: [
        LgSettingsRow.toggle(
          key: ctx.keyOf(kConnItemTcpPunch),
          name: l10n.settingsConnTcpPunch,
          // Upstream punches TCP whatever this says when the others are off; the mockup
          // gives the reason in the description's place.
          description: punch ? null : l10n.settingsConnTcpPunchAlwaysOn,
          value: !punch || local.getBool(kOptionEnableTcpPunch),
          onChanged: (v) => ctx.save(
              kConnItemTcpPunch, () => local.setBool(kOptionEnableTcpPunch, v)),
          disabled: !punch,
          marked: ctx.isMarked(kConnItemTcpPunch),
          error: ctx.errorOf(kConnItemTcpPunch),
        ),
        LgSettingsRow(
          key: ctx.keyOf(kConnItemWait),
          name: l10n.settingsConnWait,
          description: l10n.settingsConnWaitNote,
          wide: true,
          marked: ctx.isMarked(kConnItemWait),
          error: waitError,
          errorAtEnd: true,
          control: LgSettingsNumberField(
            text: local.get(kOptionRelayFallbackDelay),
            unit: l10n.settingsConnWaitUnit,
            placeholder: '2.5',
            semanticLabel: l10n.settingsConnWaitField,
            errorText: waitError,
            onSubmitted: (typed) => _saveWait(l10n, typed),
            onReverted: () => ctx.setError(kConnItemWait, null),
          ),
        ),
      ]),
    ]);
  }
}
