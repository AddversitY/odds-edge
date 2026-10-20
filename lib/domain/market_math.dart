import 'dart:math' as math;

import 'odds.dart';

/// Books whose two-sided price is a useful reference when the snapshot
/// actually contains them. The free US book list does not include these.
/// A recreational book is never substituted.
const sharpBookIds = <String>{
  'pinnacle',
  'circa',
  'circasports',
  'bookmaker',
  'betcris',
  'lowvig',
};

const marketNames = <String, String>{
  'h2h': 'Moneyline',
  'spreads': 'Spread',
  'totals': 'Total',
  'player_pass_yds': 'Passing yards',
  'player_rush_yds': 'Rushing yards',
  'player_reception_yds': 'Receiving yards',
  'player_receptions': 'Receptions',
};

class VigFreePrice {
  const VigFreePrice({
    required this.probabilities,
    required this.hold,
    required this.method,
  });

  /// Win chances after the sportsbook fee is removed. They sum to 1.
  final List<double> probabilities;

  /// Combined implied probability minus 1. Negative means the prices cross.
  final double hold;
  final String method;
}

/// Removes the fee in proportion to each side's price.
///
/// Fair chance = side's implied chance / sum of implied chances.
/// Every side stays positive. This is the figure the app shows.
VigFreePrice removeVigProportional(List<double> implied) {
  _requireImplied(implied);
  final sum = implied.reduce((a, b) => a + b);
  return VigFreePrice(
    probabilities: [for (final chance in implied) chance / sum],
    hold: sum - 1,
    method: 'proportional',
  );
}

/// Removes the same slice of fee from every side.
///
/// Returns null when a side would be zero or negative. That happens on
/// some three-outcome markets. Two-outcome prices stay positive.
VigFreePrice? removeVigAdditive(List<double> implied) {
  _requireImplied(implied);
  final sum = implied.reduce((a, b) => a + b);
  final slice = (sum - 1) / implied.length;
  final fair = [for (final chance in implied) chance - slice];
  if (fair.any((chance) => chance <= 0 || chance >= 1)) return null;
  return VigFreePrice(probabilities: fair, hold: sum - 1, method: 'additive');
}

void _requireImplied(List<double> implied) {
  if (implied.length < 2) {
    throw ArgumentError(
      'A fee can be removed only when every side has a price.',
    );
  }
  for (final chance in implied) {
    if (!chance.isFinite || chance <= 0 || chance >= 1) {
      throw ArgumentError('Each implied chance must be between 0 and 1.');
    }
  }
}

class StakeSuggestion {
  const StakeSuggestion({
    required this.fraction,
    required this.half,
    required this.quarter,
    required this.expectedValuePerUnit,
  });

  /// Fraction of the bankroll. Zero when the price is not better than the
  /// win chance. With a possible win and push, this stays within the
  /// bankroll: it reaches 1 only when there is no chance of a loss.
  final double fraction;
  final double half;
  final double quarter;

  /// Profit per 1 unit staked if the win chance is right.
  final double expectedValuePerUnit;

  bool get edgeIsPositive => expectedValuePerUnit > 0;
}

/// Full Kelly stake for a bet that can win, push, or lose.
///
/// Push returns the stake. A negative edge becomes a zero stake rather
/// than a suggestion to bet the other side.
StakeSuggestion kellyStake({
  required double decimal,
  required double win,
  double push = 0,
}) {
  final perUnit = expectedValue(decimal, win, push: push);
  final profit = decimal - 1;
  final decided = 1 - push;
  if (profit <= 0 || decided <= 0) {
    throw ArgumentError(
      'Kelly needs a real payout and a chance the bet is decided.',
    );
  }
  final loss = decided - win;
  final raw = (win * profit - loss) / (profit * decided);
  final full = !raw.isFinite || raw <= 0 ? 0.0 : raw;
  return StakeSuggestion(
    fraction: full,
    half: full / 2,
    quarter: full / 4,
    expectedValuePerUnit: perUnit,
  );
}

class ParlayLegInput {
  const ParlayLegInput({
    required this.label,
    required this.decimal,
    this.winProbability,
  });

  final String label;
  final double decimal;
  final double? winProbability;
}

class ParlayPrice {
  const ParlayPrice({
    required this.multipliedDecimal,
    required this.offeredDecimal,
    required this.sameGame,
    required this.basis,
    this.fairProbability,
    this.fairDecimal,
    this.expectedValuePerUnit,
  });

  /// What you get from multiplying the leg prices. Same-game tickets are
  /// not actually priced this way.
  final double multipliedDecimal;
  final double offeredDecimal;
  final bool sameGame;

