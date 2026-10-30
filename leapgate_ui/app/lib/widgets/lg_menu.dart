// Menus (`.menu`, `.mr`, `.mg` in A-基础.html): dropdown, context menu and
// submenus, built on Material's MenuAnchor for positioning, dismissal and
// keyboard navigation (arrows, Enter, Escape).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';
import 'lg_tooltip.dart';

/// Default menu width (`.menu{width:300px}`). Item labels that do not fit end
/// in "…" and show the full text on hover.
const double kLgMenuWidth = 300;

MenuStyle _panelStyle(LgColors c) {
  final light = c.shadow.length > 1;
  return MenuStyle(
    backgroundColor: WidgetStatePropertyAll(c.float),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    // The panel scrolls inside its Material, so the CSS shadow (light) is
    // approximated with an elevation; the dark theme's 1 px ring is a side.
    elevation: WidgetStatePropertyAll(light ? 8 : 0),
    shadowColor: WidgetStatePropertyAll(c.text),
    side: light ? null : WidgetStatePropertyAll(BorderSide(color: c.border)),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(LgRadius.r16)),
      ),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(vertical: LgSpace.s2),
    ),
    visualDensity: VisualDensity.standard,
  );
}

Widget _panelBody(double width, List<Widget> items) => SizedBox(
  width: width,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: items,
  ),
);

/// A menu opened from [builder]'s widget (dropdown). Call `controller.open()`
/// / `close()` from the trigger.
class LgMenuAnchor extends StatelessWidget {
  const LgMenuAnchor({
    super.key,
    required this.items,
    required this.builder,
    this.width = kLgMenuWidth,
    this.controller,
  });

  final List<Widget> items;
  final Widget Function(BuildContext context, MenuController controller)
  builder;
  final double width;
  final MenuController? controller;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return MenuAnchor(
      controller: controller,
      style: _panelStyle(c),
      clipBehavior: Clip.none,
      alignmentOffset: const Offset(0, LgSpace.s1),
      menuChildren: [_panelBody(width, items)],
      builder: (context, controller, _) => builder(context, controller),
    );
  }
}

/// Opens [items] at the pointer on right click.
class LgContextMenuRegion extends StatefulWidget {
  const LgContextMenuRegion({
    super.key,
    required this.items,
    required this.child,
    this.width = kLgMenuWidth,
  });

  final List<Widget> items;
  final Widget child;
  final double width;

  @override
  State<LgContextMenuRegion> createState() => _LgContextMenuRegionState();
}

class _LgContextMenuRegionState extends State<LgContextMenuRegion> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return MenuAnchor(
      controller: _controller,
      style: _panelStyle(c),
      clipBehavior: Clip.none,
      menuChildren: [_panelBody(widget.width, widget.items)],
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (d) => _controller.open(position: d.localPosition),
        child: widget.child,
      ),
    );
  }
}

/// A menu drawn in place, without an anchor (gallery, mockup comparison).
class LgMenuPanel extends StatelessWidget {
  const LgMenuPanel({
    super.key,
    required this.items,
    this.width = kLgMenuWidth,
  });

  final List<Widget> items;
  final double width;

  @override
  Widget build(BuildContext context) {
    final style = _panelStyle(LgTokens.of(context).colors);
    T r<T>(WidgetStateProperty<T?>? p) => p!.resolve(const {}) as T;
    return Material(
      color: r(style.backgroundColor),
      surfaceTintColor: Colors.transparent,
      elevation: r(style.elevation),
      shadowColor: r(style.shadowColor),
      shape: r(style.shape).copyWith(side: style.side?.resolve(const {})),
      child: Padding(
        padding: r(style.padding),
        child: _panelBody(width, items),
      ),
    );
  }
}

ButtonStyle _itemStyle(
  LgTokens t, {
  required bool danger,
  required bool bold,
  bool tall = false,
}) {
  final c = t.colors;
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((s) {
      if (s.contains(WidgetState.disabled)) return Colors.transparent;
      if (s.contains(WidgetState.hovered) ||
          s.contains(WidgetState.focused) ||
          s.contains(WidgetState.pressed)) {
        return danger ? c.errorBg : c.hover;
      }
      return Colors.transparent;
    }),
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled)
          ? c.text2
          : (danger ? c.error : c.text),
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    splashFactory: NoSplash.splashFactory,
    textStyle: WidgetStatePropertyAll(
      t.text.copyWith(fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
    ),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(
        horizontal: LgSpace.s4,
        vertical: tall ? LgSpace.s2 : 0,
      ),
    ),
    minimumSize: WidgetStatePropertyAll(Size(0, t.sizes.row)),
    // A row with a description grows with it (`.mr.two`).
    maximumSize: WidgetStatePropertyAll(
      Size(double.infinity, tall ? double.infinity : t.sizes.row),
    ),
    shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.basic),
    alignment: AlignmentDirectional.centerStart,
  );
}

