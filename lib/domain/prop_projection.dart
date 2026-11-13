import 'dart:math' as math;

import 'history.dart';
import 'hit_rate.dart';
import 'matchup.dart';
import 'player_stats.dart';
import 'prop_calibration.dart';
import 'prop_chance.dart';

/// Neutral pass attempts. Rush attempts sit beside them, so the pass
/// rate is attempts divided by attempts plus carries.
const leaguePassAttempts = 34.0;
const leagueRushAttempts = 26.0;
const leaguePassRate =
    leaguePassAttempts / (leaguePassAttempts + leagueRushAttempts);

const _leaguePoints = 22.5;

/// One piece of a projection, in yards or catches.
class PropFactor {
  const PropFactor({
    required this.label,
    required this.detail,
    required this.delta,
  });

  final String label;
  final String detail;

  /// Yards or catches this piece adds. The usage row holds the baseline.
  final double delta;
}

/// A projected stat and the chance that stat clears a line.
class PropProjection {
  const PropProjection({
    required this.metric,
    required this.mean,
    required this.sd,
    required this.distribution,
    required this.rawChance,
    required this.adjustedChance,
    required this.chance,
    required this.market,
    required this.capped,
    required this.games,
    required this.factors,
    required this.side,
  });

  final String metric;
  final double mean;
  final double sd;

  /// `normal` for yards. `negative binomial` for receptions.
  final String distribution;

  /// Chance for [side] from the curve, before recalibration.
  final double rawChance;

  /// Chance for [side] after the walk-forward curve, before the market.
  final double adjustedChance;

  /// Chance after the shrink and the cap.
  final double? chance;
  final double? market;
  final bool capped;
  final int games;
  final List<PropFactor> factors;
  final LineSide side;

  String get unit => metric == 'receptions' ? 'catches' : 'yards';
}

/// Box scores, earlier final scores, and the 2026 snap and injury file.
///
/// A lookup for a week uses only earlier weeks. A lookup with [beforeDate]
/// uses only games dated before that day. The week being scored, and the
/// closing spread, are not inputs.
class UsageIndex {
  UsageIndex._({
    required this.byPlayer,
    required this.positionOf,
    required this.idsByName,
    required this._offense,
    required this._defense,
    required this._plays,
    required this._points,
    required this._snaps,
    required this._outs,
    required this.matchupSeason,
  });

  final Map<String, List<PlayerGame>> byPlayer;
  final Map<String, String> positionOf;
  final Map<String, Set<String>> idsByName;
  final Map<String, _Offense> _offense;
  final Map<String, List<_Tagged>> _defense;
  final Map<String, List<_Tagged>> _plays;
  final Map<String, List<_Tagged>> _points;
  final Map<String, List<_Snap>> _snaps;
  final Map<String, List<_Out>> _outs;
  final int matchupSeason;

