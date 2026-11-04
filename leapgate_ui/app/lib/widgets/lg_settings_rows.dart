// The rows a settings section is made of (02 §1.2.5, A-P6-设置.html ".s-b .s-r
// .s-xs .ab-r"): the white block with its fine lines, the row (name, small
// description, control), the small title that splits a section, the line of
// small text between blocks, the row that says "ready / needs attention" with a
// button, the number box with its unit, the label-and-value row of the About
// page and of the server summary, the text link.
//
// They only draw. The values, the texts and what a click does are the section's
// business; a row that does not apply is dimmed by the section and gives its
// reason, a row that was just opened from search or a link is [marked] by the
// section for about two seconds.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_banner.dart';
import 'lg_button.dart';
import 'lg_pressable.dart';
import 'lg_selection.dart';
import 'lg_settings_layout.dart';
import 'lg_text_field.dart';

// ---- block and row frame ------------------------------------------------------

/// Tells a row whether it is the first of its block (no line above it).
class _BlockSlot extends InheritedWidget {
  const _BlockSlot({required this.first, required super.child});

  final bool first;

  static bool firstOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BlockSlot>()?.first ?? true;

  @override
  bool updateShouldNotify(_BlockSlot old) => old.first != first;
}

/// A white block (`.s-b`): related rows on the surface colour, 16 rounded,
/// a fine line between rows. Rows are [LgSettingsRow] and the other row parts
/// of this file (anything built on [LgSettingsRowFrame] draws its line and its
/// mark right).
///
/// [disabled] is for a block that another choice overrules (the password
/// settings while the approval needs no password): the rows go to 60 % and
/// cannot be reached. The reason is a [LgSettingsNote] between the blocks.
/// [gap] puts more room above it (`.s-b.gap`).
class LgSettingsBlock extends StatelessWidget implements LgSettingsFlowPart {
  const LgSettingsBlock({
    super.key,
    required this.children,
    this.disabled = false,
    this.gap = false,
  });

  final List<Widget> children;
  final bool disabled;
  final bool gap;

