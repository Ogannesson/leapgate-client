import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/address_book.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;
import 'package:flutter_hbb/models/peer_model.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_add_device_dialog.dart';
import '../../../widgets/lg_banner.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_form_dialog.dart';
import '../../../widgets/lg_menu.dart';
import '../../../widgets/lg_panel_inputs.dart';
import '../../../widgets/lg_tag_chips.dart';
import '../../../widgets/lg_tag_color_dialog.dart';
import '../../../widgets/lg_text_field.dart';
import 'ab_parts.dart';

// The address book's dialogs (01 P1 blocks F, G and §4.4, 02 §3.6), over the home tab. Errors
// stay in the dialog, which stays open (01 P1 block G "添加设备"); the two-sentence form is the
// list banner's. Rewritten after upstream `common/widgets/address_book.dart` (`addIdToCurrentAb`,
// `abAddTag`, `AddressBookTag._showMenu`) and `common/widgets/dialog.dart` (`editAbTagDialog`,
// `editAbPeerNoteDialog`, `addPeersToAbDialog`, `setSharedAbPasswordDialog`).

Future<T?> _show<T>(
  TabOverlays overlays,
  Widget Function(void Function(T? result) close) dialog,
) => overlays.show<T>(
  null,
  (context, close) =>
      LgDialogScrim(onEscape: () => close(null), child: dialog(close)),
);

/// The current book's tags as toggles, [on] the picked ones.
List<LgTagToggleItem> _tagItems(Set<String> on) => [
  for (final t in appCore.addressBook.tags)
    LgTagToggleItem(
      id: t.name,
      label: t.name,
      color: Color(t.color),
      on: on.contains(t.name),
    ),
];

void _flip(Set<String> tags, String tag) =>
    tags.contains(tag) ? tags.remove(tag) : tags.add(tag);

/// What every form dialog here shares: busy while submitting, the error under the title, and
/// closing when the address book goes away.
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

  Widget? get banner => error == null
      ? null
      : LgBanner(tone: LgTone.error, text: error, slim: true);

  /// `LgFormDialog` with "取消" and [action].
  Widget form({
    required String title,
    required LgIcons icon,
    String? note,
    required List<Widget> children,
    required String action,
    required VoidCallback? onAction,
    required VoidCallback onCancel,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return LgFormDialog(
      title: title,
      icon: icon,
      note: note,
      banner: banner,
      actions: [
        LgDialogAction(label: l10n.homeCancel, onPressed: onCancel),
        LgDialogAction(
          label: action,
          kind: LgButtonKind.primary,
          isDefault: true,
          busy: busy,
          onPressed: onAction,
        ),
      ],
      children: children,
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
  void initState() {
    super.initState();
    _id.addListener(_idChanged);
  }

  @override
  void dispose() {
    for (final c in [_id, _alias, _password, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void dismiss() => widget.close();

  /// "添加" follows the ID field; typing clears what was wrong with it.
  void _idChanged() => setState(() => _idError = null);

  /// The ID as typed, without the spaces of its groups.
  String get _cleanId => _id.text.replaceAll(RegExp(r'\s'), '');

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    final ab = appCore.addressBook;
    final book = ab.current;
    if (book == null || busy) return;
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
    return LgAddDeviceDialog(
      labels: LgAddDeviceLabels(
        title: l10n.abAddDevice,
        idLabel: l10n.abFieldId,
        idPlaceholder: l10n.abIdPlaceholder,
        aliasLabel: l10n.abFieldAlias,
        aliasPlaceholder: l10n.abAliasPlaceholder,
        passwordLabel: l10n.abFieldPassword,
        passwordPlaceholder: l10n.abPasswordPlaceholder,
        showPassword: l10n.connShowPassword,
        hidePassword: l10n.connHidePassword,
        noteLabel: l10n.abFieldNote,
        notePlaceholder: l10n.abNoteLimit,
        tagsLabel: l10n.abFieldTags,
        cancel: l10n.homeCancel,
        submit: l10n.abAdd,
        busySubmit: l10n.abAdding,
      ),
      idController: _id,
      idInputFormatters: [_IdGroups()],
      aliasController: _alias,
      noteController: _note,
      passwordController: shared ? _password : null,
      passwordHint: shared ? l10n.abVisibleToMembers : null,
      target: l10n.abAddTo(abBookName(l10n, book)),
      tags: _tagItems(_tags),
      onToggleTag: busy ? null : (t) => setState(() => _flip(_tags, t)),
      idError: _idError,
      error: error,
      busy: busy,
      onSubmit: _cleanId.isEmpty ? null : _submit,
      onCancel: widget.close,
    );
  }
}

/// The ID in groups of three as it is typed (01 P1 block G, "246 813 579"), as [formatPeerId]
/// shows IDs; the caret stays after the same digit.
class _IdGroups extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid) return newValue;
    final text = formatPeerId(newValue.text);
    if (text == newValue.text) return newValue;
    final end = newValue.selection.extentOffset.clamp(0, newValue.text.length);
    final before = newValue.text.substring(0, end).replaceAll(' ', '').length;
    var at = 0;
    for (var n = 0; at < text.length && n < before; at++) {
      if (text[at] != ' ') n++;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: at),
    );
  }
}

