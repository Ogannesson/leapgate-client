// Status text, connection-method marker and count badge (A-基础.html "连接方式标记",
// 01 §4.2). A state is never shown by colour alone: shape, colour and text
// always go together (01 §7.1). Labels come from the caller (localised).

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';

/// States drawn with the compact shapes in both modes.
enum LgStatus {
  /// Filled dot, online colour.
  online,

  /// Ring, offline colour (also "已断开" on a session tab).
  offline,

  /// Spinning 3/4 arc, connecting colour ("正在连接…").
  connecting,

  /// Spinning 3/4 arc, offline colour: status still loading ("正在查询…").
  querying,

  /// Triangle, warning colour ("已中断", "连接失败").
  warning,

  /// Circled x, error colour.
  error,
}

/// Marker and text in the marker's colour, bold (`.stt`). The font size is the
/// ambient one, as in the mockups where the parent sets it.
class LgStatusText extends StatelessWidget {
  const LgStatusText(this.status, this.label, {super.key, this.gap = 6});

  final LgStatus status;
  final String label;

  /// Marker to text: 6 (`.stt`), 8 for the service status line (`.stline`).
  final double gap;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    final (icon, color) = switch (status) {
      LgStatus.online => (LgIcons.markDot, c.online),
      LgStatus.offline => (LgIcons.markRing, c.offline),
      LgStatus.connecting => (LgIcons.markSpin, c.connecting),
      LgStatus.querying => (LgIcons.markSpin, c.offline),
      LgStatus.warning => (LgIcons.markTri, c.warning),
      LgStatus.error => (LgIcons.markX, c.error),
    };
    final spinning =
        status == LgStatus.connecting || status == LgStatus.querying;
    return _Marked(
      color: color,
      gap: gap,
      marks: [
        spinning
            ? LgSpinner(icon: icon, size: 12, color: color)
            : LgIcon(icon, size: 12, color: color),
      ],
      label: label,
    );
  }
}

enum LgRoute { direct, relay }

/// Connection-method marker (03 §4.2, one component, two drawings): compact
/// mode draws shapes (dot = direct, half dot = relayed), detail mode draws
/// paths (two ends and a line, a diamond in the middle when relayed).
///
/// An unencrypted connection adds the warning triangle:
/// * by default the route stays as it is (dashed path in detail mode) and a
///   second "△ [unencryptedLabel]" follows — toolbar, single-view tab, exit card;
/// * with [worstOnly] only the unencrypted marker is shown (compact: △; detail:
///   △ plus the dashed path), all in the unencrypted colour — a tab with
///   several views, the phone toolbar.
class LgRouteMark extends StatelessWidget {
  const LgRouteMark({
    super.key,
    required this.route,
    required this.label,
    this.encrypted = true,
    this.unencryptedLabel,
    this.worstOnly = false,
  }) : assert(encrypted || unencryptedLabel != null);

  final LgRoute route;
  final String label;
  final bool encrypted;
  final String? unencryptedLabel;
  final bool worstOnly;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final detail = t.detail;
    final dashedPath = route == LgRoute.direct
        ? LgIcons.routeDirectU
        : LgIcons.routeRelayU;
    if (!encrypted && worstOnly) {
      return _Marked(
        color: c.unencrypted,
        gap: detail ? 8 : 6,
        marks: [
          LgIcon(LgIcons.markTri, size: 12, color: c.unencrypted),
          if (detail) LgIcon(dashedPath, size: 12, color: c.unencrypted),
        ],
        label: unencryptedLabel!,
      );
    }
    final color = route == LgRoute.direct ? c.direct : c.relay;
    final LgIcons mark;
    if (!detail) {
      mark = route == LgRoute.direct ? LgIcons.markDot : LgIcons.markHalf;
    } else if (encrypted) {
      mark = route == LgRoute.direct ? LgIcons.routeDirect : LgIcons.routeRelay;
    } else {
      mark = dashedPath;
    }
    final routeMark = _Marked(
      color: color,
      gap: detail ? 8 : 6,
      marks: [LgIcon(mark, size: 12, color: color)],
      label: label,
    );
    if (encrypted) return routeMark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        routeMark,
        const SizedBox(width: LgSpace.s2),
        _Marked(
          color: c.unencrypted,
          gap: 6,
          marks: [LgIcon(LgIcons.markTri, size: 12, color: c.unencrypted)],
          label: unencryptedLabel!,
        ),
      ],
    );
  }
}

class _Marked extends StatelessWidget {
  const _Marked({
    required this.color,
    required this.gap,
    required this.marks,
    required this.label,
  });

  final Color color;
  final double gap;
  final List<Widget> marks;
  final String label;

  // One rich text, so it works in unbounded rows (tab strip) and wraps in
  // bounded ones.
  @override
  Widget build(BuildContext context) {
    WidgetSpan box(Widget w) =>
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: w);
    return Text.rich(
      TextSpan(
        children: [
          for (final (i, m) in marks.indexed) ...[
            if (i > 0) box(SizedBox(width: gap)),
            box(m),
          ],
          box(SizedBox(width: gap)),
          TextSpan(text: label),
        ],
      ),
      style: TextStyle(color: color, fontWeight: FontWeight.w700),
    );
  }
}

/// An icon turning once a second (`.spin`); still when the system asks for
/// reduced motion.
class LgSpinner extends StatefulWidget {
  const LgSpinner({
    super.key,
    this.icon = LgIcons.spinner,
    required this.size,
    this.color,
  });

  final LgIcons icon;
  final double size;
  final Color? color;

  @override
  State<LgSpinner> createState() => _LgSpinnerState();
}

class _LgSpinnerState extends State<LgSpinner>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _controller,
    child: LgIcon(widget.icon, size: widget.size, color: widget.color),
  );
}

/// Count badge (`.badge`): unread chat, background connections.
class LgBadge extends StatelessWidget {
  const LgBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(LgRadius.r6),
      ),
      child: Text(
        '$count',
        style: LgTokens.style(
          13,
          20,
          FontWeight.w700,
        ).copyWith(color: c.onAccent),
      ),
    );
  }
}
