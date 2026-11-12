import 'odds.dart';
import 'player_stats.dart';

const playerSimulationVersion = 'paired-game-replay-v1';
const playerYardageMarkets = {
  'passing_yards': ('Passing yards', 'attempts', 'Pass attempts'),
  'rushing_yards': ('Rushing yards', 'carries', 'Carries'),
  'receiving_yards': ('Receiving yards', 'targets', 'Targets'),
};

class PlayerScenario {
  const PlayerScenario({
    required this.metric,
    required this.line,
    required this.price,
    this.over = true,
    this.workload = 1,
    this.efficiency = 1,
    this.seed = 42,
    this.trials = 10000,
  });
  final String metric;
  final double line, price, workload, efficiency;
  final bool over;
  final int seed, trials;
  String get volumeMetric => playerYardageMarkets[metric]!.$2;
  String get label => playerYardageMarkets[metric]!.$1;

  void validate() {
    if (!playerYardageMarkets.containsKey(metric) ||
        !line.isFinite ||
        line < 0 ||
        line > 1000 ||
        !price.isFinite ||
        price <= 1 ||
        price > 1001 ||
        !workload.isFinite ||
        workload < .5 ||
        workload > 1.5 ||
        !efficiency.isFinite ||
        efficiency < .7 ||
        efficiency > 1.3 ||
        trials < 100 ||
        trials > 50000 ||
        seed < 0 ||
        seed > 2147483647) {
      throw const FormatException('Invalid player scenario');
    }
  }

  PlayerScenario copyWith({double? workload, double? efficiency}) =>
      PlayerScenario(
        metric: metric,
        line: line,
        price: price,
        over: over,
        workload: workload ?? this.workload,
        efficiency: efficiency ?? this.efficiency,
        seed: seed,
        trials: trials,
      );
  Map<String, dynamic> toJson() => {
    'metric': metric,
    'line': line,
    'price': price,
    'over': over,
    'workload': workload,
    'efficiency': efficiency,
    'seed': seed,
    'trials': trials,
  };
  factory PlayerScenario.fromJson(Map<String, dynamic> j) {
    final result = PlayerScenario(
      metric: j['metric'],
      line: (j['line'] as num).toDouble(),
      price: (j['price'] as num).toDouble(),
      over: j['over'],
      workload: (j['workload'] as num).toDouble(),
      efficiency: (j['efficiency'] as num).toDouble(),
      seed: j['seed'],
      trials: j['trials'],
    );
    result.validate();
    return result;
  }
}

/// Replays whole (yardage, opportunity) game pairs. The two inputs are never
/// sampled independently. Scaling is an explicit conditional assumption, not a
/// causal injury/pace model or calibrated forecast of an upcoming game.
class PlayerSimulation {
  PlayerSimulation(List<PlayerGame> input, this.scenario) {
    scenario.validate();
    final identity = input.map((g) => g.playerId).toSet();
    if (identity.length > 1 ||
        input.map((g) => g.seasonType).toSet().length > 1) {
      throw const FormatException('Mixed player or season-type identities');
    }
    final seen = <String>{};
    for (final game in input) {
      if (!seen.add(game.identity)) {
        throw const FormatException('Duplicate game');
      }
      final yards = game.stats[scenario.metric];
      final opportunities = game.stats[scenario.volumeMetric];
      if (yards == null ||
          opportunities == null ||
          !yards.isFinite ||
          !opportunities.isFinite ||
          opportunities < 0 ||
          (opportunities == 0 && yards != 0)) {
        excluded++;
        continue;
      }
      games.add(game);
      final adjustedVolume = opportunities * scenario.workload;
      final rate = opportunities == 0 ? 0 : yards / opportunities;
      // NFL credited yardage settles in whole yards, including negative yards.
      outcomes.add(
        (adjustedVolume * rate * scenario.efficiency).roundToDouble(),
      );
    }
    if (outcomes.length < 5 ||
        games.every((g) => g.stats[scenario.volumeMetric] == 0)) {
      return;
    }
    // Defined 32-bit xorshift sequence, stable across Dart runtimes.
    var state = scenario.seed == 0 ? 0x12345678 : scenario.seed;
    for (var i = 0; i < scenario.trials; i++) {
      state = (state ^ (state << 13)).toUnsigned(32);
      state = (state ^ (state >>> 17)).toUnsigned(32);
      state = (state ^ (state << 5)).toUnsigned(32);
      draws.add(outcomes[state % outcomes.length]);
    }
    draws.sort();
  }
  final PlayerScenario scenario;
  final List<PlayerGame> games = [];
  final List<double> outcomes = [], draws = [];
  int excluded = 0;
  bool get available => draws.isNotEmpty;
  int get sampleSize => games.length;
  bool wins(double value) =>
      !pushes(value) &&
      (scenario.over ? value > scenario.line : value < scenario.line);
  bool pushes(double value) => (value - scenario.line).abs() < 1e-9;
  double? get winProbability => !available
      ? null
      : (draws.where(wins).length / draws.length).clamp(
          0,
          1 - pushProbability!,
        );
  double? get pushProbability =>
      !available ? null : draws.where(pushes).length / draws.length;
  double? get ev => !available
      ? null
      : expectedValue(scenario.price, winProbability!, push: pushProbability!);
  double? get fairDecimal => !available || winProbability == 0
      ? null
      : (1 - pushProbability!) / winProbability!;
  double? get mean =>
      !available ? null : draws.reduce((a, b) => a + b) / draws.length;
  double? percentile(double q) =>
      !available ? null : draws[((draws.length - 1) * q.clamp(0, 1)).round()];
  double? get historicalHitRate =>
      outcomes.isEmpty ? null : outcomes.where(wins).length / outcomes.length;
  double? get averageVolume => games.isEmpty
      ? null
      : games
                .map((g) => g.stats[scenario.volumeMetric]!.toDouble())
                .reduce((a, b) => a + b) /
            games.length;
}

