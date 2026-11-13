import 'dart:math' as math;

import 'coach_model.dart';
import 'history.dart';
import 'hit_rate.dart';
import 'matchup.dart';
import 'player_stats.dart';
import 'prop_chance.dart';
import 'prop_projection.dart';
import 'prop_report.dart';

/// Whether the card's chance is the usage projection.
///
/// Set from the bundled walk-forward. Version 2 is used only when it has
/// a lower Brier score and a lower log loss than the record, on the same
/// player-games, with at least 1,000 of them. The test checks this flag
/// against a fresh run. A better forecast on a made-up line is still not
/// a betting edge.
const propV2Adopted = true;

class ChanceBoard {
  const ChanceBoard({
    required this.scored,
    required this.brier,
    required this.logLoss,
    required this.baselineBrier,
    required this.baselineLogLoss,
    required this.calibration,
  });

  final int scored;
  final double? brier;
  final double? logLoss;
  final double baselineBrier;
  final double baselineLogLoss;
  final List<CalibrationBin> calibration;
}

/// Version 1 and version 2 on the same player-games.
class PropModelComparison {
  const PropModelComparison({
    required this.record,
    required this.pairedRecord,
    required this.usage,
    required this.adopted,
    required this.paired,
    required this.usageMissing,
    required this.sentence,
    this.usageChances = const [],
  });

  /// The published hit-rate test, including games version 2 could not score.
  final PropReport record;

  /// Version 1 on the games version 2 also scored.
  final ChanceBoard pairedRecord;

  /// Version 2 on those same games.
  final ChanceBoard usage;
  final bool adopted;
  final int paired;

  /// Games the hit-rate test scored and the projection could not.
  final int usageMissing;
  final String sentence;
  final List<double> usageChances;
}

/// Walk-forward of both chances. To score a week, only earlier weeks
/// are used. The line is the previous season's median, frozen before
/// week 1. The market anchor is a fair 50%. No closing spread is read.
PropModelComparison comparePropModels(
  List<PlayerGame> rows, {
  List<HistoricalGame> scores = const [],
  MatchupContext? matchup,
  bool keepForecasts = false,
}) {
  final usageIndex = UsageIndex.build(rows, scores: scores, matchup: matchup);
  final record = walkForwardPropChance(rows);
  final v1 = <_Call>[];
  final v2 = <_Call>[];
  var missing = 0;
  for (final metric in propReportMetrics) {
    final games = <String, List<PlayerGame>>{};
    for (final game in rows) {
      if (game.seasonType != 'REG') continue;
      if (!_counts(game, metric)) continue;
      (games[game.playerId] ??= []).add(game);
    }
    for (final entry in games.entries) {
      final ordered = [...entry.value]..sort(_order);
      final bySeason = <int, List<PlayerGame>>{};
      for (final game in ordered) {
        (bySeason[game.season] ??= []).add(game);
      }
      final seasons = bySeason.keys.toList()..sort();
      for (var index = 1; index < seasons.length; index++) {
        final season = seasons[index];
        final previous = bySeason[seasons[index - 1]]!;
        if (previous.length < 4) continue;
        final line = _median([
          for (final game in previous) game.stats[metric]!.toDouble(),
        ]);
        if (line < (propReportMinimumLine[metric] ?? 0)) continue;
        final history = <PlayerGame>[
          for (final earlier in seasons.take(index)) ...bySeason[earlier]!,
        ];
        final weeks = <int, List<PlayerGame>>{};
        for (final game in bySeason[season]!) {
          (weeks[game.week] ??= []).add(game);
        }
        final weekNumbers = weeks.keys.toList()..sort();
        for (final week in weekNumbers) {
          final hits = _hits(history, metric, line);
          final v1Chance = hits == null
              ? null
              : propSideChance(
                  hits: hits.hits,
                  observed: hits.observed,
                  market: propReportMarketProxy,
                );
          for (final game in weeks[week]!) {
            final value = game.stats[metric]!.toDouble();
            if (value == line || v1Chance == null) continue;
            final projection = projectProp(
              index: usageIndex,
              playerId: game.playerId,
              metric: metric,
              line: line,
              side: LineSide.over,
              beforeSeason: season,
              beforeWeek: week,
              team: game.team,
              opponent: game.opponent,
              market: propReportMarketProxy,
            );
            final v2Chance = projection?.chance;
            if (v2Chance == null) {
              missing++;
              continue;
            }
            final hit = value > line;
            v1.add(_Call(v1Chance, hit));
            v2.add(_Call(v2Chance, hit));
          }
          history.addAll(weeks[week]!);
        }
      }
    }
  }
  final pairedRecord = _board(v1);
  final usage = _board(v2);
  final adopted = _beats(pairedRecord, usage);
  return PropModelComparison(
    record: record,
    pairedRecord: pairedRecord,
    usage: usage,
    adopted: adopted,
    paired: v2.length,
    usageMissing: missing,
    usageChances: keepForecasts ? [for (final row in v2) row.chance] : const [],
    sentence: _sentence(
      paired: v2.length,
      missing: missing,
      record: pairedRecord,
      usage: usage,
      adopted: adopted,
    ),
  );
}

