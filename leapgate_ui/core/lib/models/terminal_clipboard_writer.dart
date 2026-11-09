// 上游：flutter/lib/models/terminal_clipboard_writer.dart@bd9262397（原样复制，不格式化）
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Future<bool> writeTerminalClipboardPlatform(
  String text, {
  bool userInitiated = false,
}) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (error) {
    debugPrint('[Terminal] Failed to write clipboard: $error');
    return false;
  }
}
