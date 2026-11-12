import 'matchup.dart';
import 'nfl_teams.dart';

/// Statuses that can change a prop or a game. Everyone else is left off
/// the list, including players marked Active.
const injuryStatuses = <String>{
  'Out',
  'Doubtful',
  'Questionable',
  'Injured Reserve',
};

/// One listed player from one source, before sources are compared.
class InjuryEntry {
  const InjuryEntry({
    required this.player,
    required this.team,
    required this.position,
    required this.status,
    required this.sourceId,
    required this.sourceLabel,
    required this.official,
    required this.fetchedAt,
    this.injury = '',
    this.updatedAt,
    this.agrees = const [],
    this.differs,
    this.week,
  });

  final String player, team, position, status, sourceId, sourceLabel;
  final bool official;
  final DateTime fetchedAt;
  final String injury;
  final DateTime? updatedAt;
  final List<String> agrees;
  final String? differs;
  final int? week;

  bool get outLike =>
      status == 'Out' || status == 'Doubtful' || status == 'Injured Reserve';

  InjuryEntry copyWith({List<String>? agrees, String? differs}) => InjuryEntry(
    player: player,
    team: team,
    position: position,
    status: status,
    sourceId: sourceId,
    sourceLabel: sourceLabel,
    official: official,
    fetchedAt: fetchedAt,
    injury: injury,
    updatedAt: updatedAt,
    agrees: agrees ?? this.agrees,
    differs: differs ?? this.differs,
    week: week,
  );

  Map<String, Object?> toJson() => {
    'player': player,
    'team': team,
    'position': position,
    'status': status,
    'injury': injury,
    'sourceId': sourceId,
    'sourceLabel': sourceLabel,
    'official': official,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'agrees': agrees,
    'differs': differs,
    'week': week,
  };

  factory InjuryEntry.fromJson(Map<String, dynamic> json) {
    final agrees = json['agrees'];
    return InjuryEntry(
      player: '${json['player'] ?? ''}'.trim(),
      team: canonicalInjuryTeam('${json['team'] ?? ''}'),
      position: '${json['position'] ?? ''}'.trim().toUpperCase(),
      status: normalizeInjuryStatus('${json['status'] ?? ''}') ?? '',
      injury: '${json['injury'] ?? ''}'.trim(),
      sourceId: '${json['sourceId'] ?? ''}',
      sourceLabel: '${json['sourceLabel'] ?? ''}',
      official: json['official'] == true,
      fetchedAt:
          DateTime.tryParse('${json['fetchedAt'] ?? ''}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}')?.toUtc(),
      agrees: agrees is List ? [for (final item in agrees) '$item'] : const [],
      differs: json['differs'] == null ? null : '${json['differs']}',
      week: json['week'] is int
          ? json['week'] as int
          : int.tryParse('${json['week']}'),
    );
  }
}

class SourceNote {
  const SourceNote({
    required this.id,
    required this.label,
    required this.ok,
    this.fetchedAt,
    this.problem,
  });

  final String id, label;
  final bool ok;
  final DateTime? fetchedAt;
  final String? problem;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'ok': ok,
    'fetchedAt': fetchedAt?.toUtc().toIso8601String(),
    'problem': problem,
  };

  factory SourceNote.fromJson(Map<String, dynamic> json) => SourceNote(
    id: '${json['id'] ?? ''}',
    label: '${json['label'] ?? ''}',
    ok: json['ok'] == true,
    fetchedAt: DateTime.tryParse('${json['fetchedAt'] ?? ''}')?.toUtc(),
    problem: json['problem'] == null ? null : '${json['problem']}',
  );
}

class InjuryChange {
  const InjuryChange({
    required this.player,
    required this.team,
    required this.position,
    required this.status,
    required this.summary,
    required this.removed,
    this.previousStatus,
    this.entry,
  });

  final String player, team, position, status, summary;
  final bool removed;
  final String? previousStatus;
  final InjuryEntry? entry;

