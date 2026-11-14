import 'bets.dart';
import 'hit_rate.dart';
import 'market_math.dart';
import 'odds.dart';
import 'prop_history.dart';

/// How old a saved price is, in plain language. Never rounds a missing time
/// into "live".
String priceAge(DateTime source, DateTime now) {
  final age = now.difference(source);
  if (age.isNegative) {
    return 'The price time is after the clock, so it is not used as current.';
  }
  if (age.inMinutes < 1) return 'Under a minute old';
  if (age.inMinutes < 60) {
    final minutes = age.inMinutes;
    return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} old';
  }
  if (age.inHours < 48) {
    final hours = age.inHours;
    return '$hours ${hours == 1 ? 'hour' : 'hours'} old';
  }
  final days = age.inDays;
  return '$days ${days == 1 ? 'day' : 'days'} old';
}

String signedPercent(double value) {
  final points = value * 100;
  final text = points.abs().toStringAsFixed(1);
  if (points > 0) return '+$text%';
  if (points < 0) return '-$text%';
  return '0.0%';
}

String percentLabel(double value) => '${(value * 100).toStringAsFixed(1)}%';

const feeFreeChanceExplanation =
    'Each sportsbook that posted both sides has its fee removed in proportion to the two prices. '
    'Those fee-free chances are then averaged. This is the books agreeing with each other after the fee, '
    'not a model and not a prediction that the side will hit.';

const expectedProfitExplanation =
    'Expected profit per \$1 staked if the fee-free chance above were exactly right. '
    'Positive means this price pays more than that chance. '
    'It is a comparison with the other prices in the snapshot, not a tip.';

const impliedChanceExplanation =
    'The break-even rate of this one price, before any fee is removed. '
    'A -110 price needs to hit about 52.4% of the time to break even.';

const historyGapExplanation =
    'Season clear rate minus the books\' fee-free chance. '
    'Positive means the recorded regular-season games cleared more often than that chance. '
    'Missing stats are skipped. This is not a prediction, and last season is not filled in when this season is empty.';

const bestPriceExplanation =
    'The highest open price for this side in the snapshot. '
    'A higher American number, or a shorter favorite, is a better payout. '
    'It may be a sample price or hours old. Read the age before you treat it as offered.';

class BookPriceRow {
  const BookPriceRow({required this.quote, required this.expectedProfit});

  final OddsQuote quote;
  final double? expectedProfit;
}

class PropCardModel {
  const PropCardModel({
    required this.side,
    required this.otherSide,
    required this.event,
    required this.player,
    required this.market,
    required this.marketLabel,
    required this.line,
    required this.lineSide,
    required this.best,
    required this.implied,
    required this.fairProbability,
    required this.expectedProfit,
    required this.bookRows,
    required this.rulesUnverified,
    required this.demo,
  });

  final Selection side;
  final Selection? otherSide;
  final SportEvent? event;
  final String player, market, marketLabel;
  final double line;
  final LineSide lineSide;
  final OddsQuote? best;
  final double? implied, fairProbability, expectedProfit;
  final List<BookPriceRow> bookRows;
  final bool rulesUnverified, demo;

  String get id => side.key;

  String get lineLabel {
    final number = line.toStringAsFixed(1);
    final sideName = lineSide == LineSide.over ? 'Over' : 'Under';
    return '$sideName $number';
  }
}

class PropFilter {
  const PropFilter({
    this.market,
    this.bookId,
    this.minAmerican,
    this.maxAmerican,
    this.minFair,
    this.onlyLongerThanTheBooks = false,
    this.sort = PropSort.expectedProfit,
  });

  final String? market;
  final String? bookId;
  final int? minAmerican, maxAmerican;

  /// Keep cards whose fee-free chance is at least this. Null means no cutoff.
  final double? minFair;
  final bool onlyLongerThanTheBooks;
  final PropSort sort;
}

enum PropSort { expectedProfit, historyGap, price, line }

Map<String, dynamic> propFilterJson(PropFilter filter) => {
  'market': filter.market,
  'bookId': filter.bookId,
  'minAmerican': filter.minAmerican,
  'maxAmerican': filter.maxAmerican,
  'minFair': filter.minFair,
  'onlyLongerThanTheBooks': filter.onlyLongerThanTheBooks,
  'sort': filter.sort.name,
};

