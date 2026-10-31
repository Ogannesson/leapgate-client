// The device card of the device page and of the connection box's results
// (01 §3.1 block F; `.card`, `.grid` in A-基础.html, `p1-card-*` in A-P1.html),
// its placeholder while the list loads, and the grid that lays cards out, at
// least 300 px wide each.
//
// The cards only draw: all text comes from the caller (localised) and nothing
// here knows the peer model or the session.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_device.dart';
import 'lg_device_parts.dart';
import 'lg_pressable.dart';
import 'lg_status.dart';
import 'lg_tooltip.dart';

/// Height of a card; the columns grow, the height does not.
const double kLgDeviceCardHeight = 112;

/// Narrowest a card gets (01 block F); the grid makes fewer, wider columns
/// rather than narrower ones.
const double kLgDeviceCardMinWidth = 300;

/// A device as a card (`.card`): the platform tile, the name with its marks,
/// `user@host`, the online state, and the tags at the right.
///
/// A click selects ([onTap]), a double click or Enter connects ([onDoubleTap],
/// [onConnect]). While the pointer or the keyboard is on the card, "connect"
/// and "⋯" ([onMore], the device menu) show at its top right corner. With
/// [picked] non-null the card is in multi-select: the corner shows the pick box
/// instead and a click should toggle it ([onTap]). [onContextMenu] gets the
/// right click's position.
class LgDeviceCard extends StatefulWidget {
  const LgDeviceCard({
    super.key,
    required this.name,
    required this.id,
    required this.platform,
    required this.status,
    required this.statusLabel,
    this.userHost,
    this.tags = const [],
    this.source,
    this.favorite = false,
    this.savedPassword = false,
    this.favoriteLabel,
    this.savedPasswordLabel,
    this.selected = false,
    this.picked,
    this.onTap,
    this.onDoubleTap,
    this.onConnect,
    this.connectLabel,
    this.onMore,
    this.moreLabel,
    this.onContextMenu,
    this.focusNode,
    this.autofocus = false,
  }) : assert(onConnect == null || connectLabel != null),
       assert(onMore == null || moreLabel != null);

  final String name;

  /// Formatted ID ("123 456 789").
  final String id;
  final LgPlatform platform;
  final LgDeviceStatus status;

  /// "在线", "离线", "正在查询…".
  final String statusLabel;
  final String? userHost;
  final List<LgDeviceTag> tags;

  /// The category the device came from, in search results ("收藏").
  final String? source;
  final bool favorite;
  final bool savedPassword;

  /// Names of the two marks, for hover and for a screen reader.
  final String? favoriteLabel;
  final String? savedPasswordLabel;
  final bool selected;

  /// Null outside multi-select.
  final bool? picked;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onConnect;
  final String? connectLabel;
  final VoidCallback? onMore;
  final String? moreLabel;
  final ValueChanged<Offset>? onContextMenu;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<LgDeviceCard> createState() => _LgDeviceCardState();
}

class _LgDeviceCardState extends State<LgDeviceCard> {
  static const _doubleClick = Duration(milliseconds: 300);
  Duration? _lastDown;
  bool _within = false;

  void _onPointerDown(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    final last = _lastDown;
    if (last != null && e.timeStamp - last <= _doubleClick) {
      _lastDown = null;
      widget.onDoubleTap?.call();
    } else {
      _lastDown = e.timeStamp;
    }
  }

