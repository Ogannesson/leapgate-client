import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传出连接 › 会话期间 (02 §1.4.3). Coder C (`LEAPGATE.md` §10.14); hidden until built.
SettingsSection duringSessionsSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.duringSessions,
      title: l10n.settingsSectionDuringSessions,
      visible: () => false,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