  factory UsageIndex.build(
    List<PlayerGame> rows, {
    List<HistoricalGame> scores = const [],
    MatchupContext? matchup,
  }) {
    final byPlayer = <String, List<PlayerGame>>{};
    final positionOf = <String, String>{};
    final idsByName = <String, Set<String>>{};
    final offense = <String, _Offense>{};
    for (final game in rows) {
      if (game.seasonType != 'REG') continue;
      (byPlayer[game.playerId] ??= []).add(game);
      positionOf[game.playerId] = game.position;
      final name = normalizePropName(game.name);
      if (name.isNotEmpty) (idsByName[name] ??= {}).add(game.playerId);
      final off = offense.putIfAbsent(
        _key(game.season, game.week, game.team),
        _Offense.new,
      );
      off.date = game.date;
      if (game.opponent.isNotEmpty) off.opponent = game.opponent;
      _addStat(off, game);
    }
    for (final games in byPlayer.values) {
      games.sort(_gameOrder);
    }
    final defense = <String, List<_Tagged>>{};
    final plays = <String, List<_Tagged>>{};
    for (final entry in offense.entries) {
      final parts = entry.key.split('|');
      final season = int.parse(parts[0]);
      final week = int.parse(parts[1]);
      final team = parts[2];
      final off = entry.value;
      plays.putIfAbsent(team, () => []).add(
        _Tagged(season, week, off.date, off.attempts, off.carries, 0, 0),
      );
      if (off.opponent.isEmpty) continue;
      defense.putIfAbsent(off.opponent, () => []).add(
        _Tagged(
          season,
          week,
          off.date,
          off.passYds,
          off.rushYds,
          off.recYds,
          off.receptions,
        ),
      );
    }
    final points = <String, List<_Tagged>>{};
    for (final game in scores) {
      points.putIfAbsent(game.home, () => []).add(
        _Tagged(
          game.season,
          game.week,
          game.date,
          game.homeScore.toDouble(),
          game.awayScore.toDouble(),
          0,
          0,
        ),
      );
      points.putIfAbsent(game.away, () => []).add(
        _Tagged(
          game.season,
          game.week,
          game.date,
          game.awayScore.toDouble(),
          game.homeScore.toDouble(),
          0,
          0,
        ),
      );
    }
    for (final list in [...defense.values, ...plays.values, ...points.values]) {
      list.sort(_tagOrder);
    }
    final snaps = <String, List<_Snap>>{};
    final outs = <String, List<_Out>>{};
    final fileSeason = matchup?.season ?? 0;
    if (matchup != null) {
      for (final snap in matchup.snaps) {
        final name = normalizePropName(snap.player);
        final pct = snap.offensePct;
        if (name.isEmpty || pct == null) continue;
        (snaps[name] ??= []).add(_Snap(snap.week, snap.team, pct));
      }
      for (final list in snaps.values) {
        list.sort((a, b) => a.week.compareTo(b.week));
      }
      for (final row in matchup.injuries) {
        if (!_listedOut(row.status)) continue;
        (outs['$fileSeason|${row.week}|${row.team}'] ??= []).add(
          _Out(row.player, row.position),
        );
      }
    }
    return UsageIndex._(
      byPlayer: byPlayer,
      positionOf: positionOf,
      idsByName: idsByName,
      offense: offense,
      defense: defense,
      plays: plays,
      points: points,
      snaps: snaps,
      outs: outs,
      matchupSeason: fileSeason,
    );
  }

  String? onlyId(String name) {
    final ids = idsByName[normalizePropName(name)];
    if (ids == null || ids.length != 1) return null;
    return ids.single;
  }
}

class _Offense {
  double attempts = 0, carries = 0, targets = 0;
  double passYds = 0, rushYds = 0, recYds = 0, receptions = 0;
  String opponent = '';
  DateTime date = DateTime.utc(1970);
}

class _Tagged {
  const _Tagged(
    this.season,
    this.week,
    this.date,
    this.a,
    this.b,
    this.c,
    this.d,
  );
  final int season, week;
  final DateTime date;
  final double a, b, c, d;
}

class _Snap {
  const _Snap(this.week, this.team, this.pct);
  final int week;
  final String team;
  final double pct;
}

class _Out {
  const _Out(this.player, this.position);
  final String player, position;
}

class _Cut {
  const _Cut({required this.season, required this.week, this.date});
  final int season, week;
  final DateTime? date;

  bool allows(int season, int week, DateTime date) {
    final day = this.date;
    if (day != null) {
      final gameDay = DateTime.utc(date.year, date.month, date.day);
      final limit = DateTime.utc(day.year, day.month, day.day);
      return gameDay.isBefore(limit);
    }
    return season < this.season || (season == this.season && week < this.week);
  }
}

UsageIndex? _cachedIndex;
Object? _cachedRows, _cachedScores, _cachedMatchup;

/// Reuses the index when the same lists are passed again.
UsageIndex usageIndexFor(
  List<PlayerGame> rows, {
  List<HistoricalGame> scores = const [],
  MatchupContext? matchup,
}) {
  final cached = _cachedIndex;
  if (cached != null &&
      identical(_cachedRows, rows) &&
      identical(_cachedScores, scores) &&
      identical(_cachedMatchup, matchup)) {
    return cached;
  }
  final built = UsageIndex.build(rows, scores: scores, matchup: matchup);
  _cachedIndex = built;
  _cachedRows = rows;
  _cachedScores = scores;
  _cachedMatchup = matchup;
  return built;
}