PropFilter propFilterFromJson(Map<String, dynamic> json) {
  String? text(String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid $key');
    }
    return value;
  }

  int? price(String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! int || value.abs() < 100) {
      throw FormatException('Invalid $key');
    }
    return value;
  }

  final min = price('minAmerican'), max = price('maxAmerican');
  if (min != null && max != null && min > max) {
    throw const FormatException('Reversed odds range');
  }
  final fair = json['minFair'];
  if (fair != null &&
      (fair is! num || !fair.isFinite || fair < 0 || fair > 1)) {
    throw const FormatException('Invalid market chance');
  }
  if (json['onlyLongerThanTheBooks'] is! bool || json['sort'] is! String) {
    throw const FormatException('Invalid prop preferences');
  }
  final market = text('market');
  if (market != null && !propMarketLabels.containsKey(market)) {
    throw const FormatException('Unsupported saved stat');
  }
  return PropFilter(
    market: market,
    bookId: text('bookId'),
    minAmerican: min,
    maxAmerican: max,
    minFair: (fair as num?)?.toDouble(),
    onlyLongerThanTheBooks: json['onlyLongerThanTheBooks'],
    sort: PropSort.values.byName(json['sort']),
  );
}

List<PropCardModel> propCards(
  OddsBoard board,
  DateTime now, {
  Set<String>? books,
}) {
  final scan = scanMarkets(board, now, books: books);
  final events = {for (final event in board.events) event.id: event};
  final cards = <PropCardModel>[];
  for (final market in scan.markets) {
    if (!market.market.startsWith('player_')) continue;
    if (!propMarketLabels.containsKey(market.market)) continue;
    for (var i = 0; i < market.sides.length; i++) {
      final side = market.sides[i];
      if (side.selection.outcome != 'Over' &&
          side.selection.outcome != 'Under') {
        continue;
      }
      final point = side.selection.point;
      if (point == null) continue;
      Selection? other;
      if (market.sides.length == 2) {
        other = market.sides[1 - i].selection;
      }
      final ladder = bookLadder(
        board,
        side.selection,
        now,
        books: books,
        fairProbability: side.fairProbability,
      );
      cards.add(
        PropCardModel(
          side: side.selection,
          otherSide: other,
          event: events[market.eventId],
          player: side.selection.participant,
          market: market.market,
          marketLabel: propMarketLabels[market.market] ?? market.detail,
          line: point,
          lineSide: side.selection.outcome == 'Over'
              ? LineSide.over
              : LineSide.under,
          best: side.best,
          implied: side.best == null
              ? null
              : impliedProbability(side.best!.decimal),
          fairProbability: side.fairProbability,
          expectedProfit: side.marketEv,
          bookRows: ladder,
          rulesUnverified: market.rulesUnverified,
          demo: side.best?.demo ?? board.demo,
        ),
      );
    }
  }
  cards.sort((a, b) {
    final player = a.player.compareTo(b.player);
    if (player != 0) return player;
    return a.lineLabel.compareTo(b.lineLabel);
  });
  return cards;
}

List<PropCardModel> applyPropFilter(
  List<PropCardModel> cards,
  PropFilter filter, {
  Map<String, double?> historyGaps = const {},
}) {
  final kept = <PropCardModel>[];
  for (final card in cards) {
    if (filter.market != null && card.market != filter.market) continue;
    if (filter.bookId != null &&
        card.bookRows.every((row) => row.quote.bookId != filter.bookId)) {
      continue;
    }
    final price = card.best?.decimal;
    if (filter.minAmerican != null || filter.maxAmerican != null) {
      if (price == null) continue;
      final american = _americanValue(price);
      if (filter.minAmerican != null && american < filter.minAmerican!) {
        continue;
      }
      if (filter.maxAmerican != null && american > filter.maxAmerican!) {
        continue;
      }
    }
    if (filter.minFair != null) {
      final fair = card.fairProbability;
      if (fair == null || fair < filter.minFair!) continue;
    }
    if (filter.onlyLongerThanTheBooks &&
        (card.expectedProfit == null || card.expectedProfit! <= 0)) {
      continue;
    }
    kept.add(card);
  }
  kept.sort((a, b) => _compareProps(a, b, filter.sort, historyGaps));
  return kept;
}