// ---- One text field: add tag, rename tag, edit note, shared password.

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.icon,
    required this.label,
    required this.action,
    required this.close,
    required this.submit,
    this.initial = '',
    this.hint,
    this.check,
    this.obscure = false,
    this.area = false,
    this.allowEmpty = false,
  });

  final String title;
  final LgIcons icon;
  final String label;

  /// The main button: what it does ("添加", "保存").
  final String action;
  final String initial;

  /// Under the field.
  final String? hint;
  final bool obscure;

  /// The note: several lines, at most 300 characters, counted at the label.
  final bool area;
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
  static const _noteMax = 300;

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
    if (busy) return;
    final problem = widget.check?.call(_text.text);
    if (problem != null) {
      setState(() => _fieldError = problem);
      return;
    }
    run(() => widget.submit(_text.text), widget.close);
  }

  void _changed(String _) => setState(() => _fieldError = null);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return form(
      title: widget.title,
      icon: widget.icon,
      action: widget.action,
      onAction: widget.allowEmpty || _text.text.isNotEmpty ? _submit : null,
      onCancel: widget.close,
      children: [
        LgFormField(
          label: widget.label,
          // In characters, as the limit counts them.
          counter: widget.area
              ? '${_text.text.characters.length} / $_noteMax'
              : null,
          hint: widget.hint,
          child: widget.area
              ? LgTextArea(
                  controller: _text,
                  enabled: !busy,
                  maxLength: _noteMax,
                  semanticLabel: widget.label,
                  onChanged: _changed,
                )
              : widget.obscure
              ? LgPasswordField(
                  controller: _text,
                  autofocus: true,
                  enabled: !busy,
                  semanticLabel: widget.label,
                  showLabel: l10n.connShowPassword,
                  hideLabel: l10n.connHidePassword,
                  errorText: _fieldError,
                  onChanged: _changed,
                  onSubmitted: (_) => _submit(),
                )
              : LgTextField(
                  controller: _text,
                  autofocus: true,
                  enabled: !busy,
                  semanticLabel: widget.label,
                  errorText: _fieldError,
                  onChanged: _changed,
                  onSubmitted: (_) => _submit(),
                ),
        ),
      ],
    );
  }
}

