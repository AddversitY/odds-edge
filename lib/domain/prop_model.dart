import 'dart:math' as math;

import 'coach_model.dart';
import 'history.dart';
import 'hit_rate.dart';
import 'matchup.dart';
import 'player_stats.dart';
import 'prop_calibration.dart';
import 'prop_chance.dart';
import 'prop_projection.dart';
import 'prop_report.dart';

/// Which chance the card shows.
///
/// Set from the bundled walk-forward. A candidate is live only when it
/// has a lower Brier score and a lower log loss than each chance it
/// replaces, on the same player-games, with at least 1,000 of them.
/// Recalibration replaces the raw usage chance only when it beats that
/// chance and the record. The test checks this against a fresh run.
enum PropLiveChance { record, usage, calibrated }

const propLiveChance = PropLiveChance.usage;

/// True when the card uses a usage chance rather than the record.
const propV2Adopted = propLiveChance != PropLiveChance.record;

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

/// The record, the raw usage chance, and the recalibrated usage chance
/// on the same player-games.
class PropModelComparison {
  const PropModelComparison({
    required this.record,
    required this.pairedRecord,
    required this.usage,
    required this.calibrated,
    required this.live,
    required this.calibrator,
    required this.paired,
    required this.usageMissing,
    required this.sentence,
    this.usageChances = const [],
    this.calibratedChances = const [],
  });

  /// The published hit-rate test, including games version 2 could not score.
  final PropReport record;

  /// Version 1 on the games version 2 also scored.
  final ChanceBoard pairedRecord;

  /// Version 2, before the walk-forward curve, on those same games.
  final ChanceBoard usage;

  /// Version 2 after the curve was fit on earlier weeks only.
  final ChanceBoard calibrated;

  final PropLiveChance live;

  /// The curve fit on every scored week. Upcoming games are not in it.
  final PropCalibrator calibrator;

  bool get adopted => live != PropLiveChance.record;
  final int paired;

  /// Games the hit-rate test scored and the projection could not.
  final int usageMissing;
  final String sentence;
  final List<double> usageChances;
  final List<double> calibratedChances;
}

PropModelComparison? _cachedComparison;
String? _cachedComparisonKey;

String _comparisonKey(
  List<PlayerGame> rows,
  List<HistoricalGame> scores,
  MatchupContext? matchup,
) {
  final row = rows.isEmpty
      ? '0'
      : '${rows.length}:${rows.first.playerId}:${rows.first.season}:${rows.first.week}:${rows.last.playerId}:${rows.last.season}:${rows.last.week}';
  final score = scores.isEmpty
      ? '0'
      : '${scores.length}:${scores.first.season}:${scores.first.week}:${scores.last.season}:${scores.last.week}';
  final snaps = matchup == null
      ? 'none'
      : '${matchup.season}:${matchup.snaps.length}:${matchup.injuries.length}';
  return '$row|$score|$snaps';
}

/// The bundled comparison, reused when the same files are scored again.
PropModelComparison cachedPropComparison(
  List<PlayerGame> rows, {
  List<HistoricalGame> scores = const [],
  MatchupContext? matchup,
}) {
  final key = _comparisonKey(rows, scores, matchup);
  final hit = _cachedComparison;
  if (hit != null && _cachedComparisonKey == key) return hit;
  final built = comparePropModels(rows, scores: scores, matchup: matchup);
  _cachedComparison = built;
  _cachedComparisonKey = key;
  return built;
}

