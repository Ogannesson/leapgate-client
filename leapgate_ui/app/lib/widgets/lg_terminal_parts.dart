// Two more parts of the terminal view (13 §2.2, R3-Q10; `.cbn` and the admin account of the
// connection panel in `A-P9-终端.html`): the request of an application in the remote terminal to
// write to this computer's clipboard, and the system account an administrator terminal asks for
// in the connection panel.
//
// Only draw: the texts, the controllers and the callbacks are the caller's (`LEAPGATE.md` §10.18).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_panel_inputs.dart';
import 'lg_text_field.dart';

/// "远程终端中的应用请求写入本机剪贴板。……" with "拒绝" and "允许" (`.cbn`): a card of the float
/// ground with a shadow (in the dark theme a 1 px ring), 12 px from the top and the sides of the
/// area it lies over. It does not push the terminal down: put it in a `Stack` over
/// the terminal, at the top (`Positioned(top: 0, left: 0, right: 0, child: …)`; the 12 px
/// margin is inside it). The text may take two lines in a narrow window.
///
/// The buttons are the ordinary 36 px ones; the group is named [semanticLabel] ("剪贴板写入请求"),
/// a live region so that a reader says it when it appears.
class LgClipboardRequest extends StatelessWidget {
  const LgClipboardRequest({
    super.key,
    required this.text,
    required this.allowLabel,
    required this.denyLabel,
    required this.onAllow,
    required this.onDeny,
    this.semanticLabel,
  });

  final String text;

  /// "允许".
  final String allowLabel;

  /// "拒绝".
  final String denyLabel;
  final VoidCallback onAllow;
  final VoidCallback onDeny;

  /// "剪贴板写入请求".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final dark = c.shadow.length == 1;
    return Padding(
      padding: const EdgeInsets.all(LgSpace.s3),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        liveRegion: true,
        label: semanticLabel,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            LgSpace.s4,
            LgSpace.s3,
            LgSpace.s3,
            LgSpace.s3,
          ),
          decoration: BoxDecoration(
            color: c.float,
            borderRadius: BorderRadius.circular(LgRadius.r16),
            // `.frame.lg-dark .cbn`: a ring of the strong border instead of the shadow.
            boxShadow: dark
                ? [BoxShadow(color: c.borderStrong, spreadRadius: 1)]
                : c.shadow,
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: LgIcon(LgIcons.clipboard, size: 22, color: c.accent),
              ),
              const SizedBox(width: LgSpace.s3),
              Expanded(
                child: Text(text, style: t.textM.copyWith(color: c.text)),
              ),
              const SizedBox(width: LgSpace.s3),
              LgButton(
                label: denyLabel,
                horizontalPadding: LgSpace.s4,
                onPressed: onDeny,
              ),
              const SizedBox(width: LgSpace.s3),
              LgButton(
                label: allowLabel,
                kind: LgButtonKind.primary,
                horizontalPadding: LgSpace.s4,
                onPressed: onAllow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The system account an administrator terminal asks for, as the inputs of the connection panel
/// (`.sub2` with two `.field`s): a heading, the line under it, the user name and the password.
///
/// Two cases (13 §2.2.1): the connection needs no password, so the account is all that is asked
/// ([withRule] false), or it needs both, and a thin rule sets the account off from the connection
/// password and "记住密码" above it ([withRule] true). Put it in
/// [LgConnectionPanel.inputs], last. The vertical gaps make up what the panel puts between its
/// inputs (14 first, 16 after) to the mockup's 28 under the steps and 20 under the rule.
///
/// [autofocus] takes the keyboard for the user name when the section appears; a section asked
/// for again after a failure keeps it off the field the user may be typing in.
class LgAdminAccountInputs extends StatelessWidget {
  const LgAdminAccountInputs({
    super.key,
    required this.title,
    required this.userController,
    required this.passwordController,
    required this.userLabel,
    required this.passwordLabel,
    required this.showLabel,
    required this.hideLabel,
    this.description,
    this.withRule = false,
    this.autofocus = false,
    this.userFocusNode,
    this.passwordFocusNode,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
  });

  /// "远程设备上的管理员账户".
  final String title;

  /// "终端将以 SYSTEM 账户运行".
  final String? description;
  final TextEditingController userController;
  final TextEditingController passwordController;

  /// "系统用户名": the placeholder and the name of the field.
  final String userLabel;

  /// "系统密码": the placeholder and the name of the field.
  final String passwordLabel;

  /// Names of the show and hide buttons of the password.
  final String showLabel;
  final String hideLabel;
  final bool withRule;
  final bool autofocus;
  final FocusNode? userFocusNode;
  final FocusNode? passwordFocusNode;
  final ValueChanged<String>? onChanged;

  /// Enter in the password field; Enter in the user name field moves on to the password.
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  /// From the user name to the password.
  void _moveOn(BuildContext context) {
    final next = passwordFocusNode;
    if (next != null) {
      next.requestFocus();
    } else {
      FocusScope.of(context).nextFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (withRule) ...[
            // 16 from the panel and 4 here make the 20 above the rule; 20 below it.
            const SizedBox(height: LgSpace.s1),
            Container(height: 1, color: c.border),
            const SizedBox(height: LgSpace.s5),
          ] else
            // 14 from the panel and 14 here: the 28 of a heading under the steps.
            const SizedBox(height: 14),
          ExcludeSemantics(
            child: Text(
              title,
              style: t.textN.copyWith(
                color: c.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: LgSpace.s1),
              child: Text(
                description!,
                style: t.textS.copyWith(color: c.text2),
              ),
            ),
          const SizedBox(height: 14),
          // Enter in the user name moves on here, before a default button around the panel
          // (`LgDefaultEnter`) takes it and signs in with an empty password.
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (node, event) {
              final key = event.logicalKey;
              if (key != LogicalKeyboardKey.enter &&
                  key != LogicalKeyboardKey.numpadEnter) {
                return KeyEventResult.ignored;
              }
              if (event is KeyDownEvent) _moveOn(context);
              return KeyEventResult.handled;
            },
            child: LgTextField(
              controller: userController,
              focusNode: userFocusNode,
              placeholder: userLabel,
              semanticLabel: userLabel,
              enabled: enabled,
              autofocus: autofocus,
              onChanged: onChanged,
              onSubmitted: (_) => _moveOn(context),
            ),
          ),
          const SizedBox(height: 14),
          LgPasswordField(
            controller: passwordController,
            focusNode: passwordFocusNode,
            placeholder: passwordLabel,
            semanticLabel: passwordLabel,
            showLabel: showLabel,
            hideLabel: hideLabel,
            enabled: enabled,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ],
      ),
    );
  }
}
