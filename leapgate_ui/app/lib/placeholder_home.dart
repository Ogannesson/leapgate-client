import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';

import 'l10n/app_localizations.dart';

/// M0 stand-in for the home tab: this device's ID, the service status and the version. The empty
/// main window shell (top bar, home tab, left column) replaces it.
class PlaceholderHome extends StatelessWidget {
  const PlaceholderHome(
      {super.key, required this.status, required this.version});

  final LocalStatusModel status;
  final String version;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListenableBuilder(
          listenable: status,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.thisDevice,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('${l10n.deviceId}  ${status.id}'),
              const SizedBox(height: 8),
              Text(switch (status.status) {
                ServiceStatus.ready => l10n.serviceReady,
                ServiceStatus.connecting => l10n.serviceConnecting,
                ServiceStatus.notReady => l10n.serviceNotReady,
                ServiceStatus.stopped => l10n.serviceStopped,
              }),
              const SizedBox(height: 8),
              Text(l10n.version(version)),
            ],
          ),
        ),
      ),
    );
  }
}
