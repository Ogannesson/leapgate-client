import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/outgoing.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shell/window_close.dart'
    show CloseAction, kOptionLeapgateCloseAction, rememberedCloseAction;
import '../../../widgets/lg_selection.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';

/// Item ids of this section.
const kOtherItemConfirmClose = kOptionEnableConfirmClosingTabs;
const kOtherItemCloseAction = kOptionLeapgateCloseAction;
const kOtherItemHwcodec = kOptionEnableHwcodec;

/// 通用 › 其他 (02 §1.5.4). Coder D. The two close options are the other ends of the close
/// dialog's "不再提示" and "记住此选择" (`shell/window_close.dart`).
SettingsSection otherSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.other,
      title: l10n.settingsSectionOther,
      items: () => [
        SettingsItem(kOtherItemConfirmClose, l10n.settingsOtherConfirmClose),
        // The installed version hides to the tray (Q6).
        if (!appCore.options.isInstalled)
          SettingsItem(kOtherItemCloseAction, l10n.settingsOtherCloseAction,
              options: [
                l10n.settingsOtherAsk,
                l10n.closingExit,
                l10n.closingBackground,
              ]),
        if (hasHardwareCodec())
          SettingsItem(kOtherItemHwcodec, l10n.settingsOtherHwcodec,
              description: l10n.settingsOtherHwcodecNote),
      ],
      build: (context, ctx) => _other(context, ctx),
    );

Widget _other(BuildContext context, SettingsSectionContext ctx) {
  final l10n = AppLocalizations.of(context)!;
  final local = appCore.options.local;
  final config = appCore.options.config;
  final closeAction = rememberedCloseAction(local);

  LgRadio<CloseAction?> radio(
          CloseAction? value, String label, String? description) =>
      LgRadio<CloseAction?>(
        value: value,
        groupValue: closeAction,
        label: label,
        description: description,
        onChanged: (v) {
          if (v == closeAction) return;
          ctx.save(kOtherItemCloseAction,
              () => local.set(kOptionLeapgateCloseAction, v?.name ?? ''));
        },
      );

  return SettingsFlow([
    LgSettingsBlock(children: [
      LgSettingsRow.toggle(
        key: ctx.keyOf(kOtherItemConfirmClose),
        name: l10n.settingsOtherConfirmClose,
        value: local.getBool(kOptionEnableConfirmClosingTabs),
        onChanged: (v) => ctx.save(kOtherItemConfirmClose,
            () => local.setBool(kOptionEnableConfirmClosingTabs, v)),
        marked: ctx.isMarked(kOtherItemConfirmClose),
        error: ctx.errorOf(kOtherItemConfirmClose),
      ),
      if (!appCore.options.isInstalled)
        LgSettingsRow(
          key: ctx.keyOf(kOtherItemCloseAction),
          name: l10n.settingsOtherCloseAction,
          marked: ctx.isMarked(kOtherItemCloseAction),
          error: ctx.errorOf(kOtherItemCloseAction),
          body: LgSettingsOptions(children: [
            radio(null, l10n.settingsOtherAsk, null),
            radio(CloseAction.exit, l10n.closingExit, l10n.closingExitDetail),
            radio(CloseAction.background, l10n.closingBackground,
                l10n.closingBackgroundDetail),
          ]),
        ),
      if (hasHardwareCodec())
        LgSettingsRow.toggle(
          key: ctx.keyOf(kOtherItemHwcodec),
          name: l10n.settingsOtherHwcodec,
          description: l10n.settingsOtherHwcodecNote,
          value: config.getBool(kOptionEnableHwcodec),
          onChanged: (v) =>
              ctx.save(kOtherItemHwcodec, () => setHardwareCodec(config, v)),
          marked: ctx.isMarked(kOtherItemHwcodec),
          error: ctx.errorOf(kOtherItemHwcodec),
        ),
    ]),
  ]);
}
