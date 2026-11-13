import 'coach_board.dart';
import 'market_math.dart';
import 'odds.dart';

/// A short or likely price that is worse than the fee-free consensus.
///
/// The word is Skip. The reason compares the price with the market.
/// It is not a pick, and it does not use Coach's Line.
class SkipItem {
  const SkipItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.reason,
    required this.brief,
    required this.name,
    required this.market,
    required this.breakEven,
    required this.fair,
    required this.gap,
    required this.likely,
  });

  final String id;
  final String title;
  final String detail;
  final String reason;

  /// One line for the card. The long [reason] stays behind a tap.
  final String brief;
  final String name;
  final String market;
  final double breakEven;
  final double fair;

  /// Break-even minus the fee-free consensus. Positive means the price
  /// is short of the market.
  final double gap;
  final bool likely;
}

/// Break-even chance that counts as a short, popular price.
const skipShortPrice = 0.60;

/// Recorded clear rate that counts as a likely prop.
const skipHotRate = 0.60;

/// How far a price must sit above the fee-free consensus.
///
/// Ordinary -110 vig is about 2.4 points and does not qualify.
const skipConsensusGap = 0.03;

/// A price already on the board, plus an optional recorded hit rate.
class RatedPrice {
  const RatedPrice({
    required this.id,
    required this.title,
    required this.detail,
    required this.decimal,
    required this.fair,
    this.hits,
    this.observed,
    this.name = '',
    this.market = '',
  });

  final String id;
  final String title;
  final String detail;
  final String name;
  final String market;
  final double? decimal;
  final double? fair;
  final int? hits;
  final int? observed;
}

List<SkipItem> skipList({
  required OddsBoard board,
  required DateTime now,
  required List<RatedPrice> prices,
  Set<String>? books,
}) {
  final items = <SkipItem>[];
  final seen = <String>{};
  for (final price in prices) {
    final item = _fromPrice(price);
    if (item != null && seen.add(item.id)) items.add(item);
  }
  final scan = scanMarkets(board, now, books: books);
  for (final market in scan.markets) {
    if (market.market.startsWith('player_')) continue;
    for (final side in market.sides) {
      final item = _fromSide(market, side);
      if (item != null && seen.add(item.id)) items.add(item);
    }
  }
  items.sort((a, b) {
    final gap = b.gap.compareTo(a.gap);
    if (gap != 0) return gap;
    return b.breakEven.compareTo(a.breakEven);
  });
  return items;
}

SkipItem? _fromPrice(RatedPrice price) {
  final decimal = price.decimal;
  final fair = price.fair;
  if (decimal == null || fair == null || decimal <= 1) return null;
  final breakEven = 1 / decimal;
  final gap = breakEven - fair;
  if (gap < skipConsensusGap) return null;
  final observed = price.observed;
  final hits = price.hits;
  final hot =
      hits != null &&
      observed != null &&
      observed >= 5 &&
      hits / observed >= skipHotRate;
  final short = breakEven >= skipShortPrice;
  if (!hot && !short) return null;
  return SkipItem(
    id: price.id,
    title: price.title,
    detail: price.detail,
    reason: _reason(
      label: price.title,
      breakEven: breakEven,
      fair: fair,
      short: short,
      hits: hot ? hits : null,
      observed: hot ? observed : null,
    ),
    brief: _brief(
      gap: gap,
      hits: hot ? hits : null,
      observed: hot ? observed : null,
    ),
    name: price.name.isEmpty ? price.title : price.name,
    market: price.market,
    breakEven: breakEven,
    fair: fair,
    gap: gap,
    likely: hot || short,
  );
}

SkipItem? _fromSide(PricedMarket market, PricedSide side) {
  final quote = side.best;
  final fair = side.fairProbability;
  if (quote == null || fair == null || !fair.isFinite) return null;
  final breakEven = 1 / quote.decimal;
  final gap = breakEven - fair;
  if (gap < skipConsensusGap || breakEven < skipShortPrice) return null;
  final title = side.selection.label;
  return SkipItem(
    id: side.selection.key,
    title: title,
    detail:
        '${market.matchup} · ${market.detail} · ${quote.book} · ${americanLabel(quote.decimal)}',
    reason: _reason(
      label: title,
      breakEven: breakEven,
      fair: fair,
      short: true,
    ),
    brief: _brief(gap: gap),
    name: title,
    market: market.matchup,
    breakEven: breakEven,
    fair: fair,
    gap: gap,
    likely: true,
  );
}

String _brief({required double gap, int? hits, int? observed}) {
  final points = (gap * 100).toStringAsFixed(1);
  if (hits != null && observed != null) {
    return 'Hit $hits of $observed, but the price is $points pts too high.';
  }
  return 'The price is $points pts too high.';
}

String _reason({
  required String label,
  required double breakEven,
  required double fair,
  required bool short,
  int? hits,
  int? observed,
}) {
  final points = ((breakEven - fair) * 100).toStringAsFixed(1);
  final buffer = StringBuffer()
    ..write(
      '$label needs ${percentLabel(breakEven)} to break even. The fee-free consensus is ${percentLabel(fair)}. The price is $points points short of that consensus. ',
    );
  if (hits != null && observed != null) {
    buffer.write(
      'It cleared in $hits of $observed recorded games, so it looks likely. The record does not make the price fair. ',
    );
  } else if (short) {
    buffer.write(
      'It is a short price, the kind of side that gets bet because it looks likely. ',
    );
  }
  buffer.write(
    'This compares the price with the fee-free consensus. It is not a pick.',
  );
  return buffer.toString();
}
