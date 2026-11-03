// The floating toolbar of a session (01 §3.2 block B; `.tb`, `.ti` in
// A-基础.html and `s-*`, `m-*`, `min-*`, `x-full` in A-P2.html): a pill with a
// pin, the menu buttons, the connection method and "disconnect", and at its
// end the grip, the full-screen and fold buttons. Folded it shrinks to a bar
// that hangs from the edge of the picture and keeps a dot for the connection
// method. On the left and right edges it runs up and down with icons only;
// what does not fit goes into a "更多" menu.
//
// Which buttons there are, what their menus hold and when they are disabled is
// the caller's. Where the bar sits is told by `dock`; moving it with the grip is
// `LgToolbarPlacer` (lg_toolbar_dock.dart), snapping and remembering the place
// are the caller's.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/identity_color.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_menu.dart';
import 'lg_pressable.dart';
import 'lg_status.dart';
import 'lg_toolbar_dock.dart';
import 'lg_toolbar_fold.dart';
import 'lg_tooltip.dart';

export 'lg_toolbar_dock.dart';
export 'lg_toolbar_fold.dart' show LgToolbarFoldable;

/// Accessible names and tooltips of what the bar itself holds.
class LgToolbarLabels {
  const LgToolbarLabels({
    required this.toolbar,
    required this.pin,
    required this.fullscreen,
    required this.exitFullscreen,
    required this.minimize,
    required this.collapse,
    required this.expand,
    this.drag,
    this.more,
  });

  /// The bar as a whole ("会话工具栏").
  final String toolbar;

  /// Pin: the bar stays open.
  final String pin;
  final String fullscreen;
  final String exitFullscreen;
  final String minimize;

  /// Fold the bar up / unfold it.
  final String collapse;
  final String expand;

  /// The grip that moves the bar ("移动工具栏"); it shows inside an
  /// [LgToolbarPlacer] only.
  final String? drag;

  /// The "更多" button that holds what does not fit.
  final String? more;
}

