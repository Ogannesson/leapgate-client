import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/server_config.dart';
import 'package:flutter_hbb/leapgate/settings/settings_api.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_banner.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../dialogs/proxy_dialog.dart';
import '../dialogs/server_dialog.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';

/// Item ids of this section.
const kNetItemIdServer = kOptionCustomRendezvousServer;
const kNetItemApiServer = kOptionApiServer;
const kNetItemKey = kOptionKey;
const kNetItemRelayServer = kOptionRelayServer;
const kNetItemKind = 'server-kind';
const kNetItemProxy = 'proxy';
const kNetItemWebSocket = kOptionAllowWebSocket;
const kNetItemUdp = kOptionDisableUdp;
const kNetItemTls = kOptionAllowInsecureTLSFallback;

/// 通用 › 网络和服务器 (02 §1.5.2). Coder B.
SettingsSection networkSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.network,
      title: l10n.settingsSectionNetwork,
      locked: true,
      items: () => [
        SettingsItem(kNetItemIdServer, l10n.settingsNetIdServer),
        SettingsItem(kNetItemApiServer, l10n.settingsNetApiServer),
        SettingsItem(kNetItemKey, l10n.settingsNetKey),
        if (appCore.options.config.get(kOptionRelayServer).isNotEmpty)
          SettingsItem(kNetItemRelayServer, l10n.settingsNetRelayServer),
        SettingsItem(kNetItemKind, l10n.settingsNetKind),
        SettingsItem(kNetItemProxy, l10n.settingsNetProxy,
            description: l10n.settingsNetProxyNote),
        SettingsItem(kNetItemWebSocket, l10n.settingsNetWebSocket,
            description: l10n.settingsNetWebSocketNote),
        SettingsItem(kNetItemUdp, l10n.settingsNetUdp,
            description: l10n.settingsNetUdpNote),
        SettingsItem(kNetItemTls, l10n.settingsNetTls,
            description: l10n.settingsNetTlsNote),
      ],
      build: (context, ctx) => _NetworkBody(ctx: ctx),
    );

/// A server value with what the summary writes after it (02 §1.5.2).
String markedServer(AppLocalizations l10n, String value, ServerMark mark) =>
    switch (mark) {
      ServerMark.none => value,
      ServerMark.byDefault => l10n.settingsNetMarkDefault(value),
      ServerMark.lastUsed => l10n.settingsNetMarkLastUsed(value),
      ServerMark.derived => l10n.settingsNetMarkDerived(value),
    };

class _NetworkBody extends StatefulWidget {
  const _NetworkBody({required this.ctx});

  final SettingsSectionContext ctx;

  @override
  State<_NetworkBody> createState() => _NetworkBodyState();
}

class _NetworkBodyState extends State<_NetworkBody> {
  ServerSummary? _summary;
  Socks? _socks;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(_NetworkBody old) {
    super.didUpdateWidget(old);
    _read();
  }

