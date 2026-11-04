import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 通用 › 网络和服务器 (02 §1.5.2). Coder B.
SettingsSection networkSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.network,
      title: l10n.settingsSectionNetwork,
      locked: true,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
