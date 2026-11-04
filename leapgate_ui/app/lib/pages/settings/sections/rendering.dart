import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传出连接 › 渲染 (02 §1.4.5). Coder D (`LEAPGATE.md` §10.14); hidden until built.
SettingsSection renderingSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.rendering,
      title: l10n.settingsSectionRendering,
      visible: () => false,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
