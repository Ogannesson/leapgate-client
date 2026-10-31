// The connection state panel of a session tab (01 §3.2 block D, §4.1; `.sheet`
// in A-基础.html and `c-*`, `e-*` in A-P2.html). One card in the middle of the
// tab that replaces the chain of modal boxes of the upstream: who it is, how
// far the connection is, what is going on or went wrong, the inputs that are
// asked for, the buttons.
//
// The panel only draws. Which of the states of 01 §3.2 it is, and every
// string in it, is the caller's: the panel has a slot for each thing a state
// can show and leaves the others out.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_banner.dart';
import 'lg_button.dart';
import 'lg_default_enter.dart';
import 'lg_device.dart';
import 'lg_status.dart';

/// How far one step of the connection is (`.dot`).
enum LgStepState { todo, current, done, failed }

/// One of the steps shown under the device: "建立连接", "验证身份".
class LgPanelStep {
  const LgPanelStep(this.label, this.state);

  final String label;
  final LgStepState state;
}

/// The colour of the message: [normal] is a line of text, the other two put
/// it in a banner with a warning or an error icon.
enum LgPanelTone { normal, warning, error }

/// "‹n› 秒后重试（第 ‹k› 次）" with a bar that fills until the retry.
class LgPanelCountdown {
  const LgPanelCountdown({required this.text, required this.progress});

  final String text;

  /// 0..1, how much of the wait has passed.
  final double progress;
}

/// A button of the panel. Primary buttons fill the rest of the row.
///
/// [isDefault] marks what Enter does (at most one button; none means Enter
/// does nothing, as in an error). Without inputs in the panel the default
/// button takes the keyboard focus when the panel appears, so Enter is its own
/// press; with inputs, Enter in an input runs it. With the focus on any other
/// button, Enter is that button's.
class LgPanelAction {
  const LgPanelAction({
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.isDefault = false,
    this.semanticLabel,
  });

  final String label;

  /// Null shows the button disabled (the "connect" of an empty password).
  final VoidCallback? onPressed;
  final bool primary;
  final bool isDefault;

  /// The accessible name when it must differ from [label].
  final String? semanticLabel;
}

const double _gap = LgSpace.s3;

