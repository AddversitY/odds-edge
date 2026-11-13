import 'coach_board.dart';
import 'hit_rate.dart';
import 'matchup.dart';
import 'player_stats.dart';
import 'prop_history.dart';
import 'prop_chance.dart';
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
}) {
  final rate = rateFor(card);
  final anchor = _marketAnchor(card, cards);
  final chance = _chanceFor(rate, anchor);
  final quote = card.best;
  final input = ValueInput(
    label: '${card.player} ${card.lineLabel}',
    ourChance: chance,
    decimal: quote?.decimal,
    otherDecimal: quote == null
        ? null
        : _otherAtBook(card, cards, quote.bookId),
    consensusFair: card.fairProbability,
    source: _chanceSource(rate, anchor),
    hits: rate?.hits,
    observed: rate?.observed,
    chanceNote: _chanceNote(rate, anchor),
  );
  final verdict = judgeValue(input);
  final alternative = suggestAlternative(
    current: verdict,
    sameLine: _sameLine(card, cards, rateFor),
    altLines: _alts(card, cards, rateFor),
    otherLegs: _otherLegs(card, cards, rateFor),
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
) {
  final rate = rateFor(card);
  final anchor = _marketAnchor(card, cards);
  final chance = _chanceFor(rate, anchor);
  final best = card.best?.bookId;
  return [
    for (final row in card.bookRows)
      if (row.quote.bookId != best)
        ValueInput(
          label: '${row.quote.book} ${card.lineLabel}',
          ourChance: chance,
          decimal: row.quote.decimal,
          otherDecimal: _otherAtBook(card, cards, row.quote.bookId),
          consensusFair: card.fairProbability,
          source: _chanceSource(rate, anchor),
          hits: rate?.hits,
          observed: rate?.observed,
          chanceNote: _chanceNote(rate, anchor),
        ),
  ];
}

List<ValueInput> _alts(
  PropCardModel card,
  List<PropCardModel> cards,
  HitRate? Function(PropCardModel card) rateFor,
) {
  return [
    for (final item in cards)
      if (item.player == card.player &&
          item.market == card.market &&
          item.id != card.id &&
          (item.line != card.line || item.lineSide != card.lineSide))
        _inputFor(item, cards, rateFor),
  ];
}

List<ValueInput> _otherLegs(
  PropCardModel card,
  List<PropCardModel> cards,
  HitRate? Function(PropCardModel card) rateFor,
) {
  final event = card.event?.id;
  return [
    for (final item in cards)
      if (item.id != card.id &&
          item.event?.id == event &&
          (item.player != card.player || item.market != card.market))
        _inputFor(item, cards, rateFor),
  ];
}

ValueInput _inputFor(
  PropCardModel item,
  List<PropCardModel> cards,
  HitRate? Function(PropCardModel card) rateFor,
) {
  final rate = rateFor(item);
  final anchor = _marketAnchor(item, cards);
  final chance = _chanceFor(rate, anchor);
  final quote = item.best;
  return ValueInput(
    label:
        '${item.player} ${item.marketLabel} ${item.lineLabel}${quote == null ? '' : ' at ${quote.book}'}',
    ourChance: chance,
    decimal: quote?.decimal,
    otherDecimal: quote == null
        ? null
        : _otherAtBook(item, cards, quote.bookId),
    consensusFair: item.fairProbability,
    source: _chanceSource(rate, anchor),
    hits: rate?.hits,
    observed: rate?.observed,
    chanceNote: _chanceNote(rate, anchor),
  );
}

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