  Map<String, Object?> toJson() => {
    'player': player,
    'team': team,
    'position': position,
    'status': status,
    'summary': summary,
    'removed': removed,
    'previousStatus': previousStatus,
    'entry': entry?.toJson(),
  };

  factory InjuryChange.fromJson(Map<String, dynamic> json) {
    final entry = json['entry'];
    return InjuryChange(
      player: '${json['player'] ?? ''}',
      team: '${json['team'] ?? ''}',
      position: '${json['position'] ?? ''}',
      status: '${json['status'] ?? ''}',
      summary: '${json['summary'] ?? ''}',
      removed: json['removed'] == true,
      previousStatus: json['previousStatus'] == null
          ? null
          : '${json['previousStatus']}',
      entry: entry is Map
          ? InjuryEntry.fromJson(Map<String, dynamic>.from(entry))
          : null,
    );
  }
}

class InjuryReport {
  const InjuryReport({
    required this.fetchedAt,
    required this.live,
    required this.entries,
    required this.changes,
    required this.sources,
    required this.notice,
  });

  final DateTime fetchedAt;
  final bool live;
  final List<InjuryEntry> entries;
  final List<InjuryChange> changes;
  final List<SourceNote> sources;
  final String notice;

  DateTime? get checkedAt {
    DateTime? latest;
    for (final source in sources) {
      final at = source.fetchedAt;
      if (at == null || !source.ok) continue;
      if (latest == null || at.isAfter(latest)) latest = at;
    }
    return latest;
  }

  String freshness(DateTime now) {
    if (!live) return 'Stored report, not a live check';
    final at = checkedAt;
    if (at == null) return 'Not checked yet';
    return updatedAgo(at, now);
  }

  Map<String, Object?> toJson() => {
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'live': live,
    'notice': notice,
    'entries': [for (final entry in entries) entry.toJson()],
    'changes': [for (final change in changes) change.toJson()],
    'sources': [for (final source in sources) source.toJson()],
  };

  factory InjuryReport.fromJson(Map<String, dynamic> json) {
    List<T> read<T>(Object? raw, T Function(Map<String, dynamic>) decode) {
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (item is Map) decode(Map<String, dynamic>.from(item)),
      ];
    }

    return InjuryReport(
      fetchedAt:
          DateTime.tryParse('${json['fetchedAt'] ?? ''}')?.toUtc() ??
          DateTime.now().toUtc(),
      live: json['live'] == true,
      notice: '${json['notice'] ?? ''}',
      entries: read(json['entries'], InjuryEntry.fromJson),
      changes: read(json['changes'], InjuryChange.fromJson),
      sources: read(json['sources'], SourceNote.fromJson),
    );
  }

  /// Latest week of the bundled nflverse file. Not a live check.
  /// Changes are against the week before it. A thin week does not mark
  /// everyone else as back.
  factory InjuryReport.fromMatchup(MatchupContext context, {DateTime? now}) {
    final clock = (now ?? DateTime.now()).toUtc();
    final byWeek = <int, List<InjuryEntry>>{};
    for (final injury in context.injuries) {
      final status = normalizeInjuryStatus(injury.status);
      if (status == null || injury.player.isEmpty) continue;
      byWeek
          .putIfAbsent(injury.week, () => [])
          .add(
            InjuryEntry(
              player: injury.player,
              team: canonicalInjuryTeam(injury.team),
              position: injury.position,
              status: status,
              injury: injury.injury,
              sourceId: 'nflverse',
              sourceLabel: 'nflverse, stored report',
              official: false,
              fetchedAt: clock,
              week: injury.week,
            ),
          );
    }
    if (byWeek.isEmpty) {
      return InjuryReport(
        fetchedAt: clock,
        live: false,
        entries: const [],
        changes: const [],
        sources: const [
          SourceNote(
            id: 'nflverse',
            label: 'nflverse, stored report',
            ok: false,
            problem: 'The stored file has no injury rows.',
          ),
        ],
        notice: 'The stored nflverse file has no injury rows. Connect the local backend for a live check.',
      );
    }
    final weeks = byWeek.keys.toList()..sort();
    final week = weeks.last;
    final previousWeek = weeks.length < 2 ? null : weeks[weeks.length - 2];
    final current = _dedupe(byWeek[week]!);
    final previous = previousWeek == null
        ? const <InjuryEntry>[]
        : _dedupe(byWeek[previousWeek]!);
    return assembleInjuryReport(
      now: clock,
      live: false,
      espn: const [],
      nfl: const [],
      nflverse: current,
      previous: previous,
      sources: [
        SourceNote(
          id: 'nflverse',
          label: 'nflverse, stored report',
          ok: true,
          fetchedAt: clock,
        ),
      ],
      storedWeek: week,
      previousWeek: previousWeek,
    );
  }
}

