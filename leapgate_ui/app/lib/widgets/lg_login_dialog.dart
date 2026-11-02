// The login dialog (01 §3.1 block K; `p1-dlg-login*` in A-P1.html): a user
// name, a password and the buttons. What can go wrong has its own place: a word
// under the field it is about (no user name, no password, the server's answer
// under the password), and a banner with "重试" when the login options could not
// be fetched, which leaves the form greyed.
//
// Only drawing: the controllers and the texts are the caller's. Put it in an
// `LgDialogScrim` over the home page.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import 'lg_banner.dart';
import 'lg_button.dart';
import 'lg_feedback.dart';
import 'lg_form_dialog.dart';
import 'lg_panel_inputs.dart';
import 'lg_text_field.dart';

/// The words of the login dialog, localised by the caller.
class LgLoginDialogLabels {
  const LgLoginDialogLabels({
    required this.title,
    required this.usernameLabel,
    required this.usernamePlaceholder,
    required this.passwordLabel,
    required this.passwordPlaceholder,
    required this.showPassword,
    required this.hidePassword,
    required this.cancel,
    required this.submit,
    required this.busySubmit,
    required this.retry,
  });

  /// "登录".
  final String title;
  final String usernameLabel;
  final String usernamePlaceholder;
  final String passwordLabel;
  final String passwordPlaceholder;

  /// Names of the eye button in its two states.
  final String showPassword;
  final String hidePassword;
  final String cancel;

  /// "登录"; while [LgLoginDialog.busy] the button says [busySubmit] instead
  /// ("正在登录…").
  final String submit;
  final String busySubmit;

  /// "重试", in the banner of [LgLoginDialog.loadError].
  final String retry;
}

class LgLoginDialog extends StatelessWidget {
  const LgLoginDialog({
    super.key,
    required this.labels,
    required this.usernameController,
    required this.passwordController,
    required this.onSubmit,
    required this.onCancel,
    this.usernameError,
    this.passwordError,
    this.loadError,
    this.onRetry,
    this.busy = false,
    this.usernameFocus,
    this.passwordFocus,
    this.onChanged,
    this.width = 400,
    this.maxLength,
  }) : assert(loadError == null || onRetry != null);

  final LgLoginDialogLabels labels;
  final TextEditingController usernameController;
  final TextEditingController passwordController;

  /// Under the user name ("请输入用户名").
  final String? usernameError;

  /// Under the password ("请输入密码", or the server's answer).
  final String? passwordError;

  /// "无法获取登录选项。请检查网络连接。": a banner under the title with "重试"; the
  /// fields and "登录" are greyed until it is gone.
  final String? loadError;
  final VoidCallback? onRetry;

  /// The login request is on its way: the fields are greyed and "登录" turns.
  final bool busy;

  /// Enter in a field does the same as the button.
  final VoidCallback? onSubmit;
  final VoidCallback onCancel;
  final FocusNode? usernameFocus;
  final FocusNode? passwordFocus;

  /// Both fields call it when their text changes.
  final ValueChanged<String>? onChanged;
  final double width;

  /// Longest user name and password the two fields take.
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final inputsOn = !busy && loadError == null;
    return LgFormDialog(
      title: labels.title,
      icon: LgIcons.user,
      width: width,
      banner: loadError == null
          ? null
          : LgBanner(
              tone: LgTone.error,
              slim: true,
              text: loadError,
              actionLabel: labels.retry,
              actionIcon: LgIcons.refresh,
              onAction: onRetry,
            ),
      actions: [
        LgDialogAction(label: labels.cancel, onPressed: onCancel),
        LgDialogAction(
          label: busy ? labels.busySubmit : labels.submit,
          kind: LgButtonKind.primary,
          isDefault: true,
          busy: busy,
          onPressed: loadError == null ? onSubmit : null,
        ),
      ],
      children: [
        LgFormField(
          label: labels.usernameLabel,
          child: LgTextField(
            controller: usernameController,
            focusNode: usernameFocus,
            placeholder: labels.usernamePlaceholder,
            semanticLabel: labels.usernameLabel,
            errorText: usernameError,
            enabled: inputsOn,
            autofocus: usernameController.text.isEmpty,
            onChanged: onChanged,
            maxLength: maxLength,
          ),
        ),
        LgFormField(
          label: labels.passwordLabel,
          child: LgPasswordField(
            controller: passwordController,
            focusNode: passwordFocus,
            placeholder: labels.passwordPlaceholder,
            semanticLabel: labels.passwordLabel,
            showLabel: labels.showPassword,
            hideLabel: labels.hidePassword,
            errorText: passwordError,
            enabled: inputsOn,
            autofocus: usernameController.text.isNotEmpty,
            onChanged: onChanged,
            maxLength: maxLength,
          ),
        ),
      ],
    );
  }
}
