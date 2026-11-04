import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../shell/tab_overlays.dart';
import 'sections/access.dart';
import 'sections/account.dart';
import 'sections/appearance.dart';
import 'sections/connection.dart';
import 'sections/exit_node.dart';
import 'sections/network.dart';
import 'sections/permissions.dart';
import 'sections/service.dart';
import 'settings_ids.dart';

export 'settings_ids.dart';

/// One item of a section: what search matches (02 §1.2.4: the name, the description and the
/// option names of a choice) and what links scroll to. [id] is unique within the section.
class SettingsItem {
  const SettingsItem(this.id, this.name,
      {this.description = '', this.options = const []});

  final String id;
  final String name;
  final String description;
  final List<String> options;
}

/// A section as the settings page shows and searches it (`LEAPGATE.md` §10.13).
class SettingsSection {
  const SettingsSection({
    required this.id,
    required this.title,
    required this.items,
    required this.build,
    this.visible = _always,
    this.locked = false,
  });

  static bool _always() => true;

  final SettingsSectionId id;
  final String title;

  /// The items shown now, in display order. An item hidden because a switch above it is off is
  /// left out; a locked one is listed (02 §1.2.4).
  final List<SettingsItem> Function() items;

  /// False drops the section from the navigation (02 §1.2.3: no item to show on this device).
  final bool Function() visible;

  /// On the installed version, locked until unlocked (02 §1.2.6): the page shows the lock bar
  /// and [SettingsSectionContext.locked] tells the section to disable its controls.
  final bool locked;

  /// The section's content under its title (and lock bar). Called again whenever the context
  /// changes or the page reads the values again (opened, window refocused, after a save).
  final Widget Function(BuildContext context, SettingsSectionContext ctx) build;
}

/// What the page gives a section (`LEAPGATE.md` §10.13).
abstract interface class SettingsSectionContext implements Listenable {
  /// The home tab's dialogs.
  TabOverlays get overlays;

  /// The section is locked now; the lock bar says why, items don't repeat it (02 §1.2.5 rule 4).
  /// Items that ask for administrator permission themselves stay usable (02 §1.2.6).
  bool get locked;

  /// The key of [item]'s row, so search and links can scroll to it.
  GlobalKey keyOf(String item);

  /// [item] was just opened from search or a link: its row is marked for about 2 seconds.
  bool isMarked(String item);

  /// The line under [item] ("无法保存设置", "未获得管理员权限，…"), null when none (02 §3.4).
  String? errorOf(String item);

  /// Shows [error] under [item], or clears it with null.
  void setError(String item, String? error);

  /// Runs [write] (an option scope's `set`): false shows "无法保存设置" under [item], true clears
  /// the line. The section is built again either way, which reads the values again.
  Future<bool> save(String item, Future<bool> Function() write);
}

/// Every registered section in display order. M6a registers its eight; M6b adds the rest here.
List<SettingsSection> settingsSections(AppLocalizations l10n) => [
      accessSection(l10n),
      permissionsSection(l10n),
      exitNodeSection(l10n),
      serviceSection(l10n),
      connectionSection(l10n),
      appearanceSection(l10n),
      networkSection(l10n),
      accountSection(l10n),
    ]..sort((a, b) => a.id.index.compareTo(b.id.index));

/// The group's name in the navigation.
String settingsGroupTitle(AppLocalizations l10n, SettingsGroup group) =>
    switch (group) {
      SettingsGroup.incoming => l10n.settingsGroupIncoming,
      SettingsGroup.outgoing => l10n.settingsGroupOutgoing,
      SettingsGroup.general => l10n.settingsGroupGeneral,
    };
