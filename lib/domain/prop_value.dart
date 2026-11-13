import 'coach_board.dart';
import 'hit_rate.dart';
import 'matchup.dart';
import 'player_stats.dart';
import 'prop_history.dart';
import 'prop_chance.dart';
import 'prop_model.dart';
import 'value_check.dart';

class PropValue {
  const PropValue({required this.verdict, this.matchup});

  final ValueVerdict verdict;
  final MatchupCard? matchup;
}

/// The price on the card, judged against the recorded games, plus a
/// better line or leg when this one is short.
PropValue priceProp({
  required PropCardModel card,
  required List<PropCardModel> cards,
  required HitRate? Function(PropCardModel card) rateFor,
  MatchupContext? context,
  List<PlayerGame> rows = const [],
  String? playerTeam,
  String? position,
  String? opponent,
  double? teamSpread,
  double? total,
  int? seasonYear,
  HitRate? recent,
  double? Function(PropCardModel card, HitRate? rate, double? market)?
  projectedChance,
}) {
  final rate = rateFor(card);
  final anchor = _marketAnchor(card, cards);
  final projected = projectedChance?.call(card, rate, anchor);
  final chance = projected ?? _chanceFor(rate, anchor);
  final usingProjection = projected != null;
  final quote = card.best;
  final input = _input(
    card: card,
    cards: cards,
    rate: rate,
    anchor: anchor,
    chance: chance,
    usingProjection: usingProjection,
    decimal: quote?.decimal,
    label: '${card.player} ${card.lineLabel}',
  );
  final verdict = judgeValue(input);
  final alternative = suggestAlternative(
    current: verdict,
    sameLine: _sameLine(card, cards, rateFor, projectedChance),
    altLines: _alts(card, cards, rateFor, projectedChance),
    otherLegs: _otherLegs(card, cards, rateFor, projectedChance),
  );
  final withAlt = alternative == null
      ? verdict
      : ValueVerdict(
          word: verdict.word,
          why: '${verdict.why} $alternative',
          math: '${verdict.math} $alternative',
          ourChance: verdict.ourChance,
          fairChance: verdict.fairChance,
          breakEven: verdict.breakEven,
          expectedValue: verdict.expectedValue,
          alternative: alternative,
          overpriced: verdict.overpriced,
        );
  MatchupCard? matchup;
  if (context != null) {
    matchup = buildMatchup(
      player: card.player,
      market: card.market,
      lineLabel: card.lineLabel,
      valueWord: withAlt.wordLabel,
      rows: rows,
      context: context,
      playerTeam: playerTeam,
      position: position,
      opponent: opponent,
      teamSpread: teamSpread,
      total: total,
      season: rate,
      recent: recent,
      seasonYear: seasonYear,
    );
  }
  return PropValue(verdict: withAlt, matchup: matchup);
}

HitRate? preferredRate(PropWindows? windows) {
  final season = windows?.season;
  if (season != null && season.observed >= 4) return season;
  final last10 = windows?.last10;
  if (last10 != null && last10.observed >= 4) return last10;
  final last20 = windows?.last20;
  if (last20 != null && last20.observed >= 4) return last20;
  return season ?? last10 ?? last20;
}

