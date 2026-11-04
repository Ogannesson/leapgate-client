import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../settings_registry.dart';

/// 传出连接 › 收到的打印任务 (02 §1.4.7). Coder D (`LEAPGATE.md` §10.14); hidden until built.
SettingsSection printJobsSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.printJobs,
      title: l10n.settingsSectionPrintJobs,
      visible: () => false,
      items: () => const [],
      build: (context, ctx) => const SizedBox.shrink(),
    );
