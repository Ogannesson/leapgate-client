// The small table of a tunnel card (`.fl`, `.fl-r`, `.fl-add` of
// `A-P8-隧道.html`): one line for each port forward, "本机 → 目标 | 状态 | 操作",
// the note that hangs under a line, the placeholder of a card without
// forwards, and the line that unfolds in place to add one.
//
// The components only draw: every state is a parameter and every text comes
// from the caller (localised). Nothing here knows the tunnel model (docs
// LEAPGATE.md §10.8, §10.18). The parts of one card are put together by
// [LgTunnelCard].

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_banner.dart';
import 'lg_button.dart';
import 'lg_exit_card.dart';
import 'lg_pressable.dart';
import 'lg_status.dart';
import 'lg_text_field.dart';
import 'lg_tooltip.dart';

/// The columns of the table (`.fl`): the local address, the arrow, the target
/// (takes what is left), the status and the actions, 12 px apart.
const double kLgForwardLocalWidth = 200;
const double kLgForwardArrowWidth = 16;
const double kLgForwardStatusWidth = 280;
const double kLgForwardActionsWidth = 188;
const double kLgForwardGap = LgSpace.s3;

/// The width of the table below which the status moves under the addresses
/// (`.nar`): 880 leaves the target column about 140 wide. The window's smallest
/// width (960) is below it.
const double kLgForwardNarrowBelow = 880;

const double _narrowLocalWidth = 196;

/// Whether the table is laid out in its narrow form; [LgForwardList] sets it
/// from its own width, a row outside a list is wide.
class _ForwardLayout extends InheritedWidget {
  const _ForwardLayout({required this.narrow, required super.child});

  final bool narrow;

  static bool narrowOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ForwardLayout>()?.narrow ??
      false;

  @override
  bool updateShouldNotify(_ForwardLayout old) => old.narrow != narrow;
}

/// How an [LgForwardButton] looks.
enum LgForwardButtonKind {
  /// Accent-coloured words: "重新连接", "重试", "取消".
  accent,

  /// Words in the second colour: "删除".
  neutral,

  /// A filled button: "添加".
  primary,
}

