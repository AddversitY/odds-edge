import '../domain/coach_board.dart';
import '../domain/eastern.dart';
import '../domain/coach_model.dart';
import '../domain/edge_gap.dart';
import '../domain/history.dart';
import '../domain/hit_rate.dart';
import '../domain/matchup.dart';
import '../domain/nfl_teams.dart';
import '../domain/odds.dart';
import '../domain/parlay_value.dart';
import '../domain/injury_report.dart';
import '../domain/prop_chance.dart';
import '../domain/prop_history.dart';
import '../domain/prop_model.dart';
import '../domain/prop_projection.dart';
import '../domain/prop_value.dart';
import '../domain/value_check.dart';

/// How the one-line matchup reads. Rank 1 allows the least.
enum MatchupTone { favorable, tough, even }

class MatchupNote {
  const MatchupNote(this.text, this.tone);
  final String text;
  final MatchupTone tone;
}

/// One prop, priced and annotated for the feed and the detail screen.
class ShownProp {
  const ShownProp({
    required this.card,
    required this.cards,
    required this.windows,
    required this.value,
    required this.opponent,
    required this.teamSpread,
    required this.total,
    required this.badge,
    required this.note,
    required this.pairedBook,
    this.projection,
    this.usingProjection = false,
  });

  final PropCardModel card;
  final List<PropCardModel> cards;
  final PropWindows? windows;
  final PropValue value;
  final String? opponent;
  final double? teamSpread;
  final double? total;
  final InjuryBadge? badge;
  final MatchupNote? note;

  /// True when the no-vig chance came from this book's other side,
  /// rather than the average of every book.
  final bool pairedBook;

  /// The usage projection, even when the card still uses the record.
  final PropProjection? projection;

  /// True when [projection] is the chance in [verdict].
  final bool usingProjection;

  ValueVerdict get verdict => value.verdict;

  double? get edge => edgePoints(verdict.ourChance, verdict.fairChance);

  String get bookChanceLabel => pairedBook ? "Book's no-vig" : "Books' no-vig";
}

ShownProp showProp({
  required PropCardModel card,
  required List<PropCardModel> cards,
  required PlayerDirectory? directory,
  required MatchupContext? context,
  required OddsBoard board,
  required DateTime now,
  InjuryReport? injuries,
  List<HistoricalGame> scores = const [],
}) {
  final windows = directory == null ? null : propWindows(directory, card, now);
  final opponent = opponentFor(card, windows);
  final spread = teamSpreadFor(card, windows, board);
  final total = card.event == null
      ? null
      : readMarketLine(card.event!, board.quotes).total;
  final quote = card.best;
  final paired = quote == null
      ? null
      : otherDecimalAtBook(card, cards, quote.bookId);
  final rows = directory?.data.rows;
  final index = rows == null
      ? null
      : usageIndexFor(rows, matchup: context);
  final calibrator = propLiveChance == PropLiveChance.calibrated && rows != null
      ? cachedPropComparison(rows, scores: scores, matchup: context).calibrator
      : null;
  final outs = _teammateOuts(injuries, windows?.team, card.player);
  PropProjection? project(PropCardModel item, double? market) {
    final metric = propStatMetrics[item.market];
    final players = directory;
    final usage = index;
    if (metric == null || players == null || usage == null) return null;
    final looked = item.id == card.id
        ? windows
        : propWindows(players, item, now);
    final id = looked?.playerId;
    if (id == null) return null;
    return projectProp(
      index: usage,
      playerId: id,
      metric: metric,
      line: item.line,
      side: item.lineSide,
      beforeSeason: 10000,
      beforeWeek: 1,
      team: looked?.team,
      opponent: item.id == card.id ? opponent : opponentFor(item, looked),
      teamSpread: item.id == card.id
          ? spread
          : teamSpreadFor(item, looked, board),
      total: item.event == null
          ? null
          : readMarketLine(item.event!, board.quotes).total,
      market: market,
      teammateOuts: item.id == card.id
          ? outs
          : _teammateOuts(injuries, looked?.team, item.player),
      calibrator: calibrator,
    );
  }

  final shownProjection = project(card, propMarketAnchor(card, cards));
  final value = priceProp(
    card: card,
    cards: cards,
    rateFor: (item) {
      if (directory == null) {
        return item.id == card.id ? preferredRate(windows) : null;
      }
      return preferredRate(propWindows(directory, item, now));
    },
    context: context,
    rows: directory?.data.rows ?? const [],
    playerTeam: windows?.team,
    position: windows?.position,
    opponent: opponent,
    teamSpread: spread,
    total: total,
    seasonYear: windows?.seasonYear,
    recent: windows?.last5,
    projectedChance: propV2Adopted
        ? (item, rate, market) => project(item, market)?.chance
        : null,
  );
  return ShownProp(
    card: card,
    cards: cards,
    windows: windows,
    value: value,
    opponent: opponent,
    teamSpread: spread,
    total: total,
    badge: badgeForProp(
      injuries,
      market: card.market,
      playerName: card.player,
      playerTeam: windows?.team,
      opponent: opponent,
    ),
    note: matchupNote(
      defense: value.matchup?.defense,
      position: windows?.position,
      side: card.lineSide,
    ),
    pairedBook: paired != null && value.verdict.fairChance != null,
    projection: shownProjection,
    usingProjection:
        propV2Adopted && shownProjection?.chance != null,
  );
}