int _compareProps(
  PropCardModel a,
  PropCardModel b,
  PropSort sort,
  Map<String, double?> gaps,
) {
  double? primary(PropCardModel card) => switch (sort) {
    PropSort.expectedProfit => card.expectedProfit,
    PropSort.historyGap => gaps[card.id],
    PropSort.price => card.best?.decimal,
    PropSort.line => card.line,
  };
  final left = primary(a);
  final right = primary(b);
  if (left == null && right != null) return 1;
  if (left != null && right == null) return -1;
  if (left != null && right != null && left != right) {
    return right.compareTo(left);
  }
  final player = a.player.compareTo(b.player);
  return player != 0 ? player : a.lineLabel.compareTo(b.lineLabel);
}

double _americanValue(double decimal) {
  impliedProbability(decimal);
  return decimal >= 2 ? (decimal - 1) * 100 : -100 / (decimal - 1);
}

List<BookPriceRow> bookLadder(
  OddsBoard board,
  Selection selection,
  DateTime now, {
  Set<String>? books,
  double? fairProbability,
}) {
  final quotes = usableSnapshotQuotes(
    board.quotes,
    now,
    books: books,
    events: board.events,
    fetchedAt: board.fetchedAt,
  ).where((quote) => quote.selection.key == selection.key).toList();
  quotes.sort((a, b) {
    final price = b.decimal.compareTo(a.decimal);
    if (price != 0) return price;
    return a.book.compareTo(b.book);
  });
  return [
    for (final quote in quotes)
      BookPriceRow(
        quote: quote,
        expectedProfit: fairProbability == null
            ? null
            : expectedValue(quote.decimal, fairProbability),
      ),
  ];
}

class GameSummary {
  const GameSummary({
    required this.event,
    required this.positiveEvMarkets,
    required this.arbitrageCount,
    required this.parlayCount,
    required this.awayChance,
    required this.homeChance,
    required this.booksInMoneyline,
    required this.markets,
  });

  final SportEvent event;
  final int positiveEvMarkets, arbitrageCount, parlayCount;
  final double? awayChance, homeChance;
  final int booksInMoneyline;
  final List<PricedMarket> markets;

  String get chanceExplanation => awayChance == null || homeChance == null
      ? 'Both teams need a price from the same books before a fee-free chance can be shown.'
      : 'Fee-free chance the books\' moneylines imply after the fee is removed and the books are averaged. '
            '$booksInMoneyline ${booksInMoneyline == 1 ? 'book posted' : 'books posted'} both sides. '
            'This is not a prediction that either team wins.';
}

class SlateSummary {
  const SlateSummary({
    required this.games,
    required this.parlays,
    required this.scan,
    required this.topPlays,
  });

  final List<GameSummary> games;
  final List<ParlaySuggestion> parlays;
  final MarketScan scan;
  final List<TopPlay> topPlays;
}

class TopPlay {
  const TopPlay({
    required this.title,
    required this.subtitle,
    required this.expectedProfit,
    required this.explanation,
    required this.quote,
    required this.longerThanTheBooks,
  });

  final String title, subtitle, explanation;
  final double expectedProfit;
  final OddsQuote quote;
  final bool longerThanTheBooks;
}

class ParlayLegView {
  const ParlayLegView({
    required this.label,
    required this.matchup,
    required this.eventId,
    required this.market,
    required this.quote,
    required this.fairProbability,
  });

  final String label, matchup, eventId, market;
  final OddsQuote quote;
  final double fairProbability;
}

class ParlaySuggestion {
  const ParlaySuggestion({
    required this.id,
    required this.bookId,
    required this.book,
    required this.legs,
    required this.price,
    required this.plainEnglish,
    required this.demo,
  });

  final String id, bookId, book, plainEnglish;
  final List<ParlayLegView> legs;
  final ParlayPrice price;
  final bool demo;
}

class ParlayFilter {
  const ParlayFilter({
    this.bookId,
    this.legs = 2,
    this.markets = const {'h2h', 'spreads', 'totals'},
    this.minAmerican,
  });

  final String? bookId;
  final int legs;
  final Set<String> markets;
  final int? minAmerican;

