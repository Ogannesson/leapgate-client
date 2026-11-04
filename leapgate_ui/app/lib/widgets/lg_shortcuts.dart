// The shortcut list of the settings (02 §1.4.6, A-P6-设置.html ".kb-*", ".keyc",
// ".kst") and the dialog that records one: the operation, its combination in a
// monospace face ("未设置" when there is none), "修改", and "清除" when there is a
// binding; and a dialog with the keys being pressed in the middle, a line under
// them that says what is wrong or what will happen, and the buttons.
//
// They only draw. Which keys are pressed, what they mean, what clashes, are the
// page's; so is every text.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_feedback.dart';
import 'lg_form_dialog.dart';
import 'lg_settings_layout.dart';
import 'lg_settings_rows.dart';

/// A group of operations of the shortcut list (`.kb-g` with `.kb-b`): its name
/// above a white block of [LgShortcutRow]s. [disabled] dims all of it (the keys
/// are all sent to the remote device, so none of them is Leapgate's now).
class LgShortcutGroup extends StatelessWidget implements LgSettingsFlowPart {
  const LgShortcutGroup({
    super.key,
    required this.title,
    required this.rows,
    this.disabled = false,
  });

  final String title;
  final List<LgShortcutRow> rows;
  final bool disabled;

  @override
  LgSettingsFlow get flow => LgSettingsFlow.group;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: LgSpace.s1),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: t.textS.copyWith(
                color: t.colors.text2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: LgSpace.s2),
        LgSettingsBlock(disabled: disabled, children: rows),
      ],
    );
  }
}

/// An operation and its combination (`.kb-r`). [keys] are the keys of the
/// combination as they are written ("Ctrl", "Alt", "Shift", "→"); none means
/// "未设置" ([unsetLabel]) and no "清除". The button that edits is named for the
/// operation, so that a list of sixty "修改" is not sixty equal names.
class LgShortcutRow extends StatelessWidget {
  const LgShortcutRow({
    super.key,
    required this.action,
    required this.keys,
    required this.unsetLabel,
    required this.editLabel,
    required this.onEdit,
    required this.clearLabel,
    required this.onClear,
    this.editSemanticLabel,
    this.clearSemanticLabel,
    this.marked = false,
  });

  final String action;
  final List<String> keys;

  /// "未设置".
  final String unsetLabel;

  /// "修改".
  final String editLabel;
  final VoidCallback? onEdit;

  /// "清除".
  final String clearLabel;

  /// Clears the binding without asking; only shown when there is one.
  final VoidCallback? onClear;

  /// "修改快捷键：刷新画面".
  final String? editSemanticLabel;
  final String? clearSemanticLabel;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final bound = keys.isNotEmpty;
    return LgSettingsRowFrame(
      marked: marked,
      // A little air above and under the buttons in the detail mode, where the
      // row is not higher than they are.
      verticalPadding: 2,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: '$action, ${bound ? keys.join('+') : unsetLabel}',
        child: Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: LgSpace.s2),
                  child: Text(action, style: t.textM.copyWith(color: c.text)),
                ),
              ),
            ),
            const SizedBox(width: LgSpace.s3),
            ExcludeSemantics(
              child: bound
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (i, k) in keys.indexed) ...[
                          if (i > 0) const SizedBox(width: LgSpace.s1),
                          _KeyCap(k),
                        ],
                      ],
                    )
                  : Text(unsetLabel, style: t.textM.copyWith(color: c.text2)),
            ),
            const SizedBox(width: LgSpace.s3),
            LgButton(
              label: editLabel,
              semanticLabel: editSemanticLabel,
              horizontalPadding: LgSpace.s3,
              onPressed: onEdit,
            ),
            // The slot of "清除" stays when there is nothing to clear, so the
            // "修改" buttons of all rows stand in one column.
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 56),
              child: bound
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: LgButton(
                        label: clearLabel,
                        semanticLabel: clearSemanticLabel,
                        kind: LgButtonKind.text,
                        horizontalPadding: LgSpace.s3,
                        onPressed: onClear,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// A key of a combination in the list (`.k i`): small, monospace, on the
/// second surface.
class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Container(
      height: t.sizes.lhS + LgSpace.s1,
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(LgRadius.r6),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: LgTokens.monoStyle(
          t.sizes.fsS,
          t.sizes.lhS,
        ).copyWith(color: c.text),
      ),
    );
  }
}

// ---- recording dialog -----------------------------------------------------------

/// What the dialog says about what was pressed (02 §1.4.6).
enum LgShortcutRecordState {
  /// Nothing yet: "请按下组合键"; save is off.
  waiting,

  /// A key that cannot be a shortcut: shown in red, save is off.
  unsupported,

