import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shell/navigation.dart';
import '../../shell/tab_overlays.dart';
import 'settings_registry.dart';
import 'settings_section_state.dart';

// TODO(M6a coder A): the real page (02 §1.2): designer's navigation, search, lock bar and
// unlock, scrolling to and marking an item, reading the values again on refocus, the section
// remembered for this run. This placeholder only lists the sections so the other lane can see
// its own while working.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.overlays});

  final TabOverlays overlays;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsSectionId _current = SettingsSectionId.access;
  SettingsSectionState? _state;

  @override
  void initState() {
    super.initState();
    settingsPageRequests.addListener(_onRequest);
    _onRequest();
  }

  @override
  void dispose() {
    settingsPageRequests.removeListener(_onRequest);
    _state?.dispose();
    super.dispose();
  }

  void _onRequest() {
    final request = settingsPageRequests.take();
    if (request == null) return;
    setState(() => _current = request.section);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sections = settingsSections(l10n).where((s) => s.visible()).toList();
    final section = sections.firstWhere((s) => s.id == _current,
        orElse: () => sections.first);
    _state ??= SettingsSectionState(
        overlays: widget.overlays, saveFailedText: l10n.settingsSaveFailed);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 180,
          child: ListView(children: [
            for (final s in sections)
              TextButton(
                onPressed: () => setState(() => _current = s.id),
                child: Text(s.title),
              ),
          ]),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: _state!,
            builder: (context, _) => ListView(children: [
              Text(section.title),
              section.build(context, _state!),
            ]),
          ),
        ),
      ],
    );
  }
}
