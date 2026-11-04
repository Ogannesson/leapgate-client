import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;
import 'package:flutter_hbb/leapgate/settings/two_factor.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../../../widgets/lg_trusted_devices.dart';
import '../../peer_platform.dart';
import '../dialogs/telegram_dialog.dart';
import '../dialogs/two_factor_dialog.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';

/// Item ids of this section.
const _twoFactor = '2fa';
const _trusted = kOptionEnableTrustedDevices;
const _devices = 'trusted-devices';
const _bot = 'telegram-bot';

/// 传入连接 › 二次验证 (02 §1.3.3). Coder C.
SettingsSection twoFactorSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.twoFactor,
      title: l10n.settingsSectionTwoFactor,
      locked: true,
      items: () => [
        SettingsItem(_twoFactor, l10n.settingsSectionTwoFactor,
            description: l10n.settingsTwoFactorNote),
        if (twoFactorOn()) ...[
          SettingsItem(_trusted, l10n.settingsTwoFactorTrusted,
              description: l10n.settingsTwoFactorTrustedNote),
          SettingsItem(_devices, l10n.settingsTwoFactorDevices),
          SettingsItem(_bot, l10n.settingsTwoFactorBot,
              description: l10n.settingsTwoFactorBotNote),
        ],
      ],
      build: (context, ctx) => _TwoFactorBody(ctx: ctx),
    );

class _TwoFactorBody extends StatefulWidget {
  const _TwoFactorBody({required this.ctx});

  final SettingsSectionContext ctx;

  @override
  State<_TwoFactorBody> createState() => _TwoFactorBodyState();
}

class _TwoFactorBodyState extends State<_TwoFactorBody> {
  List<TrustedDevice> _list = const [];

  /// The IDs of the picked rows.
  final _picked = <String>{};

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(_TwoFactorBody old) {
    super.didUpdateWidget(old);
    // The page builds the section again when it reads the values again.
    _read();
  }

  Future<void> _read() async {
    final list = twoFactorOn() ? await readTrustedDevices() : const <TrustedDevice>[];
    if (!mounted) return;
    setState(() {
      _list = list;
      _picked.retainWhere((id) => list.any((d) => d.id == id));
    });
  }

