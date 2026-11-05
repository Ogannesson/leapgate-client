// The path of a file pane (02 §2.2 block C; `.bc`, `.cr`, `.perr` in A-P7-文件传输.html): the
// breadcrumb that shows the folders from the root to the one that is open, and the path input it
// turns into when the user clicks past the last folder or presses Ctrl+L.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_menu.dart';
import 'lg_pressable.dart';
import 'lg_text_field.dart';
import 'lg_tooltip.dart';

/// The folders from the root to the open one. Every one but the last can be clicked; the root has
/// a drop-down of its own ("此电脑" lists the drives). When the row is too narrow the middle ones
/// fold into "…", whose tooltip lists them, and the root, the first folder (the drive) and the
/// last ones stay in view (02 §2.2 block C). Narrower still, the drive folds too; narrower than
/// that the root keeps only [rootIcon] and its arrow (its name goes into the tooltip, the name
/// a screen reader reads stays), and then the "…" goes as well, the open folder's tooltip
/// listing the whole path; the open folder is cut with "…" to the room that is left. Nothing
/// overflows at any width. A click on the empty part of the row is [onEdit]: the caller swaps in
/// an [LgPathInput].
class LgBreadcrumb extends StatelessWidget {
  const LgBreadcrumb({
    super.key,
    required this.rootLabel,
    required this.rootTip,
    required this.segments,
    required this.onRoot,
    required this.onSegment,
    required this.onEdit,
    this.rootMenu = const [],
    this.separatorLabel = '›',
    this.rootIcon = LgIcons.monitor,
    this.editLabel,
  });

  /// "此电脑" on Windows, "/" elsewhere.
  final String rootLabel;

  /// The drop-down button's name and tooltip: "此电脑", or "根文件夹" on the other systems.
  final String rootTip;

  /// The folders below the root: "C:", "Users", "zhangsan", "Documents".
  final List<String> segments;
  final VoidCallback onRoot;

  /// Called with the index in [segments]; never for the last one.
  final ValueChanged<int> onSegment;
  final VoidCallback onEdit;

  /// The rows of the root's drop-down: the drives (an `LgMenuItem` each, the open one checked), or
  /// an `LgMenuLoadingRow` while the remote device's drives are read. Empty draws no arrow.
  final List<Widget> rootMenu;

  /// What joins the folders in the tooltip of the "…".
  final String separatorLabel;

  /// What the root is drawn as when the row has no room for its name.
  final LgIcons rootIcon;

  /// "编辑路径": with it the empty part of the row is a button of its own to a screen reader (a
  /// press on it is [onEdit], as it is for the pointer). Without it the row reads as it did.
  final String? editLabel;

  static const double _crumbPad = LgSpace.s2;
  static const double _gap = LgSpace.s1;
  static const double _chevron = 14;

  /// How far over its room the row may be before one more folder is folded: the last folder
  /// gives way with "…", and a name a pixel short of fitting should not cost a folder.
  static const double _tolerance = 4;

