import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/settings/settings_api.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_banner.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_form_dialog.dart';
import '../../../widgets/lg_text_field.dart';
import 'server_dialog.dart' show ServerErrorDetail;

/// "设置 Telegram 机器人" (02 §1.6.4, upstream `changeBot`) over the home tab; true when the bot
/// and the chat the user confirmed were saved. Rust looks the bot up first and saves nothing:
/// the chat its latest message came from is shown to confirm, since anyone can message a bot
/// whose name they find. While a request is on its way the dialog can't be closed or sent again.
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

  /// The lookup's answer: not `ok` shows its error, `ok` the chat to confirm.
  BotLookup? _lookup;
  bool _notSaved = false;

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
      _lookup = null;
    });
    final lookup = await settingsApi.lookupBot(typed);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lookup = lookup;
    });
  }

  Future<void> _confirm(BotLookup lookup) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notSaved = false;
    });
    final saved = await settingsApi.saveBot(_token.text.trim(), lookup.chatId);
    if (!mounted) return;
    if (saved) {
      widget.close(true);
      return;
    }
    setState(() {
      _busy = false;
      _notSaved = true;
    });
  }

  /// "@zhangsan", "家里（群组）".
  String _chat(BotLookup lookup) {
    final l10n = widget.l10n;
    return switch (lookup.chatType) {
      'group' || 'supergroup' => l10n.settingsTwoFactorBotGroup(lookup.chatLabel),
      'channel' => l10n.settingsTwoFactorBotChannel(lookup.chatLabel),
      _ => lookup.chatLabel,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final lookup = _lookup;
    if (lookup != null && lookup.result == 'ok') {
      return _confirmation(context, lookup);
    }
    final error = switch (lookup?.result) {
      null => null,
      'network' => l10n.settingsTwoFactorBotNetwork,
      'no_chat' => l10n.settingsTwoFactorBotNoChat,
      'invalid_token' => l10n.settingsTwoFactorBotInvalid,
      _ => l10n.settingsTwoFactorBotFailed,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LgTextField(
                controller: _token,
                placeholder: l10n.settingsTwoFactorBotTokenPlaceholder,
                errorText: error,
                enabled: !_busy,
                autofocus: true,
              ),
              // A lookup that failed otherwise carries Rust's words.
              if (lookup != null &&
                  lookup.result == 'other' &&
                  lookup.text.isNotEmpty)
                ServerErrorDetail(
                    label: l10n.settingsNetDetails, detail: lookup.text),
            ],
          ),
        ),
      ],
    );
  }

  /// Nothing is saved until "确认" (02 §1.6.4).
  Widget _confirmation(BuildContext context, BotLookup lookup) {
    final l10n = widget.l10n;
    final t = LgTokens.of(context);
    return LgFormDialog(
      title: l10n.settingsTwoFactorBotTitle,
      icon: LgIcons.send,
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
          label: l10n.settingsTwoFactorBotConfirm,
          kind: LgButtonKind.primary,
          isDefault: true,
          busy: _busy,
          onPressed: () => _confirm(lookup),
        ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.only(top: LgSpace.s4),
          child: Text(l10n.settingsTwoFactorBotSendTo(_chat(lookup)),
              style: t.text.copyWith(color: t.colors.text)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: LgSpace.s2),
          child: Text(l10n.settingsTwoFactorBotNotYours,
              style: t.textS.copyWith(color: t.colors.text2)),
        ),
      ],
    );
  }
}