List<({String name, String position})> _teammateOuts(
  InjuryReport? injuries,
  String? team,
  String player,
) {
  if (injuries == null || team == null || team.isEmpty) return const [];
  final club = boxScoreTeam(team);
  final self = normalizePropName(player);
  return [
    for (final entry in injuries.entries)
      if (entry.outLike &&
          boxScoreTeam(entry.team) == club &&
          normalizePropName(entry.player) != self)
        (name: entry.player, position: entry.position),
  ];
}

List<ShownProp> showProps({
  required List<PropCardModel> cards,
  required PlayerDirectory? directory,
  required MatchupContext? context,
  required OddsBoard board,
  required DateTime now,
  InjuryReport? injuries,
  List<HistoricalGame> scores = const [],
}) {
  return [
    for (final card in cards)
      showProp(
        card: card,
        cards: cards,
        directory: directory,
        context: context,
        board: board,
        now: now,
        injuries: injuries,
        scores: scores,
      ),
  ];
}

/// One card per player, market, and line. The side with the larger gap
/// between our chance and the book's no-vig is the one on the card.
/// A tie, or two missing chances, keeps the over. The other side stays
/// on [ShownProp.cards] so the detail can switch to it.
List<ShownProp> preferredPropSides(List<ShownProp> shown) {
  final best = <String, ShownProp>{};
  final order = <String>[];
  for (final prop in shown) {
    final key = _sideGroup(prop.card);
    final current = best[key];
    if (current == null) {
      best[key] = prop;
      order.add(key);
    } else {
      best[key] = _betterSide(current, prop);
    }
  }
  return [for (final key in order) best[key]!];
}

String _sideGroup(PropCardModel card) {
  final event = card.event?.id ?? card.side.eventId;
  return '$event|${card.player}|${card.market}|${card.line}';
}

ShownProp _betterSide(ShownProp a, ShownProp b) {
  final left = a.edge;
  final right = b.edge;
  if (left == null && right == null) return _overOrFirst(a, b);
  if (left == null) return b;
  if (right == null) return a;
  if ((left - right).abs() < 1e-6) return _overOrFirst(a, b);
  return left > right ? a : b;
}

ShownProp _overOrFirst(ShownProp a, ShownProp b) {
  if (a.card.lineSide == LineSide.over) return a;
  if (b.card.lineSide == LineSide.over) return b;
  return a;
}

/// A slip leg judged with the same chance the prop card used.
TicketLegInput ticketLegFor(ShownProp shown) {
  final card = shown.card;
  final quote = card.best;
  if (quote == null) {
    throw ArgumentError('${card.player} has no open price to add.');
  }
  final rate = preferredRate(shown.windows);
  return TicketLegInput(
    label: '${card.player} ${card.lineLabel}',
    eventId: card.event?.id ?? card.side.eventId,
    market: card.market,
    outcome: card.side.outcome,
    player: card.player,
    team: shown.windows?.team ?? '',
    point: card.line,
    decimal: quote.decimal,
    ourChance: shown.verdict.ourChance,
    otherDecimal: otherDecimalAtBook(card, shown.cards, quote.bookId),
    consensusFair: card.fairProbability,
    source: shown.usingProjection
        ? propProjectionSource
        : rate == null
        ? 'the recorded games'
        : shown.verdict.fairChance == null
        ? propEvenSource
        : propChanceSource,
    hits: rate?.hits,
    observed: rate?.observed,
  );
}

