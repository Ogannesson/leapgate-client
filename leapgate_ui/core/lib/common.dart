// 上游：flutter/lib/common.dart@bd9262397（改写：部分复制，只收 core 里的 models 用到的非界面符号，各段照上游原样、按上游顺序；option2bool、bool2option 是 Leapgate 的写法，见各自的说明）
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/native/win32.dart';
import 'package:flutter_hbb/native/common.dart';

final isAndroid = isAndroid_;
final isIOS = isIOS_;
final isWindows = isWindows_;
final isMacOS = isMacOS_;
final isLinux = isLinux_;
final isDesktop = isDesktop_;
final isWeb = isWeb_;
final isWebDesktop = isWebDesktop_;
final isWebOnWindows = isWebOnWindows_;
final isWebOnMacOs = isWebOnMacOS_;
var isMobile = isAndroid || isIOS;
var version = '';
int androidVersion = 0;

/// only available for Windows target
int windowsBuildNumber = 0;
DesktopType? desktopType;

typedef FMethod = String Function(String, dynamic);

typedef StreamEventHandler = Future<void> Function(Map<String, dynamic>);
typedef SessionID = UuidValue;

enum DesktopType {
  main,
  remote,
  fileTransfer,
  viewCamera,
  terminal,
  cm,
  portForward,
}

const K = 1024;

const M = K * K;

const G = M * K;

String readableFileSize(double size) {
  if (size < K) {
    return "${size.toStringAsFixed(2)} B";
  } else if (size < M) {
    return "${(size / K).toStringAsFixed(2)} KB";
  } else if (size < G) {
    return "${(size / M).toStringAsFixed(2)} MB";
  } else {
    return "${(size / G).toStringAsFixed(2)} GB";
  }
}

String translate(String name) {
  if (name.startsWith('Failed to') && name.contains(': ')) {
    return name.split(': ').map((x) => translate(x)).join(': ');
  }
  return platformFFI.translate(name, localeName);
}

// 上游 common.dart:1613-1630（原样，常量换成字面值）
// This function must be kept the same as the one in rust and sciter code.
// rust: libs/hbb_common/src/config.rs -> option2bool()
bool option2bool(String option, String value) {
  bool res;
  if (option.startsWith("enable-")) {
    res = value != "N";
  } else if (option.startsWith("allow-") ||
      option == "stop-service" ||
      option == "direct-server" ||
      option == "force-always-relay") {
    res = value == "Y";
  } else {
    // "" is true
    res = value != "N";
  }
  return res;
}

/// Upstream `bool2option` (common.dart:1632-1648) writes `defaultOptionYes` / `defaultOptionNo`
/// in two of its branches, which are 'Y' / 'N' whenever `isCustomClient` is true, and that is
/// always the case here: `src/common.rs` `is_custom_client` is "app name isn't RustDesk". So every
/// branch comes down to 'Y' / 'N', the same values the upstream UI writes in a Leapgate build.
/// Session options are not booleans of this kind; see `SessionOptions`.
String bool2option(String option, bool b) => b ? 'Y' : 'N';

// Consider using Rect.contains() instead,
// though the implementation is not exactly the same.
bool isPointInRect(Offset point, Rect rect) {
  return point.dx >= rect.left &&
      point.dx <= rect.right &&
      point.dy >= rect.top &&
      point.dy <= rect.bottom;
}

/// Get windows target build number.
///
/// [Note]
/// Please use this function wrapped with `Platform.isWindows`.
int getWindowsTargetBuildNumber() {
  return getWindowsTargetBuildNumber_();
}

int versionCmp(String v1, String v2) {
  return bind.versionToNumber(v: v1) - bind.versionToNumber(v: v2);
}

sessionRefreshVideo(SessionID sessionId, PeerInfo pi) async {
  if (pi.currentDisplay == kAllDisplayValue) {
    for (int i = 0; i < pi.displays.length; i++) {
      await bind.sessionRefresh(sessionId: sessionId, display: i);
    }
  } else {
    await bind.sessionRefresh(sessionId: sessionId, display: pi.currentDisplay);
  }
}

openMonitorInTheSameTab(int i, FFI ffi, PeerInfo pi,
    {bool updateCursorPos = true, bool recordSelection = true}) {
  if (recordSelection) {
    ffi.ffiModel.lastUserDisplay = i;
    ffi.ffiModel.cancelPendingRestoreTimer();
    ffi.ffiModel.pendingMonitorRestore = null;
  }
  final displays = i == kAllDisplayValue
      ? List.generate(pi.displays.length, (index) => index)
      : [i];
  // Try clear image model before switching from all displays
  // 1. The remote side has multiple displays.
  // 2. Do not use texture render.
  // 3. Connect to Display 1.
  // 4. Switch to multi-displays `kAllDisplayValue`
  // 5. Switch to Display 2.
  // Then the remote page will display last picture of Display 1 at the beginning.
  if (pi.forceTextureRender && i != kAllDisplayValue) {
    ffi.imageModel.clearImage();
  }
  bind.sessionSwitchDisplay(
    isDesktop: isDesktop,
    sessionId: ffi.sessionId,
    value: Int32List.fromList(displays),
  );
  ffi.ffiModel.switchToNewDisplay(i, ffi.sessionId, ffi.id,
      updateCursorPos: updateCursorPos);
}

get isInputSourceFlutter => stateGlobal.getInputSource() == "Input source 2";

List<String> getPrinterNames() {
  final printerNamesJson = bind.mainGetPrinterNames();
  if (printerNamesJson.isEmpty) {
    return [];
  }
  try {
    final List<dynamic> printerNamesList = jsonDecode(printerNamesJson);
    final appPrinterName = '$appName Printer';
    return printerNamesList
        .map((e) => e.toString())
        .where((name) => name != appPrinterName)
        .toList();
  } catch (e) {
    debugPrint('failed to parse printer names, err: $e');
    return [];
  }
}

String _appName = '';
String get appName {
  if (_appName.isEmpty) {
    _appName = bind.mainGetAppNameSync();
  }
  return _appName;
}

// TODO: We should support individual bits combinations in the future.
// But for now, just keep it simple, because the old code only supports single button.
// No users have requested multi-button support yet.
String mouseButtonsToPeer(int buttons) {
  switch (buttons) {
    case kPrimaryMouseButton:
      return 'left';
    case kSecondaryMouseButton:
      return 'right';
    case kMiddleMouseButton:
      return 'wheel';
    case kBackMouseButton:
      return 'back';
    case kForwardMouseButton:
      return 'forward';
    default:
      return '';
  }
}
