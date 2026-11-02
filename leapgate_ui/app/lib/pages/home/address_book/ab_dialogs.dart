import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/address_book.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_banner.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_device_parts.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_menu.dart';
import '../../../widgets/lg_text_field.dart';
import 'ab_parts.dart';

// The address book's dialogs (01 P1 blocks F, G and §4.4, 02 §3.6), over the home tab. Errors
// stay in the dialog, which stays open (01 P1 block G "添加设备"); the two-sentence form is the
// list banner's. Rewritten after upstream `common/widgets/address_book.dart` (`addIdToCurrentAb`,
// `abAddTag`, `AddressBookTag._showMenu`) and `common/widgets/dialog.dart` (`editAbTagDialog`,
// `editAbPeerNoteDialog`, `addPeersToAbDialog`, `setSharedAbPasswordDialog`).
// The add device and tag colour dialogs are the designer's (`ui/m4-ds`); until then they are
// drawn with `LgConfirmDialog` like the small ones.

Future<T?> _show<T>(
  TabOverlays overlays,
  Widget Function(void Function(T? result) close) dialog,
) => overlays.show<T>(
  null,
  (context, close) =>
      LgDialogScrim(onEscape: () => close(null), child: dialog(close)),
);

/// A label over a field.
Widget _labeled(
  BuildContext context,
  String label,
  Widget field, {
  String? note,
}) {
  final t = LgTokens.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: t.textS.copyWith(color: t.colors.text2)),
      const SizedBox(height: LgSpace.s1),
      field,
      if (note != null) ...[
        const SizedBox(height: LgSpace.s1),
        Text(note, style: t.textS.copyWith(color: t.colors.text2)),
      ],
    ],
  );
}

/// The current book's tags to pick from, as in the filter bar.
Widget _tagChoice(Set<String> selected, ValueChanged<String>? onToggle) {
  final ab = appCore.addressBook;
  return Wrap(
    spacing: LgSpace.s2,
    runSpacing: LgSpace.s2,
    children: [
      for (final t in ab.tags)
        AbTagToggle(
          label: t.name,
          color: Color(t.color),
          selected: selected.contains(t.name),
          onPressed: onToggle == null ? null : () => onToggle(t.name),
        ),
    ],
  );
}

/// What every form dialog here shares: busy while submitting, the error banner under the title,
/// "取消" and the main button.
abstract class _FormState<T extends StatefulWidget> extends State<T> {
  bool busy = false;
  String? error;

  /// Closes the dialog without a result.
  void dismiss();

  // Signed out meanwhile (by the server's answer to this very change, say): the address book
  // is gone, and so is the dialog.
  void _onModel() {
    if (appCore.addressBook.current == null) dismiss();
  }

  @override
  void initState() {
    super.initState();
    appCore.addressBook.addListener(_onModel);
  }

  @override
  void dispose() {
    appCore.addressBook.removeListener(_onModel);
    super.dispose();
  }

  /// [submit] returns the error to show, null to close.
  Future<void> run(
    Future<String?> Function() submit,
    VoidCallback close,
  ) async {
    setState(() {
      busy = true;
      error = null;
    });
    final e = await submit();
    if (!mounted) return;
    if (appCore.addressBook.current == null) {
      dismiss();
    } else if (e == null) {
      close();
    } else {
      setState(() {
        busy = false;
        error = e;
      });
    }
  }

  Widget form({
    required String title,
    String? subtitle,
    required List<Widget> children,
    required String action,
    String? busyAction,
    required VoidCallback? onAction,
    required VoidCallback onCancel,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return LgConfirmDialog(
      title: title,
      subtitle: subtitle,
      actions: [
        LgDialogAction(label: l10n.homeCancel, onPressed: onCancel),
        LgDialogAction(
          label: busy ? (busyAction ?? action) : action,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: busy ? null : onAction,
        ),
      ],
      children: [
        if (error != null) LgBanner(tone: LgTone.error, text: error),
        ...children,
      ],
    );
  }
}

// ---- Add device (`p1-dlg-add`).

Future<void> showAbAddDeviceDialog(TabOverlays overlays) => _show<void>(
  overlays,
  (close) => _AddDeviceDialog(close: () => close(null)),
);

class _AddDeviceDialog extends StatefulWidget {
  const _AddDeviceDialog({required this.close});

