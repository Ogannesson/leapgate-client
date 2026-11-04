import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 通用 › 其他 (02 §1.5.4). Coder D (`LEAPGATE.md` §10.14); hidden until built.
SettingsSection otherSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.other,
      title: l10n.settingsSectionOther,
      visible: () => false,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