/// A button of a forward's line (`.fl-a .btn`): one button-high less 4 px
/// (32, detail 28) and 10 px at the sides, so that a line of them fits in the
/// row. [semanticLabel] is the name when "重试" alone would not say which
/// forward ("重试端口转发 8080").
class LgForwardButton extends StatelessWidget {
  const LgForwardButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = LgForwardButtonKind.accent,
    this.semanticLabel,
    this.focusNode,
  });

  final String label;
  final VoidCallback? onPressed;
  final LgForwardButtonKind kind;
  final String? semanticLabel;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    const radius = BorderRadius.all(Radius.circular(LgRadius.r10));
    return LgPressable(
      onPressed: onPressed,
      focusNode: focusNode,
      semanticLabel: semanticLabel ?? label,
      builder: (context, states) {
        final disabled = states.contains(WidgetState.disabled);
        final filled = kind == LgForwardButtonKind.primary;
        var fg = switch (kind) {
          LgForwardButtonKind.accent => c.accent,
          LgForwardButtonKind.neutral => c.text2,
          LgForwardButtonKind.primary => c.onAccent,
        };
        Color? bg = filled ? c.accent : null;
        var opacity = 1.0;
        if (disabled) {
          fg = c.text2;
          if (filled) {
            bg = c.disabled;
          } else {
            opacity = .6;
          }
        }
        final overlay = lgStateOverlay(c, states);
        return Opacity(
          opacity: opacity,
          child: LgFocusRing(
            show: states.contains(WidgetState.focused),
            radius: radius,
            child: Container(
              height: t.sizes.button - 4,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: overlay == null
                    ? bg
                    : Color.alphaBlend(overlay, bg ?? Colors.transparent),
                borderRadius: radius,
              ),
              child: ExcludeSemantics(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: t.text.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A button at the end of a forward's line, as [LgForwardList] draws it.
class LgForwardAction {
  const LgForwardAction({
    required this.label,
    required this.onPressed,
    this.kind = LgForwardButtonKind.accent,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final LgForwardButtonKind kind;
  final String? semanticLabel;
}

/// The status of one forward (`.fl-s .stt`): a mark, the bold [LgExitStatus.label] in the colour of
/// the kind and the [LgExitStatus.reason] after it in regular weight, and under them, indented to
/// the label, a small [LgExitStatus.note] ("远程设备不在线"). A long text wraps and keeps its
/// indent under the mark. Only the mark, the label and the reason are announced when the status
/// changes, as in [LgExitStatusLine].
///
/// Use the kinds `busy`, `direct`, `relay`, `warning` and `error`.
class LgForwardStatusText extends StatelessWidget {
  const LgForwardStatusText(this.status, {super.key});

  final LgExitStatus status;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final (Widget mark, double markSize, Color color) = switch (status.kind) {
      LgExitStatusKind.busy => (
        LgSpinner(icon: LgIcons.markSpin, size: 12, color: c.connecting),
        12.0,
        c.connecting,
      ),
      // The detail mode draws the connection method as a path (`LgRouteMark`).
      LgExitStatusKind.direct => (
        LgIcon(
          t.detail ? LgIcons.routeDirect : LgIcons.markDot,
          size: 12,
          color: c.direct,
        ),
        12.0,
        c.direct,
      ),
      LgExitStatusKind.relay => (
        LgIcon(
          t.detail ? LgIcons.routeRelay : LgIcons.markHalf,
          size: 12,
          color: c.relay,
        ),
        12.0,
        c.relay,
      ),
      LgExitStatusKind.warning => (
        LgIcon(LgIcons.markTri, size: 12, color: c.warning),
        12.0,
        c.warning,
      ),
      LgExitStatusKind.password => (
        LgIcon(LgIcons.key, size: 16, color: c.accent),
        16.0,
        c.accent,
      ),
      LgExitStatusKind.code => (
        LgIcon(LgIcons.shield, size: 16, color: c.accent),
        16.0,
        c.accent,
      ),
      LgExitStatusKind.error => (
        LgIcon(LgIcons.markX, size: 12, color: c.error),
        12.0,
        c.error,
      ),
    };
    final bold = TextStyle(color: color, fontWeight: FontWeight.w700);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: (t.sizes.lhM - markSize) / 2),
          child: mark,
        ),
        SizedBox(
          width:
              t.detail &&
                  (status.kind == LgExitStatusKind.direct ||
                      status.kind == LgExitStatusKind.relay)
              ? 8
              : 6,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                liveRegion: true,
                container: true,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: status.label, style: bold),
                      if (status.reason != null)
                        TextSpan(
                          text: status.reason,
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      if (status.elapsed != null)
                        TextSpan(text: status.elapsed, style: bold),
                    ],
                  ),
                  style: t.textM,
                ),
              ),
              if (status.note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    status.note!,
                    style: t.textS.copyWith(color: c.text2),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One address, "主机:端口" (`.ad`): the host and the colon in [hostColor], the port in bold in
/// the text colour. A long host ends in "…" with its full text on hover; the port stays.
class _Address extends StatelessWidget {
  const _Address({required this.host, required this.port, this.hostColor});

  final String host;
  final String port;
  final Color? hostColor;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final style = t.text.copyWith(color: hostColor ?? c.text);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: LgEllipsisText(host, style: style)),
        Text(
          port,
          maxLines: 1,
          softWrap: false,
          style: t.text.copyWith(color: c.text, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// A forward of a tunnel card: the local address with the button that copies it, the target, the
/// status, the buttons, and under them the [notice] of this forward (`.fl-r`, `.fl-n`).
///
/// [localHost] and [targetHost] include the colon ("127.0.0.1:", "localhost:"): the host part of
/// the local address is in the second colour. A forward whose local port is taken has no copy
/// button: leave [onCopy] null. A forward is a group named [semanticLabel] for a screen reader,
/// by default "127.0.0.1:2222 → localhost:22"; wide it is one line (columns of
/// [kLgForwardLocalWidth], [kLgForwardStatusWidth] and [kLgForwardActionsWidth]), narrow (see
/// [kLgForwardNarrowBelow]) the status stands under the addresses and the buttons stay at the
/// right.
class LgForwardRow extends StatelessWidget {
  const LgForwardRow({
    super.key,
    required this.localHost,
    required this.localPort,
    required this.targetHost,
    required this.targetPort,
    required this.status,
    this.copyLabel,
    this.onCopy,
    this.actions = const [],
    this.notice,
    this.semanticLabel,
  }) : assert(onCopy == null || copyLabel != null);

  final String localHost;
  final String localPort;
  final String targetHost;
  final String targetPort;
  final LgExitStatus status;

  /// "复制 127.0.0.1:2222": the name of the copy button, which is drawn when [onCopy] is set.
  final String? copyLabel;
  final VoidCallback? onCopy;
  final List<LgForwardAction> actions;

  /// A note that hangs under the line and can be closed (`.fl-n`).
  final LgExitNotice? notice;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final narrow = _ForwardLayout.narrowOf(context);
    final local = Row(
      children: [
        Flexible(
          child: ExcludeSemantics(
            child: _Address(
              host: localHost,
              port: localPort,
              hostColor: c.text2,
            ),
          ),
        ),
        if (onCopy != null) ...[
          const SizedBox(width: LgSpace.s1),
          LgIconButton(
            icon: LgIcons.copy,
            label: copyLabel ?? '',
            size: 28,
            iconSize: 18,
            onPressed: onCopy,
          ),
        ],
      ],
    );
    final arrow = ExcludeSemantics(
      child: Center(child: LgIcon(LgIcons.arrowR, size: 16, color: c.text2)),
    );
    final target = ExcludeSemantics(
      child: _Address(host: targetHost, port: targetPort),
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (final (i, a) in actions.indexed) ...[
          if (i > 0) const SizedBox(width: 2),
          LgForwardButton(
            label: a.label,
            kind: a.kind,
            semanticLabel: a.semanticLabel,
            onPressed: a.onPressed,
          ),
        ],
      ],
    );
    final Widget line;
    if (narrow) {
      line = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(width: _narrowLocalWidth, child: local),
                    const SizedBox(width: kLgForwardGap),
                    SizedBox(width: kLgForwardArrowWidth, child: arrow),
                    const SizedBox(width: kLgForwardGap),
                    Expanded(child: target),
                  ],
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: LgForwardStatusText(status),
                ),
              ],
            ),
          ),
          const SizedBox(width: kLgForwardGap),
          buttons,
        ],
      );
    } else {
      line = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: kLgForwardLocalWidth, child: local),
          const SizedBox(width: kLgForwardGap),
          SizedBox(width: kLgForwardArrowWidth, child: arrow),
          const SizedBox(width: kLgForwardGap),
          Expanded(child: target),
          const SizedBox(width: kLgForwardGap),
          SizedBox(
            width: kLgForwardStatusWidth,
            child: LgForwardStatusText(status),
          ),
          const SizedBox(width: kLgForwardGap),
          // At least 188 wide: longer words (a language that needs more room) make it wider and
          // take the room from the target, not from the buttons.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: kLgForwardActionsWidth),
            child: Align(alignment: Alignment.centerRight, child: buttons),
          ),
        ],
      );
    }
    return CustomPaint(
      // `.fl-g`: a 1 px line over the group that takes no room (a box shadow).
      foregroundPainter: _TopLine(c.border),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: semanticLabel ?? '$localHost$localPort → $targetHost$targetPort',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: t.sizes.tableRow),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: t.detail ? LgSpace.s1 : LgSpace.s2,
                ),
                child: line,
              ),
            ),
            if (notice != null)
              KeyedSubtree(
                key: ValueKey('notice-${notice!.id}'),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: LgSpace.s2),
                  child: LgBanner(
                    tone: LgTone.info,
                    slim: true,
                    compact: true,
                    text: notice!.text,
                    dismissLabel: notice!.dismissLabel,
                    onDismiss: notice!.onDismiss,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopLine extends CustomPainter {
  const _TopLine(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, -1, size.width, 1),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TopLine old) => old.color != color;
}