  final VoidCallback close;

  @override
  State<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends _FormState<_AddDeviceDialog> {
  final _id = TextEditingController();
  final _alias = TextEditingController();
  final _password = TextEditingController();
  final _note = TextEditingController();
  final _tags = <String>{};
  String? _idError;

  @override
  void dispose() {
    for (final c in [_id, _alias, _password, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void dismiss() => widget.close();

  /// The ID as typed, without the spaces of its groups.
  String get _cleanId => _id.text.replaceAll(RegExp(r'\s'), '');

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    final ab = appCore.addressBook;
    final book = ab.current;
    if (book == null) return;
    if (ab.contains(book, _cleanId)) {
      setState(() => _idError = l10n.abIdExists);
      return;
    }
    if (ab.isFull(book)) {
      setState(() => error = l10n.abFull);
      return;
    }
    run(() async {
      final e = await ab.addDevice(
        id: _cleanId,
        alias: _alias.text.trim(),
        password: _password.text,
        note: _note.text,
        tags: [
          for (final t in ab.tags)
            if (_tags.contains(t.name)) t.name,
        ],
      );
      return e == null ? null : l10n.abAddDeviceFailed(abReason(l10n, e));
    }, widget.close);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ab = appCore.addressBook;
    final book = ab.current;
    if (book == null) return const SizedBox.shrink();
    final shared = !ab.isPersonal(book);
    return form(
      title: l10n.abAddDevice,
      subtitle: l10n.abAddTo(abBookName(l10n, book)),
      action: l10n.abAdd,
      busyAction: l10n.abAdding,
      onAction: _cleanId.isEmpty ? null : _submit,
      onCancel: widget.close,
      children: [
        _labeled(
          context,
          l10n.abFieldId,
          LgTextField(
            controller: _id,
            autofocus: true,
            enabled: !busy,
            semanticLabel: l10n.abFieldId,
            errorText: _idError,
            onChanged: (_) => setState(() => _idError = null),
          ),
        ),
        _labeled(
          context,
          l10n.abFieldAlias,
          LgTextField(
            controller: _alias,
            enabled: !busy,
            semanticLabel: l10n.abFieldAlias,
          ),
        ),
        if (shared)
          _labeled(
            context,
            l10n.abFieldPassword,
            LgTextField(
              controller: _password,
              enabled: !busy,
              obscureText: true,
              semanticLabel: l10n.abFieldPassword,
            ),
            note: l10n.abVisibleToMembers,
          ),
        _labeled(
          context,
          l10n.abFieldNote,
          LgTextField(
            controller: _note,
            enabled: !busy,
            maxLength: 300,
            semanticLabel: l10n.abFieldNote,
          ),
          note: l10n.abNoteLimit,
        ),
        if (ab.tags.isNotEmpty)
          _labeled(
            context,
            l10n.abFieldTags,
            _tagChoice(
              _tags,
              busy
                  ? null
                  : (t) => setState(
                      () => _tags.contains(t) ? _tags.remove(t) : _tags.add(t),
                    ),
            ),
          ),
      ],
    );
  }
}

// ---- One text field: add tag, rename tag, edit note, shared password.

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.close,
    required this.submit,
    this.initial = '',
    this.note,
    this.check,
    this.obscure = false,
    this.maxLength,
    this.allowEmpty = false,
  });

  final String title;
  final String label;
  final String initial;
  final String? note;
  final bool obscure;
  final int? maxLength;
  final bool allowEmpty;
  final VoidCallback close;

  /// What is wrong with the text, shown under the field; null when it can be submitted.
  final String? Function(String text)? check;