  /// `unrelated-legs`, `your-assumption`, or `unavailable`.
  final String basis;
  final double? fairProbability;
  final double? fairDecimal;
  final double? expectedValuePerUnit;

  bool get usesTypedTicketPrice =>
      (offeredDecimal - multipliedDecimal).abs() > 1e-9;
}

ParlayPrice priceParlay({
  required List<ParlayLegInput> legs,
  required bool sameGame,
  double? jointWinProbability,
  double? offeredDecimal,
}) {
  if (legs.length < 2) {
    throw ArgumentError('A parlay needs at least two legs.');
  }
  var multiplied = 1.0;
  for (final leg in legs) {
    impliedProbability(leg.decimal);
    final chance = leg.winProbability;
    if (chance != null && (!chance.isFinite || chance <= 0 || chance >= 1)) {
      throw ArgumentError('Each win chance must be between 0 and 1.');
    }
    multiplied *= leg.decimal;
  }
  final offered = offeredDecimal ?? multiplied;
  impliedProbability(offered);

  double? fair;
  var basis = 'unavailable';
  if (sameGame) {
    if (jointWinProbability != null) {
      if (!jointWinProbability.isFinite ||
          jointWinProbability <= 0 ||
          jointWinProbability >= 1) {
        throw ArgumentError('The joint win chance must be between 0 and 1.');
      }
      fair = jointWinProbability;
      basis = 'your-assumption';
    }
  } else if (legs.every((leg) => leg.winProbability != null)) {
    fair = 1.0;
    for (final leg in legs) {
      fair = fair! * leg.winProbability!;
    }
    basis = 'unrelated-legs';
  }

  double? fairDecimal;
  double? perUnit;
  if (fair != null) {
    fairDecimal = 1 / fair;
    perUnit = expectedValue(offered, fair);
  }
  return ParlayPrice(
    multipliedDecimal: multiplied,
    offeredDecimal: offered,
    sameGame: sameGame,
    basis: basis,
    fairProbability: fair,
    fairDecimal: fairDecimal,
    expectedValuePerUnit: perUnit,
  );
}

class BookLineMove {
  const BookLineMove({
    required this.bookId,
    required this.book,
    required this.firstDecimal,
    required this.latestDecimal,
    required this.firstAt,
    required this.latestAt,
    required this.samples,
  });

  final String bookId, book;
  final double firstDecimal, latestDecimal;
  final DateTime firstAt, latestAt;
  final int samples;

  double get change => latestDecimal - firstDecimal;
  bool get moved => samples > 1 && change.abs() > 1e-9;
}

/// One row per book. The first saved price is not an opening line, and the
/// latest saved price is not a closing line.
List<BookLineMove> lineMoves(Iterable<OddsQuote> quotes) {
  final grouped = <String, List<OddsQuote>>{};
  for (final quote in quotes) {
    grouped.putIfAbsent(quote.bookId, () => []).add(quote);
  }
  final rows = <BookLineMove>[];
  for (final group in grouped.values) {
    group.sort((a, b) {
      final collected = a.collectedAt.compareTo(b.collectedAt);
      return collected != 0 ? collected : a.sourceAt.compareTo(b.sourceAt);
    });
    final first = group.first;
    final latest = group.last;
    rows.add(
      BookLineMove(
        bookId: first.bookId,
        book: latest.book,
        firstDecimal: first.decimal,
        latestDecimal: latest.decimal,
        firstAt: first.collectedAt,
        latestAt: latest.collectedAt,
        samples: group.length,
      ),
    );
  }
  rows.sort((a, b) => a.book.compareTo(b.book));
  return rows;
}

class PricedSide {
  const PricedSide({
    required this.selection,
    required this.best,
    required this.fairProbability,
    required this.marketEv,
    required this.sharpProbability,
    required this.sharpEv,
  });

  final Selection selection;
  final OddsQuote? best;
  final double? fairProbability;
  final double? marketEv;
  final double? sharpProbability;
  final double? sharpEv;
}

class PricedMarket {
  const PricedMarket({
    required this.eventId,
    required this.matchup,
    required this.market,
    required this.detail,
    required this.sides,
    required this.bestHold,
    required this.typicalHold,
    required this.booksAveraged,
    required this.sharpLabel,
    required this.wholeNumberLine,
    required this.tieNotPriced,
    required this.removalMethodsDisagree,
    required this.complete,
    required this.rulesUnverified,
  });

  final String eventId, matchup, market, detail;
  final List<PricedSide> sides;
  final double? bestHold;
  final double? typicalHold;
  final int booksAveraged;
  final String? sharpLabel;
  final bool wholeNumberLine;
  final bool tieNotPriced;
  final bool removalMethodsDisagree;
  final bool complete;

