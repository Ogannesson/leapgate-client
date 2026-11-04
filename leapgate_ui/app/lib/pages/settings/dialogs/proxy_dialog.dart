import 'package:flutter/material.dart';
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
import '../../../widgets/lg_panel_inputs.dart';
import '../../../widgets/lg_text_field.dart';
import 'server_dialog.dart' show ServerErrorDetail;

/// "代理" (02 §1.6.9, upstream `changeSocks5Proxy`) over the home tab, filled with [socks];
/// true when it saved or removed the proxy. While it checks and saves, neither "取消" nor Esc
/// closes it: the save runs on.
Future<bool> showProxyDialog(TabOverlays overlays, AppLocalizations l10n,
    {required Socks socks}) async {
  final busy = ValueNotifier(false);
  return await overlays.show<bool>(
        null,
        (context, close) => LgDialogScrim(
          onEscape: () {
            if (!busy.value) close(false);
          },
          child: _ProxyDialog(
              l10n: l10n, socks: socks, busy: busy, close: close),
        ),
      ) ??
      false;
}

class _ProxyDialog extends StatefulWidget {
  const _ProxyDialog(
      {required this.l10n,
      required this.socks,
      required this.busy,
      required this.close});

  final AppLocalizations l10n;
  final Socks socks;

  /// Checking and saving; the scrim reads it for Esc.
  final ValueNotifier<bool> busy;
  final void Function(bool?) close;

  @override
  State<_ProxyDialog> createState() => _ProxyDialogState();
}

class _ProxyDialogState extends State<_ProxyDialog> {
  late final _proxy = TextEditingController(text: widget.socks.proxy);
  late final _username = TextEditingController(text: widget.socks.username);
  late final _hidden = TextEditingController(text: widget.socks.password);
  bool get _busy => widget.busy.value;
  set _busy(bool value) => widget.busy.value = value;
  bool _failed = false;
  String? _proxyDetail;
  bool _tooLong = false;

  @override
  void initState() {
    super.initState();
    _proxy.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _proxy.dispose();
    _username.dispose();
    _hidden.dispose();
    super.dispose();
  }

  Future<void> _save(String proxy, String username, String password) async {
    final ok = await settingsApi.setSocks(proxy, username, password);
    if (!mounted) return;
    if (ok) {
      widget.close(true);
    } else {
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final proxy = _proxy.text.trim();
    final username = _username.text.trim();
    final typed = _hidden.text;
    setState(() {
      _failed = false;
      _proxyDetail = null;
      _tooLong = typed.length > maxProxyPasswordLength;
    });
    if (_tooLong) return;
    setState(() => _busy = true);
    if (proxy.isNotEmpty) {
      final detail = await testProxyAddress(proxy);
      if (!mounted) return;
      if (detail.isNotEmpty) {
        setState(() {
          _busy = false;
          _proxyDetail = detail;
        });
        return;
      }
    }
    await _save(proxy, username, typed);
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    await _save('', '', '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final t = LgTokens.of(context);
    final wasSet = widget.socks.proxy.isNotEmpty;
    return LgFormDialog(
      title: l10n.settingsNetProxy,
      icon: LgIcons.globe,
      banner: _failed
          ? LgBanner(
              tone: LgTone.error,
              text: l10n.settingsSaveFailed,
              slim: true,
              dense: true)
          : null,
      leading: wasSet
          ? LgButton(
              label: l10n.settingsNetProxyRemove,
              kind: LgButtonKind.danger,
              onPressed: _busy ? null : _remove,
            )
          : null,
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
        LgFormField(
          label: l10n.settingsNetProxyServer,
          hint: l10n.settingsNetProxyServerHint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LgTextField(
                controller: _proxy,
                placeholder: l10n.settingsNetProxyPlaceholder,
                errorText:
                    _proxyDetail == null ? null : l10n.settingsNetUnresolvable,
                enabled: !_busy,
                autofocus: true,
              ),
              if (_proxyDetail != null)
                ServerErrorDetail(
                    label: l10n.settingsNetDetails, detail: _proxyDetail!),
            ],
          ),
        ),
        LgFormField(
          label: l10n.settingsNetProxyUsername,
          child: LgTextField(controller: _username, enabled: !_busy),
        ),
        LgFormField(
          label: l10n.settingsNetProxyPassword,
          child: LgPasswordField(
            controller: _hidden,
            showLabel: l10n.connShowPassword,
            hideLabel: l10n.connHidePassword,
            errorText: _tooLong ? l10n.settingsNetProxyTooLong : null,
            enabled: !_busy,
          ),
        ),
        if (!wasSet && _proxy.text.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: LgSpace.s4),
            child: Text(l10n.settingsNetProxyWarning,
                style: t.textS.copyWith(color: t.colors.warning)),
          ),
      ],
    );
  }
}
