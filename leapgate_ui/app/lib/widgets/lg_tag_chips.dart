// The tags that can be switched on and off (01 §3.1 block G; `.tgf`, `.tf` in
// A-P1.html): the filter bar of the address book, and the choice of tags in the
// dialog that adds a device. A tag is drawn as everywhere else, a small square
// of its colour on a tint of it (01 §2.4); one that is on gets a ring in the
// accent colour, a check mark and bold text, never the tag colour as a solid
// ground, so the text keeps its contrast whatever colour the owner picked.
//
// Only drawing: which tags there are, which are on and what a click does belong
// to the caller.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';

/// One tag of a [LgTagFilterBar] or an [LgTagChooser].
@immutable
class LgTagToggleItem {
  const LgTagToggleItem({
    required this.id,
    required this.label,
    this.color,
    this.on = false,
  });

  /// What the callbacks get back; the label of a tag does not have to be unique
  /// in a list, the id is.
  final String id;
  final String label;

  /// The tag's colour; null for "未标记", which has no square and is tinted in
  /// the grey of the text.
  final Color? color;
  final bool on;
}

/// A tag as a button (`.tf`): `--lg-h-btn` high, the text at the medium size.
/// A click calls [onPressed]; a right click calls [onContextMenu] with where it
/// happened, for the menu of a tag (rename, change the colour, delete). With the
/// keyboard on the tag, the menu key or Shift+F10 calls it too, with the place
/// under the tag's left end.
class LgTagToggle extends StatelessWidget {
  const LgTagToggle({
    super.key,
    required this.item,
    required this.onPressed,
    this.onContextMenu,
  });

  final LgTagToggleItem item;

  /// Null greys the tag and it does not respond (a request is on its way).
  final VoidCallback? onPressed;
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r10);
    final pressable = LgPressable(
      onPressed: onPressed,
      onSecondaryTapUp: onContextMenu == null
          ? null
          : (d) => onContextMenu!(d.globalPosition),
      semanticLabel: item.label,
      toggled: item.on,
      builder: (context, states) {
        final base = c.tagTint(item.color ?? c.text2);
        final overlay = lgStateOverlay(c, states);
        return Opacity(
          opacity: states.contains(WidgetState.disabled) ? .6 : 1,
          child: LgFocusRing(
            show: states.contains(WidgetState.focused),
            radius: radius,
            child: Container(
              height: t.sizes.button,
              padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
              decoration: BoxDecoration(
                color: overlay == null ? base : Color.alphaBlend(overlay, base),
                borderRadius: radius,
              ),
              foregroundDecoration: item.on
                  ? BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(color: c.accent, width: 2),
                    )
                  : null,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.on) ...[
                      LgIcon(LgIcons.check, size: 16, color: c.accent),
                      const SizedBox(width: LgSpace.s2),
                    ],
                    if (item.color != null) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: item.color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: LgSpace.s2),
                    ],
                    Text(
                      item.label,
                      maxLines: 1,
                      softWrap: false,
                      style: t.textM.copyWith(
                        color: c.text,
                        fontWeight: item.on ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (onContextMenu == null) return pressable;
    // The menu key and Shift+F10 open the menu of the tag that has the
    // keyboard, below it (the right click has no key of its own).
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent || onPressed == null) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        final menuKey =
            key == LogicalKeyboardKey.contextMenu ||
            (key == LogicalKeyboardKey.f10 &&
                HardwareKeyboard.instance.isShiftPressed);
        final box = node.context?.findRenderObject();
        if (!menuKey || box is! RenderBox || !box.attached) {
          return KeyEventResult.ignored;
        }
        onContextMenu!(box.localToGlobal(Offset(0, box.size.height)));
        return KeyEventResult.handled;
      },
      child: pressable,
    );
  }
}

/// The filter bar of the address book (`.tgf`): "未标记" first, then the tags,
/// side by side. When they do not fit they scroll sideways (the wheel too).
/// The bar is 6 px higher than a tag, which leaves room for the focus ring.
///
/// [onToggle] gets the tag's id; [onContextMenu] gets it with the position of
/// the right click. A tag with `id` in [noMenu] (the one of "未标记") has no
/// menu.
class LgTagFilterBar extends StatefulWidget {
  const LgTagFilterBar({
    super.key,
    required this.items,
    required this.onToggle,
    this.onContextMenu,
    this.noMenu = const {},
    this.semanticLabel,
  });

  final List<LgTagToggleItem> items;
  final ValueChanged<String>? onToggle;
  final void Function(String id, Offset position)? onContextMenu;
  final Set<String> noMenu;

  /// Name of the group for a screen reader ("标签筛选").
  final String? semanticLabel;

  @override
  State<LgTagFilterBar> createState() => _LgTagFilterBarState();
}

class _LgTagFilterBarState extends State<LgTagFilterBar> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // The wheel moves a row of tags sideways, but only when the row can move
  // that way; otherwise it is left to the page, which scrolls up and down. A
  // shifted wheel is the scroll view's own.
  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.maxScrollExtent <= 0) return;
    final target = (p.pixels + event.scrollDelta.dy).clamp(
      0.0,
      p.maxScrollExtent,
    );
    if (target == p.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _scroll.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticLabel,
      child: Listener(
        onPointerSignal: _onSignal,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              for (final (i, item) in items.indexed) ...[
                if (i > 0) const SizedBox(width: LgSpace.s2),
                LgTagToggle(
                  item: item,
                  onPressed: widget.onToggle == null
                      ? null
                      : () => widget.onToggle!(item.id),
                  onContextMenu:
                      widget.onContextMenu == null ||
                          widget.noMenu.contains(item.id)
                      ? null
                      : (p) => widget.onContextMenu!(item.id, p),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The tags to choose from in a dialog (`.tchips`): they wrap onto further
/// lines. Several can be on.
class LgTagChooser extends StatelessWidget {
  const LgTagChooser({
    super.key,
    required this.items,
    required this.onToggle,
    this.semanticLabel,
  });

  final List<LgTagToggleItem> items;

  /// Null greys all the tags (a request is on its way).
  final ValueChanged<String>? onToggle;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Wrap(
        spacing: LgSpace.s2,
        runSpacing: LgSpace.s2,
        children: [
          for (final item in items)
            LgTagToggle(
              item: item,
              onPressed: onToggle == null ? null : () => onToggle!(item.id),
            ),
        ],
      ),
    );
  }
}