  /// The error to show, null when done.
  final Future<String?> Function(String text) submit;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends _FormState<_TextDialog> {
  @override
  void dismiss() => widget.close();

  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  String? _fieldError;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final problem = widget.check?.call(_text.text);
    if (problem != null) {
      setState(() => _fieldError = problem);
      return;
    }
    run(() => widget.submit(_text.text), widget.close);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return form(
      title: widget.title,
      action: l10n.homeOk,
      onAction: widget.allowEmpty || _text.text.isNotEmpty ? _submit : null,
      onCancel: widget.close,
      children: [
        _labeled(
          context,
          widget.label,
          LgTextField(
            controller: _text,
            autofocus: true,
            enabled: !busy,
            obscureText: widget.obscure,
            maxLength: widget.maxLength,
            semanticLabel: widget.label,
            errorText: _fieldError,
            onChanged: (_) => setState(() => _fieldError = null),
          ),
          note: widget.note,
        ),
      ],
    );
  }
}

Future<void> _textDialog(
  TabOverlays overlays, {
  required String title,
  required String label,
  required Future<String?> Function(String text) submit,
  String initial = '',
  String? note,
  String? Function(String text)? check,
  bool obscure = false,
  int? maxLength,
  bool allowEmpty = false,
}) => _show<void>(
  overlays,
  (close) => _TextDialog(
    title: title,
    label: label,
    initial: initial,
    note: note,
    check: check,
    obscure: obscure,
    maxLength: maxLength,
    allowEmpty: allowEmpty,
    close: () => close(null),
    submit: submit,
  ),
);

/// "添加标签" (upstream `abAddTag`): several names at once, split as upstream splits them.
Future<void> showAbAddTagDialog(TabOverlays overlays, AppLocalizations l10n) {
  final ab = appCore.addressBook;
  List<String> names(String text) => text
      .trim()
      .split(RegExp(r'[\s,;\n]+'))
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList();
  return _textDialog(
    overlays,
    title: l10n.abAddTag,
    label: l10n.abFieldTags,
    note: l10n.abAddTagNote,
    check: (text) {
      final tags = names(text);
      if (tags.isEmpty) return l10n.abTagEmpty;
      if (tags.contains(kAbUntagged) || tags.contains(l10n.abUntagged)) {
        return l10n.abTagReserved;
      }
      if (tags.any((t) => ab.tags.any((x) => x.name == t))) {
        return l10n.abTagExists;
      }
      return null;
    },
    submit: (text) async {
      final e = await ab.addTags(names(text));
      if (e == null) return null;
      return e.kind == ApiErrorKind.conflict
          ? l10n.abTagExists
          : l10n.abAddTagFailed(abReason(l10n, e));
    },
  );
}

/// "重命名" on a tag (upstream `AddressBookTag._showMenu`).
Future<void> showAbRenameTagDialog(
  TabOverlays overlays,
  AppLocalizations l10n,
  String tag,
) {
  final ab = appCore.addressBook;
  return _textDialog(
    overlays,
    title: l10n.abRenameTag,
    label: l10n.abFieldTags,
    initial: tag,
    check: (text) {
      final name = text.trim();
      if (name.isEmpty) return l10n.abTagEmpty;
      if (name == kAbUntagged || name == l10n.abUntagged) {
        return l10n.abTagReserved;
      }
      if (name != tag && ab.tags.any((t) => t.name == name)) {
        return l10n.abTagExists;
      }
      return null;
    },
    submit: (text) async {
      final name = text.trim();
      if (name == tag) return null;
      final e = await ab.renameTag(tag, name);
      if (e == null) return null;
      return e.kind == ApiErrorKind.conflict
          ? l10n.abTagExists
          : l10n.abRenameTagFailed(abReason(l10n, e));
    },
  );
}

/// "编辑备注" (upstream `editAbPeerNoteDialog`).
Future<void> showAbEditNoteDialog(
  TabOverlays overlays,
  AppLocalizations l10n,
  Peer peer,
) {
  return _textDialog(
    overlays,
    title: l10n.abEditNote,
    label: l10n.abFieldNote,
    initial: peer.note,
    note: l10n.abNoteLimit,
    maxLength: 300,
    allowEmpty: true,
    submit: (text) async {
      if (text == peer.note) return null;
      final e = await appCore.addressBook.setNote(peer.id, text);
      return e == null ? null : l10n.abEditNoteFailed(abReason(l10n, e));
    },
  );
}

/// "设置共享密码" (upstream `setSharedAbPasswordDialog`): "确定" waits for a password.
Future<void> showAbSharedPasswordDialog(
  TabOverlays overlays,
  AppLocalizations l10n,
  Peer peer,
) {
  return _textDialog(
    overlays,
    title: l10n.abSetSharedPassword,
    label: l10n.abFieldPassword,
    note: l10n.abVisibleToMembers,
    obscure: true,
    submit: (text) async {
      final e = await appCore.addressBook.setSharedPassword(peer.id, text);
      return e == null
          ? null
          : l10n.abSetSharedPasswordFailed(abReason(l10n, e));
    },
  );
}

// ---- Edit tags (upstream `editAbTagDialog`): of one device, or of the picked ones.

Future<void> showAbEditTagsDialog(
  TabOverlays overlays,
  List<String> ids,
  List<dynamic> initial,
) {
  return _show<void>(
    overlays,
    (close) =>
        _EditTagsDialog(ids: ids, initial: initial, close: () => close(null)),
  );
}

class _EditTagsDialog extends StatefulWidget {
  const _EditTagsDialog({
    required this.ids,
    required this.initial,
    required this.close,
  });

