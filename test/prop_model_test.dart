import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/history.dart';
import 'package:odds_edge/domain/hit_rate.dart';
import 'package:odds_edge/domain/matchup.dart';
import 'package:odds_edge/domain/player_stats.dart';
import 'package:odds_edge/domain/prop_chance.dart';
import 'package:odds_edge/domain/prop_clv.dart';
import 'package:odds_edge/domain/prop_model.dart';
import 'package:odds_edge/domain/prop_projection.dart';
import 'package:odds_edge/domain/public_sharp.dart';

PlayerGame box({
  required String id,
  required String name,
  required String position,
  required String team,
  required String opponent,
  required int season,
  required int week,
  required Map<String, num> stats,
}) {
  return PlayerGame(
    playerId: id,
    name: name,
    position: position,
    team: team,
    opponent: opponent,
    season: season,
    week: week,
    date: DateTime.utc(season, 9, week.clamp(1, 28)),
    seasonType: 'REG',
    stats: stats,
  );
}

List<PlayerGame> receiverSeason({
  required int season,
  required int weeks,
}) {
  return [
    for (var week = 1; week <= weeks; week++) ...[
      box(
        id: 'qb',
        name: 'Pass Game',
        position: 'QB',
        team: 'DET',
        opponent: 'MIA',
        season: season,
        week: week,
        stats: {'attempts': 40, 'passing_yards': 250},
      ),
      box(
        id: 'wr',
        name: 'Amon-Ra St. Brown',
        position: 'WR',
        team: 'DET',
        opponent: 'MIA',
        season: season,
        week: week,
        stats: {'targets': 8, 'receptions': 5, 'receiving_yards': 64},
      ),
      box(
        id: 'mate',
        name: 'Wide Out',
        position: 'WR',
        team: 'DET',
        opponent: 'MIA',
        season: season,
        week: week,
        stats: {'targets': 10, 'receptions': 7, 'receiving_yards': 90},
      ),
    ],
  ];
}

PropProjection projectReceiver(
  List<PlayerGame> rows, {
  String opponent = 'MIA',
  double? teamSpread,
  double? total,
  int beforeSeason = 2025,
  int beforeWeek = 1,
  List<({String name, String position})> teammateOuts = const [],
}) {
  final index = UsageIndex.build(rows);
  final face = projectProp(
    index: index,
    playerId: 'wr',
    metric: 'receiving_yards',
    line: 60.5,
    side: LineSide.over,
    beforeSeason: beforeSeason,
    beforeWeek: beforeWeek,
    team: 'DET',
    opponent: opponent,
    teamSpread: teamSpread,
    total: total,
    market: 0.5,
    teammateOuts: teammateOuts,
  );
  expect(face, isNotNull);
  return face!;
}