  @override
  LgSettingsFlow get flow =>
      gap ? LgSettingsFlow.gappedBlock : LgSettingsFlow.block;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(LgRadius.r16),
        ),
        child: LgSettingsDimmed(
          dimmed: disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, child) in children.indexed)
                _BlockSlot(first: i == 0, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// What every row of a block stands on: 16 at the sides, the fine line above
/// it (unless it is the first, or is marked), the mark itself. A row part of
/// another file (the shortcut row, the trusted devices) builds on it.
///
/// [marked] is the "you are here" that follows a click in the search results or
/// a link: the row is tinted and ringed in the accent colour, a little wider
/// than the rows around it so that the ring is not cut by the block's padding.
class LgSettingsRowFrame extends StatelessWidget {
  const LgSettingsRowFrame({
    super.key,
    required this.child,
    this.marked = false,
    this.indented = false,
    this.verticalPadding,
    this.minHeight,
  });

  final Widget child;
  final bool marked;

  /// One level in (`.s-r.in`): the row depends on the one above.
  final bool indented;
  final double? verticalPadding;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final first = _BlockSlot.firstOf(context);
    final v = verticalPadding ?? (t.detail ? LgSpace.s2 : LgSpace.s3);
    final radius = BorderRadius.circular(LgRadius.r12);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: CustomPaint(
        foregroundPainter: _RulePainter(
          color: c.border,
          show: !first && !marked,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight ?? t.sizes.row),
          // Only the mark fades; the padding follows the mode at once.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: radius,
              color: marked
                  ? Color.alphaBlend(c.active, c.surface)
                  : c.surface.withValues(alpha: 0),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: marked ? c.accent : c.accent.withValues(alpha: 0),
                width: 2,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                LgSpace.s4 + (indented ? LgSpace.s6 : 0),
                v,
                LgSpace.s4,
                v,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The fine line above a row, inset 16 at both ends. Painted, so that it takes
/// no room (`box-shadow: 0 -1px 0` in the mockup).
class _RulePainter extends CustomPainter {
  _RulePainter({required this.color, required this.show});

  final Color color;
  final bool show;

  @override
  void paint(Canvas canvas, Size size) {
    if (!show) return;
    canvas.drawRect(
      Rect.fromLTRB(LgSpace.s4, 0, size.width - LgSpace.s4, 1),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_RulePainter old) =>
      old.color != color || old.show != show;
}

// ---- the row ------------------------------------------------------------------

/// A setting (`.s-r`): its name, a line of small description under it, and the
/// control at the end (a switch, a segmented control, a field with its unit, a
/// value with buttons). Where the content is narrow ([LgSettingsMetrics]) a
/// [wide] control moves to the line under the name.
///
/// - [body]: more under the name and description (the option group of a
///   choice, a status line).
/// - [disabled]: the name and the control go to 60 % and cannot be reached;
///   [disabledReason] says why, under the row ("由访问模式“完全访问”决定").
/// - [error]: a red line under the row ("无法保存设置", "端口 21118 已被其他应用占用");
///   [errorAtEnd] puts it at the right, under the control, where the number
///   boxes have theirs.
class LgSettingsRow extends StatelessWidget {
  const LgSettingsRow({
    super.key,
    required this.name,
    this.description,
    this.body,
    this.control,
    this.indented = false,
    this.wide = false,
    this.marked = false,
    this.disabled = false,
    this.disabledReason,
    this.error,
    this.errorAtEnd = false,
    this.nameNamesControl = false,
  });

  /// A row whose control is a switch, named by [name]. The switch carries the
  /// name for a reader, so the visible name is not read a second time.
  factory LgSettingsRow.toggle({
    Key? key,
    required String name,
    String? description,
    required bool value,
    required ValueChanged<bool>? onChanged,
    bool indented = false,
    bool marked = false,
    bool disabled = false,
    String? disabledReason,
    String? error,
  }) => LgSettingsRow(
    key: key,
    name: name,
    description: description,
    control: LgSwitch(
      value: value,
      onChanged: disabled ? null : onChanged,
      semanticLabel: name,
    ),
    indented: indented,
    marked: marked,
    disabled: disabled,
    disabledReason: disabledReason,
    error: error,
    nameNamesControl: true,
  );

  final String name;
  final String? description;
  final Widget? body;
  final Widget? control;
  final bool indented;

  /// The control is wide (three segments, a field with a unit, a drop-down,
  /// buttons): it goes under the name where the content is narrow.
  final bool wide;
  final bool marked;
  final bool disabled;
  final String? disabledReason;
  final String? error;
  final bool errorAtEnd;

  /// The control already says [name] to a reader (a switch given the name as
  /// its label): the visible name is left out of the semantics, or it would be
  /// read twice. Rows whose control is named otherwise ("修改", "设置固定密码")
  /// keep it.
  final bool nameNamesControl;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final narrow = LgSettingsMetrics.narrowOf(context);
    final nameText = Text(name, style: t.text.copyWith(color: c.text));
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LgSettingsDimmed(
          dimmed: disabled,
          child: nameNamesControl
              ? ExcludeSemantics(child: nameText)
              : nameText,
        ),
        if (description != null)
          Text(description!, style: t.textS.copyWith(color: c.text2)),
        // A status line ([LgStatusText]) takes its size from here.
        if (body != null)
          DefaultTextStyle(
            style: t.textM.copyWith(color: c.text),
            child: body!,
          ),
      ],
    );
    final Widget main;
    if (control == null) {
      main = text;
    } else if (wide && narrow) {
      main = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          text,
          const SizedBox(height: LgSpace.s2),
          LgSettingsDimmed(dimmed: disabled, child: control!),
        ],
      );
    } else {
      main = Row(
        children: [
          Expanded(child: text),
          const SizedBox(width: LgSpace.s4),
          LgSettingsDimmed(dimmed: disabled, child: control!),
        ],
      );
    }
    return LgSettingsRowFrame(
      marked: marked,
      indented: indented,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          main,
          if (disabled && disabledReason != null)
            Padding(
              padding: const EdgeInsets.only(top: LgSpace.s2),
              child: _NoteLine(disabledReason!),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: LgSpace.s1),
              child: _ErrorLine(error!, alignEnd: errorAtEnd),
            ),
        ],
      ),
    );
  }
}

/// The options of a choice, stacked under its name (`.s-os`): put the
/// [LgRadio]s here and the group in the row's `body`.
class LgSettingsOptions extends StatelessWidget {
  const LgSettingsOptions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: LgSpace.s1, bottom: LgSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

// ---- small text -----------------------------------------------------------------

/// The small title that splits a section into parts (`.s-sub`: "高级", "录制").
class LgSettingsSubtitle extends StatelessWidget implements LgSettingsFlowPart {
  const LgSettingsSubtitle(this.text, {super.key});

  final String text;

