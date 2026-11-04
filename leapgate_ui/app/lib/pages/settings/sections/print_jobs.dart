import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/common.dart' show getPrinterNames, isWindows;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/settings/print_jobs.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_panel_inputs.dart';
import '../../../widgets/lg_selection.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';

/// Item ids of this section.
const kPrintJobsItemAction = kKeyPrinterIncomingJobAction;
const kPrintJobsItemPrinter = kKeyPrinterSelected;

/// 传出连接 › 收到的打印任务 (02 §1.4.7), Windows only. Coder D. The session's print job notice
/// writes the same choice when "记住此选择" is ticked (`leapgate/session_requests.dart`).
SettingsSection printJobsSection(AppLocalizations l10n) => SettingsSection(
      id: SettingsSectionId.printJobs,
      title: l10n.settingsSectionPrintJobs,
      visible: () => isWindows,
      items: () => [
        SettingsItem(kPrintJobsItemAction, l10n.settingsPrintJobsAction,
            description: l10n.settingsPrintJobsNote,
            options: [
              l10n.settingsPrintJobsAsk,
              l10n.settingsPrintJobsDefault,
              l10n.settingsPrintJobsSelected,
              l10n.settingsPrintJobsDismiss,
            ]),
        if (printJobChoice(appCore.options.local) ==
            PrintJobChoice.selectedPrinter)
          SettingsItem(kPrintJobsItemPrinter, l10n.settingsPrintJobsPrinter),
      ],
      build: (context, ctx) => _PrintJobs(ctx: ctx),
    );

class _PrintJobs extends StatefulWidget {
  const _PrintJobs({required this.ctx});

  final SettingsSectionContext ctx;

  @override
  State<_PrintJobs> createState() => _PrintJobsState();
}

class _PrintJobsState extends State<_PrintJobs> {
  @override
  void initState() {
    super.initState();
    _dropMissing();
  }

  Future<void> _dropMissing() async {
    await dropMissingPrinter(appCore.options.local, getPrinterNames());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ctx = widget.ctx;
    final local = appCore.options.local;
    final printers = getPrinterNames();
    final choice = printJobChoice(local);
    final stored = local.get(kKeyPrinterSelected);
    final printer = printers.contains(stored)
        ? stored
        : printers.isEmpty
            ? ''
            : printers.first;

    void choose(PrintJobChoice v) {
      if (v == choice) return;
      ctx.save(kPrintJobsItemAction,
          () => setPrintJobChoice(local, v, printer: printer));
    }

    return SettingsFlow([
      LgSettingsBlock(children: [
        LgSettingsRow(
          key: ctx.keyOf(kPrintJobsItemAction),
          name: l10n.settingsPrintJobsAction,
          description: l10n.settingsPrintJobsNote,
          marked: ctx.isMarked(kPrintJobsItemAction),
          error: ctx.errorOf(kPrintJobsItemAction),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (printers.isEmpty) LgSettingsNote(l10n.settingsPrintJobsNoPrinter),
              LgSettingsOptions(children: [
                for (final (value, label, needsPrinter) in [
                  (PrintJobChoice.ask, l10n.settingsPrintJobsAsk, false),
                  (PrintJobChoice.defaultPrinter, l10n.settingsPrintJobsDefault, true),
                  (PrintJobChoice.selectedPrinter, l10n.settingsPrintJobsSelected, true),
                  (PrintJobChoice.dismiss, l10n.settingsPrintJobsDismiss, false),
                ])
                  LgRadio<PrintJobChoice>(
                    value: value,
                    groupValue: choice,
                    label: label,
                    onChanged: needsPrinter && printers.isEmpty ? null : choose,
                  ),
              ]),
            ],
          ),
        ),
        if (choice == PrintJobChoice.selectedPrinter && printers.isNotEmpty)
          LgSettingsRow(
            key: ctx.keyOf(kPrintJobsItemPrinter),
            name: l10n.settingsPrintJobsPrinter,
            indented: true,
            wide: true,
            marked: ctx.isMarked(kPrintJobsItemPrinter),
            error: ctx.errorOf(kPrintJobsItemPrinter),
            control: SizedBox(
              width: 240,
              child: LgSelectField<String>(
                dense: true,
                semanticLabel: l10n.settingsPrintJobsPrinter,
                items: [for (final p in printers) LgSelectItem(p, p)],
                value: printer,
                onChanged: (v) => ctx.save(kPrintJobsItemPrinter,
                    () => local.set(kKeyPrinterSelected, v)),
              ),
            ),
          ),
      ]),
    ]);
  }
}
