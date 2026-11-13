import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/prop_pricing.dart';
import 'package:odds_edge/domain/coach_board.dart';
import 'package:odds_edge/domain/hit_rate.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/prop_value.dart';
import 'package:odds_edge/domain/value_check.dart';

void main() {
  test('the card defaults to the side with more value and labels it', () {
    final over = _shown(
      player: 'Derrick Henry',
      side: LineSide.over,
      line: 78.5,
      ours: 0.456,
      book: 0.509,
    );
    final under = _shown(
      player: 'Derrick Henry',
      side: LineSide.under,
      line: 78.5,
      ours: 0.544,
      book: 0.491,
    );
    final picked = preferredPropSides([over, under]);
    expect(picked, hasLength(1));
    expect(picked.single.card.lineSide, LineSide.under);
    expect(picked.single.card.lineLabel, 'Under 78.5');
    expect(picked.single.edge!, closeTo(5.3, 0.05));
    expect(picked.single.cards, isNotEmpty);
  });

  test('a tie keeps the over, and a missing chance does not invent one', () {
    final over = _shown(
      player: 'Jahmyr Gibbs',
      side: LineSide.over,
      line: 64.5,
      ours: 0.55,
      book: 0.50,
    );
    final under = _shown(
      player: 'Jahmyr Gibbs',
      side: LineSide.under,
      line: 64.5,
      ours: 0.45,
      book: 0.50,
    );
    expect(preferredPropSides([under, over]).single.card.lineSide, LineSide.over);

    final tiedOver = _shown(
      player: 'Jahmyr Gibbs',
      side: LineSide.over,
      line: 64.5,
      ours: 0.50,
      book: 0.50,
    );
    final tiedUnder = _shown(
      player: 'Jahmyr Gibbs',
      side: LineSide.under,
      line: 64.5,
      ours: 0.50,
      book: 0.50,
    );
    expect(
      preferredPropSides([tiedUnder, tiedOver]).single.card.lineSide,
      LineSide.over,
    );

    final blankOver = _shown(
      player: 'Jahmyr Gibbs',
      side: LineSide.over,
      line: 64.5,
    );
    final blankUnder = _shown(
      player: 'Jahmyr Gibbs',
      side: LineSide.under,
      line: 64.5,
    );
    expect(
      preferredPropSides([blankUnder, blankOver]).single.card.lineSide,
      LineSide.over,
    );

    final known = _shown(
      player: 'Jahmyr Gibbs',
      side: LineSide.under,
      line: 64.5,
      ours: 0.58,
      book: 0.50,
    );
    expect(
      preferredPropSides([blankOver, known]).single.card.lineSide,
      LineSide.under,
    );
  });

  test('different lines stay separate', () {
    final main = _shown(
      player: 'Josh Allen',
      side: LineSide.over,
      line: 249.5,
      ours: 0.52,
      book: 0.50,
    );
    final alt = _shown(
      player: 'Josh Allen',
      side: LineSide.under,
      line: 149.5,
      ours: 0.20,
      book: 0.15,
    );
    final picked = preferredPropSides([main, alt]);
    expect(picked, hasLength(2));
  });

  test('a parlay suggestion uses the side with more value', () {
    final now = DateTime.utc(2026, 11, 16);
    final current = _card(
      player: 'James Cook',
      side: LineSide.over,
      line: 72.5,
      decimal: 1.80,
      fair: 0.55,
      now: now,
    );
    final henryOver = _card(
      player: 'Derrick Henry',
      side: LineSide.over,
      line: 78.5,
      decimal: 4.0,
      fair: 0.55,
      now: now,
    );
    final henryUnder = _card(
      player: 'Derrick Henry',
      side: LineSide.under,
      line: 78.5,
      decimal: 1.80,
      fair: 0.45,
      now: now,
    );
    final cards = [current, henryOver, henryUnder];
    double? chance(PropCardModel card, HitRate? rate, double? market) {
      if (card.player == 'James Cook') return 0.40;
      if (card.lineSide == LineSide.over) return 0.40;
      return 0.62;
    }

    final preferred = preferredPropCards(cards, (card) {
      return chance(card, null, null);
    });
    final henry = preferred.where((card) => card.player == 'Derrick Henry');
    expect(henry, hasLength(1));
    expect(henry.single.lineSide, LineSide.under);

    final priced = priceProp(
      card: current,
      cards: cards,
      rateFor: (_) => null,
      projectedChance: chance,
    );
    expect(priced.verdict.alternative, contains('Under 78.5'));
    expect(priced.verdict.alternative, isNot(contains('Over 78.5')));
  });
}

ShownProp _shown({
  required String player,
  required LineSide side,
  required double line,
  double? ours,
  double? book,
}) {
  final card = _card(
    player: player,
    side: side,
    line: line,
    decimal: 1.91,
    fair: book,
    now: DateTime.utc(2026, 11, 16),
  );
  return ShownProp(
    card: card,
    cards: [card],
    windows: null,
    value: PropValue(
      verdict: ValueVerdict(
        word: ValueWord.skip,
        why: '',
        math: '',
        ourChance: ours,
        fairChance: book,
      ),
    ),
    opponent: 'CIN',
    teamSpread: null,
    total: null,
    badge: null,
    note: null,
    pairedBook: false,
  );
}

PropCardModel _card({
  required String player,
  required LineSide side,
  required double line,
  required double decimal,
  required double? fair,
  required DateTime now,
}) {
  final outcome = side == LineSide.over ? 'Over' : 'Under';
  final selection = Selection(
    eventId: 'bal-cin',
    market: 'player_rush_yds',
    outcome: outcome,
    participant: player,
    point: line,
  );
  final quote = OddsQuote(
    selection: selection,
    bookId: 'book-$player-$outcome',
    book: 'Book',
    provider: 'demo',
    decimal: decimal,
    sourceAt: now,
    collectedAt: now,
    demo: true,
  );
  return PropCardModel(
    side: selection,
    otherSide: null,
    event: SportEvent('bal-cin', 'CIN', 'BAL', now),
    player: player,
    market: 'player_rush_yds',
    marketLabel: 'Rush yards',
    line: line,
    lineSide: side,
    best: quote,
    implied: fair,
    fairProbability: fair,
    expectedProfit: null,
    bookRows: const [],
    rulesUnverified: false,
    demo: true,
  );
}
