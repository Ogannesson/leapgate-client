import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传入连接 › 访问与密码 (02 §1.3.1). Coder A.
SettingsSection accessSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.access,
      title: l10n.settingsSectionAccess,
      locked: true,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
