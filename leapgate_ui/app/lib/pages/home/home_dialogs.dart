import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/permanent_password.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import '../../l10n/app_localizations.dart';
import '../../shell/tab_overlays.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_feedback.dart';
import '../../widgets/lg_password_dialog.dart';
import '../../widgets/lg_text_field.dart';

// The home page's dialogs (01 P1 block K, §4.4): over the home tab only (its scope in
// [TabOverlays] is null). The permanent password dialog keeps upstream's checks and calls
// (`desktop/pages/desktop_home_page.dart:890-1126`).

/// A yes-or-no question with a destructive main button; true when it was confirmed.
Future<bool> confirmOnHome(
  TabOverlays overlays, {
  required String title,
  required String action,
  required String cancel,
}) async =>
    await overlays.show<bool>(
      null,
      (context, close) => LgDialogScrim(
        onEscape: () => close(false),
        child: LgConfirmDialog(
          title: title,
          actions: [
            LgDialogAction(label: cancel, onPressed: () => close(false)),
            LgDialogAction(
              label: action,
              kind: LgButtonKind.dangerSolid,
              isDefault: true,
              onPressed: () => close(true),
            ),
          ],
        ),
      ),
    ) ??
    false;

/// "Rename" (upstream `renameDialog`): the alias, trimmed; null when cancelled.
Future<String?> askAlias(
  TabOverlays overlays,
  AppLocalizations l10n, {
  required String alias,
}) => overlays.show<String>(
  null,
  (context, close) => LgDialogScrim(
    onEscape: () => close(null),
    child: _RenameDialog(l10n: l10n, alias: alias, close: close),
  ),
);

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({
    required this.l10n,
    required this.alias,
    required this.close,
  });

  final AppLocalizations l10n;
  final String alias;
  final void Function(String?) close;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _text = TextEditingController(text: widget.alias)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.alias.length,
    );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() => widget.close(_text.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return LgConfirmDialog(
      title: l10n.peerMenuRename,
      actions: [
        LgDialogAction(
          label: l10n.homeCancel,
          onPressed: () => widget.close(null),
        ),
        LgDialogAction(
          label: l10n.homeOk,
          kind: LgButtonKind.primary,
          onPressed: _submit,
        ),
      ],
      children: [
        LgTextField(
          controller: _text,
          autofocus: true,
          semanticLabel: l10n.peerMenuRename,
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}

/// "Set permanent password" from the password row's "Change" (portable version; the installed
/// one unlocks first, M6).
Future<void> showPermanentPasswordDialog(
  TabOverlays overlays,
  AppLocalizations l10n,
) async {
  final state = await readPermanentPasswordState();
  // Upstream's limit on both fields (`desktop_home_page.dart:909`).
  final maxLength = bind.mainMaxEncryptLen();
  await overlays.show<void>(
    null,
    (context, close) => LgDialogScrim(
      onEscape: () => close(null),
      child: PermanentPasswordDialog(
        l10n: l10n,
        state: state,
        maxLength: maxLength,
        close: () => close(null),
      ),
    ),
  );
}

class PermanentPasswordDialog extends StatefulWidget {
  const PermanentPasswordDialog({
    super.key,
    required this.l10n,
    required this.state,
    required this.maxLength,
    required this.close,
  });

  final AppLocalizations l10n;
  final PermanentPasswordState state;
  final int maxLength;
  final VoidCallback close;

  @override
  State<PermanentPasswordDialog> createState() =>
      _PermanentPasswordDialogState();
}

class _PermanentPasswordDialogState extends State<PermanentPasswordDialog> {
  final _confirmation = TextEditingController();
  final _first = TextEditingController();
  PasswordSaveError? _error;
  bool _busy = false;

  /// Typing clears the error, as upstream's onChanged.
  void _changed(String _) => setState(() => _error = null);

  @override
  void dispose() {
    _first.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  /// "OK" is available once either field has text (01 P1 block K); the rules are checked when it
  /// is pressed, as upstream.
  bool get _canSubmit =>
      !_busy &&
      (_first.text.trim().isNotEmpty || _confirmation.text.trim().isNotEmpty);

  Future<void> _run(Future<PasswordSaveError?> Function() save) async {
    setState(() => _busy = true);
    final error = await save();
    if (!mounted) return;
    if (error == null) {
      widget.close();
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  void _submit() {
    if (_canSubmit) {
      _run(() => savePermanentPassword(_first.text, _confirmation.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final pass = _first.text.trim();
    // The component has one line under the title; the two notes share it.
    final notes = [
      if (widget.state.isSet) l10n.pwdNotShown,
      if (widget.state.clearsTrustedDevices) l10n.pwdClearsTrustedDevices,
    ];
    return LgPasswordDialog(
      labels: LgPasswordDialogLabels(
        title: l10n.pwdTitle,
        passwordLabel: l10n.pwdPassword,
        passwordPlaceholder: widget.state.isSet
            ? l10n.pwdEnterNew
            : l10n.pwdEnter,
        confirmLabel: l10n.pwdConfirm,
        confirmPlaceholder: l10n.pwdEnterAgain,
        showPassword: l10n.connShowPassword,
        hidePassword: l10n.connHidePassword,
        strength: l10n.pwdStrength,
        ruleMet: l10n.pwdRuleMet,
        ruleUnmet: l10n.pwdRuleUnmet,
        cancel: l10n.homeCancel,
        confirm: l10n.homeOk,
        remove: l10n.pwdRemove,
      ),
      passwordController: _first,
      confirmController: _confirmation,
      maxLength: widget.maxLength,
      rules: [
        for (final (rule, label) in [
          (PasswordRule.digit, l10n.pwdRuleDigit),
          (PasswordRule.uppercase, l10n.pwdRuleUppercase),
          (PasswordRule.lowercase, l10n.pwdRuleLowercase),
          (PasswordRule.length8, l10n.pwdRuleLength),
        ])
          LgPasswordRule(label, passwordRuleMet(rule, pass)),
      ],
      strength: passwordStrengthBars(pass),
      note: notes.isEmpty ? null : notes.join('\n'),
      // The banner under the title: saving failed, or the rules are not met (the component has
      // no line under the first field).
      error: switch (_error) {
        PasswordSaveError.failed => l10n.pwdSaveFailed,
        PasswordSaveError.rules => l10n.pwdRulesNotMet,
        _ => null,
      },
      confirmError: _error == PasswordSaveError.mismatch
          ? l10n.pwdMismatch
          : null,
      onChanged: _changed,
      onCancel: widget.close,
      onConfirm: _canSubmit ? _submit : null,
      // Given whenever a password is set: null would take the button away while saving.
      onRemove: widget.state.isSet
          ? () {
              if (!_busy) _run(removePermanentPassword);
            }
          : null,
    );
  }
}
