import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传入连接 › 会话 (02 §1.3.5). Coder C (`LEAPGATE.md` §10.14); hidden until built.
SettingsSection sessionsSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.sessions,
      title: l10n.settingsSectionSessions,
      locked: true,
      visible: () => false,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