  /// True when the prices were grouped without an independent rules check.
  /// The card has to say so. Books with different confirmed rules stay apart.
  final bool rulesUnverified;

  double? get bestMarketEv {
    final values = sides.map((side) => side.marketEv).whereType<double>();
    return values.isEmpty ? null : values.reduce(math.max);
  }
}

class ArbitrageLeg {
  const ArbitrageLeg({required this.quote, required this.share});

  final OddsQuote quote;

  /// Share of a combined stake. The shares sum to 1.
  final double share;
}

class ArbitrageOpportunity {
  const ArbitrageOpportunity({
    required this.matchup,
    required this.detail,
    required this.legs,
    required this.roi,
    required this.sameBook,
    required this.tieNotPriced,
    required this.wholeNumberLine,
    required this.rulesUnverified,
  });

  final String matchup, detail;
  final List<ArbitrageLeg> legs;

  /// Profit as a fraction of the combined stake, before any rejected bet.
  final double roi;
  final bool sameBook, tieNotPriced, wholeNumberLine;
  final bool rulesUnverified;
}

/// Profit and loss for $100 staked on each side of a middle.
class MiddlePayoff {
  const MiddlePayoff({
    required this.stakePerSide,
    required this.hitProfit,
    required this.missIfFirstWins,
    required this.missIfSecondWins,
    required this.breakEvenIfFirstCovers,
    required this.breakEvenIfSecondCovers,
  });

  final double stakePerSide;

  /// Profit if both bets win.
  final double hitProfit;

  /// Result if the first bet wins and the second loses. Negative is a loss.
  final double missIfFirstWins;

  /// Result if the second bet wins and the first loses. Negative is a loss.
  final double missIfSecondWins;

  /// Hit rate that breaks even when every miss is a win for the first bet.
  /// Zero when that miss does not lose money.
  final double breakEvenIfFirstCovers;

  /// Hit rate that breaks even when every miss is a win for the second bet.
  final double breakEvenIfSecondCovers;

  /// Hit rate that breaks even against the larger of the two decided losses.
  double get breakEvenHitRate =>
      math.max(breakEvenIfFirstCovers, breakEvenIfSecondCovers);
}

class MiddleOpportunity {
  const MiddleOpportunity({
    required this.matchup,
    required this.market,
    required this.first,
    required this.second,
    required this.window,
    required this.pushPossible,
    required this.payoff,
    required this.rulesUnverified,
  });

  final String matchup, market, window;
  final OddsQuote first, second;
  final bool pushPossible;
  final MiddlePayoff payoff;
  final bool rulesUnverified;
}

/// Shown on a card whose books were not listed in VERIFIED_NFL_RULE_BOOKS.
const unverifiedRulesNote =
    'House rules not independently verified. Standard full-game prices are grouped by market and number so books can be compared. A book that settles overtime, a tie, or a push differently is a different bet.';

/// A saved price older than this, relative to the time it was collected, is
/// left out of the snapshot tools. This does not request a new price.
const snapshotPriceLag = Duration(minutes: 30);

enum MarketSort { comparison, lowestFee }

/// [MarketSort.comparison] keeps the scan order (best market comparison first).
/// [MarketSort.lowestFee] puts the smallest sportsbook fee first.
List<PricedMarket> sortPricedMarkets(
  List<PricedMarket> markets,
  MarketSort sort,
) {
  if (sort == MarketSort.comparison) return markets;
  final copy = [...markets]
    ..sort((a, b) {
      final hold = (a.bestHold ?? double.infinity).compareTo(
        b.bestHold ?? double.infinity,
      );
      if (hold != 0) return hold;
      final game = a.matchup.compareTo(b.matchup);
      return game != 0 ? game : a.detail.compareTo(b.detail);
    });
  return copy;
}

class MarketScan {
  const MarketScan({
    required this.markets,
    required this.arbitrage,
    required this.middles,
    required this.snapshotAt,
    required this.demo,
    this.emptyReason,
  });

  final List<PricedMarket> markets;
  final List<ArbitrageOpportunity> arbitrage;
  final List<MiddleOpportunity> middles;
  final DateTime snapshotAt;
  final bool demo;

  /// Why [markets] is empty. Null when the snapshot still has a priced market.
  final String? emptyReason;
}

/// Shared bucket for books whose settlement rules were not confirmed.
/// A per-book suffix such as `unverified:draftkings:h2h` is the same bucket.
String comparisonRules(String rules) =>
    rules == 'unverified' || rules.startsWith('unverified:')
    ? 'unverified'
    : rules;

bool rulesLookUnverified(OddsQuote quote) =>
    quote.status == 'unverified' ||
    comparisonRules(quote.selection.rules) == 'unverified';

