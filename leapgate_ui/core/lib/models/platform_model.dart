// 上游：flutter/lib/models/platform_model.dart@bd9262397（原样复制，去掉 Web 的条件导入，不格式化）
import 'native_model.dart';
import 'package:flutter_hbb/generated_bridge.dart';

final platformFFI = PlatformFFI.instance;
final localeName = PlatformFFI.localeName;

RustdeskImpl get bind => platformFFI.ffiBind;

String ffiGetByName(String name, [String arg = '']) {
  return PlatformFFI.getByName(name, arg);
}

void ffiSetByName(String name, [String value = '']) {
  PlatformFFI.setByName(name, value);
}
