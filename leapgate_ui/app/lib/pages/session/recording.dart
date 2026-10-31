import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/lg_session_toolbar.dart';
import '../../widgets/lg_tooltip.dart';

/// The toolbar's record button (01 P2 block B, item 9), or null when the "hide the recording
/// button" option is on (upstream `desktop/widgets/remote_toolbar.dart` `_RecordMenu`). Recording,
/// it shows as on and stays usable even when the permission is taken away, so it can be stopped
/// (upstream's exception, `:2983-2984`); otherwise without the permission it is greyed out with
/// the reason, where upstream hid it (01 P2 block B).
Widget? recordButton(BuildContext context, FFI ffi) {
  if (appCore.options.local.get(kOptionHideRecordingButton) == 'Y') return null;
  return ListenableBuilder(
    listenable: Listenable.merge([ffi.recordingModel, ffi.ffiModel]),
    builder: (context, _) {
      final l10n = AppLocalizations.of(context)!;
      final recording = ffi.recordingModel.start;
      final allowed = recording || ffi.ffiModel.permissions['recording'] != false;
      final button = LgToolbarButton(
        icon: LgIcons.record,
        label: recording ? l10n.recordStop : l10n.recordStart,
        toggled: recording,
        danger: recording,
        onPressed: allowed ? ffi.requests.toggleRecording : null,
      );
      return allowed
          ? button
          : LgTooltip(message: l10n.recordNoPermission, child: button);
    },
  );
}
