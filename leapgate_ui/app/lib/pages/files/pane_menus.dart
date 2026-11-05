// The menus of a pane (02 §2.2 block F): "⋯" on the action row and the context menus of a
// folder, a file, a link, a drive and the blank, with their keys on the right.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/models/file_model.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/lg_menu.dart';
import '../../widgets/lg_menu_items.dart';

/// Why items of a pane can't be sent to [other] now: "目标位置不能是“此电脑”" while it shows
/// "此电脑", an empty note while it has no folder yet; null when they can.
String? transferBlocked(AppLocalizations l10n, FilePane other) {
  if (other.isThisPc) return l10n.filesNotThisPc;
  if (other.path.isEmpty) return '';
  return null;
}

/// "上传" on this device's pane, "下载" on the remote one.
String transferLabel(AppLocalizations l10n, FilePane pane) =>
    pane.isLocal ? l10n.filesUpload : l10n.filesDownload;

void copyPath(String path) {
  Clipboard.setData(ClipboardData(text: path));
  appCore.toasts.show('Copied');
}

/// The rows of the menu for a right click on [clicked], with [selection] (which holds it, the
/// list selects it first) or, on a drive, nothing selected.
List<Widget> entryMenuItems(
  AppLocalizations l10n, {
  required FilePane pane,
  required FilePane other,
  required Entry clicked,
  required List<Entry> selection,
}) {
  if (clicked.isDrive) {
    return [
      LgMenuItem(
        label: l10n.filesOpen,
        shortcut: 'Enter',
        onPressed: () => pane.openDirectory(clicked.path),
      ),
      LgMenuItem(
        label: l10n.filesCopyPath,
        onPressed: () => copyPath(clicked.path),
      ),
    ];
  }
  final items = selection.isEmpty ? [clicked] : selection;
  final blocked = transferBlocked(l10n, other);
  return [
    if (clicked.isDirectory)
      LgMenuItem(
        label: l10n.filesOpen,
        shortcut: 'Enter',
        onPressed: () => pane.openDirectory(clicked.path),
      ),
    LgMenuItem(
      label: transferLabel(l10n, pane),
      onPressed: blocked == null ? () => pane.transfer(items) : null,
      disabledNote: blocked == null || blocked.isEmpty ? null : blocked,
    ),
    if (pane.canRename)
      LgMenuItem(
        label: l10n.filesRename,
        shortcut: 'F2',
        onPressed: items.length == 1 ? () => pane.rename(items.single) : null,
      ),
    LgMenuItem(
      label: l10n.filesDelete,
      shortcut: 'Delete',
      onPressed: () => pane.delete(items),
    ),
    LgMenuItem(
      label: l10n.filesCopyPath,
      onPressed: () =>
          copyPath(items.length == 1 ? items.single.path : clicked.path),
    ),
  ];
}

/// The rows of the menu for a right click on the blank of the list; "新建文件夹" is not offered
/// in "此电脑".
List<Widget> blankMenuItems(
  AppLocalizations l10n, {
  required FilePane pane,
  required List<Entry> visible,
}) => [
  if (!pane.isThisPc && pane.path.isNotEmpty)
    LgMenuItem(
      label: l10n.filesNewFolder,
      shortcut: 'Ctrl+Shift+N',
      onPressed: pane.newFolder,
    ),
  LgMenuItem(label: l10n.filesRefresh, shortcut: 'F5', onPressed: pane.refresh),
  LgMenuItem(
    label: l10n.filesSelectAll,
    shortcut: 'Ctrl+A',
    onPressed: () => pane.select(visible),
  ),
  LgMenuCheckItem(
    label: l10n.filesShowHidden,
    value: pane.showHidden,
    onChanged: pane.setShowHidden,
  ),
];

/// The "⋯" menu of the action row.
List<Widget> moreMenuItems(
  AppLocalizations l10n, {
  required FilePane pane,
  required List<Entry> visible,
}) {
  final sort = pane.sort;
  LgMenuItem sortItem(String label, FileSortField field) => LgMenuItem(
    label: label,
    checked: sort.field == field,
    onPressed: () => pane.setSort((field: field, ascending: true)),
  );
  return [
    LgMenuCheckItem(
      label: l10n.filesShowHidden,
      value: pane.showHidden,
      onChanged: pane.setShowHidden,
    ),
    LgMenuItem(
      label: l10n.filesSelectAll,
      shortcut: 'Ctrl+A',
      onPressed: () => pane.select(visible),
    ),
    LgMenuItem(
      label: l10n.filesSelectNone,
      onPressed: pane.selection.isEmpty ? null : () => pane.select(const []),
    ),
    const LgMenuDivider(),
    LgSubmenu(
      label: l10n.filesSortBy,
      items: [
        sortItem(l10n.filesColName, FileSortField.name),
        sortItem(l10n.filesColModified, FileSortField.modified),
        sortItem(l10n.filesColType, FileSortField.type),
        sortItem(l10n.filesColSize, FileSortField.size),
      ],
    ),
  ];
}
