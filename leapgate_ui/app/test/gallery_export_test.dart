// Exports the gallery to PNG files from `flutter test`, to put the components
// next to the mockups (docs/新界面/03-实施方案.md §8.4). Skipped unless
// LG_EXPORT_DIR is set:
//
//   $env:LG_EXPORT_DIR = '<folder>'
//   $env:LG_EXPORT_ONLY = 'connection-panel,session-toolbar'   # optional: sections
//   flutter test test/gallery_export_test.dart
//
// Why not `flutter run -t lib/gallery_main.dart -d windows --dart-define=
// LG_GALLERY_EXPORT=<folder>`: the runner of the app loads libleapgate.dll and
// runs the Rust core before it starts Flutter, whatever the entry point, so it
// needs the DLL built and starts the core. This test needs neither.
//
// The test binding draws text in a placeholder font: the app fonts and the
// system Chinese font (Windows) are loaded here, and shadows are switched on.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/gallery_main.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    if (File(file).existsSync()) {
      loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
    }
  }
  await loader.load();
}

void main() {
  final out = Platform.environment['LG_EXPORT_DIR'];
  final only = Platform.environment['LG_EXPORT_ONLY']?.split(',');

  testWidgets(
    'export the gallery',
    (tester) async {
      await tester.runAsync(() async {
        await _loadFont('Atkinson Hyperlegible Next', [
          'assets/fonts/AtkinsonHyperlegibleNext-Regular.ttf',
          'assets/fonts/AtkinsonHyperlegibleNext-SemiBold.ttf',
          'assets/fonts/AtkinsonHyperlegibleNext-Bold.ttf',
        ]);
        await _loadFont('Microsoft YaHei UI', [
          'C:/Windows/Fonts/msyh.ttc',
          'C:/Windows/Fonts/msyhbd.ttc',
        ]);
      });
      debugDisableShadows = false;
      tester.view.physicalSize = const Size(2400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final dir = Directory(out!)..createSync(recursive: true);
      var count = 0;
      for (final specimen in buildSpecimens()) {
        if (only != null && !only.contains(specimen.section)) continue;
        for (final variant in galleryVariants) {
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Align(
                alignment: Alignment.topLeft,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: RepaintBoundary(
                    key: key,
                    child: SpecimenCell(
                      specimen: specimen,
                      variant: variant,
                      still: true,
                    ),
                  ),
                ),
              ),
            ),
          );
          // One frame to build, one more for post-frame updates (focus).
          await tester.pump(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => captureSpecimenPng(
              key,
              File('${dir.path}/${specimen.fileName(variant)}'),
            ),
          );
          count++;
        }
      }
      // The binding checks that tests leave its debug flags as they were.
      debugDisableShadows = true;
      // ignore: avoid_print
      print('exported $count images to ${dir.path}');
    },
    skip: out == null,
    timeout: Timeout.none,
  );
}
