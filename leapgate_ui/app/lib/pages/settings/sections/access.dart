import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/options.dart';
import 'package:flutter_hbb/leapgate/permanent_password.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_selection.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../../home/home_dialogs.dart' show showPermanentPasswordDialog;
import '../settings_flow.dart';
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

  /// A row with its key, so search and links can scroll to it.
  Widget _keyed(String id, Widget row) =>
      KeyedSubtree(key: ctx.keyOf(id), child: row);

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
    // "在本机接受" uses no password: the blocks below grey out (02 §1.3.1; upstream hid them).
    final click = approve == _approveClick;
    final noOneTime = !click && method == kUsePermanentPassword;
    final passwords = open && !click;
    final oneTime = passwords && !noOneTime;

    LgRadio<String> radio(
      String value,
      String group,
      String label,
      ValueChanged<String>? onChanged,
    ) => LgRadio<String>(
      value: value,
      groupValue: group,
      label: label,
      onChanged: onChanged == null
          ? null
          : (v) {
              if (v != group) onChanged(v);
            },
    );

    void setApprove(String v) =>
        ctx.save(_approve, () => _config.set(kOptionApproveMode, v));

    return SettingsFlow(
      children: [
        LgSettingsBlock(
          children: [
            _keyed(
              _approve,
              LgSettingsRow(
                name: l10n.settingsAccessApproveMode,
                description: l10n.settingsAccessNewConnectionsOnly,
                marked: ctx.isMarked(_approve),
                error: ctx.errorOf(_approve),
                body: LgSettingsOptions(
                  children: [
                    radio(
                      _approvePassword,
                      approve,
                      l10n.settingsAccessApprovePassword,
                      open ? setApprove : null,
                    ),
                    radio(
                      _approveClick,
                      approve,
                      l10n.settingsAccessApproveClick,
                      open ? setApprove : null,
                    ),
                    radio(
                      '',
                      approve,
                      l10n.settingsAccessApproveBoth,
                      open ? setApprove : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (click) LgSettingsNote(l10n.settingsAccessClickNoPassword),
        LgSettingsBlock(
          disabled: click,
          children: [
            _keyed(
              _verification,
              LgSettingsRow(
                name: l10n.settingsAccessVerification,
                marked: ctx.isMarked(_verification),
                error: ctx.errorOf(_verification),
                body: LgSettingsOptions(
                  children: [
                    for (final (value, label) in [
                      (kUseTemporaryPassword, l10n.settingsAccessOneTimeOnly),
                      (kUsePermanentPassword, l10n.settingsAccessPermanentOnly),
                      (kUseBothPasswords, l10n.settingsAccessBothPasswords),
                    ])
                      radio(
                        value,
                        method,
                        label,
                        passwords ? _setVerification : null,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        LgSettingsSubtitle(l10n.settingsAccessOneTime),
        if (noOneTime) LgSettingsNote(l10n.settingsAccessPermanentNoOneTime),
        LgSettingsBlock(
          disabled: click || noOneTime,
          children: [
            _keyed(
              _length,
              LgSettingsRow(
                name: l10n.settingsAccessLength,
                wide: true,
                marked: ctx.isMarked(_length),
                error: ctx.errorOf(_length),
                control: LgSegmented<String>(
                  segments: const [
                    LgSegment('6', '6'),
                    LgSegment('8', '8'),
                    LgSegment('10', '10'),
                  ],
                  selected: length,
                  onChanged: oneTime
                      ? (v) {
                          if (v == length) return;
                          _setOneTime(
                            status,
                            _length,
                            () =>
                                _config.set(kOptionTemporaryPasswordLength, v),
                          );
                        }
                      : null,
                ),
              ),
            ),
            _keyed(
              _numeric,
              LgSettingsRow.toggle(
                name: l10n.settingsAccessNumeric,
                value: _config.getBool(kOptionAllowNumericOneTimePassword),
                marked: ctx.isMarked(_numeric),
                error: ctx.errorOf(_numeric),
                onChanged: oneTime
                    ? (v) => _setOneTime(
                        status,
                        _numeric,
                        () => _config.setBool(
                          kOptionAllowNumericOneTimePassword,
                          v,
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
        LgSettingsBlock(
          gap: true,
          disabled: click,
          children: [
            _keyed(
              _permanent,
              _PermanentRow(l10n: l10n, ctx: ctx, enabled: passwords),
            ),
          ],
        ),
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
        return LgSettingsRow(
          name: l10n.settingsAccessPermanent,
          marked: widget.ctx.isMarked(_permanent),
          error: widget.ctx.errorOf(_permanent),
          control: LgSettingsValueActions(
            value: isSet ? l10n.settingsAccessSet : l10n.settingsAccessNotSet,
            emphasized: isSet,
            actions: [
              LgSettingsAction(
                label: isSet
                    ? l10n.homeChange
                    : l10n.settingsAccessSetPermanent,
                semanticLabel: isSet ? l10n.homeChangePassword : null,
                onPressed: widget.enabled && snapshot.hasData ? _edit : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
