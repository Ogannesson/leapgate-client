import 'bridge.dart';
import 'options.dart';

/// LocalConfig: the interface mode (01 §2.3, 02 §4.1): 'detail' is the detail mode, anything
/// else the simple one. The home page's "View" menu and the settings page (M6) write the same
/// value.
const kOptionLeapgateUiMode = 'leapgate-ui-mode';

bool isDetailMode(OptionScope local) =>
    local.get(kOptionLeapgateUiMode) == 'detail';

/// The main window's switch; the connection manager follows it (S7), with the same value.
Future<bool> setDetailMode(OptionScope local, bool detail) async {
  final mode = detail ? 'detail' : '';
  final saved = await local.set(kOptionLeapgateUiMode, mode);
  await lgBind.leapgateUiModeChanged(mode: mode);
  return saved;
}
