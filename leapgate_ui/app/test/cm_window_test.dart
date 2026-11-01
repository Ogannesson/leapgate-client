import 'package:flutter/services.dart';
import 'package:flutter_hbb/leapgate/cm_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/cm/cm_window.dart';
import 'package:leapgate_ui/widgets/lg_cm_frame.dart';

// The connection manager's window keeps the side panel's width (LEAPGATE.md §10.10).

void main() {
  test(
    'shown again for a new visitor, the window is as wide as the side panel needs',
    () async {
      final widths = <double>[];
      TestWidgetsFlutterBinding.ensureInitialized()
          .defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'), (
            call,
          ) async {
            if (call.method == 'setBounds' && call.arguments['width'] != null) {
              widths.add(call.arguments['width'] as double);
            }
            return call.method.startsWith('is') ? false : null;
          });
      final scale = cmPrimaryWorkArea().scale;
      final window = LgCmWindow();

      await window.show();
      await window.setExpanded(true);
      await window.hide();
      await window.show();
      await window.setExpanded(false);
      expect(widths, [
        kLgCmWidth * scale,
        kLgCmExpandedWidth * scale,
        kLgCmExpandedWidth * scale,
        kLgCmWidth * scale,
      ]);

      // Already up (a chat message, "查看"): it stays where the user moved it.
      await window.bringToFront();
      expect(widths, hasLength(4));
    },
  );
}
