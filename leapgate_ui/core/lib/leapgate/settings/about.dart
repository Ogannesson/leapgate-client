// The About section (02 §1.5.5, R2-Q18): Leapgate's version (S12) with the RustDesk version it
// is based on, the build date, the fingerprint, and the link to the source code. Upstream reads
// the same from Rust in `desktop_setting_page.dart` `_AboutState`.
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

import '../../models/platform_model.dart';
import '../bridge.dart';

/// The public repository, where the source of every build is (AGPL-3.0).
const kLeapgateSourceUrl = 'https://github.com/Ogannesson/leapgate';

typedef AboutInfo = ({
  String version,
  String upstreamVersion,
  String buildDate,
  String fingerprint,
  String license,
});

Future<AboutInfo> readAbout() async => (
      version: lgBind.leapgateVersion(),
      upstreamVersion: await bind.mainGetVersion(),
      buildDate: await bind.mainGetBuildDate(),
      fingerprint: await bind.mainGetFingerprint(),
      license: await bind.mainGetLicense(),
    );

/// Rust's fingerprint (`pk_to_fingerprint`: groups of four hex digits) on two lines of eight
/// groups; empty stays empty.
String fingerprintLines(String fingerprint) {
  final groups = fingerprint.trim().split(RegExp(r'\s+'));
  if (groups.length <= 8) return fingerprint.trim();
  return '${groups.take(8).join(' ')}\n${groups.skip(8).join(' ')}';
}

/// Opens [url] in the default browser. Windows only.
void openUrl(String url) => using((arena) {
      win32.ShellExecute(0, 'open'.toNativeUtf16(allocator: arena),
          url.toNativeUtf16(allocator: arena), nullptr, nullptr,
          win32.SW_SHOWNORMAL);
    });
