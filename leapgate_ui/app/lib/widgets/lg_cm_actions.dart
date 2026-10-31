// The action area of the connection manager (CM): the buttons for what the
// person at this computer may do now (01 §3.3 "操作区"; `.cm-actions`, `.row2`,
// `.cm-note`, `.tip` in A-P3.html), the voice-call row and the bubble that
// says why a click did nothing.
//
// The caller picks the combination for the state (accept and refuse; accept,
// elevate and refuse; waiting for a password; disconnect; answer or refuse a
// call; microphone and hang up; close) and passes the words.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_menu.dart';
import 'lg_panel_inputs.dart' show LgSelectItem;
import 'lg_pressable.dart';

enum LgCmActionKind { primary, secondary, danger }

/// One button of the area. [tip] is the bubble shown above it ("无法远程执行此
/// 操作" when a click is refused because it came from the remote side); the
/// caller shows it for a moment and then takes it away.
class LgCmAction {
  const LgCmAction({
    required this.label,
    required this.onPressed,
    this.kind = LgCmActionKind.secondary,
    this.icon,
    this.tip,
    this.semanticLabel,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final LgCmActionKind kind;
  final LgIcons? icon;
  final String? tip;
  final String? semanticLabel;
}

/// The rows of the action area, 12 px apart, as wide as the panel.
class LgCmActions extends StatelessWidget {
  const LgCmActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(height: LgSpace.s3),
          child,
        ],
      ],
    );
  }
}

/// One or more large buttons on a row. One button is as wide as the panel;
/// several share the width equally, or by [flex] ("接受并提升权限" takes twice
/// the room of "拒绝").
class LgCmActionRow extends StatelessWidget {
  const LgCmActionRow({super.key, required this.actions, this.flex})
    : assert(flex == null || flex.length == actions.length);

