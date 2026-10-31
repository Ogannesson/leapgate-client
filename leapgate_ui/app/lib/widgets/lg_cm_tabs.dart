// The tab strip of the connection manager (CM): one tab per incoming
// connection, with the session type icon, the visitor's name and the unread
// count (01 §3.3; `.cm-tabs` in A-P3.html).
//
// Components only draw: names, ID text and hints come from the caller.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_cm_frame.dart' show kLgCmTabInset;
import 'lg_pressable.dart';
import 'lg_status.dart';
import 'lg_tooltip.dart';

/// What the visitor does on one connection. One person with a remote desktop
/// and a file transfer open is two connections, so two tabs.
enum LgCmKind { remote, file, port, exit, terminal, camera }

LgIcons lgCmKindIcon(LgCmKind kind) => switch (kind) {
  LgCmKind.remote => LgIcons.monitor,
  LgCmKind.file => LgIcons.folder,
  LgCmKind.port => LgIcons.forward,
  LgCmKind.exit => LgIcons.exit,
  LgCmKind.terminal => LgIcons.terminal,
  LgCmKind.camera => LgIcons.camera,
};

/// One tab. [identity] is the group (0..6) of the visitor's device ID, the one
/// `identityGroup()` gives: the colour of the strip on the tab's top edge.
class LgCmTab {
  const LgCmTab({
    required this.kind,
    required this.name,
    required this.identity,
    this.unread = 0,
    this.gone = false,
    this.tooltip,
    this.semanticLabel,
  });

  final LgCmKind kind;
  final String name;
  final int identity;

  /// Unread chat messages; the count is drawn when above zero.
  final int unread;

  /// The visitor has left: the name is greyed (the header says "已断开").
  final bool gone;

  /// Shown on hover: the connection number (01 §3.3).
  final String? tooltip;

  /// The accessible name when it must say more than the name ("李四，远程桌面").
  final String? semanticLabel;
}

const double _tabHeight = 32;
const double _maxTabName = 120;

/// The tabs of the visitors, bottom aligned in the 36 px strip below the title
/// row. The selected tab has the ground of the header it sits on, so the two
/// read as one. Tabs that do not fit scroll sideways; selecting one brings it
/// into view. The empty part of the strip passes the pointer on (dragging the
/// window).
class LgCmTabStrip extends StatefulWidget {
  const LgCmTabStrip({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<LgCmTab> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  State<LgCmTabStrip> createState() => _LgCmTabStripState();
}

class _LgCmTabStripState extends State<LgCmTabStrip> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(LgCmTabStrip old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected ||
        old.tabs.length != widget.tabs.length) {
      _reveal();
    }
  }

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(ctx);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: kLgCmTabInset),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, tab) in widget.tabs.indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              _CmTab(
                key: i == widget.selected ? _selectedKey : null,
                tab: tab,
                selected: i == widget.selected,
                onSelect: () => widget.onSelect(i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CmTab extends StatelessWidget {
  const _CmTab({
    super.key,
    required this.tab,
    required this.selected,
    required this.onSelect,
  });

  final LgCmTab tab;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    const radius = BorderRadius.vertical(top: Radius.circular(LgRadius.r10));
    final strip = c.identity[tab.identity % c.identity.length].solid;
    final fg = tab.gone ? c.offline : (selected ? c.text : c.text2);
    final built = LgPressable(
      onPressed: onSelect,
      selected: selected,
      semanticLabel: tab.semanticLabel ?? tab.name,
      builder: (context, states) {
        final overlay = selected ? null : lgStateOverlay(c, states);
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          inset: true,
          child: Stack(
            children: [
              Container(
                height: _tabHeight,
                padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
                decoration: BoxDecoration(
                  color: selected ? c.cmBand : overlay,
                  borderRadius: radius,
                ),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LgIcon(lgCmKindIcon(tab.kind), size: 20, color: fg),
                      const SizedBox(width: LgSpace.s2),
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _maxTabName,
                        ),
                        child: Text(
                          tab.name,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: t.text.copyWith(
                            color: fg,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (tab.unread > 0) ...[
                        // `.tab` gap 8 plus the badge's own 4.
                        const SizedBox(width: LgSpace.s3),
                        LgBadge(tab.unread),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                left: LgSpace.s3,
                right: LgSpace.s3,
                top: 0,
                height: LgFixed.strip,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: strip,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    return tab.tooltip == null
        ? built
        : LgTooltip(message: tab.tooltip, child: built);
  }
}