class LgConnectionPanel extends StatelessWidget {
  const LgConnectionPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.platform,
    this.steps,
    this.tone = LgPanelTone.normal,
    this.message,
    this.messageIcon,
    this.detail,
    this.busy = false,
    this.secondary,
    this.notice,
    this.hint,
    this.countdown,
    this.inputs = const [],
    this.actions = const [],
    this.dimBackdrop = false,
    this.width = 440,
    this.semanticLabel,
  });

  /// The device name.
  final String title;

  /// The device ID, formatted ("456 789 123"); also gives the identity colour.
  final String subtitle;
  final LgPlatform platform;

  /// The two steps; null leaves them out (a device that is restarting).
  final List<LgPanelStep>? steps;
  final LgPanelTone tone;

  /// What is going on, in one sentence ("正在连接 客厅迷你主机…", "输入密码");
  /// with a warning or error [tone] it is the bold first line of the banner.
  final String? message;

  /// Replaces the icon of the banner (a crossed-out signal for a lost link).
  final LgIcons? messageIcon;

  /// The rest of the banner text of a warning or error.
  final String? detail;

  /// A turning arrow before the message: the panel is waiting for something.
  final bool busy;

  /// A small plain line under the message ("已等待 0:12").
  final String? secondary;

  /// A line in a banner of its own ("显示给对方的名称：张三", the hint that the
  /// remote screen may be locked).
  final String? notice;

  /// A small line with an info icon under the banner.
  final String? hint;
  final LgPanelCountdown? countdown;

  /// Fields and check boxes that are asked for, top to bottom.
  final List<Widget> inputs;
  final List<LgPanelAction> actions;

  /// Dims the whole area behind the card (the last picture of a device that
  /// restarts shows through, 01 §4.1).
  final bool dimBackdrop;
  final double width;

  /// Accessible name of the panel as a whole ("连接过程 · 要密码").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final h4 = t.textN.copyWith(color: c.text, fontWeight: FontWeight.w700);
    final banner =
        tone != LgPanelTone.normal && (message != null || detail != null);
    final defaultAction = actions
        .where((a) => a.isDefault && a.onPressed != null)
        .firstOrNull;

    final card = Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: c.float,
        borderRadius: BorderRadius.circular(LgRadius.r20),
        boxShadow: c.shadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LgDeviceAvatar(id: subtitle, platform: platform),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LgTokens.style(
                        20,
                        28,
                        FontWeight.w700,
                      ).copyWith(color: c.text),
                    ),
                    Text(
                      subtitle,
                      style: t.text.copyWith(
                        color: c.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (steps != null) ...[
            const SizedBox(height: LgSpace.s6),
            _Steps(steps!),
          ],
          if (message != null && !banner) ...[
            SizedBox(height: busy ? LgSpace.s7 : 28),
            Semantics(
              liveRegion: busy,
              child: busy
                  ? Row(
                      children: [
                        LgSpinner(
                          icon: LgIcons.spinner,
                          size: 24,
                          color: c.accent,
                        ),
                        const SizedBox(width: _gap),
                        Expanded(child: Text(message!, style: h4)),
                      ],
                    )
                  : Text(message!, style: h4),
            ),
          ],
          if (banner) ...[
            const SizedBox(height: LgSpace.s5),
            LgBanner(
              tone: tone == LgPanelTone.error ? LgTone.error : LgTone.warning,
              icon: messageIcon,
              title: message,
              text: detail,
            ),
          ],
          if (secondary != null) ...[
            const SizedBox(height: LgSpace.s5),
            Text(secondary!, style: t.textM.copyWith(color: c.text2)),
          ],
          if (notice != null) ...[
            const SizedBox(height: LgSpace.s5),
            LgBanner(tone: LgTone.info, text: notice),
          ],
          if (hint != null) ...[
            const SizedBox(height: _gap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: LgIcon(LgIcons.info, size: 16, color: c.accent),
                ),
                const SizedBox(width: LgSpace.s2),
                Expanded(
                  child: Text(hint!, style: t.textS.copyWith(color: c.text2)),
                ),
              ],
            ),
          ],
          if (countdown != null) ...[
            const SizedBox(height: LgSpace.s4),
            _Countdown(countdown!),
          ],
          for (final (i, input) in inputs.indexed) ...[
            SizedBox(height: i == 0 ? 14 : LgSpace.s4),
            input,
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: LgSpace.s5),
            _Actions(
              actions: actions,
              autofocus: inputs.isEmpty ? defaultAction : null,
            ),
          ],
        ],
      ),
    );

    Widget body = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(LgSpace.s6),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          // The card grows and shrinks between states instead of jumping
          // (AnimatedSize with a zero duration fails in layout, so it is left
          // out when the system asks for no motion).
          child: MediaQuery.disableAnimationsOf(context)
              ? card
              : AnimatedSize(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  child: card,
                ),
        ),
      ),
    );
    if (dimBackdrop) {
      body = Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: c.scrim)),
          body,
        ],
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel ?? title,
      child: LgDefaultEnter(
        onEnter: defaultAction?.onPressed,
        // Tab goes round the card and never out to what is under or around it
        // (the toolbar, the title bar); the scope takes the focus when the
        // card appears.
        child: FocusScope(autofocus: true, child: body),
      ),
    );
  }
}

/// The steps (`.steps`): a dot with a number or a mark and the name, joined
/// by bars that are filled up to the last finished step.
class _Steps extends StatelessWidget {
  const _Steps(this.steps);