String _sideKey(Selection selection) {
  final point = selection.point?.toStringAsFixed(3) ?? '';
  return '${selection.market}|${selection.period}|${selection.participant}|${selection.outcome}|$point|${comparisonRules(selection.rules)}';
}

String _sliceKey(Selection selection) =>
    '${selection.market}|${selection.period}|${comparisonRules(selection.rules)}';

bool _eventAlreadyStarted(SportEvent event, DateTime fetchedAt) =>
    !event.startsAt.isAfter(fetchedAt);

bool _quoteUsable(
  OddsQuote quote,
  DateTime now, {
  Set<String>? books,
  Map<String, SportEvent>? events,
  DateTime? fetchedAt,
}) {
  if (quote.status != 'open' && quote.status != 'unverified') return false;
  if (books != null && !books.contains(quote.bookId)) return false;
  final limit = now.add(const Duration(seconds: 5));
  if (quote.sourceAt.isAfter(limit) || quote.collectedAt.isAfter(limit)) {
    return false;
  }
  if (quote.collectedAt.difference(quote.sourceAt) > snapshotPriceLag) {
    return false;
  }
  if (events != null && fetchedAt != null) {
    final event = events[quote.selection.eventId];
    if (event != null && _eventAlreadyStarted(event, fetchedAt)) return false;
  }
  return true;
}

List<OddsQuote> usableSnapshotQuotes(
  Iterable<OddsQuote> quotes,
  DateTime now, {
  Set<String>? books,
  Iterable<SportEvent>? events,
  DateTime? fetchedAt,
}) {
  final byId = events == null
      ? null
      : {for (final event in events) event.id: event};
  return deduplicateQuotes(
    quotes.where(
      (quote) => _quoteUsable(
        quote,
        now,
        books: books,
        events: byId,
        fetchedAt: fetchedAt,
      ),
    ),
  );
}

/// Plain reason the snapshot tools have nothing to price. Null when at least
/// one price is still usable. Does not call the odds provider.
String? snapshotEmptyReason(
  OddsBoard board,
  DateTime now, {
  Set<String>? books,
}) {
  if (usableSnapshotQuotes(
    board.quotes,
    now,
    books: books,
    events: board.events,
    fetchedAt: board.fetchedAt,
  ).isNotEmpty) {
    return null;
  }
  return _explainEmptySnapshot(board, now, books: books);
}

String _explainEmptySnapshot(
  OddsBoard board,
  DateTime now, {
  Set<String>? books,
}) {
  if (board.quotes.isEmpty) return 'No prices in this snapshot.';
  final events = {for (final event in board.events) event.id: event};
  var wrongBook = 0, future = 0, closed = 0, stale = 0, started = 0;
  for (final quote in board.quotes) {
    if (books != null && !books.contains(quote.bookId)) {
      wrongBook++;
      continue;
    }
    final limit = now.add(const Duration(seconds: 5));
    if (quote.sourceAt.isAfter(limit) || quote.collectedAt.isAfter(limit)) {
      future++;
      continue;
    }
    if (quote.status != 'open' && quote.status != 'unverified') {
      closed++;
      continue;
    }
    if (quote.collectedAt.difference(quote.sourceAt) > snapshotPriceLag) {
      stale++;
      continue;
    }
    final event = events[quote.selection.eventId];
    if (event != null && _eventAlreadyStarted(event, board.fetchedAt)) {
      started++;
      continue;
    }
  }
  final reasons = [
    started > 0,
    stale > 0,
    closed > 0,
    future > 0,
    wrongBook > 0,
  ].where((hit) => hit).length;
  if (reasons <= 1) {
    if (started > 0) {
      return 'No usable prices in this snapshot. The games have already started, so in-game lines are left out.';
    }
    if (stale > 0) {
      return 'No usable prices in this snapshot. Every price was more than 30 minutes old when it was saved.';
    }
    if (closed > 0) {
      return 'No usable prices in this snapshot. Suspended lines are left out.';
    }
    if (future > 0) {
      return 'No usable prices in this snapshot. The prices are dated after the snapshot.';
    }
    if (wrongBook > 0) {
      return 'No prices from the books you can use are in this snapshot.';
    }
  }
  final parts = <String>[
    if (started > 0)
      '$started ${started == 1 ? 'price is' : 'prices are'} from games that have already started',
    if (stale > 0)
      '$stale ${stale == 1 ? 'price was' : 'prices were'} more than 30 minutes old when saved',
    if (closed > 0)
      '$closed ${closed == 1 ? 'price is' : 'prices are'} suspended or not open',
    if (future > 0)
      '$future ${future == 1 ? 'price is' : 'prices are'} dated after the snapshot',
    if (wrongBook > 0)
      '$wrongBook ${wrongBook == 1 ? 'price is' : 'prices are'} from books you cannot use',
  ];
  if (parts.isEmpty) return 'No usable prices in this snapshot.';
  return 'No usable prices in this snapshot. ${parts.join('; ')}.';
}

