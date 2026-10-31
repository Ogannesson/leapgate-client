// The rows a menu holds besides plain items (A-P2.html menus `m-*`, A-P1.html
// "视图" menu): a divider, rows with a switch, a slider or a stepper, the map of
// the remote displays, a row that folds a list open, and a helper that opens a
// menu at a point (a right click). All of them draw only; what the values mean
// is the caller's.
//
// The rows are built on `LgPressable`, not on `MenuItemButton`: they must not
// close the menu when used, and the menu still moves between them with the
// arrow keys because they take the focus like any control.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_menu.dart';
import 'lg_pressable.dart';
import 'lg_selection.dart';
import 'lg_slider.dart';
import 'lg_tooltip.dart';

/// The line between two groups of rows (`.mdv`).
class LgMenuDivider extends StatelessWidget {
  const LgMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return ExcludeSemantics(
      child: Container(
        height: 1,
        margin: const EdgeInsets.symmetric(
          horizontal: LgSpace.s4,
          vertical: LgSpace.s2,
        ),
        color: c.border,
      ),
    );
  }
}

/// A switch drawn on its own (`.sw`): 36×22, the knob left when off. The
/// control around it takes the focus and the clicks.
class LgSwitchGlyph extends StatelessWidget {
  const LgSwitchGlyph({super.key, required this.value, this.enabled = true});

  final bool value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    const radius = BorderRadius.all(Radius.circular(11));
    return ExcludeSemantics(
      child: Opacity(
        opacity: enabled ? 1 : .6,
        child: Container(
          width: 36,
          height: 22,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: value ? c.accent : null,
            borderRadius: radius,
          ),
          foregroundDecoration: value
              ? null
              : BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: c.borderStrong, width: 1.5),
                ),
          child: Align(
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? c.onAccent : c.borderStrong,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small check box drawn on its own (`i-square` when off): 18 px, the accent
/// colour with a check mark when on. The control around it takes the clicks.
class LgCheckGlyph extends StatelessWidget {
  const LgCheckGlyph({super.key, required this.value, this.enabled = true});

  final bool value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return ExcludeSemantics(
      child: Opacity(
        opacity: enabled ? 1 : .6,
        child: value
            ? Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: LgIcon(LgIcons.check, size: 14, color: c.onAccent),
              )
            : LgIcon(LgIcons.square, size: 18, color: c.text2),
      ),
    );
  }
}

/// The ground of a row of this file: hover and keyboard focus both tint it,
/// like the rows of `MenuItemButton`.
class _Row extends StatelessWidget {
  const _Row({
    required this.states,
    required this.height,
    required this.child,
    this.padding,
  });

  final Set<WidgetState> states;
  final double? height;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final lit =
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused) ||
        states.contains(WidgetState.pressed);
    return Container(
      height: height,
      constraints: BoxConstraints(minHeight: t.sizes.row),
      padding: padding ?? const EdgeInsets.symmetric(horizontal: LgSpace.s4),
      color: lit ? t.colors.hover : null,
      alignment: Alignment.centerLeft,
      child: DefaultTextStyle(
        style: t.text.copyWith(
          color: t.colors.text,
          fontWeight: FontWeight.w400,
        ),
        child: child,
      ),
    );
  }
}

/// A row with a switch at its end ("同步剪贴板"): a click anywhere on the row
/// turns it. The menu stays open, so several can be set in a row. [shortcut] is
/// the key combination bound to the same switch; [indent] sets the row in
/// under the one it depends on ("显示本机光标" under "仅查看模式").
class LgMenuSwitchItem extends StatelessWidget {
  const LgMenuSwitchItem({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.shortcut,
    this.indent = false,
    this.disabledNote,
  });

  final String label;
  final bool value;

