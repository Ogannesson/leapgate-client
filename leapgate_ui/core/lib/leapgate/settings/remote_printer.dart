// The Leapgate printer of the remote printing section (02 §1.3.7). Upstream:
// `desktop_setting_page.dart` `_PrinterState.outgoing`; installing is `main_set_common`'s
// `install-printer`, which asks for administrator permission itself and answers with the global
// event `install-printer-res` (`src/flutter_ffi.rs`).
import 'package:flutter/foundation.dart';

import '../../models/platform_model.dart';

enum PrinterState { portable, notInstalled, installing, failed, ready }

const _event = 'install-printer-res';

class RemotePrinterModel extends ChangeNotifier {
  RemotePrinterModel() {
    platformFFI.registerEventHandler(_event, _event, (evt) async {
      if (evt['success'] == true) {
        _state = read();
      } else {
        _state = PrinterState.failed;
        _detail = evt['msg'] as String? ?? '';
      }
      notifyListeners();
    }, replace: true);
  }

  late PrinterState _state = read();
  String _detail = '';

  PrinterState get state => _state;

  /// Rust's message when installing failed (the technical details).
  String get detail => _detail;

  /// What Rust says now.
  static PrinterState read() {
    if (!bind.mainIsInstalled()) return PrinterState.portable;
    return bind.mainGetCommonSync(key: 'is-printer-installed') == 'true'
        ? PrinterState.ready
        : PrinterState.notInstalled;
  }

  void install() {
    _state = PrinterState.installing;
    _detail = '';
    notifyListeners();
    bind.mainSetCommon(key: 'install-printer', value: '');
  }

  @override
  void dispose() {
    platformFFI.unregisterEventHandler(_event, _event);
    super.dispose();
  }
}