class _Call {
  const _Call(this.chance, this.hit);
  final double chance;
  final bool hit;
}

class _Hits {
  const _Hits(this.hits, this.observed);
  final int hits, observed;
}

bool _beats(ChanceBoard record, ChanceBoard usage) {
  final leftBrier = record.brier;
  final rightBrier = usage.brier;
  final leftLoss = record.logLoss;
  final rightLoss = usage.logLoss;
  if (leftBrier == null ||
      rightBrier == null ||
      leftLoss == null ||
      rightLoss == null) {
    return false;
  }
  if (usage.scored < 1000 || usage.scored != record.scored) return false;
  return rightBrier < leftBrier && rightLoss < leftLoss;
}

const _bins = <(double, double)>[
  (0.0, 0.40),
  (0.40, 0.45),
  (0.45, 0.50),
  (0.50, 0.55),
  (0.55, 0.60),
  (0.60, 1.01),
];

ChanceBoard _board(List<_Call> rows) {
  const baselineBrier = 0.25;
  final baselineLogLoss = math.log(2);
  if (rows.isEmpty) {
    return ChanceBoard(
      scored: 0,
      brier: null,
      logLoss: null,
      baselineBrier: baselineBrier,
      baselineLogLoss: baselineLogLoss,
      calibration: const [],
    );
  }
  var brierSum = 0.0, lossSum = 0.0;
  for (final row in rows) {
    final outcome = row.hit ? 1.0 : 0.0;
    final chance = row.chance.clamp(1e-6, 1 - 1e-6).toDouble();
    brierSum += (chance - outcome) * (chance - outcome);
    lossSum +=
        -(outcome * math.log(chance) + (1 - outcome) * math.log(1 - chance));
  }
  final calibration = <CalibrationBin>[];
  for (final bin in _bins) {
    final inside = [
      for (final row in rows)
        if (row.chance >= bin.$1 && row.chance < bin.$2) row,
    ];
    if (inside.isEmpty) {
      calibration.add(
        CalibrationBin(
          from: bin.$1,
          to: bin.$2 >= 1 ? 1 : bin.$2,
          games: 0,
          predicted: 0,
          actual: 0,
        ),
      );
      continue;
    }
    final predicted =
        inside.map((row) => row.chance).reduce((a, b) => a + b) / inside.length;
    final actual = inside.where((row) => row.hit).length / inside.length;
    calibration.add(
      CalibrationBin(
        from: bin.$1,
        to: bin.$2 >= 1 ? 1 : bin.$2,
        games: inside.length,
        predicted: predicted,
        actual: actual,
      ),
    );
  }
  return ChanceBoard(
    scored: rows.length,
    brier: brierSum / rows.length,
    logLoss: lossSum / rows.length,
    baselineBrier: baselineBrier,
    baselineLogLoss: baselineLogLoss,
    calibration: calibration,
  );
}

String _sentence({
  required int paired,
  required int missing,
  required ChanceBoard record,
  required ChanceBoard usage,
  required bool adopted,
}) {
  if (paired == 0 || record.brier == null || usage.brier == null) {
    return 'The usage projection could not be scored. No sportsbook prop price was used. It is not a pick.';
  }
  final which = adopted
      ? 'Version 2 beat the record on both scores, so it is the chance on the card.'
      : 'Version 2 did not beat the record, so the card still uses the record.';
  return 'On the same $paired player-games, the record scored Brier ${record.brier!.toStringAsFixed(3)} and log loss ${record.logLoss!.toStringAsFixed(3)}. '
      'The usage projection scored Brier ${usage.brier!.toStringAsFixed(3)} and log loss ${usage.logLoss!.toStringAsFixed(3)}. '
      '$missing other games had a record and no projection. '
      'The line was the previous-season median. The anchor was a fair 50%. The closing spread was not used. '
      '$which No sportsbook prop price was used, so this is not a profit test and not a pick.';
}

bool _counts(PlayerGame game, String metric) {
  final value = game.stats[metric];
  if (value == null) return false;
  switch (metric) {
    case 'passing_yards':
      final attempts = game.stats['attempts'];
      if (attempts != null) return attempts >= 1;
      return value > 0;
    case 'rushing_yards':
      final carries = game.stats['carries'];
      if (carries != null) return carries >= 1;
      return value > 0;
    case 'receiving_yards':
    case 'receptions':
      final targets = game.stats['targets'];
      if (targets != null) return targets >= 1;
      return value > 0;
    default:
      return false;
  }
}

int _order(PlayerGame a, PlayerGame b) {
  final season = a.season.compareTo(b.season);
  if (season != 0) return season;
  final week = a.week.compareTo(b.week);
  if (week != 0) return week;
  return a.date.compareTo(b.date);
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

_Hits? _hits(List<PlayerGame> history, String metric, double line) {
  var hits = 0, observed = 0;
  for (final game in history) {
    final value = game.stats[metric];
    if (value == null) continue;
    observed++;
    if (value > line) hits++;
  }
  if (observed < 4) return null;
  return _Hits(hits, observed);
}