/// The table: the names of the two columns, then the [rows]. The columns are named for the eyes
/// only; a row says what its parts are. At a width below [narrowBelow] the rows take their narrow
/// form (see [LgForwardRow]).
class LgForwardList extends StatelessWidget {
  const LgForwardList({
    super.key,
    required this.localLabel,
    required this.targetLabel,
    required this.rows,
    this.semanticLabel,
    this.narrowBelow = kLgForwardNarrowBelow,
  });

  /// "本机".
  final String localLabel;

  /// "目标".
  final String targetLabel;
  final List<LgForwardRow> rows;

  /// Name of the list for a screen reader ("端口转发").
  final String? semanticLabel;
  final double narrowBelow;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final label = t.textS.copyWith(color: c.text2, fontWeight: FontWeight.w700);
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < narrowBelow;
        return _ForwardLayout(
          narrow: narrow,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: semanticLabel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: LgSpace.s2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: narrow
                              ? _narrowLocalWidth
                              : kLgForwardLocalWidth,
                          child: Text(localLabel, style: label),
                        ),
                        const SizedBox(width: kLgForwardGap),
                        const SizedBox(width: kLgForwardArrowWidth),
                        const SizedBox(width: kLgForwardGap),
                        Expanded(child: Text(targetLabel, style: label)),
                      ],
                    ),
                  ),
                ),
                ...rows,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "暂无端口转发" (`.fl-empty`): what stands where the table would be.
