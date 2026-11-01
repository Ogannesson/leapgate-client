// Where the floating toolbar sits (01 P2 block B): along the top edge, or with "允许工具栏停靠在
// 窗口任意一边" on any edge, nearest to where it is dropped. The place is kept per device.
// Upstream: `flutter/lib/desktop/widgets/remote_toolbar.dart` (:29-160, `_syncDockingOptions`
// :506-606, `_DraggableShowHideState` :3354-3520), rewritten; the edge and the fraction along it
// are stored under upstream's keys, so the old UI and this one share them.

import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_toolbar_dock.dart';

/// What the placer keeps between the toolbar and the ends of its edge.
const kToolbarEdgeMargin = LgSpace.s3;

enum ToolbarEdge { top, right, bottom, left }

/// Where upstream kept the place before docking on any edge.
const _kLegacyDragX = 'remote-menubar-drag-x';

/// Upstream favours the edge being previewed by this much, so a drag between two edges does
/// not flicker (`remote_toolbar.dart:3388`).
const kToolbarEdgeHysteresis = 50.0;

ToolbarEdge parseToolbarEdge(String? s) => switch (s) {
  'right' => ToolbarEdge.right,
  'bottom' => ToolbarEdge.bottom,
  'left' => ToolbarEdge.left,
  _ => ToolbarEdge.top,
};

bool isHorizontalEdge(ToolbarEdge e) =>
    e == ToolbarEdge.top || e == ToolbarEdge.bottom;

/// [fraction] 0 is the start of the edge, 1 its end: the share of the way the toolbar can
/// travel along it, as upstream's and as [LgToolbarPlacement.position].
typedef ToolbarDock = ({ToolbarEdge edge, double fraction});

LgToolbarPlacement placementOf(ToolbarDock dock) => LgToolbarPlacement(
  LgToolbarDock.values.byName(dock.edge.name),
  dock.fraction,
);

/// A place the toolbar's placer gives back (a drop, an arrow key), kept inside the bounds.
ToolbarDock dockOf(LgToolbarPlacement placement) {
  final edge = ToolbarEdge.values.byName(placement.dock.name);
  final bounds = _boundsFor(edge);
  return (
    edge: edge,
    fraction: placement.position.clamp(bounds.left, bounds.right),
  );
}

bool multiEdgeDocking() =>
    appCore.options.local.getBool(kOptionAllowMultiEdgeToolbarDock);

/// How far along the top and bottom edges the toolbar may go (upstream's local options; whole
/// edge by default).
({double left, double right}) dragBounds() => (
  left:
      double.tryParse(
        appCore.options.local.get(kOptionRemoteMenubarDragLeft),
      ) ??
      0.0,
  right:
      double.tryParse(
        appCore.options.local.get(kOptionRemoteMenubarDragRight),
      ) ??
      1.0,
);

({double left, double right}) _boundsFor(ToolbarEdge edge) =>
    isHorizontalEdge(edge) ? dragBounds() : (left: 0.0, right: 1.0);

/// The device's saved place (`remote_toolbar.dart:506-606`). Docking on any edge off: the top
/// edge at the old horizontal place, written back as upstream does.
Future<ToolbarDock> loadToolbarDock(FFI ffi) async {
  final multiEdge = multiEdgeDocking();
  final saved = await ffi.options.get(kOptionRemoteMenubarFraction);
  final legacy = await ffi.options.get(_kLegacyDragX);
  final edge = multiEdge
      ? parseToolbarEdge(await ffi.options.get(kOptionRemoteMenubarEdge))
      : ToolbarEdge.top;
  String raw;
  if (!multiEdge) {
    raw = legacy != null && legacy.isNotEmpty ? legacy : '0.5';
  } else if (saved != null && saved.isNotEmpty) {
    raw = saved;
  } else if (edge == ToolbarEdge.top && legacy != null && legacy.isNotEmpty) {
    raw = legacy;
  } else {
    raw = '0.5';
  }
  final bounds = _boundsFor(edge);
  final dock = (
    edge: edge,
    fraction: (double.tryParse(raw) ?? 0.5).clamp(bounds.left, bounds.right),
  );
  if (!multiEdge) {
    await ffi.options.set(kOptionRemoteMenubarEdge, 'top');
    await ffi.options.set(kOptionRemoteMenubarFraction, '${dock.fraction}');
  }
  return dock;
}

/// Saves a dropped place (`remote_toolbar.dart:3484-3520`).
Future<void> saveToolbarDock(FFI ffi, ToolbarDock dock) async {
  await ffi.options.set(kOptionRemoteMenubarEdge, dock.edge.name);
  await ffi.options.set(kOptionRemoteMenubarFraction, '${dock.fraction}');
  if (!multiEdgeDocking()) {
    await ffi.options.set(_kLegacyDragX, '${dock.fraction}');
  }
}

/// The edge a drag at [cursor] drops on; only the top edge unless docking on any edge is on
/// (`remote_toolbar.dart:3390-3418`).
ToolbarEdge nearestToolbarEdge(
  Offset cursor,
  Size area, {
  required bool multiEdge,
  required ToolbarEdge current,
  ToolbarEdge? previewed,
}) {
  if (!multiEdge) return current;
  double distance(ToolbarEdge e) => switch (e) {
    ToolbarEdge.top => cursor.dy,
    ToolbarEdge.bottom => area.height - cursor.dy,
    ToolbarEdge.left => cursor.dx,
    ToolbarEdge.right => area.width - cursor.dx,
  };
  var winner = current;
  var best = double.infinity;
  for (final e in ToolbarEdge.values) {
    final d = e == previewed
        ? distance(e) - kToolbarEdgeHysteresis
        : distance(e);
    if (d < best) {
      best = d;
      winner = e;
    }
  }
  return winner;
}

/// The size of the toolbar on [edge]: its long side runs along the edge.
Size toolbarSizeOn(ToolbarEdge edge, Size measured) => isHorizontalEdge(edge)
    ? Size(measured.longestSide, measured.shortestSide)
    : Size(measured.shortestSide, measured.longestSide);

/// Where along [edge] the toolbar lands when the pointer is at [cursor], [grab] from the
/// toolbar's start along the edge (`remote_toolbar.dart:97-111`, `:3445-3475`).
double dragFraction(
  ToolbarEdge edge,
  Offset cursor,
  double grab,
  Size area,
  Size toolbar,
) {
  final bounds = _boundsFor(edge);
  final horizontal = isHorizontalEdge(edge);
  final travel = horizontal
      ? area.width - toolbar.width
      : area.height - toolbar.height;
  final along = horizontal ? cursor.dx : cursor.dy;
  if (travel <= 0) return 0.5.clamp(bounds.left, bounds.right);
  return ((along - grab) / travel).clamp(bounds.left, bounds.right);
}
