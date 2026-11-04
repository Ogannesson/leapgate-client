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
import '../../../widgets/lg_selection.dart';
import '../dialogs/proxy_dialog.dart';
import '../dialogs/server_dialog.dart';
import '../net_rows.dart';
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
      final ok = await confirmInSettings(widget.ctx.overlays,
          title: title, body: body, action: action!, cancel: l10n.homeCancel);
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
    Widget value(String text, {bool warning = false}) => Text(text,
        style: t.text.copyWith(color: warning ? t.colors.warning : t.colors.text));
    final noId = summary != null && summary.idSource == ServerSource.none;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NetSubheading(l10n.settingsNetServer),
        if (summary != null) ...[
          NetRow(
            ctx: ctx,
            item: kNetItemIdServer,
            name: l10n.settingsNetIdServer,
            control: noId
                ? value(l10n.settingsNetNoIdServer, warning: true)
                : value(markedServer(
                    l10n, summary.id, idServerMark(summary.idSource))),
          ),
          NetRow(
            ctx: ctx,
            item: kNetItemApiServer,
            name: l10n.settingsNetApiServer,
            control: value(summary.api.isEmpty
                ? l10n.settingsNetNotSet
                : markedServer(
                    l10n, summary.api, apiServerMark(summary.apiSource))),
          ),
          NetRow(
            ctx: ctx,
            item: kNetItemKey,
            name: l10n.settingsNetKey,
            control: value(switch (keyState(summary.keySource)) {
              KeyState.setByDefault => l10n.settingsNetKeySetDefault,
              KeyState.set => l10n.settingsNetKeySet,
              KeyState.notSet => l10n.settingsNetNotSet,
            }),
          ),
          if (summary.relay.isNotEmpty)
            NetRow(
              ctx: ctx,
              item: kNetItemRelayServer,
              name: l10n.settingsNetRelayServer,
              control: value(summary.relay),
            ),
          NetRow(
            ctx: ctx,
            item: kNetItemKind,
            name: l10n.settingsNetKind,
            control: value(switch (settingsApi.serverKind()) {
              ServerKind.leapgate => l10n.settingsNetKindLeapgate,
              ServerKind.compat => l10n.settingsNetKindCompat,
              ServerKind.checking => l10n.settingsNetKindChecking,
            }),
          ),
          if (isPlainHttpApi(summary.api))
            LgBanner(
                tone: LgTone.warning, text: l10n.settingsNetPlainHttp, slim: true),
          Padding(
            padding: const EdgeInsets.only(top: LgSpace.s2),
            child: Wrap(
              spacing: LgSpace.s3,
              children: [
                LgButton(
                  label: l10n.settingsNetChange,
                  kind: noId ? LgButtonKind.primary : LgButtonKind.secondary,
                  onPressed: locked ? null : _editServer,
                ),
                LgButton(
                    label: l10n.settingsNetImport,
                    onPressed: locked ? null : _import),
                LgButton(label: l10n.settingsNetExport, onPressed: _export),
              ],
            ),
          ),
        ],
        NetRow(
          ctx: ctx,
          item: kNetItemProxy,
          name: l10n.settingsNetProxy,
          description: l10n.settingsNetProxyNote,
          control: socks == null
              ? null
              : Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: LgSpace.s3,
                  children: [
                    value(socks.proxy.isEmpty
                        ? l10n.settingsNetProxyNone
                        : socks.proxy),
                    LgButton(
                      label: socks.proxy.isEmpty
                          ? l10n.settingsNetProxySet
                          : l10n.settingsNetChange,
                      onPressed: locked ? null : _editProxy,
                    ),
                  ],
                ),
        ),
        NetSubheading(l10n.settingsNetAdvanced),
        NetRow(
          ctx: ctx,
          item: kNetItemWebSocket,
          name: l10n.settingsNetWebSocket,
          description: l10n.settingsNetWebSocketNote,
          control: LgSwitch(
            value: config.getBool(kOptionAllowWebSocket),
            semanticLabel: l10n.settingsNetWebSocket,
            onChanged: locked
                ? null
                : (v) => _switch(kOptionAllowWebSocket, v,
                    title: l10n.settingsNetWebSocketTitle,
                    body: l10n.settingsNetWebSocketBody,
                    action: l10n.settingsNetWebSocketUse),
          ),
        ),
        NetRow(
          ctx: ctx,
          item: kNetItemUdp,
          name: l10n.settingsNetUdp,
          description: l10n.settingsNetUdpNote,
          control: LgSwitch(
            // Only "Y" disables it; `getBool` takes an unset key for on.
            value: config.get(kOptionDisableUdp) == 'Y',
            semanticLabel: l10n.settingsNetUdp,
            onChanged: locked
                ? null
                : (v) => _switch(kOptionDisableUdp, v,
                    title: l10n.settingsNetUdpTitle,
                    body: l10n.settingsNetUdpBody,
                    action: l10n.settingsNetUdpDisable),
          ),
        ),
        NetRow(
          ctx: ctx,
          item: kNetItemTls,
          name: l10n.settingsNetTls,
          description: l10n.settingsNetTlsNote,
          control: LgSwitch(
            value: config.getBool(kOptionAllowInsecureTLSFallback),
            semanticLabel: l10n.settingsNetTls,
            onChanged: locked
                ? null
                : (v) => _switch(kOptionAllowInsecureTLSFallback, v),
          ),
        ),
      ],
    );
  }
}
