// The path of a pane (02 §2.2 block C): the breadcrumb with the root's drop-down, the middle
// left out when it does not fit (`LgBreadcrumb`), and the path field (Ctrl+L or a click on the
// blank after it).
import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/file_transfer/errors.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/models/file_model.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/lg_breadcrumb.dart';
import '../../widgets/lg_file_marks.dart';
import '../../widgets/lg_menu.dart';
import 'formats.dart';

/// One segment: what it shows and the folder it opens.
typedef Crumb = ({String label, String path});

/// The segments of [path]: "此电脑" (Windows) or "/" first, then each folder, a drive without
/// its backslash.
List<Crumb> crumbsOf(String path, bool isWindows, String thisPc) {
  if (isWindows) {
    final out = <Crumb>[(label: thisPc, path: '/')];
    if (path.isEmpty || path == '/') return out;
    var acc = '';
    for (final part in PathUtil.split(path, true)) {
      acc = acc.isEmpty ? part : PathUtil.join(acc, part, true);
      final label = part.length > 1 && part.endsWith('\\')
          ? part.substring(0, part.length - 1)
          : part;
      out.add((label: label, path: acc));
    }
    return out;
  }
  final out = <Crumb>[(label: '/', path: '/')];
  var acc = '/';
  for (final part in PathUtil.split(path, false)) {
    if (part == '/') continue;
    acc = PathUtil.join(acc, part, false);
    out.add((label: part, path: acc));
  }
  return out;
}

class FileBreadcrumb extends StatefulWidget {
  const FileBreadcrumb({super.key, required this.pane, required this.editing});

  final FilePane pane;

  /// The path field is shown; Ctrl+L in the list sets it.
  final ValueNotifier<bool> editing;

  @override
  State<FileBreadcrumb> createState() => _FileBreadcrumbState();
}

class _FileBreadcrumbState extends State<FileBreadcrumb> {
  final _field = TextEditingController();
  final _fieldFocus = FocusNode(debugLabel: 'path field');
  String? _error;

  /// The text that [_error] is about; typing something else takes the error away.
  String _failed = '';

  /// Enter takes the focus out of the field before it hands over the path (`LgPathInput` has
  /// no way to keep it); the field stays while that path is opened.
  var _submitting = false;

  FilePane get _pane => widget.pane;

  @override
  void initState() {
    super.initState();
    widget.editing.addListener(_onEditing);
    _fieldFocus.addListener(() {
      if (!_fieldFocus.hasFocus && widget.editing.value && !_submitting) {
        _cancel();
      }
    });
    _field.addListener(() {
      if (_error != null && _field.text != _failed) {
        setState(() => _error = null);
      }
    });
  }

  @override
  void dispose() {
    widget.editing.removeListener(_onEditing);
    _field.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _onEditing() {
    if (widget.editing.value) {
      _field.text = _pane.path;
      _field.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _field.text.length,
      );
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fieldFocus.requestFocus(),
      );
    }
    setState(() {});
  }

  void _cancel() {
    _error = null;
    widget.editing.value = false;
  }

  Future<void> _submit(String text) async {
    final l10n = AppLocalizations.of(context)!;
    final path = text.trim();
    if (path.isEmpty) {
      _fieldFocus.requestFocus();
      return;
    }
    final FtError? error;
    _submitting = true;
    try {
      error = await _pane.openDirectory(path, showError: false);
    } finally {
      _submitting = false;
    }
    if (!mounted) return;
    if (error == null) {
      _cancel();
    } else {
      _failed = _field.text;
      final text =
          openErrorText(l10n, path, error, _pane.isWindows, brief: true);
      setState(() => _error = text);
      _fieldFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (widget.editing.value) {
      return LgPathInput(
        controller: _field,
        focusNode: _fieldFocus,
        semanticLabel: l10n.filesEditPath,
        errorText: _error,
        onSubmitted: _submit,
        onCancel: _cancel,
      );
    }
    final crumbs = crumbsOf(_pane.path, _pane.isWindows, l10n.filesThisPc);
    // The drive of the open folder, ticked in the root's drop-down.
    final drive = _pane.isWindows && crumbs.length > 1 ? crumbs[1].path : null;
    return LgBreadcrumb(
      rootLabel: crumbs.first.label,
      rootTip: _pane.isWindows ? l10n.filesThisPc : l10n.filesRootFolder,
      segments: [for (final c in crumbs.skip(1)) c.label],
      onRoot: () => _pane.openDirectory('/'),
      onSegment: (i) => _pane.openDirectory(crumbs[i + 1].path),
      onEdit: () => widget.editing.value = true,
      editLabel: l10n.filesEditPath,
      rootMenu: _pane.isWindows
          ? [_DriveItems(pane: _pane, current: drive)]
          : [
              LgMenuItem(
                label: '/',
                checked: true,
                onPressed: () => _pane.openDirectory('/'),
              ),
            ],
    );
  }
}

/// The drives under "此电脑" in the root drop-down; "正在读取…" until they are read, a greyed
/// line when they could not be.
class _DriveItems extends StatefulWidget {
  const _DriveItems({required this.pane, required this.current});

  final FilePane pane;

  /// The open folder's drive ("C:\"), null in "此电脑".
  final String? current;

  @override
  State<_DriveItems> createState() => _DriveItemsState();
}

class _DriveItemsState extends State<_DriveItems> {
  late final Future<List<Entry>> _drives = widget.pane.drives();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<List<Entry>>(
      future: _drives,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return LgMenuLoadingRow(l10n.filesReading);
        }
        if (snap.hasError) {
          return LgMenuItem(label: l10n.filesDrivesFailed, onPressed: null);
        }
        final current = widget.current?.toLowerCase();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in snap.data!)
              LgMenuItem(
                icon: LgIcons.drive,
                label: d.name,
                checked: d.path.toLowerCase() == current,
                onPressed: () => widget.pane.openDirectory(d.path),
              ),
          ],
        );
      },
    );
  }
}
