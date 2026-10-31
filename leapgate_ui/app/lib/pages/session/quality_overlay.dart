import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/leapgate/session_route.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_canvas_parts.dart';

/// The quality data over the image, top left (01 P2 block C, `det-session`): speed, frame rate,
/// latency, target bitrate, codec, chroma, as upstream's monitor (`common/widgets/overlay.dart`
/// `QualityMonitor`). Shown by the switch in the connection details, on by default in detail mode
/// (02 R2-Q11). Drawn by [LgQualityOverlay]; where it draws nothing, pointer events reach the
/// image below.
class QualityOverlay extends StatelessWidget {
  const QualityOverlay({super.key, required this.ffi});

  final FFI ffi;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        ffi.qualityMonitorModel,
        ffi.options.listenable(kOptionQualityMonitorChosen),
      ]),
      builder: (context, _) {
        if (!showsQualityMonitor(ffi, detailMode: t.detail)) {
          return const SizedBox.shrink();
        }
        final l10n = AppLocalizations.of(context)!;
        final data = ffi.qualityMonitorModel.data;
        // Upstream shows 0 ms while no frame comes (every fps 0).
        final idle = (data.fps ?? '').replaceAll(' ', '').replaceAll('0', '').isEmpty;
        final delay = data.delay == null
            ? '—'
            : l10n.routeMs(idle ? 0 : int.tryParse(data.delay!) ?? 0);
        final rows = [
          (l10n.routeSpeed, data.speed ?? '—'),
          (l10n.routeFps, data.fps ?? '—'),
          (l10n.routeLatency, delay),
          (
            l10n.routeTargetBitrate,
            data.targetBitrate == null ? '—' : l10n.routeKbps(data.targetBitrate!)
          ),
          (l10n.routeCodec, data.codecFormat ?? '—'),
          (l10n.routeChroma, data.chroma ?? '—'),
        ];
        return Padding(
          padding: const EdgeInsets.all(LgSpace.s4),
          child: Align(
            alignment: Alignment.topLeft,
            child: LgQualityOverlay(
                rows: rows, semanticLabel: l10n.routeQualityData),
          ),
        );
      },
    );
  }
}
