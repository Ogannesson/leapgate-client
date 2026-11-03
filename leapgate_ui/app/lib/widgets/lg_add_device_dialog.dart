// The dialog that adds a device to an address book (01 §3.1 block G;
// `p1-dlg-add*` in A-P1.html): ID (the only required field), alias, password
// (only in a shared book), note (up to 300 characters) and the book's tags to
// pick from. What went wrong has its own place: "该 ID 已在此地址簿中" under the
// ID, and a banner under the title for "已达到此地址簿的设备数量上限" and for
// the server's own answer. The dialog stays open on every error.
//
// Only drawing: the controllers and the texts are the caller's. Put it in an
// `LgDialogScrim` over the home page.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import 'lg_banner.dart';
import 'lg_button.dart';
import 'lg_feedback.dart';
import 'lg_form_dialog.dart';
import 'lg_panel_inputs.dart';
import 'lg_tag_chips.dart';
import 'lg_text_field.dart';

/// The words of the dialog, localised by the caller.
class LgAddDeviceLabels {
  const LgAddDeviceLabels({
    required this.title,
    required this.idLabel,
    required this.idPlaceholder,
    required this.aliasLabel,
    required this.aliasPlaceholder,
    required this.passwordLabel,
    required this.passwordPlaceholder,
    required this.showPassword,
    required this.hidePassword,
    required this.noteLabel,
    required this.notePlaceholder,
    required this.tagsLabel,
    required this.cancel,
    required this.submit,
    required this.busySubmit,
  });

  /// "添加设备".
  final String title;
  final String idLabel;
  final String idPlaceholder;
  final String aliasLabel;
  final String aliasPlaceholder;
  final String passwordLabel;
  final String passwordPlaceholder;

  /// Names of the eye button in its two states.
  final String showPassword;
  final String hidePassword;
  final String noteLabel;
  final String notePlaceholder;

  /// Name of the group of tags ("标签").
  final String tagsLabel;
  final String cancel;

  /// "添加"; while [LgAddDeviceDialog.busy] the button says [busySubmit]
  /// ("正在添加…").
  final String submit;
  final String busySubmit;
}

class LgAddDeviceDialog extends StatelessWidget {
  const LgAddDeviceDialog({
    super.key,
    required this.labels,
    required this.idController,
    required this.aliasController,
    required this.noteController,
    required this.onSubmit,
    required this.onCancel,
    this.passwordController,
    this.passwordHint,
    this.target,
    this.tags = const [],
    this.onToggleTag,
    this.idError,
    this.error,
    this.busy = false,
    this.idFocus,
    this.idInputFormatters = const [],
    this.noteMax = 300,
    this.width = 480,
  }) : assert(passwordController == null || passwordHint != null);

  final LgAddDeviceLabels labels;
  final TextEditingController idController;
  final TextEditingController aliasController;
  final TextEditingController noteController;

  /// Present in a shared book only: the password field, with [passwordHint]
  /// ("这些内容对此地址簿的其他成员可见") under it.
  final TextEditingController? passwordController;
  final String? passwordHint;

  /// Where the device goes ("添加到：家里的电脑").
  final String? target;

  /// The tags of the book; none leaves the group out.
  final List<LgTagToggleItem> tags;
  final ValueChanged<String>? onToggleTag;

  /// Under the ID ("该 ID 已在此地址簿中").
  final String? idError;

  /// In a banner under [target] ("已达到此地址簿的设备数量上限", or "无法添加设备。
  /// 服务器返回：…。").
  final String? error;

  /// The request is on its way: everything is greyed and "添加" turns.
  final bool busy;

  /// Null greys "添加" (nothing in the ID field yet). Enter in a one-line field
  /// does the same as the button.
  final VoidCallback? onSubmit;
  final VoidCallback onCancel;
  final FocusNode? idFocus;

  /// Run on the ID as it is typed: the caller's grouping of its digits.
  final List<TextInputFormatter> idInputFormatters;

  /// The most the note can have; shown as "0 / 300" at its label.
  final int noteMax;
  final double width;

  @override
  Widget build(BuildContext context) {
    final on = !busy;
    return LgFormDialog(
      title: labels.title,
      icon: LgIcons.plus,
      note: target,
      width: width,
      banner: error == null
          ? null
          : LgBanner(tone: LgTone.error, slim: true, text: error),
      actions: [
        LgDialogAction(label: labels.cancel, onPressed: onCancel),
        LgDialogAction(
          label: busy ? labels.busySubmit : labels.submit,
          kind: LgButtonKind.primary,
          isDefault: true,
          busy: busy,
          onPressed: onSubmit,
        ),
      ],
      children: [
        LgFormField(
          label: labels.idLabel,
          required: true,
          child: LgTextField(
            controller: idController,
            focusNode: idFocus,
            placeholder: labels.idPlaceholder,
            semanticLabel: labels.idLabel,
            errorText: idError,
            enabled: on,
            autofocus: true,
            inputFormatters: idInputFormatters,
          ),
        ),
        LgFormField(
          label: labels.aliasLabel,
          child: LgTextField(
            controller: aliasController,
            placeholder: labels.aliasPlaceholder,
            semanticLabel: labels.aliasLabel,
            enabled: on,
          ),
        ),
        if (passwordController != null)
          LgFormField(
            label: labels.passwordLabel,
            hint: passwordHint,
            child: LgPasswordField(
              controller: passwordController!,
              placeholder: labels.passwordPlaceholder,
              semanticLabel: labels.passwordLabel,
              showLabel: labels.showPassword,
              hideLabel: labels.hidePassword,
              enabled: on,
            ),
          ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: noteController,
          builder: (context, value, _) => LgFormField(
            label: labels.noteLabel,
            counter: '${value.text.characters.length} / $noteMax',
            child: LgTextArea(
              controller: noteController,
              placeholder: labels.notePlaceholder,
              semanticLabel: labels.noteLabel,
              maxLength: noteMax,
              enabled: on,
            ),
          ),
        ),
        if (tags.isNotEmpty)
          LgFormField(
            label: labels.tagsLabel,
            child: LgTagChooser(
              items: tags,
              semanticLabel: labels.tagsLabel,
              onToggle: on ? onToggleTag : null,
            ),
          ),
      ],
    );
  }
}
