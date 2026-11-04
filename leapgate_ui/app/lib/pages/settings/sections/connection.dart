import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传出连接 › 连接方式 (02 §1.4.1). Coder B.
SettingsSection connectionSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.connection,
      title: l10n.settingsSectionConnection,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
