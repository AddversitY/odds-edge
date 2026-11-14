import 'dart:math' as math;

import 'history.dart';
import 'nfl_teams.dart';
import 'odds.dart';
import 'player_stats.dart';
import 'prop_projection.dart' show normalCdf;

const scriptDraws = 10000;
const scriptPriorGames = 40.0;
const scriptCorrelationCap = .65;
const scriptMinimumPairs = 12;

String scriptTeam(String name) =>
    canonicalTeam(name) ??
    const {'LA': 'LAR', 'OAK': 'LV', 'SD': 'LAC', 'STL': 'LAR'}[name] ??
    name;
String _day(DateTime date) => date.toIso8601String().substring(0, 10);
String _gameKey(DateTime date, String a, String b) {
  final teams = [scriptTeam(a), scriptTeam(b)]..sort();
  return '${_day(date)}|${teams.join('|')}';
}

class ScriptLeg {
  const ScriptLeg({
    required this.id,
    required this.eventId,
    required this.playerId,
    required this.team,
    required this.metric,
    required this.line,
    required this.over,
    required this.chance,
    required this.mean,
    required this.sd,
  });
  final String id, eventId, playerId, team, metric;
  final double line, chance, mean, sd;
  final bool over;
  String get feature => '$playerId:$metric';
}

class ScriptCorrelation {
  const ScriptCorrelation({
    required this.features,
    required this.matrix,
    required this.lower,
    required this.pairs,
    required this.beforeSeason,
    required this.trainingGames,
    required this.psdScale,
  });
  final List<String> features;
  final List<List<double>> matrix, lower;
  final List<List<int>> pairs;
  final int beforeSeason, trainingGames;
  final double psdScale;
}

/// Earlier seasons only. Orient historical scripts to an observed selected
/// player's live side, so "own team" remains own team after a trade. Other
/// selected players must have the same teammate/opponent relationship then.
ScriptCorrelation fitScriptCorrelation({
  required List<ScriptLeg> legs,
  required SportEvent event,
  required List<PlayerGame> players,
  required List<HistoricalGame> games,
  required int beforeSeason,
}) {
  if (legs.isEmpty || legs.any((l) => l.eventId != event.id)) {
    throw ArgumentError('Fit one game at a time.');
  }
  final unique = <String, ScriptLeg>{for (final leg in legs) leg.feature: leg};
  final selected = unique.values.toList()
    ..sort((a, b) => a.feature.compareTo(b.feature));
  final features = [
    'margin',
    'total',
    'home_pass',
    'home_rush',
    'away_pass',
    'away_rush',
    ...selected.map((l) => l.feature),
  ];
  final byGame = <String, List<PlayerGame>>{};
  for (final row in players) {
    if (row.season >= beforeSeason || row.seasonType != 'REG') continue;
    (byGame[_gameKey(row.date, row.team, row.opponent)] ??= []).add(row);
  }
  final observations = <List<double?>>[];
  for (final game in games) {
    if (game.season >= beforeSeason) continue;
    final rows = byGame[_gameKey(game.date, game.home, game.away)];
    if (rows == null) continue;
    var home = scriptTeam(game.home), away = scriptTeam(game.away);
    var margin = (game.homeScore - game.awayScore).toDouble();
    for (final leg in selected) {
      final anchor = rows.where((r) => r.playerId == leg.playerId).toList();
      if (anchor.length != 1) continue;
      final isLiveHome = scriptTeam(leg.team) == scriptTeam(event.home);
      final isHistoricalHome = scriptTeam(anchor.single.team) == home;
      if (isLiveHome != isHistoricalHome) {
        final previous = home;
        home = away;
        away = previous;
        margin = -margin;
      }
      break;
    }
    double? sum(String team, String metric) {
      final values = rows
          .where((r) => scriptTeam(r.team) == team && r.stats[metric] != null)
          .map((r) => r.stats[metric]!.toDouble())
          .toList();
      return values.isEmpty ? null : values.reduce((a, b) => a + b);
    }

    observations.add([
      margin,
      (game.homeScore + game.awayScore).toDouble(),
      sum(home, 'passing_yards'),
      sum(home, 'rushing_yards'),
      sum(away, 'passing_yards'),
      sum(away, 'rushing_yards'),
      for (final leg in selected)
        _historicalStat(
          leg,
          rows,
          scriptTeam(leg.team) == scriptTeam(event.home) ? home : away,
        ),
    ]);
  }
  return fitScriptMatrix(features, observations, beforeSeason);
}

