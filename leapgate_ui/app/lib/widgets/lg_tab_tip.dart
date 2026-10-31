// Content of the hover tip of a session tab (01 §2.1; `.tip` in A-P2.html):
// the full name, the ID and either one line per open view with its connection
// method, or the reason the tab shows a problem. Give it to
// `LgSessionTab.tooltip`; `LgTooltip` draws the box around it.

import 'package:flutter/material.dart';

import '../theme/lg_tokens.dart';

class LgTabTip extends StatelessWidget {
  const LgTabTip({
    super.key,
    required this.name,
    required this.id,
    this.views = const [],
    this.lines = const [],
  });

  final String name;

  /// Formatted ID.
  final String id;

  /// A row per open view: its name ("远程桌面") and its connection method (an
  /// `LgRouteMark`).
  final List<(String, Widget)> views;

  /// Plain lines of text: the reason of an error, the time to the next try.
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: t.text.copyWith(color: c.text, fontWeight: FontWeight.w700),
        ),
        Text(id, style: t.textS.copyWith(color: c.text2)),
        if (lines.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: LgSpace.s2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in lines)
                  Text(line, style: t.textS.copyWith(color: c.text)),
              ],
            ),
          ),
        for (final (view, mark) in views)
          Padding(
            padding: const EdgeInsets.only(top: LgSpace.s1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 64,
                  child: Text(view, style: t.textS.copyWith(color: c.text2)),
                ),
                const SizedBox(width: LgSpace.s4),
                DefaultTextStyle(style: t.textS, child: mark),
              ],
            ),
          ),
      ],
    );
  }
}