void main() {
  test('a projection shrinks toward the no-vig and stays inside the cap', () {
    final open = shrinkProjectedChance(
      projected: 0.80,
      observed: 8,
      market: 0.50,
    );
    expect(open, closeTo((8 * 0.80 + 32 * 0.50) / 40, 1e-9));

    final capped = shrinkProjectedChance(
      projected: 0.99,
      observed: 8,
      market: 0.40,
    );
    expect(capped, closeTo(0.50, 1e-9));
    expect((capped! - 0.40).abs(), lessThanOrEqualTo(0.10 + 1e-9));

    final wide = shrinkProjectedChance(
      projected: 0.90,
      observed: 40,
      market: 0.50,
    );
    expect(wide, closeTo(0.65, 1e-9));
    expect((wide! - 0.50).abs(), lessThanOrEqualTo(0.15 + 1e-9));
    expect((wide - 0.50).abs(), greaterThan(0.10));

    expect(
      shrinkProjectedChance(projected: 0.80, observed: 8, market: null),
      closeTo((8 * 0.80 + 2) / 12, 1e-9),
    );
    expect(
      shrinkProjectedChance(projected: 0.80, observed: 3, market: 0.50),
      isNull,
    );
  });

  test('a half-point line splits the two sides, and a higher mean raises the over', () {
    const mean = 250.0;
    const width = 40.0;
    final over = sideChance(
      metric: 'passing_yards',
      mean: mean,
      sd: width,
      line: 249.5,
      side: LineSide.over,
    );
    final under = sideChance(
      metric: 'passing_yards',
      mean: mean,
      sd: width,
      line: 249.5,
      side: LineSide.under,
    );
    expect(over + under, closeTo(1, 1e-6));
    final higher = sideChance(
      metric: 'passing_yards',
      mean: mean + 30,
      sd: width,
      line: 249.5,
      side: LineSide.over,
    );
    expect(higher, greaterThan(over));

    final catchesOver = sideChance(
      metric: 'receptions',
      mean: 4.6,
      sd: 2,
      line: 4.5,
      side: LineSide.over,
    );
    final catchesUnder = sideChance(
      metric: 'receptions',
      mean: 4.6,
      sd: 2,
      line: 4.5,
      side: LineSide.under,
    );
    expect(catchesOver + catchesUnder, closeTo(1, 1e-6));
    final integerOver = sideChance(
      metric: 'receptions',
      mean: 5,
      sd: 2,
      line: 5,
      side: LineSide.over,
    );
    final integerUnder = sideChance(
      metric: 'receptions',
      mean: 5,
      sd: 2,
      line: 5,
      side: LineSide.under,
    );
    expect(integerOver + integerUnder, lessThan(1));
  });

  test('team total, a softer defense, and a teammate out move the mean', () {
    final rows = receiverSeason(season: 2024, weeks: 8);
    final quiet = projectReceiver(rows, teamSpread: 7, total: 38);
    final loud = projectReceiver(rows, teamSpread: -7, total: 55);
    expect(loud.mean, greaterThan(quiet.mean));

    final padded = [
      ...rows,
      for (var week = 1; week <= 4; week++) ...[
        box(
          id: 'soft-qb',
          name: 'Soft Passer',
          position: 'QB',
          team: 'CLE',
          opponent: 'SOFT',
          season: 2024,
          week: week,
          stats: {'attempts': 40, 'passing_yards': 320},
        ),
        box(
          id: 'soft-wr',
          name: 'Soft Catcher',
          position: 'WR',
          team: 'CLE',
          opponent: 'SOFT',
          season: 2024,
          week: week,
          stats: {'targets': 12, 'receptions': 8, 'receiving_yards': 280},
        ),
        box(
          id: 'hard-qb',
          name: 'Hard Passer',
          position: 'QB',
          team: 'NYJ',
          opponent: 'HARD',
          season: 2024,
          week: week,
          stats: {'attempts': 40, 'passing_yards': 140},
        ),
        box(
          id: 'hard-wr',
          name: 'Hard Catcher',
          position: 'WR',
          team: 'NYJ',
          opponent: 'HARD',
          season: 2024,
          week: week,
          stats: {'targets': 6, 'receptions': 3, 'receiving_yards': 70},
        ),
      ],
    ];
    final soft = projectReceiver(padded, opponent: 'SOFT');
    final hard = projectReceiver(padded, opponent: 'HARD');
    expect(soft.mean, greaterThan(hard.mean));
    expect(
      soft.factors.map((factor) => factor.delta).reduce((a, b) => a + b),
      closeTo(soft.mean, 1e-6),
    );

    final healthy = projectReceiver(rows);
    final missing = projectReceiver(
      rows,
      teammateOuts: [(name: 'Wide Out', position: 'WR')],
    );
    expect(missing.mean, greaterThan(healthy.mean));
    expect(
      missing.factors.singleWhere((factor) => factor.label == 'Teammates out').detail,
      '1 out',
    );
  });

  test('a later week does not change an earlier projection', () {
    final early = receiverSeason(season: 2024, weeks: 8);
    final weekOne = box(
      id: 'wr',
      name: 'Amon-Ra St. Brown',
      position: 'WR',
      team: 'DET',
      opponent: 'GB',
      season: 2025,
      week: 1,
      stats: {'targets': 11, 'receptions': 8, 'receiving_yards': 110},
    );
    final sameWeek = box(
      id: 'wr',
      name: 'Amon-Ra St. Brown',
      position: 'WR',
      team: 'DET',
      opponent: 'GB',
      season: 2025,
      week: 3,
      stats: {'targets': 14, 'receptions': 11, 'receiving_yards': 180},
    );
    final later = box(
      id: 'wr',
      name: 'Amon-Ra St. Brown',
      position: 'WR',
      team: 'DET',
      opponent: 'CHI',
      season: 2025,
      week: 6,
      stats: {'targets': 15, 'receptions': 12, 'receiving_yards': 200},
    );
    final base = projectReceiver([...early, weekOne], beforeWeek: 3);
    final withSameWeek = projectReceiver(
      [...early, weekOne, sameWeek],
      beforeWeek: 3,
    );
    final withLater = projectReceiver(
      [...early, weekOne, sameWeek, later],
      beforeWeek: 3,
    );
    expect(withSameWeek.mean, closeTo(base.mean, 1e-9));
    expect(withSameWeek.chance, closeTo(base.chance!, 1e-9));
    expect(withLater.mean, closeTo(base.mean, 1e-9));
    expect(withLater.rawChance, closeTo(base.rawChance, 1e-9));

    final history = [
      for (var week = 1; week <= 8; week++) ...[
        box(
          id: 'qb',
          name: 'Pass Game',
          position: 'QB',
          team: 'DET',
          opponent: 'MIA',
          season: 2024,
          week: week,
          stats: {'attempts': 40, 'passing_yards': 250},
        ),
        box(
          id: 'wr',
          name: 'Amon-Ra St. Brown',
          position: 'WR',
          team: 'DET',
          opponent: 'MIA',
          season: 2024,
          week: week,
          stats: {
            'targets': 8,
            'receiving_yards': 40 + week * 7,
          },
        ),
      ],
    ];
    final first = box(
      id: 'wr',
      name: 'Amon-Ra St. Brown',
      position: 'WR',
      team: 'DET',
      opponent: 'GB',
      season: 2025,
      week: 1,
      stats: {'targets': 9, 'receiving_yards': 30},
    );
    final sunday = box(
      id: 'wr',
      name: 'Amon-Ra St. Brown',
      position: 'WR',
      team: 'DET',
      opponent: 'CHI',
      season: 2025,
      week: 6,
      stats: {'targets': 12, 'receiving_yards': 160},
    );
    final scored = comparePropModels(
      [...history, first],
      keepForecasts: true,
    );
    final scoredLater = comparePropModels(
      [...history, first, sunday],
      keepForecasts: true,
    );
    expect(scored.usageChances, isNotEmpty);
    expect(
      scoredLater.usageChances.take(scored.usageChances.length),
      scored.usageChances,
    );
    expect(
      scoredLater.calibratedChances.take(scored.calibratedChances.length),
      scored.calibratedChances,
    );
    expect(scoredLater.usageChances.length, greaterThan(scored.usageChances.length));
    expect(scored.record.usedSportsbookPrices, isFalse);
    expect(scored.record.hasEdge, isFalse);
    expect(scored.sentence, contains('not a pick'));
    expect(scored.sentence, contains('closing spread was not used'));
  });

  test('two saved prop prices produce a closing-line value and spend nothing', () {
    LineSnapshot shot(DateTime at, double over, double under) => LineSnapshot(
      at: at,
      prices: [
        LinePrice(
          bookId: 'draftkings',
          market: 'player_rush_yds',
          outcome: 'Over',
          decimal: over,
          point: 72.5,
          player: 'James Cook',
        ),
        LinePrice(
          bookId: 'draftkings',
          market: 'player_rush_yds',
          outcome: 'Under',
          decimal: under,
          point: 72.5,
          player: 'James Cook',
        ),
      ],
    );
    final history = {
      'game': [
        shot(DateTime.utc(2026, 11, 1, 12), 1.91, 1.91),
        shot(DateTime.utc(2026, 11, 2, 16), 1.70, 2.15),
      ],
    };
    final toward = propClosingValue(
      history,
      overChance: (player, market, line, at, earlier) => 0.62,
    );
    expect(toward.compared, 1);
    expect(toward.average, isNotNull);
    expect(toward.average!, greaterThan(0));
    expect(toward.sentence, contains('not a pick'));

    final away = propClosingValue(
      history,
      overChance: (player, market, line, at, earlier) => 0.40,
    );
    expect(away.average!, lessThan(0));
    expect(propClosingValue(const {}).sentence, contains('blank'));
  });

  test(
    'the bundled walk-forward locks whether version 2 is the card chance',
    () {
      final rows = PlayerStatsDataset.fromJson(
        jsonDecode(
          File('assets/nfl-player-stats.json')
              .readAsStringSync()
              .replaceFirst('\uFEFF', ''),
        ),
      ).rows;
      final history = jsonDecode(
        File('assets/nfl-history.json').readAsStringSync().replaceFirst('\uFEFF', ''),
      );
      final scores = [
        for (final row in history['games'] as List)
          if (row is Map)
            HistoricalGame.fromJson(Map<String, dynamic>.from(row)),
      ];
      final matchup = MatchupContext.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(
            File('assets/nfl-matchup.json')
                .readAsStringSync()
                .replaceFirst('\uFEFF', ''),
          ),
        ),
      );
      final comparison = comparePropModels(
        rows,
        scores: scores,
        matchup: matchup,
      );
      // ignore: avoid_print
      print(comparison.sentence);
      // ignore: avoid_print
      print(
        'paired ${comparison.paired} missing ${comparison.usageMissing} '
        'live ${comparison.live.name} adopted ${comparison.adopted} '
        'record brier ${comparison.pairedRecord.brier} log ${comparison.pairedRecord.logLoss} '
        'usage brier ${comparison.usage.brier} log ${comparison.usage.logLoss} '
        'calibrated brier ${comparison.calibrated.brier} log ${comparison.calibrated.logLoss}',
      );
      void dump(String name, ChanceBoard board) {
        for (final bin in board.calibration) {
          // ignore: avoid_print
          print(
            '$name ${bin.from}-${bin.to} n ${bin.games} '
            'pred ${bin.predicted.toStringAsFixed(3)} act ${bin.actual.toStringAsFixed(3)}',
          );
        }
      }

      dump('record', comparison.pairedRecord);
      dump('usage', comparison.usage);
      dump('calibrated', comparison.calibrated);
      expect(comparison.record.usedSportsbookPrices, isFalse);
      expect(comparison.record.hasEdge, isFalse);
      expect(comparison.sentence, contains('not a pick'));
      expect(comparison.sentence, contains('No sportsbook prop price'));
      expect(comparison.sentence, contains('closing spread was not used'));
      expect(comparison.sentence, contains('earlier weeks'));
      expect(comparison.paired, greaterThan(0));
      expect(comparison.calibrated.scored, comparison.usage.scored);
      expect(propLiveChance, comparison.live);
      expect(propV2Adopted, comparison.adopted);
      if (comparison.live == PropLiveChance.calibrated) {
        expect(comparison.paired, greaterThanOrEqualTo(1000));
        expect(
          comparison.calibrated.brier!,
          lessThan(comparison.pairedRecord.brier!),
        );
        expect(
          comparison.calibrated.logLoss!,
          lessThan(comparison.pairedRecord.logLoss!),
        );
        expect(comparison.calibrated.brier!, lessThan(comparison.usage.brier!));
        expect(
          comparison.calibrated.logLoss!,
          lessThan(comparison.usage.logLoss!),
        );
      } else if (comparison.live == PropLiveChance.usage) {
        expect(comparison.paired, greaterThanOrEqualTo(1000));
        expect(comparison.usage.brier!, lessThan(comparison.pairedRecord.brier!));
        expect(
          comparison.usage.logLoss!,
          lessThan(comparison.pairedRecord.logLoss!),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
