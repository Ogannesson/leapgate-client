import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;
import 'package:flutter_hbb/leapgate/settings/unlock.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_status.dart';
import '../dialogs/unlock_pin.dart';
import '../settings_parts.dart';
import '../settings_registry.dart';

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

/// A question over the home tab; true when [action] was pressed.
Future<bool> _confirm(
  TabOverlays overlays,
  AppLocalizations l10n, {
  required String title,
  String? body,
  required String action,
  bool danger = false,
}) async =>
    await overlays.show<bool>(
      null,
      (context, close) => LgDialogScrim(
        onEscape: () => close(false),
        child: LgConfirmDialog(
          title: title,
          body: body,
          actions: [
            LgDialogAction(
              label: l10n.homeCancel,
              onPressed: () => close(false),
            ),
            LgDialogAction(
              label: action,
              kind: danger ? LgButtonKind.dangerSolid : LgButtonKind.primary,
              isDefault: true,
              onPressed: () => close(true),
            ),
          ],
        ),
      ),
    ) ??
    false;

class _Service extends StatefulWidget {
  const _Service({required this.l10n, required this.ctx});

  final AppLocalizations l10n;
  final SettingsSectionContext ctx;

  @override
  State<_Service> createState() => _ServiceState();
}

class _ServiceState extends State<_Service> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Whether a PIN is set takes an IPC round trip (up to 1 s): once when the section opens,
    // after the first frame, not on every build.
    if (appCore.options.isInstalled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) settingsUnlock.readPinSet();
      });
    }
  }

  /// "停止服务" / "启动服务" (02 §1.3.8), not under the lock: it asks for administrator permission
  /// itself on the installed version. There it removes or installs the Windows service and
  /// Leapgate restarts; the call returns only when that did not happen, cancelled or failed
  /// alike (09 §4.4).
  Future<void> _toggle(bool stop) async {
    final l10n = widget.l10n;
    final ctx = widget.ctx;
    final installed = appCore.options.isInstalled;
    final inUse =
        appCore.sessions.devices.isNotEmpty ||
        appCore.exitNodes.runningCount > 0;
    if (stop || (installed && inUse)) {
      final ok = await _confirm(
        ctx.overlays,
        l10n,
        title: stop
            ? l10n.settingsServiceStopTitle
            : l10n.settingsServiceStartTitle,
        body: !stop
            ? l10n.settingsServiceStartBody
            : installed
            ? l10n.settingsServiceStopBodyInstalled
            // TODO(M6a): 02 §4.3 item 3 (R2-Q7) may change this once measured.
            : l10n.settingsServiceStopBodyPortable,
        action: stop ? l10n.settingsServiceStop : l10n.homeStartService,
        danger: stop,
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    await appCore.options.config.set(kOptionStopService, stop ? 'Y' : '');
    if (!mounted) return;
    ctx.setError(
      _service,
      !installed
          ? null
          : stop
          ? l10n.settingsServiceNotStopped
          : l10n.settingsServiceNotStarted,
    );
    setState(() => _busy = false);
  }

  Future<void> _removePin() async {
    final l10n = widget.l10n;
    if (!await _confirm(
      widget.ctx.overlays,
      l10n,
      title: l10n.settingsServiceRemovePinTitle,
      action: l10n.settingsServiceRemove,
      danger: true,
    )) {
      return;
    }
    widget.ctx.setError(
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
        final pinSet = settingsUnlock.pinSet ?? false;
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
                onPressed: _busy ? null : () => _toggle(!stopped),
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
                    Text(
                      pinSet
                          ? l10n.settingsAccessSet
                          : l10n.settingsAccessNotSet,
                    ),
                    LgButton(
                      label: pinSet
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
                    if (pinSet)
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