/// Project one prop from games strictly before [beforeSeason]/[beforeWeek],
/// or before [beforeDate] when that is set.
///
/// [teamSpread] and [total] are the numbers on the screen. The backtest
/// leaves them null and uses earlier final scores instead, so a closing
/// number cannot leak into the test.
PropProjection? projectProp({
  required UsageIndex index,
  required String playerId,
  required String metric,
  required double line,
  required LineSide side,
  required int beforeSeason,
  required int beforeWeek,
  String? team,
  String? opponent,
  double? teamSpread,
  double? total,
  double? market,
  DateTime? beforeDate,
  List<({String name, String position})> teammateOuts = const [],
  PropCalibrator? calibrator,
}) {
  final cut = _Cut(season: beforeSeason, week: beforeWeek, date: beforeDate);
  final games = index.byPlayer[playerId];
  if (games == null) return null;
  final prior = [
    for (final game in games)
      if (cut.allows(game.season, game.week, game.date) &&
          _counts(game, metric))
        game,
  ];
  if (prior.length < 4) return null;
  final position = index.positionOf[playerId] ?? prior.last.position;
  final club = (team == null || team.isEmpty) ? prior.last.team : team;
  final foe = (opponent == null || opponent.isEmpty)
      ? prior.last.opponent
      : opponent;
  final window = prior.length <= 8 ? prior : prior.sublist(prior.length - 8);
  final usage = _usage(index, window, metric, position);
  if (usage == null) return null;

  final passRate = _passRate(index, club, cut);
  final defense = _defense(index, foe, metric, cut, beforeSeason);
  final script = _script(
    index,
    club,
    foe,
    cut,
    teamSpread: teamSpread,
    total: total,
  );
  final snap = _snap(
    index,
    prior.last.name,
    position,
    cut,
    beforeSeason,
  );
  final mates = _teammates(
    index,
    selfId: playerId,
    metric: metric,
    team: club,
    cut: cut,
    beforeSeason: beforeSeason,
    beforeWeek: beforeWeek,
    extra: teammateOuts,
  );

  double meanAt({
    required bool snapOn,
    required bool passOn,
    required bool scriptOn,
    required bool defenseOn,
    required bool matesOn,
  }) {
    return _statMean(
      metric: metric,
      share: usage.share,
      passRate: passOn ? passRate : leaguePassRate,
      efficiency: usage.efficiency,
      defense: defenseOn ? defense.factor : 1,
      scale: scriptOn ? script.scale : 1,
      snapFactor: snapOn && snap.known ? snap.factor : 1,
      qbVacated: matesOn ? mates.qbShare : 0,
      skillVacated: matesOn ? mates.skillShare : 0,
    );
  }

  final base = meanAt(
    snapOn: false,
    passOn: false,
    scriptOn: false,
    defenseOn: false,
    matesOn: false,
  );
  final afterSnap = meanAt(
    snapOn: true,
    passOn: false,
    scriptOn: false,
    defenseOn: false,
    matesOn: false,
  );
  final afterPass = meanAt(
    snapOn: true,
    passOn: true,
    scriptOn: false,
    defenseOn: false,
    matesOn: false,
  );
  final afterScript = meanAt(
    snapOn: true,
    passOn: true,
    scriptOn: true,
    defenseOn: false,
    matesOn: false,
  );
  final afterDefense = meanAt(
    snapOn: true,
    passOn: true,
    scriptOn: true,
    defenseOn: true,
    matesOn: false,
  );
  final mean = meanAt(
    snapOn: true,
    passOn: true,
    scriptOn: true,
    defenseOn: true,
    matesOn: true,
  );
  final values = [
    for (final game in prior) game.stats[metric]!.toDouble(),
  ];
  final sd = _spread(values, _sdPrior(metric), _sdFloor(metric));
  final raw = sideChance(
    metric: metric,
    mean: mean,
    sd: sd,
    line: line,
    side: side,
  );
  final adjusted = _recalibrate(raw, side, calibrator);
  final shrunk = shrinkProjectedChance(
    projected: adjusted,
    observed: prior.length,
    market: market,
  );
  final anchor = market;
  var capped = false;
  if (shrunk != null &&
      anchor != null &&
      anchor.isFinite &&
      anchor > 0 &&
      anchor < 1) {
    final blended =
        (prior.length * adjusted + propPriorGames * anchor) /
        (prior.length + propPriorGames);
    capped = (blended - shrunk).abs() > 1e-9;
  }
  final shareLabel = metric == 'rushing_yards'
      ? '${_pct(usage.share)} of carries'
      : metric == 'passing_yards'
      ? '${_pct(usage.share)} of dropbacks'
      : '${_pct(usage.share)} of targets';
  return PropProjection(
    metric: metric,
    mean: mean,
    sd: sd,
    distribution: metric == 'receptions' ? 'negative binomial' : 'normal',
    rawChance: raw,
    adjustedChance: adjusted,
    chance: shrunk,
    market: market,
    capped: capped,
    games: prior.length,
    side: side,
    factors: [
      PropFactor(label: 'Usage', detail: 'start · $shareLabel', delta: base),
      PropFactor(
        label: 'Snaps',
        detail: snap.known ? '${_pct(snap.pct)} of snaps' : 'no earlier snaps',
        delta: afterSnap - base,
      ),
      PropFactor(
        label: 'Pass rate',
        detail: '${_pct(passRate)} pass',
        delta: afterPass - afterSnap,
      ),
      PropFactor(
        label: 'Team total',
        detail: script.detail,
        delta: afterScript - afterPass,
      ),
      PropFactor(
        label: 'Defense',
        detail: defense.detail,
        delta: afterDefense - afterScript,
      ),
      PropFactor(
        label: 'Teammates out',
        detail: mates.detail,
        delta: mean - afterDefense,
      ),
    ],
  );
}