Map<String, dynamic> playerGameJson(PlayerGame g) => {
  'playerId': g.playerId,
  'name': g.name,
  'position': g.position,
  'team': g.team,
  'opponent': g.opponent,
  'season': g.season,
  'week': g.week,
  'date': g.date.toIso8601String().substring(0, 10),
  'seasonType': g.seasonType,
  'stats': g.stats,
};

/// Descriptive recent form. The comparison excludes the recent games, avoiding
/// presenting overlapping samples as independent evidence of a change.
class PlayerFormEvidence {
  PlayerFormEvidence(List<PlayerGame> input, this.metric) {
    PlayerStatWindow(input); // Validate one stable player and unique games.
    if (!playerYardageMarkets.containsKey(metric)) {
      throw const FormatException('Unknown metric');
    }
    final ordered = [...input]..sort((a, b) => b.date.compareTo(a.date));
    final eligible = ordered.where((g) {
      final y = g.stats[metric], v = g.stats[volumeMetric];
      return y != null &&
          v != null &&
          y.isFinite &&
          v.isFinite &&
          v >= 0 &&
          (v > 0 || y == 0);
    }).toList();
    recent = eligible.take(3).toList();
    earlier = eligible.skip(3).toList();
  }
  final String metric;
  String get volumeMetric => playerYardageMarkets[metric]!.$2;
  late final List<PlayerGame> recent, earlier;
  double? get recentWithoutLargest {
    if (recent.length < 3) return null;
    final ordered = [...recent]
      ..sort((a, b) => b.stats[metric]!.compareTo(a.stats[metric]!));
    return PlayerStatWindow(ordered.skip(1).toList()).average(metric);
  }

  double? average(List<PlayerGame> games, String key) =>
      PlayerStatWindow(games).average(key);
  double? rate(List<PlayerGame> games) {
    final volume = PlayerStatWindow(games).total(volumeMetric);
    final yards = PlayerStatWindow(games).total(metric);
    return volume == null || volume == 0 || yards == null
        ? null
        : yards / volume;
  }

  String get interpretation {
    if (recent.length < 3 || earlier.length < 5) {
      return 'Too little separate history to assess a recent change.';
    }
    final rv = average(recent, volumeMetric)!;
    final pv = average(earlier, volumeMetric)!;
    final rr = rate(recent), pr = rate(earlier);
    if (pv == 0 || rr == null || pr == null || pr <= 0) {
      return 'Opportunity or efficiency history is too sparse to compare.';
    }
    final volumeChange = rv / pv - 1;
    final rateChange = rr / pr - 1;
    if (volumeChange > .1 && rateChange > .1) {
      return 'Both opportunity and efficiency rose in this small recent sample.';
    }
    if (volumeChange > .1) {
      return 'Recent opportunity rose; check whether the increased role is likely to continue.';
    }
    if (rateChange > .1) {
      return 'Efficiency rose more than opportunity; strong yardage may depend on unusually productive plays.';
    }
    if (volumeChange < -.1) {
      return 'Recent opportunity fell; inspect the game records before assuming an unchanged role.';
    }
    return 'No large opportunity increase appears under this descriptive 10% threshold.';
  }
}
