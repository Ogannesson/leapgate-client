// Dropping onto the panes (02 §2.2 block G, `LEAPGATE.md` §10.15 "几处约定"): files from the
// system's file manager through `desktop_drop` (one target for the whole view, the pane and row
// found from the coordinates), items from the other pane through Flutter's own drag and drop.
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/models/file_model.dart';

import '../../l10n/app_localizations.dart';
import 'formats.dart';

/// Items dragged out of a pane.
class FileDrag {
  const FileDrag(this.source, this.items);

  final FilePane source;
  final List<Entry> items;
}

/// Where a drag would land in a pane.
class FileDropSpot {
  const FileDropSpot.into(this.folder, {this.to}) : accepted = true;

  const FileDropSpot.refused() : accepted = false, folder = '', to = null;

  final bool accepted;

  /// The folder or drive row it is over; null for the pane's own folder.
  final String? to;

  /// The name in "上传到“‹folder›”".
  final String folder;
}

/// What the drop handling knows of one pane: the pane's box, the row under a point (set by the
/// pane's list while it shows) and the spot to draw.
class PaneDropArea {
  PaneDropArea(this.pane);

  final FilePane pane;
  final key = GlobalKey(debugLabel: 'file pane');
  final hover = ValueNotifier<FileDropSpot?>(null);
  Entry? Function(Offset global)? rowAt;

  bool contains(Offset global) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(global);
  }

  /// Where items from [source] (null: the system's file manager) land at [global]: a folder or
  /// drive row takes them, otherwise the pane's folder, except "此电脑". Nothing is taken from
  /// the system on this device's pane, or by the pane the items came from (there is no move).
  FileDropSpot spotAt(
    AppLocalizations l10n,
    Offset global, {
    FilePane? source,
  }) {
    if (source == null ? pane.isLocal : identical(source, pane)) {
      return const FileDropSpot.refused();
    }
    final row = rowAt?.call(global);
    if (row != null && (row.isDirectory || row.isDrive)) {
      return FileDropSpot.into(row.name, to: row.path);
    }
    if (pane.path.isEmpty || pane.isThisPc) {
      return const FileDropSpot.refused();
    }
    return FileDropSpot.into(folderName(l10n, pane.path, pane.isWindows));
  }

  void dispose() => hover.dispose();
}

/// The whole view as the one target for files from the system's file manager: it tells each
/// pane what to draw while they are over it, and uploads what is dropped on the remote pane.
/// Only the shown view listens ([enabled]).
class SystemDropTarget extends StatelessWidget {
  const SystemDropTarget({
    super.key,
    required this.enabled,
    required this.areas,
    required this.onDrop,
    required this.child,
  });

  final bool enabled;
  final List<PaneDropArea> areas;

  /// The dropped paths, and the folder row they went to (null: the remote pane's folder).
  final void Function(List<String> paths, String? to) onDrop;
  final Widget child;

  void _hover(BuildContext context, Offset global) {
    final l10n = AppLocalizations.of(context)!;
    for (final a in areas) {
      a.hover.value = a.contains(global) ? a.spotAt(l10n, global) : null;
    }
  }

  void _clear() {
    for (final a in areas) {
      a.hover.value = null;
    }
  }

  @override
  Widget build(BuildContext context) => DropTarget(
    enable: enabled,
    onDragEntered: (d) => _hover(context, d.globalPosition),
    onDragUpdated: (d) => _hover(context, d.globalPosition),
    onDragExited: (_) => _clear(),
    onDragDone: (d) {
      final l10n = AppLocalizations.of(context)!;
      _clear();
      for (final a in areas) {
        if (!a.contains(d.globalPosition)) continue;
        final spot = a.spotAt(l10n, d.globalPosition);
        final paths = [for (final f in d.files) f.path];
        if (spot.accepted && paths.isNotEmpty) onDrop(paths, spot.to);
      }
    },
    child: child,
  );
}

/// A pane as the target of items dragged from the other pane: the items go to the folder row
/// they are dropped on, or the pane's folder.
class PaneDragTarget extends StatelessWidget {
  const PaneDragTarget({super.key, required this.area, required this.child});

  final PaneDropArea area;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DragTarget<FileDrag>(
      onWillAcceptWithDetails: (d) => !identical(d.data.source, area.pane),
      onMove: (d) =>
          area.hover.value = area.spotAt(l10n, d.offset, source: d.data.source),
      onLeave: (_) => area.hover.value = null,
      onAcceptWithDetails: (d) {
        final spot = area.spotAt(l10n, d.offset, source: d.data.source);
        area.hover.value = null;
        if (spot.accepted) d.data.source.transfer(d.data.items, to: spot.to);
      },
      builder: (context, _, __) => child,
    );
  }
}
