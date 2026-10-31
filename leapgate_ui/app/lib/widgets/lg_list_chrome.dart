// What surrounds the device list on the device page (01 §3.1 blocks A, B, F, J;
// `.cats`, `.tool`, `.msel`, `.who`, `.pcard`, `.lockov` in A-基础.html and
// A-P1.html): the category tabs and the tools beside them, the bar of
// multi-select, the short notes under and beside the list, the notice card
// of the local area and the layer that covers the page while this computer is
// being controlled.
//
// Everything here only draws: the texts come from the caller (localised) and
// the callbacks are the caller's.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_banner.dart';
import 'lg_button.dart';
import 'lg_menu.dart';
import 'lg_pressable.dart';

/// One category tab ("最近").
class LgCategory<T> {
  const LgCategory(this.value, this.label);

  final T value;
  final String label;
}

/// The categories of the device list as text tabs (`.cats`): the chosen one on
/// a tinted ground, bold. Left and Right move between them like Tab does.
class LgCategoryTabs<T> extends StatelessWidget {
  const LgCategoryTabs({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
    this.semanticLabel,
  });

  final List<LgCategory<T>> categories;
  final T selected;
  final ValueChanged<T>? onSelect;

  /// Name of the group for a screen reader ("设备分类").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r12);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, cat) in categories.indexed) ...[
            if (i > 0) const SizedBox(width: LgSpace.s1),
            LgPressable(
              onPressed: onSelect == null ? null : () => onSelect!(cat.value),
              semanticLabel: cat.label,
              selected: cat.value == selected,
              builder: (context, states) {
                final on = cat.value == selected;
                final overlay = on ? null : lgStateOverlay(c, states);
                return LgFocusRing(
                  show: states.contains(WidgetState.focused),
                  radius: radius,
                  child: Container(
                    height: t.sizes.nav,
                    padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? c.cat : overlay,
                      borderRadius: radius,
                    ),
                    child: ExcludeSemantics(
                      child: Text(
                        cat.label,
                        maxLines: 1,
                        softWrap: false,
                        style: t.text.copyWith(
                          color: on ? c.catFg : c.text2,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// A tool beside the tabs (`.tool`): an icon and a word, "视图", "多选". With
/// [active] it is tinted and bold: its menu is open, or the mode it switches
/// is on.
class LgListToolButton extends StatelessWidget {
  const LgListToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final LgIcons icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return LgPressable(
      onPressed: onPressed,
      semanticLabel: label,
      toggled: active ? true : null,
      builder: (context, states) => _ToolFace(
        icon: icon,
        label: label,
        states: states,
        active: active || states.contains(WidgetState.selected),
      ),
    );
  }
}

/// A tool that opens a menu under its right edge ("视图", "排序").
class LgListToolMenu extends StatelessWidget {
  const LgListToolMenu({
    super.key,
    required this.icon,
    required this.label,
    required this.items,
    this.width = kLgMenuWidth,
  });

  final LgIcons icon;
  final String label;
  final List<Widget> items;
  final double width;

  @override
  Widget build(BuildContext context) {
    return LgMenuAnchor(
      items: items,
      width: width,
      builder: (context, controller) => LgPressable(
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
            return;
          }
          // The right edge of the menu under the right edge of the tool.
          final size = (context.findRenderObject()! as RenderBox).size;
          controller.open(
            position: Offset(size.width - width, size.height + LgSpace.s1),
          );
        },
        semanticLabel: label,
        toggled: controller.isOpen,
        builder: (context, states) => _ToolFace(
          icon: icon,
          label: label,
          states: states,
          active: controller.isOpen || states.contains(WidgetState.selected),
        ),
      ),
    );
  }
}

class _ToolFace extends StatelessWidget {
  const _ToolFace({
    required this.icon,
    required this.label,
    required this.states,
    required this.active,
  });

  final LgIcons icon;
  final String label;
  final Set<WidgetState> states;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r10);
    final overlay = active ? null : lgStateOverlay(c, states);
    final fg = active ? c.accent : c.text2;
    return Opacity(
      opacity: states.contains(WidgetState.disabled) ? .6 : 1,
      child: LgFocusRing(
        show: states.contains(WidgetState.focused),
        radius: radius,
        child: Container(
          height: t.sizes.button,
          padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
          decoration: BoxDecoration(
            color: active ? c.active : overlay,
            borderRadius: radius,
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LgIcon(icon, size: t.sizes.icon, color: fg),
                const SizedBox(width: LgSpace.s2),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: t.text.copyWith(
                    color: fg,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The row under the connection box: the [tabs] at the left, the [tools] at
/// the right, 24 px below the box above it (`.cats`). In a narrow window the
/// tools keep their place and the tabs scroll sideways.
class LgListToolbar extends StatelessWidget {
  const LgListToolbar({super.key, required this.tabs, this.tools = const []});

  final Widget tabs;
  final List<Widget> tools;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: tabs,
            ),
          ),
        ),
        for (final (i, tool) in tools.indexed) ...[
          if (i > 0) const SizedBox(width: LgSpace.s1),
          tool,
        ],
      ],
    );
  }
}

/// One button of [LgSelectionBar].
class LgSelectionAction {
  const LgSelectionAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final LgIcons icon;

  /// Null greys it (nothing picked yet).
  final VoidCallback? onPressed;
  final bool danger;
}

/// The bar of multi-select (`.msel`): what can be done with the picked
/// devices, then how many are picked, "全选" and "完成". [countText] is the
/// whole sentence ("已选择 3 台").
class LgSelectionBar extends StatelessWidget {
  const LgSelectionBar({
    super.key,
    required this.actions,
    required this.countText,
    required this.selectAllLabel,
    required this.onSelectAll,
    required this.doneLabel,
    required this.onDone,
    this.semanticLabel,
  });

  final List<LgSelectionAction> actions;
  final String countText;
  final String selectAllLabel;
  final VoidCallback? onSelectAll;
  final String doneLabel;
  final VoidCallback? onDone;

  /// Name of the bar for a screen reader ("多选").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Container(
        constraints: BoxConstraints(minHeight: t.sizes.nav),
        // A button is 36 high, so the bar is 40 with 2 px above and under.
        padding: const EdgeInsets.fromLTRB(LgSpace.s2, 2, LgSpace.s2, 2),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(LgRadius.r12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: LgSpace.s2,
                runSpacing: LgSpace.s1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final a in actions)
                    LgButton(
                      label: a.label,
                      icon: a.icon,
                      kind: a.danger
                          ? LgButtonKind.danger
                          : LgButtonKind.secondary,
                      onPressed: a.onPressed,
                    ),
                ],
              ),
            ),
            const SizedBox(width: LgSpace.s2),
            Semantics(
              liveRegion: true,
              label: countText,
              child: ExcludeSemantics(
                child: Text(
                  countText,
                  maxLines: 1,
                  softWrap: false,
                  style: t.text.copyWith(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: LgSpace.s2),
            LgButton(
              label: selectAllLabel,
              kind: LgButtonKind.text,
              onPressed: onSelectAll,
            ),
            LgButton(
              label: doneLabel,
              kind: LgButtonKind.text,
              onPressed: onDone,
            ),
          ],
        ),
      ),
    );
  }
}

