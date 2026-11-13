import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/games_screen.dart';
import 'package:odds_edge/coach/report_card_screen.dart';
import 'package:odds_edge/domain/coach_model.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/prop_report.dart';
import 'package:odds_edge/theme/edge_theme.dart';

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
  testWidgets('390px games list and an open-roof game with weather', (
    tester,
  ) async {
    if (Platform.environment['SCREENSHOT'] != '1') return;
    final now = DateTime.utc(2026, 11, 13, 15);
    final kick = DateTime.utc(2026, 11, 15, 18);
    final model = (await tester.runAsync(loadBundledCoachModel))!;
    tester.view.physicalSize = const Size(390, 1180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadType);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot'),
        child: MaterialApp(
          theme: edgeTheme(),
          home: Scaffold(
            backgroundColor: EdgeColors.background,
            body: GamesScreen(
              board: _outdoorBoard(now, kick),
              now: now,
              model: model,
              settings: model.settings,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Houston Texans'), findsOneWidget);
    expect(find.text('Minnesota Vikings'), findsOneWidget);
    expect(find.textContaining('The comparison is not a pick.'), findsOneWidget);
    await _save(tester, '/opt/cursor/artifacts/games_list_390.png');

    tester.view.physicalSize = const Size(390, 1680);
    await tester.pump();
    await tester.tap(find.text('Houston Texans'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('how-we-got-this')), findsOneWidget);
    expect(find.textContaining('Huntington Bank Field'), findsOneWidget);
    expect(find.text('Comparison, not a pick.'), findsOneWidget);
    await _save(tester, '/opt/cursor/artifacts/game_detail_weather_390.png');
  });

  testWidgets('390px report card game version chart', (tester) async {
    if (Platform.environment['SCREENSHOT'] != '1') return;
    final now = DateTime.utc(2026, 11, 13, 15);
    final model = (await tester.runAsync(loadBundledCoachModel))!;
    tester.view.physicalSize = const Size(390, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadType);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot'),
        child: MaterialApp(
          theme: edgeTheme(),
          home: Scaffold(
            backgroundColor: EdgeColors.background,
            body: ReportCardScreen(
              model: model,
              now: now,
              lineHistory: const {},
              events: const [],
              examplePrices: true,
              propReport: const PropReport(
                method: 'Walk-forward.',
                tested: 'Box scores against a fair 50% line.',
                notTested: 'No historical sportsbook prop price was used.',
                usedSportsbookPrices: false,
                marketProxy: 0.5,
                scored: 1200,
                pushes: 40,
                players: 80,
                brier: 0.251,
                logLoss: 0.694,
                baselineBrier: 0.25,
                baselineLogLoss: 0.693,
                calibration: [],
                scoredByMetric: {'passing_yards': 1200},
                hasEdge: false,
                plainEnglish: 'Tested 1200 player-games.',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('game-version-chart')), findsOneWidget);
    expect(find.text('Game model: no edge yet'), findsOneWidget);
    await _save(tester, '/opt/cursor/artifacts/report_card_games_v1_v2_390.png');
  });
}

OddsBoard _outdoorBoard(DateTime now, DateTime kick) {
  final games = [
    (
      'hou-cle',
      'Houston Texans',
      'Cleveland Browns',
      -3.0,
      41.5,
    ),
    (
      'min-gb',
      'Minnesota Vikings',
      'Green Bay Packers',
      -2.5,
      43.5,
    ),
    (
      'buf-nyj',
      'Buffalo Bills',
      'New York Jets',
      2.5,
      47.0,
    ),
  ];
  final quotes = <OddsQuote>[];
  for (final game in games) {
    void add(String bookId, String book, String market, String outcome, double? point, double decimal) {
      quotes.add(
        OddsQuote(
          selection: Selection(
            eventId: game.$1,
            market: market,
            outcome: outcome,
            point: point,
          ),
          bookId: bookId,
          book: book,
          provider: 'demonstration',
          decimal: decimal,
          sourceAt: now,
          collectedAt: now,
          demo: true,
        ),
      );
    }

    for (final book in const [('fanduel', 'FanDuel'), ('draftkings', 'DraftKings')]) {
      add(book.$1, book.$2, 'spreads', game.$2, -game.$4, 1.91);
      add(book.$1, book.$2, 'spreads', game.$3, game.$4, 1.91);
      add(book.$1, book.$2, 'totals', 'Over', game.$5, 1.91);
      add(book.$1, book.$2, 'totals', 'Under', game.$5, 1.91);
      add(book.$1, book.$2, 'h2h', game.$2, null, 2.10);
      add(book.$1, book.$2, 'h2h', game.$3, null, 1.74);
    }
    add('pinnacle', 'Pinnacle', 'spreads', game.$2, -game.$4, 1.95);
    add('pinnacle', 'Pinnacle', 'spreads', game.$3, game.$4, 1.87);
    add('pinnacle', 'Pinnacle', 'totals', 'Over', game.$5, 1.90);
    add('pinnacle', 'Pinnacle', 'totals', 'Under', game.$5, 1.90);
  }
  return OddsBoard(
    events: [
      for (final game in games) SportEvent(game.$1, game.$2, game.$3, kick),
    ],
    quotes: quotes,
    fetchedAt: now,
    demo: true,
    notices: const [
      'Sample prices. The weather on an open roof is the real forecast.',
    ],
  );
}

Future<void> _save(WidgetTester tester, String path) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('shot')),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}
