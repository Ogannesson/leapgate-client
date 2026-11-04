import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传入连接 › 权限 (02 §1.3.2). Coder A.
SettingsSection permissionsSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.permissions,
      title: l10n.settingsSectionPermissions,
      locked: true,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
