/// A recorded player box score. An absent metric is unknown, not a zero.
class PlayerGame {
  PlayerGame({
    required this.playerId,
    required this.name,
    required this.position,
    required this.team,
    required this.opponent,
    required this.season,
    required this.week,
    required this.date,
    required this.seasonType,
    required Map<String, num?> stats,
  }) : stats = Map.unmodifiable(stats);

  final String playerId, name, position, team, opponent, seasonType;
  final int season, week;
  final DateTime date;
  final Map<String, num?> stats;

  String get identity => '$playerId/$season/$seasonType/$week';

  factory PlayerGame.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Player game $key must be a nonempty string.');
      }
      return value.trim();
    }

    int positiveInt(String key) {
      final value = json[key];
      if (value is! int || value < 1) {
        throw FormatException('Player game $key must be a positive integer.');
      }
      return value;
    }

    final dateText = text('date');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateText)) {
      throw const FormatException('Player game date must be YYYY-MM-DD.');
    }
    final parsed = DateTime.tryParse(dateText);
    if (parsed == null ||
        parsed.toIso8601String().substring(0, 10) != dateText) {
      throw const FormatException('Player game date is not a valid date.');
    }
    final seasonType = text('seasonType');
    if (seasonType != 'REG' && seasonType != 'POST') {
      throw const FormatException('Player seasonType must be REG or POST.');
    }
    final rawStats = json['stats'];
    if (rawStats is! Map) {
      throw const FormatException('Player game stats must be an object.');
    }
    final stats = <String, num?>{};
    for (final entry in rawStats.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || key.trim().isEmpty) {
        throw const FormatException('Player metric names must be nonempty.');
      }
      if (value != null && (value is! num || !value.isFinite)) {
        throw FormatException(
          'Player metric $key must be a finite number or null.',
        );
      }
      stats[key] = value as num?;
    }
    return PlayerGame(
      playerId: text('playerId'),
      name: text('name'),
      position: text('position'),
      team: text('team'),
      opponent: text('opponent'),
      season: positiveInt('season'),
      week: positiveInt('week'),
      date: DateTime.utc(parsed.year, parsed.month, parsed.day),
      seasonType: seasonType,
      stats: stats,
    );
  }
}

class PlayerStatsDataset {
  PlayerStatsDataset({
    required List<PlayerGame> rows,
    Map<String, dynamic> metadata = const {},
  }) : rows = List.unmodifiable(rows),
       metadata = Map.unmodifiable(metadata) {
    final identities = <String>{};
    for (final game in rows) {
      if (!identities.add(game.identity)) {
        throw FormatException('Duplicate player game: ${game.identity}.');
      }
    }
  }

  final List<PlayerGame> rows;
  final Map<String, dynamic> metadata;

  factory PlayerStatsDataset.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'];
    final rawMetadata =
        json['metadata'] ?? (Map<String, dynamic>.of(json)..remove('rows'));
    if (rawRows is! List || rawMetadata is! Map<String, dynamic>) {
      throw const FormatException(
        'Player dataset needs rows and metadata objects.',
      );
    }
    final rawKeys = json['statKeys'];
    List<String>? statKeys;
    if (rawKeys != null) {
      if (rawKeys is! List ||
          rawKeys.isEmpty ||
          rawKeys.any((key) => key is! String || key.trim().isEmpty)) {
        throw const FormatException('Player statKeys must be metric names.');
      }
      statKeys = rawKeys.cast<String>();
      if (statKeys.toSet().length != statKeys.length) {
        throw const FormatException(
          'Player statKeys cannot contain duplicates.',
        );
      }
    }
    final rows = <PlayerGame>[];
    for (var i = 0; i < rawRows.length; i++) {
      final row = rawRows[i];
      if (row is! Map<String, dynamic>) {
        throw FormatException('Player dataset row ${i + 1} must be an object.');
      }
      try {
        final rawStats = row['stats'];
        if (rawStats is List) {
          if (statKeys == null || rawStats.length != statKeys.length) {
            throw const FormatException(
              'Packed player stats must match the statKeys length.',
            );
          }
          rows.add(
            PlayerGame.fromJson({
              ...row,
              'stats': Map.fromIterables(statKeys, rawStats),
            }),
          );
        } else {
          rows.add(PlayerGame.fromJson(row));
        }
      } on FormatException catch (error) {
        throw FormatException('Player dataset row ${i + 1}: ${error.message}');
      }
    }
    return PlayerStatsDataset(rows: rows, metadata: rawMetadata);
  }
}

/// Previous completed NFL season labels, independently of calendar-year dates.
List<int> previous3CompletedYears(int currentSeason) {
  if (currentSeason < 4) {
    throw ArgumentError.value(currentSeason, 'currentSeason');
  }
  return [currentSeason - 1, currentSeason - 2, currentSeason - 3];
}

/// Newest first. Byes and absent player rows do not create observations.
/// [through] is an inclusive game-date cutoff, not a data-publication cutoff.
List<PlayerGame> playerGames(
  List<PlayerGame> rows,
  String playerId, {
  int? season,
  String seasonType = 'REG',
  DateTime? through,
}) {
  if (seasonType != 'REG' && seasonType != 'POST') {
    throw ArgumentError.value(seasonType, 'seasonType');
  }
  final cutoff = through == null
      ? null
      : DateTime.utc(through.year, through.month, through.day);
  return rows
      .where(
        (game) =>
            game.playerId == playerId &&
            (season == null || game.season == season) &&
            game.seasonType == seasonType &&
            (cutoff == null ||
                !DateTime.utc(
                  game.date.year,
                  game.date.month,
                  game.date.day,
                ).isAfter(cutoff)),
      )
      .toList()
    ..sort((a, b) {
      final dateOrder = b.date.compareTo(a.date);
      if (dateOrder != 0) return dateOrder;
      final seasonOrder = b.season.compareTo(a.season);
      return seasonOrder != 0 ? seasonOrder : b.week.compareTo(a.week);
    });
}

List<PlayerGame> lastPlayerGames(
  List<PlayerGame> rows,
  String playerId, {
  int count = 3,
  int? season,
  String seasonType = 'REG',
  DateTime? through,
}) {
  if (count < 1) throw ArgumentError.value(count, 'count');
  return playerGames(
    rows,
    playerId,
    season: season,
    seasonType: seasonType,
    through: through,
  ).take(count).toList();
}

/// Per-metric denominators count only observed values; zero is an observation.
class PlayerStatWindow {
  PlayerStatWindow(List<PlayerGame> games) : games = List.unmodifiable(games) {
    if (games.map((game) => game.playerId).toSet().length > 1) {
      throw ArgumentError('A player stat window cannot mix player identities.');
    }
    if (games.map((game) => game.identity).toSet().length != games.length) {
      throw ArgumentError('A player stat window cannot count a game twice.');
    }
  }

  final List<PlayerGame> games;
  int get gamesCount => games.length;
  int observed(String metric) =>
      games.where((game) => game.stats[metric] != null).length;
  num? total(String metric) {
    final values = games.map((game) => game.stats[metric]).whereType<num>();
    return values.isEmpty ? null : values.reduce((a, b) => a + b);
  }

  double? average(String metric) {
    final count = observed(metric);
    return count == 0 ? null : total(metric)! / count;
  }
}
