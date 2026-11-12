import 'hit_rate.dart';
import 'nfl_teams.dart';
import 'player_stats.dart';
import 'prop_history.dart';

/// The player-stat file uses LA for the Rams. The odds names use LAR.
String boxScoreTeam(String abbrev) {
  final team = abbrev.trim().toUpperCase();
  if (team == 'LAR') return 'LA';
  return team;
}

class ListedInjury {
  const ListedInjury({
    required this.week,
    required this.team,
    required this.player,
    required this.position,
    required this.status,
    this.injury = '',
  });

  final int week;
  final String team, player, position, status, injury;

  bool get listed =>
      status == 'Out' || status == 'Questionable' || status == 'Doubtful';
}

class SnapShare {
  const SnapShare({
    required this.week,
    required this.team,
    required this.opponent,
    required this.player,
    required this.position,
    this.offensePct,
    this.defensePct,
  });

  final int week;
  final String team, opponent, player, position;
  final double? offensePct, defensePct;

  double? get share {
    final offense = offensePct;
    final defense = defensePct;
    if (offense != null && offense > 0) return offense;
    if (defense != null && defense > 0) return defense;
    return offense ?? defense;
  }
}

class MatchupContext {
  const MatchupContext({
    required this.injuries,
    required this.snaps,
    required this.note,
    this.season = 2026,
  });

  final List<ListedInjury> injuries;
  final List<SnapShare> snaps;
  final String note;
  final int season;

  static const participationNote =
      'nflverse participation, the play-by-play record of who was on the field, is not updated during the season. Snap counts are used instead.';

  factory MatchupContext.fromJson(Map<String, dynamic> json) {
    final rawInjuries = json['injuries'];
    final rawSnaps = json['snaps'];
    if (rawInjuries is! List || rawSnaps is! List) {
      throw const FormatException('Matchup file needs injuries and snaps.');
    }
    return MatchupContext(
      season: json['season'] is int ? json['season'] as int : 2026,
      note: json['participationNote'] is String
          ? json['participationNote'] as String
          : participationNote,
      injuries: [
        for (final row in rawInjuries)
          if (row is Map<String, dynamic>)
            ListedInjury(
              week: _week(row['week']),
              team: boxScoreTeam('${row['team'] ?? ''}'),
              player: '${row['player'] ?? ''}'.trim(),
              position: '${row['position'] ?? ''}'.trim().toUpperCase(),
              status: '${row['status'] ?? ''}'.trim(),
              injury: '${row['injury'] ?? ''}'.trim(),
            ),
      ],
      snaps: [
        for (final row in rawSnaps)
          if (row is Map<String, dynamic>)
            SnapShare(
              week: _week(row['week']),
              team: boxScoreTeam('${row['team'] ?? ''}'),
              opponent: boxScoreTeam('${row['opponent'] ?? ''}'),
              player: '${row['player'] ?? ''}'.trim(),
              position: '${row['position'] ?? ''}'.trim().toUpperCase(),
              offensePct: _pct(row['offensePct']),
              defensePct: _pct(row['defensePct']),
            ),
      ],
    );
  }
}