MarketScan scanMarkets(OddsBoard board, DateTime now, {Set<String>? books}) {
  final quotes = usableSnapshotQuotes(
    board.quotes,
    now,
    books: books,
    events: board.events,
    fetchedAt: board.fetchedAt,
  );
  final events = {for (final event in board.events) event.id: event};
  final markets = <PricedMarket>[];
  final byEvent = <String, List<OddsQuote>>{};
  for (final quote in quotes) {
    byEvent.putIfAbsent(quote.selection.eventId, () => []).add(quote);
  }
  for (final entry in byEvent.entries) {
    final event = events[entry.key];
    final matchup = event == null
        ? entry.key
        : '${event.away} at ${event.home}';
    final bySlice = <String, List<OddsQuote>>{};
    for (final quote in entry.value) {
      final selection = quote.selection;
      bySlice.putIfAbsent(_sliceKey(selection), () => []).add(quote);
    }
    for (final slice in bySlice.values) {
      final market = slice.first.selection.market;
      if (market == 'spreads') {
        markets.addAll(_priceSpreadSlice(slice, matchup));
      } else {
        markets.addAll(_pricePointSlice(slice, matchup));
      }
    }
  }
  markets.sort((a, b) {
    final ev = (b.bestMarketEv ?? -999).compareTo(a.bestMarketEv ?? -999);
    if (ev != 0) return ev;
    final game = a.matchup.compareTo(b.matchup);
    return game != 0 ? game : a.detail.compareTo(b.detail);
  });
  final arbitrage = [for (final market in markets) ?_arbitrageFor(market)]
    ..sort((a, b) => b.roi.compareTo(a.roi));
  final middles = _middlesFor(quotes, events)
    ..sort((a, b) {
      final game = a.matchup.compareTo(b.matchup);
      return game != 0 ? game : a.window.compareTo(b.window);
    });
  return MarketScan(
    markets: markets,
    arbitrage: arbitrage,
    middles: middles,
    snapshotAt: board.fetchedAt,
    demo: board.demo,
    emptyReason: markets.isEmpty
        ? snapshotEmptyReason(board, now, books: books)
        : null,
  );
}

List<PricedMarket> _pricePointSlice(List<OddsQuote> quotes, String matchup) {
  final byPoint = <String, List<OddsQuote>>{};
  for (final quote in quotes) {
    final selection = quote.selection;
    final point = selection.point?.toStringAsFixed(3) ?? '';
    byPoint.putIfAbsent('${selection.participant}|$point', () => []).add(quote);
  }
  return [
    for (final group in byPoint.values)
      _priceMarket(_uniqueSelections(group), group, matchup),
  ];
}

List<PricedMarket> _priceSpreadSlice(List<OddsQuote> quotes, String matchup) {
  final selections = _uniqueSelections(quotes);
  final markets = <PricedMarket>[];
  final used = <String>{};
  final sorted = [...selections]
    ..sort((a, b) {
      final name = a.outcome.compareTo(b.outcome);
      if (name != 0) return name;
      return (a.point ?? 0).compareTo(b.point ?? 0);
    });
  for (var i = 0; i < sorted.length; i++) {
    if (!used.add(sorted[i].key)) continue;
    Selection? partner;
    for (var j = i + 1; j < sorted.length; j++) {
      if (used.contains(sorted[j].key)) continue;
      if (!_pointsMirror(sorted[i].point, sorted[j].point)) continue;
      if (sorted[i].outcome == sorted[j].outcome) continue;
      partner = sorted[j];
      break;
    }
    final group = partner == null ? [sorted[i]] : [sorted[i], partner];
    if (partner != null) used.add(partner.key);
    markets.add(_priceMarket(group, quotes, matchup));
  }
  return markets;
}

bool _pointsMirror(double? a, double? b) =>
    a != null && b != null && (a + b).abs() < 1e-6;

