import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show isWindows;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/settings/exit_settings.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shell/navigation.dart';
import '../../../widgets/lg_banner.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../../home/home_dialogs.dart' show showPermanentPasswordDialog;
import '../dialogs/allow_nets_dialog.dart';
import '../settings_flow.dart';
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

  /// Asking the service how many sessions use the exit node.
  bool _counting = false;

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
      // The service may take up to 2 s to answer: the switch waits, so a second click can't
      // stack a second question.
      setState(() => _counting = true);
      int? count;
      try {
        count = await exitSessionCount();
      } catch (e) {
        // An answer that can't be read is an unknown count: asked with the general body.
        lgBind.leapgateLog(
            level: 2, msg: 'leapgate ui: exit session count unreadable: $e');
      } finally {
        if (mounted) setState(() => _counting = false);
      }
      if (!mounted) return;
      if (count != 0) {
        final ok = await ctx.overlays.show<bool>(
              null,
              (context, close) => LgDialogScrim(
                onEscape: () => close(false),
                child: LgConfirmDialog(
                  title: l10n.settingsExitOffTitle,
                  body: count == null
                      ? l10n.settingsExitOffBodyUnknown
                      : l10n.settingsExitOffBody(count),
                  actions: [
                    LgDialogAction(
                        label: l10n.homeCancel, onPressed: () => close(false)),
                    LgDialogAction(
                      label: l10n.settingsExitOff,
                      kind: LgButtonKind.primary,
                      isDefault: true,
                      onPressed: () => close(true),
                    ),
                  ],
                ),
              ),
            ) ??
            false;
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
    // A locked section can't be used at all (02 §1.2.5 rule 4), its links included.
    LgSettingsAction link(
            SettingsSectionId section, String item, String semanticLabel) =>
        LgSettingsAction(
          label: l10n.settingsExitChange,
          semanticLabel: semanticLabel,
          onPressed: ctx.locked
              ? null
              : () => mainNavigation.showSettings(section, item: item),
        );
    // With "完全访问" the tunnel switch is greyed under the access mode: that is what to change.
    final fullAccess = config.get(kOptionAccessMode) == 'full';
    LgSettingsStatusRow status(bool ok, String text,
            {String? description,
            List<LgSettingsAction> actions = const [],
            String? item}) =>
        LgSettingsStatusRow(
          key: item == null ? null : ctx.keyOf(item),
          tone: ok ? LgTone.success : LgTone.warning,
          toneLabel: ok ? l10n.settingsExitMet : l10n.settingsExitAttention,
          text: text,
          description: description,
          actions: actions,
          marked: item != null && ctx.isMarked(item),
        );
    return SettingsFlow([
      LgSettingsBlock(children: [
        LgSettingsRow.toggle(
          key: ctx.keyOf(kExitItemAllow),
          name: l10n.settingsExitAllow,
          description: l10n.settingsExitAllowNote,
          value: on,
          onChanged: ctx.locked || _counting ? null : (v) => _toggle(l10n, v),
          marked: ctx.isMarked(kExitItemAllow),
          error: ctx.errorOf(kExitItemAllow),
        ),
      ]),
      if (on && p != null) ...[
        LgSettingsSubtitle(l10n.settingsExitUnattended),
        LgSettingsBlock(children: [
          switch (p.fixedPassword) {
            FixedPassword.set => status(true, l10n.settingsExitPasswordSet),
            FixedPassword.notSet =>
              status(false, l10n.settingsExitPasswordNotSet, actions: [
                LgSettingsAction(
                  label: l10n.settingsExitSet,
                  semanticLabel: l10n.settingsExitSetPasswordLabel,
                  onPressed: ctx.locked ? null : () => _setPassword(l10n),
                ),
              ]),
            FixedPassword.oneTimeOnly => status(
                false, l10n.settingsExitPasswordOneTimeOnly,
                actions: [
                  link(SettingsSectionId.access, 'verification-method',
                      l10n.settingsExitChangeVerificationLabel),
                ]),
          },
          switch (p.approval) {
            Approval.password =>
              status(true, l10n.settingsExitApprovalPassword),
            Approval.both => status(true, l10n.settingsExitApprovalBoth),
            Approval.click => status(false, l10n.settingsExitApprovalClick,
                actions: [
                  link(SettingsSectionId.access, 'approve-mode',
                      l10n.settingsExitChangeApprovalLabel),
                ]),
          },
        ]),
        LgSettingsSubtitle(l10n.settingsExitLanProtection),
        LgSettingsBlock(children: [
          // Allowing none is the safe default; what is allowed is said, not warned about.
          LgSettingsStatusRow(
            key: ctx.keyOf(kExitItemNets),
            tone: nets == 0 ? LgTone.success : LgTone.info,
            toneLabel: nets == 0 ? l10n.settingsExitMet : null,
            text: nets == 0
                ? l10n.settingsExitNetsNone
                : l10n.settingsExitNetsCount(nets),
            description: l10n.settingsExitNetsNote,
            marked: ctx.isMarked(kExitItemNets),
            actions: [
              LgSettingsAction(
                label: l10n.settingsExitEdit,
                semanticLabel: l10n.settingsExitEditNetsLabel,
                onPressed: ctx.locked ? null : () => _editNets(l10n),
              ),
            ],
          ),
          p.tunnelAllowed
              ? status(false, l10n.settingsExitTunnelOn, actions: [
                  fullAccess
                      ? link(SettingsSectionId.permissions, kOptionAccessMode,
                          l10n.settingsExitChangeAccessModeLabel)
                      : link(SettingsSectionId.permissions, kOptionEnableTunnel,
                          l10n.settingsExitChangeTunnelLabel),
                ])
              : status(true, l10n.settingsExitTunnelOff),
        ]),
        // A status row has no error line of its own.
        if (ctx.errorOf(kExitItemNets) case final error?)
          LgBanner(tone: LgTone.error, slim: true, dense: true, text: error),
      ],
    ]);
  }
}
