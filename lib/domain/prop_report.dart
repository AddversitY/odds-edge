import 'dart:math' as math;

import 'coach_model.dart';
import 'player_stats.dart';
import 'prop_chance.dart';

/// Box-score counts the prop chance can score. Passing yards and
/// receptions are the markets on the card today. Rushing yards and
/// receiving yards use the same chance function and the same file.
const propReportMetrics = <String>[
  'passing_yards',
  'rushing_yards',
  'receiving_yards',
  'receptions',
];

const propReportMetricLabels = <String, String>{
  'passing_yards': 'Passing yards',
  'rushing_yards': 'Rushing yards',
  'receiving_yards': 'Receiving yards',
  'receptions': 'Receptions',
};

/// A prior-season median below this is not a line a book would post.
const propReportMinimumLine = <String, double>{
  'passing_yards': 100,
  'rushing_yards': 10,
  'receiving_yards': 10,
  'receptions': 1,
};

/// The anchor used when no historical prop price exists.
const propReportMarketProxy = 0.5;

const propReportNotTested =
    'No historical sportsbook prop price was used. Profit at -110, closing-line value, and whether a posted line was beaten were not tested. The line in this test is the median of the previous season, and the market anchor is a fair 50%, not a book.';

/// Walk-forward test of [propSideChance] on bundled box scores.
///
/// To score a week, only earlier weeks are used. The line is frozen
/// from the previous season before week 1, so the week being scored
/// cannot set its own number. Same-week games are not used as history.
/// A missing stat is skipped. Regular season only.
PropReport walkForwardPropChance(
  List<PlayerGame> rows, {
  bool keepForecasts = false,
}) {
  final scored = <_Forecast>[];
  final byMetric = <String, int>{
    for (final metric in propReportMetrics) metric: 0,
  };
  final players = <String>{};
  var pushes = 0;
  for (final metric in propReportMetrics) {
    final games = <String, List<PlayerGame>>{};
    for (final game in rows) {
      if (game.seasonType != 'REG') continue;
      if (!_counts(game, metric)) continue;
      (games[game.playerId] ??= []).add(game);
    }
    for (final entry in games.entries) {
      final ordered = [...entry.value]..sort(_byWeek);
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
        final floor = propReportMinimumLine[metric] ?? 0;
        if (line < floor) continue;
        final history = <PlayerGame>[
          for (final earlier in seasons.take(index)) ...bySeason[earlier]!,
        ];
        final weeks = <int, List<PlayerGame>>{};
        for (final game in bySeason[season]!) {
          (weeks[game.week] ??= []).add(game);
        }
        final weekNumbers = weeks.keys.toList()..sort();
        for (final week in weekNumbers) {
          final record = _record(history, metric, line);
          final chance = record == null
              ? null
              : propSideChance(
                  hits: record.hits,
                  observed: record.observed,
                  market: propReportMarketProxy,
                );
          for (final game in weeks[week]!) {
            final value = game.stats[metric]!.toDouble();
            if (value == line) {
              pushes++;
            } else if (chance != null) {
              scored.add(
                _Forecast(
                  metric: metric,
                  playerId: game.playerId,
                  chance: chance,
                  hit: value > line,
                ),
              );
              byMetric[metric] = (byMetric[metric] ?? 0) + 1;
              players.add(game.playerId);
            }
          }
          history.addAll(weeks[week]!);
        }
      }
    }
  }
  return _summarize(
    scored,
    pushes,
    players.length,
    byMetric,
    keepForecasts: keepForecasts,
  );
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
      final receptions = game.stats['receptions'];
      if (receptions != null && metric == 'receiving_yards') {
        return receptions > 0 || value > 0;
      }
      return value > 0;
    default:
      return false;
  }
}