WidgetStatesController? _forced(BuildContext context) {
  final states = LgStateOverride.of(context);
  return states.isEmpty ? null : WidgetStatesController(states);
}

/// The 20 px column in front of a label: a check mark or an icon (`.mr .ck`).
Widget? _lead(LgColors c, {LgIcons? icon, bool? checked}) {
  if (checked == true) return LgIcon(LgIcons.check, size: 20, color: c.accent);
  if (icon != null) return LgIcon(icon, size: 20, color: c.text2);
  if (checked == false) return const SizedBox(width: 20);
  return null;
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.label,
    this.description,
    this.lead,
    this.trailing,
    required this.disabled,
  });

  final String label;
  final String? description;
  final Widget? lead;
  final Widget? trailing;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final row = Row(
      crossAxisAlignment: description == null
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        if (lead != null) ...[
          // Top aligned with a description: keep the icon on the first line.
          description == null
              ? lead!
              : Padding(
                  padding: EdgeInsets.only(
                    top: math.max(0, (t.sizes.lh - 20) / 2),
                  ),
                  child: lead!,
                ),
          const SizedBox(width: LgSpace.s3),
        ],
        Expanded(
          child: description == null
              ? LgEllipsisText(label)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label),
                    Text(
                      description!,
                      style: t.textS.copyWith(
                        color: t.colors.text2,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
        ),
        if (trailing != null) ...[const SizedBox(width: LgSpace.s3), trailing!],
      ],
    );
    // `.mr.off`
    return disabled ? Opacity(opacity: .6, child: row) : row;
  }
}

/// A menu row.
///
/// [checked] reserves the check column: true draws the check mark and makes
/// the label bold (the current choice), false leaves the column empty so the
/// labels line up. [icon] takes the same column. [hint] is the small text at
/// the right end (`.mr .hint`). [danger] is the one destructive item of a menu
/// (`.mr.dng`): error colour, bold, red hover.
class LgMenuItem extends StatelessWidget {
  const LgMenuItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.checked,
    this.hint,
    this.description,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final LgIcons? icon;
  final bool? checked;
  final String? hint;

  /// Small text on a second line under the label (`.mr.two`).
  final String? description;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return MenuItemButton(
      onPressed: onPressed,
      statesController: _forced(context),
      // Inside a menu MenuAnchor already uses this; it matters for LgMenuPanel.
      overflowAxis: Axis.vertical,
      style: _itemStyle(
        t,
        danger: danger,
        bold: danger || checked == true,
        tall: description != null,
      ),
      child: _ItemRow(
        label: label,
        description: description,
        disabled: onPressed == null,
        lead: _lead(c, icon: icon, checked: checked),
        trailing: hint == null
            ? null
            : Text(
                hint!,
                style: t.textS.copyWith(
                  color: c.text2,
                  fontWeight: FontWeight.w400,
                ),
              ),
      ),
    );
  }
}

/// A row that opens a second-level menu on hover, click or Right arrow.
class LgSubmenu extends StatelessWidget {
  const LgSubmenu({
    super.key,
    required this.label,
    required this.items,
    this.icon,
    this.width = kLgMenuWidth,
  });

  final String label;
  final List<Widget> items;
  final LgIcons? icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return SubmenuButton(
      statesController: _forced(context),
      style: _itemStyle(t, danger: false, bold: false),
      menuStyle: _panelStyle(c),
      clipBehavior: Clip.none,
      submenuIcon: const WidgetStatePropertyAll(SizedBox.shrink()),
      // No children disables the button, so it cannot open an empty panel.
      menuChildren: items.isEmpty ? const [] : [_panelBody(width, items)],
      child: _ItemRow(
        label: label,
        disabled: items.isEmpty,
        lead: _lead(c, icon: icon),
        trailing: LgIcon(LgIcons.chevR, size: 20, color: c.text2),
      ),
    );
  }
}

/// Group title inside a menu (`.mg`).
class LgMenuGroup extends StatelessWidget {
  const LgMenuGroup(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Container(
      height: t.sizes.menuGroup,
      padding: EdgeInsets.fromLTRB(
        LgSpace.s4,
        t.sizes.menuGroup - 22,
        LgSpace.s4,
        0,
      ),
      child: Semantics(
        header: true,
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.textS.copyWith(
            color: t.colors.text2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
