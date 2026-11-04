import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传入连接 › 出口 (02 §1.3.6), Windows only. Coder B.
SettingsSection exitNodeSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.exitNode,
      title: l10n.settingsSectionExitNode,
      locked: true,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
