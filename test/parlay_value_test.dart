import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/parlay_value.dart';
import 'package:odds_edge/domain/value_check.dart';

void main() {
  TicketLegInput leg({
    required String label,
    required String eventId,
    required String market,
    required String outcome,
    required double decimal,
    double? chance,
    double? point,
    String player = '',
    String team = '',
  }) => TicketLegInput(
    label: label,
    eventId: eventId,
    market: market,
    outcome: outcome,
    decimal: decimal,
    point: point,
    ourChance: chance,
    player: player,
    team: team,
    source: 'the chance you typed',
  );

  test('different games multiply and same-game legs do not', () {
    expect(
      legCorrelation(
        eventA: 'a',
        eventB: 'b',
        marketA: 'spreads',
        marketB: 'totals',
        outcomeA: 'Home',
        outcomeB: 'Over',
      ),
      0,
    );
    expect(
      jointChance(
        [0.5, 0.4],
        const [
          [1, 0],
          [0, 1],
        ],
      ),
      closeTo(0.2, 1e-12),
    );

    final rho = legCorrelation(
      eventA: 'g',
      eventB: 'g',
      marketA: 'player_pass_yds',
      marketB: 'player_reception_yds',
      outcomeA: 'Over',
      outcomeB: 'Over',
      teamA: 'BUF',
      teamB: 'BUF',
    );
    expect(rho, 0.30);
    final together = jointChance(
      [0.5, 0.5],
      [
        [1, rho],
        [rho, 1],
      ],
    );
    expect(together, greaterThan(0.25));
  });

  test('the over and the under of one number are almost opposite', () {
    final rho = legCorrelation(
      eventA: 'g',
      eventB: 'g',
      marketA: 'totals',
      marketB: 'totals',
      outcomeA: 'Over',
      outcomeB: 'Under',
      pointA: 47.5,
      pointB: 47.5,
    );
    expect(rho, -0.95);
    expect(
      jointChance(
        [0.5, 0.5],
        [
          [1, rho],
          [rho, 1],
        ],
      ),
      lessThan(0.02),
    );
  });

  test('a pasted payout is real and a same-game payout is estimated', () {
    final legs = [
      leg(
        label: 'Spread',
        eventId: 'g',
        market: 'spreads',
        outcome: 'Home',
        decimal: 1.91,
        chance: 0.58,
        point: -3.5,
      ),
      leg(
        label: 'Total',
        eventId: 'g',
        market: 'totals',
        outcome: 'Over',
        decimal: 1.91,
        chance: 0.58,
        point: 47.5,
      ),
    ];
    final pasted = priceTicket(legs, pastedDecimal: 3.4);
    expect(pasted.payoutEstimated, isFalse);
    expect(pasted.payoutDecimal, 3.4);
    expect(pasted.why, contains('slip'));
    expect(pasted.sameGame, isTrue);

    final estimated = priceTicket(legs);
    expect(estimated.payoutEstimated, isTrue);
    expect(estimated.why, contains('estimated'));
    expect(estimated.payoutDecimal, lessThan(1.91 * 1.91));
  });

  test('legs in different games use the multiplied price', () {
    final ticket = priceTicket([
      leg(
        label: 'One',
        eventId: 'a',
        market: 'spreads',
        outcome: 'Home',
        decimal: 1.91,
        chance: 0.6,
        point: -3,
      ),
      leg(
        label: 'Two',
        eventId: 'b',
        market: 'totals',
        outcome: 'Over',
        decimal: 1.91,
        chance: 0.6,
        point: 45,
      ),
    ]);
    expect(ticket.sameGame, isFalse);
    expect(ticket.payoutEstimated, isFalse);
    expect(ticket.payoutDecimal, closeTo(1.91 * 1.91, 1e-9));
    expect(ticket.why, contains('multiply'));
  });

  test('one skip leg makes the ticket a skip', () {
    final ticket = priceTicket([
      leg(
        label: 'Priced',
        eventId: 'a',
        market: 'spreads',
        outcome: 'Home',
        decimal: 2.2,
        chance: 0.6,
        point: -3,
      ),
      leg(
        label: 'Missing',
        eventId: 'b',
        market: 'totals',
        outcome: 'Over',
        decimal: 1.91,
        point: 45,
      ),
    ]);
    expect(ticket.word, ValueWord.skip);
    expect(ticket.why, contains('Missing'));
    expect(ticket.why, contains('skip'));
  });

  test('the best book is the one with every leg at the highest product', () {
    final ticket = priceTicket(
      [
        leg(
          label: 'One',
          eventId: 'a',
          market: 'spreads',
          outcome: 'Home',
          decimal: 1.91,
          chance: 0.6,
          point: -3,
        ),
        leg(
          label: 'Two',
          eventId: 'b',
          market: 'totals',
          outcome: 'Over',
          decimal: 1.91,
          chance: 0.6,
          point: 45,
        ),
      ],
      booksByLeg: const [
        [
          BookLegPrice(bookId: 'fanduel', book: 'FanDuel', decimal: 1.90),
          BookLegPrice(
            bookId: 'hardrock',
            book: 'Hard Rock Bet',
            decimal: 1.98,
          ),
        ],
        [
          BookLegPrice(bookId: 'fanduel', book: 'FanDuel', decimal: 1.90),
          BookLegPrice(
            bookId: 'hardrock',
            book: 'Hard Rock Bet',
            decimal: 1.95,
          ),
        ],
      ],
    );
    expect(ticket.bestBook, 'Hard Rock Bet');
    expect(ticket.math, contains('Hard Rock Bet'));
  });
}
