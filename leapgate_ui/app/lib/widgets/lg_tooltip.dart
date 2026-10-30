import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/lg_tokens.dart';

const _hoverDelay = Duration(milliseconds: 500);
const _gap = 8.0;

/// Hover tooltip (`.tip` in A-P2.html): a floating box 8 px below the anchor,
/// left-aligned with it, flipped above when there is no room.
///
/// Use [message] for plain text, [content] for richer layouts such as the
/// session tab tooltip (name, ID, one line per open view).
class LgTooltip extends StatelessWidget {
  const LgTooltip({super.key, this.message, this.content, required this.child})
    : assert((message == null) != (content == null)),
      _when = null;

  const LgTooltip._conditional({
    required String this.message,
    required bool Function() when,
    required this.child,
  }) : content = null,
       _when = when;

  final String? message;
  final Widget? content;
  final Widget child;
  final bool Function()? _when;

  @override
  Widget build(BuildContext context) {
    return RawTooltip(
      semanticsTooltip: _when == null ? message : null,
      hoverDelay: _hoverDelay,
      triggerMode: TooltipTriggerMode.longPress,
      positionDelegate: _position,
      tooltipBuilder: (context, animation) {
        if (_when != null && !_when()) return const SizedBox.shrink();
        return FadeTransition(
          opacity: animation,
          child: LgTooltipBox(child: content ?? Text(message!)),
        );
      },
      child: child,
    );
  }

  static Offset _position(TooltipPositionContext p) {
    final left = p.target.dx - p.targetSize.width / 2;
    final top = p.target.dy - p.targetSize.height / 2;
    final bottom = p.target.dy + p.targetSize.height / 2;
    final x = math.max(
      0.0,
      math.min(left, p.overlaySize.width - p.tooltipSize.width),
    );
    final below = bottom + _gap;
    final y =
        below + p.tooltipSize.height <= p.overlaySize.height ||
            top - _gap - p.tooltipSize.height < 0
        ? below
        : top - _gap - p.tooltipSize.height;
    return Offset(x, y);
  }
}

/// The floating box of a tooltip. Public so the gallery can show it in place.
class LgTooltipBox extends StatelessWidget {
  const LgTooltipBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      padding: const EdgeInsets.symmetric(
        vertical: LgSpace.s3,
        horizontal: LgSpace.s4,
      ),
      decoration: BoxDecoration(
        color: c.float,
        borderRadius: BorderRadius.circular(LgRadius.r12),
        boxShadow: c.shadow,
      ),
      child: DefaultTextStyle(
        style: t.textS.copyWith(color: c.text),
        child: child,
      ),
    );
  }
}

/// Single-line text that ends in "…" when it does not fit and shows the full
/// text in a tooltip on hover (menu items, tab names, card names; 01 §7.1).
class LgEllipsisText extends StatefulWidget {
  const LgEllipsisText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<LgEllipsisText> createState() => _LgEllipsisTextState();
}

class _LgEllipsisTextState extends State<LgEllipsisText> {
  final _key = GlobalKey();

  bool _overflows() {
    final box = _key.currentContext?.findRenderObject();
    return box is RenderParagraph && box.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    return LgTooltip._conditional(
      message: widget.text,
      when: _overflows,
      child: Text(
        widget.text,
        key: _key,
        style: widget.style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