  ParlayFilter copyWith({
    String? bookId,
    bool clearBook = false,
    int? legs,
    Set<String>? markets,
    int? minAmerican,
    bool clearMinAmerican = false,
  }) => ParlayFilter(
    bookId: clearBook ? null : (bookId ?? this.bookId),
    legs: legs ?? this.legs,
    markets: markets ?? this.markets,
    minAmerican: clearMinAmerican ? null : (minAmerican ?? this.minAmerican),
  );
}

const parlayMarkets = {'h2h', 'spreads', 'totals'};

SlateSummary summarizeSlate(
  OddsBoard board,
  DateTime now, {
  Set<String>? books,
  ParlayFilter filter = const ParlayFilter(),
  int parlayLimit = 8,
}) {
  final scan = scanMarkets(board, now, books: books);
  final parlays = buildParlays(
    board,
    now,
    scan: scan,
    books: books,
    filter: filter,
    limit: parlayLimit,
  );
  final parlayCounts = <String, int>{};
  for (final parlay in parlays) {
    for (final leg in parlay.legs) {
      parlayCounts[leg.eventId] = (parlayCounts[leg.eventId] ?? 0) + 1;
    }
  }
  final byEvent = <String, List<PricedMarket>>{};
  for (final market in scan.markets) {
    byEvent.putIfAbsent(market.eventId, () => []).add(market);
  }
  final games = [
    for (final event in board.events)
      _gameSummary(
        event,
        byEvent[event.id] ?? const [],
        scan.arbitrage,
        parlayCounts[event.id] ?? 0,
      ),
  ]..sort((a, b) => a.event.startsAt.compareTo(b.event.startsAt));
  return SlateSummary(
    games: games,
    parlays: parlays,
    scan: scan,
    topPlays: topPlays(scan),
  );
}

GameSummary _gameSummary(
  SportEvent event,
  List<PricedMarket> markets,
  List<ArbitrageOpportunity> arbitrage,
  int parlayCount,
) {
  final positive = markets.where((market) => (market.bestMarketEv ?? 0) > 0);
  PricedMarket? moneyline;
  for (final market in markets) {
    if (market.market != 'h2h' || !market.complete) continue;
    if (moneyline == null || market.booksAveraged > moneyline.booksAveraged) {
      moneyline = market;
    }
  }
  double? chance(String team) {
    final line = moneyline;
    if (line == null) return null;
    for (final side in line.sides) {
      if (side.selection.outcome == team) return side.fairProbability;
    }
    return null;
  }

  final matchup = '${event.away} at ${event.home}';
  return GameSummary(
    event: event,
    positiveEvMarkets: positive.length,
    arbitrageCount: arbitrage.where((item) => item.matchup == matchup).length,
    parlayCount: parlayCount,
    awayChance: chance(event.away),
    homeChance: chance(event.home),
    booksInMoneyline: moneyline?.booksAveraged ?? 0,
    markets: markets,
  );
}

List<TopPlay> topPlays(MarketScan scan, {int limit = 5}) {
  final rows = <TopPlay>[];
  for (final market in scan.markets) {
    for (final side in market.sides) {
      final quote = side.best;
      final edge = side.marketEv;
      if (quote == null || edge == null) continue;
      final longer = edge > 0;
      rows.add(
        TopPlay(
          title: side.selection.label,
          subtitle: market.matchup,
          expectedProfit: edge,
          longerThanTheBooks: longer,
          quote: quote,
          explanation: longer
              ? 'This price pays more than the books\' fee-free chance. Expected profit if that chance is right: ${signedPercent(edge)} per dollar. Not a tip.'
              : 'This price pays less than the books\' fee-free chance, by ${signedPercent(edge)} per dollar if that chance is right. Shown because it is among the closest, not because it is a play.',
        ),
      );
    }
  }
  rows.sort((a, b) => b.expectedProfit.compareTo(a.expectedProfit));
  if (rows.length <= limit) return rows;
  return rows.sublist(0, limit);
}

