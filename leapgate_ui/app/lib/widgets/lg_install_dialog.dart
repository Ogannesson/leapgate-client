// The install page (13 §4, `A-P11-安装.html`): the dialog "安装 Leapgate" on the home tab and the
// parts it is made of: the read-only install location with "修改", the options with a line of
// explanation, the licence line, and the banners for what the install will do and what went
// wrong. The local notice card's button (the shield on "升级") is `LgLocalNotice.actionIcon`.
//
// Only draws: the texts are the caller's (localised), so are the paths, the state of the
// location checks and the callbacks (`LEAPGATE.md` §10.8, §10.18).

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_banner.dart';
import 'lg_button.dart';
import 'lg_default_enter.dart';
import 'lg_feedback.dart';
import 'lg_pressable.dart';
import 'lg_tooltip.dart';

/// The mark of the location row: nothing wrong, a warning that does not stop the install (the
/// folder is not empty), or an error that does (`.pbox.wn`, `.pbox.err`).
enum LgPathTone { normal, warning, error }

/// The install dialog (`.sheet.inst`): the head, the middle that scrolls when the window is low,
/// and the buttons, which stay in view. 480 wide; 32 px at the sides, 24 above and below.
///
/// Put it in `LgDialogScrim(scrollable: false, …)` so that it gets the height of the area to keep
/// within (the scrim only dims the home tab). The middle is built from the slots in the order of
/// the mockup, with the gaps of the mockup: [pathRow], [options], [license], [banners]. A slot
/// that is null or empty leaves its gap out.
///
/// [actions] are the buttons from the left: the way out and the answer. Mark the answer
/// [LgDialogAction.isDefault] (it takes the keyboard when the dialog opens and runs on Enter);
/// give it [LgDialogAction.icon] `LgIcons.uac` with `iconSize: 18` since it asks for administrator
/// permission, and [LgDialogAction.busy] while the install runs.
///
/// [scrollController] lets the caller bring the end into view when a banner appears (a failure
/// is added under the options and must be seen): `animateTo(maxScrollExtent)`.
class LgInstallDialog extends StatelessWidget {
  const LgInstallDialog({
    super.key,
    required this.title,
    required this.actions,
    this.icon = LgIcons.download,
    this.pathRow,
    this.options = const [],
    this.license,
    this.banners = const [],
    this.width = 480,
    this.scrollController,
  });

  /// "安装 Leapgate". Also names the dialog for a screen reader.
  final String title;
  final LgIcons icon;
  final List<LgDialogAction> actions;

  /// An [LgInstallPathRow].
  final Widget? pathRow;

  /// [LgOptionCheck]s.
  final List<Widget> options;

  /// An [LgLicenseLine].
  final Widget? license;

