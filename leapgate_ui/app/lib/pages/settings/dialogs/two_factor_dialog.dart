import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/settings/two_factor.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_banner.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_form_dialog.dart';
import '../../../widgets/lg_qr_code.dart';
import '../../../widgets/lg_text_field.dart';

/// "开启二次验证" (02 §1.6.3, upstream `change2fa`) over the home tab, with a new secret from
/// Rust; true when the code checked out and the service kept the secret. While it checks,
/// neither "取消" nor Esc closes it.
Future<bool> showTwoFactorDialog(
    TabOverlays overlays, AppLocalizations l10n) async {
  final link = await newTwoFactorLink();
  if (link.isEmpty) {
    lgBind.leapgateLog(level: 2, msg: 'leapgate ui: no 2FA secret from Rust');
    return false;
  }
  final busy = ValueNotifier(false);
  return await overlays.show<bool>(
        null,
        (context, close) => LgDialogScrim(
          onEscape: () {
            if (!busy.value) close(false);
          },
          child: _TwoFactorDialog(
              l10n: l10n, link: link, busy: busy, close: close),
        ),
      ) ??
      false;
}

class _TwoFactorDialog extends StatefulWidget {
  const _TwoFactorDialog(
      {required this.l10n,
      required this.link,
      required this.busy,
      required this.close});

  final AppLocalizations l10n;

  /// The `otpauth://` link the code holds.
  final String link;
  final ValueNotifier<bool> busy;
  final void Function(bool?) close;

  @override
  State<_TwoFactorDialog> createState() => _TwoFactorDialogState();
}

class _TwoFactorDialogState extends State<_TwoFactorDialog> {
  final _code = TextEditingController();
  bool get _busy => widget.busy.value;
  set _busy(bool value) => widget.busy.value = value;
  bool _wrong = false;
  bool _notSaved = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text;
    if (_busy || !twoFactorCodeComplete(code)) return;
    setState(() {
      _busy = true;
      _wrong = false;
      _notSaved = false;
    });
    final result = await verifyTwoFactor(code);
    if (!mounted) return;
    if (result == 'ok') {
      widget.close(true);
      return;
    }
    setState(() {
      _busy = false;
      _wrong = result == 'wrong_code';
      _notSaved = !_wrong;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(
        ClipboardData(text: twoFactorSecret(widget.link)));
    appCore.toasts.show('Copied');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final complete = twoFactorCodeComplete(_code.text);
    return LgFormDialog(
      title: l10n.settingsTwoFactorDialogTitle,
      icon: LgIcons.shield,
      banner: _notSaved
          ? LgBanner(
              tone: LgTone.error,
              text: l10n.settingsSaveFailed,
              slim: true,
              dense: true)
          : null,
      actions: [
        LgDialogAction(
            label: l10n.homeCancel,
            onPressed: _busy ? null : () => widget.close(false)),
        LgDialogAction(
          label: _busy
              ? l10n.settingsTwoFactorVerifying
              : l10n.settingsTwoFactorTurnOn,
          kind: LgButtonKind.primary,
          isDefault: true,
          busy: _busy,
          onPressed: complete ? _submit : null,
        ),
      ],
      children: [
        const SizedBox(height: LgSpace.s4),
        Center(
          child: LgQrCode(
              data: widget.link, semanticLabel: l10n.settingsTwoFactorQrCode),
        ),
        const SizedBox(height: LgSpace.s2),
        LgQrKeyRow(
          label: l10n.settingsTwoFactorKey,
          value: twoFactorSecretText(widget.link),
          copyLabel: l10n.homeCopy,
          copySemanticLabel: l10n.settingsTwoFactorCopyKey,
          onCopy: _copy,
        ),
        LgFormField(
          label: l10n.settingsTwoFactorCode,
          child: LgTextField(
            controller: _code,
            placeholder: l10n.settingsTwoFactorCodePlaceholder,
            errorText: _wrong ? l10n.settingsTwoFactorWrongCode : null,
            enabled: !_busy,
            autofocus: true,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            // Six digits submit by themselves (02 §1.6.3).
            onChanged: (code) {
              setState(() {
                _wrong = false;
                _notSaved = false;
              });
              if (twoFactorCodeComplete(code)) _submit();
            },
          ),
        ),
      ],
    );
  }
}
