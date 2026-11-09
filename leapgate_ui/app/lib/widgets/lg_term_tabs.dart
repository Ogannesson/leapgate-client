// The tabs of the terminals of one device, in the title bar of the terminal view (13 §2.2.2 block
// A, R3-Q8; `.tts`, `.tt`, `.tcl` and `.tts.ov` of `A-P9-终端.html`). One step lighter than the
// session tabs of the window: a light rounded block, the selected one on a deeper ground, bold,
// with a short accent line at its foot.
//
// Only draws: the tabs, their texts and the callbacks are the caller's (`LEAPGATE.md` §10.18).

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_menu.dart';
import 'lg_pressable.dart';
import 'lg_tooltip.dart';
import 'lg_view_bar.dart';

/// One tab: the name ("终端 2") and the name of its close button ("关闭终端 2"; the mockup says
/// "关闭终端" on all of them, which leaves a script and a reader nothing to tell them apart by).
class LgTermTabItem {
  const LgTermTabItem({required this.label, required this.closeLabel});

  final String label;
  final String closeLabel;
}

/// The tab strip with its "新建终端" and, when the tabs do not fit, "全部终端".
///
/// Put it in [LgViewBar.middle]; it takes the width that is left. The tabs stay as wide as they
/// are and scroll sideways (the wheel, or by keeping the selected one in view), the edges that
/// have more behind them fade out, and a button that opens the list of every tab appears before
/// "+". [onNew] null greys "+" (the connection is not up yet). The selected tab is brought into
/// view whenever [selected] changes.
///
/// The strip is a tab list for a screen reader (named [semanticLabel], "终端"); each tab and each
/// close button is a button of its own, the selected tab says so.
class LgTermTabs extends StatefulWidget {
  const LgTermTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    required this.onNew,
    required this.semanticLabel,
    required this.newLabel,
    required this.allLabel,
    this.newTooltip,
    this.closeTooltip,
    this.closeEnabled = true,
  });

  final List<LgTermTabItem> tabs;
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback? onNew;

  /// "关闭终端（Ctrl+Shift+W）": what the pointer shows on each close button; none when null.
  /// The name a reader gets stays the tab's [LgTermTabItem.closeLabel].
  final String? closeTooltip;

  /// False greys every close button (the connection is down: a remote terminal cannot be
  /// closed); the tabs can still be selected.
  final bool closeEnabled;

  /// "终端": the name of the strip.
  final String semanticLabel;

  /// "新建终端": the name of "+".
  final String newLabel;

  /// "新建终端（Ctrl+Shift+T）": what the pointer shows on "+"; [newLabel] when null.
  final String? newTooltip;

  /// "全部终端": the name of the button that lists every tab.
  final String allLabel;

  @override
  State<LgTermTabs> createState() => _LgTermTabsState();
}

