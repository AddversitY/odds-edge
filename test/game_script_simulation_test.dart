import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/game_script_simulation.dart';
import 'package:odds_edge/domain/history.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/player_stats.dart';
import 'package:odds_edge/domain/prop_projection.dart' show normalCdf;

ScriptLeg leg(
  String id, {
  String event = 'g',
  String player = 'p',
  double chance = .6,
  String metric = 'passing_yards',
  double line = 200.5,
  bool over = true,
}) => ScriptLeg(
  id: id,
  eventId: event,
  playerId: player,
  team: 'BUF',
  metric: metric,
  line: line,
  over: over,
  chance: chance,
  mean: metric == 'receptions' ? 5 : 240,
  sd: metric == 'receptions' ? 3 : 50,
);
final event = SportEvent('g', 'KC', 'BUF', DateTime.utc(2026, 11, 15));

void main() {
  test('missing-pair covariance is repaired and remains reconstructable', () {
    final fit = fitScriptMatrix(
      ['a', 'b', 'c'],
      [
        for (var i = 0; i < 300; i++) ...[
          [i.toDouble(), i.toDouble(), null],
          [i.toDouble(), null, i.toDouble()],
          [null, i.toDouble(), -i.toDouble()],
        ],
      ],
      2026,
    );
    expect(fit.psdScale, lessThan(1));
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        var reconstructed = 0.0;
        for (var k = 0; k < 3; k++) {
          reconstructed += fit.lower[i][k] * fit.lower[j][k];
        }
        expect(reconstructed, closeTo(fit.matrix[i][j], 1e-9));
      }
    }
  });
  test(
    'empirical simulation matches analytic copula and reverses for an under',
    () {
      final games = [
        for (var i = 0; i < 180; i++)
          HistoricalGame(
            season: 2025,
            week: i + 1,
            date: DateTime.utc(2025, 3, 1).add(Duration(days: i)),
            home: 'BUF',
            away: 'KC',
            homeScore: i + 7,
            awayScore: 3,
          ),
      ];
      final players = [
        for (var i = 0; i < games.length; i++)
          for (final id in ['p', 'q'])
            PlayerGame(
              playerId: id,
              name: id,
              position: 'QB',
              team: 'BUF',
              opponent: 'KC',
              season: 2025,
              week: i + 1,
              date: games[i].date,
              seasonType: 'REG',
              stats: {'passing_yards': i * (id == 'p' ? 10 : 3)},
            ),
      ];
      ScriptSimulation run(bool over) => simulateGameScripts(
        legs: [
          leg('a', chance: .5),
          leg('b', player: 'q', chance: .5, over: over),
        ],
        events: [event],
        players: players,
        games: games,
        beforeSeason: 2026,
      );
      final both = run(true), reversed = run(false);
      final analytic = .25 + math.asin(.65) / (2 * math.pi);
      expect(both.joint, closeTo(analytic, .015));
      expect(reversed.joint, closeTo(.5 - analytic, .015));
      expect(both.joint, greaterThan(both.independent));
      expect(both.failureLegs, isNotEmpty);
      expect(both.failurePatternShare, inInclusiveRange(0, 1));
    },
  );
  test('normal inverse round trips through tails and counts', () {
    for (final p in [.00001, .001, .05, .2, .5, .9, .99999]) {
      expect(normalCdf(scriptNormalQuantile(p)), closeTo(p, 1e-8));
    }
  });
  test('sparse pairs and constant columns revert to independence', () {
    final fit = fitScriptMatrix(
      ['a', 'b'],
      [
        for (var i = 0; i < 11; i++) [i.toDouble(), i.toDouble()],
      ],
      2026,
    );
    expect(fit.matrix[0][1], 0);
    expect(fit.pairs[0][1], 11);
    final constant = fitScriptMatrix(
      ['a', 'b'],
      [
        for (var i = 0; i < 50; i++) [1.0, i.toDouble()],
      ],
      2026,
    );
    expect(constant.matrix[0][1], 0);
  });
  test('empirical ranks shrink and cap; valid covariance reconstructs', () {
    final fit = fitScriptMatrix(
      ['a', 'b', 'c'],
      [
        for (var i = 0; i < 300; i++)
          [i.toDouble(), i.toDouble(), -i.toDouble()],
      ],
      2026,
    );
    expect(fit.matrix[0][1], closeTo(.65, 1e-10));
    expect(fit.matrix[0][2], closeTo(-.65, 1e-10));
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        var actual = 0.0;
        for (var k = 0; k < 3; k++) {
          actual += fit.lower[i][k] * fit.lower[j][k];
        }
        expect(actual, closeTo(fit.matrix[i][j], 1e-9));
      }
    }
  });
  test(
    'training excludes the entire target season, including earlier weeks',
    () {
      final games = [
        for (var y = 2024; y <= 2026; y++)
          for (var w = 1; w <= 15; w++)
            HistoricalGame(
              season: y,
              week: w,
              date: DateTime.utc(y, 9, w),
              home: 'BUF',
              away: 'KC',
              homeScore: w + 10,
              awayScore: 7,
            ),
      ];
      final rows = [
        for (final g in games)
          PlayerGame(
            playerId: 'p',
            name: 'Player',
            position: 'QB',
            team: 'BUF',
            opponent: 'KC',
            season: g.season,
            week: g.week,
            date: g.date,
            seasonType: 'REG',
            stats: {'passing_yards': g.week * 10},
          ),
      ];
      final fit = fitScriptCorrelation(
        legs: [leg('a')],
        event: event,
        players: rows,
        games: games,
        beforeSeason: 2026,
      );
      final prior = fitScriptCorrelation(
        legs: [leg('a')],
        event: event,
        players: rows.where((r) => r.season < 2026).toList(),
        games: games.where((g) => g.season < 2026).toList(),
        beforeSeason: 2026,
      );
      expect(fit.trainingGames, 30);
      expect(fit.matrix, prior.matrix);
    },
  );
  test('seeded draws preserve marginals and separate-game independence', () {
    final legs = [leg('a'), leg('b', event: 'other', player: 'q', chance: .4)];
    ScriptSimulation run() => simulateGameScripts(
      legs: legs,
      events: [
        event,
        SportEvent('other', 'BUF', 'KC', DateTime.utc(2026, 11, 22)),
      ],
      players: [],
      games: [],
      beforeSeason: 2026,
    );
    final result = run();
    expect(result.joint, run().joint);
    expect(result.legHitRates[0], closeTo(.6, .015));
    expect(result.legHitRates[1], closeTo(.4, .015));
    expect(result.joint, closeTo(.24, .015));
    expect(result.standardError, greaterThan(0));
  });
  test(
    'receptions draw integers from a count curve with the displayed chance',
    () {
      final result = simulateGameScripts(
        legs: [
          leg('a', metric: 'receptions', line: 4.5, chance: .7),
          leg('b', player: 'q'),
        ],
        events: [event],
        players: [],
        games: [],
        beforeSeason: 2026,
      );
      expect(result.legHitRates[0], closeTo(.7, .015));
      expect(result.meanStats[0], greaterThanOrEqualTo(0));
    },
  );
  test('opposites, duplicate exposures, inconsistent alt-lines and push lines are rejected', () {
    void run(List<ScriptLeg> legs) => simulateGameScripts(
      legs: legs,
      events: [event],
      players: [],
      games: [],
      beforeSeason: 2026,
    );
    expect(() => run([leg('a'), leg('a')]), throwsArgumentError);
    expect(() => run([leg('a'), leg('b', over: false)]), throwsArgumentError);
    expect(
      () => run([leg('a'), leg('b', line: 250.5, chance: .8)]),
      throwsArgumentError,
    );
    expect(
      () => run([leg('a', line: 200), leg('b', player: 'q')]),
      throwsArgumentError,
    );
    expect(
      () => run([leg('a', chance: double.nan), leg('b', player: 'q')]),
      throwsArgumentError,
    );
  });
}