class InjuryImpact {
  const InjuryImpact({
    required this.line,
    required this.markets,
    required this.offense,
  });

  /// Plain effect, such as "WR out: lowers QB passing yards."
  final String line;
  final List<String> markets;
  final bool offense;
}

class InjuryBadge {
  const InjuryBadge({required this.outCount, required this.questionableCount});

  final int outCount, questionableCount;

  bool get visible => outCount > 0 || questionableCount > 0;

  bool get severe => outCount > 0;

  String get label {
    if (outCount > 0) return outCount == 1 ? '1 out' : '$outCount out';
    if (questionableCount == 1) return '1 questionable';
    return '$questionableCount questionable';
  }
}

/// How soon to ask again. In season this is 2 minutes near a kickoff and
/// 5 minutes otherwise. Out of season, with no kickoff close, it waits
/// longer so the check is not constant. One request per source, not a crawl.
Duration injuryPollInterval({
  required DateTime now,
  required Iterable<DateTime> kickoffs,
}) {
  var nearest = const Duration(days: 30);
  for (final kick in kickoffs) {
    final delta = kick.toUtc().difference(now.toUtc()).abs();
    if (delta < nearest) nearest = delta;
  }
  final month = now.toUtc().month;
  final inSeason = month >= 8 || month <= 2;
  if (nearest <= const Duration(hours: 6)) return const Duration(minutes: 2);
  if (inSeason) return const Duration(minutes: 5);
  return const Duration(hours: 6);
}

/// NFL.com's page is one document, so it can follow the fast cadence,
/// but not quicker than every 5 minutes. The file from nflverse is a
/// compiled season, so it is checked on a slow clock.
Duration nflConfirmationInterval(Duration fast) {
  if (fast < const Duration(minutes: 5)) return const Duration(minutes: 5);
  return fast;
}

const nflverseRefreshInterval = Duration(hours: 2);

String? normalizeInjuryStatus(String raw) {
  final text = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return switch (text) {
    'out' => 'Out',
    'doubtful' => 'Doubtful',
    'questionable' => 'Questionable',
    'injured reserve' || 'ir' || 'reserve/injured' => 'Injured Reserve',
    _ => null,
  };
}

String canonicalInjuryTeam(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final code = canonicalTeam(trimmed);
  if (code != null) return code;
  final upper = trimmed.toUpperCase();
  if (upper == 'LA') return 'LAR';
  if (upper == 'WSH') return 'WAS';
  return upper;
}

bool sameClub(String a, String b) {
  final left = canonicalInjuryTeam(a);
  final right = canonicalInjuryTeam(b);
  if (left.isEmpty || right.isEmpty) return false;
  return boxScoreTeam(left) == boxScoreTeam(right);
}

