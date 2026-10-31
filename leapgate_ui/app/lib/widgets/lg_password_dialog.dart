// The dialog that sets the fixed password of this computer (01 §4.4 and
// block K; `p1-dlg-pw-*` in A-P1.html): two fields, how strong the password
// is, the rules it has to meet one by one, an error if there is one and the
// buttons. Put it in an `LgDialogScrim` like the other confirmations.
//
// It only draws. The text lives in the controllers of the caller, which also
// decides what the rules are, how many of the four bars are on, and when
// "确定" may be pressed.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_banner.dart';
import 'lg_button.dart';
import 'lg_default_enter.dart';
import 'lg_panel_inputs.dart';

/// One rule of the password and whether it is met now.
class LgPasswordRule {
  const LgPasswordRule(this.label, this.met);

  final String label;
  final bool met;
}

/// The words of the dialog, localised by the caller.
class LgPasswordDialogLabels {
  const LgPasswordDialogLabels({
    required this.title,
    required this.passwordLabel,
    required this.passwordPlaceholder,
    required this.confirmLabel,
    required this.confirmPlaceholder,
    required this.showPassword,
    required this.hidePassword,
    required this.strength,
    required this.ruleMet,
    required this.ruleUnmet,
    required this.cancel,
    required this.confirm,
    this.remove,
  });

  /// "设置固定密码".
  final String title;
  final String passwordLabel;
  final String passwordPlaceholder;
  final String confirmLabel;
  final String confirmPlaceholder;

  /// Names of the eye button in its two states.
  final String showPassword;
  final String hidePassword;

  /// Name of the strength bar for a screen reader ("密码强度").
  final String strength;

  /// What a screen reader says after a rule: "已满足" / "未满足".
  final String ruleMet;
  final String ruleUnmet;
  final String cancel;
  final String confirm;

  /// "移除"; the button shows when [LgPasswordDialog.onRemove] is given.
  final String? remove;
}

class LgPasswordDialog extends StatelessWidget {
  const LgPasswordDialog({
    super.key,
    required this.labels,
    required this.passwordController,
    required this.confirmController,
    required this.rules,
    required this.strength,
    required this.onCancel,
    required this.onConfirm,
    this.note,
    this.error,
    this.confirmError,
    this.onChanged,
    this.onRemove,
    this.passwordFocus,
    this.confirmFocus,
    this.width = 440,
  });

  final LgPasswordDialogLabels labels;
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final List<LgPasswordRule> rules;

  /// How many of the four bars are on, 0 to 4.
  final int strength;

  /// A line under the title ("已设置的密码不会显示").
  final String? note;

  /// Why saving failed, in a banner under the title.
  final String? error;

  /// Under the second field ("两次输入的密码不一致").
  final String? confirmError;

  /// Both fields call it when their text changes.
  final ValueChanged<String>? onChanged;
  final VoidCallback onCancel;

  /// Null greys "确定". The mockup greys it only while both fields are empty;
  /// once there is text it can be pressed, and a password that does not meet
  /// the rules or does not match the second field is answered with [error] or
  /// [confirmError]. Enter does the same as the button.
  final VoidCallback? onConfirm;

  /// Shows "移除" at the left end of the buttons; [LgPasswordDialogLabels.remove]
  /// must then be given.
  final VoidCallback? onRemove;
  final FocusNode? passwordFocus;
  final FocusNode? confirmFocus;
  final double width;

  @override
  Widget build(BuildContext context) {
    assert(
      onRemove == null || labels.remove != null,
      'LgPasswordDialog: onRemove needs labels.remove ("移除").',
    );
    final t = LgTokens.of(context);
    final c = t.colors;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: LgSpace.s4, bottom: LgSpace.s1),
      child: Text(
        text,
        style: t.textS.copyWith(color: c.text2, fontWeight: FontWeight.w700),
      ),
    );

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: labels.title,
      child: LgDefaultEnter(
        onEnter: onConfirm,
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
                        child: LgIcon(LgIcons.key, size: 24, color: c.text2),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            labels.title,
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
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: LgSpace.s4),
                      child: LgBanner(tone: LgTone.error, text: error),
                    ),
                  label(labels.passwordLabel),
                  LgPasswordField(
                    controller: passwordController,
                    focusNode: passwordFocus,
                    placeholder: labels.passwordPlaceholder,
                    semanticLabel: labels.passwordLabel,
                    showLabel: labels.showPassword,
                    hideLabel: labels.hidePassword,
                    autofocus: true,
                    onChanged: onChanged,
                  ),
                  _Strength(
                    on: strength.clamp(0, 4),
                    label: labels.strength,
                  ),
                  _Rules(rules: rules, labels: labels),
                  label(labels.confirmLabel),
                  LgPasswordField(
                    controller: confirmController,
                    focusNode: confirmFocus,
                    placeholder: labels.confirmPlaceholder,
                    semanticLabel: labels.confirmLabel,
                    showLabel: labels.showPassword,
                    hideLabel: labels.hidePassword,
                    errorText: confirmError,
                    onChanged: onChanged,
                  ),
                  const SizedBox(height: LgSpace.s6),
                  Row(
                    children: [
                      if (onRemove != null)
                        LgButton(
                          label: labels.remove!,
                          kind: LgButtonKind.danger,
                          onPressed: onRemove,
                        ),
                      const Spacer(),
                      LgButton(label: labels.cancel, onPressed: onCancel),
                      const SizedBox(width: LgSpace.s3),
                      LgButton(
                        label: labels.confirm,
                        kind: LgButtonKind.primary,
                        onPressed: onConfirm,
                      ),
                    ],
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

/// Four bars under the first field (`.sbar`): as many as the password is
/// strong are in the accent colour.
class _Strength extends StatelessWidget {
  const _Strength({required this.on, required this.label});

  final int on;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return Semantics(
      label: label,
      value: '$on / 4',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: LgSpace.s2),
          child: Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: LgSpace.s1),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < on ? c.accent : c.track,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The rules in two columns (`.rules`): a ring while a rule is not met, a
/// green check once it is. The state is also in the words a screen reader gets.
class _Rules extends StatelessWidget {
  const _Rules({required this.rules, required this.labels});

  final List<LgPasswordRule> rules;
  final LgPasswordDialogLabels labels;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    Widget rule(LgPasswordRule r) {
      final color = r.met ? c.online : c.text2;
      return Semantics(
        label: '${r.label}, ${r.met ? labels.ruleMet : labels.ruleUnmet}',
        child: ExcludeSemantics(
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Center(
                  child: LgIcon(
                    r.met ? LgIcons.checkCircle : LgIcons.markRing,
                    size: r.met ? 16 : 12,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: LgSpace.s2),
              Expanded(
                child: Text(r.label, style: t.textS.copyWith(color: color)),
              ),
            ],
          ),
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < rules.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : LgSpace.s2),
          child: Row(
            children: [
              Expanded(child: rule(rules[i])),
              const SizedBox(width: LgSpace.s4),
              Expanded(
                child: i + 1 < rules.length
                    ? rule(rules[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: LgSpace.s3),
      child: Column(children: rows),
    );
  }
}
