import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/restrictions.dart';
import 'package:flutter_hbb/leapgate/settings/settings_api.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../dialogs/whitelist_dialog.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';

/// 传入连接 › 访问限制 (02 §1.3.4). Coder C.
SettingsSection restrictionsSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.restrictions,
      title: l10n.settingsSectionRestrictions,
      locked: true,
      items: () {
        final config = appCore.options.config;
        final installed = appCore.options.isInstalled;
        return [
          SettingsItem(kOptionWhitelist, l10n.settingsRestrictIp,
              description: l10n.settingsRestrictIpNote),
          SettingsItem(kOptionIdWhitelist, l10n.settingsRestrictId,
              description: l10n.settingsRestrictIdNote),
          if (installed)
            SettingsItem(
                kOptionAllowOnlyConnWindowOpen, l10n.settingsRestrictWindowOpen,
                description: l10n.settingsRestrictWindowOpenNote),
          SettingsItem(kOptionDirectServer, l10n.settingsRestrictDirect,
              description: l10n.settingsRestrictDirectNote),
          if (config.getBool(kOptionDirectServer))
            SettingsItem(kOptionDirectAccessPort, l10n.settingsRestrictPort),
          if (installed)
            SettingsItem(kOptionEnableLanDiscovery, l10n.settingsRestrictLan,
                description: l10n.settingsRestrictLanNote),
        ];
      },
      build: (context, ctx) => _RestrictionsBody(ctx: ctx),
    );

class _RestrictionsBody extends StatefulWidget {
  const _RestrictionsBody({required this.ctx});

  final SettingsSectionContext ctx;

  @override
  State<_RestrictionsBody> createState() => _RestrictionsBodyState();
}

class _RestrictionsBodyState extends State<_RestrictionsBody> {
  List<LocalAdapter> _adapters = const [];
  DirectListen _listen = const DirectListen();
  Timer? _again;

  @override
  void initState() {
    super.initState();
    _readAdapters();
    _readListen();
  }

  @override
  void didUpdateWidget(_RestrictionsBody old) {
    super.didUpdateWidget(old);
    // The page builds the section again when it reads the values again; a read already due
    // reads then.
    if (!(_again?.isActive ?? false)) _readListen();
  }

  @override
  void dispose() {
    _again?.cancel();
    super.dispose();
  }

  Future<void> _readAdapters() async {
    final adapters = await settingsApi.localAddresses();
    if (mounted) setState(() => _adapters = adapters);
  }

  /// The service starts or moves the listener about a second after a change and says nothing
  /// (S5): while direct access is on and the answer is not about the port set, ask again a
  /// second later.
  Future<void> _readListen() async {
    _again?.cancel();
    final config = appCore.options.config;
    if (!config.getBool(kOptionDirectServer)) return;
    final listen = await settingsApi.directListen();
    if (!mounted) return;
    setState(() => _listen = listen);
    if (config.getBool(kOptionDirectServer) &&
        (listen.state == null ||
            listen.port != directPort(config.get(kOptionDirectAccessPort)))) {
      _again?.cancel();
      _again = Timer(const Duration(seconds: 1), _readListen);
    }
  }

  Future<void> _editList(AppLocalizations l10n, String key) async {
    final config = appCore.options.config;
    final value = await showWhitelistDialog(widget.ctx.overlays, l10n,
        kind: key == kOptionWhitelist ? WhitelistKind.ip : WhitelistKind.id,
        stored: config.get(key));
    if (value == null) return;
    await widget.ctx.save(key, () => config.set(key, value));
  }

