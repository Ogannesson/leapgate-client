// The window of the connection manager (CM): title row, tab strip, the main
// panel and a side panel that opens to the left (01 §3.3; `.cm-title`,
// `.cm-panel`, `.cm-side` in A-P3.html).
//
// The components only draw. The window itself (size, position, always on top,
// moving) belongs to the page: the frame asks for a drag with [onStartDrag] and
// fills whatever size it is given.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';

/// The size the mockup draws the window at: 320 × 500 with one column, 700 × 500
/// with the side panel open.
const double kLgCmWidth = 320;
const double kLgCmHeight = 500;
const double kLgCmSideWidth = 380;
const double kLgCmExpandedWidth = kLgCmSideWidth + kLgCmWidth;

/// What the window actually draws in: its 320 includes the invisible resize
/// border Windows keeps at both sides, so the client area is 309 wide at 150 %
/// (measured in the M3 acceptance); 304 is the narrowest taken for the other
/// scales, which were not measured. The two-column
/// permission grid has to fit "文件复制粘贴" and "阻止本地输入" on one line at
/// this width, not at the mockup's 320.
const double kLgCmNarrowestClient = 304;

const double _rowHeight = 36;

/// Space left of the first tab and of the side panel's tab, so that they sit
/// above the flat part of the panel's rounded corner.
const double kLgCmTabInset = 28;

/// The window: ground colour, a drag area over the title row and the tab strip,
/// then the columns. [overlay] covers the whole window (the close
/// confirmation).
class LgCmFrame extends StatelessWidget {
  const LgCmFrame({
    super.key,
    required this.title,
    required this.collapseLabel,
    required this.closeLabel,
    required this.onCollapse,
    required this.onClose,
    required this.tabs,
    required this.panel,
    this.side,
    this.overlay,
    this.onStartDrag,
    this.sideFocusOnly = false,
  });

  /// "Leapgate".
  final String title;
  final String collapseLabel;
  final String closeLabel;

  /// "收起": shrinks the window to the edge strip (not minimise).
  final VoidCallback onCollapse;
  final VoidCallback onClose;

  /// An [LgCmTabStrip].
  final Widget tabs;

  /// An [LgCmPanel].
  final Widget panel;

  /// An [LgCmSidePanel]; it takes [kLgCmSideWidth] on the left and the window
  /// must be [kLgCmExpandedWidth] wide.
  final Widget? side;
  final Widget? overlay;

  /// A pointer went down on the title row or the empty part of the strip and
  /// moved: start moving the window.
  final VoidCallback? onStartDrag;

  /// Nothing but [side] takes the keyboard focus: the remote user's keyboard cannot reach the
  /// buttons, while the chat input can still be typed in (01 §3.3).
  final bool sideFocusOnly;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    Widget noFocus(Widget child) =>
        ExcludeFocus(excluding: sideFocusOnly, child: child);
    return DefaultTextStyle(
      style: t.text.copyWith(color: c.text),
      child: ColoredBox(
        color: c.bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (onStartDrag != null)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: _rowHeight * 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => onStartDrag!(),
                ),
              ),
            Column(
              children: [
                SizedBox(
                  height: _rowHeight,
                  child: noFocus(
                    _TitleRow(
                      title: title,
                      collapseLabel: collapseLabel,
                      closeLabel: closeLabel,
                      onCollapse: onCollapse,
                      onClose: onClose,
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (side != null)
                        SizedBox(width: kLgCmSideWidth, child: side),
                      Expanded(
                        child: Column(
                          children: [
                            SizedBox(height: _rowHeight, child: noFocus(tabs)),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  LgSpace.s2,
                                  0,
                                  LgSpace.s2,
                                  LgSpace.s2,
                                ),
                                child: noFocus(panel),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (overlay != null) noFocus(overlay!),
          ],
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.title,
    required this.collapseLabel,
    required this.closeLabel,
    required this.onCollapse,
    required this.onClose,
  });

  final String title;
  final String collapseLabel;
  final String closeLabel;
  final VoidCallback onCollapse;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Padding(
      padding: const EdgeInsets.only(left: LgSpace.s3, right: LgSpace.s1),
      child: Row(
        children: [
          // Placeholder app mark, as in the main window's title bar. The mark
          // and the title take no pointer: pressing them drags the window.
          IgnorePointer(
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: c.borderStrong,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: LgSpace.s2),
          Expanded(
            child: IgnorePointer(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textS.copyWith(
                  color: c.text2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          LgIconButton(
            icon: LgIcons.dockTop,
            label: collapseLabel,
            size: 32,
            insetFocusRing: true,
            onPressed: onCollapse,
          ),
          LgIconButton(
            icon: LgIcons.x,
            label: closeLabel,
            size: 32,
            insetFocusRing: true,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// The white panel under the tabs: [header] over the full width, then [body]
/// (the permissions, the note of an exit session) and [actions] pinned to the
/// bottom. The body scrolls when a language needs more room than the window
/// has; the actions never scroll away.
class LgCmPanel extends StatelessWidget {
  const LgCmPanel({super.key, required this.header, this.body, this.actions});

  final Widget header;
  final Widget? body;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(LgRadius.r20),
      child: ColoredBox(
        color: c.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: LgSpace.s2),
            Expanded(
              child: body == null
                  ? const SizedBox.shrink()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LgSpace.s4,
                      ),
                      child: body,
                    ),
            ),
            if (actions != null)
              // The mockup's panel ends 10 px under the last button.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  LgSpace.s4,
                  0,
                  LgSpace.s4,
                  10,
                ),
                child: actions,
              ),
          ],
        ),
      ),
    );
  }
}

/// The panel that opens to the left of the main panel (file records, chat):
/// its own tab over [child], on the same line as the visitor tabs.
class LgCmSidePanel extends StatelessWidget {
  const LgCmSidePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  final LgIcons icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    const tabRadius = BorderRadius.vertical(top: Radius.circular(LgRadius.r10));
    return Column(
      children: [
        SizedBox(
          height: _rowHeight,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: kLgCmTabInset),
              child: Semantics(
                header: true,
                label: title,
                child: ExcludeSemantics(
                  child: Stack(
                    children: [
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(
                          horizontal: LgSpace.s3,
                        ),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: tabRadius,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LgIcon(icon, size: 20, color: c.text),
                            const SizedBox(width: LgSpace.s2),
                            Text(
                              title,
                              style: t.text.copyWith(
                                color: c.text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: LgSpace.s3,
                        right: LgSpace.s3,
                        top: 0,
                        height: LgFixed.strip,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(
              left: LgSpace.s2,
              bottom: LgSpace.s2,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(LgRadius.r20),
              child: ColoredBox(
                color: c.surface,
                child: SizedBox.expand(child: child),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