  final List<String> ids;
  final List<dynamic> initial;
  final VoidCallback close;

  @override
  State<_EditTagsDialog> createState() => _EditTagsDialogState();
}

class _EditTagsDialogState extends _FormState<_EditTagsDialog> {
  late final _tags = {for (final t in widget.initial) t.toString()};

  @override
  void dismiss() => widget.close();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ab = appCore.addressBook;
    return form(
      title: l10n.abEditTags,
      action: l10n.homeOk,
      onAction: () => run(() async {
        final e = await ab.setTags(widget.ids, [
          for (final t in ab.tags)
            if (_tags.contains(t.name)) t.name,
        ]);
        return e == null ? null : l10n.abEditTagsFailed(abReason(l10n, e));
      }, widget.close),
      onCancel: widget.close,
      children: [
        _tagChoice(
          _tags,
          busy
              ? null
              : (t) => setState(
                  () => _tags.contains(t) ? _tags.remove(t) : _tags.add(t),
                ),
        ),
      ],
    );
  }
}

// ---- Change tag colour (`p1-tagcolor-*`, 02 §3.6).

/// A row of presets (upstream's Material colours of `str2color2`) and the `#RRGGBB` value; the
/// designer's dialog adds the colour wheel.
const _presets = [
  0xFFF44336,
  0xFFFF9800,
  0xFFCDDC39,
  0xFF4CAF50,
  0xFF009688,
  0xFF2196F3,
  0xFF3F51B5,
  0xFF9C27B0,
];

/// `#RRGGBB` (or without `#`) as an opaque ARGB value; null when it is not one.
int? parseTagColor(String text) {
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(text.trim());
  return m == null ? null : 0xFF000000 | int.parse(m.group(1)!, radix: 16);
}

String _hex(int color) =>
    '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Future<void> showAbTagColorDialog(TabOverlays overlays, String tag) =>
    _show<void>(
      overlays,
      (close) => _TagColorDialog(tag: tag, close: () => close(null)),
    );

class _TagColorDialog extends StatefulWidget {
  const _TagColorDialog({required this.tag, required this.close});

  final String tag;
  final VoidCallback close;

  @override
  State<_TagColorDialog> createState() => _TagColorDialogState();
}

class _TagColorDialogState extends _FormState<_TagColorDialog> {
  @override
  void dismiss() => widget.close();