  /// No Ctrl, Alt or Shift in it: shown in red, save is off.
  missingModifier,

  /// Another operation has it: the line says which, and what replacing does;
  /// the main button reads "替换".
  conflict,

  /// Good to save: the combination alone, no line.
  valid,
}

/// The dialog that records a shortcut (`.sheet` with `.keyc`, `.kst`): the
/// title, a field in the middle that shows the keys held ([keys]; "—" while
/// there are none), the line [statusText], and "取消" with "保存" ("替换" when it
/// takes the keys from another operation). Put it in an [LgDialogScrim].
///
/// The keyboard is the page's: it listens for the keys, works out the
/// [state], and gives [keys] as they are written ("Ctrl", "Alt", "P"). The
/// dialog does not take Enter as an answer, since Enter may be the key being
/// recorded.
class LgShortcutRecordDialog extends StatelessWidget {
  const LgShortcutRecordDialog({
    super.key,
    required this.title,
    required this.state,
    required this.keys,
    required this.statusText,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.emptyKeysLabel = '—',
  });

  /// "设置快捷键：刷新画面".
  final String title;
  final LgShortcutRecordState state;
  final List<String> keys;

  /// The line under the keys: "请按下组合键", "“Caps Lock”不能用作快捷键",
  /// "组合键须包含 Ctrl、Alt 或 Shift", "已用于“截图”，替换后该操作将没有快捷键".
  /// Null for [LgShortcutRecordState.valid].
  final String? statusText;

  /// "取消".
  final String cancelLabel;

  /// "保存", or "替换" in [LgShortcutRecordState.conflict].
  final String confirmLabel;
  final VoidCallback? onCancel;

  /// Ignored (the button is off) while waiting, with an unsupported key or
  /// with no modifier.
  final VoidCallback? onConfirm;
  final String emptyKeysLabel;

  bool get _canConfirm =>
      state == LgShortcutRecordState.conflict ||
      state == LgShortcutRecordState.valid;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final bad =
        state == LgShortcutRecordState.unsupported ||
        state == LgShortcutRecordState.missingModifier;
    final ok =
        state == LgShortcutRecordState.conflict ||
        state == LgShortcutRecordState.valid;
    final body = <Widget>[
      const SizedBox(height: LgSpace.s4),
      Semantics(
        container: true,
        liveRegion: true,
        label: keys.isEmpty ? emptyKeysLabel : keys.join('+'),
        child: ExcludeSemantics(
          child: Container(
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(LgRadius.r12),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LgRadius.r12),
              border: Border.all(
                color: bad
                    ? c.error
                    : ok
                    ? c.accent
                    : c.borderStrong,
                width: bad || ok ? 2 : 1.5,
              ),
            ),
            child: keys.isEmpty
                ? Text(emptyKeysLabel, style: t.text.copyWith(color: c.text2))
                // A long combination ("Ctrl + Alt + Shift + Print Screen") gets
                // smaller rather than wider than the field.
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (i, k) in keys.indexed) ...[
                            if (i > 0) ...[
                              const SizedBox(width: LgSpace.s2),
                              Text('+', style: t.text.copyWith(color: c.text2)),
                              const SizedBox(width: LgSpace.s2),
                            ],
                            _RecordedKey(k),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: LgSpace.s3),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: t.sizes.lhM),
          child: Semantics(
            liveRegion: true,
            child: statusText == null
                ? null
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (bad || state == LgShortcutRecordState.conflict) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: LgIcon(
                            bad ? LgIcons.err : LgIcons.warn,
                            size: 16,
                            color: bad ? c.error : c.warning,
                          ),
                        ),
                        const SizedBox(width: LgSpace.s2),
                      ],
                      Expanded(
                        child: Text(
                          statusText!,
                          style: t.textM.copyWith(
                            color: bad ? c.error : c.text,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ];
    return LgFormDialog(
      title: title,
      icon: LgIcons.keyboard,
      width: 400,
      actions: [
        LgDialogAction(label: cancelLabel, onPressed: onCancel),
        LgDialogAction(
          label: confirmLabel,
          kind: LgButtonKind.primary,
          onPressed: _canConfirm ? onConfirm : null,
        ),
      ],
      children: body,
    );
  }
}

/// A key being held in the dialog (`.kc`): bigger than in the list, bold, on
/// the surface with a firm ring.
class _RecordedKey extends StatelessWidget {
  const _RecordedKey(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r10);
    return Container(
      constraints: const BoxConstraints(minWidth: 36),
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.surface, borderRadius: radius),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: c.borderStrong, width: 1.5),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: t.text.copyWith(color: c.text, fontWeight: FontWeight.w700),
      ),
    );
  }
}
