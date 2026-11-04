import 'package:flutter/widgets.dart';

import '../../widgets/lg_settings_layout.dart';

/// A section's parts (blocks, small titles, notes, banners) with the spaces of
/// [LgSettingsContent] between them: a section builds one widget, the page puts it in the
/// content column.
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