  /// Null greys the row.
  final ValueChanged<bool>? onChanged;
  final String? shortcut;
  final bool indent;
  final String? disabledNote;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final enabled = onChanged != null;
    final row = LgPressable(
      onPressed: enabled ? () => onChanged!(!value) : null,
      semanticLabel: shortcut == null ? label : '$label, $shortcut',
      toggled: value,
      builder: (context, states) => Opacity(
        opacity: enabled ? 1 : .6,
        child: _Row(
          states: states,
          height: t.sizes.row,
          padding: EdgeInsets.only(
            left: indent ? LgSpace.s4 + LgSpace.s6 : LgSpace.s4,
            right: LgSpace.s4,
          ),
          child: ExcludeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: !enabled && disabledNote != null
                      ? Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        )
                      : LgEllipsisText(label),
                ),
                if (shortcut != null) ...[
                  const SizedBox(width: LgSpace.s3),
                  Flexible(
                    child: Text(
                      shortcut!,
                      style: t.textS.copyWith(color: c.text2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const SizedBox(width: LgSpace.s4),
                LgSwitchGlyph(value: value, enabled: enabled),
              ],
            ),
          ),
        ),
      ),
    );
    if (enabled || disabledNote == null) return row;
    return LgTooltip(
      message: disabledNote!,
      child: Semantics(hint: disabledNote, child: row),
    );
  }
}

/// A row that turns something on and off with a check box at its end ("始终经
/// 中继连接" in the device menu). Like [LgMenuSwitchItem], the menu stays open.
class LgMenuCheckItem extends StatelessWidget {
  const LgMenuCheckItem({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.disabledNote,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? disabledNote;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final enabled = onChanged != null;
    final row = LgPressable(
      onPressed: enabled ? () => onChanged!(!value) : null,
      semanticLabel: label,
      toggled: value,
      builder: (context, states) => Opacity(
        opacity: enabled ? 1 : .6,
        child: _Row(
          states: states,
          height: t.sizes.row,
          child: ExcludeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: !enabled && disabledNote != null
                      ? Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        )
                      : LgEllipsisText(label),
                ),
                const SizedBox(width: LgSpace.s3),
                LgCheckGlyph(value: value, enabled: enabled),
              ],
            ),
          ),
        ),
      ),
    );
    if (enabled || disabledNote == null) return row;
    return LgTooltip(
      message: disabledNote!,
      child: Semantics(hint: disabledNote, child: row),
    );
  }
}

