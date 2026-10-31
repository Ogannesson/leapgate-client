// Inputs of the connection panel (01 §3.2 block D): the password field with a
// show button, the verification code field and the drop-down. `.field`,
// `.otp` and `.field.sel` in A-P2.html.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_menu.dart';
import 'lg_pressable.dart';
import 'lg_text_field.dart';

/// A password input with a button that shows what was typed. The text is
/// hidden to begin with; [showLabel] and [hideLabel] name the button for the
/// state it will switch to.
class LgPasswordField extends StatefulWidget {
  const LgPasswordField({
    super.key,
    required this.controller,
    required this.showLabel,
    required this.hideLabel,
    this.focusNode,
    this.placeholder,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.semanticLabel,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final String? errorText;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? semanticLabel;
  final String showLabel;
  final String hideLabel;

  @override
  State<LgPasswordField> createState() => _LgPasswordFieldState();
}

class _LgPasswordFieldState extends State<LgPasswordField> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    return LgTextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      placeholder: widget.placeholder,
      errorText: widget.errorText,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: !_shown,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      semanticLabel: widget.semanticLabel ?? widget.placeholder,
      trailing: LgIconButton(
        icon: _shown ? LgIcons.eyeOff : LgIcons.eye,
        label: _shown ? widget.hideLabel : widget.showLabel,
        size: 32,
        iconSize: 22,
        onPressed: widget.enabled
            ? () => setState(() => _shown = !_shown)
            : null,
      ),
    );
  }
}

/// A verification code of [length] digits drawn as one box per digit (`.otp`).
/// One transparent text field lies over the boxes, so typing, deleting,
/// pasting and the input method work as in any field; [onCompleted] is called
/// each time the last digit is typed.
class LgCodeField extends StatefulWidget {
  const LgCodeField({
    super.key,
    required this.semanticLabel,
    this.length = 6,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.errorText,
    this.onChanged,
    this.onCompleted,
  });

  /// Accessible name of the field ("验证码").
  final String semanticLabel;
  final int length;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;

  /// Draws every box in the error colour and shows the text under them.
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;

  @override
  State<LgCodeField> createState() => _LgCodeFieldState();
}

class _LgCodeFieldState extends State<LgCodeField> {
  TextEditingController? _ownController;
  FocusNode? _ownNode;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_rebuild);
    _node.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(LgCodeField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.removeListener(_rebuild);
      _controller.addListener(_rebuild);
    }
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownNode)?.removeListener(_rebuild);
      _node.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    _node.removeListener(_rebuild);
    _ownController?.dispose();
    _ownNode?.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _changed(String text) {
    widget.onChanged?.call(text);
    if (text.length == widget.length) widget.onCompleted?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final text = _controller.text;
    final error = widget.errorText != null;
    final focused =
        widget.enabled &&
        (_node.hasFocus ||
            LgStateOverride.of(context).contains(WidgetState.focused));
    final current = text.length < widget.length
        ? text.length
        : widget.length - 1;
    final radius = BorderRadius.circular(LgRadius.r12);
    final boxes = Row(
      children: [
        for (var i = 0; i < widget.length; i++) ...[
          if (i > 0) const SizedBox(width: LgSpace.s2),
          Expanded(
            child: Container(
              height: t.sizes.main,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.enabled ? c.surface : c.disabled,
                borderRadius: radius,
              ),
              foregroundDecoration: !widget.enabled
                  ? null
                  : BoxDecoration(
                      borderRadius: radius,
                      border: error
                          ? Border.all(color: c.error, width: 2)
                          : (focused && i == current)
                          ? Border.all(color: c.accent, width: 2)
                          : Border.all(color: c.borderStrong, width: 1.5),
                    ),
              child: Text(
                i < text.length ? text[i] : '',
                style: t.textN.copyWith(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    );
    final field = Stack(
      children: [
        ExcludeSemantics(child: boxes),
        // Lies over the boxes with invisible text: the field gets the clicks,
        // the keyboard and the input method.
        Positioned.fill(
          child: Semantics(
            label: widget.semanticLabel,
            validationResult: error
                ? SemanticsValidationResult.invalid
                : SemanticsValidationResult.none,
            child: TextField(
              controller: _controller,
              focusNode: _node,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.length),
              ],
              enableInteractiveSelection: false,
              showCursor: false,
              cursorColor: Colors.transparent,
              style: const TextStyle(color: Colors.transparent),
              decoration: const InputDecoration.collapsed(hintText: null),
              onChanged: _changed,
            ),
          ),
        ),
      ],
    );
    if (!error) return field;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        const SizedBox(height: LgSpace.s2),
        LgFieldError(widget.errorText!),
      ],
    );
  }
}

/// One choice of an [LgSelectField].
class LgSelectItem<T> {
  const LgSelectItem(this.value, this.label);

  final T value;
  final String label;
}

/// A field that opens a list of choices (`.field.sel`): the chosen label and
/// a down arrow; the list is a menu as wide as the field.
class LgSelectField<T> extends StatelessWidget {
  const LgSelectField({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<LgSelectItem<T>> items;
  final T? value;

  /// Null disables the field.
  final ValueChanged<T>? onChanged;

  /// Accessible name ("Windows 用户"); the chosen label is read with it.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final chosen = items.where((i) => i.value == value).firstOrNull;
    final radius = BorderRadius.circular(LgRadius.r12);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : kLgMenuWidth;
        return LgMenuAnchor(
          width: width,
          items: [
            for (final item in items)
              LgMenuItem(
                label: item.label,
                checked: item.value == value,
                onPressed: onChanged == null
                    ? null
                    : () => onChanged!(item.value),
              ),
          ],
          builder: (context, controller) => LgPressable(
            onPressed: onChanged == null
                ? null
                : () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
            semanticLabel: [?semanticLabel, ?chosen?.label].join(': '),
            builder: (context, states) {
              final open =
                  controller.isOpen || states.contains(WidgetState.selected);
              final disabled = states.contains(WidgetState.disabled);
              final Border? border = disabled
                  ? null
                  : open
                  ? Border.all(color: c.accent, width: 2)
                  : Border.all(color: c.borderStrong, width: 1.5);
              return LgFocusRing(
                show: states.contains(WidgetState.focused),
                radius: radius,
                child: Container(
                  height: t.sizes.main,
                  padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
                  decoration: BoxDecoration(
                    color: disabled ? c.disabled : c.surface,
                    borderRadius: radius,
                  ),
                  foregroundDecoration: border == null
                      ? null
                      : BoxDecoration(borderRadius: radius, border: border),
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            chosen?.label ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.text.copyWith(color: c.text),
                          ),
                        ),
                        const SizedBox(width: LgSpace.s3),
                        LgIcon(LgIcons.chevD, size: 20, color: c.text2),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