class LgForwardEmpty extends StatelessWidget {
  const LgForwardEmpty(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: LgSpace.s2, bottom: LgSpace.s1),
      child: Text(text, style: t.textM.copyWith(color: t.colors.text2)),
    );
  }
}

/// The field of the add row that an error is about.
enum LgForwardField { local, host, remote }

/// The line that unfolds in a tunnel card to add a forward (`.fl-add`): on the page's background,
/// with the three fields under the columns of the table (the local port after "127.0.0.1:", the
/// target host, ":" and the remote port), "添加" and "取消" at the end, and under them
/// [errorText] when something is wrong with [errorField] (the frame of that field is red).
///
/// [onAdd] null greys "添加" (a field is empty, or a number cannot be a port); Enter in a field
/// runs it, Esc is "取消". The first field asks for the keyboard when the row is built.
class LgForwardAddRow extends StatelessWidget {
  const LgForwardAddRow({
    super.key,
    required this.localHost,
    required this.localController,
    required this.localLabel,
    required this.hostController,
    required this.hostLabel,
    required this.remoteController,
    required this.remoteLabel,
    required this.addLabel,
    required this.cancelLabel,
    required this.onAdd,
    required this.onCancel,
    this.localPlaceholder,
    this.hostPlaceholder,
    this.remotePlaceholder,
    this.errorText,
    this.errorField = LgForwardField.local,
    this.localFocusNode,
    this.semanticLabel,
    this.narrowBelow = kLgForwardNarrowBelow,
  });

  /// "127.0.0.1:".
  final String localHost;
  final TextEditingController localController;

  /// The accessible names of the three fields ("本机端口", "目标主机", "远程端口").
  final String localLabel;
  final TextEditingController hostController;
  final String hostLabel;
  final TextEditingController remoteController;
  final String remoteLabel;
  final String addLabel;
  final String cancelLabel;
  final VoidCallback? onAdd;
  final VoidCallback onCancel;
  final String? localPlaceholder;
  final String? hostPlaceholder;
  final String? remotePlaceholder;
  final String? errorText;
  final LgForwardField errorField;
  final FocusNode? localFocusNode;

