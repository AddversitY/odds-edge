import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/value_check.dart';
import 'package:odds_edge/main.dart';
import 'package:odds_edge/ui/feed_card.dart';

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
    await _save(tester, 'build/review/home-390.png');
    final legs = _crossGameLegs(tester);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Research'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Games', skipOffstage: false));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _save(tester, 'build/review/games-390.png');

    await tester.tap(find.widgetWithText(NavigationDestination, 'Research'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Props', skipOffstage: false));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _save(tester, 'build/review/props-390.png');

    await tester.tap(find.widgetWithText(NavigationDestination, 'Today'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _addLeg(tester, legs.first, shot: true);
    await _addLeg(tester, legs.last, shot: false);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-parlay-builder')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await _save(tester, 'build/review/parlay-390.png');
  });
}

/// The two strongest Bet or Lean cards that are not in the same game.
List<String> _crossGameLegs(WidgetTester tester) {
  final cards =
      tester.widgetList<FeedPropCard>(find.byType(FeedPropCard)).where((card) {
        final word = card.shown.verdict.word;
        return word == ValueWord.bet || word == ValueWord.lean;
      }).toList()..sort(
        (a, b) => (b.shown.edge ?? -999).compareTo(a.shown.edge ?? -999),
      );
  final ids = <String>[];
  final events = <String>{};
  for (final card in cards) {
    final event = card.shown.card.event?.id ?? '';
    if (!events.add(event)) continue;
    ids.add(card.shown.card.id);
    if (ids.length == 2) return ids;
  }
  throw StateError(
    'The example board has no cross-game pair of Bet or Lean legs.',
  );
}

Future<void> _addLeg(
  WidgetTester tester,
  String id, {
  required bool shot,
}) async {
  final card = find.byKey(ValueKey(id));
  await tester.ensureVisible(card);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  await tester.tap(card);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  if (shot) {
    await _save(tester, 'build/review/prop-detail-390.png');
  }
  await tester.tap(find.text('Add to parlay'));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  await tester.pageBack();
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
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
