import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lg_pressable.dart';

/// The Enter rule of the cards that ask something (the connection panel and
/// the confirmations): Enter runs [onEnter], the default action, only while the
/// focus is on the card itself or in a field of it. With the focus on a button
/// (a check box, an option, the drop-down too) Enter is left to that button,
/// so Tab to "取消" and Enter cancels.
///
/// The key is reported as handled, so a text field inside does not also submit
/// by itself: give the field no `onSubmitted` when the card has a default.
/// With [onEnter] null Enter does nothing here.
class LgDefaultEnter extends StatelessWidget {
  const LgDefaultEnter({super.key, required this.onEnter, required this.child});

  final VoidCallback? onEnter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (onEnter == null ||
            event is! KeyDownEvent ||
            (event.logicalKey != LogicalKeyboardKey.enter &&
                event.logicalKey != LogicalKeyboardKey.numpadEnter)) {
          return KeyEventResult.ignored;
        }
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused?.findAncestorWidgetOfExactType<LgPressable>() != null) {
          return KeyEventResult.ignored;
        }
        onEnter!();
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}
