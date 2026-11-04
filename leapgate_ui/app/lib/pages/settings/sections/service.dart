import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传入连接 › 服务与 ID (02 §1.3.8). Coder A.
SettingsSection serviceSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.service,
      title: l10n.settingsSectionService,
      locked: true,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
