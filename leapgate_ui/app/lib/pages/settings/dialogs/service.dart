import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';

/// "停止服务" / "启动服务" of the service section and the home page's "启动服务", one way for both
/// (02 §1.3.8, §3.3): the question first when [LocalStatusModel.serviceAsksFirst], then the
/// call. Null when the question was cancelled; otherwise the red line for under the button,
/// null in it when there is none ("未获得管理员权限，…" on the installed version, 02 §1.6.10).
Future<({String? error})?> toggleService(
  TabOverlays overlays,
  AppLocalizations l10n,
  LocalStatusModel status, {
  required bool stop,
}) async {
  final installed = appCore.options.isInstalled;
  if (status.serviceAsksFirst(stop: stop)) {
    final ok =
        await overlays.show<bool>(
          null,
          (context, close) => LgDialogScrim(
            onEscape: () => close(false),
            child: LgConfirmDialog(
              title: stop
                  ? l10n.settingsServiceStopTitle
                  : l10n.settingsServiceStartTitle,
              body: !stop
                  ? l10n.settingsServiceStartBody
                  : installed
                  ? l10n.settingsServiceStopBodyInstalled
                  // 02 §4.3 item 3 (R2-Q7) may change this once measured.
                  : l10n.settingsServiceStopBodyPortable,
              actions: [
                LgDialogAction(
                  label: l10n.homeCancel,
                  onPressed: () => close(false),
                ),
                LgDialogAction(
                  label: stop
                      ? l10n.settingsServiceStop
                      : l10n.homeStartService,
                  // Only the installed version's stop takes everything down (02 §3.5).
                  kind: stop && installed
                      ? LgButtonKind.dangerSolid
                      : LgButtonKind.primary,
                  isDefault: true,
                  onPressed: () => close(true),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!ok) return null;
  }
  final done = await status.toggleService(stop: stop);
  return (
    error: done
        ? null
        : stop
        ? l10n.settingsServiceNotStopped
        : l10n.settingsServiceNotStarted,
  );
}
