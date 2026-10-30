import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_button.dart';

/// The password row of this device (01 P1 block A): label, content, the note when both
/// passwords work, "Copy" while there is a one-time password to copy. "Refresh" and "Change"
/// come with M2b. A placeholder until the designer's `LgPasswordRow` (M2a integration).
class PasswordRowView extends StatelessWidget {
  const PasswordRowView({super.key, required this.status});

  final LocalStatusModel status;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final l10n = AppLocalizations.of(context)!;
    final row = status.passwordRow;
    final password = status.oneTimePassword;
    final showsPassword = row == PasswordRow.oneTime || row == PasswordRow.both;
    final label = switch (row) {
      PasswordRow.permanent => l10n.homePermanentPassword,
      PasswordRow.acceptOnly => l10n.homeApprovalMode,
      _ => l10n.homeOneTimePassword,
    };
    final content = switch (row) {
      PasswordRow.permanent => l10n.homePasswordSet,
      PasswordRow.acceptOnly => l10n.homeAcceptOnThisDevice,
      PasswordRow.unavailable => l10n.homePasswordUnavailable,
      _ => password.isEmpty ? l10n.idGenerating : password,
    };
    final dim =
        row == PasswordRow.permanent || row == PasswordRow.unavailable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.textS.copyWith(color: c.text2)),
        Row(
          children: [
            Expanded(
              child: Text(
                content,
                style: t.textM.copyWith(
                  color: dim ? c.text2 : c.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (showsPassword && password.isNotEmpty)
              LgButton(
                label: l10n.homeCopy,
                kind: LgButtonKind.text,
                onPressed: () => copyWithToast(password),
              ),
          ],
        ),
        if (row == PasswordRow.both)
          Text(
            l10n.homeAlsoPermanentPassword,
            style: t.textS.copyWith(color: c.text2),
          ),
      ],
    );
  }

}

/// "Copy" of this device's ID and password (01 P1 block A).
Future<void> copyWithToast(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  // Upstream's translation key; the app's toast host shows "已复制".
  appCore.toasts.show('Copied');
}