  /// Enter or leaving the box saves; a wrong value is not saved and says so (02 §1.2.5).
  Future<void> _savePort(AppLocalizations l10n, String typed) async {
    final value = parseDirectPort(typed);
    if (value == null) {
      widget.ctx.setError(kOptionDirectAccessPort, l10n.settingsRestrictPortInvalid);
      return;
    }
    await widget.ctx.save(kOptionDirectAccessPort,
        () => appCore.options.config.set(kOptionDirectAccessPort, value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ctx = widget.ctx;
    final config = appCore.options.config;
    final installed = appCore.options.isInstalled;
    final open = !ctx.locked;

    Widget list(String key, String name, String note, String editLabel) {
      final count = whitelistEntries(config.get(key)).length;
      return LgSettingsRow(
        key: ctx.keyOf(key),
        name: name,
        description: note,
        wide: true,
        marked: ctx.isMarked(key),
        error: ctx.errorOf(key),
        control: LgSettingsValueActions(
          value: count == 0
              ? l10n.settingsRestrictOff
              : l10n.settingsRestrictOn(count),
          emphasized: count > 0,
          actions: [
            LgSettingsAction(
              label: l10n.settingsRestrictEdit,
              semanticLabel: editLabel,
              onPressed: open ? () => _editList(l10n, key) : null,
            ),
          ],
        ),
      );
    }

    Widget toggle(String key, String name, {String? note}) =>
        LgSettingsRow.toggle(
          key: ctx.keyOf(key),
          name: name,
          description: note,
          value: config.getBool(key),
          onChanged:
              open ? (v) => ctx.save(key, () => config.setBool(key, v)) : null,
          marked: ctx.isMarked(key),
          error: ctx.errorOf(key),
        );

    final direct = config.getBool(kOptionDirectServer);
    final storedPort = config.get(kOptionDirectAccessPort);
    final port = directPort(storedPort);
    final addresses = [
      for (final a in _adapters) ...a.ipv4,
      for (final a in _adapters) ...a.ipv6,
    ];
    final portError = ctx.errorOf(kOptionDirectAccessPort) ??
        (_listen.state == 'failed' && _listen.port == port
            ? (_listen.error == 'other'
                ? l10n.settingsRestrictPortFailed(port)
                // Windows 10013 is mostly a port another component reserved.
                : l10n.settingsRestrictPortInUse(port))
            : null);
    return SettingsFlow([
      LgSettingsBlock(
        disabled: ctx.locked,
        children: [
          list(kOptionWhitelist, l10n.settingsRestrictIp,
              l10n.settingsRestrictIpNote, l10n.settingsRestrictEditIpLabel),
          list(kOptionIdWhitelist, l10n.settingsRestrictId,
              l10n.settingsRestrictIdNote, l10n.settingsRestrictEditIdLabel),
          if (installed)
            toggle(kOptionAllowOnlyConnWindowOpen, l10n.settingsRestrictWindowOpen,
                note: l10n.settingsRestrictWindowOpenNote),
        ],
      ),
      LgSettingsBlock(
        disabled: ctx.locked,
        children: [
          LgSettingsRow.toggle(
            key: ctx.keyOf(kOptionDirectServer),
            name: l10n.settingsRestrictDirect,
            description: l10n.settingsRestrictDirectNote,
            value: direct,
            onChanged: open
                ? (v) {
                    // The service listens again about a second later; until then it still
                    // answers with the record from before it stopped.
                    if (v) {
                      _listen = const DirectListen();
                      _again?.cancel();
                      _again = Timer(const Duration(seconds: 1), _readListen);
                    }
                    ctx.save(kOptionDirectServer,
                        () => config.setBool(kOptionDirectServer, v));
                  }
                : null,
            marked: ctx.isMarked(kOptionDirectServer),
            error: ctx.errorOf(kOptionDirectServer),
          ),
          if (direct)
            LgSettingsRow(
              key: ctx.keyOf(kOptionDirectAccessPort),
              name: l10n.settingsRestrictPort,
              description: addresses.isEmpty
                  ? null
                  : l10n.settingsRestrictAddresses(
                      addresses.join(l10n.settingsRestrictAddressSeparator)),
              indented: true,
              wide: true,
              marked: ctx.isMarked(kOptionDirectAccessPort),
              error: portError,
              errorAtEnd: true,
              control: LgSettingsNumberField(
                text: storedPort,
                placeholder: '$kDefaultDirectPort',
                semanticLabel: l10n.settingsRestrictPort,
                errorText: portError,
                enabled: open,
                maxLength: 5,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (typed) => _savePort(l10n, typed),
                onReverted: () => ctx.setError(kOptionDirectAccessPort, null),
              ),
            ),
        ],
      ),
      if (installed)
        LgSettingsBlock(
          disabled: ctx.locked,
          children: [
            toggle(kOptionEnableLanDiscovery, l10n.settingsRestrictLan,
                note: l10n.settingsRestrictLanNote),
          ],
        ),
    ]);
  }
}
