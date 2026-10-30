// The connection box at the top of the device page (01 §3.1 block E): the
// input with its clear and help buttons, the "connect" button with its
// drop-down, and the help popover. `.connect`, `.field`, `.split`, `.pop` in
// A-基础.html and A-P1.html. Text comes from the caller.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_menu.dart';
import 'lg_pressable.dart';
import 'lg_text_field.dart';

/// What the help popover of the input lists: a title and (term, example)
/// rows, e.g. ("设备 ID", "123 456 789").
class LgHelpContent {
  const LgHelpContent({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;
}

const double _helpWidth = 400;

/// Body of the help popover (`.pop`): the title over a two column list. Shown
/// by [LgHelpButton] inside a menu surface; the gallery shows it the same way
/// through `LgMenuPanel`.
class LgHelpPanel extends StatelessWidget {
  const LgHelpPanel(this.content, {super.key});

  final LgHelpContent content;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Focus(
      // Holds the focus while the popover is open, so that Esc closes it.
      autofocus: true,
      skipTraversal: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LgSpace.s4,
          vertical: LgSpace.s2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                content.title,
                style: t.text.copyWith(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: LgSpace.s3),
            Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              columnWidths: const {1: FlexColumnWidth()},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                for (final (i, (term, example)) in content.rows.indexed)
                  TableRow(
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                          top: i == 0 ? 0 : LgSpace.s2,
                          right: LgSpace.s4,
                        ),
                        child: Text(
                          term,
                          style: t.textM.copyWith(
                            color: c.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : LgSpace.s2),
                        child: Text(
                          example,
                          style: t.textM.copyWith(color: c.text2),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The "?" at the end of the input: opens [LgHelpPanel] under it.
class LgHelpButton extends StatelessWidget {
  const LgHelpButton({super.key, required this.label, required this.content});

  /// Accessible name and tooltip ("输入说明").
  final String label;
  final LgHelpContent content;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return LgMenuAnchor(
      width: _helpWidth,
      items: [LgHelpPanel(content)],
      builder: (context, controller) => LgPressable(
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
            return;
          }
          // Right edge of the popover under the right edge of the button.
          final size = (context.findRenderObject()! as RenderBox).size;
          controller.open(
            position: Offset(size.width - _helpWidth, size.height + LgSpace.s2),
          );
        },
        semanticLabel: label,
        toggled: controller.isOpen,
        builder: (context, states) {
          final open =
              controller.isOpen || states.contains(WidgetState.selected);
          final radius = BorderRadius.circular(LgRadius.r10);
          return LgFocusRing(
            show: states.contains(WidgetState.focused),
            radius: radius,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: lgStateOverlay(c, states),
                borderRadius: radius,
              ),
              child: LgIcon(
                LgIcons.help,
                size: 22,
                color: open ? c.accent : c.text2,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A button with a drop-down (`.split`): the label connects, the arrow opens
/// [menuItems]. Both parts are disabled together when [onPressed] is null.
class LgSplitButton extends StatelessWidget {
  const LgSplitButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.menuItems,
    required this.menuLabel,
    this.menuWidth = kLgMenuWidth,
  });

  final String label;
  final VoidCallback? onPressed;
  final List<Widget> menuItems;

  /// Accessible name of the arrow.
  final String menuLabel;
  final double menuWidth;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final enabled = onPressed != null;
    final bg = enabled ? c.accent : c.disabled;
    final fg = enabled ? c.onAccent : c.text2;
    const outer = Radius.circular(LgRadius.r12);
    const left = BorderRadius.horizontal(left: outer);
    const right = BorderRadius.horizontal(right: outer);
    final height = t.sizes.main;

    Widget part({
      required BorderRadius radius,
      required VoidCallback? onTap,
      required String semanticLabel,
      required Widget child,
      double? width,
    }) {
      return LgPressable(
        onPressed: onTap,
        semanticLabel: semanticLabel,
        builder: (context, states) {
          final overlay = lgStateOverlay(c, states);
          return LgFocusRing(
            show: states.contains(WidgetState.focused),
            radius: radius,
            child: Container(
              width: width,
              height: height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: overlay == null ? bg : Color.alphaBlend(overlay, bg),
                borderRadius: radius,
              ),
              child: child,
            ),
          );
        },
      );
    }

    return LgMenuAnchor(
      items: menuItems,
      width: menuWidth,
      builder: (context, controller) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          part(
            radius: left,
            onTap: onPressed,
            semanticLabel: label,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: ExcludeSemantics(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: t.text.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          // `.sep`: 1.5 px, a quarter of the height in from both ends.
          Container(
            width: 1.5,
            height: height / 2,
            color: fg.withValues(alpha: .4),
          ),
          part(
            radius: right,
            width: 44,
            semanticLabel: menuLabel,
            onTap: onPressed == null
                ? null
                : () {
                    if (controller.isOpen) {
                      controller.close();
                      return;
                    }
                    // Right edges of the menu and of the whole button meet.
                    final size =
                        (context.findRenderObject()! as RenderBox).size;
                    controller.open(
                      position: Offset(
                        size.width - menuWidth,
                        size.height + LgSpace.s1,
                      ),
                    );
                  },
            child: LgIcon(LgIcons.chevD, size: 20, color: fg),
          ),
        ],
      ),
    );
  }
}

/// The whole box: input with search icon, clear and help buttons, and the
/// split "connect" button. Keys (arrows into the results, Enter, Esc) are the
/// page's business: wrap the box in a `Focus(onKeyEvent: …)`.
class LgConnectBar extends StatelessWidget {
  const LgConnectBar({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.connectLabel,
    required this.onConnect,
    required this.menuItems,
    required this.menuLabel,
    required this.clearLabel,
    required this.helpLabel,
    required this.help,
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;

  /// "输入 ID 或搜索设备": the hint and the accessible name of the input.
  final String placeholder;
  final String connectLabel;

  /// Null while the input is empty: the button and its arrow are disabled.
  final VoidCallback? onConnect;
  final List<Widget> menuItems;
  final String menuLabel;
  final String clearLabel;
  final String helpLabel;
  final LgHelpContent help;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LgTextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            placeholder: placeholder,
            semanticLabel: placeholder,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            leading: LgIcon(LgIcons.search, size: 22, color: c.text2),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => controller.text.isEmpty
                      ? const SizedBox.shrink()
                      : LgIconButton(
                          icon: LgIcons.x,
                          label: clearLabel,
                          size: 32,
                          iconSize: 22,
                          onPressed: () {
                            controller.clear();
                            onChanged?.call('');
                            focusNode?.requestFocus();
                          },
                        ),
                ),
                LgHelpButton(label: helpLabel, content: help),
              ],
            ),
          ),
        ),
        const SizedBox(width: LgSpace.s2),
        LgSplitButton(
          label: connectLabel,
          onPressed: onConnect,
          menuItems: menuItems,
          menuLabel: menuLabel,
        ),
      ],
    );
  }
}
