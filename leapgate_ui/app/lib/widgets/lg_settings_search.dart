// The results of a settings search (02 §1.2.4, A-P6-设置.html ".rs-*"): in the
// place of the section content, one line per hit with "分组 › 小节" in small
// text, the name of the setting and, if it has one, its description, the words
// that matched marked. The page decides what matches and which hit is
// highlighted (Up and Down in the search box move it, Enter opens it); this
// only draws and tells which was clicked.

import 'package:flutter/material.dart';

import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';

/// One hit.
class LgSettingsSearchResult {
  const LgSettingsSearchResult({
    required this.path,
    required this.name,
    this.description,
  });

  /// "传入连接 › 访问与密码".
  final String path;

  /// The name of the setting. A hit in the options of a choice has the names of
  /// the options in [description], joined the way the page likes ("A · B · C").
  final String name;
  final String? description;
}

/// The list of hits, or [emptyText] ("未找到匹配的设置") when there are none.
class LgSettingsSearchResults extends StatefulWidget {
  const LgSettingsSearchResults({
    super.key,
    required this.results,
    required this.query,
    required this.selectedIndex,
    required this.onOpen,
    required this.emptyText,
  });

  final List<LgSettingsSearchResult> results;

  /// What was typed: its occurrences in the texts are marked, whatever their case.
  final String query;

  /// The hit the keyboard stands on; -1 for none. It is kept in view.
  final int selectedIndex;

  /// A hit was clicked or Enter was pressed on it.
  final ValueChanged<int> onOpen;
  final String emptyText;

  @override
  State<LgSettingsSearchResults> createState() =>
      _LgSettingsSearchResultsState();
}

class _LgSettingsSearchResultsState extends State<LgSettingsSearchResults> {
  final _keys = <GlobalKey>[];

  @override
  void didUpdateWidget(LgSettingsSearchResults old) {
    super.didUpdateWidget(old);
    final i = widget.selectedIndex;
    if (i == old.selectedIndex || i < 0 || i >= _keys.length) return;
    final forward = i > old.selectedIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = i < _keys.length ? _keys[i].currentContext : null;
      if (!mounted || ctx == null || Scrollable.maybeOf(ctx) == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignmentPolicy: forward
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    if (widget.results.isEmpty) {
      return Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LgSpace.s2,
            vertical: LgSpace.s5,
          ),
          child: Text(widget.emptyText, style: t.text.copyWith(color: c.text2)),
        ),
      );
    }
    while (_keys.length < widget.results.length) {
      _keys.add(GlobalKey());
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LgSpace.s2,
          vertical: LgSpace.s1,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(LgRadius.r16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, r) in widget.results.indexed) ...[
              if (i > 0) const SizedBox(height: 1),
              KeyedSubtree(
                key: _keys[i],
                child: _Hit(
                  result: r,
                  query: widget.query,
                  selected: i == widget.selectedIndex,
                  onPressed: () => widget.onOpen(i),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Hit extends StatelessWidget {
  const _Hit({
    required this.result,
    required this.query,
    required this.selected,
    required this.onPressed,
  });

  final LgSettingsSearchResult result;
  final String query;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r10);
    final desc = result.description;
    return LgPressable(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: [
        result.path,
        result.name,
        if (desc != null && desc.isNotEmpty) desc,
      ].join(', '),
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        // The hit the keyboard is on carries the accent tint; the mark inside
        // it is a little stronger, or it would vanish (`.rs-i.hv mark`).
        final base = selected
            ? Color.alphaBlend(c.active, c.surface)
            : c.surface.withValues(alpha: 0);
        final mark = selected
            ? Color.alphaBlend(c.accent.withValues(alpha: .28), c.surface)
            : c.active;
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            padding: const EdgeInsets.all(LgSpace.s2),
            decoration: BoxDecoration(
              color: overlay == null ? base : Color.alphaBlend(overlay, base),
              borderRadius: radius,
            ),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.path, style: t.textS.copyWith(color: c.text2)),
                  Text.rich(
                    TextSpan(
                      children: _marked(
                        result.name,
                        query,
                        t.text.copyWith(
                          color: c.text,
                          fontWeight: FontWeight.w700,
                        ),
                        mark,
                      ),
                    ),
                  ),
                  if (desc != null && desc.isNotEmpty)
                    Text.rich(
                      TextSpan(
                        children: _marked(
                          desc,
                          query,
                          t.textS.copyWith(color: c.text2),
                          mark,
                        ),
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

/// [text] cut at the occurrences of [query] (any case), which get [mark] behind them.
List<InlineSpan> _marked(
  String text,
  String query,
  TextStyle style,
  Color mark,
) {
  final q = query.trim();
  if (q.isEmpty) return [TextSpan(text: text, style: style)];
  final spans = <InlineSpan>[];
  final lower = text.toLowerCase();
  final needle = q.toLowerCase();
  // The lower-cased text can differ in length from the original (a few
  // letters change length); then there is no safe way to cut it, so show it plain.
  if (lower.length != text.length) {
    return [TextSpan(text: text, style: style)];
  }
  var from = 0;
  while (true) {
    final at = lower.indexOf(needle, from);
    if (at < 0) break;
    if (at > from) {
      spans.add(TextSpan(text: text.substring(from, at), style: style));
    }
    spans.add(
      TextSpan(
        text: text.substring(at, at + needle.length),
        style: style.copyWith(backgroundColor: mark),
      ),
    );
    from = at + needle.length;
  }
  if (from < text.length) {
    spans.add(TextSpan(text: text.substring(from), style: style));
  }
  return spans.isEmpty ? [TextSpan(text: text, style: style)] : spans;
}