  @override
  LgSettingsFlow get flow => LgSettingsFlow.subtitle;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: LgSpace.s1),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: t.textS.copyWith(
            color: t.colors.text2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// A line of small text between blocks, with the information icon: why the
/// block below is dimmed (`.s-note`).
class LgSettingsNote extends StatelessWidget implements LgSettingsFlowPart {
  const LgSettingsNote(this.text, {super.key});

  final String text;

  @override
  LgSettingsFlow get flow => LgSettingsFlow.note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: LgSpace.s1),
    child: _NoteLine(text),
  );
}

class _NoteLine extends StatelessWidget {
  const _NoteLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: LgIcon(LgIcons.info, size: 16, color: c.accent),
        ),
        const SizedBox(width: LgSpace.s2),
        Expanded(
          child: Text(text, style: t.textS.copyWith(color: c.text2)),
        ),
      ],
    );
  }
}

/// The red line under a setting, which can be set at the right (`.ferr`). The
/// line is read after the name, as a live message.
class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text, {required this.alignEnd});

  final String text;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisAlignment: alignEnd
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: LgIcon(LgIcons.err, size: 16, color: c.error),
          ),
          const SizedBox(width: LgSpace.s2),
          Flexible(
            child: Text(
              text,
              textAlign: alignEnd ? TextAlign.end : TextAlign.start,
              style: t.textS.copyWith(
                color: c.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- value and buttons ------------------------------------------------------------

/// A button of [LgSettingsValueActions] and [LgSettingsStatusRow].
class LgSettingsAction {
  const LgSettingsAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = LgButtonKind.secondary,
    this.busy = false,
    this.semanticLabel,
    this.focusNode,
  });

  final String label;
  final VoidCallback? onPressed;

  /// The shield ([LgIcons.uac]) on a button that asks for administrator
  /// permission (02 §3.4).
  final LgIcons? icon;
  final LgButtonKind kind;
  final bool busy;
  final String? semanticLabel;
  final FocusNode? focusNode;

  Widget build() => LgButton(
    label: label,
    icon: icon,
    kind: kind,
    busy: busy,
    semanticLabel: semanticLabel,
    focusNode: focusNode,
    onPressed: onPressed,
  );
}

/// The control of a setting that has a value only a dialog can edit: the
/// present state in words ("未启用", "已启用 · 3 条", "已设置") and up to three
/// buttons with the verbs ("编辑", "移除"). Never a check box that opens a
/// dialog (02 §1.2.5).
class LgSettingsValueActions extends StatelessWidget {
  const LgSettingsValueActions({
    super.key,
    this.value,
    this.emphasized = false,
    this.mono = false,
    this.actions = const [],
  }) : assert(actions.length <= 3);

  /// The state in words.
  final String? value;

  /// The state is on, set, in use: in the text colour and bold, not quiet.
  final bool emphasized;

  /// A figure in the monospace face (a port).
  final bool mono;
  final List<LgSettingsAction> actions;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final base = mono ? LgTokens.monoStyle(t.sizes.fsS, t.sizes.lhM) : t.textM;
    return Wrap(
      spacing: LgSpace.s3,
      runSpacing: LgSpace.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (value != null)
          Text(
            value!,
            softWrap: false,
            style: base.copyWith(
              color: emphasized ? c.text : c.text2,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        for (final a in actions) a.build(),
      ],
    );
  }
}

// ---- status row -------------------------------------------------------------------

/// A line that says whether a precondition holds (`.s-xs`): a tone icon, the
/// sentence, and buttons that lead to the fix ("修改"). The exit page's
/// preconditions are these. The tone is told by the icon, the sentence and
/// [toneLabel], never by the colour alone (02 §5.1).
class LgSettingsStatusRow extends StatelessWidget {
  const LgSettingsStatusRow({
    super.key,
    required this.tone,
    required this.text,
    this.description,
    this.toneLabel,
    this.actions = const [],
    this.marked = false,
  });

  /// [LgTone.success] for met, [LgTone.warning] for needs a look,
  /// [LgTone.info] for neutral; [LgTone.error] for failed.
  final LgTone tone;
  final String text;

  /// Smaller text under the sentence.
  final String? description;

  /// What a screen reader hears for the icon ("已满足", "需要注意").
  final String? toneLabel;
  final List<LgSettingsAction> actions;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final narrow = LgSettingsMetrics.narrowOf(context);
    final icon = Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Semantics(
        label: toneLabel,
        child: LgIcon(lgToneIcon(tone), size: 20, color: lgToneColor(c, tone)),
      ),
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: t.textM.copyWith(color: c.text)),
        if (description != null)
          Text(description!, style: t.textS.copyWith(color: c.text2)),
      ],
    );
    final buttons = Wrap(
      spacing: LgSpace.s2,
      runSpacing: LgSpace.s2,
      children: [for (final a in actions) a.build()],
    );
    // The icon and the words are one unit, so that a button taller than one line
    // of words is level with the middle of the words.
    final lead = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        icon,
        const SizedBox(width: LgSpace.s3),
        Expanded(child: words),
      ],
    );
    return LgSettingsRowFrame(
      marked: marked,
      child: narrow && actions.isNotEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                lead,
                const SizedBox(height: LgSpace.s2),
                Padding(
                  padding: const EdgeInsets.only(left: 20 + LgSpace.s3),
                  child: buttons,
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: lead),
                if (actions.isNotEmpty) ...[
                  const SizedBox(width: LgSpace.s3),
                  buttons,
                ],
              ],
            ),
    );
  }
}

