import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传入连接 › 远程打印 (02 §1.3.7). Coder C (`LEAPGATE.md` §10.14); hidden until built.
SettingsSection remotePrintingSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.remotePrinting,
      title: l10n.settingsSectionRemotePrinting,
      locked: true,
      visible: () => false,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