double? _historicalStat(ScriptLeg leg, List<PlayerGame> rows, String team) {
  final matched = rows
      .where((r) => r.playerId == leg.playerId && scriptTeam(r.team) == team)
      .toList();
  if (matched.length != 1) return null;
  return matched.single.stats[leg.metric]?.toDouble();
}

/// Rank-normal margins avoid fitting count-stat tails as a normal distribution.
/// Sparse pairs revert to zero, then shrink n/(n+40), cap and repair to a valid
/// covariance matrix by further shrinking all off-diagonals toward zero.
ScriptCorrelation fitScriptMatrix(
  List<String> features,
  List<List<double?>> rows,
  int beforeSeason,
) {
  final size = features.length;
  if (size == 0 ||
      features.toSet().length != size ||
      rows.any(
        (r) => r.length != size || r.any((x) => x != null && !x.isFinite),
      )) {
    throw ArgumentError('Invalid script training rows.');
  }
  final normal = List.generate(
    rows.length,
    (_) => List<double?>.filled(size, null),
  );
  for (var c = 0; c < size; c++) {
    final ranked = [
      for (var r = 0; r < rows.length; r++)
        if (rows[r][c] != null) r,
    ]..sort((a, b) => rows[a][c]!.compareTo(rows[b][c]!));
    var start = 0;
    while (start < ranked.length) {
      var end = start + 1;
      while (end < ranked.length &&
          rows[ranked[end]][c] == rows[ranked[start]][c]) {
        end++;
      }
      final value = scriptNormalQuantile(((start + end) / 2) / ranked.length);
      for (var k = start; k < end; k++) {
        normal[ranked[k]][c] = value;
      }
      start = end;
    }
  }
  final matrix = List.generate(
    size,
    (i) => List.generate(size, (j) => i == j ? 1.0 : 0.0),
  );
  final pairs = List.generate(size, (_) => List<int>.filled(size, 0));
  for (var i = 0; i < size; i++) {
    for (var j = 0; j < i; j++) {
      final paired = normal.where((r) => r[i] != null && r[j] != null).toList();
      final n = paired.length;
      pairs[i][j] = pairs[j][i] = n;
      if (n < scriptMinimumPairs) continue;
      final a = paired.map((r) => r[i]!).reduce((a, b) => a + b) / n;
      final b = paired.map((r) => r[j]!).reduce((a, b) => a + b) / n;
      var covariance = 0.0, va = 0.0, vb = 0.0;
      for (final row in paired) {
        final x = row[i]! - a, y = row[j]! - b;
        covariance += x * y;
        va += x * x;
        vb += y * y;
      }
      if (va < 1e-10 || vb < 1e-10) continue;
      final rho = (covariance / math.sqrt(va * vb) * n / (n + scriptPriorGames))
          .clamp(-scriptCorrelationCap, scriptCorrelationCap);
      matrix[i][j] = matrix[j][i] = rho;
    }
  }
  var scale = 1.0;
  var lower = _cholesky(matrix);
  while (lower == null) {
    scale *= .8;
    for (var i = 0; i < size; i++) {
      for (var j = 0; j < i; j++) {
        matrix[i][j] = matrix[j][i] = matrix[i][j] * .8;
      }
    }
    lower = _cholesky(matrix);
  }
  return ScriptCorrelation(
    features: features,
    matrix: matrix,
    lower: lower,
    pairs: pairs,
    beforeSeason: beforeSeason,
    trainingGames: rows.length,
    psdScale: scale,
  );
}

List<List<double>>? _cholesky(List<List<double>> matrix) {
  final lower = List.generate(
    matrix.length,
    (_) => List<double>.filled(matrix.length, 0),
  );
  for (var i = 0; i < matrix.length; i++) {
    for (var j = 0; j <= i; j++) {
      var sum = matrix[i][j];
      for (var k = 0; k < j; k++) {
        sum -= lower[i][k] * lower[j][k];
      }
      if (i == j) {
        if (sum < 1e-8) return null;
        lower[i][j] = math.sqrt(sum);
      } else {
        lower[i][j] = sum / lower[j][j];
      }
    }
  }
  return lower;
}

