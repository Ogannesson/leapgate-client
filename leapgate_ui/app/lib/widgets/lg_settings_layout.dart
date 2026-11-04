// The frame of the settings page (02 §1.2.2, A-P6-设置.html "设置页框架"): the
// section navigation on the left (a search box, three groups of sections), the
// section's content on the right (title, lock bar, the blocks), and the lock bar.
//
// These only draw. What the sections are, what a search finds, whether the page
// is locked and what the buttons do are the page's business; every text comes
// from the caller (09-M6拆法.md §2.2, `LEAPGATE.md` §10.13).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_pressable.dart';
import 'lg_text_field.dart';

/// The width of the navigation column (`--sn-w`).
const double kLgSettingsNavWidth = 180;

/// The widest the content gets (`.sc` max-width, the padding included).
const double kLgSettingsContentMaxWidth = 640;

/// Below this width of the content (the container query of A-P6-设置.html), the
/// controls that are wide move to the line under the name of their row.
const double kLgSettingsNarrowBelow = 560;

/// Tells the rows of a section whether the content is narrow
/// ([kLgSettingsNarrowBelow]). [LgSettingsContent] sets it; outside of it
/// nothing is narrow.
class LgSettingsMetrics extends InheritedWidget {
  const LgSettingsMetrics({
    super.key,
    required this.narrow,
    required super.child,
  });

  final bool narrow;

  static bool narrowOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LgSettingsMetrics>()?.narrow ??
      false;

  @override
  bool updateShouldNotify(LgSettingsMetrics old) => old.narrow != narrow;
}

/// What the parts of a section ask for above them. [LgSettingsContent] puts
/// the space between its children from this, the way the mockup's margins do.
enum LgSettingsFlow {
  /// A white block ([LgSettingsBlock]); 12 under another block.
  block,

  /// A white block with room above it (`.s-b.gap`).
  gappedBlock,

  /// The small title of a part of the section (`.s-sub`).
  subtitle,

  /// A line of small text between blocks (`.s-note`).
  note,

  /// A title with its own buttons (`.td-h`), such as the one of the shortcut list.
  heading,

  /// A titled group of rows that has its own block (`.kb-g` with `.kb-b`).
  group,

  /// Anything else; 12 under whatever comes before.
  other,
}

/// Implemented by the parts of a section that know how much room they want.
abstract interface class LgSettingsFlowPart {
  LgSettingsFlow get flow;
}

// ---- the two columns ----------------------------------------------------------

/// The navigation and the content side by side, 8 from the page's left edge and
/// 16 between the two (`.sv`). Neither scrolls sideways at the smallest window.
class LgSettingsLayout extends StatelessWidget {
  const LgSettingsLayout({
    super.key,
    required this.navigation,
    required this.content,
  });

  final Widget navigation;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: LgSpace.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          navigation,
          const SizedBox(width: LgSpace.s4),
          Expanded(child: content),
        ],
      ),
    );
  }
}

// ---- navigation ---------------------------------------------------------------

/// The navigation column (`.sn`, 180 wide): the search box stays at the top, the
/// groups under it scroll when they do not fit (the window is 600 high at the
/// smallest). The section that gets selected is scrolled into view.
class LgSettingsNav extends StatefulWidget {
  const LgSettingsNav({
    super.key,
    required this.search,
    required this.children,
    this.semanticLabel,
  });

  /// An [LgSettingsSearchField].
  final Widget search;

  /// [LgSettingsNavGroup]s.
  final List<Widget> children;

  /// The name of the navigation for a screen reader ("设置分区").
  final String? semanticLabel;

  @override
  State<LgSettingsNav> createState() => _LgSettingsNavState();
}

