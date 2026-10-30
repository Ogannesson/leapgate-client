// The floating toolbar of a session (01 §3.2 block B; `.tb`, `.ti` in
// A-基础.html and `s-*`, `x-full` in A-P2.html): a pill with a pin, the menu
// buttons, the connection method and "disconnect", and at its end the
// full-screen and fold buttons. Folded it shrinks to a bar that hangs from the
// top edge of the picture and keeps a dot for the connection method.
//
// Moving the bar along the edge and docking it are not here yet (M2b), so the
// drag handle of the mockups is left out. Which buttons there are, what their
// menus hold and when they are disabled is the caller's.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/identity_color.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_menu.dart';
import 'lg_pressable.dart';
import 'lg_status.dart';
import 'lg_tooltip.dart';

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
}

/// An icon button or an icon with its text in the bar (`.ti`). With [showText]
/// the label is written next to the icon (detail mode of the menu buttons, a
/// count such as "2/3"); otherwise it is the tooltip and the accessible name.
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
  });

  final LgIcons icon;
  final String label;
  final VoidCallback? onPressed;
  final bool showText;
  final bool? toggled;
  final bool danger;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final on = toggled == true;
    final button = LgPressable(
      onPressed: onPressed,
      semanticLabel: label,
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

/// A menu button of the bar (`.ti` with a down arrow): the name, and in detail
/// mode the [icon] before it. Open, it is tinted and bold, like a selected
/// button, while its [items] hang under it.
class LgToolbarMenuButton extends StatelessWidget {
  const LgToolbarMenuButton({
    super.key,
    required this.label,
    required this.items,
    this.icon,
    this.width = kLgMenuWidth,
    this.enabled = true,
  });

  final String label;
  final List<Widget> items;

  /// Shown before the name in detail mode only (01 §2.3).
  final LgIcons? icon;
  final double width;

  /// False greys the whole menu (no permission for it).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return LgMenuAnchor(
      items: items,
      width: width,
      builder: (context, controller) => LgPressable(
        onPressed: !enabled
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
        semanticLabel: label,
        toggled: controller.isOpen,
        builder: (context, states) {
          // The gallery shows an open menu with the selected state forced.
          final open =
              controller.isOpen || states.contains(WidgetState.selected);
          final overlay = open ? null : lgStateOverlay(c, states);
          final base = open ? c.active : null;
          final fg = open ? c.accent : c.text;
          final radius = BorderRadius.circular(LgRadius.r12);
          return Opacity(
            opacity: states.contains(WidgetState.disabled) ? .6 : 1,
            child: LgFocusRing(
              show: states.contains(WidgetState.focused),
              radius: radius,
              child: Container(
                height: t.sizes.tool,
                padding: EdgeInsets.symmetric(horizontal: t.sizes.toolPad),
                decoration: BoxDecoration(
                  color: overlay == null
                      ? base
                      : Color.alphaBlend(overlay, Colors.transparent),
                  borderRadius: radius,
                ),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (t.detail && icon != null) ...[
                        LgIcon(icon!, size: t.sizes.icon, color: fg),
                        SizedBox(width: t.sizes.toolGap),
                      ],
                      Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        style: t.text.copyWith(
                          color: fg,
                          fontWeight: open ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      SizedBox(width: t.sizes.toolGap),
                      LgIcon(LgIcons.chevD, size: 16, color: fg),
                    ],
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

/// A read-only part of the bar: the connection method mark (`.ti` holding an
/// [LgRouteMark]). It is not a button until the details of M2b.
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

class _Group extends StatelessWidget {
  const _Group(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, child) in children.indexed) ...[
        if (i > 0) const SizedBox(width: 2),
        child,
      ],
    ],
  );
}

/// The toolbar. Put it at the top centre of the picture (`Align(topCenter)`);
/// the distance from the top edge (12 px open, none folded) is part of it.
class LgSessionToolbar extends StatelessWidget {
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
    required this.route,
    required this.routeLabel,
    this.encrypted = true,
    this.unencryptedLabel,
    this.deviceName,
    this.deviceId,
    this.onMinimize,
  }) : assert(encrypted || unencryptedLabel != null);

  final LgToolbarLabels labels;

  /// The buttons between the pin and the end buttons, left to right, in
  /// groups (view switch; menus; recording and connection method; disconnect).
  /// Groups are 12 px apart, the buttons of a group 2 px.
  final List<List<Widget>> groups;

  /// Whether the bar stays open while the pointer is in the picture.
  final bool pinned;
  final VoidCallback onTogglePin;

  /// Folded: only the connection dot, the full-screen button and the unfold
  /// button remain.
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;

  /// Direct or relayed, for the dot of the folded bar.
  final LgRoute route;
  final String routeLabel;
  final bool encrypted;
  final String? unencryptedLabel;

  /// Shown first in the bar in full screen, where the title bar is gone
  /// (01 §2.1). [deviceId] gives its identity colour.
  final String? deviceName;
  final String? deviceId;

  /// "Minimize" at the end of the bar, shown in full screen only.
  final VoidCallback? onMinimize;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final minimize = fullscreen && onMinimize != null
        ? LgToolbarButton(
            icon: LgIcons.minus,
            label: labels.minimize,
            dim: true,
            onPressed: onMinimize,
          )
        : null;
    final fullscreenButton = LgToolbarButton(
      icon: fullscreen ? LgIcons.fullscreenExit : LgIcons.fullscreen,
      label: fullscreen ? labels.exitFullscreen : labels.fullscreen,
      dim: true,
      onPressed: onToggleFullscreen,
    );

    final Widget bar;
    if (collapsed) {
      final dot = _routeDot(t);
      bar = Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LgSpace.s2,
          vertical: LgSpace.s1,
        ),
        decoration: BoxDecoration(
          color: c.float,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(LgRadius.r16),
          ),
          boxShadow: c.shadow,
        ),
        child: _Group([
          dot,
          ?minimize,
          fullscreenButton,
          LgToolbarButton(
            icon: LgIcons.chevD,
            label: labels.expand,
            dim: true,
            onPressed: onToggleCollapsed,
          ),
        ]),
      );
    } else {
      final lead = <Widget>[
        if (fullscreen && deviceName != null)
          _DeviceName(name: deviceName!, id: deviceId ?? deviceName!),
        LgToolbarButton(
          icon: LgIcons.pin,
          label: labels.pin,
          toggled: pinned,
          onPressed: onTogglePin,
        ),
      ];
      final rows = <List<Widget>>[
        if (groups.isEmpty) lead else [...lead, ...groups.first],
        ...groups.skip(1),
        [
          ?minimize,
          fullscreenButton,
          LgToolbarButton(
            icon: LgIcons.chevU,
            label: labels.collapse,
            dim: true,
            onPressed: onToggleCollapsed,
          ),
        ],
      ];
      bar = Padding(
        padding: const EdgeInsets.only(top: LgSpace.s3),
        child: Container(
          height: t.sizes.bar,
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: LgSpace.s1,
          ),
          decoration: BoxDecoration(
            color: c.float,
            borderRadius: BorderRadius.circular(LgRadius.r16),
            boxShadow: c.shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, group) in rows.indexed) ...[
                if (i > 0) const SizedBox(width: LgSpace.s3),
                _Group(group),
              ],
            ],
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: labels.toolbar,
      child: FittedBox(fit: BoxFit.scaleDown, child: bar),
    );
  }

  /// The dot of the folded bar: filled for a direct connection, half filled
  /// (a diamond in detail mode) for a relayed one, and a triangle after it
  /// when the connection is not encrypted.
  Widget _routeDot(LgTokens t) {
    final c = t.colors;
    final direct = route == LgRoute.direct;
    final color = direct ? c.direct : c.relay;
    final mark = direct
        ? LgIcons.markDot
        : (t.detail ? LgIcons.markDia : LgIcons.markHalf);
    final text = encrypted ? routeLabel : '$routeLabel, $unencryptedLabel';
    return LgTooltip(
      message: text,
      child: Semantics(
        label: text,
        child: ExcludeSemantics(
          child: Container(
            height: t.sizes.tool,
            padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LgIcon(mark, size: 12, color: color),
                if (!encrypted) ...[
                  const SizedBox(width: LgSpace.s1),
                  LgIcon(LgIcons.markTri, size: 12, color: c.unencrypted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