  /// The name of the group ("添加端口转发").
  final String? semanticLabel;
  final double narrowBelow;

  Widget _port(
    TextEditingController controller,
    String label,
    String? placeholder,
    bool error, {
    FocusNode? focusNode,
    bool autofocus = false,
  }) => LgTextField(
    controller: controller,
    focusNode: focusNode,
    semanticLabel: label,
    placeholder: placeholder,
    dense: true,
    bodyText: true,
    autofocus: autofocus,
    maxLength: 5,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    errorText: error ? errorText : null,
    showErrorText: false,
    onSubmitted: (_) => onAdd?.call(),
  );

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final hasError = errorText != null;
    // The local column is 188 wide (the table's 200 less the row's 12 of padding); narrow, the
    // table's is 196 and this one 184, with the port field 8 px narrower to fit.
    Widget localRow(bool narrow) => Row(
      children: [
        Flexible(
          child: ExcludeSemantics(
            child: Text(
              localHost,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: t.text.copyWith(color: c.text2),
            ),
          ),
        ),
        const SizedBox(width: LgSpace.s1),
        SizedBox(
          width: narrow ? 104 : 112,
          child: _port(
            localController,
            localLabel,
            localPlaceholder,
            hasError && errorField == LgForwardField.local,
            focusNode: localFocusNode,
            autofocus: true,
          ),
        ),
      ],
    );
    final targetRow = Row(
      children: [
        Expanded(
          child: LgTextField(
            controller: hostController,
            semanticLabel: hostLabel,
            placeholder: hostPlaceholder,
            dense: true,
            bodyText: true,
            errorText: hasError && errorField == LgForwardField.host
                ? errorText
                : null,
            showErrorText: false,
            onSubmitted: (_) => onAdd?.call(),
          ),
        ),
        const SizedBox(width: LgSpace.s2),
        ExcludeSemantics(
          child: Text(':', style: t.text.copyWith(color: c.text2)),
        ),
        const SizedBox(width: LgSpace.s2),
        SizedBox(
          width: 112,
          child: _port(
            remoteController,
            remoteLabel,
            remotePlaceholder,
            hasError && errorField == LgForwardField.remote,
          ),
        ),
      ],
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LgForwardButton(
          label: addLabel,
          kind: LgForwardButtonKind.primary,
          onPressed: onAdd,
        ),
        const SizedBox(width: 2),
        LgForwardButton(label: cancelLabel, onPressed: onCancel),
      ],
    );
    final arrow = SizedBox(
      width: kLgForwardArrowWidth,
      child: ExcludeSemantics(
        child: Center(child: LgIcon(LgIcons.arrowR, size: 16, color: c.text2)),
      ),
    );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onCancel},
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: semanticLabel,
        child: Container(
          padding: const EdgeInsets.all(LgSpace.s3),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(LgRadius.r12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  // The status column is empty here; in the narrow form it is dropped.
                  final narrow =
                      constraints.maxWidth + 2 * LgSpace.s3 < narrowBelow;
                  return Row(
                    children: [
                      SizedBox(
                        width: narrow ? 184 : 188,
                        child: localRow(narrow),
                      ),
                      const SizedBox(width: kLgForwardGap),
                      arrow,
                      const SizedBox(width: kLgForwardGap),
                      Expanded(child: targetRow),
                      const SizedBox(width: kLgForwardGap),
                      if (narrow)
                        buttons
                      else ...[
                        const SizedBox(width: kLgForwardStatusWidth),
                        const SizedBox(width: kLgForwardGap),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 176),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: buttons,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              if (hasError) ...[
                const SizedBox(height: LgSpace.s2),
                // Read as part of the field's name (see `LgTextField`).
                ExcludeSemantics(child: LgFieldError(errorText!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