  final List<LgPanelStep> steps;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Row(
      children: [
        for (final (i, step) in steps.indexed) ...[
          if (i > 0)
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minWidth: 12),
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
                decoration: BoxDecoration(
                  color: steps[i - 1].state == LgStepState.done
                      ? c.accent
                      : c.track,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Flexible(
            child: Semantics(
              selected: step.state == LgStepState.current,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Dot(index: i + 1, state: step.state),
                  const SizedBox(width: LgSpace.s2),
                  Flexible(
                    child: Text(
                      step.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: t.textS.copyWith(
                        color: switch (step.state) {
                          LgStepState.current => c.text,
                          LgStepState.failed => c.error,
                          _ => c.text2,
                        },
                        fontWeight:
                            step.state == LgStepState.current ||
                                step.state == LgStepState.failed
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.index, required this.state});

  final int index;
  final LgStepState state;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    final number = LgTokens.style(13, 22, FontWeight.w700);
    final (Color? fill, Color? ring, Widget child) = switch (state) {
      LgStepState.done => (
        c.accent,
        null,
        LgIcon(LgIcons.check, size: 14, color: c.onAccent),
      ),
      LgStepState.failed => (
        c.error,
        null,
        LgIcon(LgIcons.x, size: 14, color: c.onAccent),
      ),
      LgStepState.current => (
        null,
        c.accent,
        Text('$index', style: number.copyWith(color: c.accent)),
      ),
      LgStepState.todo => (
        null,
        c.borderStrong,
        Text('$index', style: number.copyWith(color: c.text2)),
      ),
    };
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
      foregroundDecoration: ring == null
          ? null
          : BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: 2),
            ),
      child: child,
    );
  }
}

/// "4 秒后重试（第 3 次）" over a thin bar that fills (`.cd`).
class _Countdown extends StatelessWidget {
  const _Countdown(this.countdown);

  final LgPanelCountdown countdown;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final animate = !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LgSpinner(icon: LgIcons.spinner, size: 20, color: c.text2),
              const SizedBox(width: LgSpace.s2),
              Expanded(
                child: Text(
                  countdown.text,
                  style: t.textM.copyWith(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LgSpace.s2),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: c.track,
              borderRadius: BorderRadius.circular(2),
            ),
            alignment: Alignment.centerLeft,
            // The caller sets a new value once a second; run the bar in
            // between.
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: countdown.progress.clamp(0.0, 1.0)),
              duration: animate ? const Duration(seconds: 1) : Duration.zero,
              curve: Curves.linear,
              builder: (context, value, _) => FractionallySizedBox(
                widthFactor: value,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.warning,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The buttons: in one row with the primary one filling what is left (or the
/// last one when none is primary); when the labels do not fit the width, one
/// under the other with the primary first.
class _Actions extends StatelessWidget {
  const _Actions({required this.actions, required this.autofocus});

  final List<LgPanelAction> actions;

  /// The default button, when it should take the focus.
  final LgPanelAction? autofocus;

  static const double _padding = 24;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final style = t.text.copyWith(fontWeight: FontWeight.w700);
    double labelWidth(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final fill = actions.indexWhere((a) => a.primary) >= 0
        ? actions.indexWhere((a) => a.primary)
        : actions.length - 1;

    Widget button(int i) {
      final a = actions[i];
      return LgButton(
        label: a.label,
        large: true,
        horizontalPadding: _padding,
        kind: a.primary ? LgButtonKind.primary : LgButtonKind.secondary,
        autofocus: a == autofocus,
        semanticLabel: a.semanticLabel,
        onPressed: a.onPressed,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final needed =
            actions.fold<double>(
              0,
              (sum, a) => sum + labelWidth(a.label) + 2 * _padding,
            ) +
            _gap * (actions.length - 1);
        if (needed <= constraints.maxWidth) {
          return Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                i == fill ? Expanded(child: button(i)) : button(i),
              ],
            ],
          );
        }
        final order = [
          fill,
          for (var i = 0; i < actions.length; i++)
            if (i != fill) i,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (n, i) in order.indexed) ...[
              if (n > 0) const SizedBox(height: _gap),
              button(i),
            ],
          ],
        );
      },
    );
  }
}