Future<void> _textDialog(
  TabOverlays overlays, {
  required String title,
  required LgIcons icon,
  required String label,
  required String action,
  required Future<String?> Function(String text) submit,
  String initial = '',
  String? hint,
  String? Function(String text)? check,
  bool obscure = false,
  bool area = false,
  bool allowEmpty = false,
}) => _show<void>(
  overlays,
  (close) => _TextDialog(
    title: title,
    icon: icon,
    label: label,
    action: action,
    initial: initial,
    hint: hint,
    check: check,
    obscure: obscure,
    area: area,
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
    icon: LgIcons.tag,
    label: l10n.abFieldTags,
    action: l10n.abAdd,
    hint: l10n.abAddTagNote,
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
    icon: LgIcons.tag,
    label: l10n.abFieldName,
    action: l10n.abSave,
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
    icon: LgIcons.note,
    label: l10n.abFieldNote,
    action: l10n.abSave,
    initial: peer.note,
    area: true,
    allowEmpty: true,
    submit: (text) async {
      if (text == peer.note) return null;
      final e = await appCore.addressBook.setNote(peer.id, text);
      return e == null ? null : l10n.abEditNoteFailed(abReason(l10n, e));
    },
  );
}

/// "设置共享密码" (upstream `setSharedAbPasswordDialog`): "保存" waits for a password.
Future<void> showAbSharedPasswordDialog(
  TabOverlays overlays,
  AppLocalizations l10n,
  Peer peer,
) {
  return _textDialog(
    overlays,
    title: l10n.abSetSharedPassword,
    icon: LgIcons.key,
    label: l10n.abFieldPassword,
    action: l10n.abSave,
    hint: l10n.abVisibleToMembers,
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
      icon: LgIcons.tag,
      action: l10n.abSave,
      onAction: () => run(() async {
        final e = await ab.setTags(widget.ids, [
          for (final t in ab.tags)
            if (_tags.contains(t.name)) t.name,
        ]);
        return e == null ? null : l10n.abEditTagsFailed(abReason(l10n, e));
      }, widget.close),
      onCancel: widget.close,
      children: [
        // A field like the add-device dialog's tag row, which also spaces it from the title.
        LgFormField(
          label: l10n.abFieldTags,
          child: LgTagChooser(
            items: _tagItems(_tags),
            semanticLabel: l10n.abFieldTags,
            onToggle: busy ? null : (t) => setState(() => _flip(_tags, t)),
          ),
        ),
      ],
    );
  }
}

// ---- Change tag colour (`p1-tagcolor-*`, 02 §3.6).

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LgTagColorDialog(
      labels: LgTagColorDialogLabels(
        title: l10n.abTagColorTitle,
        colorLabel: l10n.abTagColor,
        customLabel: l10n.abTagColorCustom,
        valueLabel: l10n.abTagColorValue,
        hexPlaceholder: '#RRGGBB',
        hexError: l10n.abTagColorBad,
        brightnessLabel: l10n.abTagColorBrightness,
        wheelLabel: l10n.abTagColorWheel,
        cancel: l10n.homeCancel,
        save: l10n.abSave,
        busySave: l10n.abSaving,
        presetNames: [
          l10n.abTagPresetRose,
          l10n.abTagPresetTerracotta,
          l10n.abTagPresetOchre,
          l10n.abTagPresetMoss,
          l10n.abTagPresetTeal,
          l10n.abTagPresetBlue,
          l10n.abTagPresetPurple,
          l10n.abTagPresetGray,
        ],
      ),
      tagName: widget.tag,
      initialColor: abTagColor(widget.tag),
      busy: busy,
      error: error,
      onCancel: widget.close,
      onSave: (color) {
        if (busy) return;
        run(() async {
          final e = await appCore.addressBook.setTagColor(widget.tag, color);
          return e == null ? null : l10n.abTagColorFailed(abReason(l10n, e));
        }, widget.close);
      },
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
      icon: LgIcons.book,
      action: l10n.abAdd,
      onAction: () {
        if (busy) return;
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
        // No component of its own yet: the books as checked menu rows.
        LgFormField(
          label: l10n.abChooseBook,
          child: Column(
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
    (close) => LgFormDialog(
      title: l10n.abBooksTitle,
      icon: LgIcons.book,
      note: l10n.abSharedNote,
      actions: [
        LgDialogAction(
          label: l10n.homeOk,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: () => close(null),
        ),
      ],
      children: [for (final n in names) Text(n)],
    ),
  );
}
