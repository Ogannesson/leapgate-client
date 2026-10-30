// Custom title bar with the in-app tabs (01 §2.1, 03 §4.4; `.topbar`, `.tab`,
// `.winctl` in A-基础.html). Window behaviour is left to the caller through
// callbacks, so this file does not depend on window_manager. While the window
// is full screen the caller leaves the bar out entirely (01 §2.1).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_menu.dart';
import 'lg_pressable.dart';
import 'lg_status.dart';
import 'lg_tooltip.dart';

const double kLgTitleBarHeight = 40;
const double _tabHeight = 32;
const double _captionWidth = 46;

/// Keeps a blank strip before the caption buttons for dragging the window
/// even when the tabs overflow.
const double _minDragGap = LgSpace.s8;

/// Longest tab name before it ends in "…"; the tooltip shows the full name.
const double _maxTabName = 180;

/// Edges resized from inside Flutter. The window has no system title bar, so
/// the top edge needs a Flutter drag area; the other edges keep the native
/// frame (upstream does the same, flutter/lib/common.dart:4048-4054).
enum LgResizeEdge { topLeft, top, topRight }

/// Localised strings of the bar, for semantics and tooltips.
class LgTitleBarLabels {
  const LgTitleBarLabels({
    required this.home,
    required this.newTab,
    required this.allTabs,
    required this.closeTab,
    required this.minimize,
    required this.maximize,
    required this.restore,
    required this.close,
  });

  final String home;
  final String newTab;
  final String allTabs;
  final String closeTab;
  final String minimize;
  final String maximize;
  final String restore;
  final String close;
}

/// One session tab: one device (01 §2.1).
class LgSessionTab {
  const LgSessionTab({
    required this.name,
    required this.identity,
    this.status,
    this.unread = 0,
    this.disconnected = false,
    this.tooltip,
  });

  final String name;

  /// Identity colour group 0..6 of the device ID (top strip).
  final int identity;

  /// Usually an [LgRouteMark] or [LgStatusText]; drawn at the small size.
  final Widget? status;

  /// Unread chat messages.
  final int unread;

  /// Greys the device name (`.tab.gone`).
  final bool disconnected;

  /// Hover content: full name, ID, connection method of each open view.
  final Widget? tooltip;
}

class LgTitleBar extends StatefulWidget {
  const LgTitleBar({
    super.key,
    required this.labels,
    required this.sessions,
    required this.selected,
    required this.onSelect,
    required this.onCloseTab,
    required this.onNewTab,
    required this.maximized,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
    required this.onStartDrag,
    required this.onStartResize,
    this.homeBadge = 0,
    this.onTabContextMenu,
  });

  final LgTitleBarLabels labels;
  final List<LgSessionTab> sessions;

  /// Selected tab: 0 is the home tab, 1.. are [sessions].
  final int selected;
  final ValueChanged<int> onSelect;

  /// Called with the tab index (1..); the home tab cannot be closed.
  final ValueChanged<int> onCloseTab;
  final VoidCallback onNewTab;

  /// Background connections shown on the home tab (exit nodes, 01 §2.1).
  final int homeBadge;

  /// Right click on a tab: tab index and global pointer position.
  final void Function(int index, Offset globalPosition)? onTabContextMenu;

  final bool maximized;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;

  /// Pointer pressed on blank title bar space: start moving the window.
  final VoidCallback onStartDrag;
  final ValueChanged<LgResizeEdge> onStartResize;

  @override
  State<LgTitleBar> createState() => _LgTitleBarState();
}

class _LgTitleBarState extends State<LgTitleBar> {
  final _scroll = ScrollController();
  final _tabKeys = <GlobalKey>[];
  bool _overflow = false;

