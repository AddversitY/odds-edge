import 'hit_rate.dart';
import 'player_stats.dart';

/// Odds API market key → nflverse counting stat. Markets that are not here
/// have no hit rate in the bundled box scores.
const propStatMetrics = <String, String>{
  'player_pass_yds': 'passing_yards',
  'player_pass_tds': 'passing_tds',
  'player_rush_yds': 'rushing_yards',
  'player_rush_tds': 'rushing_tds',
  'player_receptions': 'receptions',
  'player_reception_yds': 'receiving_yards',
  'player_reception_tds': 'receiving_tds',
};

const propMarketLabels = <String, String>{
  'player_pass_yds': 'Passing yards',
  'player_pass_tds': 'Passing touchdowns',
  'player_rush_yds': 'Rushing yards',
  'player_rush_tds': 'Rushing touchdowns',
  'player_receptions': 'Receptions',
  'player_reception_yds': 'Receiving yards',
  'player_reception_tds': 'Receiving touchdowns',
};

/// Season clear rate minus the books' fee-free chance.
///
/// Positive means the recorded games cleared more often than that chance.
/// It is a comparison of two numbers we have, not a prediction.
double? historyGap({double? clearRate, double? fairProbability}) {
  if (clearRate == null || fairProbability == null) return null;
  if (!clearRate.isFinite || !fairProbability.isFinite) return null;
  return clearRate - fairProbability;
}

class PropWindows {
  const PropWindows({
    required this.note,
    this.playerId,
    this.position,
    this.team,
    this.seasonYear,
    this.last5,
    this.last10,
    this.last20,
    this.season,
    this.headToHead,
  });

  final String? playerId, position, team, note;
  final int? seasonYear;
  final HitRate? last5, last10, last20, season, headToHead;

  bool get hasAnyRate =>
      last5 != null ||
      last10 != null ||
      last20 != null ||
      season != null ||
      headToHead != null;
}

class _Identity {
  _Identity(this.playerId);
  final String playerId;
  String position = '';
  String team = '';
  int season = 0;
  int week = 0;
}

/// Index of the bundled box scores so a prop card can find one player.
class PlayerDirectory {
  PlayerDirectory(this.data) {
    final seasonValue = data.metadata['currentSeason'];
    var season = seasonValue is int ? seasonValue : 0;
    for (final game in data.rows) {
      final name = _normalize(game.name);
      if (name.isEmpty) continue;
      (_rowsByPlayer[game.playerId] ??= []).add(game);
      (_idsByName[name] ??= {}).add(game.playerId);
      final identity = _players[game.playerId] ??= _Identity(game.playerId);
      final newer =
          game.season > identity.season ||
          (game.season == identity.season && game.week >= identity.week);
      if (newer) {
        identity.position = game.position;
        identity.team = game.team;
        identity.season = game.season;
        identity.week = game.week;
      }
      if (game.season > season) season = game.season;
    }
    currentSeason = season;
  }

  final PlayerStatsDataset data;
  late final int currentSeason;
  final _idsByName = <String, Set<String>>{};
  final _players = <String, _Identity>{};
  final _rowsByPlayer = <String, List<PlayerGame>>{};

  PropWindows lookup({
    required String playerName,
    required String market,
    required double line,
    required LineSide side,
    String? opponent,
    DateTime? through,
  }) {
    final metric = propStatMetrics[market];
    if (metric == null) {
      return const PropWindows(
        note: 'This prop is not in the free NFL box scores, so the hit rate is left blank.',
      );
    }
    final ids = _idsByName[_normalize(playerName)];
    if (ids == null || ids.isEmpty) {
      return PropWindows(
        note:
            'No box score is stored under "$playerName", so the hit rate is left blank.',
      );
    }
    if (ids.length > 1) {
      return PropWindows(
        note:
            'More than one player is stored as "$playerName", so the hit rate is left blank.',
      );
    }
    final id = ids.single;
    final games = _rowsByPlayer[id] ?? const <PlayerGame>[];
    var identity = _players[id];
    if (through != null) {
      identity = null;
      for (final row in playerGames(games, id, through: through)) {
        final current = identity;
        if (current == null ||
            row.season > current.season ||
            (row.season == current.season && row.week >= current.week)) {
          identity = _Identity(id)
            ..team = row.team
            ..position = row.position
            ..season = row.season
            ..week = row.week;
        }
      }
    }
    HitRate window(String label, {int? limit, int? season, String? foe}) {
      final rows = propGames(
        games,
        id,
        limit: limit,
        season: season,
        opponent: foe,
        through: through,
      );
      return hitRate(
        label: label,
        games: rows,
        metric: metric,
        line: line,
        side: side,
      );
    }

    final seasonYear = identity?.season;
    final foe = opponent?.trim().toUpperCase();
    return PropWindows(
      playerId: id,
      position: identity?.position,
      team: identity?.team,
      seasonYear: seasonYear,
      last5: window('Last 5', limit: 5),
      last10: window('Last 10', limit: 10),
      last20: window('Last 20', limit: 20),
      season: seasonYear == null ? null : window('Season', season: seasonYear),
      headToHead: foe == null || foe.isEmpty
          ? null
          : window('Head to head', foe: foe),
      note: _note(identity, foe),
    );
  }

  String? _note(_Identity? identity, String? foe) {
    if (identity == null) return null;
    final team = identity.team.isEmpty ? 'an unknown team' : identity.team;
    final role = identity.position.isEmpty ? 'player' : identity.position;
    final base =
        'Latest recorded game lists this player as $role for $team. '
        'That is the newest box score allowed by this history cutoff, not a confirmation they are starting. '
        'Last 5, 10, and 20 use regular-season games only and can cross seasons. '
        'A missing stat is skipped, not counted as a miss.';
    if (foe == null) return base;
    return base;
  }
}

String _normalize(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r"[^a-z0-9 ]"), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