class _Usage {
  const _Usage(this.share, this.efficiency);
  final double share, efficiency;
}

_Usage? _usage(
  UsageIndex index,
  List<PlayerGame> window,
  String metric,
  String position,
) {
  var stat = 0.0, volume = 0.0, efficiencyDen = 0.0, teamDenom = 0.0;
  var counted = 0;
  for (final game in window) {
    final value = game.stats[metric];
    if (value == null) continue;
    final off = index._offense[_key(game.season, game.week, game.team)];
    if (off == null) continue;
    counted++;
    stat += value.toDouble();
    switch (metric) {
      case 'passing_yards':
        final attempts = game.stats['attempts']?.toDouble() ?? 0;
        volume += attempts;
        efficiencyDen += attempts;
        teamDenom += off.attempts;
        break;
      case 'rushing_yards':
        final carries = game.stats['carries']?.toDouble() ?? 0;
        volume += carries;
        efficiencyDen += carries;
        teamDenom += off.carries;
        break;
      case 'receiving_yards':
      case 'receptions':
        final targets = game.stats['targets']?.toDouble() ?? 0;
        volume += targets;
        efficiencyDen += targets;
        teamDenom += off.attempts;
        break;
    }
  }
  if (counted < 4 || efficiencyDen <= 0 || teamDenom <= 0) return null;
  final prior = switch (metric) {
    'passing_yards' => position == 'QB' ? 0.92 : 0.08,
    'rushing_yards' => _rushPrior(position),
    _ => _targetPrior(position),
  };
  final priorWeight = metric == 'passing_yards' ? 30.0 : 40.0;
  final share = _shrink(volume, teamDenom, prior, priorWeight);
  final efficiency = switch (metric) {
    'passing_yards' => _shrink(stat, efficiencyDen, 7.0, 40),
    'rushing_yards' => _shrink(stat, efficiencyDen, 4.3, 16),
    'receiving_yards' => _shrink(stat, efficiencyDen, 7.5, 10),
    'receptions' => _shrink(stat, efficiencyDen, 0.65, 12),
    _ => 0.0,
  };
  if (!share.isFinite || !efficiency.isFinite || efficiency <= 0) return null;
  final cap = metric == 'passing_yards' ? 0.98 : 0.60;
  return _Usage(share.clamp(0.01, cap), efficiency);
}