List<ParlaySuggestion> buildParlays(
  OddsBoard board,
  DateTime now, {
  required MarketScan scan,
  Set<String>? books,
  ParlayFilter filter = const ParlayFilter(),
  int limit = 8,
}) {
  if (filter.legs < 2 || filter.legs > 3) {
    throw ArgumentError('Pre-built tickets use 2 or 3 legs.');
  }
  final allowed = filter.markets.intersection(parlayMarkets);
  if (allowed.isEmpty) return const [];
  final fairByKey = <String, double>{};
  final matchupByEvent = <String, String>{};
  for (final market in scan.markets) {
    if (!allowed.contains(market.market) || !market.complete) continue;
    matchupByEvent[market.eventId] = market.matchup;
    for (final side in market.sides) {
      final fair = side.fairProbability;
      if (fair != null) fairByKey[side.selection.key] = fair;
    }
  }
  final quotes = usableSnapshotQuotes(
    board.quotes,
    now,
    books: books,
    events: board.events,
    fetchedAt: board.fetchedAt,
  );
  final byBook = <String, Map<String, ParlayLegView>>{};
  final bookNames = <String, String>{};
  for (final quote in quotes) {
    if (filter.bookId != null && quote.bookId != filter.bookId) continue;
    final fair = fairByKey[quote.selection.key];
    final matchup = matchupByEvent[quote.selection.eventId];
    if (fair == null || matchup == null) continue;
    if (!allowed.contains(quote.selection.market)) continue;
    bookNames[quote.bookId] = quote.book;
    final events = byBook.putIfAbsent(quote.bookId, () => {});
    final leg = ParlayLegView(
      label: quote.selection.label,
      matchup: matchup,
      eventId: quote.selection.eventId,
      market: quote.selection.market,
      quote: quote,
      fairProbability: fair,
    );
    final current = events[quote.selection.eventId];
    if (current == null ||
        _legEdge(leg) > _legEdge(current) ||
        (_legEdge(leg) == _legEdge(current) &&
            quote.decimal > current.quote.decimal)) {
      events[quote.selection.eventId] = leg;
    }
  }
  final suggestions = <ParlaySuggestion>[];
  for (final entry in byBook.entries) {
    final candidates = entry.value.values.toList()
      ..sort((a, b) => _legEdge(b).compareTo(_legEdge(a)));
    final pool = candidates.length > 6 ? candidates.sublist(0, 6) : candidates;
    for (final combo in _combinations(pool, filter.legs)) {
      final price = priceParlay(
        legs: [
          for (final leg in combo)
            ParlayLegInput(
              label: leg.label,
              decimal: leg.quote.decimal,
              winProbability: leg.fairProbability,
            ),
        ],
        sameGame: false,
      );
      if (filter.minAmerican != null) {
        final floor = americanToDecimal(filter.minAmerican!);
        if (price.offeredDecimal < floor) continue;
      }
      final id = [
        entry.key,
        for (final leg in combo) leg.quote.selection.key,
      ].join('|');
      suggestions.add(
        ParlaySuggestion(
          id: id,
          bookId: entry.key,
          book: bookNames[entry.key] ?? entry.key,
          legs: combo,
          price: price,
          plainEnglish: explainParlay(price),
          demo: combo.every((leg) => leg.quote.demo),
        ),
      );
    }
  }
  suggestions.sort((a, b) {
    final left = a.price.expectedValuePerUnit ?? -999;
    final right = b.price.expectedValuePerUnit ?? -999;
    final edge = right.compareTo(left);
    if (edge != 0) return edge;
    return a.book.compareTo(b.book);
  });
  if (suggestions.length <= limit) return suggestions;
  return suggestions.sublist(0, limit);
}

double _legEdge(ParlayLegView leg) =>
    expectedValue(leg.quote.decimal, leg.fairProbability);

Iterable<List<ParlayLegView>> _combinations(
  List<ParlayLegView> items,
  int count,
) sync* {
  if (count == 0) {
    yield const [];
    return;
  }
  if (items.length < count) return;
  for (var i = 0; i <= items.length - count; i++) {
    final head = items[i];
    for (final tail in _combinations(items.sublist(i + 1), count - 1)) {
      yield [head, ...tail];
    }
  }
}

