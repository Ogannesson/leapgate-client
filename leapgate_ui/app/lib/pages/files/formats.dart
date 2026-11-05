// How the file transfer view writes sizes, dates, types and a folder's errors (02 §2.2 block E,
// §2.5; `LEAPGATE.md` §10.15 "几处约定"). Coder C's; the queue rows and the dialogs (coder B)
// write their own reasons.
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/file_transfer/errors.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:intl/intl.dart';
import 'package:win32/win32.dart';

import '../../l10n/app_localizations.dart';

/// 1024-based with three significant digits, trailing zeros dropped: "2.4 MB", "512 KB",
/// "1.32 GB"; under 1 KB "‹n› 字节". Only the file view uses it: `readableFileSize` in core
/// stays for the connection manager's file log.
String formatFileSize(AppLocalizations l10n, int bytes) {
  if (bytes < 1024) return l10n.filesBytes(bytes);
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes / 1024;
  var unit = 0;
  // 999.5 would round to "1000"; the next unit says it in three digits.
  while (value >= 999.5 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  var digits = value.toStringAsPrecision(3);
  if (digits.contains('.') && !digits.contains('e')) {
    digits = digits.replaceFirst(RegExp(r'\.?0+$'), '');
  }
  return '$digits ${units[unit]}';
}

/// The system's short date and time, as the user set them in Windows ("2026/10/28 14:05");
/// `intl`'s on other systems. Empty for an entry without a time (drives).
String formatFileDate(Entry entry) {
  if (entry.modifiedTime <= 0) return '';
  final time = entry.lastModified();
  if (Platform.isWindows) {
    final date = _windowsFormat(time, date: true);
    final clock = _windowsFormat(time, date: false);
    if (date != null && clock != null) return '$date $clock';
  }
  return DateFormat.yMd().add_Hm().format(time);
}

typedef _DateFormatC =
    Int32 Function(
      Pointer<Uint16> locale,
      Uint32 flags,
      Pointer<SYSTEMTIME> time,
      Pointer<Uint16> format,
      Pointer<Uint16> out,
      Int32 size,
      Pointer<Uint16> calendar,
    );
typedef _DateFormatDart =
    int Function(
      Pointer<Uint16> locale,
      int flags,
      Pointer<SYSTEMTIME> time,
      Pointer<Uint16> format,
      Pointer<Uint16> out,
      int size,
      Pointer<Uint16> calendar,
    );
typedef _TimeFormatC =
    Int32 Function(
      Pointer<Uint16> locale,
      Uint32 flags,
      Pointer<SYSTEMTIME> time,
      Pointer<Uint16> format,
      Pointer<Uint16> out,
      Int32 size,
    );
typedef _TimeFormatDart =
    int Function(
      Pointer<Uint16> locale,
      int flags,
      Pointer<SYSTEMTIME> time,
      Pointer<Uint16> format,
      Pointer<Uint16> out,
      int size,
    );

// win32 5.15 has no binding for these two; the null locale is the user's
// (LOCALE_NAME_USER_DEFAULT), which follows what they changed in the system settings.
final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _getDateFormatEx = _kernel32
    .lookupFunction<_DateFormatC, _DateFormatDart>('GetDateFormatEx');
final _getTimeFormatEx = _kernel32
    .lookupFunction<_TimeFormatC, _TimeFormatDart>('GetTimeFormatEx');
const _dateShortDate = 0x1; // DATE_SHORTDATE
const _timeNoSeconds = 0x2; // TIME_NOSECONDS
const _chars = 128;

String? _windowsFormat(DateTime time, {required bool date}) {
  final heap = GetProcessHeap();
  final st = HeapAlloc(
    heap,
    HEAP_ZERO_MEMORY,
    sizeOf<SYSTEMTIME>(),
  ).cast<SYSTEMTIME>();
  final out = HeapAlloc(heap, HEAP_ZERO_MEMORY, _chars * 2).cast<Uint16>();
  if (st == nullptr || out == nullptr) return null;
  try {
    st.ref
      ..wYear = time.year
      ..wMonth = time.month
      ..wDay = time.day
      ..wDayOfWeek = time.weekday % 7
      ..wHour = time.hour
      ..wMinute = time.minute
      ..wSecond = time.second;
    final n = date
        ? _getDateFormatEx(
            nullptr,
            _dateShortDate,
            st,
            nullptr,
            out,
            _chars,
            nullptr,
          )
        : _getTimeFormatEx(nullptr, _timeNoSeconds, st, nullptr, out, _chars);
    // n counts the terminating null.
    if (n <= 1) return null;
    return String.fromCharCodes(out.asTypedList(n - 1));
  } finally {
    HeapFree(heap, 0, st);
    HeapFree(heap, 0, out);
  }
}

/// The partial file a transfer leaves, `‹name›.download` with its `‹name›.digest` beside it
/// (02 §2.2 block E): both are typed "未完成的传输". [names] are the folder's entry names.
bool isPartialTransfer(Entry entry, Set<String> names) {
  if (!entry.isFile) return false;
  const download = '.download', digest = '.digest';
  final name = entry.name;
  if (name.endsWith(download)) {
    return names.contains(
      '${name.substring(0, name.length - download.length)}$digest',
    );
  }
  if (name.endsWith(digest)) {
    return names.contains(
      '${name.substring(0, name.length - digest.length)}$download',
    );
  }
  return false;
}

/// The type column: 文件夹 / 驱动器 / 符号链接 / 未完成的传输 / "DOCX 文件" / 文件.
String fileTypeText(
  AppLocalizations l10n,
  Entry entry, {
  bool partial = false,
}) {
  if (entry.isDrive) return l10n.filesTypeDrive;
  if (entry.entryType == 2 || entry.entryType == 5) return l10n.filesTypeLink;
  if (entry.isDirectory) return l10n.filesTypeFolder;
  if (partial) return l10n.filesTypePartial;
  final dot = entry.name.lastIndexOf('.');
  if (dot <= 0 || dot == entry.name.length - 1) return l10n.filesTypeFile;
  return l10n.filesTypeExt(entry.name.substring(dot + 1).toUpperCase());
}

/// The name a folder goes by in the copy: its last segment, a drive without its backslash,
/// "此电脑" for a Windows side's `/`.
String folderName(AppLocalizations l10n, String path, bool isWindows) {
  if (path == '/' || path.isEmpty) return isWindows ? l10n.filesThisPc : '/';
  final sep = isWindows ? RegExp(r'[\\/]+$') : RegExp(r'/+$');
  final trimmed = path.replaceFirst(sep, '');
  if (trimmed.isEmpty) return '/';
  final last = trimmed.lastIndexOf(isWindows ? RegExp(r'[\\/]') : '/');
  return last < 0 ? trimmed : trimmed.substring(last + 1);
}

/// Why [path] did not open, for the banner on top of the pane, the list area and under the path
/// field (02 §2.5).
String openErrorText(
  AppLocalizations l10n,
  String path,
  FtError error,
  bool isWindows,
) {
  final folder = folderName(l10n, path, isWindows);
  return switch (error.reason) {
    FtReason.permissionDenied => l10n.filesCantOpenNoAccess(folder),
    FtReason.notFound => l10n.filesNotFound(path),
    FtReason.timeout => l10n.filesReadTimeout,
    FtReason.androidScope => l10n.filesAndroidScope,
    FtReason.pathTooLong => l10n.filesCantOpenReason(
      folder,
      l10n.filesReasonPathTooLong,
    ),
    FtReason.invalidName || FtReason.invalidNameWindows =>
      l10n.filesCantOpenReason(folder, l10n.filesReasonInvalidName),
    _ =>
      error.text.isEmpty
          ? l10n.filesCantOpen(folder)
          : l10n.filesCantOpenReason(folder, error.text),
  };
}

/// The remote device's platform after its name in the pane header; empty until it is known.
String platformText(String platform) =>
    platform == kPeerPlatformMacOS ? 'macOS' : platform;
