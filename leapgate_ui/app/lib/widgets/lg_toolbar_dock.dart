// Where the session toolbar sits: on which edge of the picture and how far
// along it (01 §3.2 block B; `s-drag`, `s-dock-left` in A-P2.html). This file
// holds the types, the layer that places the toolbar and follows the drag of
// its grip, and the grip itself. The rules that decide where the toolbar may
// go and what is remembered are the caller's: the layer reports the pointer as
// a candidate place and draws what it is told.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';
import 'lg_tooltip.dart';

/// The edge of the picture the toolbar hangs on. On the left and right edges the
/// bar runs up and down and shows icons only.
enum LgToolbarDock {
  top,
  bottom,
  left,
  right;

  bool get vertical => this == left || this == right;
}

/// An edge and a place along it: [position] is 0 at the start of the edge
/// (left, or top) and 1 at its end; the middle of the bar is put there, and
/// the bar stays inside the edge.
@immutable
class LgToolbarPlacement {
  const LgToolbarPlacement(this.dock, [this.position = .5])
    : assert(position >= 0 && position <= 1);

  final LgToolbarDock dock;
  final double position;

  LgToolbarPlacement copyWith({LgToolbarDock? dock, double? position}) =>
      LgToolbarPlacement(dock ?? this.dock, position ?? this.position);