/// An icon button or an icon with its text in the bar (`.ti`). With [showText]
/// the label is written next to the icon (detail mode of the menu buttons, a
/// count such as "2/3"); otherwise it is the tooltip and the accessible name.
/// [semanticLabel] names it for a screen reader when the written text is not a
/// name ("2/3" is "切换显示器，当前第 2 个，共 3 个").
///
/// [toggled] makes it a switch: the value is shown by the tinted ground and
/// the accent colour, and told to a screen reader. [danger] is the one
/// destructive button (disconnect), [dim] the quiet buttons at the end.
class LgToolbarButton extends StatelessWidget {
  const LgToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.showText = false,
    this.toggled,
    this.danger = false,
    this.dim = false,
    this.semanticLabel,
  });

  final LgIcons icon;
  final String label;
  final VoidCallback? onPressed;
  final bool showText;
  final bool? toggled;
  final bool danger;
  final bool dim;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final on = toggled == true;
    final button = LgPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel ?? label,
      toggled: toggled,
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        final base = on ? c.active : null;
        final fg = on
            ? c.accent
            : danger
            ? c.error
            : dim
            ? c.text2
            : c.text;
        final radius = BorderRadius.circular(LgRadius.r12);
        return Opacity(
          opacity: states.contains(WidgetState.disabled) ? .45 : 1,
          child: LgFocusRing(
            show: states.contains(WidgetState.focused),
            radius: radius,
            child: Container(
              height: t.sizes.tool,
              constraints: BoxConstraints(minWidth: t.sizes.tool),
              padding: showText
                  ? EdgeInsets.symmetric(horizontal: t.sizes.toolPad)
                  : null,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: overlay == null
                    ? base
                    : Color.alphaBlend(overlay, base ?? Colors.transparent),
                borderRadius: radius,
              ),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LgIcon(icon, size: t.sizes.icon, color: fg),
                    if (showText) ...[
                      SizedBox(width: t.sizes.toolGap),
                      Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        style: t.text.copyWith(
                          color: fg,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    return showText ? button : LgTooltip(message: label, child: button);
  }
}

/// A button with only a short text, no icon: the number of a display in the
/// flat display buttons (`.ti.num`). [selected] marks the display shown now.
class LgToolbarTextButton extends StatelessWidget {
  const LgToolbarTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.semanticLabel,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Its name for a screen reader ("显示器 2").
  final String semanticLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r12);
    return LgTooltip(
      message: semanticLabel,
      child: LgPressable(
        onPressed: onPressed,
        semanticLabel: semanticLabel,
        selected: selected,
        builder: (context, states) {
          final overlay = selected ? null : lgStateOverlay(c, states);
          return Opacity(
            opacity: states.contains(WidgetState.disabled) ? .45 : 1,
            child: LgFocusRing(
              show: states.contains(WidgetState.focused),
              radius: radius,
              child: Container(
                height: t.sizes.tool,
                constraints: BoxConstraints(minWidth: t.sizes.tool),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? c.active : overlay,
                  borderRadius: radius,
                ),
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: t.text.copyWith(
                      color: selected ? c.accent : c.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// How a menu button shows a call that is not an ordinary menu: waiting for the
/// other side to pick up (a turning mark, the connecting colour) and in the
/// call (a phone, the online colour). The label says it in words.
enum LgToolbarMenuState { normal, pending, live }

/// Where the menu of a button of this bar opens: under it, over it for a bar at
/// the bottom, beside it for a bar on a side.
Offset? _menuPosition(LgToolbarDock dock, Size button, double menuWidth) =>
    switch (dock) {
      LgToolbarDock.top || LgToolbarDock.bottom => null,
      LgToolbarDock.left => Offset(button.width + LgSpace.s2, 0),
      LgToolbarDock.right => Offset(-menuWidth - LgSpace.s2, 0),
    };

/// Sent up the tree when a menu of the bar has closed. The menu took the
/// keyboard on opening; the session page gives it back to the image if the
/// pointer is on it, since no "pointer entered" comes then.
class LgToolbarMenuClosed extends Notification {
  const LgToolbarMenuClosed();
}

void _menuClosed(BuildContext context) {
  if (context.mounted) const LgToolbarMenuClosed().dispatch(context);
}

/// A menu button of the bar (`.ti` with a down arrow): the name, and in detail
/// mode the [icon] before it. Open, it is tinted and bold, like a selected
/// button, while its [items] hang under it. On a bar at a side it is the icon
/// alone and the menu opens beside it. [badge] is a count after the name (unread
/// messages); [state] is a call in progress.
class LgToolbarMenuButton extends StatelessWidget {
  const LgToolbarMenuButton({
    super.key,
    required this.label,
    required this.items,
    this.icon,
    this.width = kLgMenuWidth,
    this.enabled = true,
    this.disabledNote,
    this.badge = 0,
    this.state = LgToolbarMenuState.normal,
  });

  final String label;
  final List<Widget> items;

  /// Shown before the name in detail mode, and alone on a bar at a side (01
  /// §2.3).
  final LgIcons? icon;
  final double width;

  /// False greys the button. Without [disabledNote] it also does not open; with
  /// one it still opens, so that the greyed rows inside show what there is
  /// (`x-no-perm`: no keyboard and mouse permission), and the note shows on
  /// hover and to a screen reader.
  final bool enabled;
  final String? disabledNote;

  /// The count of unread messages: after the name, or on the corner of the icon
  /// when the bar is at a side.
  final int badge;
  final LgToolbarMenuState state;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final dock = LgToolbarScope.of(context);
    final vertical = dock.vertical;
    final greyed = !enabled;
    final explained = greyed && disabledNote != null;
    final button = LgMenuAnchor(
      items: items,
      width: width,
      triggerFocus: true,
      onClose: () => _menuClosed(context),
      builder: (context, controller) => LgPressable(
        onPressed: greyed && !explained
            ? null
            : () {
                if (controller.isOpen) {
                  controller.close();
                  return;
                }
                final size = (context.findRenderObject()! as RenderBox).size;
                final at = _menuPosition(dock, size, width);
                at == null ? controller.open() : controller.open(position: at);
                final focus = Focus.of(context);
                if (!focus.hasFocus) focus.requestFocus();
              },
        semanticLabel: label,
        toggled: controller.isOpen,
        builder: (context, states) {
          // The gallery shows an open menu with the selected state forced.
          final open =
              controller.isOpen || states.contains(WidgetState.selected);
          final overlay = open ? null : lgStateOverlay(c, states);
          final base = open ? c.active : null;
          final fg = switch (state) {
            _ when open => c.accent,
            LgToolbarMenuState.pending => c.connecting,
            LgToolbarMenuState.live => c.online,
            LgToolbarMenuState.normal => c.text,
          };
          final bold = open || state != LgToolbarMenuState.normal;
          final radius = BorderRadius.circular(LgRadius.r12);
          final lead = switch (state) {
            LgToolbarMenuState.pending => LgSpinner(
              icon: LgIcons.spinner,
              size: t.sizes.icon,
              color: fg,
            ),
            LgToolbarMenuState.live => LgIcon(
              LgIcons.call,
              size: t.sizes.icon,
              color: fg,
            ),
            LgToolbarMenuState.normal =>
              (t.detail || vertical) && icon != null
                  ? LgIcon(icon!, size: t.sizes.icon, color: fg)
                  : null,
          };
          return Opacity(
            opacity: greyed || states.contains(WidgetState.disabled) ? .6 : 1,
            child: LgFocusRing(
              show: states.contains(WidgetState.focused),
              radius: radius,
              child: Container(
                height: t.sizes.tool,
                constraints: vertical
                    ? BoxConstraints(minWidth: t.sizes.tool)
                    : null,
                padding: vertical
                    ? null
                    : EdgeInsets.symmetric(horizontal: t.sizes.toolPad),
                alignment: vertical ? Alignment.center : null,
                decoration: BoxDecoration(
                  color: overlay == null
                      ? base
                      : Color.alphaBlend(overlay, Colors.transparent),
                  borderRadius: radius,
                ),
                child: ExcludeSemantics(
                  child: Stack(
                    alignment: AlignmentDirectional.centerStart,
                    clipBehavior: Clip.none,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (lead != null) ...[
                            lead,
                            if (!vertical) SizedBox(width: t.sizes.toolGap),
                          ],
                          if (!vertical) ...[
                            Text(
                              label,
                              maxLines: 1,
                              softWrap: false,
                              style: t.text.copyWith(
                                color: fg,
                                fontWeight: bold
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                            if (badge > 0) ...[
                              SizedBox(width: t.sizes.toolGap),
                              LgBadge(badge),
                            ],
                            SizedBox(width: t.sizes.toolGap),
                            LgIcon(LgIcons.chevD, size: 16, color: fg),
                          ] else if (lead == null)
                            LgIcon(
                              LgIcons.chevD,
                              size: t.sizes.icon,
                              color: fg,
                            ),
                        ],
                      ),
                      // On a bar at a side there is no room after the name: the
                      // count sits on the corner of the icon.
                      if (vertical && badge > 0)
                        Positioned(top: -8, right: -12, child: LgBadge(badge)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    if (!explained) return button;
    return LgTooltip(
      message: disabledNote!,
      child: Semantics(hint: disabledNote, child: button),
    );
  }
}

/// The "更多" button: the three dots and, if what is folded into it has unread
/// messages, their number (`.ti.more`).
class _MoreButton extends StatelessWidget {
  const _MoreButton({
    required this.label,
    required this.items,
    required this.badge,
  });

  final String label;
  final List<Widget> items;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final dock = LgToolbarScope.of(context);
    return LgMenuAnchor(
      items: items,
      triggerFocus: true,
      onClose: () => _menuClosed(context),
      builder: (context, controller) => LgPressable(
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
            return;
          }
          final size = (context.findRenderObject()! as RenderBox).size;
          final at = _menuPosition(dock, size, kLgMenuWidth);
          at == null ? controller.open() : controller.open(position: at);
          final focus = Focus.of(context);
          if (!focus.hasFocus) focus.requestFocus();
        },
        semanticLabel: label,
        toggled: controller.isOpen,
        builder: (context, states) {
          final open =
              controller.isOpen || states.contains(WidgetState.selected);
          final radius = BorderRadius.circular(LgRadius.r12);
          return LgFocusRing(
            show: states.contains(WidgetState.focused),
            radius: radius,
            child: Container(
              height: t.sizes.tool,
              constraints: BoxConstraints(minWidth: t.sizes.tool),
              padding: EdgeInsets.symmetric(horizontal: t.sizes.toolGap + 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: open ? c.active : lgStateOverlay(c, states),
                borderRadius: radius,
              ),
              child: ExcludeSemantics(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LgIcon(
                          LgIcons.more,
                          size: t.sizes.icon,
                          color: open ? c.accent : c.text,
                        ),
                        if (badge > 0 && !dock.vertical) ...[
                          SizedBox(width: t.sizes.toolGap),
                          LgBadge(badge),
                        ],
                      ],
                    ),
                    if (badge > 0 && dock.vertical)
                      Positioned(top: -8, right: -12, child: LgBadge(badge)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The connection method as a button of the bar (`.ti` with the mark and a
/// down arrow): the details open from it. With [open] it is tinted. On a bar at
/// a side only the mark shows.
class LgToolbarRouteButton extends StatelessWidget {
  const LgToolbarRouteButton({
    super.key,
    required this.route,
    required this.label,
    required this.onPressed,
    this.open = false,
    this.encrypted = true,
    this.unencryptedLabel,
  }) : assert(encrypted || unencryptedLabel != null);

  final LgRoute route;

  /// "直连" / "经中继".
  final String label;
  final VoidCallback? onPressed;
  final bool open;
  final bool encrypted;
  final String? unencryptedLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final vertical = LgToolbarScope.of(context).vertical;
    final name = encrypted ? label : '$label, $unencryptedLabel';
    final radius = BorderRadius.circular(LgRadius.r12);
    final button = LgPressable(
      onPressed: onPressed,
      semanticLabel: name,
      toggled: open,
      builder: (context, states) {
        final on = open || states.contains(WidgetState.selected);
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            height: t.sizes.tool,
            constraints: BoxConstraints(minWidth: t.sizes.tool),
            padding: vertical
                ? null
                : EdgeInsets.symmetric(horizontal: t.sizes.toolPad),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? c.active : lgStateOverlay(c, states),
              borderRadius: radius,
            ),
            child: ExcludeSemantics(
              child: vertical
                  ? LgToolbarRouteDot(
                      route: route,
                      label: label,
                      encrypted: encrypted,
                      unencryptedLabel: unencryptedLabel,
                      plain: true,
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DefaultTextStyle(
                          style: t.textM,
                          child: LgRouteMark(
                            route: route,
                            label: label,
                            encrypted: encrypted,
                            unencryptedLabel: unencryptedLabel,
                          ),
                        ),
                        SizedBox(width: t.sizes.toolGap),
                        LgIcon(
                          LgIcons.chevD,
                          size: 16,
                          color: on ? c.accent : c.text,
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
    return vertical ? LgTooltip(message: name, child: button) : button;
  }
}

/// A read-only part of the bar: the connection method mark (`.ti` holding an
/// [LgRouteMark]), for a bar whose connection method has no details to open.
class LgToolbarStatus extends StatelessWidget {
  const LgToolbarStatus({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Container(
      height: t.sizes.tool,
      padding: EdgeInsets.symmetric(horizontal: t.sizes.toolPad),
      alignment: Alignment.center,
      child: DefaultTextStyle(style: t.textM, child: child),
    );
  }
}

/// The mark of the connection method without its word: filled for a direct
/// connection, half filled (a diamond in detail mode) for a relayed one, and a
/// triangle after it when the connection is not encrypted. It is the dot of
/// the folded bar and the route button of a bar at a side. Until the route is
/// known there is no mark (only the triangle, if the connection turns out
/// unencrypted). Named for a screen reader and by a tooltip, unless [plain].
class LgToolbarRouteDot extends StatelessWidget {
  const LgToolbarRouteDot({
    super.key,
    required this.route,
    required this.label,
    this.encrypted = true,
    this.unencryptedLabel,
    this.plain = false,
  }) : assert(encrypted || unencryptedLabel != null);

  final LgRoute? route;
  final String label;
  final bool encrypted;
  final String? unencryptedLabel;

  /// Only the mark, no name and no tooltip: it sits inside a button that
  /// has them.
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final route = this.route;
    if (route == null && encrypted) return const SizedBox.shrink();
    final direct = route == LgRoute.direct;
    final color = direct ? c.direct : c.relay;
    final mark = direct
        ? LgIcons.markDot
        : (t.detail ? LgIcons.markDia : LgIcons.markHalf);
    final text = route == null
        ? unencryptedLabel!
        : encrypted
        ? label
        : '$label, $unencryptedLabel';
    final glyph = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (route != null) LgIcon(mark, size: 12, color: color),
        if (!encrypted) ...[
          if (route != null) const SizedBox(width: LgSpace.s1),
          LgIcon(LgIcons.markTri, size: 12, color: c.unencrypted),
        ],
      ],
    );
    if (plain) return glyph;
    return LgTooltip(
      message: text,
      child: Semantics(
        label: text,
        child: ExcludeSemantics(
          child: Container(
            height: t.sizes.tool,
            padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
            alignment: Alignment.center,
            child: glyph,
          ),
        ),
      ),
    );
  }
}

/// The device name at the start of the bar in full screen, with the identity
/// colour as a strip along its top edge (`.ti.nm2`).
class _DeviceName extends StatelessWidget {
  const _DeviceName({required this.name, required this.id});

  final String name;
  final String id;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final identity = c.identity[identityGroup(id.replaceAll(' ', ''))];
    return Semantics(
      label: name,
      child: ExcludeSemantics(
        child: Container(
          height: t.sizes.tool,
          constraints: const BoxConstraints(maxWidth: 200),
          padding: EdgeInsets.symmetric(horizontal: t.sizes.toolPad),
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned(
                // As wide as the name, like the mockup's `left/right: 12px`.
                left: 12 - t.sizes.toolPad,
                right: 12 - t.sizes.toolPad,
                top: -(t.sizes.tool - t.sizes.lh) / 2,
                height: LgFixed.strip,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: identity.solid,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(3),
                    ),
                  ),
                ),
              ),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.text.copyWith(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The line between two groups of a bar at a side (`.vsep`).
class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: LgSpace.s2,
          horizontal: LgSpace.s2,
        ),
        child: SizedBox(
          width: 24,
          height: 1,
          child: ColoredBox(color: c.border),
        ),
      ),
    );
  }
}

/// The toolbar. Put it where the picture's edge is (inside an
/// `LgToolbarPlacer`, or `Align(topCenter)` when it cannot be moved); the
/// distance from the edge it hangs on (12 px open, none folded) is part of it.
class LgSessionToolbar extends StatefulWidget {
  const LgSessionToolbar({
    super.key,
    required this.labels,
    required this.groups,
    required this.pinned,
    required this.onTogglePin,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.fullscreen,
    required this.onToggleFullscreen,
    this.dock = LgToolbarDock.top,
    this.route,
    this.routeLabel,
    this.encrypted = true,
    this.unencryptedLabel,
    this.collapsedActions = const [],
    this.deviceName,
    this.deviceId,
    this.onMinimize,
    this.noteSide,
  }) : assert(route == null || routeLabel != null),
       assert(encrypted || unencryptedLabel != null);

  final LgToolbarLabels labels;

  /// The buttons between the pin and the end buttons, left to right, in
  /// groups (view switch; menus; recording and connection method; disconnect).
  /// Groups are 12 px apart, the buttons of a group 2 px. Wrap the ones that
  /// may go into "更多" in `LgToolbarFoldable`, in the order they should fold
  /// from the end.
  final List<List<Widget>> groups;

  /// Whether the bar stays open while the pointer is in the picture.
  final bool pinned;
  final VoidCallback onTogglePin;

  /// Folded: only the grip, the connection dot, [collapsedActions], the
  /// full-screen button and the unfold button remain.
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;

  /// The edge the bar hangs on.
  final LgToolbarDock dock;

  /// Direct or relayed, for the dot of the folded bar; null while the route is
  /// not known yet (the dot is left out).
  final LgRoute? route;
  final String? routeLabel;
  final bool encrypted;
  final String? unencryptedLabel;

  /// What stays in the folded bar between the dot and the end buttons: the
  /// button that switches to the next display ("2/3").
  final List<Widget> collapsedActions;

  /// Shown first in the bar in full screen, where the title bar is gone
  /// (01 §2.1). [deviceId] gives its identity colour.
  final String? deviceName;
  final String? deviceId;

  /// "Minimize" at the end of the bar, shown in full screen only.
  final VoidCallback? onMinimize;

  /// The side of a menu on which the note of a greyed row opens. Null: the
  /// right, or the left for a bar on the right edge. Give [LgNoteSide.left]
  /// when a notice sits at the right of the picture, so that a note does not
  /// cover it (`x-revoked`).
  final LgNoteSide? noteSide;

  @override
  State<LgSessionToolbar> createState() => _LgSessionToolbarState();
}

class _LgSessionToolbarState extends State<LgSessionToolbar> {
  /// How many foldable buttons the row has put into "更多", told after layout.
  final _folded = ValueNotifier<int>(0);

  @override
  void didUpdateWidget(LgSessionToolbar old) {
    super.didUpdateWidget(old);
    if (old.collapsed != widget.collapsed || old.dock != widget.dock) {
      _folded.value = 0;
    }
  }

  @override
  void dispose() {
    _folded.dispose();
    super.dispose();
  }

  LgIcons _collapseIcon(LgToolbarDock dock, {required bool expand}) {
    final toward = switch (dock) {
      LgToolbarDock.top => LgIcons.chevU,
      LgToolbarDock.bottom => LgIcons.chevD,
      LgToolbarDock.left => LgIcons.chevL,
      LgToolbarDock.right => LgIcons.chevR,
    };
    if (!expand) return toward;
    return switch (toward) {
      LgIcons.chevU => LgIcons.chevD,
      LgIcons.chevD => LgIcons.chevU,
      LgIcons.chevL => LgIcons.chevR,
      _ => LgIcons.chevL,
    };
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => _build(
      context,
      widget.dock.vertical ? box.maxHeight : box.maxWidth,
    ),
  );

  Widget _build(BuildContext context, double extent) {
    final w = widget;
    final t = LgTokens.of(context);
    final c = t.colors;
    final dock = w.dock;
    final vertical = dock.vertical;
    final drag = LgToolbarDragScope.maybeOf(context);
    final lifted = drag?.dragging ?? false;
    assert(
      w.groups.every(
            (g) => g.every((item) => item is! LgToolbarFoldable),
          ) ||
          (w.labels.more != null && w.labels.drag != null),
      'A bar with foldable buttons needs labels.more (the "更多" button) and '
      'labels.drag (the grip): without them both would be named after the bar.',
    );

    final minimize = w.fullscreen && w.onMinimize != null
        ? LgToolbarButton(
            icon: LgIcons.minus,
            label: w.labels.minimize,
            dim: true,
            onPressed: w.onMinimize,
          )
        : null;
    final fullscreenButton = LgToolbarButton(
      icon: w.fullscreen ? LgIcons.fullscreenExit : LgIcons.fullscreen,
      label: w.fullscreen ? w.labels.exitFullscreen : w.labels.fullscreen,
      dim: true,
      onPressed: w.onToggleFullscreen,
    );
    final grip = drag == null
        ? null
        : LgToolbarGrip(label: w.labels.drag ?? w.labels.toolbar);

    final Widget bar;
    if (w.collapsed) {
      final dot = LgToolbarRouteDot(
        route: w.route,
        label: w.routeLabel ?? '',
        encrypted: w.encrypted,
        unencryptedLabel: w.unencryptedLabel,
      );
      final showDot = w.route != null || !w.encrypted;
      final items = <Widget>[
        ?grip,
        if (showDot) dot,
        ...w.collapsedActions,
        ?minimize,
        fullscreenButton,
        LgToolbarButton(
          icon: _collapseIcon(dock, expand: true),
          label: w.labels.expand,
          dim: true,
          onPressed: w.onToggleCollapsed,
        ),
      ];
      final hang = switch (dock) {
        LgToolbarDock.top => const BorderRadius.vertical(
          bottom: Radius.circular(LgRadius.r16),
        ),
        LgToolbarDock.bottom => const BorderRadius.vertical(
          top: Radius.circular(LgRadius.r16),
        ),
        LgToolbarDock.left => const BorderRadius.horizontal(
          right: Radius.circular(LgRadius.r16),
        ),
        LgToolbarDock.right => const BorderRadius.horizontal(
          left: Radius.circular(LgRadius.r16),
        ),
      };
      bar = Container(
        padding: vertical
            ? const EdgeInsets.symmetric(
                horizontal: LgSpace.s1,
                vertical: LgSpace.s2,
              )
            : const EdgeInsets.symmetric(
                horizontal: LgSpace.s2,
                vertical: LgSpace.s1,
              ),
        decoration: BoxDecoration(
          color: c.float,
          borderRadius: hang,
          boxShadow: [
            ...c.shadow,
            if (lifted) BoxShadow(color: c.accent, spreadRadius: 2),
          ],
        ),
        child: Flex(
          direction: vertical ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, item) in items.indexed) ...[
              if (i > 0) const SizedBox(width: 2, height: 2),
              item,
            ],
          ],
        ),
      );
    } else {
      final lead = <Widget>[
        if (w.fullscreen && w.deviceName != null && !vertical)
          _DeviceName(name: w.deviceName!, id: w.deviceId ?? w.deviceName!),
        LgToolbarButton(
          icon: LgIcons.pin,
          label: w.labels.pin,
          toggled: w.pinned,
          onPressed: w.onTogglePin,
        ),
      ];
      final rows = <List<Widget>>[
        if (w.groups.isEmpty) lead else [...lead, ...w.groups.first],
        ...w.groups.skip(1),
        [
          ?minimize,
          ?grip,
          fullscreenButton,
          LgToolbarButton(
            icon: _collapseIcon(dock, expand: false),
            label: w.labels.collapse,
            dim: true,
            onPressed: w.onToggleCollapsed,
          ),
        ],
      ];
      final slots = <LgFoldSlot>[];
      final foldables = <LgToolbarFoldable>[];
      for (final (g, group) in rows.indexed) {
        if (g > 0 && vertical) {
          slots.add(const LgFoldSlot(_Separator()));
        }
        for (final (i, item) in group.indexed) {
          final gap = i > 0
              ? 2.0
              : (g > 0 && !vertical ? LgSpace.s3 : 0.0);
          if (item is LgToolbarFoldable) {
            // A folded button stays out of the Tab order too.
            final index = foldables.length;
            foldables.add(item);
            slots.add(
              LgFoldSlot(
                ValueListenableBuilder<int>(
                  valueListenable: _folded,
                  builder: (context, k, child) => ExcludeFocus(
                    excluding: index >= foldables.length - k,
                    child: child!,
                  ),
                  child: item,
                ),
                gap: gap,
                foldable: true,
              ),
            );
          } else {
            slots.add(LgFoldSlot(item, gap: gap));
          }
        }
      }
      // What the bar's own padding takes along its axis. The 12 px of the edge
      // lie across the axis, and the distance from the ends of the edge is
      // already out of [extent] (the placer pads it).
      final room = extent - (vertical ? 2 * LgSpace.s2 : 12.0);
      bar = _Pill(
        vertical: vertical,
        dock: dock,
        lifted: lifted,
        child: ValueListenableBuilder<int>(
          valueListenable: _folded,
          // The row compares what it lays out with the count held here, so a
          // reset of the count (a new edge) is answered even when the row would
          // fold the same number as before.
          builder: (context, count, more) => LgFoldRow(
            axis: vertical ? Axis.vertical : Axis.horizontal,
            maxExtent: room,
            slots: slots,
            folded: count,
            onFolded: (k) => _folded.value = k,
            more: more!,
          ),
          child: ValueListenableBuilder<int>(
            valueListenable: _folded,
            builder: (context, k, _) {
              final folded = k == 0
                  ? const <LgToolbarFoldable>[]
                  : foldables.sublist(
                      (foldables.length - k).clamp(0, foldables.length),
                    );
              return ExcludeFocus(
                excluding: k == 0,
                child: _MoreButton(
                  label: w.labels.more ?? w.labels.toolbar,
                  items: [for (final f in folded) f.menuItem],
                  badge: folded.fold(0, (sum, f) => sum + f.badge),
                ),
              );
            },
          ),
        ),
      );
    }
    return LgToolbarScope(
      dock: dock,
      child: LgNoteSideScope(
        // A menu of a bar on the right edge opens to the left, so its notes
        // would land on the bar if they opened to the right.
        side:
            w.noteSide ??
            (dock == LgToolbarDock.right ? LgNoteSide.left : LgNoteSide.right),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: w.labels.toolbar,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: w.collapsed ? bar : _Edge(dock: dock, child: bar),
          ),
        ),
      ),
    );
  }
}

/// The 12 px between the open bar and the edge it hangs on.
class _Edge extends StatelessWidget {
  const _Edge({required this.dock, required this.child});

  final LgToolbarDock dock;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: switch (dock) {
      LgToolbarDock.top => const EdgeInsets.only(top: LgSpace.s3),
      LgToolbarDock.bottom => const EdgeInsets.only(bottom: LgSpace.s3),
      LgToolbarDock.left => const EdgeInsets.only(left: LgSpace.s3),
      LgToolbarDock.right => const EdgeInsets.only(right: LgSpace.s3),
    },
    child: child,
  );
}

/// The pill of the open bar (`.tb`): float ground, shadow, 16 px corners. Lifted
/// (while it is dragged) it gets the accent ring (`.tb.drag`).
class _Pill extends StatelessWidget {
  const _Pill({
    required this.vertical,
    required this.dock,
    required this.lifted,
    required this.child,
  });

  final bool vertical;
  final LgToolbarDock dock;
  final bool lifted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Container(
      height: vertical ? null : t.sizes.bar,
      width: vertical ? t.sizes.tool + 2 * LgSpace.s1 : null,
      padding: vertical
          ? const EdgeInsets.symmetric(
              horizontal: LgSpace.s1,
              vertical: LgSpace.s2,
            )
          : const EdgeInsets.symmetric(horizontal: 6, vertical: LgSpace.s1),
      decoration: BoxDecoration(
        color: c.float,
        borderRadius: BorderRadius.circular(LgRadius.r16),
        boxShadow: [
          ...c.shadow,
          if (lifted) BoxShadow(color: c.accent, spreadRadius: 2),
        ],
      ),
      child: child,
    );
  }
}
