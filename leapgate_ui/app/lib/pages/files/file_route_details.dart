import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/leapgate/session_route.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_route_details.dart';
import '../../widgets/lg_session_toolbar.dart';
import '../../widgets/lg_status.dart';
import '../../widgets/lg_tooltip.dart';
import '../session/route_details.dart';
import '../session/session_names.dart';

/// The connection mark on the file transfer view's title bar (02 §2.2 block A item 2): this
/// connection's "直连 / 经中继", nothing until it is ready. Clicking it opens [FileRouteDetails]
/// under it. As the toolbar's `sessionRouteMark`.
class FileRouteMark extends StatelessWidget {
  const FileRouteMark({super.key, required this.ffi});

  final FFI ffi;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ffi.connection,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final conn = ffi.connection;
    if (!showsRoute(conn)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final direct = conn.direct == true;
    final encrypted = conn.secure != false;
    final routeTip = direct ? l10n.sessionDirectTip : l10n.sessionRelayedTip;
    return MenuAnchor(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      alignmentOffset: const Offset(0, LgSpace.s1),
      menuChildren: [FileRouteDetails(ffi: ffi)],
      builder: (context, controller, _) => LgTooltip(
        message: encrypted
            ? routeTip
            : '$routeTip\n${l10n.sessionUnencryptedTip}',
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
}

/// The connection details of a file transfer (02 §2.2 block A item 2, 01 §4.2): the remote
/// desktop's `RouteDetails` without the image data and the quality data switch; the round trip
/// shows as there (a file transfer connection has TestDelay too).
class FileRouteDetails extends StatelessWidget {
  const FileRouteDetails({super.key, required this.ffi});

  final FFI ffi;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([ffi.connection, ffi.latency]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final conn = ffi.connection;
    final direct = conn.direct == true;
    final encrypted = conn.secure != false;
    final route = sessionRoute(ffi);
    final path = routePathName(l10n, route.path);
    final transport =
        route.transport ??
        (const ['UDP', 'IPv6', 'WebRTC'].contains(conn.streamType)
            ? 'udp'
            : 'tcp');
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
      ],
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
            l10n.routeChartNow,
          ],
          semanticLabel: stats.current == null
              ? l10n.routeLatencyChart
              : l10n.routeLatencyChartCurrent(stats.current!),
        ),
      ),
    );
  }
}

/// Two lines of four groups, as `route_details.dart` shows it; the copy is the whole value.
String _fingerprintLines(String fingerprint) {
  final groups = <String>[
    for (var i = 0; i < fingerprint.length; i += 4)
      fingerprint.substring(i, (i + 4).clamp(0, fingerprint.length)),
  ];
  final half = (groups.length / 2).ceil();
  return '${groups.take(half).join(' ')}\n${groups.skip(half).join(' ')}';
}
