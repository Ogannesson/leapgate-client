// The password row of this device's block (01 §3.1 block A, `.pw`, `.pwt`,
// `.pwn` in A-P1.html): a label, the value, an optional line of small text and
// the actions. Which of the five appearances it is (one-time password, both,
// fixed only, approve on this device, service stopped) is decided by the caller
// through the text and the emphasis.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';

/// How the value of a [LgPasswordRow] is set.
enum LgPasswordValue {
  /// The password itself: 28 px, bold, accent colour, easy to read out.
  code,

  /// A short statement in bold ("已设置", "不可用").
  statement,

  /// A sentence ("需在本机接受连接请求").
  sentence,
}

/// One password line: [label] over [value], then the small [note], then
/// [onCopy]'s button and the optional [actions] (refresh, change; M2b).
class LgPasswordRow extends StatelessWidget {
  const LgPasswordRow({
    super.key,
    required this.label,
    required this.value,
    this.style = LgPasswordValue.statement,
    this.note,
    this.dim = false,
    this.onCopy,
    this.copyLabel,
    this.copySemanticLabel,
    this.actions = const [],
  }) : assert(onCopy == null || copyLabel != null);

  final String label;
  final String value;
  final LgPasswordValue style;

  /// Small line under the value ("也可使用固定密码").
  final String? note;

  /// Greys the value: nothing to show ("不可用").
  final bool dim;

  /// Null hides the copy button.
  final VoidCallback? onCopy;
  final String? copyLabel;

  /// Accessible name of the copy button when it is not its text ("复制密码",
  /// next to the "复制" of the ID).
  final String? copySemanticLabel;

  /// Further buttons after the copy button, in a row.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final valueStyle = switch (style) {
      LgPasswordValue.code => LgTokens.style(
        28,
        32,
        FontWeight.w700,
      ).copyWith(color: dim ? c.text2 : c.accent),
      LgPasswordValue.statement => t.textN.copyWith(
        color: dim ? c.text2 : c.text,
        fontWeight: FontWeight.w700,
      ),
      LgPasswordValue.sentence => t.textM.copyWith(
        color: dim ? c.text2 : c.text,
      ),
    };
    final hasButtons = onCopy != null || actions.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.textS.copyWith(color: c.text2)),
        Padding(
          padding: EdgeInsets.only(
            top: style == LgPasswordValue.code ? 2 : LgSpace.s1,
          ),
          child: Text(value, style: valueStyle),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(note!, style: t.textS.copyWith(color: c.text2)),
          ),
        if (hasButtons)
          Padding(
            padding: const EdgeInsets.only(top: LgSpace.s2),
            child: Wrap(
              spacing: LgSpace.s1,
              runSpacing: LgSpace.s1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (onCopy != null)
                  LgButton(
                    label: copyLabel!,
                    semanticLabel: copySemanticLabel,
                    icon: LgIcons.copy,
                    kind: LgButtonKind.primary,
                    onPressed: onCopy,
                  ),
                ...actions,
              ],
            ),
          ),
      ],
    );
  }
}
