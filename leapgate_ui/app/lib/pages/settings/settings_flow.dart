import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../widgets/lg_settings_layout.dart';

/// A section's parts (blocks, small titles, notes, banners) with the room `LgSettingsContent`
/// puts between its own children (`LgSettingsContent.gapBetween`). A section builds one widget;
/// the page puts it into the content as its only child.
class SettingsFlow extends StatelessWidget {
  const SettingsFlow(this.parts, {super.key});

  final List<Widget> parts;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, part) in parts.indexed) ...[
        if (i > 0)
          SizedBox(height: LgSettingsContent.gapBetween(parts[i - 1], part)),
        part,
      ],
    ],
  );
}

/// Hands over what is typed into a settings box before its section goes away: a number field
/// saves when it loses the focus, and one taken out of the tree with the focus does not
/// (`LgSettingsNumberField`). Takes the focus away and lets the field hear it now. Does
/// nothing while a frame is being built, where nothing has been typed into a section yet.
void commitSettingsInput() {
  if (SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks) {
    return;
  }
  FocusManager.instance.primaryFocus?.unfocus();
  FocusManager.instance.applyFocusChangesIfNeeded();
}