// ---- number field -----------------------------------------------------------------

/// A box for a number or a short text with its unit after it (`.s-in`, `.s-u`):
/// minutes, a port, seconds. What is typed is saved when Enter is pressed or the
/// focus leaves the box ([onSubmitted], only if it differs from [text]); Esc
/// puts [text] back ([onReverted]). A wrong value is the section's to refuse:
/// it gives [errorText] (the frame turns red) and shows the words in the row's
/// `error` with `errorAtEnd`, wide enough to read.
///
/// A box that is taken out of the tree (the section is switched, the page is
/// left) while it still has the focus does not hand over what is typed: its
/// focus node is gone before it can tell. The page takes the focus away
/// (`FocusManager.instance.primaryFocus?.unfocus()`) before it switches the
/// content, and so has the value handed over first.
class LgSettingsNumberField extends StatefulWidget {
  const LgSettingsNumberField({
    super.key,
    required this.text,
    required this.onSubmitted,
    required this.semanticLabel,
    this.unit,
    this.width = 96,
    this.errorText,
    this.enabled = true,
    this.maxLength,
    this.inputFormatters = const [],
    this.placeholder,
    this.onChanged,
    this.onReverted,
    this.focusNode,
  });

  /// The saved value as the box shows it.
  final String text;

  /// What was typed, once, on Enter or when the focus leaves.
  final ValueChanged<String> onSubmitted;

  /// The accessible name; give the name of the setting (and the unit).
  final String semanticLabel;
  final String? unit;
  final double width;
  final String? errorText;
  final bool enabled;
  final int? maxLength;
  final List<TextInputFormatter> inputFormatters;
  final String? placeholder;
  final ValueChanged<String>? onChanged;

  /// Esc put the saved value back; the section clears its error.
  final VoidCallback? onReverted;
  final FocusNode? focusNode;

  @override
  State<LgSettingsNumberField> createState() => _LgSettingsNumberFieldState();
}

class _LgSettingsNumberFieldState extends State<LgSettingsNumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );
  FocusNode? _ownNode;
  String? _sent;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(LgSettingsNumberField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownNode)?.removeListener(_onFocus);
      _node.addListener(_onFocus);
    }
    if (old.text != widget.text && _controller.text != widget.text) {
      _controller.text = widget.text;
      _sent = null;
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _ownNode?.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_node.hasFocus) _commit();
  }

  void _commit() {
    final typed = _controller.text;
    if (typed == widget.text || typed == _sent) return;
    _sent = typed;
    widget.onSubmitted(typed);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_controller.text == widget.text && widget.errorText == null) {
      return KeyEventResult.ignored;
    }
    _controller.text = widget.text;
    _sent = null;
    widget.onReverted?.call();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.width,
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: LgTextField(
              controller: _controller,
              focusNode: _node,
              dense: true,
              enabled: widget.enabled,
              semanticLabel: widget.semanticLabel,
              placeholder: widget.placeholder,
              errorText: widget.errorText,
              // The row shows the words, wide enough to read.
              showErrorText: false,
              maxLength: widget.maxLength,
              inputFormatters: widget.inputFormatters,
              onChanged: (v) {
                _sent = null;
                widget.onChanged?.call(v);
              },
              // Enter must not take the focus out of the box: after a refused
              // value Esc still puts the saved one back.
              onEditingComplete: () {},
              onSubmitted: (_) => _commit(),
            ),
          ),
        ),
        if (widget.unit != null) ...[
          const SizedBox(width: LgSpace.s2),
          Text(widget.unit!, style: t.textM.copyWith(color: c.text2)),
        ],
      ],
    );
  }
}

// ---- label and value ----------------------------------------------------------------

