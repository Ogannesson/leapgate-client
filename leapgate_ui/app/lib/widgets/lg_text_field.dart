import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';

/// Tells the fields below it that they stand in a form dialog (`.sheet .field`
/// in A-P1.html): while disabled they look flat, with no frame, the surface
/// colour instead of the disabled grey and the text in the quiet colour, so a
/// form whose request is on its way keeps its white ground; and the line under
/// a field that is wrong is in regular weight, not bold. [LgFormDialog] sets it.
class LgDialogFields extends InheritedWidget {
  const LgDialogFields({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LgDialogFields>() !=
      null;

  @override
  bool updateShouldNotify(LgDialogFields old) => false;
}

/// The form field (`LgFormField`) a field stands in: its visible label is the
/// field's name unless the field is given one of its own, and "required" is
/// said by the field's semantics too.
class LgFormFieldInfo extends InheritedWidget {
  const LgFormFieldInfo({
    super.key,
    required this.label,
    this.isRequired = false,
    required super.child,
  });

  final String label;
  final bool isRequired;

  static LgFormFieldInfo? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LgFormFieldInfo>();

  @override
  bool updateShouldNotify(LgFormFieldInfo old) =>
      old.label != label || old.isRequired != isRequired;
}

/// Input field (`.field` in A-基础.html): `--lg-h-main` high, 1.5 px inset
/// border; 2 px accent when focused, 2 px error with [errorText], which is
/// shown under the field (password wrong, 01 §4.3).
class LgTextField extends StatefulWidget {
  const LgTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.errorText,
    this.enabled = true,
    this.obscureText = false,
    this.autofocus = false,
    this.leading,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.semanticLabel,
    this.dense = false,
    this.maxLength,
    this.inputFormatters = const [],
    this.showErrorText = true,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final String? errorText;
  final bool enabled;
  final bool obscureText;
  final bool autofocus;

  /// Widget at the left end, e.g. the search icon of the connection box.
  final Widget? leading;

  /// Widget at the right end, e.g. the show-password button.
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// As [TextField.onEditingComplete]: when set, Enter no longer takes the focus away (a chat
  /// input stays ready for the next message).
  final VoidCallback? onEditingComplete;
  final String? semanticLabel;

  /// A button high instead of an input high, with the medium text: the field
  /// of a chat box or of a bar (`.chatp .cf .field`).
  final bool dense;

  /// At most this many characters can be typed or pasted; no counter is shown.
  final int? maxLength;

  /// Run on what is typed, before [maxLength] (an ID in groups of three, say).
  final List<TextInputFormatter> inputFormatters;

  /// False leaves the line under the field out while the frame and the
  /// accessible name still say [errorText]: the caller shows the text itself,
  /// wider than the field (the port of an exit card).
  final bool showErrorText;

  @override
  State<LgTextField> createState() => _LgTextFieldState();
}

class _LgTextFieldState extends State<LgTextField> {
  FocusNode? _ownNode;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(LgTextField old) {
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
    final error = widget.errorText != null;
    final radius = BorderRadius.circular(LgRadius.r12);
    final Border? border;
    if (!widget.enabled) {
      border = null;
    } else if (error) {
      border = Border.all(color: c.error, width: 2);
    } else if (focused) {
      border = Border.all(color: c.accent, width: 2);
    } else {
      border = Border.all(color: c.borderStrong, width: 1.5);
    }
    final base = widget.dense ? t.textM : t.text;
    final form = LgFormFieldInfo.maybeOf(context);
    final named = widget.semanticLabel != null || form != null;
    final flat = !widget.enabled && LgDialogFields.of(context);
    final ink = flat ? c.text2 : c.text;
    final textStyle = widget.obscureText
        // `.mask`: dots at the number size, spaced .14em.
        ? t.textN.copyWith(color: ink, letterSpacing: t.sizes.fsN * .14)
        : base.copyWith(color: ink);
    final field = Container(
      height: widget.dense ? t.sizes.button : t.sizes.main,
      padding: EdgeInsets.symmetric(
        horizontal: widget.dense ? LgSpace.s3 : LgSpace.s4,
      ),
      decoration: BoxDecoration(
        color: widget.enabled || flat ? c.surface : c.disabled,
        borderRadius: radius,
      ),
      foregroundDecoration: border == null
          ? null
          : BoxDecoration(borderRadius: radius, border: border),
      child: Row(
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: LgSpace.s3),
          ],
          // One semantics node for the input itself, so the buttons at its
          // ends (show password, clear) keep names of their own. Its name is
          // the label (the field's own, else that of the form field it stands
          // in, else the placeholder) and the error text; the placeholder is
          // its hint, not part of the name.
          Expanded(
            child: MergeSemantics(
              child: Semantics(
                label: _name(form, error),
                // Not read twice when it says what the name says.
                hint: named && widget.placeholder != _label(form)
                    ? widget.placeholder
                    : null,
                isRequired: form?.isRequired == true ? true : null,
                validationResult: error
                    ? SemanticsValidationResult.invalid
                    : SemanticsValidationResult.none,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _node,
                  enabled: widget.enabled,
                  obscureText: widget.obscureText,
                  obscuringCharacter: '•',
                  autofocus: widget.autofocus,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  onEditingComplete: widget.onEditingComplete,
                  style: textStyle,
                  cursorColor: c.accent,
                  cursorWidth: 2,
                  maxLines: 1,
                  inputFormatters: [
                    ...widget.inputFormatters,
                    if (widget.maxLength != null)
                      LengthLimitingTextInputFormatter(widget.maxLength),
                  ],
                  // The placeholder is drawn as a widget, not as `hintText`:
                  // the text of `hintText` would join the name of the field.
                  decoration: InputDecoration.collapsed(
                    hintText: null,
                    hint: widget.placeholder == null
                        ? null
                        : ExcludeSemantics(
                            child: Text(
                              widget.placeholder!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: base.copyWith(color: c.text2),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: LgSpace.s3),
            widget.trailing!,
          ],
        ],
      ),
    );
    final box = error && widget.showErrorText ? _withError(field) : field;
    if (widget.leading == null && widget.trailing == null) return box;
    // The buttons at the ends are nodes beside the input's, in a group of
    // their own, so that they do not take over the node of what stands around
    // the field.
    return Semantics(container: true, explicitChildNodes: true, child: box);
  }

  String? _label(LgFormFieldInfo? form) =>
      widget.semanticLabel ?? form?.label ?? widget.placeholder;

  String? _name(LgFormFieldInfo? form, bool error) {
    final label = _label(form);
    if (!error) return label;
    return [if (label != null) label, widget.errorText!].join('\n');
  }

  Widget _withError(Widget field) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        const SizedBox(height: LgSpace.s2),
        // Read as part of the field's name (above).
        ExcludeSemantics(child: LgFieldError(widget.errorText!)),
      ],
    );
  }
}

/// The red line under a field (`.ferr`): error icon and text.
class LgFieldError extends StatelessWidget {
  const LgFieldError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return DefaultTextStyle(
      style: t.textS.copyWith(
        color: c.error,
        fontWeight: LgDialogFields.of(context)
            ? FontWeight.w400
            : FontWeight.w700,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: LgIcon(LgIcons.err, size: 16, color: c.error),
          ),
          const SizedBox(width: LgSpace.s2),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
