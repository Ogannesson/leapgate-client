import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传入连接 › 访问限制 (02 §1.3.4). Coder C (`LEAPGATE.md` §10.14); hidden until built.
SettingsSection restrictionsSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.restrictions,
      title: l10n.settingsSectionRestrictions,
      locked: true,
      visible: () => false,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