  final List<LgCmAction> actions;
  final List<int>? flex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, a) in actions.indexed) ...[
          if (i > 0) const SizedBox(width: LgSpace.s3),
          Expanded(
            flex: flex?[i] ?? 1,
            child: LgCmTipAnchor(
              tip: a.tip,
              child: LgButton(
                label: a.label,
                semanticLabel: a.semanticLabel,
                icon: a.icon,
                large: true,
                kind: switch (a.kind) {
                  LgCmActionKind.primary => LgButtonKind.primary,
                  LgCmActionKind.secondary => LgButtonKind.secondary,
                  LgCmActionKind.danger => LgButtonKind.danger,
                },
                onPressed: a.onPressed,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A line that says what is being waited for ("对方正在输入密码…"), where the
/// accept button would be.
class LgCmNote extends StatelessWidget {
  const LgCmNote({super.key, required this.text, this.icon = LgIcons.key});

  final String text;
  final LgIcons icon;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      container: true,
      label: text,
      child: ExcludeSemantics(
        child: Container(
          constraints: BoxConstraints(minHeight: t.sizes.main),
          padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(LgRadius.r12),
          ),
          child: Row(
            children: [
              LgIcon(icon, size: 20, color: c.accent),
              const SizedBox(width: LgSpace.s3),
              Expanded(
                child: Text(text, style: t.text.copyWith(color: c.text)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// During a voice call: the microphone to use and "挂断". [devices] empty means
/// this computer has no microphone: pressing the field calls [onNoDevices] and
/// the caller sets [tip] ("未找到音频输入设备").
class LgCmMicRow extends StatelessWidget {
  const LgCmMicRow({
    super.key,
    required this.microphoneLabel,
    required this.placeholder,
    required this.devices,
    required this.device,
    required this.onDeviceChanged,
    required this.hangUpLabel,
    required this.onHangUp,
    this.onNoDevices,
    this.tip,
  });

  /// The accessible name of the field ("麦克风"); the chosen device is read
  /// with it.
  final String microphoneLabel;

  /// Shown while no device is chosen ("选择麦克风").
  final String placeholder;
  final List<LgSelectItem<String>> devices;
  final String? device;
  final ValueChanged<String> onDeviceChanged;
  final String hangUpLabel;
  final VoidCallback onHangUp;
  final VoidCallback? onNoDevices;
  final String? tip;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final chosen = devices.where((d) => d.value == device).firstOrNull;
    final radius = BorderRadius.circular(LgRadius.r12);
    return Row(
      children: [
        Expanded(
          child: LgCmTipAnchor(
            tip: tip,
            align: LgCmTipAlign.start,
            child: LayoutBuilder(
              builder: (context, constraints) => LgMenuAnchor(
                width: constraints.maxWidth,
                items: [
                  for (final d in devices)
                    LgMenuItem(
                      label: d.label,
                      checked: d.value == device,
                      onPressed: () => onDeviceChanged(d.value),
                    ),
                ],
                builder: (context, controller) => LgPressable(
                  onPressed: () {
                    if (devices.isEmpty) {
                      onNoDevices?.call();
                    } else if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
                  semanticLabel: [microphoneLabel, ?(chosen?.label)].join(': '),
                  builder: (context, states) {
                    final open =
                        controller.isOpen ||
                        states.contains(WidgetState.selected);
                    return LgFocusRing(
                      show: states.contains(WidgetState.focused),
                      radius: radius,
                      child: Container(
                        height: t.sizes.main,
                        padding: const EdgeInsets.symmetric(
                          horizontal: LgSpace.s3,
                        ),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: radius,
                        ),
                        foregroundDecoration: BoxDecoration(
                          borderRadius: radius,
                          border: open
                              ? Border.all(color: c.accent, width: 2)
                              : Border.all(color: c.borderStrong, width: 1.5),
                        ),
                        child: ExcludeSemantics(
                          child: Row(
                            children: [
                              LgIcon(LgIcons.mic, size: 20, color: c.text2),
                              const SizedBox(width: LgSpace.s2),
                              Expanded(
                                child: Text(
                                  chosen?.label ?? placeholder,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.text.copyWith(
                                    color: chosen == null ? c.text2 : c.text,
                                  ),
                                ),
                              ),
                              const SizedBox(width: LgSpace.s2),
                              LgIcon(LgIcons.chevD, size: 20, color: c.text2),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: LgSpace.s3),
        _HangUpButton(label: hangUpLabel, onPressed: onHangUp),
      ],
    );
  }
}

/// "挂断": a filled quiet button with the hang-up icon in the error colour
/// (`.btn.soft`); the words stay in the text colour.
class _HangUpButton extends StatelessWidget {
  const _HangUpButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r12);
    return LgPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            height: t.sizes.main,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: overlay == null
                  ? c.surface2
                  : Color.alphaBlend(overlay, c.surface2),
              borderRadius: radius,
            ),
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LgIcon(LgIcons.callEnd, size: 20, color: c.error),
                  const SizedBox(width: LgSpace.s2),
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: t.text.copyWith(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Where the bubble's arrow points: the middle of the control, or 36 px from
/// the bubble's left end (over the icon of a field).
enum LgCmTipAlign { center, start }

/// Puts a dark bubble with an arrow 8 px above [child] while [tip] is set.
/// The bubble takes no pointer and is announced to a screen reader when it
/// appears.
class LgCmTipAnchor extends StatelessWidget {
  const LgCmTipAnchor({
    super.key,
    required this.child,
    this.tip,
    this.align = LgCmTipAlign.center,
  });

  final Widget child;
  final String? tip;
  final LgCmTipAlign align;

  @override
  Widget build(BuildContext context) {
    if (tip == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: IgnorePointer(
            child: FractionalTranslation(
              translation: const Offset(0, -1),
              child: Padding(
                padding: const EdgeInsets.only(bottom: LgSpace.s2),
                child: Align(
                  alignment: align == LgCmTipAlign.center
                      ? Alignment.topCenter
                      : Alignment.topLeft,
                  child: LgCmTip(
                    tip!,
                    arrowFromStart: align == LgCmTipAlign.start ? 36 : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The bubble itself (`.tip` of A-P3.html): inverted colours, bold small text,
/// an arrow under it. [arrowFromStart] is the arrow's centre from the left end;
/// without it the arrow is in the middle.
class LgCmTip extends StatelessWidget {
  const LgCmTip(this.text, {super.key, this.arrowFromStart});

  final String text;
  final double? arrowFromStart;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      label: text,
      child: ExcludeSemantics(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LgSpace.s3,
                vertical: LgSpace.s2,
              ),
              decoration: BoxDecoration(
                color: c.text,
                borderRadius: BorderRadius.circular(LgRadius.r10),
                boxShadow: c.shadow,
              ),
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                style: t.textS.copyWith(
                  color: c.bg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Positioned(
              bottom: -4,
              left: arrowFromStart == null ? 0 : arrowFromStart! - 4,
              right: arrowFromStart == null ? 0 : null,
              child: Center(
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: SizedBox(
                    width: 8,
                    height: 8,
                    child: ColoredBox(color: c.text),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
