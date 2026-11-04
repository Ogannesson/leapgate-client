import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/navigation.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_password_row.dart';

/// The password row of this device (01 P1 block A): label, content, the note when both
/// passwords work, "Copy" and "Refresh" while there is a one-time password, "Change" for the
/// permanent one ([onChange] null hides it), and under it the link "更多访问设置" to 传入连接 ›
/// 访问与密码 (02 §1.2.1).
class PasswordRowView extends StatelessWidget {
  const PasswordRowView({super.key, required this.status, this.onChange});

  final LocalStatusModel status;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(l10n),
        // A text button until designer's link (`.lnk-row` in A-P1.html).
        LgButton(
          label: l10n.settingsAccessMore,
          kind: LgButtonKind.text,
          onPressed: () => mainNavigation.showSettings(SettingsSectionId.access),
        ),
      ],
    );
  }

  Widget _row(AppLocalizations l10n) {
    final password = status.oneTimePassword;
    final row = status.passwordRow;
    if ((row == PasswordRow.oneTime || row == PasswordRow.both) &&
        password.isEmpty) {
      return LgPasswordRow(
        label: l10n.homeOneTimePassword,
        value: l10n.idGenerating,
        dim: true,
      );
    }
    return switch (row) {
      PasswordRow.oneTime || PasswordRow.both => LgPasswordRow(
        label: l10n.homeOneTimePassword,
        value: password,
        style: LgPasswordValue.code,
        note: row == PasswordRow.both ? l10n.homeAlsoPermanentPassword : null,
        onCopy: () => copyWithToast(password),
        copyLabel: l10n.homeCopy,
        copySemanticLabel: l10n.homeCopyPassword,
        actions: [
          LgButton(
            label: l10n.homeRefresh,
            semanticLabel: l10n.homeRefreshPassword,
            icon: LgIcons.refresh,
            kind: LgButtonKind.text,
            onPressed: status.refreshOneTimePassword,
          ),
        ],
      ),
      PasswordRow.permanent => LgPasswordRow(
        label: l10n.homePermanentPassword,
        value: l10n.homePasswordSet,
        actions: [
          if (onChange != null)
            LgButton(
              label: l10n.homeChange,
              semanticLabel: l10n.homeChangePassword,
              icon: LgIcons.edit,
              kind: LgButtonKind.text,
              onPressed: onChange,
            ),
        ],
      ),
      PasswordRow.acceptOnly => LgPasswordRow(
        label: l10n.homeApprovalMode,
        value: l10n.homeAcceptOnThisDevice,
        style: LgPasswordValue.sentence,
      ),
      PasswordRow.unavailable => LgPasswordRow(
        label: l10n.homeOneTimePassword,
        value: l10n.homePasswordUnavailable,
        dim: true,
      ),
    };
  }
}

/// "Copy" of this device's ID and password (01 P1 block A).
Future<void> copyWithToast(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  // Upstream's translation key; the app's toast host shows "已复制".
  appCore.toasts.show('Copied');
}
