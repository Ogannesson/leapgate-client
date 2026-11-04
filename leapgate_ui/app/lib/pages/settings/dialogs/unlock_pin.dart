import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/settings/unlock.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_banner.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_form_dialog.dart';
import '../../../widgets/lg_panel_inputs.dart';

// The unlock PIN's two dialogs (02 §1.2.6, §1.6.7), over the home tab only. The settings page's
// lock bar and the home page's password row ("修改", R2-Q31) unlock through [unlockSettings].

/// Unlocks [settingsUnlock], asking for the PIN in a dialog when one is set; true when the
/// settings are unlocked now (also when they were already, or on the portable version).
Future<bool> unlockSettings(TabOverlays overlays, AppLocalizations l10n) =>
    settingsUnlock.unlock(
      (pin) => overlays.show<PinAnswer>(
        null,
        (context, close) => LgDialogScrim(
          onEscape: () => close(null),
          child: _EnterPinDialog(l10n: l10n, pin: pin, close: close),
        ),
      ),
    );

class _EnterPinDialog extends StatefulWidget {
  const _EnterPinDialog({
    required this.l10n,
    required this.pin,
    required this.close,
  });

  final AppLocalizations l10n;
  final String pin;
  final void Function(PinAnswer?) close;

  @override
  State<_EnterPinDialog> createState() => _EnterPinDialogState();
}

class _EnterPinDialogState extends State<_EnterPinDialog> {
  final _text = TextEditingController();
  bool _wrong = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (unlockPinMatches(_text.text, widget.pin)) {
      widget.close(PinAnswer.correct);
    } else {
      setState(() => _wrong = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return LgFormDialog(
      title: l10n.settingsUnlockPinTitle,
      icon: LgIcons.lock,
      actions: [
        LgDialogAction(
          label: l10n.homeCancel,
          onPressed: () => widget.close(null),
        ),
        LgDialogAction(
          label: l10n.settingsUnlock,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: _submit,
        ),
      ],
      children: [
        LgFormField(
          label: l10n.settingsUnlockPin,
          child: LgPasswordField(
            controller: _text,
            autofocus: true,
            placeholder: l10n.settingsUnlockPinTitle,
            showLabel: l10n.connShowPassword,
            hideLabel: l10n.connHidePassword,
            errorText: _wrong ? l10n.settingsUnlockPinWrong : null,
            onChanged: (_) {
              if (_wrong) setState(() => _wrong = false);
            },
            onSubmitted: (_) => _submit(),
          ),
        ),
        // Upstream only took the PIN once one was set; a forgotten PIN meant the command line.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: LgButton(
            label: l10n.settingsUnlockUseAdmin,
            kind: LgButtonKind.text,
            icon: LgIcons.uac,
            onPressed: () => widget.close(PinAnswer.useAdministrator),
          ),
        ),
      ],
    );
  }
}

/// "设置 PIN" / "修改 PIN": saves the new unlock PIN; true when it was saved.
Future<bool> showSetUnlockPinDialog(
  TabOverlays overlays,
  AppLocalizations l10n,
) async =>
    await overlays.show<bool>(
      null,
      (context, close) => LgDialogScrim(
        onEscape: () => close(false),
        child: _SetPinDialog(
          l10n: l10n,
          maxLength: settingsUnlock.pinMaxLength,
          close: close,
        ),
      ),
    ) ??
    false;

class _SetPinDialog extends StatefulWidget {
  const _SetPinDialog({
    required this.l10n,
    required this.maxLength,
    required this.close,
  });

  final AppLocalizations l10n;
  final int maxLength;
  final void Function(bool?) close;

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();
  bool _failed = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  NewPinError? get _error =>
      checkNewUnlockPin(_pin.text, _confirmation.text, widget.maxLength);

  void _changed(String _) => setState(() => _failed = false);

  void _submit() {
    if (_error != null) return;
    if (settingsUnlock.savePin(_pin.text.trim())) {
      widget.close(true);
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final error = _error;
    return LgFormDialog(
      title: l10n.settingsUnlockSetPinTitle,
      icon: LgIcons.lock,
      banner: _failed
          ? LgBanner(
              tone: LgTone.error,
              slim: true,
              text: l10n.settingsSaveFailed,
            )
          : null,
      actions: [
        LgDialogAction(
          label: l10n.homeCancel,
          onPressed: () => widget.close(false),
        ),
        LgDialogAction(
          label: l10n.homeOk,
          kind: LgButtonKind.primary,
          isDefault: true,
          // Greyed while the PIN is too short or the two differ (`p6-dl-pin`).
          onPressed: error == null ? _submit : null,
        ),
      ],
      children: [
        LgFormField(
          label: l10n.settingsUnlockPin,
          hint: l10n.settingsUnlockPinRule,
          child: LgPasswordField(
            controller: _pin,
            autofocus: true,
            showLabel: l10n.connShowPassword,
            hideLabel: l10n.connHidePassword,
            errorText: error == NewPinError.tooLong
                ? l10n.settingsUnlockPinTooLong(widget.maxLength)
                : null,
            onChanged: _changed,
            onSubmitted: (_) => _submit(),
          ),
        ),
        LgFormField(
          label: l10n.settingsUnlockPinConfirm,
          child: LgPasswordField(
            controller: _confirmation,
            showLabel: l10n.connShowPassword,
            hideLabel: l10n.connHidePassword,
            // Once something is typed into it.
            errorText:
                error == NewPinError.mismatch && _confirmation.text.isNotEmpty
                ? l10n.settingsUnlockPinMismatch
                : null,
            onChanged: _changed,
            onSubmitted: (_) => _submit(),
          ),
        ),
      ],
    );
  }
}