double scriptNormalQuantile(double p) {
  if (!p.isFinite || p <= 0 || p >= 1) {
    throw ArgumentError('Probability must be strictly between 0 and 1.');
  }
  var lo = -9.0, hi = 9.0;
  for (var i = 0; i < 48; i++) {
    final mid = (lo + hi) / 2;
    if (normalCdf(mid) < p) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

class ScriptRandom {
  ScriptRandom(int seed) : state = seed & 0xffffffff;
  int state;
  double uniform() {
    state = (1664525 * state + 1013904223) % 4294967296;
    return (state + .5) / 4294967296;
  }

  double normal() =>
      math.sqrt(-2 * math.log(uniform())) * math.cos(2 * math.pi * uniform());
}

class ScriptSimulation {
  const ScriptSimulation({
    required this.joint,
    required this.independent,
    required this.standardError,
    required this.draws,
    required this.legHitRates,
    required this.mostCommonMiss,
    required this.weakest,
    required this.training,
    required this.meanStats,
    required this.failureLegs,
    required this.failurePatternShare,
  });
  final double joint, independent, standardError;
  final int draws, mostCommonMiss, weakest;
  final List<double> legHitRates, meanStats;
  final List<ScriptCorrelation> training;
  final List<int> failureLegs;
  final double failurePatternShare;
  double get lower => _bound(false);
  double get upper => _bound(true);
  double _bound(bool upper) {
    const z = 1.96;
    final center = joint + z * z / (2 * draws);
    final radius =
        z *
        math.sqrt(joint * (1 - joint) / draws + z * z / (4 * draws * draws));
    return ((center + (upper ? radius : -radius)) / (1 + z * z / draws)).clamp(
      0.0,
      1.0,
    );
  }
}

/// A seeded Gaussian-copula game script. Draw order is margin/total, team
/// passing/rushing, then player stats. The marginal quantile transform preserves
/// each displayed, market-shrunk chance. Receptions use the model's NB curve.
/// Whole-number lines are rejected rather than silently treating pushes as wins.
ScriptSimulation simulateGameScripts({
  required List<ScriptLeg> legs,
  required List<SportEvent> events,
  required List<PlayerGame> players,
  required List<HistoricalGame> games,
  required int beforeSeason,
  int draws = scriptDraws,
  int seed = 1729,
}) {
  if (legs.length < 2 || legs.length > 8 || draws < 1000 || draws > 100000) {
    throw ArgumentError('Use 2–8 legs and 1,000–100,000 draws.');
  }
  if (legs.map((l) => l.id).toSet().length != legs.length) {
    throw ArgumentError('Duplicate legs are not separate chances.');
  }
  for (final leg in legs) {
    if (![
          'passing_yards',
          'rushing_yards',
          'receiving_yards',
          'receptions',
        ].contains(leg.metric) ||
        !leg.line.isFinite ||
        leg.line % 1 == 0 ||
        !leg.mean.isFinite ||
        !leg.sd.isFinite ||
        leg.sd <= 0 ||
        !leg.chance.isFinite ||
        leg.chance <= 0 ||
        leg.chance >= 1 ||
        leg.playerId.isEmpty) {
      throw ArgumentError(
        'A leg needs a supported projection, stable player identity and a non-push line.',
      );
    }
  }
  for (var i = 0; i < legs.length; i++) {
    for (var j = 0; j < i; j++) {
      final a = legs[i], b = legs[j];
      if (a.eventId != b.eventId || a.feature != b.feature) continue;
      if (a.line == b.line) {
        throw ArgumentError(
          'Do not include both sides or duplicate exposures of one line.',
        );
      }
      final pa = a.over ? a.chance : 1 - a.chance,
          pb = b.over ? b.chance : 1 - b.chance;
      if ((a.line > b.line && pa > pb + 1e-8) ||
          (a.line < b.line && pa < pb - 1e-8)) {
        throw ArgumentError(
          'These alternate-line chances are inconsistent with one stat distribution.',
        );
      }
    }
  }
  final eventMap = {for (final event in events) event.id: event};
  final groups = <String, List<ScriptLeg>>{};
  for (final leg in legs) {
    (groups[leg.eventId] ??= []).add(leg);
  }
  final ordered = groups.keys.toList()..sort();
  final models = <String, ScriptCorrelation>{};
  for (final id in ordered) {
    final event = eventMap[id];
    if (event == null ||
        groups[id]!.any(
          (l) =>
              scriptTeam(l.team) != scriptTeam(event.home) &&
              scriptTeam(l.team) != scriptTeam(event.away),
        )) {
      throw ArgumentError('Every player must match an event team.');
    }
    models[id] = fitScriptCorrelation(
      legs: groups[id]!,
      event: event,
      players: players,
      games: games,
      beforeSeason: beforeSeason,
    );
  }
  final random = ScriptRandom(seed);
  final hits = List<int>.filled(legs.length, 0),
      missAlone = List<int>.filled(legs.length, 0);
  final sums = List<double>.filled(legs.length, 0);
  final failures = <int, int>{};
  final marginals = [for (final leg in legs) _Marginal(leg)];
  var allHits = 0;
  for (var draw = 0; draw < draws; draw++) {
    final latent = <String, Map<String, double>>{};
    for (final id in ordered) {
      final model = models[id]!;
      final independent = List.generate(
        model.features.length,
        (_) => random.normal(),
      );
      final values = <String, double>{};
      for (var i = 0; i < model.features.length; i++) {
        var value = 0.0;
        for (var j = 0; j <= i; j++) {
          value += model.lower[i][j] * independent[j];
        }
        values[model.features[i]] = value;
      }
      latent[id] = values;
    }
    var misses = 0, lastMiss = -1, mask = 0;
    for (var i = 0; i < legs.length; i++) {
      final leg = legs[i];
      final u = normalCdf(latent[leg.eventId]![leg.feature]!);
      final stat = marginals[i].stat(u);
      sums[i] += stat;
      final hit = leg.over ? stat > leg.line : stat < leg.line;
      if (hit) {
        hits[i]++;
      } else {
        misses++;
        lastMiss = i;
        mask |= 1 << i;
      }
    }
    if (misses == 0) allHits++;
    if (misses == 1) missAlone[lastMiss]++;
    if (mask != 0) failures[mask] = (failures[mask] ?? 0) + 1;
  }
  final joint = allHits / draws;
  var weakest = 0, common = 0;
  for (var i = 1; i < legs.length; i++) {
    if (legs[i].chance < legs[weakest].chance) weakest = i;
    if (missAlone[i] > missAlone[common]) common = i;
  }
  var failureMask = 0, frequency = 0;
  for (final entry in failures.entries) {
    if (entry.value > frequency) {
      frequency = entry.value;
      failureMask = entry.key;
    }
  }
  return ScriptSimulation(
    joint: joint,
    independent: legs.fold(1.0, (p, l) => p * l.chance),
    standardError: math.sqrt(joint * (1 - joint) / draws),
    draws: draws,
    legHitRates: [for (final hit in hits) hit / draws],
    mostCommonMiss: missAlone[common] == 0 ? -1 : common,
    weakest: weakest,
    training: [for (final id in ordered) models[id]!],
    meanStats: [for (final sum in sums) sum / draws],
    failureLegs: [
      for (var i = 0; i < legs.length; i++)
        if (failureMask & (1 << i) != 0) i,
    ],
    failurePatternShare: draws == allHits ? 0 : frequency / (draws - allHits),
  );
}

class _Marginal {
  _Marginal(this.leg) {
    target = leg.over ? 1 - leg.chance : leg.chance;
    if (leg.metric == 'receptions') {
      final mu = math.max(leg.mean, .05),
          variance = math.max(leg.sd * leg.sd, mu + .25);
      final r = (mu * mu / (variance - mu)).clamp(.3, 200.0), p = r / (r + mu);
      var pmf = math.pow(p, r).toDouble(), cdf = pmf;
      countCdf.add(cdf);
      for (var k = 1; k < 10000 && cdf < 1 - 1e-10; k++) {
        pmf *= (k + r - 1) / k * (1 - p);
        cdf += pmf;
        countCdf.add(cdf);
      }
      if (countCdf.last < 1 - 1e-8) {
        throw ArgumentError('Count distribution did not converge.');
      }
    }
    raw = countCdf.isEmpty
        ? normalCdf((leg.line - leg.mean) / leg.sd)
        : leg.line < 0
        ? 0
        : countCdf[math.min(leg.line.floor(), countCdf.length - 1)];
    if (raw < 1e-8 || raw > 1 - 1e-8) {
      throw ArgumentError(
        'This line is outside the supported stat distribution.',
      );
    }
  }
  final ScriptLeg leg;
  late final double target, raw;
  final countCdf = <double>[];
  double stat(double u) {
    final warped =
        (u <= target
                ? u * raw / target
                : raw + (u - target) * (1 - raw) / (1 - target))
            .clamp(1e-9, 1 - 1e-9);
    if (countCdf.isEmpty) {
      return leg.mean + leg.sd * scriptNormalQuantile(warped);
    }
    var lo = 0, hi = countCdf.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (countCdf[mid] < warped) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo.toDouble();
  }
}