  @override
  void didUpdateWidget(LgTitleBar old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected ||
        old.sessions.length != widget.sessions.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealSelected() {
    if (!mounted || widget.selected >= _tabKeys.length) return;
    final ctx = _tabKeys[widget.selected].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 150),
        alignment: .5,
      );
    }
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    final overflow = n.metrics.maxScrollExtent > 0;
    if (overflow != _overflow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _overflow = overflow);
      });
    }
    return false;
  }

  // A vertical wheel scrolls the tab strip sideways.
  void _onWheel(PointerSignalEvent e) {
    if (e is PointerScrollEvent &&
        e.scrollDelta.dx == 0 &&
        _scroll.hasClients) {
      final p = _scroll.position;
      _scroll.jumpTo(
        (p.pixels + e.scrollDelta.dy).clamp(
          p.minScrollExtent,
          p.maxScrollExtent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final labels = widget.labels;
    final count = widget.sessions.length + 1;
    while (_tabKeys.length < count) {
      _tabKeys.add(GlobalKey());
    }
    _tabKeys.length = count;

    final tabs = <Widget>[
      _Tab(
        key: _tabKeys[0],
        name: labels.home,
        selected: widget.selected == 0,
        strip: widget.selected == 0 ? c.accent : null,
        badge: widget.homeBadge,
        onSelect: () => widget.onSelect(0),
        onContextMenu: null,
      ),
      for (final (i, s) in widget.sessions.indexed)
        _Tab(
          key: _tabKeys[i + 1],
          name: s.name,
          selected: widget.selected == i + 1,
          strip: c.identity[s.identity].solid,
          status: s.status,
          badge: s.unread,
          disconnected: s.disconnected,
          tooltip: s.tooltip,
          closeLabel: labels.closeTab,
          onSelect: () => widget.onSelect(i + 1),
          onClose: () => widget.onCloseTab(i + 1),
          onContextMenu: widget.onTabContextMenu == null
              ? null
              : (p) => widget.onTabContextMenu!(i + 1, p),
        ),
    ];

    final strip = NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: Listener(
        onPointerSignal: _onWheel,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, tab) in tabs.indexed) ...[
                if (i > 0) const SizedBox(width: 2),
                tab,
              ],
            ],
          ),
        ),
      ),
    );

    final tabsArea = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(child: strip),
        const SizedBox(width: 2),
        LgIconButton(
          icon: LgIcons.plus,
          label: labels.newTab,
          size: _tabHeight,
          onPressed: widget.onNewTab,
        ),
        if (_overflow)
          LgMenuAnchor(
            items: [
              for (var i = 0; i < count; i++)
                LgMenuItem(
                  label: i == 0 ? labels.home : widget.sessions[i - 1].name,
                  checked: i == widget.selected,
                  onPressed: () => widget.onSelect(i),
                ),
            ],
            builder: (context, controller) => LgIconButton(
              icon: LgIcons.chevD,
              label: labels.allTabs,
              size: _tabHeight,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
      ],
    );

    return SizedBox(
      height: kLgTitleBarHeight,
      child: Stack(
        children: [
          // Blank space: everything below that is not a control.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => widget.onStartDrag(),
              onDoubleTap: widget.onToggleMaximize,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Placeholder app mark (`.appmark`), no interaction.
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                decoration: BoxDecoration(
                  color: c.borderStrong,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Expanded(
                child: SizedBox(height: kLgTitleBarHeight, child: tabsArea),
              ),
              const SizedBox(width: _minDragGap),
              _CaptionButton(
                icon: LgIcons.windowMin,
                label: labels.minimize,
                onPressed: widget.onMinimize,
              ),
              _CaptionButton(
                icon: widget.maximized
                    ? LgIcons.windowRestore
                    : LgIcons.windowMax,
                label: widget.maximized ? labels.restore : labels.maximize,
                onPressed: widget.onToggleMaximize,
              ),
              _CaptionButton(
                icon: LgIcons.windowClose,
                label: labels.close,
                onPressed: widget.onClose,
                close: true,
              ),
            ],
          ),
          if (!widget.maximized) ...[
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              height: 4,
              child: _ResizeZone(
                LgResizeEdge.top,
                SystemMouseCursors.resizeUp,
                widget.onStartResize,
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: 8,
              height: 4,
              child: _ResizeZone(
                LgResizeEdge.topLeft,
                SystemMouseCursors.resizeUpLeft,
                widget.onStartResize,
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              width: 8,
              height: 4,
              child: _ResizeZone(
                LgResizeEdge.topRight,
                SystemMouseCursors.resizeUpRight,
                widget.onStartResize,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResizeZone extends StatelessWidget {
  const _ResizeZone(this.edge, this.cursor, this.onStart);

  final LgResizeEdge edge;
  final MouseCursor cursor;
  final ValueChanged<LgResizeEdge> onStart;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: cursor,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => onStart(edge),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.name,
    required this.selected,
    required this.strip,
    required this.onSelect,
    required this.onContextMenu,
    this.status,
    this.badge = 0,
    this.disconnected = false,
    this.tooltip,
    this.closeLabel,
    this.onClose,
  });

  final String name;
  final bool selected;
  final Color? strip;
  final Widget? status;
  final int badge;
  final bool disconnected;
  final Widget? tooltip;
  final String? closeLabel;
  final VoidCallback onSelect;
  final VoidCallback? onClose;
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    const radius = BorderRadius.vertical(top: Radius.circular(LgRadius.r10));
    final tab = LgPressable(
      onPressed: onSelect,
      selected: selected,
      semanticLabel: name,
      onSecondaryTapUp: onContextMenu == null
          ? null
          : (d) => onContextMenu!(d.globalPosition),
      builder: (context, states) {
        final overlay = selected ? null : lgStateOverlay(c, states);
        final nameColor = disconnected
            ? c.offline
            : (selected ? c.text : c.text2);
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Stack(
            children: [
              Container(
                height: _tabHeight,
                padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
                decoration: BoxDecoration(
                  color: selected ? c.surface : overlay,
                  borderRadius: radius,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: _maxTabName),
                      child: Text(
                        name,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.copyWith(
                          color: nameColor,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (status != null) ...[
                      const SizedBox(width: LgSpace.s2),
                      DefaultTextStyle(
                        style: t.textS.copyWith(color: c.text2),
                        child: status!,
                      ),
                    ],
                    if (badge > 0) ...[
                      const SizedBox(width: LgSpace.s2),
                      LgBadge(badge),
                    ],
                    if (onClose != null) ...[
                      const SizedBox(width: LgSpace.s2 - 2),
                      LgIconButton(
                        icon: LgIcons.x,
                        label: closeLabel!,
                        size: 20,
                        iconSize: 16,
                        focusable: false,
                        onPressed: onClose,
                      ),
                    ],
                  ],
                ),
              ),
              if (strip != null)
                Positioned(
                  left: LgSpace.s3,
                  right: LgSpace.s3,
                  top: 0,
                  height: LgFixed.strip,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: strip,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(3),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
    return tooltip == null ? tab : LgTooltip(content: tooltip, child: tab);
  }
}

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.close = false,
  });

  final LgIcons icon;
  final String label;
  final VoidCallback onPressed;
  final bool close;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    // Caption buttons stay out of the Tab order, as in Windows.
    return LgPressable(
      onPressed: onPressed,
      focusable: false,
      semanticLabel: label,
      builder: (context, states) {
        final hot =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        final Color? bg;
        if (close && hot) {
          bg = states.contains(WidgetState.pressed)
              ? Color.alphaBlend(c.hover, c.winClose)
              : c.winClose;
        } else {
          bg = lgStateOverlay(c, states);
        }
        return Container(
          width: _captionWidth,
          height: kLgTitleBarHeight,
          color: bg,
          alignment: Alignment.center,
          child: LgIcon(
            icon,
            size: 10,
            color: close && hot ? c.onWinClose : c.text,
          ),
        );
      },
    );
  }
}