/// A line of small text centred under the list ("仅显示前 1000 台设备，可使用
/// 搜索缩小范围", `.more1000`).
class LgListNote extends StatelessWidget {
  const LgListNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: LgSpace.s4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: t.textM.copyWith(color: t.colors.text2),
      ),
    );
  }
}

/// A card in the local area that says something about this computer (`.pcard`):
/// a notice with an icon, the text and, if there is something to do about it,
/// a button. The tone sets the ground and the icon; an error is announced.
class LgLocalNotice extends StatelessWidget {
  const LgLocalNotice({
    super.key,
    required this.tone,
    required this.text,
    this.icon,
    this.actionLabel,
    this.onAction,
  }) : assert(actionLabel == null || onAction != null);

  final LgTone tone;
  final String text;
  final LgIcons? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final bg = switch (tone) {
      LgTone.warning => c.warningBg,
      LgTone.error => c.errorBg,
      _ => c.surface2,
    };
    return Semantics(
      container: true,
      liveRegion: tone == LgTone.error || tone == LgTone.warning,
      child: Container(
        padding: const EdgeInsets.all(LgSpace.s4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(LgRadius.r16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: math.max(0, (t.sizes.lhM - 20) / 2)),
                  child: LgIcon(
                    icon ?? lgToneIcon(tone),
                    size: 20,
                    color: lgToneColor(c, tone),
                  ),
                ),
                const SizedBox(width: LgSpace.s3),
                Expanded(
                  child: Text(text, style: t.textM.copyWith(color: c.text)),
                ),
              ],
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: LgSpace.s3),
              LgButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// "正在被远程控制（2 个会话）" with "查看" at its end (`.who`) in the local
/// area. [text] may run over two lines; [onView] null leaves "查看" out.
class LgControlledNote extends StatelessWidget {
  const LgControlledNote({
    super.key,
    required this.text,
    this.viewLabel,
    this.onView,
  }) : assert(onView == null || viewLabel != null);

  final String text;
  final String? viewLabel;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          LgSpace.s3,
          LgSpace.s2,
          LgSpace.s1,
          LgSpace.s2,
        ),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(LgRadius.r12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                label: text,
                child: ExcludeSemantics(
                  child: Text(text, style: t.textS.copyWith(color: c.text)),
                ),
              ),
            ),
            if (onView != null)
              LgButton(
                label: viewLabel!,
                kind: LgButtonKind.text,
                onPressed: onView,
              ),
          ],
        ),
      ),
    );
  }
}

/// The layer over a page while this computer is being controlled (`.lockov`):
/// with [blocked] a dim ground and one card ("远程控制期间无法修改设置") cover
/// [child]; clicks and the keyboard no longer reach it. Without it, [child] is
/// shown as it is. Cover only the page, not the tabs (01 block J).
class LgBlockedOverlay extends StatelessWidget {
  const LgBlockedOverlay({
    super.key,
    required this.blocked,
    required this.message,
    required this.child,
  });

  final bool blocked;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        ExcludeFocus(
          excluding: blocked,
          child: AbsorbPointer(absorbing: blocked, child: child),
        ),
        if (blocked)
          Positioned.fill(
            child: Semantics(
              container: true,
              liveRegion: true,
              label: message,
              child: ColoredBox(
                color: c.scrim,
                child: Center(
                  child: ExcludeSemantics(
                    child: Container(
                      margin: const EdgeInsets.all(LgSpace.s6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: LgSpace.s7,
                        vertical: LgSpace.s6,
                      ),
                      decoration: BoxDecoration(
                        color: c.float,
                        borderRadius: BorderRadius.circular(LgRadius.r20),
                        boxShadow: c.shadow,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LgIcon(LgIcons.lock, size: 28, color: c.accent),
                          const SizedBox(width: LgSpace.s4),
                          Flexible(
                            child: Text(
                              message,
                              style: t.textN.copyWith(
                                color: c.text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