double _passRate(UsageIndex index, String team, _Cut cut) {
  final prior = _taggedBefore(index._plays[team], cut);
  final last = prior.length <= 6 ? prior : prior.sublist(prior.length - 6);
  var attempts = 0.0, plays = 0.0;
  for (final row in last) {
    attempts += row.a;
    plays += row.a + row.b;
  }
  if (plays <= 0) return leaguePassRate;
  return _shrink(attempts, plays, leaguePassRate, 40);
}

class _DefenseRead {
  const _DefenseRead(this.factor, this.detail);
  final double factor;
  final String detail;
}

_DefenseRead _defense(
  UsageIndex index,
  String opponent,
  String metric,
  _Cut cut,
  int beforeSeason,
) {
  final prior = _taggedBefore(index._defense[opponent], cut);
  if (prior.isEmpty) {
    return const _DefenseRead(1, 'no earlier games');
  }
  final recent = prior.length <= 4 ? prior : prior.sublist(prior.length - 4);
  final seasonKey = beforeSeason >= 9000 ? prior.last.season : beforeSeason;
  final season = [
    for (final row in prior)
      if (row.season == seasonKey) row,
  ];
  final recentAvg = _meanOf(recent, metric);
  final seasonAvg = season.length >= 2 ? _meanOf(season, metric) : recentAvg;
  final blend = season.length >= 2
      ? 0.6 * recentAvg + 0.4 * seasonAvg
      : recentAvg;
  final league = switch (metric) {
    'passing_yards' => 230.0,
    'rushing_yards' => 115.0,
    'receiving_yards' => 220.0,
    'receptions' => 21.0,
    _ => 1.0,
  };
  final factor = (blend / league).clamp(0.80, 1.20);
  final detail = factor > 1.03
      ? 'softer, recent and season'
      : factor < 0.97
      ? 'tougher, recent and season'
      : 'about average';
  return _DefenseRead(factor, detail);
}

class _Script {
  const _Script(this.scale, this.detail);
  final double scale;
  final String detail;
}

_Script _script(
  UsageIndex index,
  String team,
  String opponent,
  _Cut cut, {
  double? teamSpread,
  double? total,
}) {
  if (teamSpread != null &&
      total != null &&
      teamSpread.isFinite &&
      total.isFinite) {
    final implied = (total - teamSpread) / 2;
    if (implied.isFinite && implied > 0) {
      return _Script(
        (implied / _leaguePoints).clamp(0.75, 1.25),
        '${implied.toStringAsFixed(1)} implied',
      );
    }
  }
  final own = _points(index._points[team], cut, scored: true);
  final allowed = opponent.isEmpty
      ? null
      : _points(index._points[opponent], cut, scored: false);
  final implied = own != null && allowed != null
      ? 0.5 * own + 0.5 * allowed
      : own ?? allowed;
  if (implied == null) return const _Script(1, 'not on this board');
  return _Script(
    (implied / _leaguePoints).clamp(0.75, 1.25),
    '${implied.toStringAsFixed(1)} from earlier games',
  );
}

double? _points(List<_Tagged>? rows, _Cut cut, {required bool scored}) {
  final prior = _taggedBefore(rows, cut);
  if (prior.isEmpty) return null;
  final last = prior.length <= 6 ? prior : prior.sublist(prior.length - 6);
  var sum = 0.0;
  for (final row in last) {
    sum += scored ? row.a : row.b;
  }
  final raw = sum / last.length;
  return (last.length * raw + 4 * _leaguePoints) / (last.length + 4);
}

class _SnapRead {
  const _SnapRead(this.known, this.pct, this.factor);
  final bool known;
  final double pct, factor;
}

_SnapRead _snap(
  UsageIndex index,
  String name,
  String position,
  _Cut cut,
  int beforeSeason,
) {
  final live = beforeSeason >= 9000 && cut.date == null;
  if (!live && cut.date == null && beforeSeason != index.matchupSeason) {
    return const _SnapRead(false, 0, 1);
  }
  final rows = index._snaps[normalizePropName(name)];
  if (rows == null || rows.isEmpty) return const _SnapRead(false, 0, 1);
  final kept = [
    for (final row in rows)
      if (_snapCounts(index, row, cut, live)) row,
  ];
  if (kept.isEmpty) return const _SnapRead(false, 0, 1);
  final last = kept.length <= 4 ? kept : kept.sublist(kept.length - 4);
  var sum = 0.0;
  for (final row in last) {
    sum += row.pct;
  }
  final pct = sum / last.length;
  final typical = _typicalSnap(position);
  final factor = (pct / typical).clamp(0.75, 1.25);
  return _SnapRead(true, pct, factor);
}

