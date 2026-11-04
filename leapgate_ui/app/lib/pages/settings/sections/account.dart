import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/settings_api.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_account.dart';
import '../../../widgets/lg_button.dart';
import '../../home/account/account.dart' show accountLetter, showLoginDialog;
import '../net_rows.dart';
import '../settings_registry.dart';

/// Item ids of this section.
const kAccountItemSignIn = 'sign-in';
const kAccountItemSignOut = 'sign-out';

/// 通用 › 账号 (02 §1.5.3), with M4's account model and login dialog. Coder B.
SettingsSection accountSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.account,
      title: l10n.settingsSectionAccount,
      visible: () => !appCore.account.disabled,
      items: () => [
        appCore.account.loggedIn
            ? SettingsItem(kAccountItemSignOut, l10n.accountSignOut)
            : SettingsItem(kAccountItemSignIn, l10n.accountSignIn,
                description: l10n.accountSignedOutNote),
      ],
      build: (context, ctx) => _AccountBody(ctx: ctx),
    );

class _AccountBody extends StatefulWidget {
  const _AccountBody({required this.ctx});

  final SettingsSectionContext ctx;

  @override
  State<_AccountBody> createState() => _AccountBodyState();
}

class _AccountBodyState extends State<_AccountBody> {
  String _api = '';

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(_AccountBody old) {
    super.didUpdateWidget(old);
    _read();
  }

  Future<void> _read() async {
    final api = (await settingsApi.serverSummary()).api;
    if (mounted && api != _api) setState(() => _api = api);
  }

  Future<void> _signOut(AppLocalizations l10n) async {
    final ok = await confirmInSettings(
      widget.ctx.overlays,
      title: l10n.accountSignOutTitle,
      body: l10n.accountSignOutBody,
      action: l10n.accountSignOut,
      cancel: l10n.homeCancel,
      danger: true,
    );
    if (ok) await appCore.account.logout();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final ctx = widget.ctx;
    final account = appCore.account;
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final user = account.user;
        if (account.signingOut) {
          return Text(l10n.accountSigningOut,
              style: t.text.copyWith(color: t.colors.text2));
        }
        if (user == null) {
          return NetRow(
            ctx: ctx,
            item: kAccountItemSignIn,
            name: l10n.settingsAccountSignedOut,
            description: l10n.accountSignedOutNote,
            control: LgButton(
              label: l10n.accountSignIn,
              kind: LgButtonKind.primary,
              onPressed: () => showLoginDialog(ctx.overlays),
            ),
          );
        }
        final name = user.displayNameOrName;
        return NetRow(
          ctx: ctx,
          item: kAccountItemSignOut,
          name: name,
          control: LgButton(
            label: l10n.accountSignOut,
            onPressed: () => _signOut(l10n),
          ),
          children: [
            Row(
              children: [
                LgPersonAvatar(initial: accountLetter(name)),
                const SizedBox(width: LgSpace.s3),
                Text('@${user.name}',
                    style: t.textS.copyWith(color: t.colors.text2)),
              ],
            ),
            if (_api.isNotEmpty)
              Text(l10n.settingsAccountServer(_api),
                  style: t.textS.copyWith(color: t.colors.text2)),
          ],
        );
      },
    );
  }
}
