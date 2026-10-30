import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';

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
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    this.semanticLabel,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final String? errorText;
  final bool enabled;
  final bool obscureText;
  final bool autofocus;

  /// Widget at the right end, e.g. the show-password button.
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? semanticLabel;

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
    final textStyle = widget.obscureText
        // `.mask`: dots at the number size, spaced .14em.
        ? t.textN.copyWith(color: c.text, letterSpacing: t.sizes.fsN * .14)
        : t.text.copyWith(color: c.text);
    final field = Container(
      height: t.sizes.main,
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
      decoration: BoxDecoration(
        color: widget.enabled ? c.surface : c.disabled,
        borderRadius: radius,
      ),
      foregroundDecoration: border == null
          ? null
          : BoxDecoration(borderRadius: radius, border: border),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _node,
              enabled: widget.enabled,
              obscureText: widget.obscureText,
              obscuringCharacter: '•',
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: textStyle,
              cursorColor: c.accent,
              cursorWidth: 2,
              maxLines: 1,
              decoration: InputDecoration.collapsed(
                hintText: widget.placeholder,
                hintStyle: t.text.copyWith(
                  color: c.text2,
                  overflow: TextOverflow.ellipsis,
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
    if (!error) return Semantics(label: widget.semanticLabel, child: field);
    return Semantics(
      label: widget.semanticLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          const SizedBox(height: LgSpace.s2),
          // `.ferr`
          DefaultTextStyle(
            style: t.textS.copyWith(
              color: c.error,
              fontWeight: FontWeight.w700,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: LgIcon(LgIcons.err, size: 16, color: c.error),
                ),
                const SizedBox(width: LgSpace.s2),
                Expanded(child: Text(widget.errorText!)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