class _Mates {
  const _Mates(this.qbShare, this.skillShare, this.detail);
  final double qbShare, skillShare;
  final String detail;
}

_Mates _teammates(
  UsageIndex index, {
  required String selfId,
  required String metric,
  required String team,
  required _Cut cut,
  required int beforeSeason,
  required int beforeWeek,
  required List<({String name, String position})> extra,
}) {
  final listed = <({String name, String position})>[
    ...extra,
    if (beforeSeason == index.matchupSeason && cut.date == null)
      ...[
        for (final row
            in index._outs['$beforeSeason|$beforeWeek|$team'] ?? const <_Out>[])
          (name: row.player, position: row.position),
      ],
  ];
  if (listed.isEmpty) return const _Mates(0, 0, 'none out');
  var qb = 0.0, skill = 0.0, count = 0;
  final seen = <String>{};
  for (final row in listed) {
    final id = index.onlyId(row.name);
    if (id == null || id == selfId || !seen.add(id)) continue;
    final position = row.position.isEmpty
        ? (index.positionOf[id] ?? '')
        : row.position;
    final share = _storedShare(index, id, metric, position, cut);
    if (share == null) continue;
    count++;
    if (metric == 'passing_yards' && position == 'QB') {
      qb += share;
    } else if (metric == 'rushing_yards' && _rusher(position)) {
      skill += share;
    } else if (metric != 'passing_yards' &&
        metric != 'rushing_yards' &&
        _catcher(position)) {
      skill += share;
    } else if (metric == 'passing_yards' && _catcher(position)) {
      skill += share;
    }
  }
  qb = qb.clamp(0.0, 0.45);
  skill = skill.clamp(0.0, 0.45);
  if (count == 0) return const _Mates(0, 0, 'none out');
  final noun = count == 1 ? '1 out' : '$count out';
  return _Mates(qb, skill, noun);
}

double? _storedShare(
  UsageIndex index,
  String playerId,
  String metric,
  String position,
  _Cut cut,
) {
  final games = index.byPlayer[playerId];
  if (games == null) return null;
  final prior = [
    for (final game in games)
      if (cut.allows(game.season, game.week, game.date)) game,
  ];
  if (prior.length < 4) return null;
  final window = prior.length <= 8 ? prior : prior.sublist(prior.length - 8);
  final kind = metric == 'rushing_yards' && _rusher(position)
      ? 'rushing_yards'
      : metric == 'passing_yards' && position == 'QB'
      ? 'passing_yards'
      : 'receiving_yards';
  return _usage(index, window, kind, position)?.share;
}

double _statMean({
  required String metric,
  required double share,
  required double passRate,
  required double efficiency,
  required double defense,
  required double scale,
  required double snapFactor,
  required double qbVacated,
  required double skillVacated,
}) {
  final cap = metric == 'passing_yards' ? 0.98 : 0.50;
  final hole = (metric == 'passing_yards' ? qbVacated : skillVacated).clamp(
    0.0,
    0.45,
  );
  // The boost cannot pass 1.35× the player's own share or the absolute
  // cap. A share that is already past that cap is left where it is.
  final raw = hole <= 0 || hole >= 1 ? share : share / (1 - hole);
  final boostCap = math.max(share, math.min(cap, share * 1.35));
  final boosted = raw.clamp(math.min(share, boostCap), boostCap);
  final penalty = metric == 'passing_yards'
      ? (1 - 0.10 * skillVacated).clamp(0.88, 1.0)
      : 1.0;
  final pass = passRate / leaguePassRate;
  final rush = (1 - passRate) / (1 - leaguePassRate);
  final mean = switch (metric) {
    'passing_yards' =>
      leaguePassAttempts * pass * scale * boosted * snapFactor * efficiency * defense * penalty,
    'rushing_yards' =>
      leagueRushAttempts * rush * scale * boosted * snapFactor * efficiency * defense,
    _ =>
      leaguePassAttempts * pass * scale * snapFactor * boosted * efficiency * defense,
  };
  final ceiling = switch (metric) {
    'passing_yards' => 450.0,
    'receptions' => 16.0,
    _ => 220.0,
  };
  if (!mean.isFinite || mean < 0) return 0;
  return mean > ceiling ? ceiling : mean;
}