PricedMarket _priceMarket(
  List<Selection> selections,
  List<OddsQuote> quotes,
  String matchup,
) {
  final byOutcome = <String, List<OddsQuote>>{};
  final wanted = selections.map(_sideKey).toSet();
  for (final quote in quotes) {
    final key = _sideKey(quote.selection);
    if (wanted.contains(key)) {
      byOutcome.putIfAbsent(key, () => []).add(quote);
    }
  }
  final byBook = <String, Map<String, OddsQuote>>{};
  for (final selection in selections) {
    final key = _sideKey(selection);
    for (final quote in byOutcome[key] ?? const <OddsQuote>[]) {
      byBook.putIfAbsent(quote.bookId, () => {})[key] = quote;
    }
  }
  final completeBooks = <Map<String, OddsQuote>>[];
  for (final book in byBook.values) {
    if (selections.every(
      (selection) => book.containsKey(_sideKey(selection)),
    )) {
      completeBooks.add(book);
    }
  }
  List<double>? consensus;
  List<double>? sharp;
  final sharpNames = <String>{};
  final holds = <double>[];
  var disagree = false;
  if (selections.length >= 2 && completeBooks.isNotEmpty) {
    final fairRows = <List<double>>[];
    final sharpRows = <List<double>>[];
    for (final book in completeBooks) {
      final implied = [
        for (final selection in selections)
          impliedProbability(book[_sideKey(selection)]!.decimal),
      ];
      final proportional = removeVigProportional(implied);
      fairRows.add(proportional.probabilities);
      holds.add(proportional.hold);
      final additive = removeVigAdditive(implied);
      if (additive != null) {
        for (var i = 0; i < additive.probabilities.length; i++) {
          if ((additive.probabilities[i] - proportional.probabilities[i])
                  .abs() >
              0.01) {
            disagree = true;
          }
        }
      }
      final sample = book.values.first;
      if (sharpBookIds.contains(sample.bookId)) {
        sharpRows.add(proportional.probabilities);
        sharpNames.add(sample.book);
      }
    }
    consensus = _averageRows(fairRows);
    if (sharpRows.isNotEmpty) sharp = _averageRows(sharpRows);
  }
  final sides = <PricedSide>[];
  for (var i = 0; i < selections.length; i++) {
    final selection = selections[i];
    final offered = byOutcome[_sideKey(selection)];
    final best = offered == null || offered.isEmpty
        ? null
        : _bestPrice(offered);
    final fair = consensus == null ? null : consensus[i];
    final sharpChance = sharp == null ? null : sharp[i];
    sides.add(
      PricedSide(
        selection: selection,
        best: best,
        fairProbability: fair,
        marketEv: best == null || fair == null
            ? null
            : expectedValue(best.decimal, fair),
        sharpProbability: sharpChance,
        sharpEv: best == null || sharpChance == null
            ? null
            : expectedValue(best.decimal, sharpChance),
      ),
    );
  }
  final bestHold =
      selections.length >= 2 && sides.every((side) => side.best != null)
      ? sides
                .map((side) => impliedProbability(side.best!.decimal))
                .reduce((a, b) => a + b) -
            1
      : null;
  final names = sharpNames.toList()..sort();
  return PricedMarket(
    eventId: selections.first.eventId,
    matchup: matchup,
    market: selections.first.market,
    detail: _detail(selections),
    sides: sides,
    bestHold: bestHold,
    typicalHold: holds.isEmpty ? null : _median(holds),
    booksAveraged: completeBooks.length,
    sharpLabel: names.isEmpty ? null : names.join(', '),
    wholeNumberLine: selections.any(_wholePoint),
    tieNotPriced:
        selections.first.market == 'h2h' &&
        !selections.any(
          (selection) => selection.outcome.toLowerCase() == 'draw',
        ),
    removalMethodsDisagree: disagree,
    complete: selections.length >= 2 && bestHold != null,
    rulesUnverified: byOutcome.values
        .expand((quotes) => quotes)
        .any(rulesLookUnverified),
  );
}

String _detail(List<Selection> selections) {
  final market = selections.first.market;
  final name = marketNames[market] ?? market.replaceAll('_', ' ');
  final point = selections.first.point;
  final number = point == null
      ? ''
      : ' ${point.abs().toStringAsFixed(point.abs().truncateToDouble() == point.abs() ? 0 : 1)}';
  if (market == 'h2h') return name;
  if (market == 'spreads') {
    return [
      for (final selection in selections)
        '${selection.outcome} ${_signedLine(selection.point)}',
    ].join(' · ');
  }
  final who = selections.first.participant;
  if (who.isEmpty) return '$name$number';
  return '$who · $name$number';
}

String _signedLine(double? point) {
  if (point == null) return '';
  final text = point.toStringAsFixed(1);
  return point > 0 ? '+$text' : text;
}

bool _wholePoint(Selection selection) {
  final point = selection.point;
  if (point == null) return false;
  return (point - point.roundToDouble()).abs() < 1e-9;
}

