// The account area at the bottom of the home page's left column (01 §3.1
// block D; `.acctout`, `.acct`, `p1-acct-*` in A-P1.html) and the question
// that comes before signing out.
//
// Signed out it is a "登录" button with a line of small text under it. Signed in
// it is a row with the person's first letter, the name and the @account; a click
// opens the account menu above the row (the row is at the bottom of the window,
// so the menu has no room below it and opens upward).
//
// Only drawing: the texts, the menu's rows and the callbacks are the caller's.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_feedback.dart';
import 'lg_menu.dart';
import 'lg_pressable.dart';

/// The round avatar of a person (`.av`): the first letter on a neutral ground,
/// not on the accent or an identity colour (01 §2.4, those belong to devices).
/// [onTint] is for a row that has its own tinted ground (the selected person),
/// where the neutral grey would melt into it.
class LgPersonAvatar extends StatelessWidget {
  const LgPersonAvatar({
    super.key,
    required this.initial,
    this.size = 32,
    this.onTint = false,
  });

  /// One character, already upper-cased by the caller (01 block D's rule).
  final String initial;
  final double size;
  final bool onTint;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: onTint ? c.surface : c.border,
        ),
        child: Text(
          initial,
          maxLines: 1,
          softWrap: false,
          style: (size >= 32 ? t.text : t.textM).copyWith(
            color: c.text,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// The account area. [LgAccountArea.signedOut] and [LgAccountArea.signedIn] are
/// its two states.
class LgAccountArea extends StatelessWidget {
  /// Signed out: the [loginLabel] button and [hint] under it ("登录后可使用地址
  /// 簿、同组设备和出口目录").
  const LgAccountArea.signedOut({
    super.key,
    required String this.loginLabel,
    required String this.hint,
    required this.onLogin,
  }) : initial = null,
       name = null,
       handle = null,
       menuItems = const [],
       semanticLabel = null;

  /// Signed in: [initial] in the avatar, [name] and [handle] ("@zhangsan") next
  /// to it. [menuItems] are the rows of the menu: an [LgAccountMenuInfo] first,
  /// then `LgMenuItem`s ("退出登录").
  const LgAccountArea.signedIn({
    super.key,
    required String this.initial,
    required String this.name,
    required String this.handle,
    required this.menuItems,
    this.semanticLabel,
  }) : loginLabel = null,
       hint = null,
       onLogin = null;

  final String? loginLabel;
  final String? hint;
  final VoidCallback? onLogin;

  final String? initial;
  final String? name;
  final String? handle;
  final List<Widget> menuItems;

  /// The accessible name of the row; the name and the account by default.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return loginLabel != null ? _signedOut(context) : _signedIn(context);
  }

  Widget _signedOut(BuildContext context) {
    final t = LgTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: LgSpace.s3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            child: LgButton(
              label: loginLabel!,
              icon: LgIcons.login,
              kind: LgButtonKind.primary,
              onPressed: onLogin,
            ),
          ),
          const SizedBox(height: LgSpace.s1),
          Text(hint!, style: t.textS.copyWith(color: t.colors.text2)),
        ],
      ),
    );
  }

  Widget _signedIn(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r12);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : kLgMenuWidth;
        return LgMenuAnchor(
          width: width,
          items: menuItems,
          builder: (context, controller) => LgPressable(
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            semanticLabel: semanticLabel ?? '$name $handle',
            expanded: controller.isOpen,
            builder: (context, states) {
              final open =
                  controller.isOpen || states.contains(WidgetState.selected);
              return LgFocusRing(
                show: states.contains(WidgetState.focused),
                radius: radius,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
                  decoration: BoxDecoration(
                    color: open ? c.surface2 : lgStateOverlay(c, states),
                    borderRadius: radius,
                  ),
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        LgPersonAvatar(initial: initial!, onTint: open),
                        const SizedBox(width: LgSpace.s3),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: LgTokens.style(
                                  t.sizes.fs,
                                  20,
                                  FontWeight.w700,
                                ).copyWith(color: c.text),
                              ),
                              Text(
                                handle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.textS.copyWith(color: c.text2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: LgSpace.s3),
                        LgIcon(
                          open ? LgIcons.chevU : LgIcons.chevD,
                          size: 20,
                          color: c.text,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// The first row of the account menu: who is signed in. It is information, not
/// a button (`.mr.two` with a user icon): [label] ("账号信息") and under it
/// [handle] ("@zhangsan").
class LgAccountMenuInfo extends StatelessWidget {
  const LgAccountMenuInfo({
    super.key,
    required this.label,
    required this.handle,
  });

  final String label;
  final String handle;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      container: true,
      label: '$label, $handle',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LgSpace.s4,
            vertical: LgSpace.s2,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: t.sizes.row - LgSpace.s4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: math.max(0, (t.sizes.lh - 20) / 2),
                  ),
                  child: LgIcon(LgIcons.user, size: 20, color: c.text2),
                ),
                const SizedBox(width: LgSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: t.text.copyWith(color: c.text)),
                      Text(
                        handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textS.copyWith(color: c.text2),
                      ),
                    ],
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

/// The question before signing out, in the page (01 §4.4): [title] ("退出登录？"),
/// [body] under it and the buttons. It takes the place of the account row, so
/// nothing has to cover the page. The button marked [LgDialogAction.isDefault]
/// has the keyboard when the card appears; Esc calls [onEscape].
class LgAccountConfirm extends StatelessWidget {
  const LgAccountConfirm({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.onEscape,
  });

  final String title;
  final String body;
  final List<LgDialogAction> actions;
  final VoidCallback? onEscape;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final defaultAction = actions
        .where((a) => a.isDefault && a.onPressed != null && !a.busy)
        .firstOrNull;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: title,
      child: CallbackShortcuts(
        bindings: {
          if (onEscape != null)
            const SingleActivator(LogicalKeyboardKey.escape): onEscape!,
        },
        child: FocusScope(
          child: Container(
            margin: const EdgeInsets.only(top: LgSpace.s3),
            padding: const EdgeInsets.all(LgSpace.s4),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(LgRadius.r16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: t.text.copyWith(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: LgSpace.s1),
                Text(body, style: t.textS.copyWith(color: c.text2)),
                const SizedBox(height: LgSpace.s3),
                Wrap(
                  spacing: LgSpace.s2,
                  runSpacing: LgSpace.s2,
                  children: [
                    for (final a in actions)
                      LgButton(
                        label: a.label,
                        semanticLabel: a.semanticLabel,
                        kind: a.kind,
                        busy: a.busy,
                        autofocus: a == defaultAction,
                        onPressed: a.onPressed,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
