import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/appearance.dart';
import 'package:flutter_hbb/leapgate/ui_mode.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_panel_inputs.dart';
import '../../../widgets/lg_selection.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';

/// Item ids of this section.
const kAppearanceItemTheme = kCommConfKeyTheme;
const kAppearanceItemMode = kOptionLeapgateUiMode;
const kAppearanceItemLang = kCommConfKeyLang;

/// 通用 › 外观 (02 §1.5.1). Coder B.
SettingsSection appearanceSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.appearance,
      title: l10n.settingsSectionAppearance,
      items: () => [
        SettingsItem(kAppearanceItemTheme, l10n.settingsAppearanceTheme,
            options: [
              l10n.settingsAppearanceLight,
              l10n.settingsAppearanceDark,
              l10n.settingsAppearanceSystem,
            ]),
        SettingsItem(kAppearanceItemMode, l10n.settingsAppearanceMode,
            description: l10n.settingsAppearanceModeNote,
            options: [l10n.uiModeSimple, l10n.uiModeDetail]),
        SettingsItem(kAppearanceItemLang, l10n.settingsAppearanceLang,
            options: [
              l10n.settingsAppearanceSystem,
              l10n.settingsAppearanceLangZh,
              l10n.settingsAppearanceLangEn,
            ]),
      ],
      build: (context, ctx) => _appearance(context, ctx),
    );

Widget _appearance(BuildContext context, SettingsSectionContext ctx) {
  final l10n = AppLocalizations.of(context)!;
  final local = appCore.options.local;
  final config = appCore.options.config;
  final theme = switch (local.get(kCommConfKeyTheme)) {
    'light' => 'light',
    'dark' => 'dark',
    _ => kThemeSystem,
  };
  return SettingsFlow([
    LgSettingsBlock(children: [
      LgSettingsRow(
        key: ctx.keyOf(kAppearanceItemTheme),
        name: l10n.settingsAppearanceTheme,
        wide: true,
        marked: ctx.isMarked(kAppearanceItemTheme),
        error: ctx.errorOf(kAppearanceItemTheme),
        control: LgSegmented<String>(
          segments: [
            LgSegment('light', l10n.settingsAppearanceLight),
            LgSegment('dark', l10n.settingsAppearanceDark),
            LgSegment(kThemeSystem, l10n.settingsAppearanceSystem),
          ],
          selected: theme,
          onChanged: (v) =>
              ctx.save(kAppearanceItemTheme, () => setTheme(local, v)),
        ),
      ),
      LgSettingsRow(
        key: ctx.keyOf(kAppearanceItemMode),
        name: l10n.settingsAppearanceMode,
        description: l10n.settingsAppearanceModeNote,
        wide: true,
        marked: ctx.isMarked(kAppearanceItemMode),
        error: ctx.errorOf(kAppearanceItemMode),
        control: LgSegmented<bool>(
          segments: [
            LgSegment(false, l10n.uiModeSimple),
            LgSegment(true, l10n.uiModeDetail),
          ],
          selected: isDetailMode(local),
          onChanged: (v) =>
              ctx.save(kAppearanceItemMode, () => setDetailMode(local, v)),
        ),
      ),
      LgSettingsRow(
        key: ctx.keyOf(kAppearanceItemLang),
        name: l10n.settingsAppearanceLang,
        wide: true,
        marked: ctx.isMarked(kAppearanceItemLang),
        error: ctx.errorOf(kAppearanceItemLang),
        control: SizedBox(
          width: 200,
          child: LgSelectField<String>(
            dense: true,
            semanticLabel: l10n.settingsAppearanceLang,
            items: [
              LgSelectItem('', l10n.settingsAppearanceSystem),
              LgSelectItem('zh-cn', l10n.settingsAppearanceLangZh),
              LgSelectItem('en', l10n.settingsAppearanceLangEn),
            ],
            value: uiLangChoice(local.get(kCommConfKeyLang)),
            onChanged: (v) => ctx.save(
                kAppearanceItemLang,
                () => setUiLang(
                    local, config, v, PlatformDispatcher.instance.locale)),
          ),
        ),
      ),
    ]),
  ]);
}
