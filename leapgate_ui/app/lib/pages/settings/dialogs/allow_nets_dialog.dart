import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/settings/exit_settings.dart';
import 'package:flutter_hbb/leapgate/settings/settings_api.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_form_dialog.dart';
import '../../../widgets/lg_text_field.dart';
import '../net_rows.dart';

/// "放行的网段" (02 §1.6.6): what to store in `leapgate-exit-allow-nets` (empty after "清除"),
/// null when cancelled. Rust checks each line as typed (E5).
Future<String?> showAllowNetsDialog(
        TabOverlays overlays, AppLocalizations l10n,
        {required String stored}) =>
    overlays.show<String>(
      null,
      (context, close) => LgDialogScrim(
        onEscape: () => close(null),
        child: _AllowNetsDialog(
            overlays: overlays, l10n: l10n, stored: stored, close: close),
      ),
    );

class _AllowNetsDialog extends StatefulWidget {
  const _AllowNetsDialog(
      {required this.overlays,
      required this.l10n,
      required this.stored,
      required this.close});

  final TabOverlays overlays;
  final AppLocalizations l10n;
  final String stored;
  final void Function(String?) close;

  @override
  State<_AllowNetsDialog> createState() => _AllowNetsDialogState();
}

class _AllowNetsDialogState extends State<_AllowNetsDialog> {
  late final _text = TextEditingController(text: allowNetsText(widget.stored));
  late AllowNetsCheck _check = settingsApi.allowNetsCheck(_text.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _clear() async {
    final l10n = widget.l10n;
    final ok = await confirmInSettings(
      widget.overlays,
      title: l10n.settingsExitNetsClearTitle,
      action: l10n.settingsExitNetsClear,
      cancel: l10n.homeCancel,
      danger: true,
    );
    if (ok) widget.close('');
  }

  void _submit() {
    if (_check.valid) widget.close(_check.value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final t = LgTokens.of(context);
    final lines = _check.lines.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return LgFormDialog(
      title: l10n.settingsExitNets,
      icon: LgIcons.exit,
      note: l10n.settingsExitNetsRule,
      actions: [
        LgDialogAction(label: l10n.settingsExitNetsClear, onPressed: _clear),
        LgDialogAction(
            label: l10n.homeCancel, onPressed: () => widget.close(null)),
        LgDialogAction(
          label: l10n.homeOk,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: _check.valid ? _submit : null,
        ),
      ],
      children: [
        LgFormField(
          label: l10n.settingsExitNets,
          hint: l10n.settingsExitNetsDnsNote,
          child: LgTextArea(
            controller: _text,
            height: 140,
            onChanged: (text) =>
                setState(() => _check = settingsApi.allowNetsCheck(text)),
          ),
        ),
        for (final MapEntry(key: line, value: state) in lines)
          Padding(
            padding: const EdgeInsets.only(top: LgSpace.s1),
            child: state == NetLineState.invalid
                ? LgFieldError(l10n.settingsExitNetsInvalidLine(line))
                : Text(l10n.settingsExitNetsBlockedLine(line),
                    style: t.textS.copyWith(color: t.colors.warning)),
          ),
      ],
    );
  }
}