/// A row of label, value and an optional copy button (`.ab-r`): the lines of the
/// About page (version, build date, fingerprint, ID, links) and of the server
/// summary (ID server, API server, key, type). The value is [value], or [child]
/// when it is more than text (the three links).
class LgSettingsInfoRow extends StatelessWidget {
  const LgSettingsInfoRow({
    super.key,
    required this.label,
    this.value,
    this.child,
    this.caption,
    this.mono = false,
    this.onCopy,
    this.copyLabel,
    this.copySemanticLabel,
    this.labelWidth = 96,
    this.marked = false,
  }) : assert(value != null || child != null),
       assert(onCopy == null || copyLabel != null);

  final String label;
  final String? value;
  final Widget? child;

  /// Small text under the value ("基于 RustDesk 1.5.1").
  final String? caption;

  /// A fingerprint: the monospace face, small, line breaks kept.
  final bool mono;

  /// Null leaves out the copy button.
  final VoidCallback? onCopy;
  final String? copyLabel;

  /// "复制版本" when the button is not named by its words.
  final String? copySemanticLabel;
  final double labelWidth;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return LgSettingsRowFrame(
      marked: marked,
      child: Row(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Text(label, style: t.textM.copyWith(color: c.text2)),
                ),
                const SizedBox(width: LgSpace.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (child != null)
                        child!
                      else
                        Text(
                          value!,
                          style: mono
                              ? LgTokens.monoStyle(
                                  t.sizes.fsS,
                                  t.sizes.lhM,
                                ).copyWith(color: c.text)
                              : t.textM.copyWith(color: c.text),
                        ),
                      if (caption != null)
                        Text(caption!, style: t.textS.copyWith(color: c.text2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (onCopy != null) ...[
            const SizedBox(width: LgSpace.s4),
            // Level with the middle of the row, as the mockup has it.
            LgButton(
              label: copyLabel!,
              icon: LgIcons.copy,
              kind: LgButtonKind.text,
              semanticLabel: copySemanticLabel,
              onPressed: onCopy,
            ),
          ],
        ],
      ),
    );
  }
}

/// The product mark with its name at the top of the About page (`.ab-h`). The
/// [logo] is the product's own; without one a quiet square stands in.
class LgSettingsAboutHeader extends StatelessWidget {
  const LgSettingsAboutHeader({
    super.key,
    required this.name,
    this.subtitle,
    this.logo,
  });

  final String name;
  final String? subtitle;
  final Widget? logo;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Padding(
      padding: const EdgeInsets.only(top: LgSpace.s2, bottom: LgSpace.s1),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child:
                logo ??
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.borderStrong,
                    borderRadius: BorderRadius.circular(LgRadius.r12),
                  ),
                ),
          ),
          const SizedBox(width: LgSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    name,
                    style: t.textN.copyWith(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: t.textM.copyWith(color: c.text2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The line of small print under the last block (`.ab-cp`: the copyright).
class LgSettingsFootnote extends StatelessWidget {
  const LgSettingsFootnote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: LgSpace.s1),
      child: Text(text, style: t.textS.copyWith(color: t.colors.text2)),
    );
  }
}

// ---- list heading and text link ----------------------------------------------------------

/// A bold title with buttons at its end (`.td-h`): "受信设备" with "全部删除",
/// "快捷键列表" with "恢复默认". The row is at least a button high.
class LgSettingsListHeader extends StatelessWidget
    implements LgSettingsFlowPart {
  const LgSettingsListHeader({
    super.key,
    required this.title,
    this.trailing = const [],
  });

  final String title;

  /// A quiet text ([Text] in the small medium style), buttons.
  final List<Widget> trailing;

  @override
  LgSettingsFlow get flow => LgSettingsFlow.heading;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: t.sizes.button),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: t.text.copyWith(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          for (final w in trailing) ...[const SizedBox(width: LgSpace.s3), w],
        ],
      ),
    );
  }
}

/// A link in a line of text or a footer (`.lnk`): small, bold, accent coloured
/// and underlined. A button for the keyboard and the screen reader.
class LgTextLink extends StatelessWidget {
  const LgTextLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
    this.focusNode,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return LgPressable(
      onPressed: onPressed,
      focusNode: focusNode,
      semanticLabel: semanticLabel ?? label,
      builder: (context, states) {
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: BorderRadius.circular(LgRadius.r6),
          child: ExcludeSemantics(
            child: Text(
              label,
              style: t.textS.copyWith(
                color: states.contains(WidgetState.disabled)
                    ? c.text2
                    : c.accent,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: states.contains(WidgetState.disabled)
                    ? c.text2
                    : c.accent,
                decorationThickness: 2,
              ),
            ),
          ),
        );
      },
    );
  }
}
