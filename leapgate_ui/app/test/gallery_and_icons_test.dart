import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leapgate_ui/gallery_main.dart';

import '../../tools/gen_icons.dart' as gen;

/// The mockup lives in the leapgate repository, two levels above leapgate-client
/// (client/leapgate_ui/app). Override with LG_MOCKUP_HTML.
File _mockup() => File(
  Platform.environment['LG_MOCKUP_HTML'] ??
      '${Directory.current.path}/../../../docs/新界面/样稿/A-基础.html',
);

void main() {
  test('lg_icons.g.dart is what gen_icons produces from the mockup', () {
    final html = _mockup();
    if (!html.existsSync()) {
      markTestSkipped('mockup not found at ${html.path}');
      return;
    }
    final committed = File('lib/icons/lg_icons.g.dart').readAsStringSync();
    expect(gen.generate(html.readAsStringSync()), committed);
  });

  testWidgets('every gallery specimen builds in every theme and mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final s in buildSpecimens()) {
      for (final v in galleryVariants) {
        // Laid out at the specimen's own size, as the exporter does.
        await tester.pumpWidget(
          MaterialApp(
            home: OverflowBox(
              alignment: Alignment.topLeft,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: SpecimenCell(specimen: s, variant: v),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: s.fileName(v));
      }
    }
  });

  testWidgets('a specimen exports to PNG', (tester) async {
    final key = GlobalKey();
    final s = buildSpecimens().firstWhere((s) => s.section == 'button');
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: SpecimenCell(specimen: s, variant: galleryVariants.first),
        ),
      ),
    );
    final dir = Directory.systemTemp.createTempSync('lg_gallery');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/${s.fileName(galleryVariants.first)}');
    await tester.runAsync(() => captureSpecimenPng(key, file));
    final bytes = file.readAsBytesSync();
    expect(bytes.sublist(1, 4), 'PNG'.codeUnits);
  });
}
