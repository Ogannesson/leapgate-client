import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart' show formatPeerId;
import 'package:flutter_hbb/leapgate/tunnel_api.dart';
import 'package:flutter_hbb/leapgate/tunnel_card.dart' show kRdpDefaultPort;
import 'package:flutter_hbb/models/platform_model.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_rdp_dialog.dart';

// The RDP settings dialog (13 §1.3 block D, upstream `_rdpDialog` in
// `common/widgets/peer_card.dart`): the device's RDP port, user name and password, which Rust
// reads when an RDP card's session starts.

/// From the "RDP" row's edit button in a device menu and from an RDP card; over the home tab
/// only. [name] is the device's, else its ID shows.
Future<void> showRdpSettings(
  TabOverlays overlays,
  String id, {
  String? name,
}) async {
  final saved = await overlays.show<RdpSettings>(
    null,
    (context, close) => LgDialogScrim(
      onEscape: () => close(null),
      child: _RdpSettingsDialog(id: id, name: name, close: close),
    ),
  );
  if (saved == null) return;
  await tunnelApi.setRdpSettings(id, saved);
  // The home page's "saved" toast (upstream "Successful").
  appCore.toasts.show('settingsNetSaved');
}

class _RdpSettingsDialog extends StatefulWidget {
  const _RdpSettingsDialog({
    required this.id,
    required this.name,
    required this.close,
  });

  final String id;
  final String? name;
  final void Function(RdpSettings?) close;

  @override
  State<_RdpSettingsDialog> createState() => _RdpSettingsDialogState();
}

class _RdpSettingsDialogState extends State<_RdpSettingsDialog> {
  late final RdpSettings _saved = tunnelApi.rdpSettings(widget.id);
  late final _port = TextEditingController(text: _saved.port);
  late final _username = TextEditingController(text: _saved.username);
  late final _password = TextEditingController(text: _saved.password);

  @override
  void initState() {
    super.initState();
    _port.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _port.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Empty is 3389; otherwise 1~65535.
  bool get _portValid {
    final text = _port.text.trim();
    if (text.isEmpty) return true;
    final port = int.tryParse(text);
    return port != null && port >= 1 && port <= 65535;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final valid = _portValid;
    final running =
        appCore.tunnels.cardOf(widget.id, TunnelKind.rdp)?.running ?? false;
    return LgRdpSettingsDialog(
      title: l10n.tunnelRdpSettings,
      // A device without a name shows its ID once.
      deviceName: widget.name == formatPeerId(widget.id) ? null : widget.name,
      deviceId: formatPeerId(widget.id),
      portLabel: l10n.tunnelRdpPort,
      portController: _port,
      portPlaceholder: '$kRdpDefaultPort',
      portError: valid ? null : l10n.exitPortInvalid,
      usernameLabel: l10n.tunnelRdpUsername,
      usernameController: _username,
      passwordLabel: l10n.tunnelRdpPassword,
      passwordController: _password,
      showPasswordLabel: l10n.connShowPassword,
      hidePasswordLabel: l10n.connHidePassword,
      // As upstream's dialog (`common/widgets/peer_card.dart` `_rdpDialog`).
      passwordMaxLength: bind.mainMaxEncryptLen(),
      runningNote: running ? l10n.tunnelRdpRunningNote : null,
      cancelLabel: l10n.homeCancel,
      confirmLabel: l10n.homeOk,
      onCancel: () => widget.close(null),
      onConfirm: valid
          ? () => widget.close((
              port: _port.text.trim(),
              username: _username.text,
              password: _password.text,
            ))
          : null,
    );
  }
}
