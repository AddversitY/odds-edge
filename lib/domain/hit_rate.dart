import 'player_stats.dart';

enum LineSide { over, under }

class HitRate {
  const HitRate({
    required this.label,
    required this.games,
    required this.hits,
    required this.misses,
    required this.pushes,
    required this.missing,
    required this.samples,
  });

  final String label;
  final int games, hits, misses, pushes, missing;
  final List<HitSample> samples;

  int get observed => hits + misses + pushes;

  /// Clears divided by games that recorded the stat. Pushes are not clears.
  /// Null when every game is missing the stat.
  double? get clearRate => observed == 0 ? null : hits / observed;
}

class HitSample {
  const HitSample({
    required this.game,
    required this.value,
    required this.outcome,
  });

  final PlayerGame game;
  final num? value;

  /// `hit`, `miss`, `push`, or `missing`.
  final String outcome;
}

/// Counts clears inside [games]. Games are not reordered or dropped.
/// A missing stat is skipped, never treated as a zero or a miss.
HitRate hitRate({
  required String label,
  required List<PlayerGame> games,
  required String metric,
  required double line,
  required LineSide side,
}) {
  if (!line.isFinite) throw ArgumentError('The line must be a real number.');
  var hits = 0, misses = 0, pushes = 0, missing = 0;
  final samples = <HitSample>[];
  for (final game in games) {
    final value = game.stats[metric];
    if (value == null) {
      missing++;
      samples.add(HitSample(game: game, value: null, outcome: 'missing'));
      continue;
    }
    final compared = value.compareTo(line);
    final String outcome;
    if (compared == 0) {
      pushes++;
      outcome = 'push';
    } else if (side == LineSide.over) {
      if (compared > 0) {
        hits++;
        outcome = 'hit';
      } else {
        misses++;
        outcome = 'miss';
      }
    } else if (compared < 0) {
      hits++;
      outcome = 'hit';
    } else {
      misses++;
      outcome = 'miss';
    }
    samples.add(HitSample(game: game, value: value, outcome: outcome));
  }
  return HitRate(
    label: label,
    games: games.length,
    hits: hits,
    misses: misses,
    pushes: pushes,
    missing: missing,
    samples: samples,
  );
}

/// Newest first. Regular season only, so a playoff game is not mixed in.
/// [limit] keeps the newest recorded games and can cross seasons.
/// [season] keeps one season. [opponent] matches the stored abbreviation.
List<PlayerGame> propGames(
  List<PlayerGame> rows,
  String playerId, {
  int? limit,
  int? season,
  String? opponent,
  DateTime? through,
}) {
  final normalized = opponent?.trim().toUpperCase();
  final games = playerGames(rows, playerId, season: season, through: through)
      .where((game) {
        if (normalized == null || normalized.isEmpty) return true;
        return game.opponent.toUpperCase() == normalized;
      })
      .toList();
  if (limit == null) return games;
  if (limit < 1) throw ArgumentError.value(limit, 'limit');
  return games.take(limit).toList();
}
