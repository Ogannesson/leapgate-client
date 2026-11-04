/// The settings page's groups and sections (02 §1.2.3), in display order. The ids are fixed so
/// links ([MainNavigation.showSettings]) can name a section before it is built; the navigation
/// only lists the sections that are registered (`settings_registry.dart`).
enum SettingsGroup { incoming, outgoing, general }

enum SettingsSectionId {
  // Incoming connections.
  access(SettingsGroup.incoming),
  permissions(SettingsGroup.incoming),
  twoFactor(SettingsGroup.incoming),
  restrictions(SettingsGroup.incoming),
  sessions(SettingsGroup.incoming),
  exitNode(SettingsGroup.incoming),
  remotePrinting(SettingsGroup.incoming),
  service(SettingsGroup.incoming),
  // Outgoing connections.
  connection(SettingsGroup.outgoing),
  newDeviceDefaults(SettingsGroup.outgoing),
  duringSessions(SettingsGroup.outgoing),
  toolbar(SettingsGroup.outgoing),
  rendering(SettingsGroup.outgoing),
  shortcuts(SettingsGroup.outgoing),
  printJobs(SettingsGroup.outgoing),
  // General.
  appearance(SettingsGroup.general),
  network(SettingsGroup.general),
  account(SettingsGroup.general),
  other(SettingsGroup.general),
  about(SettingsGroup.general);

  const SettingsSectionId(this.group);

  final SettingsGroup group;
}
