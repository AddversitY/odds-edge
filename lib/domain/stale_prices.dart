import 'market_math.dart';
import 'odds.dart';

/// One book whose price, at the same number, is short of the fee-free
/// consensus by more than a normal fee, and also short of the best
/// book in the same snapshot.
class StalePrice {
  const StalePrice({
    required this.book,
    required this.bookId,
    required this.matchup,
    required this.label,
    required this.decimal,
    required this.breakEven,
    required this.fair,
    required this.bestBreakEven,
    required this.gap,
    required this.reason,
    required this.brief,
  });

  final String book;
  final String bookId;
  final String matchup;
  final String label;
  final double decimal;
  final double breakEven;
  final double fair;
  final double bestBreakEven;

  /// Break-even minus the fee-free consensus.
  final double gap;
  final String reason;

  /// One line for the card. The long [reason] stays behind a tap.
  final String brief;
}

/// A book must be at least this far above the fee-free consensus.
const staleConsensusGap = 0.03;

/// And at least this far shorter than the best price at the same number,
/// so a normal fee on every book is not called stale.
const staleBehindBest = 0.02;

List<StalePrice> stalePrices(
  OddsBoard board,
  DateTime now, {
  Set<String>? books,
}) {
  final quotes = usableSnapshotQuotes(
    board.quotes,
    now,
    books: books,
    events: board.events,
    fetchedAt: board.fetchedAt,
  );
  final events = {for (final event in board.events) event.id: event};
  final grouped = <String, List<OddsQuote>>{};
  for (final quote in quotes) {
    final selection = quote.selection;
    if (selection.market != 'h2h' &&
        selection.market != 'spreads' &&
        selection.market != 'totals' &&
        !selection.market.startsWith('player_')) {
      continue;
    }
    final point = selection.point;
    final pointKey = selection.market == 'spreads'
        ? (point?.abs().toStringAsFixed(3) ?? '')
        : (point?.toStringAsFixed(3) ?? '');
    final key =
        '${selection.eventId}|${selection.market}|${selection.participant}|$pointKey|${selection.period}';
    (grouped[key] ??= []).add(quote);
  }
  final rows = <StalePrice>[];
  for (final group in grouped.values) {
    rows.addAll(_lags(group, events));
  }
  rows.sort((a, b) => b.gap.compareTo(a.gap));
  return rows;
}

List<StalePrice> _lags(List<OddsQuote> quotes, Map<String, SportEvent> events) {
  final outcomes = <String, Map<String, OddsQuote>>{};
  for (final quote in quotes) {
    outcomes.putIfAbsent(quote.selection.outcome, () => {})[quote.bookId] =
        quote;
  }
  if (outcomes.length < 2) return const [];
  final names = outcomes.keys.toList();
  final complete = <String>{};
  for (final book in outcomes[names.first]!.keys) {
    if (names.every((name) => outcomes[name]!.containsKey(book))) {
      complete.add(book);
    }
  }
  if (complete.length < 2) return const [];
  final fairByBook = <String, Map<String, double>>{};
  for (final book in complete) {
    final implied = [
      for (final side in names)
        impliedProbability(outcomes[side]![book]!.decimal),
    ];
    try {
      final removed = removeVigProportional(implied);
      fairByBook[book] = {
        for (var i = 0; i < names.length; i++)
          names[i]: removed.probabilities[i],
      };
    } on ArgumentError {
      continue;
    }
  }
  if (fairByBook.length < 2) return const [];
  final event = events[quotes.first.selection.eventId];
  final matchup = event == null ? '' : '${event.away} at ${event.home}';
  final found = <StalePrice>[];
  for (final name in names) {
    final offered = [for (final book in complete) outcomes[name]![book]!];
    final best = offered
        .map((quote) => impliedProbability(quote.decimal))
        .reduce((a, b) => a < b ? a : b);
    for (final quote in offered) {
      final others = [
        for (final entry in fairByBook.entries)
          if (entry.key != quote.bookId && entry.value[name] != null)
            entry.value[name]!,
      ];
      if (others.isEmpty) continue;
      final consensus = others.reduce((a, b) => a + b) / others.length;
      final breakEven = impliedProbability(quote.decimal);
      final gap = breakEven - consensus;
      if (gap < staleConsensusGap) continue;
      if (breakEven < best + staleBehindBest) continue;
      final label = _label(quote);
      final points = (gap * 100).toStringAsFixed(1);
      found.add(
        StalePrice(
          book: quote.book,
          bookId: quote.bookId,
          matchup: matchup,
          label: label,
          decimal: quote.decimal,
          breakEven: breakEven,
          fair: consensus,
          bestBreakEven: best,
          gap: gap,
          brief: '$points pts above the other books.',
          reason:
              '${quote.book} on $label needs ${(breakEven * 100).toStringAsFixed(1)}% to break even. The fee-free consensus at this number is ${(consensus * 100).toStringAsFixed(1)}%. That is $points points short of the other books, after the fee. The best price in this snapshot needs ${(best * 100).toStringAsFixed(1)}%. This is the saved snapshot, not a live price, and it is not a pick.',
        ),
      );
    }
  }
  return found;
}

String _label(OddsQuote quote) {
  final selection = quote.selection;
  final market = marketNames[selection.market] ?? selection.market;
  final who = selection.participant.isEmpty
      ? selection.outcome
      : '${selection.participant} ${selection.outcome}';
  final point = selection.point;
  if (point == null) return '$who · $market';
  final number = point.abs().toStringAsFixed(
    point.abs().truncateToDouble() == point.abs() ? 0 : 1,
  );
  final signed = selection.market == 'spreads'
      ? (point > 0
            ? '+$number'
            : point < 0
            ? '-$number'
            : number)
      : number;
  return '$who $signed · $market';
}
