import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';

/// This device's status for the sections: the service line (02 §1.3.8), the one-time password,
/// the incoming sessions (the exit node section's count before switching it off). The settings
/// page puts the home page's model here; sections read it with [SettingsStatus.of].
class SettingsStatus extends InheritedNotifier<LocalStatusModel> {
  const SettingsStatus({
    super.key,
    required LocalStatusModel status,
    required super.child,
  }) : super(notifier: status);

  static LocalStatusModel of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsStatus>()!.notifier!;
}
