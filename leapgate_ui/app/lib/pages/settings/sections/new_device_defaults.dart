import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传出连接 › 新设备的默认设置 (02 §1.4.2). Coder D (`LEAPGATE.md` §10.14); hidden until built.
SettingsSection newDeviceDefaultsSection(AppLocalizations l10n) =>
    SettingsSection(
      id: SettingsSectionId.newDeviceDefaults,
      title: l10n.settingsSectionNewDeviceDefaults,
      visible: () => false,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
