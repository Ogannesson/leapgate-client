import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/options.dart';
import 'package:flutter_hbb/leapgate/permanent_password.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_selection.dart';
import '../../home/home_dialogs.dart' show showPermanentPasswordDialog;
import '../settings_parts.dart';
import '../settings_registry.dart';
import '../settings_status.dart';

// Item ids. `approve-mode`, `verification-method` and `permanent-password` are fixed: the exit
// node section links to them (`LEAPGATE.md` §10.13).
const _approve = 'approve-mode';
const _verification = 'verification-method';
const _length = kOptionTemporaryPasswordLength;
const _numeric = kOptionAllowNumericOneTimePassword;
const _permanent = 'permanent-password';

/// `approve-mode`: Rust takes anything but these two as both (`password_security.rs`
/// `approve_mode`); both is written as nothing.
const _approvePassword = 'password';
const _approveClick = 'click';

/// 传入连接 › 访问与密码 (02 §1.3.1). Coder A.
SettingsSection accessSection(AppLocalizations l10n) => SettingsSection(
  id: SettingsSectionId.access,
  title: l10n.settingsSectionAccess,
  locked: true,
  items: () => [
    SettingsItem(
      _approve,
      l10n.settingsAccessApproveMode,
      description: l10n.settingsAccessNewConnectionsOnly,
      options: [
        l10n.settingsAccessApprovePassword,
        l10n.settingsAccessApproveClick,
        l10n.settingsAccessApproveBoth,
      ],
    ),
    SettingsItem(
      _verification,
      l10n.settingsAccessVerification,
      options: [
        l10n.settingsAccessOneTimeOnly,
        l10n.settingsAccessPermanentOnly,
        l10n.settingsAccessBothPasswords,
      ],
    ),
    SettingsItem(
      _length,
      '${l10n.settingsAccessOneTime} · ${l10n.settingsAccessLength}',
    ),
    SettingsItem(
      _numeric,
      '${l10n.settingsAccessOneTime} · ${l10n.settingsAccessNumeric}',
    ),
    SettingsItem(_permanent, l10n.settingsAccessPermanent),
  ],
  build: (context, ctx) => _Access(l10n: l10n, ctx: ctx),
);

class _Access extends StatelessWidget {
  const _Access({required this.l10n, required this.ctx});

  final AppLocalizations l10n;
  final SettingsSectionContext ctx;

  OptionScope get _config => appCore.options.config;

  Future<void> _setVerification(String method) async {
    // Only the permanent password while none is set: set one first, and switch only when a
    // password was saved (upstream `desktop_setting_page.dart:1313-1326`).
    if (method == kUsePermanentPassword &&
        !(await readPermanentPasswordState()).isSet) {
      await showPermanentPasswordDialog(ctx.overlays, l10n);
      if (!(await readPermanentPasswordState()).isSet) return;
    }
    await ctx.save(
      _verification,
      () => _config.set(kOptionVerificationMethod, method),
    );
  }

  /// Length and "仅使用数字" make a new one-time password at once (02 §1.3.1).
  Future<void> _setOneTime(
    LocalStatusModel status,
    String item,
    Future<bool> Function() write,
  ) async {
    if (await ctx.save(item, write)) await status.refreshOneTimePassword();
  }

