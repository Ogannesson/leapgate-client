import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/outgoing.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';

/// Item ids of this section.
const kToolbarItemAnyEdge = kOptionAllowMultiEdgeToolbarDock;
const kToolbarItemFlat = kKeyShowMonitorsToolbar;
const kToolbarItemNext = kOptionAllowMonitorSwitchMainToolbar;
const kToolbarItemNextCollapsed = kOptionAllowMonitorSwitchMinToolbar;

/// 传出连接 › 工具栏与显示器 (02 §1.4.4). Coder D. The open sessions' toolbars listen to these
/// keys and follow at once (`pages/session/session_toolbar.dart`).
SettingsSection toolbarSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.toolbar,
      title: l10n.settingsSectionToolbar,
      items: () => [
        SettingsItem(kToolbarItemAnyEdge, l10n.settingsToolbarAnyEdge),
        SettingsItem(kToolbarItemFlat, l10n.settingsToolbarFlatMonitors,
            description: l10n.settingsToolbarFlatMonitorsNote),
        SettingsItem(kToolbarItemNext, l10n.settingsToolbarNextMonitor),
        if (appCore.options.local.getBool(kOptionAllowMonitorSwitchMainToolbar))
          SettingsItem(kToolbarItemNextCollapsed,
              l10n.settingsToolbarNextMonitorCollapsed),
      ],
      build: (context, ctx) => _toolbar(context, ctx),
    );

Widget _toolbar(BuildContext context, SettingsSectionContext ctx) {
  final l10n = AppLocalizations.of(context)!;
  final local = appCore.options.local;
  final defaults = appCore.options.userDefault;
  final next = local.getBool(kOptionAllowMonitorSwitchMainToolbar);

  LgSettingsRow toggle(String item, String name, bool value,
          Future<bool> Function(bool) write,
          {String? description, bool indented = false}) =>
      LgSettingsRow.toggle(
        key: ctx.keyOf(item),
        name: name,
        description: description,
        value: value,
        indented: indented,
        onChanged: (v) => ctx.save(item, () => write(v)),
        marked: ctx.isMarked(item),
        error: ctx.errorOf(item),
      );

  return SettingsFlow([
    LgSettingsBlock(children: [
      toggle(
          kToolbarItemAnyEdge,
          l10n.settingsToolbarAnyEdge,
          local.getBool(kOptionAllowMultiEdgeToolbarDock),
          (v) => local.setBool(kOptionAllowMultiEdgeToolbarDock, v)),
      // Upstream keeps it among the defaults for new devices, but the toolbar reads it for
      // every device (`remote_toolbar.dart:1073-1081`).
      toggle(
          kToolbarItemFlat,
          l10n.settingsToolbarFlatMonitors,
          defaultOn(defaults, kKeyShowMonitorsToolbar),
          (v) => setDefaultOn(defaults, kKeyShowMonitorsToolbar, v),
          description: l10n.settingsToolbarFlatMonitorsNote),
      toggle(kToolbarItemNext, l10n.settingsToolbarNextMonitor, next, (v) async {
        // Off takes the folded bar's button with it (DSP:676-702).
        if (!v && !await local.setBool(kOptionAllowMonitorSwitchMinToolbar, false)) {
          return false;
        }
        return local.setBool(kOptionAllowMonitorSwitchMainToolbar, v);
      }),
      if (next)
        toggle(
            kToolbarItemNextCollapsed,
            l10n.settingsToolbarNextMonitorCollapsed,
            local.getBool(kOptionAllowMonitorSwitchMinToolbar),
            (v) => local.setBool(kOptionAllowMonitorSwitchMinToolbar, v),
            indented: true),
    ]),
  ]);
}
