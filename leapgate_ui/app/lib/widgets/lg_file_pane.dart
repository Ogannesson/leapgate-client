// One pane of the file transfer view (02 §2.2 blocks B to F and G; `.col`, `.ch`, `.nv`, `.op`,
// `.sr`, `.es`, `.drop` in A-P7-文件传输.html): the frame, the header that names the device, the
// navigation row, the row of actions with the folder search, the status line, the dimmed "reading"
// state of the list and the highlights of a drag. The path (breadcrumb) is `lg_breadcrumb.dart`,
// the list `lg_file_list.dart`. The parts only draw: text comes from the caller.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_device.dart';
import 'lg_pressable.dart';
import 'lg_status.dart';
import 'lg_text_field.dart';
import 'lg_tooltip.dart';

/// The ground of a pane: the surface colour, 16 px corners, nothing may spill out of them.
class LgFilePaneFrame extends StatelessWidget {
  const LgFilePaneFrame({super.key, required this.child, this.semanticLabel});

  final Widget child;

  /// "本机" / "远程设备": the pane is a group of its own for a screen reader.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(LgRadius.r16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(LgRadius.r16),
          child: child,
        ),
      ),
    );
  }
}

/// The line that says which device the pane shows (`.ch`): the platform tile, the title in bold
/// ("本机", "远程设备") and the device after it in the quieter text. The remote device's tile is on
/// its identity colour (the same as its card, 01 §2.4), the local one on a neutral ground. While
/// the remote platform is not known ([platform] null) the tile is left out and nothing turns.
/// With [compact] the line is the navigation height instead of the input height (the smallest
/// window, `.frame.mn .ch`); the page passes it by the height of the window.
class LgFilePaneHeader extends StatelessWidget {
  const LgFilePaneHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.platform,
    this.remoteId,
    this.compact = false,
  });

  final String title;

  /// The host name for the local pane; the device's name and platform for the remote one.
  final String subtitle;
  final LgPlatform? platform;

  /// The remote device's ID, which gives the tile its identity colour; null draws the neutral
  /// tile of the local pane.
  final String? remoteId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final platform = this.platform;
    return Container(
      height: compact ? math.min(t.sizes.main, t.sizes.nav) : t.sizes.main,
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
      child: Row(
        children: [
          if (platform != null) ...[
            remoteId == null
                ? Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(LgRadius.r10),
                    ),
                    child: LgIcon(
                      lgPlatformIcon(platform),
                      size: 20,
                      color: c.text2,
                    ),
                  )
                : LgDeviceAvatar(id: remoteId!, platform: platform, size: 28),
            const SizedBox(width: LgSpace.s3),
          ],
          Text(
            title,
            style: t.text.copyWith(color: c.text, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: LgSpace.s3),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: t.text.copyWith(color: c.text2),
            ),
          ),
        ],
      ),
    );
  }
}

/// A button of the navigation row: its icon, its name and shortcut for the tooltip and the screen
/// reader ("后退（Alt+←）"), `null` [onPressed] greys it.
class LgFileNavButton {
  const LgFileNavButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final LgIcons icon;
  final String label;
  final VoidCallback? onPressed;
}

/// The navigation row (`.nv`): back, up and home, then [path] (an `LgBreadcrumb` or an
/// `LgPathInput`) taking the room, then refresh. With [compact] it is 4 px lower (the smallest
/// window, `.frame.mn .nv`); the page passes it by the height of the window.
class LgFileNavRow extends StatelessWidget {
  const LgFileNavRow({
    super.key,
    required this.back,
    required this.up,
    required this.home,
    required this.refresh,
    required this.path,
    this.compact = false,
  });

  final LgFileNavButton back;
  final LgFileNavButton up;
  final LgFileNavButton home;
  final LgFileNavButton refresh;
  final Widget path;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    Widget button(LgFileNavButton b) =>
        LgIconButton(icon: b.icon, label: b.label, onPressed: b.onPressed);
    return Container(
      height: t.sizes.button + (compact ? LgSpace.s1 : LgSpace.s2),
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
      child: Row(
        children: [
          button(back),
          const SizedBox(width: LgSpace.s1),
          button(up),
          const SizedBox(width: LgSpace.s1),
          button(home),
          const SizedBox(width: LgSpace.s1),
          Expanded(child: path),
          const SizedBox(width: LgSpace.s1),
          button(refresh),
        ],
      ),
    );
  }
}

