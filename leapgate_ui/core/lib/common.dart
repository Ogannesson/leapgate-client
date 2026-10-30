// 上游：flutter/lib/common.dart@bd9262397（改写：部分复制。M0 只收 models/native_model.dart、models/platform_model.dart 用到的非界面符号，M1 起随复制进来的 models 继续补）
import 'package:uuid/uuid.dart';

import 'package:flutter_hbb/native/win32.dart';
import 'package:flutter_hbb/native/common.dart';

final isAndroid = isAndroid_;
final isIOS = isIOS_;
final isWindows = isWindows_;
final isMacOS = isMacOS_;
final isLinux = isLinux_;
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

/// Get windows target build number.
///
/// [Note]
/// Please use this function wrapped with `Platform.isWindows`.
int getWindowsTargetBuildNumber() {
  return getWindowsTargetBuildNumber_();
}