List<double> _averageRows(List<List<double>> rows) {
  final width = rows.first.length;
  return [
    for (var column = 0; column < width; column++)
      rows.map((row) => row[column]).reduce((a, b) => a + b) / rows.length,
  ];
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

OddsQuote _bestPrice(List<OddsQuote> quotes) {
  final sorted = [...quotes]
    ..sort((a, b) {
      final price = b.decimal.compareTo(a.decimal);
      if (price != 0) return price;
      final time = b.sourceAt.compareTo(a.sourceAt);
      return time != 0 ? time : a.book.compareTo(b.book);
    });
  return sorted.first;
}

List<Selection> _uniqueSelections(List<OddsQuote> quotes) {
  final byKey = <String, Selection>{};
  for (final quote in quotes) {
    byKey[_sideKey(quote.selection)] = quote.selection;
  }
  return byKey.values.toList();
}

ArbitrageOpportunity? _arbitrageFor(PricedMarket market) {
  if (!market.complete ||
      market.bestHold == null ||
      market.bestHold! >= -1e-9) {
    return null;
  }
  final implied = [
    for (final side in market.sides) impliedProbability(side.best!.decimal),
  ];
  final sum = implied.reduce((a, b) => a + b);
  if (sum <= 0 || sum >= 1) return null;
  final books = market.sides.map((side) => side.best!.bookId).toSet();
  return ArbitrageOpportunity(
    matchup: market.matchup,
    detail: market.detail,
    legs: [
      for (var i = 0; i < market.sides.length; i++)
        ArbitrageLeg(quote: market.sides[i].best!, share: implied[i] / sum),
    ],
    roi: 1 / sum - 1,
    sameBook: books.length == 1,
    tieNotPriced: market.tieNotPriced,
    wholeNumberLine: market.wholeNumberLine,
    rulesUnverified: market.rulesUnverified,
  );
}

List<MiddleOpportunity> _middlesFor(
  List<OddsQuote> quotes,
  Map<String, SportEvent> events,
) {
  final slices = <String, List<OddsQuote>>{};
  for (final quote in quotes) {
    final selection = quote.selection;
    if (selection.market != 'spreads' && selection.market != 'totals') {
      continue;
    }
    if (selection.point == null) continue;
    slices
        .putIfAbsent('${selection.eventId}|${_sliceKey(selection)}', () => [])
        .add(quote);
  }
  final middles = <MiddleOpportunity>[];
  for (final slice in slices.values) {
    final bestByKey = <String, OddsQuote>{};
    for (final quote in slice) {
      final key = _sideKey(quote.selection);
      final current = bestByKey[key];
      if (current == null || quote.decimal > current.decimal) {
        bestByKey[key] = quote;
      }
    }
    final bests = bestByKey.values.toList();
    final event = events[slice.first.selection.eventId];
    final matchup = event == null
        ? slice.first.selection.eventId
        : '${event.away} at ${event.home}';
    for (var i = 0; i < bests.length; i++) {
      for (var j = i + 1; j < bests.length; j++) {
        final middle = _middle(bests[i], bests[j], matchup);
        if (middle != null) middles.add(middle);
      }
    }
  }
  return middles;
}

MiddleOpportunity? _middle(OddsQuote a, OddsQuote b, String matchup) {
  final left = a.selection;
  final right = b.selection;
  if (left.market != right.market) return null;
  final leftPoint = left.point;
  final rightPoint = right.point;
  if (leftPoint == null || rightPoint == null) return null;
  if (left.market == 'spreads') {
    if (left.outcome == right.outcome) return null;
    if (leftPoint + rightPoint <= 1e-6) return null;
    final margins = _strictIntegers(-leftPoint, rightPoint);
    if (margins.isEmpty) return null;
    return MiddleOpportunity(
      matchup: matchup,
      market: 'Spread',
      first: a,
      second: b,
      window: _marginWindow(left.outcome, right.outcome, margins),
      pushPossible: _wholePoint(left) || _wholePoint(right),
      payoff: _middlePayoff(a, b),
      rulesUnverified: rulesLookUnverified(a) || rulesLookUnverified(b),
    );
  }
  final over = left.outcome.toLowerCase() == 'over'
      ? a
      : right.outcome.toLowerCase() == 'over'
      ? b
      : null;
  final under = left.outcome.toLowerCase() == 'under'
      ? a
      : right.outcome.toLowerCase() == 'under'
      ? b
      : null;
  if (over == null || under == null || identical(over, under)) return null;
  final low = over.selection.point!;
  final high = under.selection.point!;
  if (high - low <= 1e-6) return null;
  final totals = _strictIntegers(low, high);
  if (totals.isEmpty) return null;
  return MiddleOpportunity(
    matchup: matchup,
    market: 'Total',
    first: over,
    second: under,
    window: _totalWindow(totals),
    pushPossible: _wholePoint(over.selection) || _wholePoint(under.selection),
    payoff: _middlePayoff(over, under),
    rulesUnverified: rulesLookUnverified(over) || rulesLookUnverified(under),
  );
}

MiddlePayoff _middlePayoff(OddsQuote first, OddsQuote second) {
  const stake = 100.0;
  final hit = stake * ((first.decimal - 1) + (second.decimal - 1));
  final missFirst = stake * (first.decimal - 2);
  final missSecond = stake * (second.decimal - 2);
  return MiddlePayoff(
    stakePerSide: stake,
    hitProfit: hit,
    missIfFirstWins: missFirst,
    missIfSecondWins: missSecond,
    breakEvenIfFirstCovers: _breakEvenHitRate(hit, missFirst),
    breakEvenIfSecondCovers: _breakEvenHitRate(hit, missSecond),
  );
}

/// Fraction of results that must land in the window so the average result is
/// zero, if every miss pays [miss]. A miss that does not lose money needs no
/// hits to break even.
double _breakEvenHitRate(double hit, double miss) {
  if (miss >= -1e-9) return 0;
  final span = hit - miss;
  if (span <= 1e-12) return 1;
  final rate = -miss / span;
  if (rate <= 0) return 0;
  if (rate >= 1) return 1;
  return rate;
}

String _dollars(double value) {
  final sign = value < 0 ? '-' : '';
  return '$sign\$${value.abs().toStringAsFixed(2)}';
}

String _hitRateLabel(double rate) => '${(rate * 100).toStringAsFixed(1)}%';

/// Visible card copy: hit profit, decided-miss result, and break-even rate.
String middlePayoffSummary(MiddleOpportunity middle) {
  final pay = middle.payoff;
  final hit = _dollars(pay.hitProfit);
  final first = middle.first.selection.label;
  final second = middle.second.selection.label;
  final missFirst = _dollars(pay.missIfFirstWins);
  final missSecond = _dollars(pay.missIfSecondWins);
  final opening =
      '\$100 on each side. If the window hits, the profit is $hit. ';
  final neitherLoses =
      pay.missIfFirstWins >= -0.005 && pay.missIfSecondWins >= -0.005;
  if (neitherLoses) {
    return '$opening'
        'If the window misses and both bets are decided, the result is still not a loss. '
        'The window does not have to hit to break even.';
  }
  final sameMiss = (pay.missIfFirstWins - pay.missIfSecondWins).abs() < 0.005;
  if (sameMiss) {
    return '$opening'
        'If the window misses and both bets are decided, the result is $missFirst. '
        'The window has to hit ${_hitRateLabel(pay.breakEvenIfFirstCovers)} of the time to break even.';
  }
  return '$opening'
      'If $first wins and $second loses, the result is $missFirst. '
      'If $second wins and $first loses, the result is $missSecond. '
      'The window has to hit ${_hitRateLabel(pay.breakEvenHitRate)} of the time to break even against the larger loss.';
}

/// Dialog copy for the window. A push is not a win on one side and a loss
/// on the other.
String middleWindowExplanation(MiddleOpportunity middle) {
  if (middle.pushPossible) {
    return 'Those final scores are the only ones where both bets win. '
        'Outside that window, if both bets are decided, one wins and the other loses. '
        'Landing on a whole number can push that bet and return the stake. '
        'A push is not a win on one side and a loss on the other. '
        'This is not a guaranteed profit.';
  }
  return 'Those final scores are the only ones where both bets win. '
      'Every other whole-number result loses one side and wins the other. '
      'This is not a guaranteed profit.';
}

List<int> _strictIntegers(double low, double high) {
  if (high <= low) return const [];
  var first = low.ceil();
  if (first <= low) first++;
  var last = high.floor();
  if (last >= high) last--;
  if (last < first) return const [];
  return [for (var value = first; value <= last; value++) value];
}

String _marginWindow(String team, String other, List<int> margins) {
  final phrases = [
    for (final margin in margins)
      if (margin == 0)
        'the game ends in a tie'
      else if (margin > 0)
        '$team win by $margin'
      else
        '$other win by ${-margin}',
  ];
  return 'Both bets win if ${_joinPhrases(phrases)}.';
}

String _totalWindow(List<int> totals) =>
    'Both bets win if the total is ${_joinPhrases([for (final total in totals) '$total'])}.';

String _joinPhrases(List<String> phrases) {
  if (phrases.length == 1) return phrases.single;
  if (phrases.length == 2) return '${phrases[0]} or ${phrases[1]}';
  return '${phrases.sublist(0, phrases.length - 1).join(', ')}, or ${phrases.last}';
}
