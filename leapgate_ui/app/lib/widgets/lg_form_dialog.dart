// The shell of the dialogs that ask for something typed (01 §3.1 block K,
// `.sheet` with `.hd`, `.flbl`, `.field`, `.acts2` in A-P1.html): an icon tile
// and the title, a line of small text, a banner for what went wrong, the
// labelled fields, and the buttons at the end. The login dialog, the dialog
// that adds a device and the one that changes a tag's colour are built on it,
// and so are the small ones the address book needs (add a tag, rename,
// edit the note, set the shared password, join an address book).
//
// It only draws: the controllers, the texts and the callbacks are the caller's.
// Put it in an `LgDialogScrim` like the other confirmations.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_default_enter.dart';
import 'lg_feedback.dart';
import 'lg_pressable.dart';
import 'lg_text_field.dart';

/// The dialog card: head, [note], [banner], [children], buttons.
///
/// [actions] are the buttons from the left; the usual two are the way out
/// (secondary) and the answer ([LgButtonKind.primary], marked
/// [LgDialogAction.isDefault] so that Enter in a field runs it). While a request
/// is on its way give the answer [LgDialogAction.busy]: it greys, turns, and
/// Enter no longer runs it.
class LgFormDialog extends StatelessWidget {
  const LgFormDialog({
    super.key,
    required this.title,
    required this.icon,
    required this.actions,
    this.note,
    this.banner,
    this.children = const [],
    this.width = 440,
    this.leading,
  });

  /// "登录", "添加设备", "修改标签颜色".
  final String title;

  /// In the tile before the title.
  final LgIcons icon;

  /// A small line under the head ("添加到：家里的电脑").
  final String? note;

  /// What went wrong, as an `LgBanner(slim: true)`; it sits under [note].
  final Widget? banner;

  /// The fields, usually [LgFormField]s.
  final List<Widget> children;
  final List<LgDialogAction> actions;
  final double width;

  /// Something at the start of the button row, away from the answer
  /// (`.acts2 .mv`): a link ("改用管理员权限解锁") or a button that undoes
  /// the whole thing ("清除", "全部恢复默认"). Not part of [actions], so Enter
  /// never runs it.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final defaultAction = actions
        .where((a) => a.isDefault && a.onPressed != null && !a.busy)
        .firstOrNull;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: LgDefaultEnter(
        onEnter: defaultAction?.onPressed,
        child: FocusScope(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: c.float,
                borderRadius: BorderRadius.circular(LgRadius.r20),
                boxShadow: c.shadow,
              ),
              child: LgDialogFields(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
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
                    if (note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: LgSpace.s3),
                        child: Text(
                          note!,
                          style: t.textS.copyWith(color: c.text2),
                        ),
                      ),
                    if (banner != null)
                      Padding(
                        padding: const EdgeInsets.only(top: LgSpace.s4),
                        child: banner,
                      ),
                    ...children,
                    const SizedBox(height: LgSpace.s6),
                    if (leading == null)
                      _buttons()
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: leading!),
                          const SizedBox(width: LgSpace.s3),
                          _buttons(),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buttons() => Wrap(
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
          onPressed: a.onPressed,
        ),
    ],
  );
}

/// A field of a form dialog with its label above (`.flbl`): the label in small
/// bold text, a red star after it when the field must be filled in, [counter]
/// at the other end ("0 / 300"), the [child] (an `LgTextField`, an
/// `LgPasswordField`, an `LgTextArea`, a group of tag buttons), and [hint]
/// under it.
///
/// The field in it is named by the label alone (unless it is given a
/// `semanticLabel` of its own), so that a screen reader and an automation script
/// find it by what it is called on screen; its placeholder is its hint, and
/// [required] is said too. The counter and the [hint] under the field are read
/// as they stand.
class LgFormField extends StatelessWidget {
  const LgFormField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.counter,
    this.hint,
  });

  final String label;
  final Widget child;

  /// A red star after the label.
  final bool required;

  /// Small text at the right end of the label row.
  final String? counter;

  /// A line of small text under the field ("这些内容对此地址簿的其他成员可见").
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final style = t.textS.copyWith(color: c.text2, fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.only(top: LgSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                // The field is named by it (see [LgFormFieldInfo]); read here
                // it would be said twice.
                child: ExcludeSemantics(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: label),
                        if (required)
                          TextSpan(
                            text: '*',
                            style: TextStyle(color: c.error),
                          ),
                      ],
                    ),
                    style: style,
                  ),
                ),
              ),
              if (counter != null) ...[
                const SizedBox(width: LgSpace.s3),
                Text(counter!, style: style),
              ],
            ],
          ),
          const SizedBox(height: LgSpace.s1),
          LgFormFieldInfo(label: label, isRequired: required, child: child),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: LgSpace.s1),
              child: Text(hint!, style: t.textS.copyWith(color: c.text2)),
            ),
        ],
      ),
    );
  }
}

/// A multi-line input of a fixed height (`.field.area`, the note of a device):
/// the same frame as `LgTextField`, text from the top. The counter is the
/// label row's business ([LgFormField.counter]); [maxLength] only stops the
/// typing.
class LgTextArea extends StatefulWidget {
  const LgTextArea({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.enabled = true,
    this.maxLength,
    this.onChanged,
    this.semanticLabel,
    this.height = 72,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final bool enabled;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final String? semanticLabel;
  final double height;

  @override
  State<LgTextArea> createState() => _LgTextAreaState();
}

class _LgTextAreaState extends State<LgTextArea> {
  FocusNode? _ownNode;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(LgTextArea old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownNode)?.removeListener(_onFocus);
      _node.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _ownNode?.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final focused =
        widget.enabled &&
        (_node.hasFocus ||
            LgStateOverride.of(context).contains(WidgetState.focused));
    final radius = BorderRadius.circular(LgRadius.r12);
    final flat = !widget.enabled && LgDialogFields.of(context);
    final Border? border = !widget.enabled
        ? null
        : focused
        ? Border.all(color: c.accent, width: 2)
        : Border.all(color: c.borderStrong, width: 1.5);
    final form = LgFormFieldInfo.maybeOf(context);
    final name = widget.semanticLabel ?? form?.label;
    return MergeSemantics(
      child: Semantics(
        label: name ?? widget.placeholder,
        // Not read twice when it says what the name says.
        hint: name != null && name != widget.placeholder
            ? widget.placeholder
            : null,
        isRequired: form?.isRequired == true ? true : null,
        child: Container(
          height: widget.height,
          padding: const EdgeInsets.symmetric(
            horizontal: LgSpace.s4,
            vertical: LgSpace.s3,
          ),
          decoration: BoxDecoration(
            color: widget.enabled || flat ? c.surface : c.disabled,
            borderRadius: radius,
          ),
          foregroundDecoration: border == null
              ? null
              : BoxDecoration(borderRadius: radius, border: border),
          child: TextField(
            controller: widget.controller,
            focusNode: _node,
            enabled: widget.enabled,
            onChanged: widget.onChanged,
            style: t.text.copyWith(color: flat ? c.text2 : c.text),
            cursorColor: c.accent,
            cursorWidth: 2,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            inputFormatters: [
              if (widget.maxLength != null)
                LengthLimitingTextInputFormatter(widget.maxLength),
            ],
            decoration: InputDecoration.collapsed(
              hintText: null,
              hint: widget.placeholder == null
                  ? null
                  : ExcludeSemantics(
                      child: Text(
                        widget.placeholder!,
                        style: t.text.copyWith(color: c.text2),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
