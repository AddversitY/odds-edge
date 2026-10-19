import 'dart:convert';
import 'dart:math' as math;

double americanToDecimal(num odds) {
  if (!odds.isFinite || odds.abs() < 100) {
    throw ArgumentError('American odds must be at least +100 or at most -100.');
  }
  return odds > 0 ? 1 + odds / 100 : 1 + 100 / odds.abs();
}

double impliedProbability(double decimal) {
  if (!decimal.isFinite || decimal <= 1) throw ArgumentError('Invalid odds');
  return 1 / decimal;
}

String americanLabel(double decimal) {
  impliedProbability(decimal);
  final value = decimal >= 2 ? (decimal - 1) * 100 : -100 / (decimal - 1);
  return '${value >= 0 ? '+' : ''}${value.round()}';
}

double expectedValue(double decimal, double win, {double push = 0}) {
  impliedProbability(decimal);
  if (!win.isFinite ||
      !push.isFinite ||
      win < 0 ||
      push < 0 ||
      win + push > 1) {
    throw ArgumentError('Win and push probabilities must sum to at most 1.');
  }
  return win * (decimal - 1) - (1 - win - push);
}

class Selection {
  const Selection({
    required this.eventId,
    required this.market,
    required this.outcome,
    this.participant = '',
    this.point,
    this.period = 'full_game',
    this.rules = 'includes_overtime_push_on_tie',
  });
  final String eventId, market, outcome, participant, period, rules;
  final double? point;
  // Structured encoding avoids delimiter collisions. A threshold is part of identity.
  String get key => jsonEncode([
    eventId,
    market,
    period,
    participant,
    outcome,
    point == 0 ? 0.0 : point,
    rules,
  ]);
  String get label {
    final line = point == null
        ? ''
        : ' ${point! > 0 && market == 'spreads' ? '+' : ''}${point!.toStringAsFixed(1)}';
    return '${participant.isEmpty ? '' : '$participant · '}$outcome$line';
  }

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'market': market,
    'outcome': outcome,
    'participant': participant,
    'point': point,
    'period': period,
    'rules': rules,
  };
  factory Selection.fromJson(Map<String, dynamic> j) => Selection(
    eventId: j['eventId'],
    market: j['market'],
    outcome: j['outcome'],
    participant: j['participant'] ?? '',
    point: (j['point'] as num?)?.toDouble(),
    period: j['period'],
    rules: j['rules'],
  );
}

class SportEvent {
  const SportEvent(
    this.id,
    this.away,
    this.home,
    this.startsAt, {
    this.sport = 'american_football',
    this.league = 'NFL',
  });
  final String id, away, home;
  final String sport, league;
  final DateTime startsAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'away': away,
    'home': home,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'sport': sport,
    'league': league,
  };
  factory SportEvent.fromJson(Map<String, dynamic> j) => SportEvent(
    j['id'],
    j['away'],
    j['home'],
    DateTime.parse(j['startsAt']),
    sport: j['sport'] ?? 'american_football',
    league: j['league'] ?? 'NFL',
  );
}

// Compatibility for existing NFL adapters and version-one stored boards.
typedef NflEvent = SportEvent;

class OddsQuote {
  OddsQuote({
    required this.selection,
    required this.bookId,
    required this.book,
    required this.provider,
    required this.decimal,
    required this.sourceAt,
    required this.collectedAt,
    this.status = 'open',
    this.demo = false,
  }) {
    impliedProbability(decimal);
    if (selection.point != null && !selection.point!.isFinite) {
      throw ArgumentError('Invalid threshold');
    }
  }
  final Selection selection;
  final String bookId, book, provider, status;
  final double decimal;
  final DateTime sourceAt, collectedAt;
  final bool demo;
  String freshness(DateTime now, {bool inPlay = false}) {
    if (status != 'open') return status;
    if (sourceAt.isAfter(now.add(const Duration(seconds: 5))) ||
        collectedAt.isAfter(now.add(const Duration(seconds: 5)))) {
      return 'unverified';
    }
    final ttl = Duration(seconds: inPlay ? 20 : 120);
    if (now.difference(sourceAt) > ttl || now.difference(collectedAt) > ttl) {
      return 'stale';
    }
    return demo ? 'demo' : 'current';
  }