double? otherDecimalAtBook(
  PropCardModel card,
  List<PropCardModel> cards,
  String bookId,
) {
  final otherKey = card.otherSide?.key;
  if (otherKey == null) return null;
  for (final item in cards) {
    if (item.side.key != otherKey) continue;
    for (final row in item.bookRows) {
      if (row.quote.bookId == bookId) return row.quote.decimal;
    }
  }
  return null;
}

PropWindows propWindows(
  PlayerDirectory directory,
  PropCardModel card,
  DateTime now,
) {
  final event = card.event;
  String? opponent;
  if (event != null) {
    final away = canonicalTeam(event.away);
    final home = canonicalTeam(event.home);
    final looked = directory.lookup(
      playerName: card.player,
      market: card.market,
      line: card.line,
      side: card.lineSide,
    );
    final team = looked.team;
    if (team != null && boxScoreTeam(team) == boxScoreTeam(away ?? '')) {
      opponent = home;
    } else if (team != null && boxScoreTeam(team) == boxScoreTeam(home ?? '')) {
      opponent = away;
    }
  }
  return directory.lookup(
    playerName: card.player,
    market: card.market,
    line: card.line,
    side: card.lineSide,
    opponent: opponent,
    through: now,
  );
}

String? opponentFor(PropCardModel card, PropWindows? windows) {
  final event = card.event;
  final team = windows?.team;
  if (event == null || team == null) return null;
  final away = canonicalTeam(event.away);
  final home = canonicalTeam(event.home);
  final club = boxScoreTeam(team);
  if (club == boxScoreTeam(away ?? '')) return home;
  if (club == boxScoreTeam(home ?? '')) return away;
  return null;
}

double? teamSpreadFor(
  PropCardModel card,
  PropWindows? windows,
  OddsBoard board,
) {
  final event = card.event;
  final team = windows?.team;
  if (event == null || team == null) return null;
  final home = readMarketLine(event, board.quotes).homeSpread;
  if (home == null) return null;
  final club = boxScoreTeam(team);
  if (club == boxScoreTeam(canonicalTeam(event.home) ?? '')) return home;
  if (club == boxScoreTeam(canonicalTeam(event.away) ?? '')) return -home;
  return null;
}

MatchupNote? matchupNote({
  required DefenseAllow? defense,
  required String? position,
  required LineSide side,
}) {
  if (defense == null || defense.teams < 2) return null;
  final pos = (position == null || position.trim().isEmpty)
      ? defense.statLabel
      : position.trim();
  final band = defenseBand(defense.rank, defense.teams);
  final tone = matchupTone(band, side);
  final phrase = matchupPhrase(band, side);
  return MatchupNote(
    '${clubNickname(defense.team)} ${ordinal(defense.rank)} vs $pos · $phrase',
    tone,
  );
}

/// Rank 1 allows the least. On a 32-team board, 1–10 is a tough front,
/// 11–22 is even, and 23–32 is a soft front.
enum DefenseBand { tough, even, soft }

DefenseBand defenseBand(int rank, int teams) {
  final size = teams < 2 ? 2 : teams;
  final toughMax = (size * 10 / 32).round().clamp(1, size);
  final softMin = (size * 23 / 32).round().clamp(1, size);
  if (rank <= toughMax) return DefenseBand.tough;
  if (rank >= softMin) return DefenseBand.soft;
  return DefenseBand.even;
}

/// The rank describes the defense. The side of the bet flips it:
/// an under against a soft front is a hard matchup for that bet.
MatchupTone matchupTone(DefenseBand band, LineSide side) {
  if (band == DefenseBand.even) return MatchupTone.even;
  final helpsOver = band == DefenseBand.soft;
  final helpsSide = side == LineSide.over ? helpsOver : !helpsOver;
  return helpsSide ? MatchupTone.favorable : MatchupTone.tough;
}

String matchupPhrase(DefenseBand band, LineSide side) {
  return switch ((band, side)) {
    (DefenseBand.even, _) => 'an even matchup',
    (DefenseBand.tough, LineSide.over) => 'a tough front for the over',
    (DefenseBand.tough, LineSide.under) =>
      'a tough front, which helps the under',
    (DefenseBand.soft, LineSide.over) => 'a soft front for the over',
    (DefenseBand.soft, LineSide.under) =>
      'a soft front, which works against the under',
  };
}

