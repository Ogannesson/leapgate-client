import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;
import 'package:flutter_hbb/leapgate/settings/unlock.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../../../widgets/lg_status.dart';
import '../dialogs/service.dart';
import '../dialogs/unlock_pin.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';
import '../settings_status.dart';

const _service = 'service';
const _id = 'id';
const _pin = 'unlock-pin';

/// 传入连接 › 服务与 ID (02 §1.3.8). Coder A.
SettingsSection serviceSection(AppLocalizations l10n) => SettingsSection(
  id: SettingsSectionId.service,
  title: l10n.settingsSectionService,
  locked: true,
  items: () => [
    SettingsItem(_service, l10n.settingsServiceService),
    SettingsItem(_id, l10n.settingsServiceId),
    if (appCore.options.isInstalled)
      SettingsItem(
        _pin,
        l10n.settingsServiceUnlockPin,
        description: l10n.settingsServiceUnlockPinNote,
      ),
  ],
  build: (context, ctx) => _Service(l10n: l10n, ctx: ctx),
);

class _Service extends StatefulWidget {
  const _Service({required this.l10n, required this.ctx});

  final AppLocalizations l10n;
  final SettingsSectionContext ctx;

  @override
  State<_Service> createState() => _ServiceState();
}

class _ServiceState extends State<_Service> {
  bool _busy = false;

  /// "停止服务" / "启动服务", not under the lock: on the installed version it asks for
  /// administrator permission itself (02 §1.2.6).
  Future<void> _toggle(LocalStatusModel status, bool stop) async {
    setState(() => _busy = true);
    final result = await toggleService(
      widget.ctx.overlays,
      widget.l10n,
      status,
      stop: stop,
    );
    if (!mounted) return;
    if (result != null) widget.ctx.setError(_service, result.error);
    setState(() => _busy = false);
  }

  Future<void> _removePin() async {
    final l10n = widget.l10n;
    final ctx = widget.ctx;
    final ok =
        await ctx.overlays.show<bool>(
          null,
          (context, close) => LgDialogScrim(
            onEscape: () => close(false),
            child: LgConfirmDialog(
              title: l10n.settingsServiceRemovePinTitle,
              actions: [
                LgDialogAction(
                  label: l10n.homeCancel,
                  onPressed: () => close(false),
                ),
                LgDialogAction(
                  label: l10n.settingsServiceRemove,
                  kind: LgButtonKind.dangerSolid,
                  isDefault: true,
                  onPressed: () => close(true),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!ok) return;
    ctx.setError(
      _pin,
      settingsUnlock.savePin('') ? null : l10n.settingsSaveFailed,
    );
  }

  Future<void> _copyId(String id) async {
    await Clipboard.setData(ClipboardData(text: id));
    appCore.toasts.show('Copied');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final ctx = widget.ctx;
    final status = SettingsStatus.of(context);
    final installed = appCore.options.isInstalled;
    final stopped = status.status == ServiceStatus.stopped;
    return ListenableBuilder(
      listenable: settingsUnlock,
      builder: (context, _) {
        // Known once unlocked (`SettingsUnlock.unlock` reads it); locked, the row is grey and
        // says nothing about it.
        final pinSet = settingsUnlock.pinSet;
        final locked = ctx.locked;
        return SettingsFlow([
          // Outside the lock (02 §1.2.6): the page leaves this section usable and the
          // blocks under the lock grey themselves.
          LgSettingsBlock(
            children: [
              KeyedSubtree(
                key: ctx.keyOf(_service),
                child: LgSettingsRow(
                  name: l10n.settingsServiceService,
                  marked: ctx.isMarked(_service),
                  error: ctx.errorOf(_service),
                  // Word for word the home page's service line (02 §1.3.8).
                  body: switch (status.status) {
                    ServiceStatus.ready => LgStatusText(
                      LgStatus.online,
                      l10n.serviceReady,
                    ),
                    ServiceStatus.connecting => LgStatusText(
                      LgStatus.connecting,
                      l10n.serviceConnecting,
                    ),
                    ServiceStatus.notReady => LgStatusText(
                      LgStatus.warning,
                      l10n.serviceNotReady,
                    ),
                    ServiceStatus.stopped => LgStatusText(
                      LgStatus.error,
                      l10n.serviceStopped,
                    ),
                  },
                  control: LgSettingsValueActions(
                    actions: [
                      LgSettingsAction(
                        label: stopped
                            ? l10n.homeStartService
                            : l10n.settingsServiceStop,
                        icon: installed ? LgIcons.uac : null,
                        busy: _busy,
                        onPressed: _busy
                            ? null
                            : () => _toggle(status, !stopped),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          LgSettingsBlock(
            disabled: locked,
            children: [
              KeyedSubtree(
                key: ctx.keyOf(_id),
                child: LgSettingsInfoRow(
                  label: l10n.settingsServiceId,
                  value: formatPeerId(status.id),
                  marked: ctx.isMarked(_id),
                  copyLabel: l10n.homeCopy,
                  copySemanticLabel: l10n.homeCopyId,
                  onCopy: status.id.isEmpty || locked
                      ? null
                      : () => _copyId(status.id),
                ),
              ),
            ],
          ),
          if (installed)
            LgSettingsBlock(
              disabled: locked,
              children: [
                KeyedSubtree(
                  key: ctx.keyOf(_pin),
                  child: LgSettingsRow(
                    name: l10n.settingsServiceUnlockPin,
                    description: l10n.settingsServiceUnlockPinNote,
                    marked: ctx.isMarked(_pin),
                    error: ctx.errorOf(_pin),
                    wide: true,
                    // Locked, the PIN is not read (09 §4.3): the name and the description
                    // alone until it is unlocked (02 §1.3.8).
                    control: locked || pinSet == null
                        ? null
                        : LgSettingsValueActions(
                            value: pinSet
                                ? l10n.settingsAccessSet
                                : l10n.settingsAccessNotSet,
                            emphasized: pinSet,
                            actions: [
                              LgSettingsAction(
                                label: pinSet
                                    ? l10n.settingsServiceChangePin
                                    : l10n.settingsServiceSetPin,
                                semanticLabel: pinSet
                                    ? l10n.settingsServiceChangePinLabel
                                    : l10n.settingsUnlockSetPinTitle,
                                onPressed: () async {
                                  if (await showSetUnlockPinDialog(
                                    ctx.overlays,
                                    l10n,
                                  )) {
                                    ctx.setError(_pin, null);
                                  }
                                },
                              ),
                              if (pinSet)
                                LgSettingsAction(
                                  label: l10n.settingsServiceRemovePin,
                                  semanticLabel:
                                      l10n.settingsServiceRemovePinLabel,
                                  onPressed: _removePin,
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
        ]);
      },
    );
  }
}