  Future<bool> _confirm(String title,
      {String? body, required String action}) async {
    final l10n = AppLocalizations.of(context)!;
    return await widget.ctx.overlays.show<bool>(
          null,
          (context, close) => LgDialogScrim(
            onEscape: () => close(false),
            child: LgConfirmDialog(
              title: title,
              body: body,
              actions: [
                LgDialogAction(
                    label: l10n.homeCancel, onPressed: () => close(false)),
                LgDialogAction(
                  label: action,
                  kind: LgButtonKind.dangerSolid,
                  isDefault: true,
                  onPressed: () => close(true),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<void> _turnOn(AppLocalizations l10n) async {
    if (!await showTwoFactorDialog(widget.ctx.overlays, l10n)) return;
    appCore.toasts.show('settingsTwoFactorEnabled');
    widget.ctx.setError(_twoFactor, null);
    await _read();
  }

  Future<void> _turnOff(AppLocalizations l10n) async {
    if (!await _confirm(l10n.settingsTwoFactorOffTitle,
        body: l10n.settingsTwoFactorOffBody,
        action: l10n.settingsTwoFactorTurnOff)) {
      return;
    }
    await widget.ctx
        .save(_twoFactor, () => turnOffTwoFactor(appCore.options.config));
  }

  Future<void> _deletePicked(AppLocalizations l10n) async {
    final picked = _list.where((d) => _picked.contains(d.id)).toList();
    if (!await _confirm(l10n.settingsTwoFactorDeletePickedTitle(picked.length),
        action: l10n.settingsTwoFactorDelete)) {
      return;
    }
    await removeTrustedDevices(picked, _list.length);
    await _read();
  }

  Future<void> _deleteAll(AppLocalizations l10n) async {
    if (!await _confirm(l10n.settingsTwoFactorDeleteAllTitle,
        action: l10n.settingsTwoFactorDelete)) {
      return;
    }
    await clearTrustedDevices();
    await _read();
  }

  Future<void> _setUpBot(AppLocalizations l10n) async {
    if (!await showTelegramDialog(widget.ctx.overlays, l10n)) return;
    widget.ctx.setError(_bot, null);
    if (mounted) setState(() {});
  }

  Future<void> _removeBot(AppLocalizations l10n) async {
    if (!await _confirm(l10n.settingsTwoFactorBotRemoveTitle,
        action: l10n.settingsTwoFactorBotRemove)) {
      return;
    }
    await widget.ctx.save(_bot, () => removeBot(appCore.options.config));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ctx = widget.ctx;
    final config = appCore.options.config;
    final on = twoFactorOn();
    final bot = on && botSet();
    final open = !ctx.locked;
    final now = DateTime.now();
    return SettingsFlow([
      LgSettingsBlock(
        disabled: ctx.locked,
        children: [
          LgSettingsRow(
            key: ctx.keyOf(_twoFactor),
            name: l10n.settingsSectionTwoFactor,
            description: l10n.settingsTwoFactorNote,
            wide: true,
            marked: ctx.isMarked(_twoFactor),
            error: ctx.errorOf(_twoFactor),
            control: LgSettingsValueActions(
              value: on
                  ? l10n.settingsTwoFactorStateOn
                  : l10n.settingsTwoFactorStateOff,
              emphasized: on,
              actions: [
                on
                    ? LgSettingsAction(
                        label: l10n.settingsTwoFactorTurnOff,
                        semanticLabel: l10n.settingsTwoFactorTurnOffLabel,
                        onPressed: open ? () => _turnOff(l10n) : null,
                      )
                    : LgSettingsAction(
                        label: l10n.settingsTwoFactorTurnOn,
                        semanticLabel: l10n.settingsTwoFactorDialogTitle,
                        onPressed: open ? () => _turnOn(l10n) : null,
                      ),
              ],
            ),
          ),
          if (on) ...[
            LgSettingsRow.toggle(
              key: ctx.keyOf(_trusted),
              name: l10n.settingsTwoFactorTrusted,
              description: l10n.settingsTwoFactorTrustedNote,
              indented: true,
              value: config.getBool(kOptionEnableTrustedDevices),
              onChanged: open
                  ? (v) => ctx.save(
                      _trusted, () => config.setBool(kOptionEnableTrustedDevices, v))
                  : null,
              marked: ctx.isMarked(_trusted),
              error: ctx.errorOf(_trusted),
            ),
            LgSettingsRowFrame(
              key: ctx.keyOf(_devices),
              indented: true,
              marked: ctx.isMarked(_devices),
              child: LgTrustedDevices(
                title: l10n.settingsTwoFactorDevices,
                devices: [
                  for (final d in _list)
                    LgTrustedDevice(
                      id: d.id,
                      name: d.name,
                      formattedId: formatPeerId(d.id),
                      platform: lgPlatformOf(d.platform),
                      remaining: switch (d.daysLeft(now)) {
                        0 => l10n.settingsTwoFactorExpiresToday,
                        final days => l10n.settingsTwoFactorDaysLeft(days),
                      },
                    ),
                ],
                picked: _picked,
                onToggle: (id) {
                  if (!open) return;
                  setState(() =>
                      _picked.contains(id) ? _picked.remove(id) : _picked.add(id));
                },
                emptyText: l10n.settingsTwoFactorDevicesEmpty,
                deleteAllLabel: l10n.settingsTwoFactorDeleteAll,
                onDeleteAll: open ? () => _deleteAll(l10n) : null,
                pickedCountLabel: l10n.settingsTwoFactorPicked(_picked.length),
                deleteLabel: l10n.settingsTwoFactorDelete,
                onDeleteSelected: open ? () => _deletePicked(l10n) : null,
              ),
            ),
            LgSettingsRow(
              key: ctx.keyOf(_bot),
              name: l10n.settingsTwoFactorBot,
              description: l10n.settingsTwoFactorBotNote,
              indented: true,
              wide: true,
              marked: ctx.isMarked(_bot),
              error: ctx.errorOf(_bot),
              control: LgSettingsValueActions(
                value: bot
                    ? l10n.settingsTwoFactorBotSet
                    : l10n.settingsTwoFactorBotNotSet,
                emphasized: bot,
                actions: [
                  bot
                      ? LgSettingsAction(
                          label: l10n.settingsTwoFactorBotRemove,
                          semanticLabel: l10n.settingsTwoFactorBotRemoveLabel,
                          onPressed: open ? () => _removeBot(l10n) : null,
                        )
                      : LgSettingsAction(
                          label: l10n.settingsTwoFactorBotSetUp,
                          semanticLabel: l10n.settingsTwoFactorBotTitle,
                          onPressed: open ? () => _setUpBot(l10n) : null,
                        ),
                ],
              ),
            ),
          ],
        ],
      ),
    ]);
  }
}
