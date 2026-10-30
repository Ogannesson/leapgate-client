// The three layers of feedback (01 §4.5): the session notices stacked in a
// corner of the tab, the short toast of the whole window, and the
// confirmation that covers one area. `.toasts`/`.toast` of A-P2.html,
// `.toast` of A-P6-设置.html and `.sheet` of A-基础.html.
//
// Timers (when a notice or toast goes away) and the queue behind the three
// visible notices belong to the caller.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_banner.dart';
import 'lg_button.dart';
import 'lg_default_enter.dart';

Duration _enter(BuildContext context) => MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 160);

/// A button inside a notice ("另存为").
class LgNoticeAction {
  const LgNoticeAction(this.label, this.onPressed, {this.semanticLabel});

  final String label;
  final VoidCallback onPressed;

  /// The accessible name when it must differ from [label].
  final String? semanticLabel;
}

/// One session notice: what happened, and what can be done about it.
class LgNotice {
  const LgNotice({
    required this.id,
    required this.text,
    this.title,
    this.tone = LgTone.info,
    this.icon,
    this.actions = const [],
    this.dismissible = true,
  });

  /// Tells this notice from the others; passed back to `onDismiss`.
  final String id;
  final String text;

  /// Bold line before the text.
  final String? title;
  final LgTone tone;

  /// Overrides the icon of the tone (a printer for a print job).
  final LgIcons? icon;
  final List<LgNoticeAction> actions;

  /// Shows the close button; notices that ask for a decision keep it too, so
  /// that nothing stays on the picture for good.
  final bool dismissible;
}

/// Notices one under the other, newest at the bottom; at most [maxVisible]
/// are drawn, the ones after them wait in the caller's list until room is
/// made. 440 wide: place it at the right of the tab under the toolbar
/// (right 16, top 12 + toolbar height + 12).
class LgNoticeStack extends StatelessWidget {
  const LgNoticeStack({
    super.key,
    required this.notices,
    required this.onDismiss,
    required this.dismissLabel,
    this.maxVisible = 3,
  });

  final List<LgNotice> notices;
  final ValueChanged<String> onDismiss;

  /// Accessible name and tooltip of the close button ("关闭").
  final String dismissLabel;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final shown = notices.take(maxVisible).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, notice) in shown.indexed) ...[
            if (i > 0) const SizedBox(height: LgSpace.s2),
            _NoticeCard(
              key: ValueKey(notice.id),
              notice: notice,
              dismissLabel: dismissLabel,
              onDismiss: () => onDismiss(notice.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    super.key,
    required this.notice,
    required this.dismissLabel,
    required this.onDismiss,
  });

  final LgNotice notice;
  final String dismissLabel;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final card = Semantics(
      container: true,
      explicitChildNodes: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          LgSpace.s4,
          LgSpace.s3,
          LgSpace.s2,
          LgSpace.s3,
        ),
        decoration: BoxDecoration(
          color: c.float,
          borderRadius: BorderRadius.circular(LgRadius.r16),
          boxShadow: c.shadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: LgSpace.s1),
              child: LgIcon(
                notice.icon ?? lgToneIcon(notice.tone),
                size: 20,
                color: lgToneColor(c, notice.tone),
              ),
            ),
            const SizedBox(width: LgSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: LgSpace.s1),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (notice.title != null)
                            TextSpan(
                              text: '${notice.title}\n',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          TextSpan(text: notice.text),
                        ],
                      ),
                      style: t.textM.copyWith(color: c.text),
                    ),
                  ),
                  if (notice.actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: LgSpace.s2),
                      // The label of the first button lines up with the text.
                      child: Transform.translate(
                        offset: const Offset(-LgSpace.s3, 0),
                        child: Wrap(
                          spacing: LgSpace.s2,
                          runSpacing: LgSpace.s1,
                          children: [
                            for (final a in notice.actions)
                              LgButton(
                                label: a.label,
                                semanticLabel: a.semanticLabel,
                                kind: LgButtonKind.text,
                                horizontalPadding: LgSpace.s3,
                                onPressed: a.onPressed,
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (notice.dismissible)
              LgIconButton(
                icon: LgIcons.x,
                label: dismissLabel,
                onPressed: onDismiss,
              ),
          ],
        ),
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _enter(context),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(
        opacity: v,
        // Not silent while it fades in.
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * -6),
          child: child,
        ),
      ),
      child: card,
    );
  }
}

/// A short message about something that just happened ("已复制"): a pill with
/// an icon of its [tone].
class LgToast extends StatelessWidget {
  const LgToast(this.text, {super.key, this.tone = LgTone.success});

