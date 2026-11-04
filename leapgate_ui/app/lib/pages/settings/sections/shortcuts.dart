import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传出连接 › 快捷键 (02 §1.4.6). Coder D (`LEAPGATE.md` §10.14); hidden until built.
SettingsSection shortcutsSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.shortcuts,
      title: l10n.settingsSectionShortcuts,
      visible: () => false,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