int _byWeek(PlayerGame a, PlayerGame b) {
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

class _Record {
  const _Record(this.hits, this.observed);
  final int hits;
  final int observed;
}

/// Hits and observed match [propSideChance]: a push counts as observed
/// and not as a hit, the same way a recorded game that ties the line does.
_Record? _record(List<PlayerGame> history, String metric, double line) {
  var hits = 0;
  var observed = 0;
  for (final game in history) {
    final value = game.stats[metric];
    if (value == null) continue;
    observed++;
    if (value > line) hits++;
  }
  if (observed < 4) return null;
  return _Record(hits, observed);
}

class _Forecast {
  const _Forecast({
    required this.metric,
    required this.playerId,
    required this.chance,
    required this.hit,
  });

  final String metric;
  final String playerId;
  final double chance;
  final bool hit;
}

class PropReport {
  const PropReport({
    required this.method,
    required this.tested,
    required this.notTested,
    required this.usedSportsbookPrices,
    required this.marketProxy,
    required this.scored,
    required this.pushes,
    required this.players,
    required this.brier,
    required this.logLoss,
    required this.baselineBrier,
    required this.baselineLogLoss,
    required this.calibration,
    required this.scoredByMetric,
    required this.hasEdge,
    required this.plainEnglish,
    this.forecastChances = const [],
  });

  final String method;
  final String tested;
  final String notTested;

  /// True only when a real historical prop price was the anchor.
  final bool usedSportsbookPrices;
  final double marketProxy;
  final int scored;
  final int pushes;
  final int players;
  final double? brier;
  final double? logLoss;
  final double baselineBrier;
  final double baselineLogLoss;
  final List<CalibrationBin> calibration;
  final Map<String, int> scoredByMetric;

  /// A betting edge requires a price. This stays false when the test
  /// used a 50% proxy instead of a sportsbook line.
  final bool hasEdge;
  final String plainEnglish;

  /// Empty unless the caller asked to keep them. The screen does not.
  final List<double> forecastChances;
}

const _bins = <(double, double)>[
  (0.0, 0.40),
  (0.40, 0.45),
  (0.45, 0.50),
  (0.50, 0.55),
  (0.55, 0.60),
  (0.60, 1.01),
];

PropReport _summarize(
  List<_Forecast> scored,
  int pushes,
  int players,
  Map<String, int> byMetric, {
  required bool keepForecasts,
}) {
  const baselineBrier = 0.25;
  final baselineLogLoss = math.log(2);
  double? brier;
  double? logLoss;
  final calibration = <CalibrationBin>[];
  if (scored.isNotEmpty) {
    var brierSum = 0.0;
    var lossSum = 0.0;
    for (final row in scored) {
      final outcome = row.hit ? 1.0 : 0.0;
      final chance = row.chance.clamp(1e-6, 1 - 1e-6).toDouble();
      brierSum += (chance - outcome) * (chance - outcome);
      lossSum +=
          -(outcome * math.log(chance) + (1 - outcome) * math.log(1 - chance));
    }
    brier = brierSum / scored.length;
    logLoss = lossSum / scored.length;
    for (final bin in _bins) {
      final rows = [
        for (final row in scored)
          if (row.chance >= bin.$1 && row.chance < bin.$2) row,
      ];
      if (rows.isEmpty) {
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
          rows.map((row) => row.chance).reduce((a, b) => a + b) / rows.length;
      final actual = rows.where((row) => row.hit).length / rows.length;
      calibration.add(
        CalibrationBin(
          from: bin.$1,
          to: bin.$2 >= 1 ? 1 : bin.$2,
          games: rows.length,
          predicted: predicted,
          actual: actual,
        ),
      );
    }
  }
  final tested =
      'Walk-forward on regular-season box scores. The line for a season is the median of that player\'s previous season, frozen before week 1. Our chance uses only earlier weeks, shrunk toward a fair 50% with the same cap as the card. A tie with the line is a push and is left out of the scores.';
  return PropReport(
    method: tested,
    tested: tested,
    notTested: propReportNotTested,
    usedSportsbookPrices: false,
    marketProxy: propReportMarketProxy,
    scored: scored.length,
    pushes: pushes,
    players: players,
    brier: brier,
    logLoss: logLoss,
    baselineBrier: baselineBrier,
    baselineLogLoss: baselineLogLoss,
    calibration: calibration,
    scoredByMetric: byMetric,
    hasEdge: false,
    forecastChances: keepForecasts
        ? [for (final row in scored) row.chance]
        : const [],
    plainEnglish: _plain(
      scored: scored.length,
      pushes: pushes,
      players: players,
      brier: brier,
      logLoss: logLoss,
      baselineLogLoss: baselineLogLoss,
      byMetric: byMetric,
    ),
  );
}

String _plain({
  required int scored,
  required int pushes,
  required int players,
  required double? brier,
  required double? logLoss,
  required double baselineLogLoss,
  required Map<String, int> byMetric,
}) {
  if (scored == 0) {
    return 'The prop chance could not be scored. The box scores did not have a previous season to set a line. No sportsbook prop price was tested.';
  }
  final brierText = brier!.toStringAsFixed(3);
  final lossText = logLoss!.toStringAsFixed(3);
  final coinLoss = baselineLogLoss.toStringAsFixed(3);
  final versus = (brier - 0.25).abs() < 0.002
      ? 'That is next to a coin flip.'
      : brier < 0.25
      ? 'That is a slightly better forecast than a coin flip, on a made-up line.'
      : 'That is a worse forecast than a coin flip.';
  final counts = [
    for (final metric in propReportMetrics)
      if ((byMetric[metric] ?? 0) > 0)
        '${propReportMetricLabels[metric]} ${byMetric[metric]}',
  ].join(', ');
  return 'Tested $scored player-games ($players players; $counts), plus $pushes pushes left out. '
      'The line was each player\'s previous-season median, and the market anchor was a fair 50%, because no historical prop price was available. '
      'Brier score $brierText. A coin flip scores 0.250. $versus '
      'Log loss $lossText. A coin flip scores $coinLoss. '
      'This is not a profit test and not a closing-line test. It is not a pick.';
}
