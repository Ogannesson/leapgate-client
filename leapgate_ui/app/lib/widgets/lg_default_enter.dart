import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The Enter rule of the cards that ask something (the connection panel and
/// the confirmations): Enter runs [onEnter], the default action, only while the
/// focus is in an input field of the card. Anywhere else Enter is left alone:
/// a button, a check box, a drop-down and its menu items take it themselves
/// (Tab to "取消" and Enter cancels; Enter on an item of an open menu picks it),
/// and a card without inputs gives the default button the focus when it
/// appears, so Enter is that button's own press.
///
/// The key is reported as handled, so the field does not also submit by
/// itself: give the field no `onSubmitted` when the card has a default. With
/// [onEnter] null Enter does nothing here.
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
        if (focused?.findAncestorWidgetOfExactType<EditableText>() == null) {
          return KeyEventResult.ignored;
        }
        onEnter!();
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}
