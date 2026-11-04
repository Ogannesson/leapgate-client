import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/common.dart' show isWindows;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/remote_printer.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/navigation.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../dialogs/server_dialog.dart' show ServerErrorDetail;
import '../settings_flow.dart';
import '../settings_registry.dart';

/// Item ids of this section.
const _printer = 'printer';
const _permission = 'remote-print-permission';

/// 传入连接 › 远程打印 (02 §1.3.7), Windows only. Coder C.
SettingsSection remotePrintingSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.remotePrinting,
      title: l10n.settingsSectionRemotePrinting,
      locked: true,
      visible: () => isWindows,
      items: () => [
        SettingsItem(_printer, l10n.settingsRemotePrintPrinter,
            description: l10n.settingsRemotePrintPrinterNote),
        if (RemotePrinterModel.read() == PrinterState.ready)
          SettingsItem(_permission, l10n.settingsRemotePrintPermission),
      ],
      build: (context, ctx) => _RemotePrintingBody(ctx: ctx),
    );

class _RemotePrintingBody extends StatefulWidget {
  const _RemotePrintingBody({required this.ctx});

  final SettingsSectionContext ctx;

  @override
  State<_RemotePrintingBody> createState() => _RemotePrintingBodyState();
}

class _RemotePrintingBodyState extends State<_RemotePrintingBody> {
  final _model = RemotePrinterModel();

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ctx = widget.ctx;
    final config = appCore.options.config;
    // In effect, as the access mode has it (02 §1.3.2).
    final accessMode = config.get(kOptionAccessMode);
    final allowed = switch (accessMode) {
      'full' => true,
      'view' => false,
      _ => config.getBool(kOptionEnableRemotePrinter),
    };
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final state = _model.state;
        return SettingsFlow([
          // Installing asks for administrator permission itself, so the printer is not under
          // the lock (`LEAPGATE.md` §10.14).
          LgSettingsBlock(children: [
            LgSettingsRow(
              key: ctx.keyOf(_printer),
              name: l10n.settingsRemotePrintPrinter,
              description: l10n.settingsRemotePrintPrinterNote,
              wide: true,
              marked: ctx.isMarked(_printer),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(switch (state) {
                    PrinterState.portable => l10n.settingsRemotePrintPortable,
                    PrinterState.notInstalled =>
                      l10n.settingsRemotePrintNotInstalled,
                    PrinterState.installing =>
                      l10n.settingsRemotePrintInstalling,
                    PrinterState.failed => l10n.settingsRemotePrintFailed,
                    PrinterState.ready => l10n.settingsRemotePrintReady,
                  }),
                  if (state == PrinterState.failed && _model.detail.isNotEmpty)
                    ServerErrorDetail(
                        label: l10n.settingsNetDetails, detail: _model.detail),
                ],
              ),
              control: switch (state) {
                PrinterState.notInstalled ||
                PrinterState.installing ||
                PrinterState.failed =>
                  LgSettingsValueActions(actions: [
                    LgSettingsAction(
                      label: state == PrinterState.failed
                          ? l10n.settingsRemotePrintRetry
                          : l10n.settingsRemotePrintInstall,
                      icon: LgIcons.uac,
                      busy: state == PrinterState.installing,
                      onPressed: state == PrinterState.installing
                          ? null
                          : _model.install,
                    ),
                  ]),
                // No install page in the new UI yet (03 §5.2, the third round).
                PrinterState.portable || PrinterState.ready => null,
              },
            ),
          ]),
          if (state == PrinterState.ready)
            LgSettingsBlock(
              disabled: ctx.locked,
              children: [
                LgSettingsRow(
                  key: ctx.keyOf(_permission),
                  name: l10n.settingsRemotePrintPermission,
                  wide: true,
                  marked: ctx.isMarked(_permission),
                  control: LgSettingsValueActions(
                    value: allowed
                        ? l10n.settingsRemotePrintAllowed
                        : l10n.settingsRemotePrintNotAllowed,
                    emphasized: allowed,
                    actions: [
                      LgSettingsAction(
                        label: l10n.settingsRemotePrintChange,
                        semanticLabel: l10n.settingsRemotePrintChangeLabel,
                        // With "完全访问" or "仅共享屏幕" the switch is greyed under the
                        // access mode: that is what to change.
                        onPressed: ctx.locked
                            ? null
                            : () => mainNavigation.showSettings(
                                SettingsSectionId.permissions,
                                item: accessMode == 'full' ||
                                        accessMode == 'view'
                                    ? kOptionAccessMode
                                    : kOptionEnableRemotePrinter),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ]);
      },
    );
  }
}