/// Chance the stat finishes on [side] of [line].
///
/// Yards use a normal curve with the player's own spread. Receptions use
/// a negative binomial, which stays at zero or above. A half-point line
/// has no push, so the two sides add to 1. An integer line leaves the
/// tie out of both sides.
/// The curve is fit on overs. An under is one minus the recalibrated over,
/// so the two sides of a half-point line stay mirrors.
double _recalibrate(double raw, LineSide side, PropCalibrator? calibrator) {
  if (calibrator == null || calibrator.isIdentity) return raw;
  final overRaw = side == LineSide.over
      ? raw
      : (1 - raw).clamp(1e-4, 1 - 1e-4).toDouble();
  final overAdjusted = calibrator.apply(overRaw);
  if (side == LineSide.over) return overAdjusted;
  return (1 - overAdjusted).clamp(1e-4, 1 - 1e-4).toDouble();
}

double sideChance({
  required String metric,
  required double mean,
  required double sd,
  required double line,
  required LineSide side,
}) {
  if (metric == 'receptions') {
    return _negativeBinomialSide(mean: mean, sd: sd, line: line, side: side);
  }
  return _normalSide(mean: mean, sd: sd, line: line, side: side);
}

double _normalSide({
  required double mean,
  required double sd,
  required double line,
  required LineSide side,
}) {
  final width = sd <= 0 ? 1.0 : sd;
  final boundary = _whole(line)
      ? (side == LineSide.over ? line + 0.5 : line - 0.5)
      : line;
  final z = (boundary - mean) / width;
  final cdf = normalCdf(z);
  final chance = side == LineSide.over ? 1 - cdf : cdf;
  return chance.clamp(1e-4, 1 - 1e-4);
}

double _negativeBinomialSide({
  required double mean,
  required double sd,
  required double line,
  required LineSide side,
}) {
  final mu = mean <= 0 ? 0.05 : mean;
  final variance = math.max(sd * sd, mu + 0.25);
  final r = (mu * mu / (variance - mu)).clamp(0.3, 200.0);
  if (side == LineSide.over) {
    final cdf = _nbCdf(mu, r, line.floor());
    return (1 - cdf).clamp(1e-4, 1 - 1e-4);
  }
  final max = _whole(line) ? line.floor() - 1 : line.floor();
  return _nbCdf(mu, r, max).clamp(1e-4, 1 - 1e-4);
}

/// Standard normal CDF. Abramowitz and Stegun 26.2.17.
double normalCdf(double z) {
  if (z.isNaN) return 0.5;
  final x = z.abs();
  final t = 1 / (1 + 0.2316419 * x);
  const b1 = 0.319381530;
  const b2 = -0.356563782;
  const b3 = 1.781477937;
  const b4 = -1.821255978;
  const b5 = 1.330274429;
  final density = math.exp(-0.5 * x * x) / math.sqrt(2 * math.pi);
  final tail =
      density * (((((b5 * t + b4) * t + b3) * t + b2) * t + b1) * t);
  final cdf = z >= 0 ? 1 - tail : tail;
  if (cdf < 0) return 0;
  if (cdf > 1) return 1;
  return cdf;
}

double _nbCdf(double mean, double r, int k) {
  if (k < 0) return 0;
  final p = r / (r + mean);
  var pmf = math.pow(p, r).toDouble();
  if (!pmf.isFinite || pmf < 0) pmf = 0;
  var cdf = pmf;
  final fail = 1 - p;
  for (var i = 1; i <= k; i++) {
    pmf *= (i + r - 1) / i * fail;
    cdf += pmf;
    if (cdf >= 1) return 1;
  }
  if (cdf < 0) return 0;
  if (cdf > 1) return 1;
  return cdf;
}