  @override
  Widget build(BuildContext context) {
    final status = SettingsStatus.of(context);
    final approve = switch (_config.get(kOptionApproveMode)) {
      _approvePassword => _approvePassword,
      _approveClick => _approveClick,
      _ => '',
    };
    final method = switch (_config.get(kOptionVerificationMethod)) {
      kUseTemporaryPassword => kUseTemporaryPassword,
      kUsePermanentPassword => kUsePermanentPassword,
      _ => kUseBothPasswords,
    };
    final length = switch (_config.get(kOptionTemporaryPasswordLength)) {
      '8' => '8',
      '10' => '10',
      _ => '6',
    };
    final open = !ctx.locked;
    // "在本机接受" uses no password: the three below grey out (02 §1.3.1; upstream hid them).
    final passwords = open && approve != _approveClick;
    final oneTime = passwords && method != kUsePermanentPassword;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsRow(
          ctx: ctx,
          id: _approve,
          name: l10n.settingsAccessApproveMode,
          description: l10n.settingsAccessNewConnectionsOnly,
          enabled: open,
          below: SettingsChoice<String>(
            options: [
              (_approvePassword, l10n.settingsAccessApprovePassword),
              (_approveClick, l10n.settingsAccessApproveClick),
              ('', l10n.settingsAccessApproveBoth),
            ],
            value: approve,
            onChanged: open
                ? (v) => ctx.save(
                    _approve,
                    () => _config.set(kOptionApproveMode, v),
                  )
                : null,
          ),
        ),
        if (approve == _approveClick)
          SettingsNote(l10n.settingsAccessClickNoPassword),
        SettingsRow(
          ctx: ctx,
          id: _verification,
          name: l10n.settingsAccessVerification,
          enabled: passwords,
          below: SettingsChoice<String>(
            options: [
              (kUseTemporaryPassword, l10n.settingsAccessOneTimeOnly),
              (kUsePermanentPassword, l10n.settingsAccessPermanentOnly),
              (kUseBothPasswords, l10n.settingsAccessBothPasswords),
            ],
            value: method,
            onChanged: passwords ? _setVerification : null,
          ),
        ),
        SettingsNote(l10n.settingsAccessOneTime, title: true),
        if (passwords && method == kUsePermanentPassword)
          SettingsNote(l10n.settingsAccessPermanentNoOneTime),
        SettingsRow(
          ctx: ctx,
          id: _length,
          name: l10n.settingsAccessLength,
          enabled: oneTime,
          control: SettingsChoice<String>(
            horizontal: true,
            options: const [('6', '6'), ('8', '8'), ('10', '10')],
            value: length,
            onChanged: oneTime
                ? (v) => _setOneTime(
                    status,
                    _length,
                    () => _config.set(kOptionTemporaryPasswordLength, v),
                  )
                : null,
          ),
        ),
        SettingsRow(
          ctx: ctx,
          id: _numeric,
          name: l10n.settingsAccessNumeric,
          enabled: oneTime,
          control: LgSwitch(
            value: _config.getBool(kOptionAllowNumericOneTimePassword),
            semanticLabel: l10n.settingsAccessNumeric,
            onChanged: oneTime
                ? (v) => _setOneTime(
                    status,
                    _numeric,
                    () =>
                        _config.setBool(kOptionAllowNumericOneTimePassword, v),
                  )
                : null,
          ),
        ),
        _PermanentRow(l10n: l10n, ctx: ctx, enabled: passwords),
      ],
    );
  }
}

/// "固定密码": whether one is set is read again on every build and after the dialog.
class _PermanentRow extends StatefulWidget {
  const _PermanentRow({
    required this.l10n,
    required this.ctx,
    required this.enabled,
  });

  final AppLocalizations l10n;
  final SettingsSectionContext ctx;
  final bool enabled;

  @override
  State<_PermanentRow> createState() => _PermanentRowState();
}

class _PermanentRowState extends State<_PermanentRow> {
  late Future<PermanentPasswordState> _state = readPermanentPasswordState();

  @override
  void didUpdateWidget(_PermanentRow old) {
    super.didUpdateWidget(old);
    _state = readPermanentPasswordState();
  }

  Future<void> _edit() async {
    await showPermanentPasswordDialog(widget.ctx.overlays, widget.l10n);
    if (mounted) setState(() => _state = readPermanentPasswordState());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return FutureBuilder(
      future: _state,
      builder: (context, snapshot) {
        final isSet = snapshot.data?.isSet ?? false;
        return SettingsRow(
          ctx: widget.ctx,
          id: _permanent,
          name: l10n.settingsAccessPermanent,
          enabled: widget.enabled,
          below: Row(
            children: [
              Text(isSet ? l10n.settingsAccessSet : l10n.settingsAccessNotSet),
              const SizedBox(width: 12),
              LgButton(
                label: isSet
                    ? l10n.homeChange
                    : l10n.settingsAccessSetPermanent,
                semanticLabel: isSet ? l10n.homeChangePassword : null,
                kind: LgButtonKind.text,
                onPressed: widget.enabled && snapshot.hasData ? _edit : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