double? _otherAtBook(
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

List<ValueInput> _sameLine(
  PropCardModel card,
  List<PropCardModel> cards,
  HitRate? Function(PropCardModel card) rateFor,
  double? Function(PropCardModel card, HitRate? rate, double? market)?
  projectedChance,
) {
  final rate = rateFor(card);
  final anchor = _marketAnchor(card, cards);
  final projected = projectedChance?.call(card, rate, anchor);
  final best = card.best?.bookId;
  return [
    for (final row in card.bookRows)
      if (row.quote.bookId != best)
        _input(
          card: card,
          cards: cards,
          rate: rate,
          anchor: anchor,
          chance: projected ?? _chanceFor(rate, anchor),
          usingProjection: projected != null,
          decimal: row.quote.decimal,
          label: '${row.quote.book} ${card.lineLabel}',
          bookId: row.quote.bookId,
        ),
  ];
}

List<ValueInput> _alts(
  PropCardModel card,
  List<PropCardModel> cards,
  HitRate? Function(PropCardModel card) rateFor,
  double? Function(PropCardModel card, HitRate? rate, double? market)?
  projectedChance,
) {
  final preferred = preferredPropCards(
    cards,
    (item) => _ourChance(item, cards, rateFor, projectedChance),
  );
  return [
    for (final item in preferred)
      if (item.player == card.player &&
          item.market == card.market &&
          item.id != card.id &&
          (item.line != card.line || item.lineSide != card.lineSide))
        _inputFor(item, cards, rateFor, projectedChance),
  ];
}

List<ValueInput> _otherLegs(
  PropCardModel card,
  List<PropCardModel> cards,
  HitRate? Function(PropCardModel card) rateFor,
  double? Function(PropCardModel card, HitRate? rate, double? market)?
  projectedChance,
) {
  final event = card.event?.id;
  final preferred = preferredPropCards(
    cards,
    (item) => _ourChance(item, cards, rateFor, projectedChance),
  );
  return [
    for (final item in preferred)
      if (item.id != card.id &&
          item.event?.id == event &&
          (item.player != card.player || item.market != card.market))
        _inputFor(item, cards, rateFor, projectedChance),
  ];
}

double? _ourChance(
  PropCardModel item,
  List<PropCardModel> cards,
  HitRate? Function(PropCardModel card) rateFor,
  double? Function(PropCardModel card, HitRate? rate, double? market)?
  projectedChance,
) {
  final rate = rateFor(item);
  final anchor = _marketAnchor(item, cards);
  return projectedChance?.call(item, rate, anchor) ?? _chanceFor(rate, anchor);
}

/// One card per player, market, and line: the side whose chance beats
/// the book's no-vig by more. A tie, or two missing chances, keeps the over.
List<PropCardModel> preferredPropCards(
  List<PropCardModel> cards,
  double? Function(PropCardModel card) ourChance,
) {
  double? edge(PropCardModel card) {
    final ours = ourChance(card);
    final book = _marketAnchor(card, cards);
    if (ours == null || book == null) return null;
    if (ours <= 0 || ours >= 1 || book <= 0 || book >= 1) return null;
    return (ours - book) * 100;
  }

  PropCardModel better(PropCardModel a, PropCardModel b) {
    final left = edge(a);
    final right = edge(b);
    if (left == null && right == null) return _overCard(a, b);
    if (left == null) return b;
    if (right == null) return a;
    if ((left - right).abs() < 1e-6) return _overCard(a, b);
    return left > right ? a : b;
  }

  final best = <String, PropCardModel>{};
  final order = <String>[];
  for (final card in cards) {
    final event = card.event?.id ?? card.side.eventId;
    final key = '$event|${card.player}|${card.market}|${card.line}';
    final current = best[key];
    if (current == null) {
      best[key] = card;
      order.add(key);
    } else {
      best[key] = better(current, card);
    }
  }
  return [for (final key in order) best[key]!];
}

PropCardModel _overCard(PropCardModel a, PropCardModel b) {
  if (a.lineSide == LineSide.over) return a;
  if (b.lineSide == LineSide.over) return b;
  return a;
}

ValueInput _inputFor(
  PropCardModel item,
  List<PropCardModel> cards,
  HitRate? Function(PropCardModel card) rateFor,
  double? Function(PropCardModel card, HitRate? rate, double? market)?
  projectedChance,
) {
  final rate = rateFor(item);
  final anchor = _marketAnchor(item, cards);
  final projected = projectedChance?.call(item, rate, anchor);
  final quote = item.best;
  return _input(
    card: item,
    cards: cards,
    rate: rate,
    anchor: anchor,
    chance: projected ?? _chanceFor(rate, anchor),
    usingProjection: projected != null,
    decimal: quote?.decimal,
    label:
        '${item.player} ${item.marketLabel} ${item.lineLabel}${quote == null ? '' : ' at ${quote.book}'}',
  );
}

ValueInput _input({
  required PropCardModel card,
  required List<PropCardModel> cards,
  required HitRate? rate,
  required double? anchor,
  required double? chance,
  required bool usingProjection,
  required double? decimal,
  required String label,
  String? bookId,
}) {
  final book = bookId ?? card.best?.bookId;
  return ValueInput(
    label: label,
    ourChance: chance,
    decimal: decimal,
    otherDecimal: book == null ? null : _otherAtBook(card, cards, book),
    consensusFair: card.fairProbability,
    source: usingProjection ? propProjectionSource : _chanceSource(rate, anchor),
    hits: rate?.hits,
    observed: rate?.observed,
    chanceNote: usingProjection
        ? propLiveChance == PropLiveChance.calibrated
              ? 'Projected from recent usage, shifted by earlier games, then pulled toward the book\'s no-vig chance and capped.'
              : 'Projected from recent usage, the matchup, and the team total, then pulled toward the book\'s no-vig chance and capped.'
        : _chanceNote(rate, anchor),
  );
}

double? propMarketAnchor(PropCardModel card, List<PropCardModel> cards) =>
    _marketAnchor(card, cards);

double? _marketAnchor(PropCardModel card, List<PropCardModel> cards) {
  final quote = card.best;
  final consensus = card.fairProbability;
  final usableConsensus =
      consensus != null && consensus.isFinite && consensus > 0 && consensus < 1
      ? consensus
      : null;
  if (quote == null) return usableConsensus;
  return noVigChance(quote.decimal, _otherAtBook(card, cards, quote.bookId)) ??
      usableConsensus;
}

double? _chanceFor(HitRate? rate, double? market) {
  if (rate == null) return null;
  return propSideChance(
    hits: rate.hits,
    observed: rate.observed,
    market: market,
  );
}

String _chanceSource(HitRate? rate, double? market) {
  if (rate == null) return 'the recorded games';
  return market == null ? propEvenSource : propChanceSource;
}

String? _chanceNote(HitRate? rate, double? market) {
  if (rate == null) return null;
  return propChanceNote(
    hits: rate.hits,
    observed: rate.observed,
    usedMarket: market != null,
  );
}
