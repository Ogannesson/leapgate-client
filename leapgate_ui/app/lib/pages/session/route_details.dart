import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/consts.dart' show kShortcutActionToggleQualityMonitor;
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/latency.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/leapgate/session_route.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/tab_overlays.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_route_details.dart';
import '../../widgets/lg_session_toolbar.dart';
import '../../widgets/lg_status.dart';
import '../../widgets/lg_tooltip.dart';
import 'session_names.dart';

/// The toolbar's connection mark (01 P2 block B, item 10), or null until the connection is
/// ready. Clicking it opens the connection details (01 §4.2 second level) under it.
Widget? sessionRouteMark(BuildContext context, FFI ffi, TabOverlays overlays) {
  final conn = ffi.connection;
  if (!showsRoute(conn)) return null;
  final l10n = AppLocalizations.of(context)!;
  final direct = conn.direct == true;
  final encrypted = conn.secure != false;
  final routeTip = direct ? l10n.sessionDirectTip : l10n.sessionRelayedTip;
  return MenuAnchor(
    // The card draws itself; the menu only places it and closes it on a click outside.
    style: const MenuStyle(
      backgroundColor: WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      shadowColor: WidgetStatePropertyAll(Colors.transparent),
      elevation: WidgetStatePropertyAll(0),
      padding: WidgetStatePropertyAll(EdgeInsets.zero),
    ),
    alignmentOffset: const Offset(0, LgSpace.s1),
    menuChildren: [RouteDetails(ffi: ffi)],
    builder: (context, controller, _) => LgTooltip(
      message:
          encrypted ? routeTip : '$routeTip\n${l10n.sessionUnencryptedTip}',
      child: LgToolbarRouteButton(
        route: direct ? LgRoute.direct : LgRoute.relay,
        label: direct ? l10n.sessionDirect : l10n.sessionRelayed,
        encrypted: encrypted,
        unencryptedLabel: l10n.sessionUnencrypted,
        open: controller.isOpen,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    ),
  );
}

/// The quality data shortcut (upstream `toolbar.dart:1061-1071`): flips what the switch in the
/// details shows. [detailMode] is read when the keys are pressed.
void registerQualityMonitorShortcut(FFI ffi, bool Function() detailMode) =>
    ffi.shortcutModel.register(
      kShortcutActionToggleQualityMonitor,
      () => setShowsQualityMonitor(
          ffi, !showsQualityMonitor(ffi, detailMode: detailMode())),
    );

/// The path names of Q3's codes (01 §4.2); null for a code this version does not know.
String? routePathName(AppLocalizations l10n, String? path) => switch (path) {
      'lan' => l10n.routePathLan,
      'direct_ip' => l10n.routePathDirectIp,
      'punch_v4' => l10n.routePathPunchV4,
      'punch_v6' => l10n.routePathPunchV6,
      'relay' => l10n.routePathRelay,
      'relay_ws' => l10n.routePathRelayWs,
      _ => null,
    };

/// One point of the line every 2 s over the last 60 s (01 §4.2), oldest first; a slot without a
/// measurement is a gap.
List<double?> latencySlots(LatencyStats stats) {
  final step = LatencyStats.step.inMilliseconds;
  final n = LatencyStats.window.inMilliseconds ~/ step + 1;
  final slots = List<double?>.filled(n, null);
  for (final p in stats.points) {
    final i = n - 1 - (stats.ageOf(p).inMilliseconds / step).round();
    if (i >= 0 && i < n) slots[i] = p.ms.toDouble();
  }
  return slots;
}

/// The connection details (01 §4.2, `d-conn`) drawn by [LgRouteDetails]: the first level, then
/// the connection (path and relay server from Q3, transport, encryption and fingerprint), the
/// image data, the round trip and the switch for the quality data. Rebuilt with the connection,
/// so a reconnect reads Q3 again once it is connected.
class RouteDetails extends StatelessWidget {
  const RouteDetails({super.key, required this.ffi});

  final FFI ffi;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        ffi.connection,
        ffi.qualityMonitorModel,
        ffi.latency,
        ffi.options.listenable(kOptionQualityMonitorChosen),
      ]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final conn = ffi.connection;
    final direct = conn.direct == true;
    final encrypted = conn.secure != false;
    final route = sessionRoute(ffi);
    final path = routePathName(l10n, route.path);
    // Without Q3's answer, from the stream type of the ready event: KCP and WebRTC run on UDP.
    final transport = route.transport ??
        (const ['UDP', 'IPv6', 'WebRTC'].contains(conn.streamType)
            ? 'udp'
            : 'tcp');
    final data = ffi.qualityMonitorModel.data;
    final fingerprint = ffi.fingerprint.value;
    final stats = ffi.latency;
    String n(num? v) => v == null ? '—' : '${v.round()}';

    return LgRouteDetails(
      route: direct ? LgRoute.direct : LgRoute.relay,
      title: direct ? l10n.sessionDirect : l10n.sessionRelayed,
      semanticLabel: l10n.routeDetails,
      why: direct ? l10n.routeDirectNote : l10n.routeRelayedNote,
      encrypted: encrypted,
      unencryptedLabel: l10n.sessionUnencrypted,
      // No maxHeight: the menu it opens in scrolls it within the window already.
      groups: [
        LgKeyValueGroup(l10n.routeSectionConnection, [
          if (path != null) LgKeyValue(l10n.routePath, path),
          if (route.relay != null)
            LgKeyValue(l10n.routeRelayServer, route.relay!),
          LgKeyValue(l10n.routeTransport, transport.toUpperCase()),
          LgKeyValue(
            l10n.routeEncryption,
            encrypted ? l10n.routeEncrypted : l10n.routeUnencrypted,
            icon: encrypted ? LgIcons.lock : LgIcons.warn,
          ),
          if (fingerprint.isNotEmpty)
            LgKeyValue(
              l10n.routeFingerprint,
              _fingerprintLines(fingerprint),
              copyLabel: l10n.routeCopyFingerprint,
              onCopy: () {
                Clipboard.setData(ClipboardData(text: fingerprint));
                appCore.toasts.show('Copied');
              },
              wrap: true,
            ),
        ]),
        LgKeyValueGroup(l10n.routeSectionImage, [
          LgKeyValue(l10n.routeCodec, data.codecFormat ?? '—'),
          LgKeyValue(l10n.routeFps, data.fps ?? '—'),
          LgKeyValue(
              l10n.routeTargetBitrate,
              data.targetBitrate == null
                  ? '—'
                  : l10n.routeKbps(data.targetBitrate!)),
          LgKeyValue(l10n.routeChroma, data.chroma ?? '—'),
          LgKeyValue(l10n.routeSpeed, data.speed ?? '—'),
        ]),
      ],
      // Only the end-to-end row until Q13 (01 §4.2): ms on the current value only.
      latency: LgLatencySection(
        title: l10n.routeSectionLatency,
        note: l10n.routeLatencyScope,
        currentLabel: l10n.routeLatencyCurrent,
        minLabel: l10n.routeLatencyMin,
        averageLabel: l10n.routeLatencyAvg,
        maxLabel: l10n.routeLatencyMax,
        rows: [
          LgLatencyRow(
            name: l10n.routeEndToEnd,
            line: LgLineStyle.primary,
            current: stats.current == null ? '—' : l10n.routeMs(stats.current!),
            min: n(stats.min),
            average: n(stats.average),
            max: n(stats.max),
          ),
        ],
        chart: LgSparkline(
          series: [LgSparkSeries(latencySlots(stats), LgLineStyle.primary)],
          unit: 'ms',
          timeLabels: [
            l10n.routeChart60s,
            l10n.routeChart30s,
            l10n.routeChartNow
          ],
          semanticLabel: stats.current == null
              ? l10n.routeLatencyChart
              : l10n.routeLatencyChartCurrent(stats.current!),
        ),
      ),
      qualitySwitch: LgDetailsSwitch(
        label: l10n.routeShowQuality,
        value: showsQualityMonitor(ffi, detailMode: t.detail),
        onChanged: (v) => setShowsQualityMonitor(ffi, v),
      ),
    );
  }
}

/// Two lines of four groups, as the mockup; the copy is the whole value.
String _fingerprintLines(String fingerprint) {
  final groups = <String>[
    for (var i = 0; i < fingerprint.length; i += 4)
      fingerprint.substring(i, (i + 4).clamp(0, fingerprint.length)),
  ];
  final half = (groups.length / 2).ceil();
  return '${groups.take(half).join(' ')}\n${groups.skip(half).join(' ')}';
}