  bool eligible(DateTime now, {bool inPlay = false}) =>
      const ['current', 'demo'].contains(freshness(now, inPlay: inPlay));
  Map<String, dynamic> toJson() => {
    'selection': selection.toJson(),
    'bookId': bookId,
    'book': book,
    'provider': provider,
    'decimal': decimal,
    'sourceAt': sourceAt.toUtc().toIso8601String(),
    'collectedAt': collectedAt.toUtc().toIso8601String(),
    'status': status,
    'demo': demo,
  };
  factory OddsQuote.fromJson(Map<String, dynamic> j) => OddsQuote(
    selection: Selection.fromJson(j['selection']),
    bookId: j['bookId'],
    book: j['book'],
    provider: j['provider'],
    decimal: (j['decimal'] as num).toDouble(),
    sourceAt: DateTime.parse(j['sourceAt']),
    collectedAt: DateTime.parse(j['collectedAt']),
    status: j['status'],
    demo: j['demo'] ?? false,
  );
}

// Latest source observation wins; never cherry-pick an older, more profitable quote.
List<OddsQuote> deduplicateQuotes(Iterable<OddsQuote> quotes) {
  final latest = <String, OddsQuote>{};
  for (final q in quotes) {
    final key = jsonEncode([q.bookId, q.selection.key]);
    final previous = latest[key];
    if (previous == null ||
        q.sourceAt.isAfter(previous.sourceAt) ||
        (q.sourceAt == previous.sourceAt &&
            q.collectedAt.isAfter(previous.collectedAt))) {
      latest[key] = q;
    }
  }
  return latest.values.toList();
}

List<OddsQuote> comparableQuotes(
  Iterable<OddsQuote> quotes,
  Selection selection, {
  Set<String>? books,
}) => deduplicateQuotes(
  quotes.where(
    (q) =>
        q.selection.key == selection.key &&
        (books == null || books.contains(q.bookId)),
  ),
);

OddsQuote? bestQuote(
  Iterable<OddsQuote> quotes,
  Selection selection,
  DateTime now, {
  Set<String>? books,
  bool inPlay = false,
}) {
  final eligible =
      comparableQuotes(
          quotes,
          selection,
          books: books,
        ).where((q) => q.eligible(now, inPlay: inPlay)).toList()
        ..sort((a, b) => b.decimal.compareTo(a.decimal));
  return eligible.isEmpty ? null : eligible.first;
}

class OddsBoard {
  const OddsBoard({
    required this.events,
    required this.quotes,
    required this.fetchedAt,
    this.demo = false,
    this.notices = const [],
  });
  final List<NflEvent> events;
  final List<OddsQuote> quotes;
  final DateTime fetchedAt;
  final bool demo;
  final List<String> notices;
  Map<String, dynamic> toJson() => {
    'events': events.map((e) => e.toJson()).toList(),
    'quotes': quotes.map((q) => q.toJson()).toList(),
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'demo': demo,
    'notices': notices,
  };
  factory OddsBoard.fromJson(Map<String, dynamic> j) => OddsBoard(
    events: (j['events'] as List).map((e) => NflEvent.fromJson(e)).toList(),
    quotes: (j['quotes'] as List).map((q) => OddsQuote.fromJson(q)).toList(),
    fetchedAt: DateTime.parse(j['fetchedAt']),
    demo: j['demo'],
    notices: List<String>.from(j['notices'] ?? []),
  );
}

double priceSpread(Iterable<OddsQuote> quotes) {
  final values = quotes.map((q) => q.decimal).toList();
  return values.length < 2
      ? 0
      : values.reduce(math.max) - values.reduce(math.min);
}
