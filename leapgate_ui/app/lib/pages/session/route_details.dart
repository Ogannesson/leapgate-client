import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/latency.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/leapgate/session_route.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/tab_overlays.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_menu.dart';
import '../../widgets/lg_pressable.dart';
import '../../widgets/lg_selection.dart';
import '../../widgets/lg_session_toolbar.dart';
import '../../widgets/lg_status.dart';
import '../../widgets/lg_tooltip.dart';
import 'session_names.dart';

/// Width of the details panel (`d-conn`).
const kRouteDetailsWidth = 520.0;

/// The toolbar's connection mark (01 P2 block B, item 10), or null until the connection is
/// ready. Clicking it opens the connection details (01 §4.2 second level).
Widget? sessionRouteMark(BuildContext context, FFI ffi, TabOverlays overlays) {
  final conn = ffi.connection;
  if (!showsRoute(conn)) return null;
  final l10n = AppLocalizations.of(context)!;
  final direct = conn.direct == true;
  final encrypted = conn.secure != false;
  final routeTip = direct ? l10n.sessionDirectTip : l10n.sessionRelayedTip;
  return LgMenuAnchor(
    width: kRouteDetailsWidth,
    items: [RouteDetails(ffi: ffi)],
    builder: (context, controller) => LgTooltip(
      message: encrypted ? routeTip : '$routeTip\n${l10n.sessionUnencryptedTip}',
      child: LgPressable(
        semanticLabel: l10n.routeDetails,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        builder: (context, states) => LgToolbarStatus(child: _mark(ffi, l10n)),
      ),
    ),
  );
}

Widget _mark(FFI ffi, AppLocalizations l10n) {
  final conn = ffi.connection;
  final direct = conn.direct == true;
  return LgRouteMark(
    route: direct ? LgRoute.direct : LgRoute.relay,
    label: direct ? l10n.sessionDirect : l10n.sessionRelayed,
    encrypted: conn.secure != false,
    unencryptedLabel: l10n.sessionUnencrypted,
  );
}

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

