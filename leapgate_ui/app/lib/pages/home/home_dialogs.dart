import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/permanent_password.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/tab_overlays.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_banner.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_feedback.dart';
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
  await overlays.show<void>(
    null,
    (context, close) => LgDialogScrim(
      onEscape: () => close(null),
      child: PermanentPasswordDialog(
        l10n: l10n,
        state: state,
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
    required this.close,
  });

  final AppLocalizations l10n;
  final PermanentPasswordState state;
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
    final t = LgTokens.of(context);
    final c = t.colors;
    final pass = _first.text.trim();
    final strength = passwordStrength(pass);
    return LgConfirmDialog(
      title: l10n.pwdTitle,
      subtitle: widget.state.isSet ? l10n.pwdNotShown : null,
      body: widget.state.clearsTrustedDevices
          ? l10n.pwdClearsTrustedDevices
          : null,
      width: 488,
      actions: [
        if (widget.state.isSet)
          LgDialogAction(
            label: l10n.pwdRemove,
            kind: LgButtonKind.danger,
            onPressed: _busy ? null : () => _run(removePermanentPassword),
          ),
        LgDialogAction(label: l10n.homeCancel, onPressed: widget.close),
        LgDialogAction(
          label: l10n.homeOk,
          kind: LgButtonKind.primary,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
      children: [
        if (_error == PasswordSaveError.failed)
          LgBanner(tone: LgTone.error, text: l10n.pwdSaveFailed),
        Text(l10n.pwdPassword, style: t.textS.copyWith(color: c.text2)),
        LgTextField(
          controller: _first,
          obscureText: true,
          autofocus: true,
          enabled: !_busy,
          semanticLabel: l10n.pwdPassword,
          placeholder: widget.state.isSet ? l10n.pwdEnterNew : l10n.pwdEnter,
          errorText: _error == PasswordSaveError.rules
              ? l10n.pwdRulesNotMet
              : null,
          onChanged: _changed,
          onSubmitted: (_) => _submit(),
        ),
        // Placeholder for the designer's strength bar: three segments, the level in words for
        // screen readers.
        Semantics(
          label: switch (strength) {
            null => null,
            PasswordStrength.weak => l10n.pwdStrengthWeak,
            PasswordStrength.medium => l10n.pwdStrengthMedium,
            PasswordStrength.strong => l10n.pwdStrengthStrong,
          },
          child: Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: LgSpace.s1),
                Expanded(
                  child: Container(
                    height: 4,
                    color: strength != null && strength.index >= i
                        ? c.accent
                        : c.track,
                  ),
                ),
              ],
            ],
          ),
        ),
        Wrap(
          spacing: LgSpace.s3,
          runSpacing: LgSpace.s1,
          children: [
            for (final (rule, label) in [
              (PasswordRule.digit, l10n.pwdRuleDigit),
              (PasswordRule.uppercase, l10n.pwdRuleUppercase),
              (PasswordRule.lowercase, l10n.pwdRuleLowercase),
              (PasswordRule.length8, l10n.pwdRuleLength),
            ])
              _Rule(label: label, met: passwordRuleMet(rule, pass)),
          ],
        ),
        Text(l10n.pwdConfirm, style: t.textS.copyWith(color: c.text2)),
        LgTextField(
          controller: _confirmation,
          obscureText: true,
          enabled: !_busy,
          semanticLabel: l10n.pwdConfirm,
          placeholder: l10n.pwdEnterAgain,
          errorText: _error == PasswordSaveError.mismatch
              ? l10n.pwdMismatch
              : null,
          onChanged: _changed,
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}

/// Placeholder for the designer's rule chip: passed or not, told to screen readers as checked.
class _Rule extends StatelessWidget {
  const _Rule({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final color = met ? t.colors.online : t.colors.text2;
    return Semantics(
      checked: met,
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LgIcon(met ? LgIcons.check : LgIcons.minus, size: 16, color: color),
          const SizedBox(width: LgSpace.s1),
          Text(label, style: t.textS.copyWith(color: color)),
        ],
      ),
    );
  }
}
