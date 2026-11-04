import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 通用 › 外观 (02 §1.5.1). Coder B.
SettingsSection appearanceSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.appearance,
      title: l10n.settingsSectionAppearance,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