String injuryPersonKey(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String injuryKey(String team, String player) =>
    '${boxScoreTeam(canonicalInjuryTeam(team))}|${injuryPersonKey(player)}';

int injuryStatusRank(String status) => switch (status) {
  'Out' => 0,
  'Injured Reserve' => 1,
  'Doubtful' => 2,
  'Questionable' => 3,
  _ => 4,
};

String updatedAgo(DateTime at, DateTime now) {
  final age = now.toUtc().difference(at.toUtc());
  if (age.isNegative || age.inMinutes < 1) return 'Updated just now';
  if (age.inMinutes < 60) return 'Updated ${age.inMinutes} min ago';
  if (age.inHours < 48) {
    final hours = age.inHours;
    return 'Updated $hours ${hours == 1 ? 'hour' : 'hours'} ago';
  }
  final days = age.inDays;
  return 'Updated $days ${days == 1 ? 'day' : 'days'} ago';
}

InjuryImpact? injuryImpact(String position, String status) {
  final normalized = normalizeInjuryStatus(status);
  if (normalized == null) return null;
  final effect = _effectFor(position);
  if (effect == null) return null;
  final pos = position.trim().toUpperCase();
  final word = switch (normalized) {
    'Out' => 'out',
    'Doubtful' => 'doubtful',
    'Questionable' => 'questionable',
    'Injured Reserve' => 'on injured reserve',
    _ => normalized.toLowerCase(),
  };
  final line = normalized == 'Questionable'
      ? '$pos $word: may ${effect.maybe} if he sits.'
      : '$pos $word: ${effect.out}.';
  return InjuryImpact(
    line: line,
    markets: effect.markets,
    offense: effect.offense,
  );
}

bool injuryAffectsProp(
  InjuryEntry entry, {
  required String market,
  required String playerName,
  String? playerTeam,
  String? opponent,
}) {
  if (playerName.trim().isNotEmpty &&
      injuryPersonKey(entry.player) == injuryPersonKey(playerName)) {
    return true;
  }
  final impact = injuryImpact(entry.position, entry.status);
  if (impact == null || !impact.markets.contains(market)) return false;
  if (impact.offense) {
    if (playerTeam == null || playerTeam.isEmpty) return false;
    return sameClub(entry.team, playerTeam);
  }
  if (opponent == null || opponent.isEmpty) return false;
  return sameClub(entry.team, opponent);
}

InjuryBadge? badgeForClubs(InjuryReport? report, Iterable<String> clubs) {
  if (report == null) return null;
  var outCount = 0;
  var questionable = 0;
  for (final entry in report.entries) {
    if (!clubs.any((club) => sameClub(entry.team, club))) continue;
    if (injuryImpact(entry.position, entry.status) == null) continue;
    if (entry.outLike) {
      outCount++;
    } else if (entry.status == 'Questionable') {
      questionable++;
    }
  }
  final badge = InjuryBadge(
    outCount: outCount,
    questionableCount: questionable,
  );
  return badge.visible ? badge : null;
}

InjuryBadge? badgeForProp(
  InjuryReport? report, {
  required String market,
  required String playerName,
  String? playerTeam,
  String? opponent,
}) {
  if (report == null) return null;
  var outCount = 0;
  var questionable = 0;
  for (final entry in report.entries) {
    if (!injuryAffectsProp(
      entry,
      market: market,
      playerName: playerName,
      playerTeam: playerTeam,
      opponent: opponent,
    )) {
      continue;
    }
    if (entry.outLike) {
      outCount++;
    } else if (entry.status == 'Questionable') {
      questionable++;
    }
  }
  final badge = InjuryBadge(
    outCount: outCount,
    questionableCount: questionable,
  );
  return badge.visible ? badge : null;
}

/// ESPN first. NFL.com and nflverse fill gaps and confirm. A name that
/// disappears from a much shorter list is not called "back".
InjuryReport assembleInjuryReport({
  required DateTime now,
  required bool live,
  required List<InjuryEntry> espn,
  required List<InjuryEntry> nfl,
  required List<InjuryEntry> nflverse,
  required List<InjuryEntry> previous,
  required List<SourceNote> sources,
  int? storedWeek,
  int? previousWeek,
}) {
  final clock = now.toUtc();
  final fast = _dedupe(espn);
  final official = _dedupe(nfl);
  final backup = _dedupe(nflverse);
  final fastByKey = {
    for (final entry in fast) injuryKey(entry.team, entry.player): entry,
  };
  final officialByKey = {
    for (final entry in official) injuryKey(entry.team, entry.player): entry,
  };
  final backupByKey = {
    for (final entry in backup) injuryKey(entry.team, entry.player): entry,
  };
  final keys = {...fastByKey.keys, ...officialByKey.keys, ...backupByKey.keys};
  final entries = <InjuryEntry>[];
  for (final key in keys) {
    final base = fastByKey[key] ?? officialByKey[key] ?? backupByKey[key];
    if (base == null) continue;
    final agrees = <String>[];
    final differs = <String>[];
    void compare(InjuryEntry? other) {
      if (other == null ||
          identical(other, base) ||
          other.sourceId == base.sourceId) {
        return;
      }
      if (other.status == base.status) {
        agrees.add(other.sourceLabel);
      } else {
        differs.add('${other.sourceLabel} says ${other.status}');
      }
    }

    compare(fastByKey[key]);
    compare(officialByKey[key]);
    compare(backupByKey[key]);
    entries.add(
      base.copyWith(
        agrees: agrees,
        differs: differs.isEmpty ? null : differs.join(' · '),
      ),
    );
  }
  entries.sort((a, b) {
    final team = a.team.compareTo(b.team);
    if (team != 0) return team;
    final status = injuryStatusRank(a.status)
        .compareTo(injuryStatusRank(b.status));
    if (status != 0) return status;
    return a.player.compareTo(b.player);
  });
  final prior = _dedupe(previous);
  final partial =
      prior.length > 20 &&
      entries.isNotEmpty &&
      entries.length * 2 < prior.length;
  final changes = _changes(
    entries,
    prior,
    allowRemovals: !partial && prior.isNotEmpty,
  );
  final notice = _notice(
    live: live,
    sources: sources,
    partial: partial,
    storedWeek: storedWeek,
    previousWeek: previousWeek,
  );
  return InjuryReport(
    fetchedAt: clock,
    live: live,
    entries: entries,
    changes: changes,
    sources: sources,
    notice: notice,
  );
}

List<InjuryEntry> parseEspnInjuries(
  Object? decoded, {
  required DateTime fetchedAt,
}) {
  if (decoded is! Map) return const [];
  final teams = decoded['injuries'];
  if (teams is! List) return const [];
  final found = <InjuryEntry>[];
  for (final team in teams) {
    if (team is! Map) continue;
    final rows = team['injuries'];
    if (rows is! List) continue;
    for (final row in rows) {
      if (row is! Map) continue;
      final status = normalizeInjuryStatus('${row['status'] ?? ''}');
      if (status == null) continue;
      final athlete = row['athlete'];
      if (athlete is! Map) continue;
      final player = '${athlete['displayName'] ?? ''}'.trim();
      if (player.isEmpty) continue;
      final club = _espnTeam(athlete, team);
      if (club.isEmpty) continue;
      found.add(
        InjuryEntry(
          player: player,
          team: club,
          position: _espnPosition(athlete),
          status: status,
          injury: _espnInjury(row),
          sourceId: 'espn',
          sourceLabel: 'ESPN, unofficial',
          official: false,
          fetchedAt: fetchedAt.toUtc(),
          updatedAt: DateTime.tryParse('${row['date'] ?? ''}')?.toUtc(),
        ),
      );
    }
  }
  return _dedupe(found);
}

List<InjuryEntry> parseNflInjuryPage(
  String html, {
  required DateTime fetchedAt,
}) {
  final weekMatch = RegExp(
    r'WEEK\s+(\d+)',
    caseSensitive: false,
  ).firstMatch(html);
  final week = weekMatch == null ? null : int.tryParse(weekMatch.group(1)!);
  final titles = RegExp(r'd3-o-section-sub-title">\s*<span>([^<]+)</span>')
      .allMatches(html)
      .toList();
  final found = <InjuryEntry>[];
  for (var i = 0; i < titles.length; i++) {
    final label = _plain(titles[i].group(1) ?? '');
    final team = teamFromLabel(label);
    if (team == null) continue;
    final start = titles[i].end;
    final end = i + 1 < titles.length ? titles[i + 1].start : html.length;
    found.addAll(_nflRows(html.substring(start, end), team, week, fetchedAt));
  }
  return _dedupe(found);
}

List<InjuryEntry> parseNflverseInjuries(
  String csv, {
  required DateTime fetchedAt,
  int? season,
}) {
  final rows = splitCsv(csv);
  if (rows.isEmpty) return const [];
  final header = [for (final cell in rows.first) cell.trim()];
  int column(String name) => header.indexOf(name);
  final seasonCol = column('season');
  final weekCol = column('week');
  final teamCol = column('team');
  final positionCol = column('position');
  final nameCol = column('full_name');
  final statusCol = column('report_status');
  final injuryCol = column('report_primary_injury');
  final typeCol = column('season_type');
  if (weekCol < 0 || teamCol < 0 || nameCol < 0 || statusCol < 0) {
    return const [];
  }
  var year = season;
  if (year == null && seasonCol >= 0) {
    for (final row in rows.skip(1)) {
      final value = int.tryParse(_cell(row, seasonCol));
      if (value != null && value > (year ?? 0)) year = value;
    }
  }
  final listed = <List<String>>[];
  for (final row in rows.skip(1)) {
    if (year != null && seasonCol >= 0 && _cell(row, seasonCol) != '$year') {
      continue;
    }
    if (typeCol >= 0) {
      final type = _cell(row, typeCol).toUpperCase();
      if (type.isNotEmpty && type != 'REG') continue;
    }
    if (normalizeInjuryStatus(_cell(row, statusCol)) == null) continue;
    listed.add(row);
  }
  var week = 0;
  for (final row in listed) {
    final value = int.tryParse(_cell(row, weekCol)) ?? 0;
    if (value > week) week = value;
  }
  if (week == 0) return const [];
  final found = <InjuryEntry>[];
  for (final row in listed) {
    if ((int.tryParse(_cell(row, weekCol)) ?? 0) != week) continue;
    final player = _cell(row, nameCol);
    if (player.isEmpty) continue;
    final status = normalizeInjuryStatus(_cell(row, statusCol));
    if (status == null) continue;
    found.add(
      InjuryEntry(
        player: player,
        team: canonicalInjuryTeam(_cell(row, teamCol)),
        position: positionCol < 0 ? '' : _cell(row, positionCol).toUpperCase(),
        status: status,
        injury: injuryCol < 0 ? '' : _cell(row, injuryCol),
        sourceId: 'nflverse',
        sourceLabel: 'nflverse',
        official: false,
        fetchedAt: fetchedAt.toUtc(),
        week: week,
      ),
    );
  }
  return _dedupe(found);
}

/// The season nflverse files are named with. January and February still
/// belong to the season that started the previous year.
int nflSeasonYear(DateTime now) {
  final clock = now.toUtc();
  if (clock.month <= 2) return clock.year - 1;
  return clock.year;
}

String? teamFromLabel(String label) {
  final nick = label.trim().toLowerCase();
  if (nick.isEmpty) return null;
  final direct = canonicalTeam(label);
  if (direct != null) return direct;
  String? found;
  for (final entry in nflTeams.entries) {
    final words = entry.key.toLowerCase().split(' ');
    if (words.last == nick || entry.key.toLowerCase() == nick) {
      if (found != null && found != entry.value) return null;
      found = entry.value;
    }
  }
  return found;
}

List<List<String>> splitCsv(String text) {
  final rows = <List<String>>[];
  final row = <String>[];
  final cell = StringBuffer();
  var quotes = false;
  final src = text.replaceFirst('\uFEFF', '');
  for (var i = 0; i < src.length; i++) {
    final char = src[i];
    if (quotes) {
      if (char == '"') {
        if (i + 1 < src.length && src[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quotes = false;
        }
      } else {
        cell.write(char);
      }
    } else if (char == '"') {
      quotes = true;
    } else if (char == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (char == '\n') {
      row.add(cell.toString());
      cell.clear();
      if (row.any((part) => part.trim().isNotEmpty)) rows.add(List.of(row));
      row.clear();
    } else if (char != '\r') {
      cell.write(char);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    if (row.any((part) => part.trim().isNotEmpty)) rows.add(List.of(row));
  }
  return rows;
}

class _Effect {
  const _Effect(this.out, this.maybe, this.markets, {required this.offense});
  final String out, maybe;
  final List<String> markets;
  final bool offense;
}

const _pass = ['player_pass_yds', 'player_pass_tds'];
const _rush = ['player_rush_yds', 'player_rush_tds'];
const _catch = [
  'player_reception_yds',
  'player_receptions',
  'player_reception_tds',
];

const _receiver = _Effect(
  'lowers QB passing yards',
  'lower QB passing yards',
  _pass,
  offense: true,
);
const _quarterback = _Effect(
  'changes the passing game and the spread',
  'change the passing game and the spread',
  ['player_pass_yds', 'spreads', 'h2h', 'player_pass_tds', 'player_rush_yds'],
  offense: true,
);
const _runner = _Effect(
  'lowers rushing yards',
  'lower rushing yards',
  _rush,
  offense: true,
);
const _line = _Effect('lowers rushing yards', 'lower rushing yards', [
  'player_rush_yds',
], offense: true);
const _coverage = _Effect(
  'raises opponent receiving yards',
  'raise opponent receiving yards',
  _catch,
  offense: false,
);
const _front = _Effect(
  'raises opponent rushing yards',
  'raise opponent rushing yards',
  ['player_rush_yds'],
  offense: false,
);
const _kicker = _Effect(
  'changes field goals',
  'change field goals',
  [],
  offense: true,
);

_Effect? _effectFor(String position) {
  return switch (position.trim().toUpperCase()) {
    'WR' || 'TE' => _receiver,
    'QB' => _quarterback,
    'RB' || 'FB' || 'HB' => _runner,
    'OL' || 'T' || 'G' || 'C' || 'OT' || 'OG' => _line,
    'CB' || 'S' || 'DB' || 'FS' || 'SS' => _coverage,
    'LB' || 'DE' || 'DT' || 'DL' || 'NT' || 'EDGE' || 'OLB' || 'ILB' => _front,
    'K' => _kicker,
    _ => null,
  };
}

List<InjuryEntry> _dedupe(List<InjuryEntry> entries) {
  final byKey = <String, InjuryEntry>{};
  for (final entry in entries) {
    if (entry.player.isEmpty || entry.team.isEmpty || entry.status.isEmpty) {
      continue;
    }
    final key = injuryKey(entry.team, entry.player);
    final existing = byKey[key];
    if (existing == null ||
        injuryStatusRank(entry.status) < injuryStatusRank(existing.status)) {
      byKey[key] = entry;
    }
  }
  return byKey.values.toList();
}

List<InjuryChange> _changes(
  List<InjuryEntry> current,
  List<InjuryEntry> previous, {
  required bool allowRemovals,
}) {
  if (previous.isEmpty) return const [];
  final prior = {
    for (final entry in previous) injuryKey(entry.team, entry.player): entry,
  };
  final now = {
    for (final entry in current) injuryKey(entry.team, entry.player): entry,
  };
  final changes = <InjuryChange>[];
  for (final entry in current) {
    final key = injuryKey(entry.team, entry.player);
    final before = prior[key];
    if (before == null) {
      if (!entry.outLike) continue;
      changes.add(
        InjuryChange(
          player: entry.player,
          team: entry.team,
          position: entry.position,
          status: entry.status,
          previousStatus: null,
          removed: false,
          summary: '${entry.player} is now listed ${entry.status}.',
          entry: entry,
        ),
      );
    } else if (before.status != entry.status) {
      changes.add(
        InjuryChange(
          player: entry.player,
          team: entry.team,
          position: entry.position,
          status: entry.status,
          previousStatus: before.status,
          removed: false,
          summary:
              '${entry.player} moved from ${before.status} to ${entry.status}.',
          entry: entry,
        ),
      );
    }
  }
  if (allowRemovals) {
    for (final entry in previous) {
      if (!entry.outLike) continue;
      final key = injuryKey(entry.team, entry.player);
      if (now.containsKey(key)) continue;
      changes.add(
        InjuryChange(
          player: entry.player,
          team: entry.team,
          position: entry.position,
          status: 'Not listed',
          previousStatus: entry.status,
          removed: true,
          summary:
              '${entry.player} is no longer listed. The last status was ${entry.status}.',
        ),
      );
    }
  }
  changes.sort((a, b) {
    final removed = (a.removed ? 1 : 0).compareTo(b.removed ? 1 : 0);
    if (removed != 0) return removed;
    final status = injuryStatusRank(a.status)
        .compareTo(injuryStatusRank(b.status));
    if (status != 0) return status;
    return a.player.compareTo(b.player);
  });
  return changes;
}

String _notice({
  required bool live,
  required List<SourceNote> sources,
  required bool partial,
  int? storedWeek,
  int? previousWeek,
}) {
  if (!live) {
    final week = storedWeek == null ? 'the stored file' : 'week $storedWeek';
    final compared = previousWeek == null
        ? ''
        : ' Changes are against week $previousWeek.';
    final thin = partial
        ? ' This week\'s stored list is short, so players who are missing are not marked as back.'
        : '';
    return 'Stored nflverse report for $week. It is not a live check. '
        'Connect the local backend for ESPN and the NFL.com report.$compared$thin';
  }
  final problems = [
    for (final source in sources)
      if (!source.ok && source.problem != null) source.problem!,
  ];
  final thin = partial
      ? ' This check has far fewer names than the last one, so missing players are not marked as back.'
      : '';
  final failed = problems.isEmpty ? '' : ' ${problems.join(' ')}';
  return 'ESPN is unofficial and updates first. NFL.com is the league report. '
      'nflverse is the backup.$failed$thin';
}

String _espnTeam(Map athlete, Map team) {
  final nested = athlete['team'];
  if (nested is Map) {
    final code = canonicalInjuryTeam('${nested['abbreviation'] ?? ''}');
    if (code.isNotEmpty && code.length <= 3) return code;
    final named = teamFromLabel('${nested['displayName'] ?? ''}');
    if (named != null) return named;
  }
  return teamFromLabel('${team['displayName'] ?? ''}') ?? '';
}

String _espnPosition(Map athlete) {
  final position = athlete['position'];
  if (position is Map) {
    final code = '${position['abbreviation'] ?? ''}'.trim();
    if (code.isNotEmpty) return code.toUpperCase();
  }
  return '';
}

String _espnInjury(Map row) {
  final details = row['details'];
  if (details is Map) {
    final type = '${details['type'] ?? ''}'.trim();
    if (type.isNotEmpty) return type;
  }
  return '';
}

List<InjuryEntry> _nflRows(
  String html,
  String team,
  int? week,
  DateTime fetchedAt,
) {
  final found = <InjuryEntry>[];
  final rows = RegExp(
    r'<tr\b[^>]*>(.*?)</tr>',
    caseSensitive: false,
    dotAll: true,
  ).allMatches(html);
  for (final row in rows) {
    final cells = [
      for (final cell in RegExp(
        r'<td\b[^>]*>(.*?)</td>',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(row.group(1) ?? ''))
        _plain(cell.group(1) ?? ''),
    ];
    if (cells.length < 5) continue;
    if (cells.first.toLowerCase() == 'player') continue;
    final status = normalizeInjuryStatus(cells[4]);
    if (status == null) continue;
    if (cells.first.isEmpty) continue;
    found.add(
      InjuryEntry(
        player: cells.first,
        team: team,
        position: cells[1].toUpperCase(),
        status: status,
        injury: cells[2],
        sourceId: 'nfl',
        sourceLabel: 'NFL.com',
        official: true,
        fetchedAt: fetchedAt.toUtc(),
        week: week,
      ),
    );
  }
  return found;
}

String _plain(String raw) => raw
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _cell(List<String> row, int index) =>
    index >= 0 && index < row.length ? row[index].trim() : '';