/// Walk-forward of the record, the raw usage chance, and the
/// recalibrated usage chance. To score a week, only earlier weeks are
/// used. The curve for that week is fit on earlier weeks only, then
/// applied, then the market shrink. The line is the previous season's
/// median, frozen before week 1. The market anchor is a fair 50%.
/// No closing spread is read.
PropModelComparison comparePropModels(
  List<PlayerGame> rows, {
  List<HistoricalGame> scores = const [],
  MatchupContext? matchup,
  bool keepForecasts = false,
}) {
  final usageIndex = UsageIndex.build(rows, scores: scores, matchup: matchup);
  final record = walkForwardPropChance(rows);
  final events = <_Event>[];
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
            final raw = projection?.rawChance;
            if (v2Chance == null || raw == null) {
              missing++;
              continue;
            }
            events.add(
              _Event(
                season: season,
                week: week,
                games: projection!.games,
                raw: raw,
                record: v1Chance,
                usage: v2Chance,
                hit: value > line,
              ),
            );
          }
          history.addAll(weeks[week]!);
        }
      }
    }
  }
  final calibrator = _calibrate(events);
  final v1 = [for (final event in events) _Call(event.record, event.hit)];
  final v2 = [for (final event in events) _Call(event.usage, event.hit)];
  final v3 = [for (final event in events) _Call(event.calibrated, event.hit)];
  final pairedRecord = _board(v1);
  final usage = _board(v2);
  final calibrated = _board(v3);
  final live = _live(pairedRecord, usage, calibrated);
  return PropModelComparison(
    record: record,
    pairedRecord: pairedRecord,
    usage: usage,
    calibrated: calibrated,
    live: live,
    calibrator: calibrator,
    paired: events.length,
    usageMissing: missing,
    usageChances: keepForecasts
        ? [for (final event in events) event.usage]
        : const [],
    calibratedChances: keepForecasts
        ? [for (final event in events) event.calibrated]
        : const [],
    sentence: _sentence(
      paired: events.length,
      missing: missing,
      record: pairedRecord,
      usage: usage,
      calibrated: calibrated,
      live: live,
    ),
  );
}

/// Fit the curve on earlier weeks, apply it, then shrink. A week does
/// not train itself, and a later week does not train an earlier one.
PropCalibrator _calibrate(List<_Event> events) {
  final sorted = [...events]..sort((a, b) {
    final season = a.season.compareTo(b.season);
    if (season != 0) return season;
    return a.week.compareTo(b.week);
  });
  final prior = <({double raw, bool hit})>[];
  var index = 0;
  while (index < sorted.length) {
    final season = sorted[index].season;
    final week = sorted[index].week;
    var end = index;
    while (end < sorted.length &&
        sorted[end].season == season &&
        sorted[end].week == week) {
      end++;
    }
    final fit = fitPropCalibrator(prior);
    for (var i = index; i < end; i++) {
      final event = sorted[i];
      final adjusted = fit.apply(event.raw);
      event.calibrated =
          shrinkProjectedChance(
            projected: adjusted,
            observed: event.games,
            market: propReportMarketProxy,
          ) ??
          adjusted;
    }
    for (var i = index; i < end; i++) {
      prior.add((raw: sorted[i].raw, hit: sorted[i].hit));
    }
    index = end;
  }
  return fitPropCalibrator(prior);
}

class _Event {
  _Event({
    required this.season,
    required this.week,
    required this.games,
    required this.raw,
    required this.record,
    required this.usage,
    required this.hit,
  });

  final int season, week, games;
  final double raw, record, usage;
  final bool hit;
  late double calibrated;
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

PropLiveChance _live(
  ChanceBoard record,
  ChanceBoard usage,
  ChanceBoard calibrated,
) {
  if (_beats(record, calibrated) && _beats(usage, calibrated)) {
    return PropLiveChance.calibrated;
  }
  if (_beats(record, usage)) return PropLiveChance.usage;
  return PropLiveChance.record;
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
  required ChanceBoard calibrated,
  required PropLiveChance live,
}) {
  if (paired == 0 ||
      record.brier == null ||
      usage.brier == null ||
      calibrated.brier == null) {
    return 'The usage projection could not be scored. No sportsbook prop price was used. It is not a pick.';
  }
  final which = switch (live) {
    PropLiveChance.calibrated =>
      'Recalibration beat both, so it is the chance on the card.',
    PropLiveChance.usage =>
      'Recalibration did not beat both, so the card uses the raw usage chance.',
    PropLiveChance.record =>
      'Neither usage chance beat the record, so the card still uses the record.',
  };
  return 'On the same $paired player-games, the record scored Brier ${record.brier!.toStringAsFixed(3)} and log loss ${record.logLoss!.toStringAsFixed(3)}. '
      'The usage projection scored Brier ${usage.brier!.toStringAsFixed(3)} and log loss ${usage.logLoss!.toStringAsFixed(3)}. '
      'After a walk-forward recalibration it scored Brier ${calibrated.brier!.toStringAsFixed(3)} and log loss ${calibrated.logLoss!.toStringAsFixed(3)}. '
      '$missing other games had a record and no projection. '
      'The line was the previous-season median. The anchor was a fair 50%. The closing spread was not used. The curve was fit only on earlier weeks. '
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
