import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../widgets/lg_settings_layout.dart';

/// A section's blocks, small titles and notes with the room `LgSettingsContent` puts between
/// its own children (`LgSettingsContent.gapBetween`). A section builds one widget; the page puts
/// it into the content as its only child.
class SettingsFlow extends StatelessWidget {
  const SettingsFlow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, child) in children.indexed) ...[
        if (i > 0)
          SizedBox(
            height: LgSettingsContent.gapBetween(children[i - 1], child),
          ),
        child,
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