/// The row of actions (`.op`): the [actions] (the transfer button, the list tools, the "⋯" menu)
/// from the left, the search of the folder at the right.
///
/// A pane narrower than [collapseBelow] cannot hold both: the search is then an icon, and
/// [searchOpen] says whether the field has taken the whole row. The page owns that flag: a press
/// on the icon calls [onSearchOpenChanged] with true, and the field gets the keyboard when the
/// flag comes on, however it came on (Ctrl+F sets it too); focus leaving the field calls it with
/// false, whether the field is empty or not. What was typed stays in [searchController], so the
/// icon is drawn in the accent colour while the folder is filtered, and opens on the same text.
/// In a wide pane the field is always there and [searchOpen] means nothing. The field is one
/// widget kept alive across the two layouts, so crossing the width loses no typing.
class LgFileOpRow extends StatefulWidget {
  const LgFileOpRow({
    super.key,
    required this.actions,
    required this.searchController,
    required this.searchFocusNode,
    required this.searchPlaceholder,
    required this.searchClearLabel,
    required this.searchOpenLabel,
    required this.searchOpen,
    required this.onSearchOpenChanged,
    this.searchActiveLabel,
    this.onSearchChanged,
    this.collapseBelow = 540,
    this.compact = false,
  });

  final List<Widget> actions;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  /// "搜索当前文件夹".
  final String searchPlaceholder;

  /// "清除搜索".
  final String searchClearLabel;

  /// The icon's name while collapsed ("搜索当前文件夹").
  final String searchOpenLabel;

  /// The icon's name while collapsed and the folder is filtered ("搜索当前文件夹，正在过滤");
  /// [searchOpenLabel] when null.
  final String? searchActiveLabel;

  /// A narrow pane shows the field (and hides the actions) while this is true.
  final bool searchOpen;
  final ValueChanged<bool> onSearchOpenChanged;
  final ValueChanged<String>? onSearchChanged;
  final double collapseBelow;

  /// The smallest window's row, 4 px lower (`.frame.mn .op`); the page passes it by the height
  /// of the window.
  final bool compact;

  @override
  State<LgFileOpRow> createState() => _LgFileOpRowState();
}

class _LgFileOpRowState extends State<LgFileOpRow> {
  final _fieldKey = GlobalKey();
  bool _narrow = false;

  @override
  void initState() {
    super.initState();
    widget.searchFocusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(LgFileOpRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchFocusNode != widget.searchFocusNode) {
      oldWidget.searchFocusNode.removeListener(_onFocus);
      widget.searchFocusNode.addListener(_onFocus);
    }
    if (!oldWidget.searchOpen && widget.searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.searchOpen) widget.searchFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    widget.searchFocusNode.removeListener(_onFocus);
    super.dispose();
  }

  // Focus gone from the open field gives the icon back, empty or not.
  void _onFocus() {
    if (!widget.searchFocusNode.hasFocus && _narrow && widget.searchOpen) {
      widget.onSearchOpenChanged(false);
    }
  }

  Widget _field() => ListenableBuilder(
    key: _fieldKey,
    listenable: widget.searchController,
    builder: (context, _) => LgTextField(
      controller: widget.searchController,
      focusNode: widget.searchFocusNode,
      placeholder: widget.searchPlaceholder,
      semanticLabel: widget.searchPlaceholder,
      dense: true,
      quiet: true,
      leading: LgIcon(
        LgIcons.search,
        size: 20,
        color: LgTokens.of(context).colors.text2,
      ),
      // A press on the button must not count as a press outside the field: that would take the
      // focus away, and a narrow pane would fold the field before the press ended.
      trailing: widget.searchController.text.isEmpty
          ? null
          : TextFieldTapRegion(
              child: LgIconButton(
                icon: LgIcons.x,
                label: widget.searchClearLabel,
                size: 24,
                iconSize: 16,
                focusable: false,
                onPressed: () {
                  widget.searchController.clear();
                  widget.onSearchChanged?.call('');
                  widget.searchFocusNode.requestFocus();
                },
              ),
            ),
      onChanged: widget.onSearchChanged,
    ),
  );