  /// The place for a pointer at [local] in a picture of [area]: the nearest
  /// edge when [anyEdge], else [current]; the position is the pointer's share
  /// along that edge, less [grab] (how far from the middle of the bar it took
  /// hold of the grip).
  static LgToolbarPlacement nearest(
    Offset local,
    Size area, {
    required bool anyEdge,
    LgToolbarDock current = LgToolbarDock.top,
    double grab = 0,
  }) {
    var dock = current;
    if (anyEdge) {
      final distances = {
        LgToolbarDock.top: local.dy,
        LgToolbarDock.bottom: area.height - local.dy,
        LgToolbarDock.left: local.dx,
        LgToolbarDock.right: area.width - local.dx,
      };
      dock = distances.entries.reduce((a, b) => b.value < a.value ? b : a).key;
    }
    final along = dock.vertical
        ? local.dy / math.max(1, area.height)
        : local.dx / math.max(1, area.width);
    return LgToolbarPlacement(
      dock,
      (along - (dock == current ? grab : 0)).clamp(0.0, 1.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LgToolbarPlacement &&
      other.dock == dock &&
      other.position == position;

  @override
  int get hashCode => Object.hash(dock, position);
}

/// Tells the buttons of a toolbar on which edge it sits, so that a menu button
/// can show only its icon on a vertical bar and open its menu to the side.
class LgToolbarScope extends InheritedWidget {
  const LgToolbarScope({super.key, required this.dock, required super.child});

  final LgToolbarDock dock;

  static LgToolbarDock of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LgToolbarScope>()?.dock ??
      LgToolbarDock.top;

  @override
  bool updateShouldNotify(LgToolbarScope old) => old.dock != dock;
}

/// What the grip of a toolbar calls while it is dragged or moved with the
/// keys. Given by [LgToolbarPlacer]; a toolbar outside a placer has no grip.
class LgToolbarDragScope extends InheritedWidget {
  const LgToolbarDragScope({
    super.key,
    required this.dragging,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onNudge,
    required super.child,
  });

  /// True from the start of a drag to its end: the bar is drawn lifted.
  final bool dragging;
  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;

  /// Moves the bar along its edge by a step: -1 toward the start, 1 toward
  /// the end.
  final ValueChanged<int> onNudge;

  static LgToolbarDragScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LgToolbarDragScope>();

  @override
  bool updateShouldNotify(LgToolbarDragScope old) => old.dragging != dragging;
}

/// The six dots that move the bar (`.ti.ico.dim` with the grip icon). It takes
/// the drag of a pointer and, with the focus, the arrow keys. Shown only inside
/// an [LgToolbarPlacer].
class LgToolbarGrip extends StatelessWidget {
  const LgToolbarGrip({super.key, required this.label});

  /// Accessible name and tooltip ("移动工具栏").
  final String label;

  @override
  Widget build(BuildContext context) {
    final scope = LgToolbarDragScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final t = LgTokens.of(context);
    final c = t.colors;
    final dock = LgToolbarScope.of(context);
    return LgTooltip(
      message: label,
      child: _GripKeys(
        scope: scope,
        vertical: dock.vertical,
        child: LgPressable(
          // A click does nothing: the grip is for dragging.
          onPressed: () {},
          semanticLabel: label,
          builder: (context, states) {
            final radius = BorderRadius.circular(LgRadius.r12);
            return MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => scope.onStart(d.globalPosition),
                onPanUpdate: (d) => scope.onUpdate(d.globalPosition),
                onPanEnd: (_) => scope.onEnd(),
                onPanCancel: scope.onEnd,
                child: LgFocusRing(
                  show: states.contains(WidgetState.focused),
                  radius: radius,
                  child: Container(
                    height: t.sizes.tool,
                    constraints: BoxConstraints(minWidth: t.sizes.tool),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: lgStateOverlay(c, states),
                      borderRadius: radius,
                    ),
                    child: ExcludeSemantics(
                      child: LgIcon(
                        LgIcons.grip,
                        size: t.sizes.icon,
                        color: c.text2,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Arrow keys on the grip move the bar a step along its edge.
class _GripKeys extends StatelessWidget {
  const _GripKeys({
    required this.scope,
    required this.vertical,
    required this.child,
  });

  final LgToolbarDragScope scope;
  final bool vertical;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final back = vertical ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowLeft;
    final forward = vertical
        ? LogicalKeyboardKey.arrowDown
        : LogicalKeyboardKey.arrowRight;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(back): () => scope.onNudge(-1),
        SingleActivator(forward): () => scope.onNudge(1),
      },
      child: child,
    );
  }
}

/// Puts a toolbar on its edge of the picture and follows the drag of its grip.
/// Fill the picture with it (it is a `Positioned.fill` in a stack): the bar sits
/// on the edge of [placement] at its share along it, the ghost of [preview]
/// shows where a drag would drop it.
///
/// While the grip is dragged [onMove] gets the candidate place for the pointer
/// (the nearest edge when [anyEdge]); the caller may move the bar there at once
/// (pass it back as [placement]) or only show the ghost (as [preview]).
/// [onMoveEnd] gets the last candidate when the pointer lets go, or after a key
/// press. Pass [resolve] to turn a pointer position into a place by other
/// rules than "nearest".
class LgToolbarPlacer extends StatefulWidget {
  const LgToolbarPlacer({
    super.key,
    required this.placement,
    required this.child,
    this.preview,
    this.anyEdge = false,
    this.onMove,
    this.onMoveEnd,
    this.resolve,
    this.previewSize,
    this.edgeMargin = LgSpace.s3,
    this.keyStep = .05,
  });

  final LgToolbarPlacement placement;

  /// The bar, an `LgSessionToolbar` with the same dock as [placement].
  final Widget child;
  final LgToolbarPlacement? preview;
  final bool anyEdge;
  final ValueChanged<LgToolbarPlacement>? onMove;
  final ValueChanged<LgToolbarPlacement>? onMoveEnd;
  final LgToolbarPlacement Function(
    Offset local,
    Size area,
    LgToolbarPlacement start,
  )?
  resolve;

  /// The size the ghost has on a given edge; the bar's size there is not known
  /// before it is there. Defaults to about the bar in its two forms.
  final Size Function(LgToolbarDock dock)? previewSize;

  /// Space kept between the bar and the ends of its edge.
  final double edgeMargin;

  /// How far an arrow key moves the bar, as a share of the edge.
  final double keyStep;

  @override
  State<LgToolbarPlacer> createState() => _LgToolbarPlacerState();
}

class _LgToolbarPlacerState extends State<LgToolbarPlacer> {
  bool _dragging = false;
  double _grab = 0;
  late LgToolbarPlacement _start;
  LgToolbarPlacement? _last;

  RenderBox get _box => context.findRenderObject()! as RenderBox;

  double _along(Offset local, Size area, LgToolbarDock dock) => dock.vertical
      ? local.dy / math.max(1, area.height)
      : local.dx / math.max(1, area.width);

  void _begin(Offset global) {
    final area = _box.size;
    final local = _box.globalToLocal(global);
    _start = widget.placement;
    _grab = _along(local, area, _start.dock) - _start.position;
    _last = widget.placement;
    setState(() => _dragging = true);
  }

  void _drag(Offset global) {
    final area = _box.size;
    final local = _box.globalToLocal(global);
    final next =
        widget.resolve?.call(local, area, _start) ??
        LgToolbarPlacement.nearest(
          local,
          area,
          anyEdge: widget.anyEdge,
          current: _start.dock,
          grab: _grab,
        );
    if (next == _last) return;
    _last = next;
    widget.onMove?.call(next);
  }

  void _finish() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    final last = _last;
    if (last != null) widget.onMoveEnd?.call(last);
    _last = null;
  }

  void _nudge(int direction) {
    final p = widget.placement;
    final next = p.copyWith(
      position: (p.position + direction * widget.keyStep).clamp(0.0, 1.0),
    );
    if (next == p) return;
    widget.onMove?.call(next);
    widget.onMoveEnd?.call(next);
  }

  Size _ghostSize(LgToolbarDock dock) =>
      widget.previewSize?.call(dock) ??
      (dock.vertical ? const Size(60, 360) : const Size(720, 52));

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    final p = widget.placement;
    final preview = widget.preview;
    Alignment alignment(LgToolbarPlacement place) {
      final along = place.position * 2 - 1;
      return switch (place.dock) {
        LgToolbarDock.top => Alignment(along, -1),
        LgToolbarDock.bottom => Alignment(along, 1),
        LgToolbarDock.left => Alignment(-1, along),
        LgToolbarDock.right => Alignment(1, along),
      };
    }

    // The bar keeps 12 px from the edge it hangs on.
    EdgeInsets side(LgToolbarDock dock) => switch (dock) {
      LgToolbarDock.top => const EdgeInsets.only(top: LgSpace.s3),
      LgToolbarDock.bottom => const EdgeInsets.only(bottom: LgSpace.s3),
      LgToolbarDock.left => const EdgeInsets.only(left: LgSpace.s3),
      LgToolbarDock.right => const EdgeInsets.only(right: LgSpace.s3),
    };

    EdgeInsets inset(LgToolbarDock dock) => dock.vertical
        ? EdgeInsets.symmetric(vertical: widget.edgeMargin)
        : EdgeInsets.symmetric(horizontal: widget.edgeMargin);

    return LgToolbarDragScope(
      dragging: _dragging,
      onStart: _begin,
      onUpdate: _drag,
      onEnd: _finish,
      onNudge: _nudge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (preview != null && preview != p)
            Padding(
              padding: inset(preview.dock) + side(preview.dock),
              child: Align(
                alignment: alignment(preview),
                child: ExcludeSemantics(
                  child: Container(
                    width: _ghostSize(preview.dock).width,
                    height: _ghostSize(preview.dock).height,
                    padding: const EdgeInsets.all(LgSpace.s2),
                    decoration: BoxDecoration(
                      color: c.active,
                      borderRadius: BorderRadius.circular(LgRadius.r16),
                      border: Border.all(color: c.accent, width: 2),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.active,
                        borderRadius: BorderRadius.circular(LgRadius.r12),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: inset(p.dock),
            child: Align(alignment: alignment(p), child: widget.child),
          ),
        ],
      ),
    );
  }
}
