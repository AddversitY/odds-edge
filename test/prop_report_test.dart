import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/player_stats.dart';
import 'package:odds_edge/domain/prop_chance.dart';
import 'package:odds_edge/domain/prop_report.dart';

PlayerGame game({
  required int season,
  required int week,
  required num yards,
  String playerId = 'qb',
  int attempts = 30,
}) {
  return PlayerGame(
    playerId: playerId,
    name: 'Test Quarterback',
    position: 'QB',
    team: 'BUF',
    opponent: 'MIA',
    season: season,
    week: week,
    date: DateTime.utc(season, 9, week),
    seasonType: 'REG',
    stats: {'passing_yards': yards, 'attempts': attempts},
  );
}

void main() {
  test('a later week does not change the chance used for an earlier week', () {
    final prior = [
      for (var week = 1; week <= 8; week++)
        game(season: 2024, week: week, yards: 200 + week * 20),
    ];
    final early = [
      game(season: 2025, week: 1, yards: 280),
      game(season: 2025, week: 2, yards: 120),
    ];
    final withoutFuture = walkForwardPropChance([
      ...prior,
      ...early,
    ], keepForecasts: true);
    final withFuture = walkForwardPropChance([
      ...prior,
      ...early,
      game(season: 2025, week: 6, yards: 500),
    ], keepForecasts: true);
    expect(withoutFuture.forecastChances, hasLength(2));
    expect(withFuture.forecastChances.take(2), withoutFuture.forecastChances);
    expect(withFuture.usedSportsbookPrices, isFalse);
    expect(withFuture.hasEdge, isFalse);
    expect(withFuture.plainEnglish, contains('not a pick'));
    expect(withFuture.notTested, contains('No historical sportsbook'));
  });

  test('the chance is the same function as the card, anchored at 50%', () {
    final prior = [
      for (var week = 1; week <= 10; week++)
        game(season: 2024, week: week, yards: week.isEven ? 300 : 100),
    ];
    final lineValues = [
      for (final row in prior) row.stats['passing_yards']!.toDouble(),
    ]..sort();
    final line = (lineValues[4] + lineValues[5]) / 2;
    var hits = 0;
    for (final value in lineValues) {
      if (value > line) hits++;
    }
    final expected = propSideChance(
      hits: hits,
      observed: prior.length,
      market: propReportMarketProxy,
    );
    final report = walkForwardPropChance([
      ...prior,
      game(season: 2025, week: 1, yards: line + 10),
    ], keepForecasts: true);
    expect(report.scored, 1);
    expect(report.forecastChances.single, expected);
    expect(report.marketProxy, 0.5);
  });

  test('the first season has no line, so it is not scored', () {
    final report = walkForwardPropChance([
      for (var week = 1; week <= 8; week++)
        game(season: 2025, week: week, yards: 250),
    ]);
    expect(report.scored, 0);
    expect(report.brier, isNull);
    expect(report.plainEnglish, contains('No sportsbook prop price'));
  });

  test(
    'the bundled box scores publish a prop report and do not claim an edge',
    () {
      final data = PlayerStatsDataset.fromJson(
        jsonDecode(
          File('assets/nfl-player-stats.json')
              .readAsStringSync()
              .replaceFirst('\uFEFF', ''),
        ),
      );
      final report = walkForwardPropChance(data.rows);
      expect(report.usedSportsbookPrices, isFalse);
      expect(report.hasEdge, isFalse);
      expect(report.scored, greaterThan(1000));
      expect(report.brier, inInclusiveRange(0.15, 0.35));
      expect(report.logLoss, inInclusiveRange(0.4, 1.0));
      expect(report.plainEnglish, contains('not a pick'));
      expect(report.notTested, contains('closing-line value'));
      expect(report.brier!, lessThan(report.baselineBrier));
      expect(report.calibration.where((bin) => bin.games > 0), isNotEmpty);
    },
  );

  test('a same-week game is not used to score that week', () {
    final prior = [
      for (var week = 1; week <= 6; week++)
        game(season: 2024, week: week, yards: 240),
    ];
    final quiet = walkForwardPropChance([
      ...prior,
      game(season: 2025, week: 1, yards: 10, playerId: 'qb'),
    ], keepForecasts: true);
    final crowded = walkForwardPropChance([
      ...prior,
      game(season: 2025, week: 1, yards: 10),
      game(season: 2025, week: 1, yards: 400, playerId: 'other'),
    ], keepForecasts: true);
    expect(quiet.forecastChances, isNotEmpty);
    expect(crowded.forecastChances.first, quiet.forecastChances.first);
  });
}
