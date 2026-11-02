import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/tab_overlays.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_feedback.dart';
import '../../../widgets/lg_menu.dart';
import '../../../widgets/lg_pressable.dart';
import '../../../widgets/lg_text_field.dart';

// The account area and the login dialog (01 P1 blocks D and K, M4; `LEAPGATE.md` §10.11), after
// upstream's `common/widgets/login.dart` `loginDialog` and the account button of
// `desktop/pages/desktop_setting_page.dart`. Placeholders until the designer's components
// (M4 integration); the states and texts are final.

/// The avatar's letter: the first character of the name, Latin letters in upper case (01 P1
/// block D: "张三" gives "张", "alice" gives "A").
String accountLetter(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
}

/// The account area at the bottom of the home page's left column.
Widget accountArea(BuildContext context, TabOverlays overlays) =>
    _AccountArea(overlays: overlays);

/// The login dialog over the home tab; true when it signed in. The address book and the team
/// devices call it from their "signed out" state.
Future<bool> showLoginDialog(TabOverlays overlays) async =>
    await overlays.show<bool>(
      null,
      (context, close) => LgDialogScrim(
        onEscape: () => close(false),
        child: _LoginDialog(close: close),
      ),
    ) ??
    false;

class _AccountArea extends StatefulWidget {
  const _AccountArea({required this.overlays});

  final TabOverlays overlays;

  @override
  State<_AccountArea> createState() => _AccountAreaState();
}

class _AccountAreaState extends State<_AccountArea> {
  /// The in-page sign-out confirmation is open.
  bool _confirming = false;

  Future<void> _signOut() async {
    setState(() => _confirming = false);
    await appCore.account.logout();
  }

  @override
  Widget build(BuildContext context) {
    final account = appCore.account;
    if (account.disabled) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final small = t.textS.copyWith(color: t.colors.text2);
    return Padding(
      padding: const EdgeInsets.only(top: LgSpace.s5),
      child: ListenableBuilder(
        listenable: account,
        builder: (context, _) {
          final user = account.user;
          if (account.signingOut) {
            return Text(l10n.accountSigningOut, style: small);
          }
          if (user == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LgButton(
                  label: l10n.accountSignIn,
                  icon: LgIcons.login,
                  onPressed: () => showLoginDialog(widget.overlays),
                ),
                const SizedBox(height: LgSpace.s2),
                Text(l10n.accountSignedOutNote, style: small),
              ],
            );
          }
          if (_confirming) {
            return Semantics(
              container: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.accountSignOutTitle,
                    style: t.textM.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: LgSpace.s1),
                  Text(l10n.accountSignOutBody, style: small),
                  const SizedBox(height: LgSpace.s2),
                  Wrap(
                    spacing: LgSpace.s2,
                    runSpacing: LgSpace.s2,
                    children: [
                      LgButton(
                        label: l10n.accountSignOut,
                        kind: LgButtonKind.dangerSolid,
                        onPressed: _signOut,
                      ),
                      LgButton(
                        label: l10n.homeCancel,
                        onPressed: () => setState(() => _confirming = false),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
          return _AccountButton(
            user: user,
            menuLabel: l10n.accountMenu,
            items: [
              LgMenuItem(label: '@${user.name}', onPressed: null),
              LgMenuItem(
                label: l10n.accountSignOut,
                icon: LgIcons.logout,
                onPressed: () => setState(() => _confirming = true),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The avatar and the display name; pressing it opens the account menu.
class _AccountButton extends StatelessWidget {
  const _AccountButton({
    required this.user,
    required this.menuLabel,
    required this.items,
  });

  final AccountUser user;
  final String menuLabel;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final name = user.displayNameOrName;
    return LgMenuAnchor(
      items: items,
      builder: (context, controller) => LgPressable(
        semanticLabel: '$menuLabel $name',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        builder: (context, states) => Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: c.surface2,
              child: Text(
                accountLetter(name),
                style: t.textM.copyWith(color: c.text),
              ),
            ),
            const SizedBox(width: LgSpace.s2),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: t.textM,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({required this.close});

  final void Function(bool?) close;

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  late final _username = TextEditingController(
    text: appCore.account.lastUsername,
  );
  final _password = TextEditingController();
  String? _usernameError;
  String? _passwordError;
  bool _busy = false;

  /// The API server did not answer for the login options (M4-4); false while asking and once it
  /// answered.
  bool _optionsFailed = false;

  @override
  void initState() {
    super.initState();
    _checkOptions();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _checkOptions() async {
    if (_optionsFailed) setState(() => _optionsFailed = false);
    final result = await appCore.account.checkLoginOptions();
    if (mounted && !result.ok) setState(() => _optionsFailed = true);
  }

  Future<void> _submit(AppLocalizations l10n) async {
    if (_busy) return;
    final username = _username.text.trim();
    if (username.isEmpty) {
      setState(() => _usernameError = l10n.loginNoUsername);
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _passwordError = l10n.loginNoPassword);
      return;
    }
    setState(() => _busy = true);
    final result = await appCore.account.login(username, _password.text);
    if (!mounted) return;
    if (result.ok) {
      widget.close(true);
      return;
    }
    final error = result.error!;
    setState(() {
      _busy = false;
      _passwordError = switch (error.kind) {
        ApiErrorKind.wrongCredentials => l10n.loginWrongCredentials,
        ApiErrorKind.verificationRequired => l10n.loginVerificationRequired,
        ApiErrorKind.network => l10n.loginNetworkError,
        _ => l10n.loginServerError(error.text),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    return LgConfirmDialog(
      title: l10n.loginTitle,
      actions: [
        LgDialogAction(
          label: l10n.homeCancel,
          onPressed: () => widget.close(false),
        ),
        LgDialogAction(
          label: _busy ? l10n.loginBusy : l10n.loginSubmit,
          kind: LgButtonKind.primary,
          onPressed: _busy ? null : () => _submit(l10n),
        ),
      ],
      children: [
        LgTextField(
          controller: _username,
          placeholder: l10n.loginUsername,
          semanticLabel: l10n.loginUsername,
          errorText: _usernameError,
          enabled: !_busy,
          autofocus: _username.text.isEmpty,
          onChanged: (_) {
            if (_usernameError != null) setState(() => _usernameError = null);
          },
          onSubmitted: (_) => _submit(l10n),
        ),
        const SizedBox(height: LgSpace.s3),
        LgTextField(
          controller: _password,
          placeholder: l10n.loginPassword,
          semanticLabel: l10n.loginPassword,
          errorText: _passwordError,
          obscureText: true,
          enabled: !_busy,
          autofocus: _username.text.isNotEmpty,
          onChanged: (_) {
            if (_passwordError != null) setState(() => _passwordError = null);
          },
          onSubmitted: (_) => _submit(l10n),
        ),
        if (_optionsFailed) ...[
          const SizedBox(height: LgSpace.s3),
          Text(
            l10n.loginOptionsFailed,
            style: t.textS.copyWith(color: t.colors.text2),
          ),
          LgButton(
            label: l10n.loginRetry,
            kind: LgButtonKind.text,
            onPressed: _checkOptions,
          ),
        ],
      ],
    );
  }
}