  /// How far the name must stay from the right edge while the two buttons are
  /// there: "connect" (its text and 20 px of padding), a 2 px gap, "⋯" (36 px),
  /// and the 12 px margin.
  double _reserve(LgTokens t) {
    final w = widget;
    var width = 0.0;
    if (w.onConnect != null) {
      final painter = TextPainter(
        text: TextSpan(
          text: w.connectLabel,
          style: t.text.copyWith(fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      width += painter.width + 20;
      painter.dispose();
    }
    if (w.onMore != null) width += t.sizes.button + (width > 0 ? 2 : 0);
    return width == 0 ? 0 : width + LgSpace.s3 + LgSpace.s2;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r16);
    final pickMode = w.picked != null;
    final label = lgDeviceLabel(
      name: w.name,
      statusLabel: w.statusLabel,
      id: w.id,
      userHost: w.userHost,
      source: w.source,
      tags: w.tags,
      favorite: w.favorite,
      favoriteLabel: w.favoriteLabel,
      savedPassword: w.savedPassword,
      savedPasswordLabel: w.savedPasswordLabel,
    );
    final actions = <CustomSemanticsAction, VoidCallback>{
      if (w.onConnect != null)
        CustomSemanticsAction(label: w.connectLabel!): w.onConnect!,
      if (w.onMore != null) CustomSemanticsAction(label: w.moreLabel!): w.onMore!,
    };
    final card = LgPressable(
      onPressed: w.onTap ?? w.onConnect,
      onActivate: w.onConnect ?? w.onTap,
      onSecondaryTapUp: w.onContextMenu == null
          ? null
          : (d) => w.onContextMenu!(d.globalPosition),
      focusNode: w.focusNode,
      autofocus: w.autofocus,
      selected: w.selected || w.picked == true,
      semanticLabel: label,
      builder: (context, states) {
        final hot =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        final focused = states.contains(WidgetState.focused);
        final on = w.selected || w.picked == true;
        final showActions = !pickMode && (hot || focused || _within);
        final Color base;
        if (on) {
          base = Color.alphaBlend(c.active, c.surface);
        } else {
          base = hot && !pickMode ? c.float : c.surface;
        }
        final reserve = showActions ? _reserve(t) : 0.0;
        final pickReserve = pickMode ? 24 + LgSpace.s3 : 0.0;
        return LgFocusRing(
          show: focused,
          radius: radius,
          child: Container(
            height: kLgDeviceCardHeight,
            decoration: BoxDecoration(
              color: base,
              borderRadius: radius,
              boxShadow: hot && !on && !pickMode ? c.shadow : null,
            ),
            foregroundDecoration: on
                ? BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: c.accent, width: 2),
                  )
                : null,
            child: Stack(
              children: [
                ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.all(LgSpace.s4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        LgDeviceAvatar(id: w.id, platform: w.platform),
                        const SizedBox(width: LgSpace.s3),
                        Expanded(
                          child: _Body(
                            card: w,
                            nameReserve: math.max(reserve - LgSpace.s4, 0) +
                                pickReserve,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (pickMode)
                  Positioned(
                    right: LgSpace.s4,
                    top: LgSpace.s4,
                    child: LgPickBox(picked: w.picked!),
                  ),
                if (showActions && (w.onConnect != null || w.onMore != null))
                  Positioned(
                    right: LgSpace.s3,
                    top: LgSpace.s3,
                    child: _CardActions(card: w),
                  ),
              ],
            ),
          ),
        );
      },
    );
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (v) {
        if (_within != v) setState(() => _within = v);
      },
      child: Listener(
        onPointerDown: _onPointerDown,
        child: actions.isEmpty
            ? card
            : Semantics(customSemanticsActions: actions, child: card),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.card, required this.nameReserve});

  final LgDeviceCard card;
  final double nameReserve;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final status = switch (card.status) {
      LgDeviceStatus.online => LgStatus.online,
      LgDeviceStatus.offline => LgStatus.offline,
      LgDeviceStatus.querying => LgStatus.querying,
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(right: nameReserve),
          child: Row(
            children: [
              Flexible(
                child: LgEllipsisText(
                  card.name,
                  style: t.textN.copyWith(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              LgDeviceMarks(
                favorite: card.favorite,
                savedPassword: card.savedPassword,
                favoriteLabel: card.favoriteLabel,
                savedPasswordLabel: card.savedPasswordLabel,
              ),
            ],
          ),
        ),
        if (card.userHost != null)
          LgEllipsisText(
            card.userHost!,
            style: t.textS.copyWith(color: c.text2),
          ),
        SizedBox(
          height: 20,
          child: Row(
            children: [
              DefaultTextStyle(
                style: t.textS,
                child: LgStatusText(status, card.statusLabel),
              ),
              if (card.source != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    card.source!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textS.copyWith(color: c.text2),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: LgTagChips(card.tags, spacing: 10, alignEnd: true),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Connect" (a soft button) and "⋯" (an icon button) at the corner of a
/// card. "Connect" stays out of the Tab order, the card itself takes Enter;
/// "⋯" is reachable with Tab once the card has the focus, because the card then
/// shows it. Each is its own node for a screen reader and a UI Automation
/// script, next to the card's own.
class _CardActions extends StatelessWidget {
  const _CardActions({required this.card});

  final LgDeviceCard card;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (card.onConnect != null)
          Semantics(
            container: true,
            child: LgPressable(
              onPressed: card.onConnect,
              focusable: false,
              semanticLabel: '${card.connectLabel} ${card.name}',
              builder: (context, states) {
                final overlay = lgStateOverlay(c, states);
                return ExcludeSemantics(
                  child: Container(
                    height: t.sizes.button,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: overlay == null
                          ? c.surface2
                          : Color.alphaBlend(overlay, c.surface2),
                      borderRadius: BorderRadius.circular(LgRadius.r10),
                    ),
                    child: Text(
                      card.connectLabel!,
                      maxLines: 1,
                      softWrap: false,
                      style: t.text.copyWith(
                        color: c.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        if (card.onConnect != null && card.onMore != null)
          const SizedBox(width: 2),
        if (card.onMore != null)
          Semantics(
            container: true,
            child: LgPressable(
              onPressed: card.onMore,
              semanticLabel: '${card.moreLabel} ${card.name}',
              builder: (context, states) {
                final radius = BorderRadius.circular(LgRadius.r10);
                return ExcludeSemantics(
                  child: LgFocusRing(
                    show: states.contains(WidgetState.focused),
                    radius: radius,
                    child: Container(
                      width: t.sizes.button,
                      height: t.sizes.button,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: lgStateOverlay(c, states),
                        borderRadius: radius,
                      ),
                      child: LgIcon(
                        LgIcons.more,
                        size: t.sizes.icon,
                        color: c.text2,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// A card shape while the first answer is on its way (`.card.skc`). Still, so
/// that it does not ask for attention; [semanticLabel] tells a screen reader
/// that the list is loading (give it to one of them, or to the grid).
class LgDeviceCardSkeleton extends StatelessWidget {
  const LgDeviceCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    Widget bar(double? width) => Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(LgRadius.r6),
      ),
    );
    return ExcludeSemantics(
      child: Container(
        height: kLgDeviceCardHeight,
        padding: const EdgeInsets.all(LgSpace.s4),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(LgRadius.r16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(LgRadius.r12),
              ),
            ),
            const SizedBox(width: LgSpace.s3),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(144),
                  const SizedBox(height: LgSpace.s2),
                  bar(null),
                  const SizedBox(height: LgSpace.s2),
                  bar(84),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The columns of the card grid: as many as fit with each at least
/// [minWidth] wide and [gap] between them; the cards share what is left. Give
/// it to a `SliverGrid` or a `GridView` to lay out a long list lazily.
class LgDeviceCardGridDelegate extends SliverGridDelegate {
  const LgDeviceCardGridDelegate({
    this.minWidth = kLgDeviceCardMinWidth,
    this.gap = LgSpace.s3,
    this.height = kLgDeviceCardHeight,
  });

  final double minWidth;
  final double gap;
  final double height;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width = constraints.crossAxisExtent;
    final count = math.max(1, ((width + gap) / (minWidth + gap)).floor());
    final tile = (width - gap * (count - 1)) / count;
    return SliverGridRegularTileLayout(
      crossAxisCount: count,
      mainAxisStride: height + gap,
      crossAxisStride: tile + gap,
      childMainAxisExtent: height,
      childCrossAxisExtent: tile,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(LgDeviceCardGridDelegate old) =>
      old.minWidth != minWidth || old.gap != gap || old.height != height;
}

/// Cards laid out in the grid, as tall as they are (no scrolling of its own:
/// put it in the page's scroll view).
class LgDeviceCardGrid extends StatelessWidget {
  const LgDeviceCardGrid({super.key, required this.children, this.semanticLabel});

  final List<Widget> children;

  /// Name of the list for a screen reader ("最近连接的设备").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: GridView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const LgDeviceCardGridDelegate(),
        itemCount: children.length,
        itemBuilder: (context, i) => children[i],
      ),
    );
  }
}
