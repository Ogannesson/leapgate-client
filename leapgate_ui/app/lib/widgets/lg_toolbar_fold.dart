// A row that puts what does not fit into a "更多" menu (01 §3.2 block B;
// `min-s`, `min-d` in A-P2.html). The toolbar gives it its buttons in order;
// the ones wrapped in [LgToolbarFoldable] are the ones that may be folded, and
// they go from the end of the row backwards until the rest fits, the first
// folded one's place taken by the "更多" button.
//
// The toolbar wraps what it holds in this; the callers only wrap their buttons
// in [LgToolbarFoldable] and give the row they want in the menu.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// A button that may be folded into "更多": [inline] is the button as it shows
/// in the bar, [menuItem] the row it becomes in the "更多" menu (a menu item or
/// a submenu), [badge] a count (unread messages) that the "更多" button then
/// shows too. It shows [inline] anywhere else.
class LgToolbarFoldable extends StatelessWidget {
  const LgToolbarFoldable({
    super.key,
    required this.inline,
    required this.menuItem,
    this.badge = 0,
  });

  final Widget inline;
  final Widget menuItem;
  final int badge;

  @override
  Widget build(BuildContext context) => inline;
}

/// One thing in the row and how far it is from the one before.
class LgFoldSlot {
  const LgFoldSlot(this.child, {this.gap = 0, this.foldable = false});

  final Widget child;
  final double gap;
  final bool foldable;
}

/// The row. [more] is laid out at the place of the first folded slot and not at
/// all while nothing is folded. [onFolded] is told how many slots are folded
/// (after the frame, so that it may rebuild what shows them).
class LgFoldRow extends MultiChildRenderObjectWidget {
  LgFoldRow({
    super.key,
    required this.axis,
    required this.maxExtent,
    required this.slots,
    required Widget more,
    required this.onFolded,
  }) : super(children: [for (final s in slots) s.child, more]);

  final Axis axis;

  /// How long the row may be along its axis.
  final double maxExtent;
  final List<LgFoldSlot> slots;
  final ValueChanged<int> onFolded;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFoldRow(
    axis: axis,
    maxExtent: maxExtent,
    gaps: [for (final s in slots) s.gap],
    foldable: [for (final s in slots) s.foldable],
    onFolded: onFolded,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderFoldRow)
      ..axis = axis
      ..maxExtent = maxExtent
      ..gaps = [for (final s in slots) s.gap]
      ..foldable = [for (final s in slots) s.foldable]
      ..onFolded = onFolded;
  }
}

class _FoldParentData extends ContainerBoxParentData<RenderBox> {
  bool hidden = false;
}

class _RenderFoldRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FoldParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FoldParentData> {
  _RenderFoldRow({
    required Axis axis,
    required double maxExtent,
    required List<double> gaps,
    required List<bool> foldable,
    required this.onFolded,
  }) : _axis = axis,
       _maxExtent = maxExtent,
       _gaps = gaps,
       _foldable = foldable;

  Axis _axis;
  Axis get axis => _axis;
  set axis(Axis v) {
    if (v == _axis) return;
    _axis = v;
    markNeedsLayout();
  }

  double _maxExtent;
  double get maxExtent => _maxExtent;
  set maxExtent(double v) {
    if (v == _maxExtent) return;
    _maxExtent = v;
    markNeedsLayout();
  }

  List<double> _gaps;
  set gaps(List<double> v) {
    if (listEquals(v, _gaps)) return;
    _gaps = v;
    markNeedsLayout();
  }

  List<bool> _foldable;
  set foldable(List<bool> v) {
    if (listEquals(v, _foldable)) return;
    _foldable = v;
    markNeedsLayout();
  }

  ValueChanged<int> onFolded;
  int _reported = 0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FoldParentData) {
      child.parentData = _FoldParentData();
    }
  }

  List<RenderBox> get _children {
    final out = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      out.add(child);
      child = childAfter(child);
    }
    return out;
  }

  double _main(Size s) => _axis == Axis.horizontal ? s.width : s.height;
  double _cross(Size s) => _axis == Axis.horizontal ? s.height : s.width;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(debugCannotComputeDryLayout(reason: 'LgFoldRow lays out its children for real'));
    return Size.zero;
  }

  @override
  void performLayout() {
    final all = _children;
    final slots = all.length - 1;
    final loose = _axis == Axis.horizontal
        ? BoxConstraints(maxHeight: constraints.maxHeight)
        : BoxConstraints(maxWidth: constraints.maxWidth);
    for (final child in all) {
      child.layout(loose, parentUsesSize: true);
    }
    final sizes = [for (final c in all) c.size];
    final foldable = [
      for (var i = 0; i < slots; i++) i < _foldable.length && _foldable[i],
    ];
    final foldIdx = [
      for (var i = 0; i < slots; i++)
        if (foldable[i]) i,
    ];

    double gapOf(int i) => i < _gaps.length ? _gaps[i] : 0;

    // The slots shown, in order, each with its distance from the one before;
    // the "更多" (index [slots]) takes the place and the gap of the first slot
    // that is folded.
    List<(int, double)> shown(int k) {
      final hidden = foldIdx.sublist(foldIdx.length - k).toSet();
      final first = k == 0 ? -1 : foldIdx[foldIdx.length - k];
      final out = <(int, double)>[];
      for (var i = 0; i < slots; i++) {
        if (i != first && hidden.contains(i)) continue;
        out.add((i == first ? slots : i, out.isEmpty ? 0 : gapOf(i)));
      }
      return out;
    }

    double extentOf(List<(int, double)> order) {
      var total = 0.0;
      for (final (i, gap) in order) {
        total += gap + _main(sizes[i]);
      }
      return total;
    }

    var k = 0;
    while (k < foldIdx.length && extentOf(shown(k)) > _maxExtent) {
      k++;
    }
    final order = shown(k);

    for (final child in all) {
      (child.parentData! as _FoldParentData).hidden = true;
    }
    var offset = 0.0;
    var cross = 0.0;
    for (final (i, gap) in order) {
      offset += gap;
      (all[i].parentData! as _FoldParentData)
        ..hidden = false
        ..offset = _axis == Axis.horizontal
            ? Offset(offset, 0)
            : Offset(0, offset);
      offset += _main(sizes[i]);
      cross = cross < _cross(sizes[i]) ? _cross(sizes[i]) : cross;
    }
    size = constraints.constrain(
      _axis == Axis.horizontal ? Size(offset, cross) : Size(cross, offset),
    );
    // Centre the shorter ones across.
    for (final (i, _) in order) {
      final data = all[i].parentData! as _FoldParentData;
      final shift = (_cross(size) - _cross(sizes[i])) / 2;
      data.offset = _axis == Axis.horizontal
          ? Offset(data.offset.dx, shift)
          : Offset(shift, data.offset.dy);
    }
    if (k != _reported) {
      _reported = k;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (attached) onFolded(k);
      });
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in _children) {
      final data = child.parentData! as _FoldParentData;
      if (!data.hidden) context.paintChild(child, offset + data.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in _children.reversed) {
      final data = child.parentData! as _FoldParentData;
      if (data.hidden) continue;
      final hit = result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (final child in _children) {
      final data = child.parentData! as _FoldParentData;
      if (!data.hidden) visitor(child);
    }
  }
}