/// The connection details (01 §4.2, `d-conn`): the first level, then the connection (path and
/// relay server from Q3, transport, encryption and fingerprint), the image data, the round trip
/// and the switch for the quality data. Rebuilt with the connection, so a reconnect reads Q3 again
/// once it is connected. A stand-in for the designer's `LgRouteDetails`.
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
    final shown = showsQualityMonitor(ffi, detailMode: t.detail);

    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: LgSpace.s1),
        child: Align(alignment: Alignment.centerLeft, child: _mark(ffi, l10n)),
      ),
      _note(t, direct ? l10n.routeDirectNote : l10n.routeRelayedNote),
      if (!encrypted) _note(t, l10n.routeUnencryptedNote),
      _section(t, l10n.routeSectionConnection),
      if (path != null) _row(t, l10n.routePath, path),
      if (route.relay != null) _row(t, l10n.routeRelayServer, route.relay!),
      _row(t, l10n.routeTransport, transport.toUpperCase()),
      _row(t, l10n.routeEncryption,
          encrypted ? l10n.routeEncrypted : l10n.routeUnencrypted),
      if (fingerprint.isNotEmpty) _fingerprint(context, t, l10n, fingerprint),
      _section(t, l10n.routeSectionImage),
      _row(t, l10n.routeCodec, data.codecFormat ?? '—'),
      _row(t, l10n.routeFps, data.fps ?? '—'),
      _row(t, l10n.routeTargetBitrate,
          data.targetBitrate == null ? '—' : l10n.routeKbps(data.targetBitrate!)),
      _row(t, l10n.routeChroma, data.chroma ?? '—'),
      _row(t, l10n.routeSpeed, data.speed ?? '—'),
      _section(t, l10n.routeSectionLatency, note: l10n.routeLatencyScope),
      _latencyTable(t, l10n, ffi.latency),
      Padding(
        padding: const EdgeInsets.only(top: LgSpace.s2),
        child: SizedBox(
          height: 64,
          child: LatencyLine(stats: ffi.latency, label: l10n.routeLatencyChart),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: LgSpace.s3),
        child: Row(children: [
          Expanded(child: Text(l10n.routeShowQuality, style: t.text)),
          LgSwitch(
            value: shown,
            semanticLabel: l10n.routeShowQuality,
            onChanged: (v) => setShowsQualityMonitor(ffi, v),
          ),
        ]),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: LgSpace.s4, vertical: LgSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }

  Widget _note(LgTokens t, String text) =>
      Text(text, style: t.textS.copyWith(color: t.colors.text2));

  Widget _section(LgTokens t, String title, {String? note}) => Padding(
        padding: const EdgeInsets.only(top: LgSpace.s3, bottom: LgSpace.s1),
        child: Row(children: [
          Semantics(
            header: true,
            child: Text(title,
                style: t.textS.copyWith(
                    color: t.colors.text2, fontWeight: FontWeight.w700)),
          ),
          if (note != null) ...[
            const SizedBox(width: LgSpace.s2),
            Expanded(
                child: Text(note,
                    style: t.textS.copyWith(color: t.colors.text2))),
          ],
        ]),
      );

  Widget _row(LgTokens t, String name, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(
              width: 120,
              child: Text(name, style: t.text.copyWith(color: t.colors.text2))),
          Expanded(child: Text(value, style: t.text)),
        ]),
      );

  /// Two lines of four groups, as the mockup; the copy is the whole value.
  Widget _fingerprint(BuildContext context, LgTokens t, AppLocalizations l10n,
      String fingerprint) {
    final groups = <String>[
      for (var i = 0; i < fingerprint.length; i += 4)
        fingerprint.substring(i, (i + 4).clamp(0, fingerprint.length)),
    ];
    final half = (groups.length / 2).ceil();
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
          width: 120,
          child: Text(l10n.routeFingerprint,
              style: t.text.copyWith(color: t.colors.text2))),
      Expanded(
        child: Text(
          '${groups.take(half).join(' ')}\n${groups.skip(half).join(' ')}',
          style: t.text,
        ),
      ),
      LgIconButton(
        icon: LgIcons.copy,
        label: l10n.routeCopyFingerprint,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: fingerprint));
          appCore.toasts.show('Copied');
        },
      ),
    ]);
  }

  /// Only the end-to-end row until Q13 (01 §4.2): ms on the current value only.
  Widget _latencyTable(LgTokens t, AppLocalizations l10n, LatencyStats s) {
    String n(num? v) => v == null ? '—' : '${v.round()}';
    TextStyle head = t.textS.copyWith(color: t.colors.text2);
    Widget cell(String text, TextStyle style) => Expanded(
        child: Text(text, style: style, textAlign: TextAlign.right));
    return Column(children: [
      Row(children: [
        const SizedBox(width: 120),
        cell(l10n.routeLatencyCurrent, head),
        cell(l10n.routeLatencyMin, head),
        cell(l10n.routeLatencyAvg, head),
        cell(l10n.routeLatencyMax, head),
      ]),
      Row(children: [
        SizedBox(width: 120, child: Text(l10n.routeEndToEnd, style: t.text)),
        cell(s.current == null ? '—' : l10n.routeMs(s.current!), t.text),
        cell(n(s.min), t.text),
        cell(n(s.average), t.text),
        cell(n(s.max), t.text),
      ]),
    ]);
  }
}

/// The last 60 s of the round trip as one line (a stand-in for the designer's `LgSparkline`).
class LatencyLine extends StatelessWidget {
  const LatencyLine({super.key, required this.stats, required this.label});

  final LatencyStats stats;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return Semantics(
      label: label,
      image: true,
      child: CustomPaint(
        size: Size.infinite,
        // Aged on the statistics' clock.
        painter: _LinePainter(
            [for (final p in stats.points) (age: stats.ageOf(p), ms: p.ms)],
            c.text,
            c.border),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.points, this.color, this.axis);

  final List<({Duration age, int ms})> points;
  final Color color;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height),
        Paint()..color = axis);
    if (points.isEmpty) return;
    final top = points.map((p) => p.ms).reduce((a, b) => a > b ? a : b);
    final span = LatencyStats.window.inMilliseconds;
    Offset at(({Duration age, int ms}) p) => Offset(
          size.width * (1 - p.age.inMilliseconds / span),
          size.height * (1 - p.ms / (top == 0 ? 1 : top * 1.2)),
        );
    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (final p in points.skip(1)) {
      path.lineTo(at(p).dx, at(p).dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_LinePainter old) => true;
}
