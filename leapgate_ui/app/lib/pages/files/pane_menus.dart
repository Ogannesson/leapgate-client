// The menus of a pane (02 §2.2 block F): "⋯" on the action row and the context menus of a
// folder, a file, a link, a drive and the blank, with their keys on the right.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/models/file_model.dart';

import '../../icons/lg_icon.dart';
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
        icon: LgIcons.folder,
        label: l10n.filesOpen,
        shortcut: 'Enter',
        onPressed: () => pane.openDirectory(clicked.path),
      ),
      LgMenuItem(
        icon: LgIcons.copy,
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
        icon: LgIcons.folder,
        label: l10n.filesOpen,
        shortcut: 'Enter',
        onPressed: () => pane.openDirectory(clicked.path),
      ),
    LgMenuItem(
      icon: pane.isLocal ? LgIcons.upload : LgIcons.download,
      label: transferLabel(l10n, pane),
      // Enter sends files, as a double click does (`FileList._activate`).
      shortcut: !clicked.isDirectory && items.every((e) => e.isFile)
          ? 'Enter'
          : null,
      onPressed: blocked == null ? () => pane.transfer(items) : null,
      disabledNote: blocked == null || blocked.isEmpty ? null : blocked,
    ),
    const LgMenuDivider(),
    if (pane.canRename)
      LgMenuItem(
        icon: LgIcons.edit,
        label: l10n.filesRename,
        shortcut: 'F2',
        onPressed: items.length == 1 ? () => pane.rename(items.single) : null,
      ),
    LgMenuItem(
      icon: LgIcons.trash,
      label: l10n.filesDelete,
      shortcut: 'Delete',
      danger: true,
      onPressed: () => pane.delete(items),
    ),
    const LgMenuDivider(),
    LgMenuItem(
      icon: LgIcons.copy,
      label: l10n.filesCopyPath,
      onPressed: () =>
          copyPath(items.length == 1 ? items.single.path : clicked.path),
    ),
  ];
}

/// "显示隐藏的项目" with its tick in the column the icons of the other rows take (`.mr .ck`), so
/// the labels line up; the menu stays open as with a check box. The row's node says whether it
/// is ticked, as the check box did.
Widget _showHiddenItem(AppLocalizations l10n, FilePane pane) => MergeSemantics(
  child: Semantics(
    checked: pane.showHidden,
    child: LgMenuItem(
      label: l10n.filesShowHidden,
      checked: pane.showHidden,
      keepOpen: true,
      onPressed: () => pane.setShowHidden(!pane.showHidden),
    ),
  ),
);

/// The rows of the menu for a right click on the blank of the list; "新建文件夹" is not offered
/// in "此电脑".
List<Widget> blankMenuItems(
  AppLocalizations l10n, {
  required FilePane pane,
  required List<Entry> visible,
}) => [
  if (!pane.isThisPc && pane.path.isNotEmpty)
    LgMenuItem(
      icon: LgIcons.folderPlus,
      label: l10n.filesNewFolder,
      shortcut: 'Ctrl+Shift+N',
      onPressed: pane.newFolder,
    ),
  LgMenuItem(
    icon: LgIcons.refresh,
    label: l10n.filesRefresh,
    shortcut: 'F5',
    onPressed: pane.refresh,
  ),
  LgMenuItem(
    icon: LgIcons.select,
    label: l10n.filesSelectAll,
    shortcut: 'Ctrl+A',
    onPressed: () => pane.select(visible),
  ),
  const LgMenuDivider(),
  _showHiddenItem(l10n, pane),
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
    _showHiddenItem(l10n, pane),
    LgMenuItem(
      icon: LgIcons.select,
      label: l10n.filesSelectAll,
      shortcut: 'Ctrl+A',
      onPressed: () => pane.select(visible),
    ),
    LgMenuItem(
      icon: LgIcons.x,
      label: l10n.filesSelectNone,
      onPressed: pane.selection.isEmpty ? null : () => pane.select(const []),
    ),
    const LgMenuDivider(),
    LgMenuGroup(l10n.filesSortBy),
    sortItem(l10n.filesColName, FileSortField.name),
    sortItem(l10n.filesColModified, FileSortField.modified),
    sortItem(l10n.filesColType, FileSortField.type),
    sortItem(l10n.filesColSize, FileSortField.size),
  ];
}
