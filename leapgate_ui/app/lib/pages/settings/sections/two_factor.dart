import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传入连接 › 二次验证 (02 §1.3.3). Coder C (`LEAPGATE.md` §10.14); hidden until built.
SettingsSection twoFactorSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.twoFactor,
      title: l10n.settingsSectionTwoFactor,
      locked: true,
      visible: () => false,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