  /// The least room the open folder is left before the drive is folded as well; a longer name
  /// ends in "…" and shows whole in its tooltip.
  static const double _minLast = 48;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final style = t.textM;
    final bold = style.copyWith(fontWeight: FontWeight.w700);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // With a name of its own the empty part is a node by itself, the row is not one too.
        excludeFromSemantics: editLabel != null,
        onTap: onEdit,
        child: Container(
          height: t.sizes.button,
          padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(LgRadius.r10),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              double width(String s, TextStyle st) {
                final p = TextPainter(
                  text: TextSpan(text: s, style: st),
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                )..layout();
                final w = p.width;
                p.dispose();
                return w;
              }

              // The root chip: padding, the name, and with a menu the gap and the arrow; or the
              // icon in the name's place.
              final arrow = rootMenu.isEmpty ? 0.0 : _gap + _chevron;
              final rootFull = width(rootLabel, style) + _crumbPad * 2 + arrow;
              final rootIconWidth = t.sizes.icon + _crumbPad * 2 + arrow;
              final n = segments.length;
              // The folded folders are `from..to`, none when `to < from`. The first folder (the
              // drive) stays until the middle ones are all folded and it still does not fit.
              // Widths of everything that stays: the root, then a separator and a folder for
              // each one kept; the "…" and its separator when some are folded ([dots]).
              double total(double rootWidth, int from, int to, bool dots) {
                var w = rootWidth;
                for (var i = 0; i < n; i++) {
                  if (i >= from && i <= to) continue;
                  w +=
                      _gap +
                      _chevron +
                      _gap +
                      width(segments[i], i == n - 1 ? bold : style) +
                      _crumbPad * 2;
                }
                if (dots && to >= from) {
                  w +=
                      _gap +
                      _chevron +
                      _gap +
                      width('…', style) +
                      _crumbPad * 2;
                }
                return w;
              }

              // With every middle folder folded the last may still give up room, down to
              // [_minLast], before the drive is folded too.
              final lastWidth = n == 0
                  ? 0.0
                  : width(segments[n - 1], bold) + _crumbPad * 2;
              bool fits(double rootWidth, int from, int to, bool dots) {
                var w = total(rootWidth, from, to, dots);
                if (to >= n - 2) {
                  w -= (lastWidth - _minLast).clamp(0.0, lastWidth);
                }
                return w <= constraints.maxWidth + _tolerance;
              }

              var from = 1;
              var to = 0;
              while (!fits(rootFull, from, to, true)) {
                if (to < n - 2) {
                  to++;
                } else if (from == 1 && n >= 2) {
                  from = 0;
                } else {
                  break;
                }
              }
              // Nothing is left to fold and it is still too wide: the root gives up its name,
              // then the "…" goes (the open folder's tooltip carries the path instead).
              var rootAsIcon = false;
              var dots = true;
              if (!fits(rootFull, from, to, true)) {
                rootAsIcon = true;
                dots = fits(rootIconWidth, from, to, true);
              }
              final hidden = to >= from;
              // What cannot give way is the root, the separators and the padding of the last
              // folder; when even that is wider than the row the row is clipped, not overflowed.
              final rowWidth = total(
                rootAsIcon ? rootIconWidth : rootFull,
                from,
                to,
                dots,
              );
              final clip =
                  rowWidth - (n == 0 ? 0 : lastWidth - _crumbPad * 2) >
                  constraints.maxWidth;
              final children = <Widget>[
                _Root(
                  label: rootLabel,
                  tip: rootTip,
                  menu: rootMenu,
                  onPressed: onRoot,
                  icon: rootAsIcon ? rootIcon : null,
                ),
              ];
              void add(Widget w) {
                children
                  ..add(const SizedBox(width: _gap))
                  ..add(LgIcon(LgIcons.chevR, size: _chevron, color: c.text2))
                  ..add(const SizedBox(width: _gap))
                  ..add(w);
              }

              for (var i = 0; i < n; i++) {
                if (dots && hidden && i == from) {
                  add(
                    _Folded(
                      tip: [
                        for (var k = from; k <= to; k++) segments[k],
                      ].join(' $separatorLabel '),
                    ),
                  );
                }
                if (i >= from && i <= to) continue;
                final last = i == n - 1;
                final current = _Current(
                  segments[i],
                  pathTip: last && hidden && !dots
                      ? [rootLabel, ...segments].join(' $separatorLabel ')
                      : null,
                );
                add(
                  last
                      ? (clip ? current : Flexible(child: current))
                      : _Crumb(
                          label: segments[i],
                          onPressed: () => onSegment(i),
                        ),
                );
              }
              // Only the last folder gives way when nothing is folded any more.
              final row = clip
                  ? ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        minWidth: 0,
                        maxWidth: double.infinity,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: children,
                        ),
                      ),
                    )
                  : Row(children: children);
              if (editLabel == null) return row;
              return Stack(
                fit: StackFit.passthrough,
                children: [
                  Positioned.fill(
                    child: Semantics(
                      button: true,
                      label: editLabel,
                      onTap: onEdit,
                      excludeSemantics: true,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  row,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

const _crumbRadius = BorderRadius.all(Radius.circular(LgRadius.r6));

class _Root extends StatelessWidget {
  const _Root({
    required this.label,
    required this.tip,
    required this.menu,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final String tip;
  final List<Widget> menu;
  final VoidCallback onPressed;

  /// Drawn in the name's place when the row has no room for the name; the name is then the
  /// tooltip, and still the name a screen reader reads.
  final LgIcons? icon;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    // One chip in the mockup: 8, the name, 4, the arrow, 8. The name takes the left 8 and the
    // arrow button the rest.
    final name = _Crumb(
      label: label,
      onPressed: onPressed,
      icon: icon,
      padding: EdgeInsets.only(
        left: LgSpace.s2,
        right: menu.isEmpty ? LgSpace.s2 : 0,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon == null ? name : LgTooltip(message: label, child: name),
        if (menu.isNotEmpty)
          LgMenuAnchor(
            items: menu,
            width: 216,
            builder: (context, controller) => LgTooltip(
              message: tip,
              child: LgPressable(
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                semanticLabel: tip,
                expanded: controller.isOpen,
                builder: (context, states) => LgFocusRing(
                  show: states.contains(WidgetState.focused),
                  radius: _crumbRadius,
                  child: Container(
                    height: t.sizes.button - LgSpace.s2,
                    padding: const EdgeInsets.only(
                      left: LgSpace.s1,
                      right: LgSpace.s2,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: controller.isOpen
                          ? c.hover
                          : lgStateOverlay(c, states),
                      borderRadius: _crumbRadius,
                    ),
                    child: LgIcon(LgIcons.chevD, size: 14, color: c.text),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: LgSpace.s2),
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final EdgeInsets padding;

  /// Drawn instead of the label (which stays the name for a screen reader).
  final LgIcons? icon;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return LgPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, states) => LgFocusRing(
        show: states.contains(WidgetState.focused),
        radius: _crumbRadius,
        child: Container(
          height: t.sizes.button - LgSpace.s2,
          padding: padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: lgStateOverlay(c, states),
            borderRadius: _crumbRadius,
          ),
          child: ExcludeSemantics(
            child: icon != null
                ? LgIcon(icon!, size: t.sizes.icon, color: c.text)
                : Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: t.textM.copyWith(color: c.text),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The folder that is open: bold, not a button, and the one that is cut with "…" when the row is
/// too narrow for even the root and the drive and it.
class _Current extends StatelessWidget {
  const _Current(this.label, {this.pathTip});

  final String label;

  /// The whole path, when the folders before this one are not shown at all: the tooltip lists
  /// them (the name of this one is cut to what is left, and is in the path too).
  final String? pathTip;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final style = t.textM.copyWith(
      color: t.colors.text,
      fontWeight: FontWeight.w700,
    );
    return Container(
      height: t.sizes.button - LgSpace.s2,
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
      alignment: Alignment.centerLeft,
      child: pathTip == null
          ? LgEllipsisText(label, style: style)
          : Semantics(
              label: label,
              excludeSemantics: true,
              child: LgTooltip(
                message: pathTip!,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ),
    );
  }
}

class _Folded extends StatelessWidget {
  const _Folded({required this.tip});

  final String tip;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    // It answers the pointer's hover with the tooltip and nothing else: a press on it is its
    // own, so that it does not fall through to the row behind it, which would turn into the
    // path input.
    return LgTooltip(
      message: tip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Only there to take the press: a screen reader must not find a button that does nothing.
        excludeFromSemantics: true,
        onTap: () {},
        child: Container(
          height: t.sizes.button - LgSpace.s2,
          padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
          alignment: Alignment.center,
          child: Text('…', style: t.textM.copyWith(color: c.text)),
        ),
      ),
    );
  }
}

/// The path as text (`.bc.inp`): the whole path in a field that has the keyboard, Enter opens it,
/// Esc gives the breadcrumb back. A path that cannot be opened keeps the field and puts
/// [errorText] in a small card under it, which floats over the row below ("未找到“D:\备份\2025”。").
/// The caller selects all of the text when it swaps the field in.
class LgPathInput extends StatefulWidget {
  const LgPathInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.semanticLabel,
    required this.onSubmitted,
    required this.onCancel,
    this.errorText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// "路径".
  final String semanticLabel;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCancel;
  final String? errorText;

  @override
  State<LgPathInput> createState() => _LgPathInputState();
}

class _LgPathInputState extends State<LgPathInput> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(LgPathInput old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!mounted) return;
    if (widget.errorText != null && !_portal.isShowing) _portal.show();
    if (widget.errorText == null && _portal.isShowing) _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(LgSpace.s2, LgSpace.s1),
            child: Align(
              alignment: Alignment.topLeft,
              child: LgPathError(widget.errorText ?? ''),
            ),
          ),
          child: LgTextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            semanticLabel: widget.semanticLabel,
            dense: true,
            quiet: true,
            errorText: widget.errorText,
            // The card below says it; the field's name carries it for a screen reader.
            showErrorText: false,
            onSubmitted: widget.onSubmitted,
          ),
        ),
      ),
    );
  }
}

/// The small card under the path input (`.perr`): the error icon and the text in bold, on the
/// floating ground with its shadow. [LgPathInput] floats it itself; it is public so that the
/// gallery can show it in place.
class LgPathError extends StatelessWidget {
  const LgPathError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Container(
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
              LgIcon(LgIcons.err, size: 16, color: c.error),
              const SizedBox(width: LgSpace.s2),
              Text(
                text,
                style: t.textS.copyWith(
                  color: c.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