String ordinal(int number) {
  final mod100 = number.abs() % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${number}th';
  return switch (number.abs() % 10) {
    1 => '${number}st',
    2 => '${number}nd',
    3 => '${number}rd',
    _ => '${number}th',
  };
}

String shortPropLine(PropCardModel card) {
  final side = card.lineSide == LineSide.over ? 'Over' : 'Under';
  final number = card.line.toStringAsFixed(1);
  final stat = switch (card.market) {
    'player_pass_yds' => 'pass yards',
    'player_pass_tds' => 'pass TD',
    'player_rush_yds' => 'rush yards',
    'player_rush_tds' => 'rush TD',
    'player_receptions' => 'receptions',
    'player_reception_yds' => 'rec. yards',
    'player_reception_tds' => 'rec. TD',
    _ => card.marketLabel.toLowerCase(),
  };
  return '$side $number $stat';
}

String priceBlurb(PropCardModel card) {
  final best = card.best;
  if (best == null || card.bookRows.isEmpty) return 'No open price';
  final count = card.bookRows.length;
  if (count == 1) return best.book;
  final tied = card.bookRows
      .where((row) => (row.quote.decimal - best.decimal).abs() < 0.0001)
      .length;
  if (tied > 1) return '${best.book} · tied best';
  return '${best.book} · best of $count';
}

String playerInitials(String name) {
  final parts = name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  String letter(String word) {
    final runes = word.runes;
    if (runes.isEmpty) return '';
    return String.fromCharCode(runes.first).toUpperCase();
  }

  if (parts.length == 1) return letter(parts.first);
  return '${letter(parts.first)}${letter(parts.last)}';
}

/// "BUF at KC · Sun Nov 15 · 1:00 PM". Missing pieces are left out.
String propMeta(ShownProp shown) {
  final windows = shown.windows;
  final event = shown.card.event;
  final bits = <String>[];
  final position = windows?.position ?? '';
  if (position.isNotEmpty) bits.add(position);
  if (event != null) {
    final away = canonicalTeam(event.away) ?? event.away;
    final home = canonicalTeam(event.home) ?? event.home;
    final team = windows?.team;
    if (team != null && team.isNotEmpty) {
      final club = boxScoreTeam(team);
      if (club == boxScoreTeam(away)) {
        bits.add('$away at $home');
      } else if (club == boxScoreTeam(home)) {
        bits.add('$home vs $away');
      } else {
        bits.add('$away at $home');
      }
    } else {
      bits.add('$away at $home');
    }
    bits.add(kickoffLabel(event.startsAt));
  }
  return bits.join(' · ');
}

String kickoffLabel(DateTime instant) => formatEastern(instant);

String slateTitle(Iterable<DateTime> kickoffs) {
  DateTime? earliest;
  for (final kick in kickoffs) {
    if (earliest == null || kick.isBefore(earliest)) earliest = kick;
  }
  if (earliest == null) return "Today's best prices";
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return "${days[easternWall(earliest).weekday - 1]}'s best prices";
}

String slateDate(Iterable<DateTime> kickoffs) {
  DateTime? earliest;
  for (final kick in kickoffs) {
    if (earliest == null || kick.isBefore(earliest)) earliest = kick;
  }
  if (earliest == null) return 'NFL';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final wall = easternWall(earliest);
  return '${months[wall.month - 1]} ${wall.day} · NFL';
}

int compareByEdge(ShownProp a, ShownProp b) {
  final left = a.edge;
  final right = b.edge;
  if (left == null && right != null) return 1;
  if (left != null && right == null) return -1;
  if (left != null && right != null && left != right) {
    return right.compareTo(left);
  }
  final player = a.card.player.compareTo(b.card.player);
  if (player != 0) return player;
  return a.card.lineLabel.compareTo(b.card.lineLabel);
}

int compareByRecent(ShownProp a, ShownProp b) {
  double? rate(ShownProp prop) =>
      prop.windows?.last5?.clearRate ?? prop.windows?.last10?.clearRate;
  final left = rate(a);
  final right = rate(b);
  if (left == null && right != null) return 1;
  if (left != null && right == null) return -1;
  if (left != null && right != null && left != right) {
    return right.compareTo(left);
  }
  return compareByEdge(a, b);
}

String hitCount(HitRate? rate) {
  if (rate == null || rate.observed == 0) return '—';
  return '${rate.hits}/${rate.observed}';
}
