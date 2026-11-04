import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/settings/settings_api.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_form_dialog.dart';
import '../../../widgets/lg_text_field.dart';

/// "设置 Telegram 机器人" (02 §1.6.4, upstream `changeBot`) over the home tab; true when Rust
/// reached the bot and the service kept it (S10). The request holds Rust's save lock, so the
/// dialog stays up and can't be sent twice until it answers (`LEAPGATE.md` §10.14).
Future<bool> showTelegramDialog(
    TabOverlays overlays, AppLocalizations l10n) async {
  final busy = ValueNotifier(false);
  return await overlays.show<bool>(
        null,
        (context, close) => LgDialogScrim(
          onEscape: () {
            if (!busy.value) close(false);
          },
          child: _TelegramDialog(l10n: l10n, busy: busy, close: close),
        ),
      ) ??
      false;
}

class _TelegramDialog extends StatefulWidget {
  const _TelegramDialog(
      {required this.l10n, required this.busy, required this.close});

  final AppLocalizations l10n;
  final ValueNotifier<bool> busy;
  final void Function(bool?) close;

  @override
  State<_TelegramDialog> createState() => _TelegramDialogState();
}

class _TelegramDialogState extends State<_TelegramDialog> {
  final _token = TextEditingController();
  bool get _busy => widget.busy.value;
  set _busy(bool value) => widget.busy.value = value;

  /// S10's result when it was not `ok`.
  String? _failed;

  @override
  void initState() {
    super.initState();
    _token.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final typed = _token.text.trim();
    if (_busy || typed.isEmpty) return;
    setState(() {
      _busy = true;
      _failed = null;
    });
    final check = await settingsApi.verifyBot(typed);
    if (!mounted) return;
    if (check.result == 'ok') {
      widget.close(true);
      return;
    }
    setState(() {
      _busy = false;
      _failed = check.result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    // `other` is a token Rust took but the service did not keep (§10.13 S10).
    final error = switch (_failed) {
      null => null,
      'network' => l10n.settingsTwoFactorBotNetwork,
      'no_chat' => l10n.settingsTwoFactorBotNoChat,
      'invalid_token' => l10n.settingsTwoFactorBotInvalid,
      _ => l10n.settingsSaveFailed,
    };
    return LgFormDialog(
      title: l10n.settingsTwoFactorBotTitle,
      icon: LgIcons.send,
      note: l10n.settingsTwoFactorBotBody,
      actions: [
        LgDialogAction(
            label: l10n.homeCancel,
            onPressed: _busy ? null : () => widget.close(false)),
        LgDialogAction(
          label: _busy ? l10n.settingsTwoFactorVerifying : l10n.homeOk,
          kind: LgButtonKind.primary,
          isDefault: true,
          busy: _busy,
          onPressed: _token.text.trim().isEmpty ? null : _submit,
        ),
      ],
      children: [
        LgFormField(
          label: l10n.settingsTwoFactorBotToken,
          child: LgTextField(
            controller: _token,
            placeholder: l10n.settingsTwoFactorBotTokenPlaceholder,
            errorText: error,
            enabled: !_busy,
            autofocus: true,
          ),
        ),
      ],
    );
  }
}