/// A slider row (`.ms`): the knob and the value ("100%") at the end, in line
/// with the labels of the rows above (48 px in). [startLabel] is a short word
/// before the track. Up and Down stay with the menu; Left and Right move the
/// knob.
class LgMenuSliderItem extends StatelessWidget {
  const LgMenuSliderItem({
    super.key,
    required this.value,
    required this.onChanged,
    required this.format,
    required this.semanticLabel,
    this.min = 0,
    this.max = 1,
    this.step,
    this.startLabel,
    this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final double? step;

  /// Writes a value as shown at the end of the row ("100%", "1.5×"), and as a
  /// screen reader says it.
  final String Function(double value) format;

  /// Accessible name of the slider ("自定义缩放").
  final String semanticLabel;
  final String? startLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final small = t.textS.copyWith(color: c.text2);
    return Container(
      height: t.sizes.menuSlider,
      padding: const EdgeInsets.only(left: 48, right: LgSpace.s5),
      child: Row(
        children: [
          if (startLabel != null) ...[
            SizedBox(
              width: 32,
              child: Text(startLabel!, style: small, maxLines: 1),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: LgSlider(
              value: value,
              min: min,
              max: max,
              step: step,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
              semanticLabel: semanticLabel,
              format: format,
              verticalArrows: false,
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 40,
            child: ExcludeSemantics(
              child: Text(
                format(value),
                textAlign: TextAlign.right,
                maxLines: 1,
                style: small.copyWith(
                  color: c.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "− 2 +" (`.stepper`): two round buttons around the number, for how many of
/// something (virtual displays). A button at the end of the range is greyed.
class LgMenuStepperItem extends StatelessWidget {
  const LgMenuStepperItem({
    super.key,
    required this.value,
    required this.onChanged,
    required this.decreaseLabel,
    required this.increaseLabel,
    required this.valueLabel,
    this.min = 0,
    this.max = 99,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final int min;
  final int max;

  /// Accessible names of the buttons ("减少虚拟显示器", "增加虚拟显示器").
  final String decreaseLabel;
  final String increaseLabel;

  /// Accessible name of the number ("虚拟显示器数量").
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    Widget button(LgIcons icon, String label, int target, bool allowed) {
      final enabled = allowed && onChanged != null;
      return LgPressable(
        onPressed: enabled ? () => onChanged!(target) : null,
        semanticLabel: label,
        builder: (context, states) {
          final overlay = lgStateOverlay(c, states);
          return LgFocusRing(
            show: states.contains(WidgetState.focused),
            radius: BorderRadius.circular(LgRadius.r20),
            child: Opacity(
              opacity: enabled ? 1 : .6,
              child: Container(
                width: t.sizes.button,
                height: t.sizes.button,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: overlay,
                  border: Border.all(
                    color: enabled ? c.borderStrong : c.border,
                    width: 1.5,
                  ),
                ),
                child: LgIcon(icon, size: 20, color: enabled ? c.text : c.text2),
              ),
            ),
          );
        },
      );
    }

    return Container(
      height: t.sizes.row,
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(LgIcons.minus, decreaseLabel, value - 1, value > min),
          const SizedBox(width: LgSpace.s6),
          Semantics(
            label: valueLabel,
            value: '$value',
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: LgSpace.s7),
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: t.textN.copyWith(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: LgSpace.s6),
          button(LgIcons.plus, increaseLabel, value + 1, value < max),
        ],
      ),
    );
  }
}

/// One display of the remote computer on the map of [LgDisplayMap]: where it
/// sits (any unit; the real pixel rectangle will do), its number and its
/// accessible name ("显示器 2").
class LgDisplayTile {
  const LgDisplayTile({
    required this.rect,
    required this.label,
    required this.semanticLabel,
  });

  final Rect rect;
  final String label;
  final String semanticLabel;
}

/// How the remote displays are laid out (`.mp .lay`): numbered tiles in the
/// arrangement the remote computer has, scaled to fit; the one shown now is
/// tinted. A click picks one. Put it at the top of the display menu.
class LgDisplayMap extends StatelessWidget {
  const LgDisplayMap({
    super.key,
    required this.tiles,
    required this.current,
    required this.onSelect,
    this.caption,
    this.height = 132,
  });

  final List<LgDisplayTile> tiles;

  /// Index into [tiles] of the display being shown; null when all are.
  final int? current;
  final ValueChanged<int>? onSelect;

  /// Small line under the map ("当前：显示器 1").
  final String? caption;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LgSpace.s4,
        LgSpace.s2,
        LgSpace.s4,
        LgSpace.s3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: height,
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(LgRadius.r12),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                if (tiles.isEmpty) return const SizedBox.shrink();
                var bounds = tiles.first.rect;
                for (final tile in tiles.skip(1)) {
                  bounds = bounds.expandToInclude(tile.rect);
                }
                const pad = 12.0;
                final w = math.max(1.0, box.maxWidth - 2 * pad);
                final h = math.max(1.0, box.maxHeight - 2 * pad);
                final scale = math.min(
                  w / math.max(1, bounds.width),
                  h / math.max(1, bounds.height),
                );
                final ox = (box.maxWidth - bounds.width * scale) / 2;
                final oy = (box.maxHeight - bounds.height * scale) / 2;
                return Stack(
                  children: [
                    for (final (i, tile) in tiles.indexed)
                      Positioned(
                        left: ox + (tile.rect.left - bounds.left) * scale,
                        top: oy + (tile.rect.top - bounds.top) * scale,
                        width: math.max(28, tile.rect.width * scale),
                        height: math.max(24, tile.rect.height * scale),
                        child: _TileButton(
                          tile: tile,
                          selected: i == current,
                          onPressed: onSelect == null
                              ? null
                              : () => onSelect!(i),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: LgSpace.s2),
              child: Text(caption!, style: t.textS.copyWith(color: c.text2)),
            ),
        ],
      ),
    );
  }
}

class _TileButton extends StatelessWidget {
  const _TileButton({
    required this.tile,
    required this.selected,
    required this.onPressed,
  });

  final LgDisplayTile tile;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    const radius = BorderRadius.all(Radius.circular(LgRadius.r6));
    return LgPressable(
      onPressed: onPressed,
      semanticLabel: tile.semanticLabel,
      selected: selected,
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        final base = selected ? c.active : c.surface2;
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: overlay == null ? base : Color.alphaBlend(overlay, base),
              borderRadius: radius,
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? c.accent : c.borderStrong,
                width: selected ? 2 : 1.5,
              ),
            ),
            child: ExcludeSemantics(
              child: Text(
                tile.label,
                style: t.textN.copyWith(
                  color: selected ? c.accent : c.text2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A segmented choice inside a menu ("简洁 | 详细" under "界面模式", `.mr.sg`):
/// the control sits in line with the labels of the rows above.
class LgMenuSegmentedItem<T> extends StatelessWidget {
  const LgMenuSegmentedItem({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<LgSegment<T>> segments;
  final T selected;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LgSpace.s4 + 20 + LgSpace.s3,
        LgSpace.s1,
        LgSpace.s4,
        LgSpace.s2,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: LgSegmented<T>(
          segments: segments,
          selected: selected,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// A row that folds a list of rows open and shut ("调整显示的分类和顺序" with an
/// arrow at its end). The rows themselves are the caller's.
class LgMenuExpandRow extends StatelessWidget {
  const LgMenuExpandRow({
    super.key,
    required this.label,
    required this.expanded,
    required this.onToggle,
  });

  final String label;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      expanded: expanded,
      child: LgPressable(
        onPressed: onToggle,
        semanticLabel: label,
        builder: (context, states) => _Row(
          states: states,
          height: t.sizes.row,
          child: ExcludeSemantics(
            child: Row(
              children: [
                Expanded(child: LgEllipsisText(label)),
                const SizedBox(width: LgSpace.s3),
                LgIcon(
                  expanded ? LgIcons.chevU : LgIcons.chevD,
                  size: 20,
                  color: c.text2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The grip at the end of a row that can be dragged to another place. It only
/// draws; wrap it in the caller's drag listener.
class LgMenuGrip extends StatelessWidget {
  const LgMenuGrip({super.key});

  @override
  Widget build(BuildContext context) =>
      LgIcon(LgIcons.grip, size: 18, color: LgTokens.of(context).colors.text2);
}

/// Opens [items] as a menu at [globalPosition] (a right click on something
/// that is not a widget of its own, like a tab). It closes on a click outside,
/// on Esc and when an item is used.
void showLgMenuAt(
  BuildContext context, {
  required Offset globalPosition,
  required List<Widget> items,
  double width = kLgMenuWidth,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final box = overlay.context.findRenderObject()! as RenderBox;
  final local = box.globalToLocal(globalPosition);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _MenuAt(
      position: local,
      items: items,
      width: width,
      onClosed: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _MenuAt extends StatefulWidget {
  const _MenuAt({
    required this.position,
    required this.items,
    required this.width,
    required this.onClosed,
  });

  final Offset position;
  final List<Widget> items;
  final double width;
  final VoidCallback onClosed;

  @override
  State<_MenuAt> createState() => _MenuAtState();
}

class _MenuAtState extends State<_MenuAt> {
  final _controller = MenuController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.open(position: widget.position);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LgMenuAnchor(
        controller: _controller,
        items: widget.items,
        width: widget.width,
        onClose: widget.onClosed,
        builder: (context, controller) => const SizedBox.expand(),
      ),
    );
  }
}
