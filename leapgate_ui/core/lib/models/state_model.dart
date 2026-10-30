// 上游：flutter/lib/models/state_model.dart@bd9262397（改写：只留复制进来的 models 和 FfiModel 用到的成员；全屏经 appCore.window；tabBarHeight 取新界面顶栏的高度。上游改了这些成员时人工移植）
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:get/get.dart';

import '../consts.dart';
import './platform_model.dart';

class StateGlobal {
  final RxBool _fullscreen = false.obs;
  final RxDouble _windowBorderWidth = RxDouble(kWindowBorderWidth);

  String _inputSource = '';

  // Track relative mouse mode state for each peer connection.
  // Key: [REDACTED], Value: true if relative mouse mode is active.
  // Note: This is session-only runtime state, NOT persisted to config.
  // Kept per device as upstream does: a device has at most one remote desktop view.
  final RxMap<String, bool> relativeMouseModeState = <String, bool>{}.obs;

  RxBool get fullscreen => _fullscreen;
  // The canvas sits right below the app's title bar, which full screen hides.
  double get tabBarHeight => fullscreen.isTrue ? 0 : kLeapgateTitleBarHeight;
  RxDouble get windowBorderWidth => _windowBorderWidth;

  setFullscreen(bool v) {
    if (_fullscreen.value != v) {
      _fullscreen.value = v;
      _windowBorderWidth.value = fullscreen.isTrue ? 0 : kWindowBorderWidth;
      appCore.window.setFullscreen(_fullscreen.isTrue);
    }
  }

  String getInputSource({bool force = false}) {
    if (force || _inputSource.isEmpty) {
      _inputSource = bind.mainGetInputSource();
    }
    return _inputSource;
  }

  StateGlobal._();

  static final StateGlobal instance = StateGlobal._();
}

/// Height of the app's title bar with the tabs, `kLgTitleBarHeight` in the app package
/// (01 §2.1); the two must match.
const double kLeapgateTitleBarHeight = 40;

// This final variable is initialized when the first time it is accessed.
final stateGlobal = StateGlobal.instance;
