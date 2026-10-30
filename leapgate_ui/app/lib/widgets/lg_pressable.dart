import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/lg_tokens.dart';

/// Forces interaction states on the components below it, so the gallery can
/// show and export hover, pressed and focus without a pointer or keyboard.
class LgStateOverride extends InheritedWidget {
  const LgStateOverride({
    super.key,
    required this.states,
    required super.child,
  });

  final Set<WidgetState> states;

  static Set<WidgetState> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LgStateOverride>()?.states ??
      const {};

  @override
  bool updateShouldNotify(LgStateOverride old) =>
      !setEquals(old.states, states);
}

/// Shared interaction for the clickable components: hover, pressed, keyboard
/// focus (Tab), Enter / Space activation, disabled when [onPressed] is null.
class LgPressable extends StatefulWidget {
  const LgPressable({
    super.key,
    required this.onPressed,
    required this.builder,
    this.focusable = true,
    this.focusNode,
    this.autofocus = false,
    this.onActivate,
    this.onSecondaryTapUp,
    this.semanticLabel,
    this.selected,
    this.toggled,
  });

  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, Set<WidgetState> states) builder;

  /// False keeps the control out of the focus order (Windows caption buttons,
  /// tab close buttons).
  final bool focusable;
  final FocusNode? focusNode;
  final bool autofocus;

  /// What Enter and Space do, when that differs from a click (a list row:
  /// click selects, Enter connects). Defaults to [onPressed].
  final VoidCallback? onActivate;
  final GestureTapUpCallback? onSecondaryTapUp;
  final String? semanticLabel;
  final bool? selected;
  final bool? toggled;

  @override
  State<LgPressable> createState() => _LgPressableState();
}

class _LgPressableState extends State<LgPressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;
  FocusNode? _ownNode;

  FocusNode get _node =>
      widget.focusNode ??
      (_ownNode ??= FocusNode(
        skipTraversal: !widget.focusable,
        canRequestFocus: widget.focusable,
      ));

  @override
  void didUpdateWidget(LgPressable old) {
    super.didUpdateWidget(old);
    if (_ownNode != null && old.focusable != widget.focusable) {
      _ownNode!
        ..skipTraversal = !widget.focusable
        ..canRequestFocus = widget.focusable;
    }
    if (widget.onPressed == null) _pressed = false;
  }

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  void _activate() => (widget.onActivate ?? widget.onPressed)?.call();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final states = <WidgetState>{
      if (!enabled) WidgetState.disabled,
      if (enabled && _hovered) WidgetState.hovered,
      if (enabled && _pressed) WidgetState.pressed,
      if (enabled && _focused) WidgetState.focused,
      if (widget.selected == true) WidgetState.selected,
      if (enabled) ...LgStateOverride.of(context),
    };
    return FocusableActionDetector(
      enabled: enabled,
      focusNode: _node,
      autofocus: widget.autofocus,
      // Arrow, not the hand: Windows controls and the mockups set no pointer cursor.
      mouseCursor: SystemMouseCursors.basic,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => _activate(),
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) => _activate(),
        ),
      },
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPressed : null,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: widget.semanticLabel,
          selected: widget.selected,
          toggled: widget.toggled,
          child: widget.builder(context, states),
        ),
      ),
    );
  }
}

/// Background layer for hover and pressed: the mockups only define the hover
/// overlay (`--lg-hover`, menu rows); pressed stacks it twice.
Color? lgStateOverlay(LgColors c, Set<WidgetState> states) {
  if (states.contains(WidgetState.pressed)) {
    return Color.alphaBlend(c.hover, c.hover);
  }
  if (states.contains(WidgetState.hovered)) return c.hover;
  return null;
}

/// Keyboard focus ring: 2 px accent outline, 2 px outside the control
/// (`.frame .focus` in A-基础.html).
///
/// [inset] draws it just inside the control instead, for controls with no
/// room around them (the title bar's tabs and buttons, which a scroll view or
/// the bar's bottom edge would cut).
class LgFocusRing extends StatelessWidget {
  const LgFocusRing({
    super.key,
    required this.show,
    required this.radius,
    required this.child,
    this.inset = false,
  });

  final bool show;
  final BorderRadius radius;
  final Widget child;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return CustomPaint(
      foregroundPainter: _RingPainter(
        LgTokens.of(context).colors.accent,
        radius,
        inset,
      ),
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color, this.radius, this.inset);

  final Color color;
  final BorderRadius radius;
  final bool inset;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = radius.toRRect(Offset.zero & size);
    canvas.drawRRect(
      // Outside: offset 2 plus half the 2 px stroke; inside: half the stroke.
      inset ? rrect.deflate(1) : rrect.inflate(3),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.radius != radius || old.inset != inset;
}
