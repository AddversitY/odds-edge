import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/games_screen.dart';
import 'package:odds_edge/coach/model_screen.dart';
import 'package:odds_edge/coach/my_bets_screen.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/domain/bets.dart';
import 'package:odds_edge/domain/coach_model.dart';
import 'package:odds_edge/domain/odds.dart';

import 'memory_research_store.dart';

void main() {
  test('decay, shrinkage, and the points line match the training formulas', () {
    expect(decayWeight(0), 1);
    expect(decayWeight(42), closeTo(0.5, 1e-12));
    expect(decayWeight(84), closeTo(0.25, 1e-12));
    expect(() => decayWeight(-1), throwsArgumentError);
    expect(
      shrunkAverage([(1.0, 200.0, 0)], priorValue: 0, priorPlays: 200),
      closeTo(0.5, 1e-12),
    );
    expect(
      projectedMargin(homeNet: 0.1, awayNet: -0.1, scale: 40, homeField: 2),
      closeTo(10, 1e-12),
    );
    expect(
      projectedTotal(
        homeOff: 0.1,
        homeDef: 0.0,
        awayOff: 0.1,
        awayDef: 0.0,
        intercept: 40,
        scale: 25,
      ),
      closeTo(45, 1e-12),
    );
  });

  test('a later week is never training material for itself', () {
    expect(gameIsBefore(2020, 5, 2020, 6), isTrue);
    expect(gameIsBefore(2020, 5, 2020, 5), isFalse);
    expect(gameIsBefore(2021, 1, 2020, 18), isFalse);
    expect(gameIsBefore(2019, 17, 2020, 1), isTrue);
  });

  test('expected value at -110 and the edge rule', () {
    final price = americanToDecimal(-110);
    expect(expectedValue(price, 0.55), closeTo(0.05, 1e-9));
    expect(
      clearsEdge(
        pointGap: 2.5,
        expectedProfit: -0.01,
        pointThreshold: 2.5,
        minExpectedValue: 0.02,
      ),
      isTrue,
    );
    expect(
      clearsEdge(
        pointGap: 1,
        expectedProfit: 0.01,
        pointThreshold: 2.5,
        minExpectedValue: 0.02,
      ),
      isFalse,
    );
    expect(
      clearsEdge(
        pointGap: 0.5,
        expectedProfit: 0.03,
        pointThreshold: 2.5,
        minExpectedValue: 0.02,
      ),
      isTrue,
    );
  });

  test(
    'home cover uses the betting number, and a logged line beats the close',
    () {
      expect(homeCovered(4, -3.5), isTrue);
      expect(homeCovered(3, -3.5), isFalse);
      expect(homeCovered(3, -3), isNull);
      final bet = TrackedBet(
        id: '1',
        placedAt: DateTime.utc(2026, 11, 1),
        description: 'Bills +3.5',
        book: 'FanDuel',
        decimal: americanToDecimal(-110),
        stake: 10,
        result: BetResult.pending,
        market: 'spreads',
        side: 'away',
        line: 3.5,
        closingLine: 2.5,
      );
      expect(bet.lineClvPoints, closeTo(1, 1e-9));
      final over = bet.copyWith(
        market: 'totals',
        side: 'over',
        line: 47.5,
        closingLine: 48.5,
      );
      expect(over.lineClvPoints, closeTo(1, 1e-9));
      final under = over.copyWith(side: 'under');
      expect(under.lineClvPoints, closeTo(-1, 1e-9));
      final roundTrip = TrackedBet.fromJson(bet.toJson());
      expect(roundTrip.line, 3.5);
      expect(roundTrip.closingLine, 2.5);
      expect(roundTrip.market, 'spreads');
      final ledger = BetLedger([bet, over]);
      expect(ledger.beatClosingNumber, 2);
      expect(ledger.averageLineClv, closeTo(1, 1e-9));
    },
  );

  test('the bundled model file has 32 teams and a real walk-forward', () {
    final file = File('assets/nfl-model.json');
    expect(file.existsSync(), isTrue, reason: 'Run python model/train.py');
    final model = CoachModel.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
    expect(model.teams, hasLength(32));
    expect(model.backtest.seasons.length, greaterThan(3));
    expect(model.backtest.games, greaterThan(500));
    expect(model.backtest.hitRate, isNotNull);
    expect(model.backtest.hitRate!, inInclusiveRange(0.35, 0.65));
    expect(model.backtest.roi, isNotNull);
    expect(model.backtest.clvBeatRate, isNotNull);
    expect(model.backtest.plainEnglish, isNotEmpty);
    expect(model.source.license, 'CC BY 4.0');
    expect(model.cover.features, contains('spread_edge'));
    expect(model.total.features, contains('total_edge'));
    expect(model.backtest.logLoss, isNotNull);
    final version = model.lineVersion;
    expect(version, isNotNull);
    expect(model.usesV2, isTrue);
    expect(version!.report.games, greaterThanOrEqualTo(1000));
    expect(version.report.brier!, lessThan(model.backtest.brier!));
    expect(version.report.logLoss!, lessThan(model.backtest.logLoss!));
    expect(version.hasEdge, isFalse);
    expect(version.differsHelped, isFalse);
    expect(version.players.length, greaterThan(200));
    expect(
      version.players.length,
      lessThan(2500),
      reason: 'The live file keeps this season, not every player who ever snapped.',
    );
    expect(model.liveReport.hasEdge, isFalse);
    final chiefs = model.team('Kansas City Chiefs');
    final bills = model.team('BUF');
    expect(chiefs, isNotNull);
    expect(bills, isNotNull);
  });

  test('Coach\'s Line uses the books\' number and flags a 2.5 point gap', () {
    final now = DateTime.utc(2026, 11, 12);
    final board = demoBoard(now);
    final model = _fixtureModel();
    final game = board.events.first;
    final line = model.lineFor(game, board.quotes, settings: model.settings);
    expect(line, isNotNull);
    expect(line!.booksSpread, 'Chiefs -3.5');
    expect(line.homeCoverProbability, isNotNull);
    expect(line.overProbability, isNotNull);
    expect(line.flagged, isTrue);
    expect(line.projectedMargin, greaterThan(3.5));
    // A missing team is left blank rather than given a zero.
    expect(
      model.lineFor(
        SportEvent('x', 'Not A Club', 'Kansas City Chiefs', now),
        board.quotes,
        settings: model.settings,
      ),
      isNull,
    );
  });

  testWidgets('the games list shows Coach\'s Line as a comparison', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 11, 12);
    final board = demoBoard(now);
    final model = _fixtureModel();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GamesScreen(
            board: board,
            now: now,
            model: model,
            settings: model.settings,
          ),
        ),
      ),
    );
    expect(find.text("Coach's Line"), findsWidgets);
    expect(find.textContaining('Our number:'), findsWidgets);
    expect(find.text('Chiefs -3.5'), findsWidgets);
    expect(find.textContaining('The books:'), findsNothing);
    expect(find.text('Differs from books'), findsWidgets);
    expect(find.text('Edge'), findsNothing);
    expect(
      find.textContaining('The past test of this number lost money.'),
      findsWidgets,
    );
    expect(find.textContaining('only a comparison'), findsWidgets);
    expect(find.textContaining('Bet the'), findsNothing);
    expect(find.text('Shown for comparison, not a pick.'), findsNothing);
    expect(find.textContaining('The comparison is not a pick.'), findsOneWidget);
    await tester.tap(find.text('Buffalo Bills').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Why').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Chance the favorite covers'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Comparison, not a pick.'),
      300,
    );
    expect(find.text('Comparison, not a pick.'), findsOneWidget);
  });

  testWidgets('My Bets compares the logged number with the closing number', (
    tester,
  ) async {
    final store = MemoryResearchStore();
    await store.saveBet(
      TrackedBet(
        id: 'bet-clv',
        placedAt: DateTime.utc(2026, 11, 10),
        description: 'Bills +3.5',
        book: 'FanDuel',
        decimal: americanToDecimal(-110),
        stake: 20,
        result: BetResult.pending,
        market: 'spreads',
        side: 'away',
        line: 3.5,
        closingLine: 2.5,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MyBetsScreen(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bet log'));
    await tester.pumpAndSettle();
    expect(find.text('Beat the close on 1 of 1 · +1.0 pts.'), findsOneWidget);
    expect(find.text('Beat the close by 1.0 pts.'), findsOneWidget);
  });

  testWidgets('the model page explains the past test in plain language', (
    tester,
  ) async {
    final model = _fixtureModel();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ModelScreen(
                model: model,
                settings: model.settings,
                onPoints: (_) {},
                onMinExpectedValue: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Team strength'), findsOneWidget);
    expect(find.text('Kansas City Chiefs'), findsOneWidget);
    expect(find.textContaining('do not guarantee'), findsOneWidget);
    expect(find.textContaining('CC BY 4.0'), findsOneWidget);
    expect(find.textContaining('not an edge'), findsOneWidget);
  });
}

CoachModel _fixtureModel() {
  LogisticModel flat(
    List<String> names, {
    double slope = 0,
    int slopeIndex = 0,
  }) {
    return LogisticModel(
      features: names,
      mean: List.filled(names.length, 0),
      scale: List.filled(names.length, 1),
      coefficients: [
        for (var i = 0; i < names.length; i++) i == slopeIndex ? slope : 0,
      ],
      intercept: 0,
    );
  }

  TeamStrength team(String abbr, String name, int rank, double net) =>
      TeamStrength(
        abbr: abbr,
        name: name,
        rank: rank,
        offEpa: net,
        defEpa: 0,
        netEpa: net,
        strengthPoints: 40 * net,
        offensePoints: 40 * net,
        defensePoints: 0,
        successRate: 0.45,
        explosiveRate: 0.1,
        turnoverRate: 0.02,
        formEpa: 0,
        playersOut: 0,
        lastGame: '2026-11-08',
        samplePlays: 800,
      );

  return CoachModel(
    generatedAt: '2026-11-12T00:00:00Z',
    asOf: '2026-11-09',
    source: const ModelSource(
      name: 'nflverse',
      license: 'CC BY 4.0',
      url: 'https://github.com/nflverse/nflverse-data',
      licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
      changes: 'Test fixture.',
    ),
    settings: const EdgeSettings(
      spreadPoints: 2.5,
      totalPoints: 2.5,
      minExpectedValue: 0.02,
    ),
    marginScale: 40,
    homeFieldAdvantage: 1.5,
    totalIntercept: 44,
    totalScale: 10,
    cover: flat(const [
      'spread_edge',
      'off_diff',
      'def_diff',
      'form_diff',
      'rest_diff',
      'success_diff',
      'explosive_diff',
      'turnover_diff',
      'out_diff',
    ], slope: 0.1),
    total: flat(const [
      'total_edge',
      'off_sum',
      'def_sum',
      'explosive_sum',
      'success_sum',
      'rest_sum',
      'out_sum',
    ], slope: 0.05),
    teams: [
      team('KC', 'Kansas City Chiefs', 1, 0.15),
      team('BUF', 'Buffalo Bills', 2, -0.05),
    ],
    backtest: const BacktestReport(
      method: 'Walk-forward by week.',
      seasons: [2018, 2019, 2020, 2021, 2022, 2023, 2024],
      games: 1000,
      decided: 980,
      wins: 500,
      losses: 480,
      pushes: 20,
      hitRate: 0.510,
      roi: -0.02,
      brier: 0.25,
      calibration: [],
      clvBeatRate: 0.49,
      clvGames: 1000,
      meanModelError: 10.4,
      meanMarketError: 10.2,
      favoriteHitRate: 0.50,
      homeHitRate: 0.50,
      flaggedGames: 100,
      flaggedDecided: 98,
      flaggedHitRate: 0.51,
      flaggedRoi: -0.01,
      flaggedRule: '2.5 points',
      totalsHitRate: 0.50,
      totalsRoi: -0.03,
      hasEdge: false,
      plainEnglish: 'That is not an edge. A -110 bet needs about 52.4% just to break even.',
    ),
  );
}
