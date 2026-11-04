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
import '../../../widgets/lg_status.dart';
import '../dialogs/service.dart';
import '../dialogs/unlock_pin.dart';
import '../settings_parts.dart';
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsRow(
              ctx: ctx,
              id: _service,
              name: l10n.settingsServiceService,
              // Word for word the home page's service line (02 §1.3.8).
              below: switch (status.status) {
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
              control: LgButton(
                label: stopped
                    ? l10n.homeStartService
                    : l10n.settingsServiceStop,
                icon: installed ? LgIcons.uac : null,
                kind: LgButtonKind.secondary,
                busy: _busy,
                onPressed: _busy ? null : () => _toggle(status, !stopped),
              ),
            ),
            SettingsRow(
              ctx: ctx,
              id: _id,
              name: l10n.settingsServiceId,
              below: Text(formatPeerId(status.id)),
              control: LgButton(
                label: l10n.homeCopy,
                semanticLabel: l10n.homeCopyId,
                icon: LgIcons.copy,
                kind: LgButtonKind.text,
                onPressed: status.id.isEmpty ? null : () => _copyId(status.id),
              ),
            ),
            if (installed)
              SettingsRow(
                ctx: ctx,
                id: _pin,
                name: l10n.settingsServiceUnlockPin,
                description: l10n.settingsServiceUnlockPinNote,
                enabled: !ctx.locked,
                below: Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (pinSet != null)
                      Text(
                        pinSet
                            ? l10n.settingsAccessSet
                            : l10n.settingsAccessNotSet,
                      ),
                    LgButton(
                      label: pinSet == true
                          ? l10n.settingsServiceChangePin
                          : l10n.settingsServiceSetPin,
                      kind: LgButtonKind.text,
                      onPressed: ctx.locked
                          ? null
                          : () async {
                              if (await showSetUnlockPinDialog(
                                ctx.overlays,
                                l10n,
                              )) {
                                ctx.setError(_pin, null);
                              }
                            },
                    ),
                    if (pinSet == true)
                      LgButton(
                        label: l10n.settingsServiceRemovePin,
                        kind: LgButtonKind.text,
                        onPressed: ctx.locked ? null : _removePin,
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
