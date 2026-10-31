import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/shell/app_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the frame is in physical pixels, as upstream models expect', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'),
            (call) async {
      calls.add(call);
      return {'x': 10.0, 'y': 20.0, 'width': 300.0, 'height': 200.0};
    });

    final frame = await const LgAppWindow().getFrame();

    expect(calls.single.method, 'getBounds');
    expect((calls.single.arguments as Map)['devicePixelRatio'], 1.0);
    expect(frame, const Rect.fromLTWH(10, 20, 300, 200));
  });
}
