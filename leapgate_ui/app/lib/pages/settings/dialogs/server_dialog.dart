import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/server_config.dart';
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
import '../../../widgets/lg_settings_rows.dart';

/// "服务器" (02 §1.6.8) over the home tab, filled with [initial] (the options, or what "导入"
/// found); true when it saved. While it checks and saves, neither "取消" nor Esc closes it: the
/// save runs on, signing out included.
Future<bool> showServerDialog(TabOverlays overlays, AppLocalizations l10n,
    {required ServerSummary summary, required ServerConfig initial}) async {
  final busy = ValueNotifier(false);
  return await overlays.show<bool>(
        null,
        (context, close) => LgDialogScrim(
          onEscape: () {
            if (!busy.value) close(false);
          },
          child: _ServerDialog(
              l10n: l10n,
              summary: summary,
              initial: initial,
              busy: busy,
              close: close),
        ),
      ) ??
      false;
}

class _ServerDialog extends StatefulWidget {
  const _ServerDialog(
      {required this.l10n,
      required this.summary,
      required this.initial,
      required this.busy,
      required this.close});

  final AppLocalizations l10n;
  final ServerSummary summary;
  final ServerConfig initial;

  /// Checking and saving; the scrim reads it for Esc.
  final ValueNotifier<bool> busy;
  final void Function(bool?) close;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final _id = TextEditingController(text: widget.initial.idServer);
  late final _api = TextEditingController(text: widget.initial.apiServer);
  late final _key = TextEditingController(text: widget.initial.key);
  late final _relay = TextEditingController(text: widget.initial.relayServer);
  bool get _busy => widget.busy.value;
  set _busy(bool value) => widget.busy.value = value;
  bool _failed = false;
  Map<String, ({ServerFieldError error, String detail})> _errors = const {};

  @override
  void initState() {
    super.initState();
    for (final c in [_id, _api, _key, _relay]) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final c in [_id, _api, _key, _relay]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  ServerConfig get _config => ServerConfig(
      idServer: _id.text,
      relayServer: _relay.text,
      apiServer: _api.text,
      key: _key.text);

  void _resetAll() {
    for (final c in [_id, _api, _key, _relay]) {
      c.clear();
    }
    setState(() => _errors = const {});
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
      _errors = const {};
    });
    final outcome = await saveServerConfig(_config,
        currentApi: widget.summary.api, account: appCore.account);
    if (!mounted) return;
    if (outcome.result == SaveResult.saved ||
        outcome.result == SaveResult.savedLocal) {
      widget.close(true);
      return;
    }
    setState(() {
      _busy = false;
      _errors = outcome.errors;
      _failed = outcome.result == SaveResult.failed;
    });
  }

  String? _errorText(String key) => switch (_errors[key]?.error) {
        null => null,
        ServerFieldError.unresolvable => widget.l10n.settingsNetUnresolvable,
        ServerFieldError.apiScheme => widget.l10n.settingsNetApiScheme,
        ServerFieldError.keyFormat => widget.l10n.settingsNetKeyInvalid,
      };

  Widget _field(String key, String label, TextEditingController controller,
          {String? hint, Widget? below}) =>
      LgFormField(
        label: label,
        hint: hint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LgTextField(
              controller: controller,
              errorText: _errorText(key),
              enabled: !_busy,
            ),
            if (_errors[key]?.detail.isNotEmpty == true)
              ServerErrorDetail(
                  label: widget.l10n.settingsNetDetails,
                  detail: _errors[key]!.detail),
            ?below,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final t = LgTokens.of(context);
    final id = _id.text.trim();
    final defaultId = defaultIdServer(widget.summary);
    final fallbackApi = resolveApiServer('', id);
    final effectiveApi = resolveApiServer(_api.text.trim(), id);
    final signsOut =
        appCore.account.loggedIn && effectiveApi != widget.summary.api;
    return LgFormDialog(
      title: l10n.settingsNetServer,
      icon: LgIcons.server,
      banner: _failed
          ? LgBanner(
              tone: LgTone.error,
              text: l10n.settingsSaveFailed,
              slim: true,
              dense: true)
          : null,
      leading: LgButton(
        label: l10n.settingsNetResetAll,
        kind: LgButtonKind.text,
        onPressed: _busy ? null : _resetAll,
      ),
      actions: [
        LgDialogAction(
            label: l10n.homeCancel,
            onPressed: _busy ? null : () => widget.close(false)),
        LgDialogAction(
          label: _busy ? l10n.settingsNetVerifying : l10n.homeOk,
          kind: LgButtonKind.primary,
          isDefault: true,
          busy: _busy,
          onPressed: _submit,
        ),
      ],
      children: [
        _field(kOptionCustomRendezvousServer, l10n.settingsNetIdServer, _id,
            hint: defaultId.isEmpty ? null : l10n.settingsNetHintDefault(defaultId)),
        _field(
          kOptionApiServer,
          l10n.settingsNetApiServer,
          _api,
          hint: fallbackApi.isEmpty
              ? null
              : id.isEmpty
                  ? l10n.settingsNetHintDefault(fallbackApi)
                  : l10n.settingsNetHintDerived(fallbackApi),
          below: isPlainHttpApi(effectiveApi)
              ? Padding(
                  padding: const EdgeInsets.only(top: LgSpace.s1),
                  child: Text(l10n.settingsNetPlainHttp,
                      style: t.textS.copyWith(color: t.colors.warning)),
                )
              : null,
        ),
        _field(kOptionKey, l10n.settingsNetKey, _key,
            hint: id.isEmpty ? l10n.settingsNetKeyHint : l10n.settingsNetKeyHintCustom),
        Padding(
          padding: const EdgeInsets.only(top: LgSpace.s6),
          child: LgSettingsSubtitle(l10n.settingsNetAdvanced),
        ),
        _field(kOptionRelayServer, l10n.settingsNetRelayServer, _relay,
            hint: l10n.settingsNetRelayHint),
        if (signsOut)
          Padding(
            padding: const EdgeInsets.only(top: LgSpace.s4),
            child: Text(l10n.settingsNetSignOutNote,
                style: t.textS.copyWith(color: t.colors.warning)),
          ),
      ],
    );
  }
}

/// Rust's own words on why an address failed, folded until asked for (02 §1.6.8).
class ServerErrorDetail extends StatefulWidget {
  const ServerErrorDetail(
      {super.key, required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  State<ServerErrorDetail> createState() => _ServerErrorDetailState();
}

class _ServerErrorDetailState extends State<ServerErrorDetail> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LgButton(
          label: widget.label,
          kind: LgButtonKind.text,
          expanded: _open,
          onPressed: () => setState(() => _open = !_open),
        ),
        if (_open)
          SelectableText(widget.detail,
              style: t.textS.copyWith(color: t.colors.text2)),
      ],
    );
  }
}
