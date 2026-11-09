// The title bar of a view (02 §2.2 block A, `.vt` in A-P7-文件传输.html): the narrow bar under the
// session tabs that the file, terminal and camera views carry. From the left: the view switch
// (the same control as on the remote desktop toolbar; "文件传输" shows the ring of the overall
// progress), the connection method with its details, then a middle part that the view brings (the
// tabs of the terminals, `LgTermTabs`) and, at the far end, "⋯" and "断开". The parts are given;
// this draws the bar they stand in.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_menu.dart';
import 'lg_pressable.dart';
import 'lg_tooltip.dart';

class LgViewBar extends StatelessWidget {
  const LgViewBar({
    super.key,
    required this.viewSwitch,
    required this.disconnectLabel,
    required this.onDisconnect,
    this.route,
    this.compact = false,
    this.middle,
    this.more,
  });

  /// An [LgToolbarMenuButton] with `highlighted` (and `progress` or `alert` while files move).
  final Widget viewSwitch;

  /// An [LgToolbarRouteButton]; null until the connection method is known.
  final Widget? route;

  /// What the view puts between the connection method and the far end, after a thin rule
  /// (`.vsep`): the tabs of the terminals. It is given the rest of the width, so it may scroll or
  /// fold what does not fit. Null leaves the space empty, as the file view has it.
  final Widget? middle;

  /// The "⋯" button of the view ([LgViewMoreButton]), 8 px before "断开". Null for none.
  final Widget? more;

  /// "断开". Disconnects this view only (02 §2.2 block A).
  final String disconnectLabel;
  final VoidCallback onDisconnect;

  /// The bar of the smallest window, a button and 8 px high where the ordinary one is a toolbar
  /// high (`.frame.mn .vt`); the page passes it by the height of the window. The detail mode's
  /// bar is lower than that already and stays as it is.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Container(
      height: compact
          ? math.min(t.sizes.bar, t.sizes.button + LgSpace.s2)
          : t.sizes.bar,
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          viewSwitch,
          if (route != null) ...[const SizedBox(width: LgSpace.s2), route!],
          if (middle != null) ...[
            // `.vsep`: the 1 px rule has 4 px of its own on either side of the bar's 8 px gap.
            const SizedBox(width: LgSpace.s3),
            Container(width: 1, height: 24, color: c.border),
            const SizedBox(width: LgSpace.s3),
            Expanded(child: middle!),
          ] else
            const Spacer(),
          if (more != null) ...[more!, const SizedBox(width: LgSpace.s2)],
          LgButton(
            label: disconnectLabel,
            icon: LgIcons.power,
            kind: LgButtonKind.danger,
            onPressed: onDisconnect,
          ),
        ],
      ),
    );
  }
}

/// A square icon button of the view bar (`.ib`): 36 px (`--lg-h-btn`), the icon in the second
/// colour, the ground tinted while the menu it opens is open ([open]). [label] is the name a
/// screen reader and a script find it by; [tooltip] is what the pointer shows when that is not the
/// same text ("新建终端（Ctrl+Shift+T）" for "新建终端"). [onPressed] null greys it.
class LgBarIconButton extends StatelessWidget {
  const LgBarIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.open,
    this.focusNode,
  });

  final LgIcons icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;

  /// Null for a button that opens nothing; true or false for one that opens a menu.
  final bool? open;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final side = t.sizes.button;
    final radius = BorderRadius.circular(LgRadius.r10);
    return LgTooltip(
      message: tooltip ?? label,
      child: LgPressable(
        onPressed: onPressed,
        focusNode: focusNode,
        semanticLabel: label,
        expanded: open,
        builder: (context, states) {
          final disabled = states.contains(WidgetState.disabled);
          final tint = open == true ? c.active : null;
          final overlay = lgStateOverlay(c, states);
          return Opacity(
            opacity: disabled ? .45 : 1,
            child: LgFocusRing(
              show: states.contains(WidgetState.focused),
              radius: radius,
              child: Container(
                width: side,
                height: side,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: overlay == null
                      ? tint
                      : Color.alphaBlend(overlay, tint ?? Colors.transparent),
                  borderRadius: radius,
                ),
                child: LgIcon(
                  icon,
                  size: t.sizes.icon,
                  color: open == true ? c.accent : c.text2,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "⋯" at the right end of a view bar, with the menu it opens ([items], an `LgMenuItem` list):
/// 320 wide, hanging from the right edge of the button (`.menu.mom`). Put it in
/// [LgViewBar.more].
class LgViewMoreButton extends StatelessWidget {
  const LgViewMoreButton({
    super.key,
    required this.label,
    required this.items,
    this.menuWidth = 320,
  });

  /// "更多".
  final String label;
  final List<Widget> items;
  final double menuWidth;

  @override
  Widget build(BuildContext context) {
    final side = LgTokens.of(context).sizes.button;
    return LgMenuAnchor(
      width: menuWidth,
      alignmentOffset: Offset(side - menuWidth, LgSpace.s1),
      items: items,
      builder: (context, controller) => LgBarIconButton(
        icon: LgIcons.more,
        label: label,
        open: controller.isOpen,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