String explainParlay(ParlayPrice price) {
  final breakEven = impliedProbability(price.offeredDecimal);
  final fair = price.fairProbability;
  final breakText = percentLabel(breakEven);
  if (fair == null || price.expectedValuePerUnit == null) {
    return 'The real chance is left blank because these legs were not treated as unrelated games. '
        'The sportsbook price pays as if the ticket hits $breakText of the time. '
        'That is the break-even rate, not a prediction.';
  }
  final fairText = percentLabel(fair);
  final profit = signedPercent(price.expectedValuePerUnit!);
  final gap = breakEven - fair;
  final cut = percentLabel(gap.abs());
  final comparison = gap.abs() < 0.0005
      ? 'The price matches that multiplied chance.'
      : gap > 0
      ? 'The price is shorter than that multiplied chance by about $cut. That gap is the house cut on this ticket.'
      : 'The price is longer than that multiplied chance by about $cut.';
  return 'If these were unrelated games, the books\' fee-free chances multiply to $fairText. '
      'The ticket price pays as if it hits $breakText of the time. '
      '$comparison '
      'If the multiplied chance were right, expected profit is $profit per dollar. '
      'Games on the same slate can still move together, so this is not a promise the ticket hits.';
}

class SlipLeg {
  const SlipLeg({required this.decimal, this.winProbability});

  final double decimal;
  final double? winProbability;
}

class SlipCheck {
  const SlipCheck({required this.price, required this.plainEnglish});

  final ParlayPrice price;
  final String plainEnglish;
}

/// Prices a ticket the person typed. Win chances are optional.
/// When any chance is missing, the real chance stays blank.
SlipCheck checkSlip(List<SlipLeg> legs) {
  if (legs.length < 2) {
    throw ArgumentError('A slip needs at least two legs.');
  }
  final told = legs.every((leg) => leg.winProbability != null);
  final price = priceParlay(
    legs: [
      for (final leg in legs)
        ParlayLegInput(
          label: 'Leg',
          decimal: leg.decimal,
          winProbability: told ? leg.winProbability : null,
        ),
    ],
    sameGame: false,
  );
  final breakEven = impliedProbability(price.offeredDecimal);
  final multiplied = americanLabel(price.multipliedDecimal);
  if (!told || price.fairProbability == null) {
    return SlipCheck(
      price: price,
      plainEnglish:
          'Multiplied price $multiplied. You would need the ticket to hit ${percentLabel(breakEven)} of the time to break even. '
          'The real chance is blank until you enter a chance for every leg. This screen will not invent one.',
    );
  }
  return SlipCheck(price: price, plainEnglish: explainParlay(price));
}

/// Local calendar day. The bet log labels days as local, and tests use the
/// same function so the expectation does not depend on a hard-coded offset.
DateTime calendarDay(DateTime instant) {
  final local = instant.toLocal();
  return DateTime(local.year, local.month, local.day);
}

class DayReport {
  const DayReport({
    required this.day,
    required this.settledProfit,
    required this.pendingStake,
    required this.settledCount,
    required this.pendingCount,
  });

  final DateTime day;
  final double settledProfit, pendingStake;
  final int settledCount, pendingCount;

  bool get hasActivity => settledCount > 0 || pendingCount > 0;
}

/// One cell per day that has a bet. Days with no bets are omitted.
List<DayReport> betCalendar(Iterable<TrackedBet> bets) {
  final grouped = <DateTime, List<TrackedBet>>{};
  for (final bet in bets) {
    grouped.putIfAbsent(calendarDay(bet.placedAt), () => []).add(bet);
  }
  final reports = <DayReport>[];
  for (final entry in grouped.entries) {
    var profit = 0.0, pending = 0.0;
    var settled = 0, waiting = 0;
    for (final bet in entry.value) {
      final result = bet.profit;
      if (result == null) {
        if (bet.result == BetResult.pending) {
          waiting++;
          pending += bet.stake;
        }
      } else {
        settled++;
        profit += result;
      }
    }
    reports.add(
      DayReport(
        day: entry.key,
        settledProfit: profit,
        pendingStake: pending,
        settledCount: settled,
        pendingCount: waiting,
      ),
    );
  }
  reports.sort((a, b) => a.day.compareTo(b.day));
  return reports;
}

double pendingStake(Iterable<TrackedBet> bets) {
  var total = 0.0;
  for (final bet in bets) {
    if (bet.result == BetResult.pending) total += bet.stake;
  }
  return total;
}
