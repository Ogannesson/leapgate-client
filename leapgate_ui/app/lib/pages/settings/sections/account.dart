import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 通用 › 账号 (02 §1.5.3). Coder B.
SettingsSection accountSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.account,
      title: l10n.settingsSectionAccount,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
