import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show isWindows;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/exit_settings.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shell/navigation.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_selection.dart';
import '../../home/home_dialogs.dart' show showPermanentPasswordDialog;
import '../dialogs/allow_nets_dialog.dart';
import '../net_rows.dart';
import '../settings_registry.dart';

/// Item ids of this section.
const kExitItemAllow = kOptionLeapgateAllowExit;
const kExitItemNets = kOptionLeapgateExitAllowNets;

/// 传入连接 › 出口 (02 §1.3.6), Windows only. Coder B.
SettingsSection exitNodeSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.exitNode,
      title: l10n.settingsSectionExitNode,
      locked: true,
      visible: () => isWindows,
      items: () => [
        SettingsItem(kExitItemAllow, l10n.settingsExitAllow,
            description: l10n.settingsExitAllowNote),
        if (exitAllowed(appCore.options.config))
          SettingsItem(kExitItemNets, l10n.settingsExitNets,
              description: l10n.settingsExitNetsNote),
      ],
      build: (context, ctx) => _ExitBody(ctx: ctx),
    );

class _ExitBody extends StatefulWidget {
  const _ExitBody({required this.ctx});

  final SettingsSectionContext ctx;

  @override
  State<_ExitBody> createState() => _ExitBodyState();
}

class _ExitBodyState extends State<_ExitBody> {
  ExitPrerequisites? _prerequisites;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(_ExitBody old) {
    super.didUpdateWidget(old);
    // The page builds the section again when it reads the values again.
    _read();
  }

  Future<void> _read() async {
    final p = await readExitPrerequisites(appCore.options.config);
    if (mounted && p != _prerequisites) setState(() => _prerequisites = p);
  }

  Future<void> _toggle(AppLocalizations l10n, bool on) async {
    final ctx = widget.ctx;
    final config = appCore.options.config;
    if (!on) {
      // Nothing to warn about when no session uses the exit node; unknown counts are warned.
      final count = await exitSessionCount();
      if (count != 0) {
        final ok = await confirmInSettings(
          ctx.overlays,
          title: l10n.settingsExitOffTitle,
          body: count == null
              ? l10n.settingsExitOffBodyUnknown
              : l10n.settingsExitOffBody(count),
          action: l10n.settingsExitOff,
          cancel: l10n.homeCancel,
        );
        if (!ok) return;
      }
    }
    await ctx.save(kExitItemAllow,
        () => config.set(kOptionLeapgateAllowExit, on ? 'Y' : 'N'));
  }

  Future<void> _editNets(AppLocalizations l10n) async {
    final ctx = widget.ctx;
    final value = await showAllowNetsDialog(ctx.overlays, l10n,
        stored: appCore.options.config.get(kOptionLeapgateExitAllowNets));
    if (value == null) return;
    await ctx.save(kExitItemNets,
        () => appCore.options.config.set(kOptionLeapgateExitAllowNets, value));
  }

  Future<void> _setPassword(AppLocalizations l10n) async {
    await showPermanentPasswordDialog(widget.ctx.overlays, l10n);
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ctx = widget.ctx;
    final config = appCore.options.config;
    final on = exitAllowed(config);
    final p = _prerequisites;
    final nets = allowedNetCount(config.get(kOptionLeapgateExitAllowNets));
    void link(SettingsSectionId section, String item) =>
        mainNavigation.showSettings(section, item: item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NetRow(
          ctx: ctx,
          item: kExitItemAllow,
          name: l10n.settingsExitAllow,
          description: l10n.settingsExitAllowNote,
          control: LgSwitch(
            value: on,
            semanticLabel: l10n.settingsExitAllow,
            onChanged: ctx.locked ? null : (v) => _toggle(l10n, v),
          ),
        ),
        if (on && p != null) ...[
          NetSubheading(l10n.settingsExitUnattended),
          switch (p.fixedPassword) {
            FixedPassword.set =>
              NetStatusLine(ok: true, text: l10n.settingsExitPasswordSet),
            FixedPassword.notSet => NetStatusLine(
                ok: false,
                text: l10n.settingsExitPasswordNotSet,
                action: l10n.settingsExitSet,
                onAction: ctx.locked ? null : () => _setPassword(l10n),
              ),
            FixedPassword.oneTimeOnly => NetStatusLine(
                ok: false,
                text: l10n.settingsExitPasswordOneTimeOnly,
                action: l10n.settingsExitChange,
                onAction: () =>
                    link(SettingsSectionId.access, 'verification-method'),
              ),
          },
          switch (p.approval) {
            Approval.password =>
              NetStatusLine(ok: true, text: l10n.settingsExitApprovalPassword),
            Approval.both =>
              NetStatusLine(ok: true, text: l10n.settingsExitApprovalBoth),
            Approval.click => NetStatusLine(
                ok: false,
                text: l10n.settingsExitApprovalClick,
                action: l10n.settingsExitChange,
                onAction: () => link(SettingsSectionId.access, 'approve-mode'),
              ),
          },
          NetSubheading(l10n.settingsExitLanProtection),
          NetRow(
            ctx: ctx,
            item: kExitItemNets,
            name: l10n.settingsExitNets,
            description: l10n.settingsExitNetsNote,
            control: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: LgSpace.s3,
              children: [
                Text(nets == 0
                    ? l10n.settingsExitNetsNone
                    : l10n.settingsExitNetsCount(nets)),
                LgButton(
                  label: l10n.settingsExitEdit,
                  onPressed: ctx.locked ? null : () => _editNets(l10n),
                ),
              ],
            ),
          ),
          p.tunnelAllowed
              ? NetStatusLine(
                  ok: false,
                  text: l10n.settingsExitTunnelOn,
                  action: l10n.settingsExitChange,
                  onAction: () =>
                      link(SettingsSectionId.permissions, kOptionEnableTunnel),
                )
              : NetStatusLine(ok: true, text: l10n.settingsExitTunnelOff),
        ],
      ],
    );
  }
}
