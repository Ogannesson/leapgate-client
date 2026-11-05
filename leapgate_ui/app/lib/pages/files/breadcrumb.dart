// The path of a pane (02 §2.2 block C): the breadcrumb with the root's drop-down, the middle
// left out when it does not fit, and the path field (Ctrl+L or a click on the blank after it).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/file_transfer/pane.dart';
import 'package:flutter_hbb/models/file_model.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_menu.dart';
import '../../widgets/lg_menu_items.dart';
import '../../widgets/lg_text_field.dart';
import '../../widgets/lg_tooltip.dart';
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

/// Which segments show in [width] (indexes into [widths], the segments' widths with their
/// separators): all that fit, otherwise the root, the first folder, "…" and as many of the last
/// as fit, at least the current one.
List<int> visibleCrumbs(List<double> widths, double ellipsis, double width) {
  final all = [for (var i = 0; i < widths.length; i++) i];
  if (widths.fold<double>(0, (a, b) => a + b) <= width || widths.length < 4) {
    return all;
  }
  final keep = [0, 1];
  var used = widths[0] + widths[1] + ellipsis;
  final tail = <int>[];
  for (var i = widths.length - 1; i > 1; i--) {
    if (tail.isNotEmpty && used + widths[i] > width) break;
    used += widths[i];
    tail.insert(0, i);
  }
  return [...keep, ...tail];
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
  final _root = GlobalKey();
  String? _error;

  FilePane get _pane => widget.pane;

  @override
  void initState() {
    super.initState();
    widget.editing.addListener(_onEditing);
    _fieldFocus.addListener(() {
      if (!_fieldFocus.hasFocus && widget.editing.value) _cancel();
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
    if (path.isEmpty) return;
    final error = await _pane.openDirectory(path, showError: false);
    if (!mounted) return;
    if (error == null) {
      _cancel();
    } else {
      setState(
        () => _error = openErrorText(l10n, path, error, _pane.isWindows),
      );
      _fieldFocus.requestFocus();
    }
  }

  void _openRootMenu() {
    final l10n = AppLocalizations.of(context)!;
    final box = _root.currentContext!.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset(0, box.size.height));
    showLgMenuAt(
      context,
      globalPosition: at,
      items: [
        LgMenuItem(
          label: _pane.isWindows ? l10n.filesThisPc : '/',
          onPressed: () => _pane.openDirectory('/'),
        ),
        if (_pane.isWindows) ...[
          const LgMenuDivider(),
          _DriveItems(pane: _pane),
        ],
      ],
    );
  }

  Widget _pathField(AppLocalizations l10n) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
      child: LgTextField(
        controller: _field,
        focusNode: _fieldFocus,
        dense: true,
        semanticLabel: l10n.filesEditPath,
        errorText: _error,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: _submit,
        // Keeps the focus: a path that did not open stays in the field to be corrected.
        onEditingComplete: () {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (widget.editing.value) return _pathField(l10n);
    final t = LgTokens.of(context);
    final style = t.text;
    final crumbs = crumbsOf(_pane.path, _pane.isWindows, l10n.filesThisPc);
    const separator = 18.0;
    double measure(String s) => (TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout()).width;
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = [
          for (final c in crumbs) measure(c.label) + LgSpace.s2 * 2 + separator,
        ];
        // The root's drop-down and some blank to click into the path field.
        final room = constraints.maxWidth - t.sizes.button - LgSpace.s6;
        final shown = visibleCrumbs(widths, measure('…') + separator, room);
        final children = <Widget>[];
        for (var k = 0; k < shown.length; k++) {
          final i = shown[k];
          if (k > 0) {
            children.add(const _Separator());
            if (shown[k - 1] != i - 1) {
              final hidden = crumbs.sublist(shown[k - 1] + 1, i);
              children.add(
                LgTooltip(
                  message: hidden.map((c) => c.label).join(' › '),
                  child: Text('…', style: style),
                ),
              );
              children.add(const _Separator());
            }
          }
          final c = crumbs[i];
          children.add(
            _CrumbButton(
              label: c.label,
              current: i == crumbs.length - 1,
              onPressed: () => _pane.openDirectory(c.path),
            ),
          );
          if (i == 0) {
            children.add(
              KeyedSubtree(
                key: _root,
                child: LgIconButton(
                  icon: LgIcons.chevD,
                  label: _pane.isWindows
                      ? l10n.filesThisPc
                      : l10n.filesRootFolder,
                  onPressed: _openRootMenu,
                  focusable: false,
                ),
              ),
            );
          }
        }
        return Row(
          children: [
            ...children,
            Expanded(
              child: Semantics(
                button: true,
                label: l10n.filesEditPath,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.editing.value = true,
                  child: SizedBox(height: t.sizes.button),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) =>
      LgIcon(LgIcons.chevR, size: 14, color: LgTokens.of(context).colors.text2);
}

class _CrumbButton extends StatelessWidget {
  const _CrumbButton({
    required this.label,
    required this.current,
    required this.onPressed,
  });

  final String label;
  final bool current;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
          child: Text(
            label,
            style: current
                ? t.text.copyWith(fontWeight: FontWeight.w600)
                : t.text,
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}

/// The drives under "此电脑" in the root drop-down; "正在读取…" until they are read.
class _DriveItems extends StatefulWidget {
  const _DriveItems({required this.pane});

  final FilePane pane;

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
          return LgMenuItem(label: l10n.filesReading, onPressed: null);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in snap.data ?? const <Entry>[])
              LgMenuItem(
                icon: LgIcons.drive,
                label: d.name,
                onPressed: () => widget.pane.openDirectory(d.path),
              ),
          ],
        );
      },
    );
  }
}