  Widget _icon() => ListenableBuilder(
    listenable: widget.searchController,
    builder: (context, _) {
      final filtering = widget.searchController.text.isNotEmpty;
      return _SearchIcon(
        label: filtering
            ? (widget.searchActiveLabel ?? widget.searchOpenLabel)
            : widget.searchOpenLabel,
        filtering: filtering,
        onPressed: () => widget.onSearchOpenChanged(true),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < widget.collapseBelow;
        _narrow = narrow;
        final Widget content;
        if (narrow && widget.searchOpen) {
          content = _field();
        } else {
          content = Row(
            children: [
              for (final (i, a) in widget.actions.indexed) ...[
                if (i > 0) const SizedBox(width: LgSpace.s1),
                a,
              ],
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: narrow
                      ? _icon()
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 196),
                          child: _field(),
                        ),
                ),
              ),
            ],
          );
        }
        return Container(
          height: t.sizes.button + (widget.compact ? LgSpace.s1 : LgSpace.s2),
          padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
          alignment: Alignment.centerLeft,
          child: content,
        );
      },
    );
  }
}

/// The search as an icon (a narrow pane): a button the size of the other icon buttons; in the
/// accent colour on a tint while the folder is filtered, so that a list with items missing says
/// why.
class _SearchIcon extends StatelessWidget {
  const _SearchIcon({
    required this.label,
    required this.filtering,
    required this.onPressed,
  });

  final String label;
  final bool filtering;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    const radius = BorderRadius.all(Radius.circular(LgRadius.r10));
    return LgTooltip(
      message: label,
      child: LgPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, states) => LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            width: t.sizes.button,
            height: t.sizes.button,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filtering
                  ? Color.alphaBlend(
                      lgStateOverlay(c, states) ?? Colors.transparent,
                      c.active,
                    )
                  : lgStateOverlay(c, states),
              borderRadius: radius,
            ),
            child: LgIcon(
              LgIcons.search,
              size: t.sizes.icon,
              color: filtering ? c.accent : c.text2,
            ),
          ),
        ),
      ),
    );
  }
}

/// The line at the bottom of a pane (`.sr`): "12 个项目", "已选择 2 个项目，2.48 MB". A live
/// region: a screen reader hears the count change as the selection does.
class LgFileStatusRow extends StatelessWidget {
  const LgFileStatusRow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Container(
      height: t.sizes.menuGroup,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: t.textS.copyWith(color: c.text2),
        ),
      ),
    );
  }
}

/// The list while a folder is read (`.es.ld`, `.lst.ld`): when the wait goes past the moment the
/// caller allows for (about half a second, 02 §2.2 block E) it dims what is shown, takes away
/// its clicks, and lays "正在读取…" with a turning arc over it.
///
/// The child keeps its place in the tree whatever [reading] says (a scroll position, a State in
/// the list below it must survive the wait): only the parameters of the wrappers around it
/// change, and the cover is added after it in the stack (over it).
class LgReadingOverlay extends StatelessWidget {
  const LgReadingOverlay({
    super.key,
    required this.reading,
    required this.label,
    required this.child,
  });

  final bool reading;

