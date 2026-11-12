import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/main.dart';

import 'memory_research_store.dart';

/// Widget tests draw Ahem squares unless a family is loaded explicitly.
Future<void> _loadType() async {
  final outfit = FontLoader('Outfit')
    ..addFont(rootBundle.load('assets/fonts/Outfit-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Outfit-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Outfit-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Outfit-Bold.ttf'));
  final fraunces = FontLoader('Fraunces')
    ..addFont(rootBundle.load('assets/fonts/Fraunces-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Fraunces-SemiBoldItalic.ttf'));
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await Future.wait([outfit.load(), fraunces.load(), icons.load()]);
}

void main() {
  testWidgets('390px shots of home, prop detail, and the parlay slip', (
    tester,
  ) async {
    if (Platform.environment['SCREENSHOT'] != '1') return;
    tester.view.physicalSize = const Size(390, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadType);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot'),
        child: OddsEdgeApp(researchStore: MemoryResearchStore()),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    // The box-score file is read off the fake clock. Let that finish,
    // then paint the hit rates before the first frame is saved.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1500)),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    await _save(tester, '/opt/cursor/artifacts/home-390.png');

    await tester.tap(find.widgetWithText(NavigationDestination, 'Games'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _save(tester, '/opt/cursor/artifacts/games-390.png');

    await tester.tap(find.widgetWithText(NavigationDestination, 'Props'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _save(tester, '/opt/cursor/artifacts/props-390.png');

    await tester.tap(find.text('Josh Allen').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _save(tester, '/opt/cursor/artifacts/prop-detail-390.png');

    await tester.tap(find.text('Add to parlay'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('Saquon Barkley').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Saquon Barkley').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Add to parlay'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.pageBack();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(NavigationDestination, 'Parlays'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _save(tester, '/opt/cursor/artifacts/parlay-390.png');
  });
}

Future<void> _save(WidgetTester tester, String path) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('shot')),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}