class _LgTermTabsState extends State<LgTermTabs> {
  final _scroll = ScrollController();
  final _selectedKey = GlobalKey();
  bool _overflow = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _bringSelectedIntoView();
  }

  @override
  void didUpdateWidget(LgTermTabs old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected ||
        old.tabs.length != widget.tabs.length) {
      _bringSelectedIntoView();
    }
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() => setState(() {});

  void _bringSelectedIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final box = _selectedKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) return;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) return;
      // 28 px at either end fade out: a tab under the fade is not in view.
      final rect = box.paintBounds.inflate(_fade);
      final toStart = viewport.getOffsetToReveal(box, 0, rect: rect).offset;
      final toEnd = viewport.getOffsetToReveal(box, 1, rect: rect).offset;
      final position = _scroll.position;
      final offset = position.pixels;
      double? target;
      if (offset > toStart) {
        target = toStart;
      } else if (offset < toEnd) {
        target = toEnd;
      }
      if (target == null) return;
      target = target.clamp(0.0, position.maxScrollExtent);
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      final d = e as PointerScrollEvent;
      final delta = d.scrollDelta.dx != 0 ? d.scrollDelta.dx : d.scrollDelta.dy;
      final position = _scroll.position;
      _scroll.jumpTo(
        (position.pixels + delta).clamp(0.0, position.maxScrollExtent),
      );
    });
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    final over = n.metrics.maxScrollExtent > .5;
    if (over != _overflow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _overflow = over);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final measured =
        _scroll.hasClients && _scroll.position.hasContentDimensions;
    final canLeft = measured && _scroll.offset > .5;
    final canRight =
        measured && _scroll.offset < _scroll.position.maxScrollExtent - .5;
    Widget strip = SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, tab) in widget.tabs.indexed) ...[
            if (i > 0) const SizedBox(width: LgSpace.s1),
            _Tab(
              key: i == widget.selected ? _selectedKey : null,
              item: tab,
              selected: i == widget.selected,
              onSelect: () => widget.onSelect(i),
              onClose: widget.closeEnabled ? () => widget.onClose(i) : null,
              closeTooltip: widget.closeTooltip,
            ),
          ],
        ],
      ),
    );
    if (_overflow && (canLeft || canRight)) {
      strip = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          final f = math.min(_fade / math.max(bounds.width, 1), .5);
          return LinearGradient(
            colors: [
              canLeft ? Colors.transparent : Colors.black,
              Colors.black,
              Colors.black,
              canRight ? Colors.transparent : Colors.black,
            ],
            stops: [0, f, 1 - f, 1],
          ).createShader(bounds);
        },
        child: strip,
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticLabel,
      child: Listener(
        onPointerSignal: _wheel,
        child: Row(
          children: [
            Flexible(
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: _onMetrics,
                child: ClipRect(child: strip),
              ),
            ),
            if (_overflow) ...[
              const SizedBox(width: LgSpace.s2),
              LgMenuAnchor(
                width: 200,
                items: [
                  for (final (i, tab) in widget.tabs.indexed)
                    LgMenuItem(
                      label: tab.label,
                      checked: i == widget.selected,
                      onPressed: () => widget.onSelect(i),
                    ),
                ],
                builder: (context, controller) => LgBarIconButton(
                  icon: LgIcons.chevD,
                  label: widget.allLabel,
                  open: controller.isOpen,
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                ),
              ),
            ],
            const SizedBox(width: LgSpace.s2),
            LgBarIconButton(
              icon: LgIcons.plus,
              label: widget.newLabel,
              tooltip: widget.newTooltip,
              onPressed: widget.onNew,
            ),
          ],
        ),
      ),
    );
  }
}

const double _fade = 28;

/// One tab (`.tt`): the label and the close button, 36 high (`--lg-h-btn`), the close button
/// 28 square (24 in the detail mode) inside the right padding. The tab and its close button are
/// two controls that overlap, not one inside the other, so that each has a node of its own.
class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.item,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    this.closeTooltip,
  });

  final LgTermTabItem item;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onClose;
  final String? closeTooltip;

  Widget _withTooltip(Widget child) {
    final tip = closeTooltip;
    return tip == null ? child : LgTooltip(message: tip, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r10);
    final closeSide = t.detail ? 24.0 : 28.0;
    return Stack(
      children: [
        LgPressable(
          onPressed: onSelect,
          semanticLabel: item.label,
          selected: selected,
          builder: (context, states) {
            final overlay = selected ? null : lgStateOverlay(c, states);
            return LgFocusRing(
              show: states.contains(WidgetState.focused),
              radius: radius,
              child: Stack(
                children: [
                  Container(
                    height: t.sizes.button,
                    // 12 before the label; after it the 4 px gap, the close button and 4 px.
                    padding: EdgeInsets.only(
                      left: LgSpace.s3,
                      right: LgSpace.s1 + closeSide + LgSpace.s1,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? c.surface2 : overlay,
                      borderRadius: radius,
                    ),
                    child: ExcludeSemantics(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        softWrap: false,
                        style: t.text.copyWith(
                          color: selected ? c.text : c.text2,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  // `.tt.sel::after`: 12 px in from either side, 3 px above the foot.
                  if (selected)
                    Positioned(
                      left: LgSpace.s3,
                      right: LgSpace.s3,
                      bottom: 3,
                      height: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        Positioned(
          right: LgSpace.s1,
          top: (t.sizes.button - closeSide) / 2,
          child: _withTooltip(
            LgPressable(
              onPressed: onClose,
              semanticLabel: item.closeLabel,
              builder: (context, states) => Opacity(
                // Greyed as the bar's other icon buttons are.
                opacity: states.contains(WidgetState.disabled) ? .45 : 1,
                child: LgFocusRing(
                  show: states.contains(WidgetState.focused),
                  radius: BorderRadius.circular(LgRadius.r6),
                  child: Container(
                    width: closeSide,
                    height: closeSide,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: lgStateOverlay(c, states),
                      borderRadius: BorderRadius.circular(LgRadius.r6),
                    ),
                    child: LgIcon(LgIcons.x, size: 14, color: c.text2),
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