  /// "正在读取…".
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        IgnorePointer(
          ignoring: reading,
          child: ExcludeSemantics(
            excluding: reading,
            child: Opacity(opacity: reading ? .45 : 1, child: child),
          ),
        ),
        if (reading)
          Positioned.fill(
            child: ColoredBox(
              color: c.surface.withValues(alpha: .4),
              child: Semantics(
                liveRegion: true,
                label: label,
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.only(top: LgSpace.s8),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LgSpinner(size: 24, color: c.text),
                          const SizedBox(height: LgSpace.s3),
                          Text(label, style: t.text.copyWith(color: c.text)),
                        ],
                      ),
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

/// What a pane does with the files that are being dragged over it.
enum LgDropState {
  /// Nothing is dragged over the pane.
  none,

  /// The files can be dropped here: the pane is tinted and framed in the accent colour.
  accept,

  /// They cannot: only a dashed neutral frame, no tint (the local pane for files from the
  /// system, the pane they came from).
  reject,
}

/// The pane's highlight while files are dragged over it (`.col.drop::before`,
/// `.col.nodrop::before`, `.dmsg`): a dashed frame 8 px inside the pane, tinted when the drop is
/// accepted, with [message] ("上传到“备份”") in a card at the middle. It lies over the content and
/// lets every pointer event through.
///
/// The child keeps its place in the tree whatever [state] says (the list under the pointer must
/// keep its scroll position and its rows while files are dragged over it): the highlight is added
/// after the child in the stack (over it), and removed again, without touching it.
class LgDropZone extends StatelessWidget {
  const LgDropZone({
    super.key,
    required this.state,
    required this.child,
    this.message,
    this.messageIcon = LgIcons.upload,
  });

  final LgDropState state;
  final Widget child;

  /// The target, shown for [LgDropState.accept]: "上传到“备份”" / "下载到“文档”".
  final String? message;
  final LgIcons messageIcon;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final accept = state == LgDropState.accept;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        if (state != LgDropState.none)
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.all(LgSpace.s2),
                child: CustomPaint(
                  painter: _DashedFrame(
                    color: accept ? c.accent : c.borderStrong,
                    fill: accept ? c.active : null,
                  ),
                ),
              ),
            ),
          ),
        if (accept && message != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Semantics(
                  liveRegion: true,
                  label: message,
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LgSpace.s5,
                        vertical: LgSpace.s3,
                      ),
                      decoration: BoxDecoration(
                        color: c.float,
                        borderRadius: BorderRadius.circular(LgRadius.r16),
                        boxShadow: c.shadow,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LgIcon(messageIcon, size: 24, color: c.accent),
                          const SizedBox(width: LgSpace.s3),
                          Text(
                            message!,
                            style: t.textN.copyWith(
                              color: c.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
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

class _DashedFrame extends CustomPainter {
  _DashedFrame({required this.color, this.fill});

  final Color color;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(1),
      const Radius.circular(LgRadius.r12),
    );
    if (fill != null) canvas.drawRRect(rrect, Paint()..color = fill!);
    final path = Path()..addRRect(rrect);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // `border: 2px dashed`: dashes and gaps of about two line widths, six and four here as
    // Chrome lays them.
    for (final metric in path.computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        canvas.drawPath(
          metric.extractPath(at, math.min(at + 6, metric.length)),
          line,
        );
        at += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame old) =>
      old.color != color || old.fill != fill;
}

/// The small label that follows the pointer while files are dragged (`.dchip`): a file icon, a
/// text and the number of items. The text is the name of the first one, or the target when the
/// pointer is over a folder row ("上传到“照片”"). With [rejected] a red "not allowed" circle
/// stands on its corner.
class LgDragChip extends StatelessWidget {
  const LgDragChip({
    super.key,
    required this.label,
    required this.count,
    this.rejected = false,
  });

  final String label;
  final int count;
  final bool rejected;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LgSpace.s3,
        vertical: LgSpace.s1,
      ),
      decoration: BoxDecoration(
        color: c.float,
        borderRadius: BorderRadius.circular(LgRadius.r10),
        boxShadow: c.shadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LgIcon(LgIcons.file, size: 18, color: c.text),
          const SizedBox(width: LgSpace.s2),
          Text(label, style: t.textM.copyWith(color: c.text)),
          if (count > 1) ...[const SizedBox(width: LgSpace.s2), LgBadge(count)],
        ],
      ),
    );
    return ExcludeSemantics(
      child: rejected
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                chip,
                Positioned(
                  left: -14,
                  top: -6,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: c.float,
                      shape: BoxShape.circle,
                      boxShadow: c.shadow,
                    ),
                    child: LgIcon(LgIcons.ban, size: 22, color: c.error),
                  ),
                ),
              ],
            )
          : chip,
    );
  }
}