  Future<void> _read() async {
    final summary = await settingsApi.serverSummary();
    final socks = await readSocks();
    if (mounted) {
      setState(() {
        _summary = summary;
        _socks = socks;
      });
      // S2 settles with no event, and the page reads again only on open, refocus and save
      // (09 §4.2): while it is still checking, read again a second later.
      if (settingsApi.serverKind() == ServerKind.checking) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _read();
        });
      }
    }
  }

  Future<void> _editServer({ServerConfig? prefill}) async {
    final summary = _summary;
    if (summary == null) return;
    final saved = await showServerDialog(widget.ctx.overlays,
        AppLocalizations.of(context)!,
        summary: summary,
        initial: prefill ?? ServerConfig.fromOptions(appCore.options.config));
    if (saved) {
      // Toast keys are the ARB keys (`shell/toast_view.dart`).
      appCore.toasts.show('settingsNetSaved');
      await _read();
    }
  }

  Future<void> _import() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final found = importServerConfig(data?.text);
    switch (found.result) {
      case ImportResult.empty:
        appCore.toasts.show('settingsNetClipboardEmpty');
      case ImportResult.invalid:
        appCore.toasts.show('settingsNetInvalidConfig');
      case ImportResult.ok:
        await _editServer(prefill: found.config);
    }
  }

  Future<void> _export() async {
    final summary = _summary;
    if (summary == null) return;
    await Clipboard.setData(ClipboardData(
        text: exportServerConfig(summary, appCore.options.config)));
    appCore.toasts.show('settingsNetExported');
  }

  Future<void> _editProxy() async {
    final socks = _socks;
    if (socks == null) return;
    final saved = await showProxyDialog(
        widget.ctx.overlays, AppLocalizations.of(context)!,
        socks: socks);
    if (saved) await _read();
  }

  /// WebSocket and disabling UDP take this device off the network for others: asked first.
  Future<void> _switch(String key, bool on,
      {String? title, String? body, String? action}) async {
    final l10n = AppLocalizations.of(context)!;
    if (on && title != null) {
      final ok = await widget.ctx.overlays.show<bool>(
            null,
            (context, close) => LgDialogScrim(
              onEscape: () => close(false),
              child: LgConfirmDialog(
                title: title,
                body: body,
                actions: [
                  LgDialogAction(
                      label: l10n.homeCancel, onPressed: () => close(false)),
                  LgDialogAction(
                    label: action!,
                    kind: LgButtonKind.primary,
                    isDefault: true,
                    onPressed: () => close(true),
                  ),
                ],
              ),
            ),
          ) ??
          false;
      if (!ok) return;
    }
    await widget.ctx
        .save(key, () => appCore.options.config.set(key, on ? 'Y' : 'N'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final ctx = widget.ctx;
    final config = appCore.options.config;
    final summary = _summary;
    final socks = _socks;
    final locked = ctx.locked;
    final noId = summary != null && summary.idSource == ServerSource.none;
    LgSettingsInfoRow info(String item, String label, String value,
            {bool warning = false}) =>
        LgSettingsInfoRow(
          key: ctx.keyOf(item),
          label: label,
          marked: ctx.isMarked(item),
          value: warning ? null : value,
          child: warning
              ? Text(value, style: t.textM.copyWith(color: t.colors.warning))
              : null,
        );
    LgSettingsRow toggle(String item, String name, String description,
            bool value, ValueChanged<bool> onChanged) =>
        LgSettingsRow.toggle(
          key: ctx.keyOf(item),
          name: name,
          description: description,
          value: value,
          onChanged: locked ? null : onChanged,
          marked: ctx.isMarked(item),
          error: ctx.errorOf(item),
        );
    return SettingsFlow([
      LgSettingsSubtitle(l10n.settingsNetServer),
      if (summary != null) ...[
        LgSettingsBlock(children: [
          noId
              ? info(kNetItemIdServer, l10n.settingsNetIdServer,
                  l10n.settingsNetNoIdServer,
                  warning: true)
              : info(kNetItemIdServer, l10n.settingsNetIdServer,
                  markedServer(l10n, summary.id, idServerMark(summary.idSource))),
          info(
              kNetItemApiServer,
              l10n.settingsNetApiServer,
              summary.api.isEmpty
                  ? l10n.settingsNetNotSet
                  : markedServer(
                      l10n, summary.api, apiServerMark(summary.apiSource))),
          info(
              kNetItemKey,
              l10n.settingsNetKey,
              switch (keyState(summary.keySource)) {
                KeyState.setByDefault => l10n.settingsNetKeySetDefault,
                KeyState.set => l10n.settingsNetKeySet,
                KeyState.notSet => l10n.settingsNetNotSet,
              }),
          if (summary.relay.isNotEmpty)
            info(kNetItemRelayServer, l10n.settingsNetRelayServer,
                summary.relay),
          info(
              kNetItemKind,
              l10n.settingsNetKind,
              switch (settingsApi.serverKind()) {
                ServerKind.leapgate => l10n.settingsNetKindLeapgate,
                ServerKind.compat => l10n.settingsNetKindCompat,
                ServerKind.checking => l10n.settingsNetKindChecking,
              }),
          LgSettingsRowFrame(
            child: LgSettingsValueActions(actions: [
              LgSettingsAction(
                label: l10n.settingsNetChange,
                semanticLabel: l10n.settingsNetChangeServerLabel,
                kind: noId ? LgButtonKind.primary : LgButtonKind.secondary,
                onPressed: locked ? null : _editServer,
              ),
              LgSettingsAction(
                  label: l10n.settingsNetImport,
                  semanticLabel: l10n.settingsNetImportLabel,
                  onPressed: locked ? null : _import),
              // A locked section can't be used at all (02 §1.2.5 rule 4).
              LgSettingsAction(
                  label: l10n.settingsNetExport,
                  semanticLabel: l10n.settingsNetExportLabel,
                  onPressed: locked ? null : _export),
            ]),
          ),
        ]),
        if (isPlainHttpApi(summary.api))
          LgBanner(
              tone: LgTone.warning,
              slim: true,
              dense: true,
              text: l10n.settingsNetPlainHttp),
      ],
      LgSettingsSubtitle(l10n.settingsNetProxy),
      LgSettingsBlock(children: [
        LgSettingsRow(
          key: ctx.keyOf(kNetItemProxy),
          name: l10n.settingsNetProxy,
          description: l10n.settingsNetProxyNote,
          wide: true,
          marked: ctx.isMarked(kNetItemProxy),
          control: socks == null
              ? null
              : LgSettingsValueActions(
                  value: socks.proxy.isEmpty
                      ? l10n.settingsNetProxyNone
                      : socks.proxy,
                  emphasized: socks.proxy.isNotEmpty,
                  actions: [
                    LgSettingsAction(
                      label: socks.proxy.isEmpty
                          ? l10n.settingsNetProxySet
                          : l10n.settingsNetChange,
                      semanticLabel: socks.proxy.isEmpty
                          ? l10n.settingsNetSetProxyLabel
                          : l10n.settingsNetChangeProxyLabel,
                      onPressed: locked ? null : _editProxy,
                    ),
                  ],
                ),
        ),
      ]),
      LgSettingsSubtitle(l10n.settingsNetAdvanced),
      LgSettingsBlock(children: [
        toggle(
            kNetItemWebSocket,
            l10n.settingsNetWebSocket,
            l10n.settingsNetWebSocketNote,
            config.getBool(kOptionAllowWebSocket),
            (v) => _switch(kOptionAllowWebSocket, v,
                title: l10n.settingsNetWebSocketTitle,
                body: l10n.settingsNetWebSocketBody,
                action: l10n.settingsNetWebSocketUse)),
        toggle(
            kNetItemUdp,
            l10n.settingsNetUdp,
            l10n.settingsNetUdpNote,
            // Only "Y" disables it; `getBool` takes an unset key for on.
            config.get(kOptionDisableUdp) == 'Y',
            (v) => _switch(kOptionDisableUdp, v,
                title: l10n.settingsNetUdpTitle,
                body: l10n.settingsNetUdpBody,
                action: l10n.settingsNetUdpDisable)),
        toggle(
            kNetItemTls,
            l10n.settingsNetTls,
            l10n.settingsNetTlsNote,
            config.getBool(kOptionAllowInsecureTLSFallback),
            (v) => _switch(kOptionAllowInsecureTLSFallback, v)),
      ]),
    ]);
  }
}
