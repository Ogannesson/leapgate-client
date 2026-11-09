// A section of a page with its own head (`.pgsec`, `.sech`, `.sechl` of
// `A-P8-隧道.html`): the page title is level one, this is level two, and the
// small titles inside it ([LgExitSection] with `LgExitSectionLevel.sub`) are
// level three. The "出口与隧道" page has two: "出口" and "隧道".
//
// It only draws: the texts come from the caller (localised).

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';

/// The head of a section, then [children]: an icon in the accent colour, the
/// [title] in bold at the number size, and under it one sentence of [lede] in
/// the second colour.
///
/// A section that is not [first] stands apart from the one above: 48 px under
/// it, a 1.5 px line, 24 px more. The first one has neither and is 16 px from
/// what is above it: with the 4 px the home page leaves under its own title that
/// makes the mockup's 20.
class LgPageSection extends StatelessWidget {
  const LgPageSection({
    super.key,
    required this.title,
    this.icon,
    this.lede,
    this.first = false,
    this.children = const [],
  });

  final String title;
  final LgIcons? icon;

  /// "将本机端口转发到远程设备或其所在网络中的地址。"
  final String? lede;
  final bool first;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              LgIcon(icon!, size: 20, color: c.accent),
              const SizedBox(width: LgSpace.s2),
            ],
            Expanded(
              child: Semantics(
                header: true,
                headingLevel: 2,
                child: Text(
                  title,
                  style: t.textN.copyWith(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (lede != null)
          Padding(
            padding: const EdgeInsets.only(top: LgSpace.s1),
            child: Text(lede!, style: t.textM.copyWith(color: c.text2)),
          ),
        ...children,
      ],
    );
    if (first) {
      return Padding(
        padding: const EdgeInsets.only(top: LgSpace.s5 - LgSpace.s1),
        child: head,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: LgSpace.s8),
      // A Container: the border's 1.5 px come on top of the 24, as in the mockup.
      child: Container(
        padding: const EdgeInsets.only(top: LgSpace.s6),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.border, width: 1.5)),
        ),
        child: head,
      ),
    );
  }
}
