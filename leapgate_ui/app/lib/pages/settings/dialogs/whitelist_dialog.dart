import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/settings/restrictions.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_banner.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_form_dialog.dart';

/// "IP 白名单" / "ID 白名单" (02 §1.6.5, upstream `changeWhiteList`, `changeIdWhiteList`): what
/// to store ([kWhitelistNone] after "清除" or with nothing left), null when cancelled.
Future<String?> showWhitelistDialog(
        TabOverlays overlays, AppLocalizations l10n,
        {required WhitelistKind kind, required String stored}) =>
    overlays.show<String>(
      null,
      (context, close) => LgDialogScrim(
        onEscape: () => close(null),
        child: _WhitelistDialog(
            overlays: overlays,
            l10n: l10n,
            kind: kind,
            stored: stored,
            close: close),
      ),
    );

class _WhitelistDialog extends StatefulWidget {
  const _WhitelistDialog(
      {required this.overlays,
      required this.l10n,
      required this.kind,
      required this.stored,
      required this.close});

  final TabOverlays overlays;
  final AppLocalizations l10n;
  final WhitelistKind kind;
  final String stored;
  final void Function(String?) close;

  @override
  State<_WhitelistDialog> createState() => _WhitelistDialogState();
}

class _WhitelistDialogState extends State<_WhitelistDialog> {
  late final _text = TextEditingController(text: whitelistText(widget.stored));
  late WhitelistCheck _check = checkWhitelist(widget.kind, _text.text);

  bool get _ip => widget.kind == WhitelistKind.ip;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Asked over the dialog (02 §3.5).
  Future<void> _clear() async {
    final l10n = widget.l10n;
    final ok = await widget.overlays.show<bool>(
          null,
          (context, close) => LgDialogScrim(
            onEscape: () => close(false),
            child: LgConfirmDialog(
              title: _ip
                  ? l10n.settingsRestrictClearIpTitle
                  : l10n.settingsRestrictClearIdTitle,
              actions: [
                LgDialogAction(
                    label: l10n.homeCancel, onPressed: () => close(false)),
                LgDialogAction(
                  label: l10n.settingsRestrictClear,
                  kind: LgButtonKind.dangerSolid,
                  isDefault: true,
                  onPressed: () => close(true),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok) widget.close(kWhitelistNone);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final title = _ip ? l10n.settingsRestrictIp : l10n.settingsRestrictId;
    return LgFormDialog(
      title: title,
      icon: LgIcons.shield,
      note: _ip ? l10n.settingsRestrictIpRule : l10n.settingsRestrictIdRule,
      banner: _check.valid
          ? null
          : LgBanner(
              tone: LgTone.error,
              slim: true,
              dense: true,
              text: [
                for (final line in _check.invalidLines)
                  l10n.settingsRestrictInvalidLine(line),
              ].join('\n'),
            ),
      leading: LgButton(
        label: l10n.settingsRestrictClear,
        kind: LgButtonKind.danger,
        onPressed: _clear,
      ),
      actions: [
        LgDialogAction(
            label: l10n.homeCancel, onPressed: () => widget.close(null)),
        LgDialogAction(
          label: l10n.homeOk,
          kind: LgButtonKind.primary,
          isDefault: true,
          onPressed: _check.valid ? () => widget.close(_check.value) : null,
        ),
      ],
      children: [
        LgFormField(
          label: title,
          hint: l10n.settingsRestrictCount(_check.entries.length),
          child: LgTextArea(
            controller: _text,
            height: 140,
            onChanged: (text) => setState(
                () => _check = checkWhitelist(widget.kind, text)),
          ),
        ),
      ],
    );
  }
}