double _spread(List<double> values, double prior, double floor) {
  if (values.length < 2) return math.max(prior, floor);
  final mean = values.reduce((a, b) => a + b) / values.length;
  var ss = 0.0;
  for (final value in values) {
    final gap = value - mean;
    ss += gap * gap;
  }
  final sample = math.sqrt(ss / (values.length - 1));
  final n = values.length.toDouble();
  final shrunk = math.sqrt((n * sample * sample + 6 * prior * prior) / (n + 6));
  return math.max(shrunk, floor);
}

double _sdPrior(String metric) => switch (metric) {
  'passing_yards' => 75,
  'rushing_yards' => 28,
  'receiving_yards' => 32,
  _ => 2,
};

double _sdFloor(String metric) => switch (metric) {
  'passing_yards' => 40,
  'rushing_yards' => 12,
  'receiving_yards' => 14,
  _ => 1.1,
};

double _shrink(double sum, double weight, double prior, double priorWeight) {
  if (weight <= 0) return prior;
  return (sum + priorWeight * prior) / (weight + priorWeight);
}

double _targetPrior(String position) => switch (position) {
  'WR' => 0.20,
  'TE' => 0.15,
  'RB' => 0.12,
  'FB' => 0.04,
  _ => 0.08,
};

double _rushPrior(String position) => switch (position) {
  'RB' => 0.45,
  'QB' => 0.10,
  'FB' => 0.08,
  _ => 0.03,
};

double _typicalSnap(String position) => switch (position) {
  'QB' => 0.95,
  'RB' => 0.55,
  'WR' => 0.78,
  'TE' => 0.70,
  _ => 0.60,
};

bool _catcher(String position) =>
    position == 'WR' || position == 'TE' || position == 'RB';

bool _rusher(String position) =>
    position == 'RB' || position == 'QB' || position == 'FB';

bool _whole(double line) => (line - line.roundToDouble()).abs() < 1e-9;

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

bool _snapCounts(UsageIndex index, _Snap row, _Cut cut, bool live) {
  if (live) return true;
  if (cut.date != null) {
    final off = index._offense[_key(index.matchupSeason, row.week, row.team)];
    if (off == null) return false;
    return cut.allows(index.matchupSeason, row.week, off.date);
  }
  return row.week < cut.week;
}

bool _listedOut(String status) =>
    status == 'Out' || status == 'Doubtful' || status == 'Injured Reserve';

List<_Tagged> _taggedBefore(List<_Tagged>? rows, _Cut cut) {
  if (rows == null) return const [];
  return [
    for (final row in rows)
      if (cut.allows(row.season, row.week, row.date)) row,
  ];
}

double _meanOf(List<_Tagged> rows, String metric) {
  var sum = 0.0;
  for (final row in rows) {
    sum += switch (metric) {
      'passing_yards' => row.a,
      'rushing_yards' => row.b,
      'receiving_yards' => row.c,
      _ => row.d,
    };
  }
  return rows.isEmpty ? 0 : sum / rows.length;
}

void _addStat(_Offense off, PlayerGame game) {
  void plus(String key, void Function(double value) write) {
    final value = game.stats[key];
    if (value != null) write(value.toDouble());
  }

  plus('attempts', (value) => off.attempts += value);
  plus('carries', (value) => off.carries += value);
  plus('targets', (value) => off.targets += value);
  plus('passing_yards', (value) => off.passYds += value);
  plus('rushing_yards', (value) => off.rushYds += value);
  plus('receiving_yards', (value) => off.recYds += value);
  plus('receptions', (value) => off.receptions += value);
}

String _key(int season, int week, String team) => '$season|$week|$team';

int _gameOrder(PlayerGame a, PlayerGame b) {
  final season = a.season.compareTo(b.season);
  if (season != 0) return season;
  final week = a.week.compareTo(b.week);
  if (week != 0) return week;
  return a.date.compareTo(b.date);
}

int _tagOrder(_Tagged a, _Tagged b) {
  final season = a.season.compareTo(b.season);
  if (season != 0) return season;
  return a.week.compareTo(b.week);
}

String normalizePropName(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r"[^a-z0-9 ]"), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _pct(double value) => '${(value * 100).round()}%';