  final String text;
  final LgTone tone;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.fromLTRB(
            LgSpace.s4,
            LgSpace.s3,
            LgSpace.s5,
            LgSpace.s3,
          ),
          decoration: BoxDecoration(
            color: c.float,
            borderRadius: BorderRadius.circular(LgRadius.r12),
            boxShadow: c.shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LgIcon(lgToneIcon(tone), size: 20, color: lgToneColor(c, tone)),
              const SizedBox(width: LgSpace.s3),
              Flexible(
                child: Text(text, style: t.textM.copyWith(color: c.text)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Puts the toast of the window over [child], centred, 24 px above the bottom
/// edge, and fades it in and out. A null [text] means no toast; a new text
/// replaces the old one. It does not take the pointer.
class LgToastHost extends StatelessWidget {
  const LgToastHost({
    super.key,
    required this.child,
    this.text,
    this.tone = LgTone.success,
  });

  final Widget child;
  final String? text;
  final LgTone tone;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned(
          left: LgSpace.s4,
          right: LgSpace.s4,
          bottom: LgSpace.s6,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSwitcher(
                duration: _enter(context),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, .3),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: text == null
                    ? const SizedBox.shrink()
                    : LgToast(text!, tone: tone, key: ValueKey(text)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A button of a confirmation.
class LgDialogAction {
  const LgDialogAction({
    required this.label,
    required this.onPressed,
    this.kind = LgButtonKind.secondary,
    this.isDefault = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;

  /// [LgButtonKind.primary] for the usual answer, [LgButtonKind.dangerSolid]
  /// for the one that cannot be taken back, secondary for the way out.
  final LgButtonKind kind;

  /// What Enter does (at most one; none means Enter does nothing): the button
  /// takes the keyboard when the dialog opens, so Enter is its own press, and
  /// Enter in a field of the dialog runs it. A destructive question marks the
  /// safe answer ("取消"). With the focus on another button, Enter is that
  /// button's.
  final bool isDefault;

  /// The accessible name when it must differ from [label].
  final String? semanticLabel;
}

/// The layer of a confirmation: covers the area it is placed in with the dim
/// ground and puts [child] in the middle. Clicks outside the card do nothing;
/// Esc calls [onEscape]. What it covers (the whole window, one tab) is decided
/// by where the caller puts it.
class LgDialogScrim extends StatelessWidget {
  const LgDialogScrim({super.key, required this.child, this.onEscape});

  final Widget child;
  final VoidCallback? onEscape;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    // The shortcut sits above the scope: keys travel from the focused node
    // up, and the scope's own node is where the focus rests when no button
    // or field of the dialog holds it.
    return BlockSemantics(
      child: CallbackShortcuts(
        bindings: {
          if (onEscape != null)
            const SingleActivator(LogicalKeyboardKey.escape): onEscape!,
        },
        child: FocusScope(
          autofocus: true,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: _enter(context),
            builder: (context, v, child) =>
                Opacity(opacity: v, alwaysIncludeSemantics: true, child: child),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Takes the clicks so that nothing behind the card reacts.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: ColoredBox(color: c.scrim),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(LgSpace.s6),
                    child: child,
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

/// The confirmation card (`.sheet`): a question as the [title], the thing it
/// is about in [subtitle], what follows in [body] (with a small [bodyIcon]),
/// any further controls in [children] (check boxes, options, a list of what
/// will be closed), and the buttons, right aligned.
class LgConfirmDialog extends StatelessWidget {
  const LgConfirmDialog({
    super.key,
    required this.title,
    required this.actions,
    this.subtitle,
    this.body,
    this.bodyIcon,
    this.children = const [],
    this.width = 440,
  });

  final String title;
  final String? subtitle;
  final String? body;
  final LgIcons? bodyIcon;
  final List<Widget> children;
  final List<LgDialogAction> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final defaultAction = actions
        .where((a) => a.isDefault && a.onPressed != null)
        .firstOrNull;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: LgDefaultEnter(
        onEnter: defaultAction?.onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: c.float,
              borderRadius: BorderRadius.circular(LgRadius.r20),
              boxShadow: c.shadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: LgTokens.style(
                      20,
                      28,
                      FontWeight.w700,
                    ).copyWith(color: c.text),
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: LgSpace.s2),
                    child: Text(
                      subtitle!,
                      style: t.textS.copyWith(color: c.text2),
                    ),
                  ),
                if (body != null)
                  Padding(
                    padding: const EdgeInsets.only(top: LgSpace.s3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (bodyIcon != null) ...[
                          Padding(
                            padding: EdgeInsets.only(
                              top: (t.sizes.lhM - 18) / 2,
                            ),
                            child: LgIcon(bodyIcon!, size: 18, color: c.text),
                          ),
                          const SizedBox(width: LgSpace.s2),
                        ],
                        Expanded(
                          child: Text(
                            body!,
                            style: t.textM.copyWith(color: c.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                for (final child in children) ...[
                  const SizedBox(height: LgSpace.s4),
                  child,
                ],
                const SizedBox(height: LgSpace.s6),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: LgSpace.s3,
                  runSpacing: LgSpace.s3,
                  children: [
                    for (final a in actions)
                      LgButton(
                        label: a.label,
                        semanticLabel: a.semanticLabel,
                        kind: a.kind,
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
