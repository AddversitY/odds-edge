import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/value_check.dart';

void main() {
  ValueInput priced({
    required String label,
    required double? chance,
    required double decimal,
    double? other,
    int? hits,
    int? observed,
    bool modelUnproven = false,
  }) => ValueInput(
    label: label,
    ourChance: chance,
    decimal: decimal,
    otherDecimal: other,
    source: 'the recorded games',
    hits: hits,
    observed: observed,
    modelUnproven: modelUnproven,
  );

  test('a likely side with a short price is a skip', () {
    final chance = shrunkClearRate(hits: 5, observed: 5);
    expect(chance, closeTo(7 / 9, 1e-12));
    final verdict = judgeValue(
      priced(
        label: 'Josh Allen Over 149.5',
        chance: chance,
        decimal: 1.20,
        other: 4.80,
        hits: 5,
        observed: 5,
      ),
    );
    expect(verdict.word, ValueWord.skip);
    expect(verdict.overpriced, isTrue);
    expect(verdict.why, contains('likely to hit'));
    expect(verdict.why, contains('The price is short'));
    expect(verdict.why, contains('Pass'));
  });

  test('a price ahead of our chance by at least three cents is a bet', () {
    final verdict = judgeValue(
      priced(label: 'Home -3.5', chance: 0.60, decimal: 2.00, other: 1.91),
    );
    expect(verdict.word, ValueWord.bet);
    expect(verdict.expectedValue, greaterThanOrEqualTo(betExpectedValue));
  });

  test('a smaller profit is a lean', () {
    final verdict = judgeValue(
      priced(label: 'Over 47.5', chance: 0.52, decimal: 1.95, other: 1.95),
    );
    expect(verdict.word, ValueWord.lean);
    expect(verdict.expectedValue, greaterThan(0));
    expect(verdict.expectedValue, lessThan(betExpectedValue));
  });

  test('fewer than four recorded games is a skip', () {
    expect(shrunkClearRate(hits: 3, observed: 3), isNull);
    final verdict = judgeValue(
      ValueInput(
        label: 'Short sample',
        decimal: 1.91,
        otherDecimal: 1.91,
        observed: 3,
        hits: 3,
        source: 'the recorded games',
      ),
    );
    expect(verdict.word, ValueWord.skip);
    expect(verdict.overpriced, isFalse);
    expect(verdict.why, contains('not enough'));
  });

  test('a better book, line, or leg is named, and a dead end says so', () {
    final current = judgeValue(
      priced(
        label: 'Over 149.5',
        chance: 0.78,
        decimal: 1.20,
        other: 4.80,
        hits: 5,
        observed: 5,
      ),
    );
    expect(current.word, ValueWord.skip);
    final sameBook = suggestAlternative(
      current: current,
      sameLine: [
        priced(
          label: 'Hard Rock Over 149.5',
          chance: 0.78,
          decimal: 2.10,
          other: 1.80,
        ),
      ],
      altLines: const [],
      otherLegs: const [],
    );
    expect(sameBook, contains('same line at another book'));
    expect(sameBook, contains('Review'));

    final line = suggestAlternative(
      current: current,
      sameLine: [
        priced(label: 'Shorter book', chance: 0.78, decimal: 1.15, other: 5.0),
      ],
      altLines: [
        priced(label: 'Under 249.5', chance: 0.55, decimal: 1.97, other: 1.91),
      ],
      otherLegs: const [],
    );
    expect(line, contains('different line'));

    final leg = suggestAlternative(
      current: current,
      sameLine: const [],
      altLines: const [],
      otherLegs: [
        priced(
          label: 'A different player Over 60.5',
          chance: 0.62,
          decimal: 1.91,
          other: 1.91,
        ),
      ],
    );
    expect(leg, contains('different leg'));

    final none = suggestAlternative(
      current: current,
      sameLine: const [],
      altLines: const [],
      otherLegs: const [],
    );
    expect(none, 'No better price, line, or leg is in this snapshot.');
  });

  test(
    'pinnacle is used for spreads and totals and ignored for moneylines',
    () {
      final now = DateTime.utc(2026, 11, 12);
      final start = now.add(const Duration(days: 1));
      final event = SportEvent(
        'g',
        'Buffalo Bills',
        'Kansas City Chiefs',
        start,
      );
      Selection side(String market, String outcome, double? point) => Selection(
        eventId: 'g',
        market: market,
        outcome: outcome,
        point: point,
      );
      OddsQuote pin(Selection selection, double decimal) => OddsQuote(
        selection: selection,
        bookId: 'pinnacle',
        book: 'Pinnacle',
        provider: 'test',
        decimal: decimal,
        sourceAt: now,
        collectedAt: now,
      );
      final home = side('spreads', 'Kansas City Chiefs', -3.5);
      final away = side('spreads', 'Buffalo Bills', 3.5);
      final board = OddsBoard(
        events: [event],
        quotes: [
          pin(home, 1.95),
          pin(away, 1.95),
          pin(side('h2h', 'Kansas City Chiefs', null), 1.50),
        ],
        fetchedAt: now,
      );
      final fair = pinnacleFairChance(board, home, away, now);
      expect(fair, isNotNull);
      expect(fair, closeTo(0.5, 0.02));
      expect(
        pinnacleFairChance(
          board,
          side('h2h', 'Kansas City Chiefs', null),
          away,
          now,
        ),
        isNull,
      );
    },
  );

  test("a model chance says the past test lost money", () {
    final verdict = judgeValue(
      priced(
        label: 'Chiefs -3.5',
        chance: 0.6,
        decimal: 2,
        other: 1.9,
        modelUnproven: true,
      ),
    );
    expect(verdict.why, contains('lost money'));
    expect(verdict.why, contains('not a claim'));
  });
}
