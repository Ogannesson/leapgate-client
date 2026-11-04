import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/settings_api.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_account.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../../home/account/account.dart' show accountLetter, showLoginDialog;
import '../settings_flow.dart';
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
    final ok = await widget.ctx.overlays.show<bool>(
          null,
          (context, close) => LgDialogScrim(
            onEscape: () => close(false),
            child: LgConfirmDialog(
              title: l10n.accountSignOutTitle,
              body: l10n.accountSignOutBody,
              actions: [
                LgDialogAction(
                    label: l10n.homeCancel, onPressed: () => close(false)),
                LgDialogAction(
                  label: l10n.accountSignOut,
                  kind: LgButtonKind.dangerSolid,
                  isDefault: true,
                  onPressed: () => close(true),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok) await appCore.account.logout();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final c = t.colors;
    final ctx = widget.ctx;
    final account = appCore.account;
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final user = account.user;
        final item = user == null ? kAccountItemSignIn : kAccountItemSignOut;
        final Widget lead;
        final List<Widget> lines;
        LgButton? action;
        if (account.signingOut) {
          lead = const _Tile();
          lines = [
            Text(l10n.accountSigningOut,
                style: t.text.copyWith(color: c.text2)),
          ];
        } else if (user == null) {
          lead = const _Tile();
          lines = [
            Text(l10n.settingsAccountSignedOut,
                style: t.text.copyWith(color: c.text)),
            Text(l10n.accountSignedOutNote,
                style: t.textS.copyWith(color: c.text2)),
          ];
          action = LgButton(
            label: l10n.accountSignIn,
            kind: LgButtonKind.primary,
            onPressed: () => showLoginDialog(ctx.overlays),
          );
        } else {
          final name = user.displayNameOrName;
          lead = LgPersonAvatar(initial: accountLetter(name), size: 40);
          lines = [
            Text(name,
                style: t.text
                    .copyWith(color: c.text, fontWeight: FontWeight.w700)),
            Text('@${user.name}', style: t.textS.copyWith(color: c.text2)),
            if (_api.isNotEmpty)
              Text(l10n.settingsAccountServer(_api),
                  style: t.textS.copyWith(color: c.text2)),
          ];
          action = LgButton(
            label: l10n.accountSignOut,
            onPressed: () => _signOut(l10n),
          );
        }
        return SettingsFlow([
          LgSettingsBlock(children: [
            LgSettingsRowFrame(
              key: ctx.keyOf(item),
              marked: ctx.isMarked(item),
              child: Row(
                children: [
                  lead,
                  const SizedBox(width: LgSpace.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: lines,
                    ),
                  ),
                  if (action != null) ...[
                    const SizedBox(width: LgSpace.s4),
                    action,
                  ],
                ],
              ),
            ),
          ]),
        ]);
      },
    );
  }
}

/// The square with the person icon where a signed-in account has its avatar (`.s-acc .tile`).
class _Tile extends StatelessWidget {
  const _Tile();

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(LgRadius.r12),
      ),
      child: LgIcon(LgIcons.user, size: 22, color: c.text2),
    );
  }
}