int _week(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double? _pct(Object? value) {
  if (value is! num || !value.isFinite) return null;
  return value.toDouble();
}

class DefenseAllow {
  const DefenseAllow({
    required this.team,
    required this.rank,
    required this.teams,
    required this.perGame,
    required this.games,
    required this.recent,
    required this.statLabel,
  });

  /// 1 is the fewest allowed.
  final String team;
  final int rank, teams, games;
  final double perGame;
  final List<double> recent;
  final String statLabel;
}

class _TeamGame {
  _TeamGame(this.season, this.week, this.total);
  final int season, week;
  double total;
}

/// What [opponent] has allowed, per game, to the position that matches
/// [playerPosition] on [metric]. Rank 1 allows the least.
DefenseAllow? defenseAllowed({
  required List<PlayerGame> rows,
  required String opponent,
  required String playerPosition,
  required String metric,
  int? season,
}) {
  final defense = boxScoreTeam(opponent);
  if (defense.isEmpty || metric.isEmpty) return null;
  final positions = _allowedPositions(playerPosition, metric);
  final byTeam = <String, List<_TeamGame>>{};
  for (final game in rows) {
    if (season != null && game.season != season) continue;
    if (game.seasonType != 'REG') continue;
    if (!positions.contains(game.position.toUpperCase())) continue;
    final value = game.stats[metric];
    if (value == null) continue;
    final key = '${game.season}-${game.week}';
    final games = byTeam.putIfAbsent(boxScoreTeam(game.opponent), () => []);
    final existing = games.where(
      (item) => '${item.season}-${item.week}' == key,
    );
    if (existing.isEmpty) {
      games.add(_TeamGame(game.season, game.week, value.toDouble()));
    } else {
      existing.first.total += value.toDouble();
    }
  }
  if (byTeam.length < 2) return null;
  final averages = <String, double>{};
  final counts = <String, int>{};
  for (final entry in byTeam.entries) {
    if (entry.value.isEmpty) continue;
    final sum = entry.value.fold<double>(
      0,
      (total, game) => total + game.total,
    );
    averages[entry.key] = sum / entry.value.length;
    counts[entry.key] = entry.value.length;
  }
  if (!averages.containsKey(defense)) return null;
  final ordered = averages.keys.toList()
    ..sort((a, b) {
      final amount = averages[a]!.compareTo(averages[b]!);
      return amount != 0 ? amount : a.compareTo(b);
    });
  final games = byTeam[defense]!
    ..sort((a, b) {
      final year = b.season.compareTo(a.season);
      return year != 0 ? year : b.week.compareTo(a.week);
    });
  return DefenseAllow(
    team: defense,
    rank: ordered.indexOf(defense) + 1,
    teams: ordered.length,
    perGame: averages[defense]!,
    games: counts[defense]!,
    recent: [for (final game in games.take(3)) game.total],
    statLabel: _statLabel(metric, positions),
  );
}

Set<String> _allowedPositions(String playerPosition, String metric) {
  final position = playerPosition.trim().toUpperCase();
  if (metric.startsWith('passing')) return const {'QB'};
  if (metric.startsWith('rushing')) {
    if (position == 'QB') return const {'QB'};
    return const {'RB', 'FB', 'HB'};
  }
  if (position == 'WR' || position == 'TE' || position == 'RB') {
    return {position};
  }
  return const {'WR', 'TE', 'RB'};
}

String _statLabel(String metric, Set<String> positions) {
  final who = positions.length == 1
      ? _positionName(positions.single)
      : 'skill players';
  final stat = switch (metric) {
    'passing_yards' => 'passing yards',
    'passing_tds' => 'passing touchdowns',
    'rushing_yards' => 'rushing yards',
    'rushing_tds' => 'rushing touchdowns',
    'receptions' => 'receptions',
    'receiving_yards' => 'receiving yards',
    'receiving_tds' => 'receiving touchdowns',
    _ => metric.replaceAll('_', ' '),
  };
  return '$stat allowed to $who';
}

String _positionName(String position) => switch (position) {
  'QB' => 'quarterbacks',
  'RB' => 'running backs',
  'WR' => 'wide receivers',
  'TE' => 'tight ends',
  _ => position,
};

class RelevantInjury {
  const RelevantInjury({required this.injury, required this.reason});

  final ListedInjury injury;
  final String reason;
}

/// Out, Questionable, and Doubtful players on the two teams whose
/// position can change this prop. The latest stored week for each team
/// is used, and that week is named.
List<RelevantInjury> relevantInjuries({
  required MatchupContext context,
  required String market,
  required String playerTeam,
  required String opponent,
  required String? leadingReceiver,
}) {
  final team = boxScoreTeam(playerTeam);
  final defense = boxScoreTeam(opponent);
  final week = _latestWeek(context.injuries, {team, defense});
  if (week == null) return const [];
  final found = <RelevantInjury>[];
  for (final injury in context.injuries) {
    if (injury.week != week) continue;
    if (!injury.listed) continue;
    if (injury.team != team && injury.team != defense) continue;
    final reason = _injuryReason(
      market: market,
      playerTeam: team,
      opponent: defense,
      injury: injury,
      leadingReceiver: leadingReceiver,
    );
    if (reason == null) continue;
    found.add(RelevantInjury(injury: injury, reason: reason));
  }
  found.sort((a, b) {
    final status = _statusRank(a.injury.status)
        .compareTo(_statusRank(b.injury.status));
    if (status != 0) return status;
    return a.injury.player.compareTo(b.injury.player);
  });
  return found;
}

int? _latestWeek(List<ListedInjury> injuries, Set<String> teams) {
  var week = 0;
  for (final injury in injuries) {
    if (!teams.contains(injury.team) || !injury.listed) continue;
    if (injury.week > week) week = injury.week;
  }
  return week == 0 ? null : week;
}

int _statusRank(String status) => switch (status) {
  'Out' => 0,
  'Doubtful' => 1,
  'Questionable' => 2,
  _ => 3,
};

String? _injuryReason({
  required String market,
  required String playerTeam,
  required String opponent,
  required ListedInjury injury,
  required String? leadingReceiver,
}) {
  final own = injury.team == playerTeam;
  final onDefense = injury.team == opponent;
  final position = injury.position;
  final passing = market == 'player_pass_yds' || market == 'player_pass_tds';
  final rushing = market == 'player_rush_yds' || market == 'player_rush_tds';
  final receiving = market.startsWith('player_reception');
  if (passing) {
    if (own && position == 'WR') {
      final leader =
          leadingReceiver != null &&
          leadingReceiver.toLowerCase() == injury.player.toLowerCase();
      return leader
          ? 'the leading receiver on the quarterback\'s team'
          : 'a receiver on the quarterback\'s team';
    }
    if (own && position == 'TE') {
      return 'a tight end on the quarterback\'s team';
    }
    if (onDefense && {'CB', 'S', 'DB'}.contains(position)) {
      return 'a defensive back on the other team';
    }
  }
  if (rushing) {
    if (own && {'OL', 'T', 'G', 'C'}.contains(position)) {
      return 'an offensive lineman on his team';
    }
    if (onDefense && {'LB', 'DL', 'DE', 'DT', 'NT'}.contains(position)) {
      return 'a front-seven defender on the other team';
    }
  }
  if (receiving) {
    if (own && position == 'QB') return 'the quarterback on his team';
    if (onDefense && {'CB', 'S', 'DB'}.contains(position)) {
      return 'a defensive back on the other team';
    }
    if (own &&
        position == 'WR' &&
        leadingReceiver != null &&
        leadingReceiver.toLowerCase() == injury.player.toLowerCase()) {
      return 'the leading receiver on his team';
    }
  }
  return null;
}

/// Player with the most receiving yards on [team] in [season].
String? leadingReceiver(List<PlayerGame> rows, String team, {int? season}) {
  final club = boxScoreTeam(team);
  final yards = <String, double>{};
  for (final game in rows) {
    if (season != null && game.season != season) continue;
    if (game.seasonType != 'REG') continue;
    if (boxScoreTeam(game.team) != club) continue;
    if (game.position.toUpperCase() != 'WR') continue;
    final value = game.stats['receiving_yards'];
    if (value == null) continue;
    yards[game.name] = (yards[game.name] ?? 0) + value.toDouble();
  }
  if (yards.isEmpty) return null;
  final names = yards.keys.toList()
    ..sort((a, b) {
      final amount = yards[b]!.compareTo(yards[a]!);
      return amount != 0 ? amount : a.compareTo(b);
    });
  return names.first;
}

class SnapNote {
  const SnapNote({required this.sentence, required this.shares});

  final String sentence;

  /// Newest first, as a fraction of offensive or defensive snaps.
  final List<double> shares;
}

SnapNote snapNote({
  required MatchupContext context,
  required String player,
  int limit = 5,
}) {
  final name = player.trim().toLowerCase();
  final games = [
    for (final snap in context.snaps)
      if (snap.player.toLowerCase() == name && snap.share != null) snap,
  ]..sort((a, b) => b.week.compareTo(a.week));
  final recent = games.take(limit).toList();
  if (recent.isEmpty) {
    return SnapNote(
      sentence: 'No snap count is stored for $player. ${context.note}',
      shares: const [],
    );
  }
  final shares = [for (final snap in recent) snap.share!];
  final listed = shares.map((share) => '${(share * 100).round()}%').join(', ');
  return SnapNote(
    sentence:
        '$player\'s snap share over the last ${shares.length} stored ${shares.length == 1 ? 'game' : 'games'}, newest first: $listed. ${context.note}',
    shares: shares,
  );
}

/// Likely script from the spread and the total. [teamSpread] is negative
/// when [teamName] is favored.
String gameScript({
  required String teamName,
  required double? teamSpread,
  required double? total,
  required String market,
}) {
  if (teamSpread == null && total == null) {
    return 'No spread or total is in this snapshot, so the game script is left blank.';
  }
  final parts = <String>[];
  final spread = teamSpread;
  if (spread != null) {
    final points = spread.abs().toStringAsFixed(1);
    if (spread <= -7) {
      parts.add(
        '$teamName is favored by $points, so they are more likely to play with a lead',
      );
    } else if (spread >= 7) {
      parts.add(
        '$teamName is an underdog by $points, so they are more likely to be trailing',
      );
    } else {
      parts.add(
        'The spread on $teamName is ${spread > 0 ? '+' : ''}${spread.toStringAsFixed(1)}, so the script is not extreme',
      );
    }
  }
  if (total != null) {
    final number = total.toStringAsFixed(1);
    if (total >= 48) {
      parts.add('the total is $number, so more plays are expected');
    } else if (total <= 42) {
      parts.add('the total is $number, so fewer plays are expected');
    } else {
      parts.add('the total is $number');
    }
  }
  final passing =
      market == 'player_pass_yds' ||
      market == 'player_pass_tds' ||
      market.startsWith('player_reception');
  final rushing = market == 'player_rush_yds' || market == 'player_rush_tds';
  if (spread != null && spread >= 7 && passing) {
    parts.add('a trailing script usually means more passes');
  } else if (spread != null && spread <= -7 && rushing) {
    parts.add('a lead usually means more rushes late');
  }
  final text = parts.join(', ');
  return '${text[0].toUpperCase()}${text.substring(1)}.';
}

/// The same facts as [gameScript], in one short line for a labeled row.
String scriptBrief({
  required String teamName,
  required double? teamSpread,
  required double? total,
  required String market,
}) {
  if (teamSpread == null && total == null) {
    return 'No spread or total in this snapshot.';
  }
  final bits = <String>[];
  final spread = teamSpread;
  if (spread != null) {
    final points = spread.abs().toStringAsFixed(1);
    if (spread < 0) {
      bits.add('Favored by $points');
    } else if (spread > 0) {
      bits.add('Underdog by $points');
    } else {
      bits.add("Pick'em");
    }
  }
  if (total != null) bits.add('total ${total.toStringAsFixed(1)}');
  final passing =
      market == 'player_pass_yds' ||
      market == 'player_pass_tds' ||
      market.startsWith('player_reception');
  final rushing = market == 'player_rush_yds' || market == 'player_rush_tds';
  if (spread != null && spread >= 7 && passing) {
    bits.add('more passes if trailing');
  } else if (spread != null && spread <= -7 && rushing) {
    bits.add('more rushes if they lead');
  } else if (spread != null && spread <= -7 && passing) {
    bits.add('fewer passes if they lead');
  } else if (spread != null && spread >= 7 && rushing) {
    bits.add('fewer rushes if trailing');
  }
  return bits.join(' · ');
}

/// Last word of the club name, for a short script line.
String clubNickname(String? abbrevOrName) {
  if (abbrevOrName == null || abbrevOrName.trim().isEmpty) {
    return 'This team';
  }
  final code = canonicalTeam(abbrevOrName);
  return _club(code ?? abbrevOrName) ?? abbrevOrName.trim();
}

class MatchupCard {
  const MatchupCard({
    required this.sentence,
    required this.defenseLine,
    required this.injuryLine,
    required this.scriptLine,
    required this.snapLine,
    required this.credit,
    this.defense,
    this.injuries = const [],
    this.snaps = const [],
  });

  final String sentence, defenseLine, injuryLine, scriptLine, snapLine, credit;
  final DefenseAllow? defense;
  final List<RelevantInjury> injuries;
  final List<double> snaps;
}

const nflverseCredit =
    'Hit rates, defense totals, injuries, and snap counts use nflverse, shared under CC BY 4.0. Odds Edge is not affiliated with nflverse.';

/// One sentence that ties the record, the defense, the injuries, and
/// the script to the value word. Missing pieces are named, not filled in.
MatchupCard buildMatchup({
  required String player,
  required String market,
  required String lineLabel,
  required String valueWord,
  required List<PlayerGame> rows,
  required MatchupContext context,
  String? playerTeam,
  String? position,
  String? opponent,
  String? opponentName,
  double? teamSpread,
  double? total,
  HitRate? season,
  HitRate? recent,
  int? seasonYear,
}) {
  final metric = propStatMetrics[market];
  final defense = opponent == null || metric == null || (position ?? '').isEmpty
      ? null
      : defenseAllowed(
          rows: rows,
          opponent: opponent,
          playerPosition: position!,
          metric: metric,
          season: seasonYear,
        );
  final leader = playerTeam == null
      ? null
      : leadingReceiver(rows, playerTeam, season: seasonYear);
  final injuries = playerTeam == null || opponent == null
      ? const <RelevantInjury>[]
      : relevantInjuries(
          context: context,
          market: market,
          playerTeam: playerTeam,
          opponent: opponent,
          leadingReceiver: leader,
        );
  final snaps = snapNote(context: context, player: player);
  final script = gameScript(
    teamName: _club(playerTeam) ?? player,
    teamSpread: teamSpread,
    total: total,
    market: market,
  );
  final record = _recordClause(player, lineLabel, season, recent);
  final defenseClause = defense == null
      ? 'the defense rank is blank because the stored games do not support one'
      : '${_club(defense.team) ?? defense.team} ranks ${defense.rank} of ${defense.teams} in ${defense.statLabel}';
  final injuryClause = injuries.isEmpty
      ? 'no Out or Questionable player in the stored report changes this prop'
      : injuries
            .take(3)
            .map(
              (item) =>
                  '${item.injury.player} (${item.injury.position}) is listed ${item.injury.status}',
            )
            .join(', ');
  final scriptClause = script.endsWith('.')
      ? script.substring(0, script.length - 1)
      : script;
  final sentence =
      '$record, $defenseClause, $injuryClause, and ${scriptClause[0].toLowerCase()}${scriptClause.substring(1)}, so this is a ${valueWord.toLowerCase()}.';
  final defenseLine = defense == null
      ? 'No defensive rank. The stored games did not have this stat against that team.'
      : '${defense.statLabel}: rank ${defense.rank} of ${defense.teams}, ${defense.perGame.toStringAsFixed(1)} a game over ${defense.games} ${defense.games == 1 ? 'game' : 'games'}.'
            '${defense.recent.isEmpty ? '' : ' Last ${defense.recent.length} games allowed ${defense.recent.map((value) => value.toStringAsFixed(0)).join(', ')}, newest first.'}';
  final injuryLine = injuries.isEmpty
      ? 'No Out or Questionable player on either team is tied to this prop in the stored report.'
      : 'Week ${injuries.first.injury.week} report. ${injuries.map((item) => '${item.injury.player}, ${item.injury.position}, ${item.injury.team}, listed ${item.injury.status}${item.injury.injury.isEmpty ? '' : ' (${item.injury.injury})'}, ${item.reason}').join('. ')}.';
  return MatchupCard(
    sentence: sentence,
    defenseLine: defenseLine,
    injuryLine: injuryLine,
    scriptLine: script,
    snapLine: snaps.sentence,
    credit: nflverseCredit,
    defense: defense,
    injuries: injuries,
    snaps: snaps.shares,
  );
}

String _recordClause(
  String player,
  String lineLabel,
  HitRate? season,
  HitRate? recent,
) {
  if (season != null && season.observed > 0) {
    final recentText = recent != null && recent.observed > 0
        ? ' and ${recent.hits} of the last ${recent.observed}'
        : '';
    return '$player has cleared $lineLabel in ${season.hits} of ${season.observed} games this season$recentText';
  }
  if (recent != null && recent.observed > 0) {
    return '$player has cleared $lineLabel in ${recent.hits} of the last ${recent.observed} recorded games';
  }
  return 'No recorded games compare $player with $lineLabel';
}

String? _club(String? abbrev) {
  if (abbrev == null || abbrev.isEmpty) return null;
  final code = abbrev == 'LA' ? 'LAR' : abbrev;
  final name = nflClubName(code);
  if (name == null) return abbrev;
  final parts = name.split(' ');
  return parts.isEmpty ? name : parts.last;
}
