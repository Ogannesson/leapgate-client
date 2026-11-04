import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 通用 › 关于 (02 §1.5.5). Coder D (`LEAPGATE.md` §10.14); hidden until built.
SettingsSection aboutSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.about,
      title: l10n.settingsSectionAbout,
      visible: () => false,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