class _LgSettingsNavState extends State<LgSettingsNav> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kLgSettingsNavWidth,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: widget.semanticLabel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top: LgSpace.s2,
                right: LgSpace.s2,
              ),
              child: widget.search,
            ),
            Expanded(
              child: Scrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.only(
                    right: LgSpace.s2,
                    bottom: LgSpace.s1,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A group of sections: its name (not a button) and the sections under it.
class LgSettingsNavGroup extends StatelessWidget {
  const LgSettingsNavGroup({
    super.key,
    required this.title,
    required this.items,
  });

  final String title;

  /// [LgSettingsNavItem]s.
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `.sg`: 12 above the line of text, 4 under it, bottom aligned.
        Semantics(
          header: true,
          child: Container(
            margin: const EdgeInsets.only(top: LgSpace.s2),
            height: t.sizes.lhS + LgSpace.s3,
            padding: const EdgeInsets.fromLTRB(
              LgSpace.s3,
              0,
              LgSpace.s3,
              LgSpace.s1,
            ),
            alignment: Alignment.bottomLeft,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textS.copyWith(
                color: c.text2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        ...items,
      ],
    );
  }
}

/// A section in the navigation (`.si`): the selected one on the navigation
/// colour as in the home page's left column, the lock of a section that is
/// locked at its end.
class LgSettingsNavItem extends StatefulWidget {
  const LgSettingsNavItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.locked = false,
    this.lockedLabel,
    this.focusNode,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  /// The section is locked now: the lock icon shows.
  final bool locked;

  /// What the lock says to a screen reader ("已锁定"); read after the name.
  final String? lockedLabel;
  final FocusNode? focusNode;

  @override
  State<LgSettingsNavItem> createState() => _LgSettingsNavItemState();
}

class _LgSettingsNavItemState extends State<LgSettingsNavItem> {
  @override
  void initState() {
    super.initState();
    if (widget.selected) _reveal();
  }

  @override
  void didUpdateWidget(LgSettingsNavItem old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) _reveal();
  }

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || Scrollable.maybeOf(context) == null) return;
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r12);
    final height = t.detail ? t.sizes.row : t.sizes.lh + LgSpace.s2;
    final label = widget.locked && widget.lockedLabel != null
        ? '${widget.label}, ${widget.lockedLabel}'
        : widget.label;
    return LgPressable(
      onPressed: widget.onPressed,
      focusNode: widget.focusNode,
      selected: widget.selected,
      semanticLabel: label,
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        final bg = widget.selected ? c.nav : null;
        final fg = widget.selected ? c.navFg : c.text;
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            constraints: BoxConstraints(minHeight: height),
            padding: EdgeInsets.symmetric(
              horizontal: LgSpace.s3,
              vertical: (height - t.sizes.lh) / 2,
            ),
            decoration: BoxDecoration(
              color: overlay == null
                  ? bg
                  : Color.alphaBlend(overlay, bg ?? Colors.transparent),
              borderRadius: radius,
            ),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Expanded(
                    // One line; a long name (the English ones are) goes on to a
                    // second, and ends in "…" only after that.
                    child: Text(
                      widget.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.copyWith(
                        color: fg,
                        fontWeight: widget.selected
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (widget.locked) ...[
                    const SizedBox(width: LgSpace.s2),
                    LgIcon(
                      LgIcons.lock,
                      size: 14,
                      color: widget.selected ? c.navFg : c.text2,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---- search box ---------------------------------------------------------------

/// The search box at the top of the navigation (`.sq`): a search icon, the
/// typing, and a clear button once there is something to clear.
///
/// The arrow keys call [onMove] (+1 down, -1 up) so that the page moves the
/// highlight in the results; Enter calls [onSubmitted] (the page opens the
/// highlighted result); Esc clears the box (02 §1.2.4). The page owns the
/// results and the highlight.
class LgSettingsSearchField extends StatelessWidget {
  const LgSettingsSearchField({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.clearLabel,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onMove,
  });

  final TextEditingController controller;

  /// "搜索设置"; also the accessible name of the box.
  final String placeholder;

  /// The accessible name of the clear button ("清除搜索").
  final String clearLabel;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<int>? onMove;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // The keys the input method is composing with (a pinyin candidate list, say)
    // are its own: Up and Down pick a candidate, Esc drops the composition.
    if (event is KeyUpEvent || controller.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown && onMove != null) {
      onMove!(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && onMove != null) {
      onMove!(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && controller.text.isNotEmpty) {
      controller.clear();
      onChanged?.call('');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => LgTextField(
          controller: controller,
          focusNode: focusNode,
          placeholder: placeholder,
          semanticLabel: placeholder,
          dense: true,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          // Enter must not take the focus out of the box: the arrows go on
          // working on the results.
          onEditingComplete: () {},
          leading: LgIcon(LgIcons.search, size: 18, color: c.text2),
          trailing: controller.text.isEmpty
              ? null
              : LgIconButton(
                  icon: LgIcons.x,
                  label: clearLabel,
                  size: 28,
                  iconSize: 18,
                  focusable: false,
                  onPressed: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                ),
        ),
      ),
    );
  }
}

// ---- content ------------------------------------------------------------------

/// The content column (`.sc`): at most 640 wide, on the left, scrolling by
/// itself. Title and lede, then the lock bar if there is one, then the
/// [children], which are put 12 apart unless they ask for more
/// ([LgSettingsFlowPart]). With [locked] the children are dimmed and cannot be
/// reached; the bar says why.
///
/// A search shows its results here without a [title].
class LgSettingsContent extends StatelessWidget {
  const LgSettingsContent({
    super.key,
    this.title,
    this.lede,
    this.lockBar,
    this.locked = false,
    required this.children,
    this.controller,
  });

  /// The section's name (`h2`).
  final String? title;

  /// A line of small text under the title.
  final String? lede;

  /// An [LgSettingsLockBar], when the section is locked or was just unlocked
  /// and the bar still has something to say.
  final Widget? lockBar;

  /// The children cannot be used (`.s-lk`).
  final bool locked;
  final List<Widget> children;

  /// So that the page can scroll to an item.
  final ScrollController? controller;

  static LgSettingsFlow _flowOf(Widget w) => w is LgSettingsFlowPart
      ? (w as LgSettingsFlowPart).flow
      : LgSettingsFlow.other;

  /// The space between two neighbours: the larger of what the one above leaves
  /// under it and what the one below asks for above it, as margins collapse.
  static double gapBetween(Widget? above, Widget below) {
    if (above == null) return LgSpace.s4;
    final up = _flowOf(above);
    final down = _flowOf(below);
    final under = switch (up) {
      LgSettingsFlow.subtitle || LgSettingsFlow.note => LgSpace.s2,
      _ => 0.0,
    };
    final over = switch (down) {
      LgSettingsFlow.gappedBlock => LgSpace.s6,
      LgSettingsFlow.subtitle => LgSpace.s6,
      LgSettingsFlow.heading => LgSpace.s6,
      LgSettingsFlow.group => LgSpace.s5,
      LgSettingsFlow.note => LgSpace.s4,
      LgSettingsFlow.block =>
        up == LgSettingsFlow.subtitle || up == LgSettingsFlow.note
            ? 0.0
            : LgSpace.s3,
      LgSettingsFlow.other => LgSpace.s3,
    };
    return math.max(under, over);
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kLgSettingsContentMaxWidth),
        child: _Scrolling(
          controller: controller,
          child: LayoutBuilder(
            builder: (context, box) {
              final narrow = box.maxWidth < kLgSettingsNarrowBelow;
              return LgSettingsMetrics(
                narrow: narrow,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (title != null)
                      Semantics(
                        header: true,
                        child: Text(
                          title!,
                          style: t.textN.copyWith(
                            color: c.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (lede != null)
                      Padding(
                        padding: const EdgeInsets.only(top: LgSpace.s1),
                        child: Text(
                          lede!,
                          style: t.textM.copyWith(color: c.text2),
                        ),
                      ),
                    if (lockBar != null)
                      Padding(
                        padding: EdgeInsets.only(
                          top: title == null ? 0 : LgSpace.s4,
                        ),
                        child: lockBar,
                      ),
                    LgSettingsDimmed(
                      dimmed: locked,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, child) in children.indexed) ...[
                            SizedBox(
                              height: i == 0
                                  ? (title == null && lockBar == null
                                        ? 0
                                        : LgSpace.s4)
                                  : gapBetween(children[i - 1], child),
                            ),
                            child,
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Scrolling extends StatefulWidget {
  const _Scrolling({required this.controller, required this.child});

  final ScrollController? controller;
  final Widget child;

  @override
  State<_Scrolling> createState() => _ScrollingState();
}

class _ScrollingState extends State<_Scrolling> {
  ScrollController? _own;

  ScrollController get _controller =>
      widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        padding: const EdgeInsets.fromLTRB(
          0,
          LgSpace.s4,
          LgSpace.s2,
          LgSpace.s7,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Dims what is under it to 60 % and keeps pointer and keyboard out of it: the
/// controls below a lock bar (`.s-lk`), the rows of a block that something else
/// overrules (`.s-b.dis`), the control of a row that does not apply. The tree
/// stays the same whether [dimmed] or not, so what the controls hold (typing,
/// focus) survives. A screen reader still finds the controls; the page disables
/// them.
class LgSettingsDimmed extends StatelessWidget {
  const LgSettingsDimmed({
    super.key,
    required this.dimmed,
    required this.child,
  });

  final bool dimmed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? .6 : 1,
      child: IgnorePointer(
        ignoring: dimmed,
        child: ExcludeFocus(excluding: dimmed, child: child),
      ),
    );
  }
}

// ---- lock bar -----------------------------------------------------------------

/// The bar at the top of a locked section (`.s-lock`): the lock, what it means,
/// and the button that unlocks. The button carries the shield icon: it asks
/// for administrator permission (02 §3.4). When asking failed, the line that
/// says so is under the bar ([error]).
class LgSettingsLockBar extends StatelessWidget {
  const LgSettingsLockBar({
    super.key,
    required this.text,
    required this.unlockLabel,
    required this.onUnlock,
    this.error,
    this.busy = false,
    this.focusNode,
    this.unlockIcon = LgIcons.uac,
  });

  /// "已锁定。修改这些设置需要管理员权限。"
  final String text;

  /// "解锁".
  final String unlockLabel;
  final VoidCallback? onUnlock;

  /// "未获得管理员权限，设置仍处于锁定状态" — shown under the bar.
  final String? error;

  /// The unlock is being asked for (the request is on its way).
  final bool busy;
  final FocusNode? focusNode;

  /// The shield by default (the icon `uac`).
  final LgIcons unlockIcon;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(
              LgSpace.s4,
              LgSpace.s2,
              LgSpace.s2,
              LgSpace.s2,
            ),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(LgRadius.r12),
            ),
            child: Row(
              children: [
                LgIcon(LgIcons.lock, size: 20, color: c.accent),
                const SizedBox(width: LgSpace.s3),
                Expanded(
                  child: Text(text, style: t.textM.copyWith(color: c.text)),
                ),
                const SizedBox(width: LgSpace.s3),
                LgButton(
                  label: unlockLabel,
                  icon: unlockIcon,
                  kind: LgButtonKind.primary,
                  busy: busy,
                  focusNode: focusNode,
                  onPressed: onUnlock,
                ),
              ],
            ),
          ),
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(
                  top: LgSpace.s2,
                  left: LgSpace.s4,
                ),
                child: LgFieldError(error!),
              ),
            ),
        ],
      ),
    );
  }
}
