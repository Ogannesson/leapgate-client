// "收到的打印任务" (02 §1.4.7): one choice over upstream's three LocalConfig keys. Rust sorts an
// incoming job by them (`src/client/io_loop.rs:2289-2312`): dismissed, printed by itself with the
// default or the stored printer, else asked in the session. The printers to choose from are
// `getPrinterNames()` (`common.dart`), without Leapgate's own.
import '../../consts.dart';
import '../options.dart';

enum PrintJobChoice { ask, defaultPrinter, selectedPrinter, dismiss }

PrintJobChoice printJobChoice(OptionScope local) {
  final action = local.get(kKeyPrinterIncomingJobAction);
  if (action == kValuePrinterIncomingJobDismiss) return PrintJobChoice.dismiss;
  if (local.get(kKeyPrinterAllowAutoPrint) != 'Y') return PrintJobChoice.ask;
  return action == kValuePrinterIncomingJobSelected
      ? PrintJobChoice.selectedPrinter
      : PrintJobChoice.defaultPrinter;
}

/// Saves [choice]; the chosen printer is [printer] for [PrintJobChoice.selectedPrinter].
Future<bool> setPrintJobChoice(OptionScope local, PrintJobChoice choice,
    {String printer = ''}) async {
  switch (choice) {
    case PrintJobChoice.ask:
      return await local.set(
              kKeyPrinterIncomingJobAction, kValuePrinterIncomingJobDefault) &&
          await local.setBool(kKeyPrinterAllowAutoPrint, false);
    case PrintJobChoice.defaultPrinter:
      return await local.set(
              kKeyPrinterIncomingJobAction, kValuePrinterIncomingJobDefault) &&
          await local.setBool(kKeyPrinterAllowAutoPrint, true);
    case PrintJobChoice.selectedPrinter:
      return await local.set(kKeyPrinterSelected, printer) &&
          await local.set(
              kKeyPrinterIncomingJobAction, kValuePrinterIncomingJobSelected) &&
          await local.setBool(kKeyPrinterAllowAutoPrint, true);
    case PrintJobChoice.dismiss:
      return local.set(
          kKeyPrinterIncomingJobAction, kValuePrinterIncomingJobDismiss);
  }
}

/// The stored printer is gone: the choice goes back to the default printer, as upstream's
/// `PrinterOptions.load` does when the page opens (`printer_model.dart:27-40`).
Future<void> dropMissingPrinter(OptionScope local, List<String> printers) async {
  if (printJobChoice(local) == PrintJobChoice.selectedPrinter &&
      !printers.contains(local.get(kKeyPrinterSelected))) {
    await local.set(
        kKeyPrinterIncomingJobAction, kValuePrinterIncomingJobDefault);
  }
}