  /// [LgBanner]s (`slim`, `textM`); see [LgInstallBanner].
  final List<Widget> banners;
  final double width;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final defaultAction = actions
        .where((a) => a.isDefault && a.onPressed != null && !a.busy)
        .firstOrNull;
    final body = <Widget>[
      if (pathRow != null) pathRow!,
      if (options.isNotEmpty) ...[
        SizedBox(height: pathRow == null ? 0 : LgSpace.s5),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: options,
        ),
      ],
      if (license != null) ...[const SizedBox(height: LgSpace.s4), license!],
      for (final b in banners) ...[const SizedBox(height: LgSpace.s4), b],
    ];
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: LgDefaultEnter(
        onEnter: defaultAction?.onPressed,
        child: FocusScope(
          autofocus: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Container(
              // 16 here and 16 inside the scrolling part: the part that scrolls reaches 16 px
              // beyond the text so that a focus ring is not cut off at its sides.
              padding: const EdgeInsets.fromLTRB(
                LgSpace.s4,
                LgSpace.s6,
                LgSpace.s4,
                LgSpace.s6,
              ),
              decoration: BoxDecoration(
                color: c.float,
                borderRadius: BorderRadius.circular(LgRadius.r20),
                boxShadow: c.shadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.bg,
                            borderRadius: BorderRadius.circular(LgRadius.r12),
                          ),
                          child: LgIcon(icon, size: 24, color: c.text2),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              title,
                              style: LgTokens.style(
                                20,
                                28,
                                FontWeight.w700,
                              ).copyWith(color: c.text),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: _ThinScroll(
                      controller: scrollController,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          LgSpace.s4,
                          LgSpace.s4,
                          LgSpace.s4,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: body,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      LgSpace.s4,
                      LgSpace.s5,
                      LgSpace.s4,
                      0,
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: LgSpace.s3,
                      runSpacing: LgSpace.s3,
                      children: [
                        for (final a in actions)
                          LgButton(
                            label: a.label,
                            semanticLabel: a.semanticLabel,
                            kind: a.kind,
                            busy: a.busy,
                            icon: a.icon,
                            iconSize: a.iconSize,
                            autofocus: a == defaultAction,
                            onPressed: a.onPressed,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A vertical scroll view with the thin thumb of the mockup (`scrollbar-width: thin`,
/// `--lg-thumb` on nothing); the thumb is only there when there is something to scroll.
class _ThinScroll extends StatefulWidget {
  const _ThinScroll({required this.child, this.controller});

  final Widget child;
  final ScrollController? controller;

  @override
  State<_ThinScroll> createState() => _ThinScrollState();
}

class _ThinScrollState extends State<_ThinScroll> {
  ScrollController? _own;

  ScrollController get _controller =>
      widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return RawScrollbar(
      controller: _controller,
      thumbColor: c.thumb,
      thickness: 6,
      radius: const Radius.circular(3),
      crossAxisMargin: 2,
      child: SingleChildScrollView(
        controller: _controller,
        child: widget.child,
      ),
    );
  }
}

/// The banner of the install dialog (`.ibody .bnr`): slim, medium text. What the install will do
/// is a warning ("Leapgate 将关闭并重新打开，……"); what went wrong is an error ("安装失败：……",
/// long English text from the installer wraps anywhere).
class LgInstallBanner extends StatelessWidget {
  const LgInstallBanner({super.key, required this.tone, required this.text});

  final LgTone tone;
  final String text;

  @override
  Widget build(BuildContext context) =>
      LgBanner(tone: tone, text: text, slim: true, medium: true);
}

/// The install location (`.flbl` with `.prow`): the small label, the folder in a sunken box (the
/// path in bold, long ones cut in the middle: the last folder name is always whole), and "修改".
/// Under it a line of [message] when [tone] is not normal.
///
/// The full path shows as a tooltip while the pointer is on a cut one. [onChange] null (the
/// install is running) greys the box and the button. A button marked by [changeAutofocus] takes
/// the keyboard: the page does that when the install is impossible and "修改" is the way on.
class LgInstallPathRow extends StatelessWidget {
  const LgInstallPathRow({
    super.key,
    required this.label,
    required this.path,
    required this.changeLabel,
    required this.onChange,
    this.changeSemanticLabel,
    this.changeFocusNode,
    this.changeAutofocus = false,
    this.tone = LgPathTone.normal,
    this.message,
    this.messageTooltip,
  });

  /// "安装位置".
  final String label;

  /// The whole path, shown from the left, "C:\Program Files\Leapgate".
  final String path;

  /// "修改".
  final String changeLabel;

  /// "修改安装位置", for a screen reader and a script: "修改" alone is not enough.
  final String? changeSemanticLabel;
  final VoidCallback? onChange;
  final FocusNode? changeFocusNode;
  final bool changeAutofocus;
  final LgPathTone tone;

  /// Why the location is not usable ("无法安装到网络位置或可移动磁盘。请选择本机磁盘上的文件夹。") or
  /// the warning ("此文件夹中的现有文件将在安装或卸载 Leapgate 时被删除").
  final String? message;

  /// What the pointer shows on the line of [message] and a screen reader reads after it: the
  /// whole folder that the message is about ("无法安装到 Leapgate 当前所在的文件夹" and the path of
  /// that folder, 13 §4.2 block A). Only that line has a tooltip; the path box keeps its own
  /// (the cut path). Null: the line is as it was.
  final String? messageTooltip;

  /// The icon and the text of [message]; [fill] lets the text take the row (the line as it was)
  /// or keeps the row to the text's width, so that the tooltip stands over the text only.
  Widget _messageLine(LgTokens t, Color color, {required bool fill}) => Row(
    mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: ExcludeSemantics(
          child: LgIcon(
            tone == LgPathTone.error ? LgIcons.err : LgIcons.warn,
            size: 16,
            color: color,
          ),
        ),
      ),
      const SizedBox(width: LgSpace.s2),
      Flexible(
        fit: fill ? FlexFit.tight : FlexFit.loose,
        child: Text(message!, style: t.textS.copyWith(color: color)),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final msgColor = switch (tone) {
      LgPathTone.warning => c.warning,
      LgPathTone.error => c.error,
      LgPathTone.normal => c.text,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: t.textS.copyWith(
              color: c.text2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: LgSpace.s1),
        Row(
          children: [
            Expanded(
              child: _PathBox(
                label: label,
                path: path,
                tone: tone,
                greyed: onChange == null,
              ),
            ),
            const SizedBox(width: LgSpace.s2),
            LgButton(
              label: changeLabel,
              semanticLabel: changeSemanticLabel,
              large: true,
              horizontalPadding: LgSpace.s4,
              focusNode: changeFocusNode,
              autofocus: changeAutofocus,
              onPressed: onChange,
            ),
          ],
        ),
        if (message != null && tone != LgPathTone.normal)
          Padding(
            padding: const EdgeInsets.only(top: LgSpace.s2),
            // `role=alert` for an error, `status` for the warning: both are read out when they
            // appear.
            child: messageTooltip == null
                ? Semantics(
                    liveRegion: true,
                    container: true,
                    child: _messageLine(t, msgColor, fill: true),
                  )
                // The tooltip has an anchor of its own, which a merged node would send on as an
                // orphan (`LEAPGATE.md` §10.8): the line is read from here, with the tooltip's
                // words after its own, so that a keyboard user gets them too.
                : Semantics(
                    liveRegion: true,
                    container: true,
                    label: '$message $messageTooltip',
                    excludeSemantics: true,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: LgTooltip(
                        message: messageTooltip!,
                        child: _messageLine(t, msgColor, fill: false),
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}

class _PathBox extends StatefulWidget {
  const _PathBox({
    required this.label,
    required this.path,
    required this.tone,
    required this.greyed,
  });

  final String label;
  final String path;
  final LgPathTone tone;
  final bool greyed;

  @override
  State<_PathBox> createState() => _PathBoxState();
}

class _PathBoxState extends State<_PathBox> {
  bool _hovered = false;

  /// The last folder with its separator: it stays whole while the rest is cut.
  (String, String) _split() {
    final cut = widget.path.lastIndexOf(RegExp(r'[\\/]'));
    if (cut <= 0) return (widget.path, '');
    return (widget.path.substring(0, cut), widget.path.substring(cut));
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final style = t.text.copyWith(color: c.text, fontWeight: FontWeight.w700);
    final (head, tail) = _split();
    final hovered =
        _hovered || LgStateOverride.of(context).contains(WidgetState.hovered);
    final ring = switch (widget.tone) {
      LgPathTone.error => c.error,
      LgPathTone.warning => c.warning,
      LgPathTone.normal => null,
    };
    final radius = BorderRadius.circular(LgRadius.r12);
    Widget box = LayoutBuilder(
      builder: (context, constraints) {
        // 16 + icon 20 + 12 + 16 around the text.
        final room = constraints.maxWidth - 64;
        final painter = TextPainter(
          text: TextSpan(text: widget.path, style: style),
          textDirection: Directionality.of(context),
          maxLines: 1,
        )..layout();
        final cutOff = painter.width > room;
        painter.dispose();
        final line = Container(
          height: t.sizes.main,
          padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
          decoration: BoxDecoration(
            color: hovered && cutOff ? c.surface2 : c.bg,
            borderRadius: radius,
          ),
          foregroundDecoration: ring == null
              ? null
              : BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: ring, width: 2),
                ),
          child: Row(
            children: [
              LgIcon(LgIcons.folder, size: 20, color: c.text2),
              const SizedBox(width: LgSpace.s3),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        head,
                        style: style,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tail.isNotEmpty)
                      Text(tail, style: style, maxLines: 1, softWrap: false),
                  ],
                ),
              ),
            ],
          ),
        );
        return cutOff ? LgTooltip(message: widget.path, child: line) : line;
      },
    );
    box = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: box,
    );
    // The tooltip of a cut path has an anchor of its own, which a merged node would send on
    // as an orphan (`LEAPGATE.md` §10.8): the box is read from here, whole.
    return Semantics(
      container: true,
      label: widget.label,
      value: widget.path,
      excludeSemantics: true,
      child: widget.greyed ? Opacity(opacity: .6, child: box) : box,
    );
  }
}

/// One option of the install (`.ick`): a 24 px box, the label, and under it a line of small text
/// that says what the option does ([description]; the printer's). The whole row toggles and is
/// read as "label. description, on or off". [onChange] null greys the row (the install is
/// running).
class LgOptionCheck extends StatelessWidget {
  const LgOptionCheck({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.description,
    this.focusNode,
  });

  final bool value;
  final String label;
  final String? description;
  final ValueChanged<bool>? onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    const radius = BorderRadius.all(Radius.circular(LgRadius.r6));
    return LgPressable(
      onPressed: onChanged == null ? null : () => onChanged!(!value),
      focusNode: focusNode,
      semanticLabel: description == null ? label : '$label. $description',
      toggled: value,
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        final fill = value ? c.accent : null;
        return Opacity(
          opacity: states.contains(WidgetState.disabled) ? .6 : 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: t.sizes.button),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: LgSpace.s1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Transform.translate(
                    // `margin-top: -1px`: the box is centred on the first line.
                    offset: const Offset(0, -1),
                    child: LgFocusRing(
                      show: states.contains(WidgetState.focused),
                      radius: radius,
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: overlay == null
                              ? fill
                              : Color.alphaBlend(
                                  overlay,
                                  fill ?? Colors.transparent,
                                ),
                          borderRadius: radius,
                        ),
                        foregroundDecoration: value
                            ? null
                            : BoxDecoration(
                                borderRadius: radius,
                                border: Border.all(
                                  color: c.borderStrong,
                                  width: 1.5,
                                ),
                              ),
                        child: value
                            ? LgIcon(LgIcons.check, size: 16, color: c.onAccent)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: LgSpace.s3),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label, style: t.text.copyWith(color: c.text)),
                          if (description != null)
                            Padding(
                              padding: const EdgeInsets.only(top: LgSpace.s1),
                              child: Text(
                                description!,
                                style: t.textS.copyWith(color: c.text2),
                              ),
                            ),
                        ],
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

/// "开始安装即表示接受‹许可协议›。" (`.lic`): medium text in the second colour with the link in
/// the middle, bold, accent coloured and underlined, with the arrow that leaves the window after
/// it (the page opens in the browser). [before] and [after] are the text on either side of
/// [link]; [after] may be empty.
class LgLicenseLine extends StatelessWidget {
  const LgLicenseLine({
    super.key,
    required this.before,
    required this.link,
    required this.after,
    required this.onOpen,
    this.linkSemanticLabel,
  });

  final String before;
  final String link;
  final String after;
  final VoidCallback onOpen;

  /// When the link needs more than its words to be understood ("打开许可协议（在浏览器中）").
  final String? linkSemanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final style = t.textM.copyWith(color: c.text2);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: before),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            // A node of its own: inline in the paragraph the link would be read, and found by a
            // script, as the whole sentence.
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: LgPressable(
                onPressed: onOpen,
                semanticLabel: linkSemanticLabel ?? link,
                builder: (context, states) => LgFocusRing(
                  show: states.contains(WidgetState.focused),
                  radius: BorderRadius.circular(LgRadius.r6),
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          link,
                          style: style.copyWith(
                            color: c.accent,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                            decorationColor: c.accent,
                            decorationThickness: 2,
                          ),
                        ),
                        const SizedBox(width: LgSpace.s1),
                        Transform.translate(
                          offset: const Offset(0, 2),
                          child: LgIcon(
                            LgIcons.externalLink,
                            size: 14,
                            color: c.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
      style: style,
    );
  }
}
