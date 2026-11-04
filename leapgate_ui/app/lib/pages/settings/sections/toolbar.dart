import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传出连接 › 工具栏与显示器 (02 §1.4.4). Coder D (`LEAPGATE.md` §10.14); hidden until built.
SettingsSection toolbarSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.toolbar,
      title: l10n.settingsSectionToolbar,
      visible: () => false,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
