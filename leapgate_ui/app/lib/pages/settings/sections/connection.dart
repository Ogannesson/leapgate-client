import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/connection_settings.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shell/navigation.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_selection.dart';
import '../../../widgets/lg_text_field.dart';
import '../net_rows.dart';
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
  final _wait = TextEditingController();
  final _waitFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _wait.text = appCore.options.local.get(kOptionRelayFallbackDelay);
    _waitFocus.addListener(() {
      if (!_waitFocus.hasFocus) _saveWait();
    });
    _read();
  }

  @override
  void didUpdateWidget(_ConnectionBody old) {
    super.didUpdateWidget(old);
    _read();
  }

  @override
  void dispose() {
    _wait.dispose();
    _waitFocus.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final notes = await readConnectionNotes(appCore.options.config);
    if (mounted) setState(() => _notes = notes);
  }

  /// Enter or leaving the field saves; a wrong value is not saved and says so (02 §1.2.5).
  Future<void> _saveWait() async {
    final l10n = AppLocalizations.of(context)!;
    final local = appCore.options.local;
    final value = parseFallbackDelay(_wait.text);
    if (value == null) {
      widget.ctx.setError(kConnItemWait, l10n.settingsConnWaitInvalid);
      return;
    }
    if (value == local.get(kOptionRelayFallbackDelay)) {
      widget.ctx.setError(kConnItemWait, null);
      return;
    }
    await widget.ctx
        .save(kConnItemWait, () => local.set(kOptionRelayFallbackDelay, value));
  }

  /// Esc puts back what is saved.
  void _restoreWait() {
    _wait.text = appCore.options.local.get(kOptionRelayFallbackDelay);
    widget.ctx.setError(kConnItemWait, null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final ctx = widget.ctx;
    final local = appCore.options.local;
    final punch = punchOn(local);
    void toNetwork() => mainNavigation.showSettings(SettingsSectionId.network);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (shown, text) in [
          (_notes.proxy, l10n.settingsConnNoteProxy),
          (_notes.webSocket, l10n.settingsConnNoteWebSocket),
          (_notes.udpDisabled, l10n.settingsConnNoteUdp),
          (_notes.keyUnusable, l10n.settingsConnNoteKey),
          (_notes.compatServer, l10n.settingsConnNoteCompat),
        ])
          if (shown)
            NetNote(
                text: text,
                link: l10n.settingsSectionNetwork,
                onLink: toNetwork),
        NetRow(
          ctx: ctx,
          item: kConnItemPunch,
          name: l10n.settingsConnPunch,
          description: l10n.settingsConnPunchNote,
          control: LgSwitch(
            value: punch,
            semanticLabel: l10n.settingsConnPunch,
            onChanged: (v) =>
                ctx.save(kConnItemPunch, () => setPunch(local, v)),
          ),
        ),
        NetSubheading(l10n.settingsConnAdvanced),
        NetRow(
          ctx: ctx,
          item: kConnItemTcpPunch,
          name: l10n.settingsConnTcpPunch,
          note: punch ? null : l10n.settingsConnTcpPunchAlwaysOn,
          control: LgSwitch(
            // Upstream punches TCP whatever this says when the others are off.
            value: !punch || local.getBool(kOptionEnableTcpPunch),
            semanticLabel: l10n.settingsConnTcpPunch,
            onChanged: punch
                ? (v) => ctx.save(
                    kConnItemTcpPunch, () => local.setBool(kOptionEnableTcpPunch, v))
                : null,
          ),
        ),
        NetRow(
          ctx: ctx,
          item: kConnItemWait,
          name: l10n.settingsConnWait,
          description: l10n.settingsConnWaitNote,
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 96,
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape):
                        _restoreWait,
                  },
                  child: LgTextField(
                    controller: _wait,
                    focusNode: _waitFocus,
                    placeholder: '2.5',
                    semanticLabel: l10n.settingsConnWait,
                    showErrorText: false,
                    errorText: ctx.errorOf(kConnItemWait),
                    onSubmitted: (_) => _saveWait(),
                  ),
                ),
              ),
              const SizedBox(width: LgSpace.s2),
              Text(l10n.settingsConnWaitUnit,
                  style: t.text.copyWith(color: t.colors.text2)),
            ],
          ),
        ),
      ],
    );
  }
}
