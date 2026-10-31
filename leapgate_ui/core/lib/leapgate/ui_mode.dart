import 'options.dart';

/// LocalConfig: the interface mode (01 §2.3, 02 §4.1): 'detail' is the detail mode, anything
/// else the simple one. The home page's "View" menu and the settings page (M6) write the same
/// value.
const kOptionLeapgateUiMode = 'leapgate-ui-mode';

bool isDetailMode(OptionScope local) =>
    local.get(kOptionLeapgateUiMode) == 'detail';

Future<bool> setDetailMode(OptionScope local, bool detail) =>
    local.set(kOptionLeapgateUiMode, detail ? 'detail' : '');