  late final int _old = abTagColor(widget.tag).toARGB32();
  late int _color = _old;
  late final _value = TextEditingController(text: _hex(_old));
  bool _bad = false;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _pick(int color) => setState(() {
    _color = color;
    _bad = false;
    _value.text = _hex(color);
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = LgTokens.of(context).colors;
    return form(
      title: l10n.abTagColorTitle,
      action: l10n.abSave,
      onAction: _bad || _color == _old
          ? null
          : () => run(() async {
              final e = await appCore.addressBook.setTagColor(
                widget.tag,
                _color,
              );
              return e == null
                  ? null
                  : l10n.abTagColorFailed(abReason(l10n, e));
            }, widget.close),
      onCancel: widget.close,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: LgTagChip(LgDeviceTag(widget.tag, Color(_color))),
        ),
        _labeled(
          context,
          l10n.abTagColor,
          Wrap(
            spacing: LgSpace.s2,
            children: [
              for (final p in _presets)
                Semantics(
                  button: true,
                  selected: p == _color,
                  label: _hex(p),
                  child: GestureDetector(
                    onTap: busy ? null : () => _pick(p),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(p),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: p == _color ? c.accent : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _labeled(
          context,
          l10n.abTagColorValue,
          LgTextField(
            controller: _value,
            enabled: !busy,
            semanticLabel: l10n.abTagColorValue,
            errorText: _bad ? l10n.abTagColorBad : null,
            onChanged: (text) => setState(() {
              final v = parseTagColor(text);
              _bad = v == null;
              if (v != null) _color = v;
            }),
          ),
        ),
      ],
    );
  }
}

// ---- Add to address book (upstream `addPeersToAbDialog`).

/// Adds [peers] to a book chosen among [targets]; straight into it when the personal book is the
/// only book there is, and only when that fails the dialog comes up to say why. True when they
/// were added.
Future<bool> showAbAddToDialog(
  TabOverlays overlays,
  AppLocalizations l10n,
  List<Peer> peers,
  List<AbProfile> targets,
) async {
  final ab = appCore.addressBook;
  String? failed;
  if (ab.books.length == 1 && targets.length == 1) {
    final book = targets.single;
    if (ab.isFull(book)) {
      failed = l10n.abFull;
    } else {
      final e = await ab.addPeersTo(book, peers);
      if (e == null) return true;
      if (e.kind == ApiErrorKind.unauthorized) return false;
      failed = l10n.abAddDeviceFailed(abReason(l10n, e));
    }
  }
  return await _show<bool>(
        overlays,
        (close) => _AddToDialog(
          peers: peers,
          targets: targets,
          close: close,
          error: failed,
        ),
      ) ??
      false;
}

class _AddToDialog extends StatefulWidget {
  const _AddToDialog({
    required this.peers,
    required this.targets,
    required this.close,
    this.error,
  });

  final List<Peer> peers;
  final List<AbProfile> targets;
  final void Function(bool? added) close;

  /// Why adding straight away failed.
  final String? error;

  @override
  State<_AddToDialog> createState() => _AddToDialogState();
}

class _AddToDialogState extends _FormState<_AddToDialog> {
  late AbProfile _book = widget.targets.first;

  @override
  void initState() {
    super.initState();
    error = widget.error;
  }

  @override
  void dismiss() => widget.close(false);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ab = appCore.addressBook;
    return form(
      title: l10n.abAddToAb,
      action: l10n.abAdd,
      busyAction: l10n.abAdding,
      onAction: () {
        if (ab.isFull(_book)) {
          setState(() => error = l10n.abFull);
          return;
        }
        run(() async {
          final e = await ab.addPeersTo(_book, widget.peers);
          return e == null ? null : l10n.abAddDeviceFailed(abReason(l10n, e));
        }, () => widget.close(true));
      },
      onCancel: () => widget.close(false),
      children: [
        _labeled(
          context,
          l10n.abChooseBook,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final b in widget.targets)
                LgMenuItem(
                  label: abBookName(l10n, b),
                  description: abBookRights(l10n, b),
                  checked: b.guid == _book.guid,
                  keepOpen: true,
                  onPressed: busy ? null : () => setState(() => _book = b),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- Where the device is ("所在地址簿", upstream `_existIn`).

Future<void> showAbBooksDialog(
  TabOverlays overlays,
  AppLocalizations l10n,
  String id,
) {
  final names = [
    for (final b in appCore.addressBook.idExistIn(id)) abBookName(l10n, b),
  ];
  return _show<void>(
    overlays,
    (close) => LgConfirmDialog(
      title: l10n.abBooksTitle,
      body: names.join('\n'),
      actions: [
        LgDialogAction(
          label: l10n.homeOk,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: () => close(null),
        ),
      ],
      children: [Text(l10n.abSharedNote)],
    ),
  );
}
