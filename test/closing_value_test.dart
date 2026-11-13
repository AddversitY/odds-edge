import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/bets.dart';
import 'package:odds_edge/domain/closing_value.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/public_sharp.dart';

LineSnapshot shot(
  DateTime at,
  SportEvent event, {
  required double home,
  String book = 'fanduel',
  double decimal = 1.91,
}) {
  return LineSnapshot(
    at: at,
    eventId: event.id,
    away: event.away,
    home: event.home,
    prices: [
      LinePrice(
        bookId: book,
        market: 'spreads',
        outcome: event.home,
        decimal: decimal,
        point: home,
      ),
      LinePrice(
        bookId: book,
        market: 'spreads',
        outcome: event.away,
        decimal: decimal,
        point: -home,
      ),
    ],
  );
}

void main() {
  final event = SportEvent(
    'game-1',
    'Buffalo Bills',
    'Kansas City Chiefs',
    DateTime.utc(2026, 11, 8, 18),
  );
  final history = {
    event.id: [
      shot(DateTime.utc(2026, 11, 7, 12), event, home: -2.5),
      shot(DateTime.utc(2026, 11, 8, 17), event, home: -3.5),
      shot(DateTime.utc(2026, 11, 8, 20), event, home: -6.5),
    ],
  };

  TrackedBet bet({double? closingLine, String closeSource = ''}) {
    return TrackedBet(
      id: 'bet-1',
      placedAt: DateTime.utc(2026, 11, 7, 15),
      description: 'Chiefs -2.5',
      book: 'FanDuel',
      decimal: americanToDecimal(-110),
      stake: 10,
      result: BetResult.pending,
      market: 'spreads',
      side: 'home',
      line: -2.5,
      closingLine: closingLine,
      eventId: event.id,
      closeSource: closeSource,
    );
  }

  test('the close is the last price at or before kickoff', () {
    final filled = autoCloseBet(bet(), history, [
      event,
    ], DateTime.utc(2026, 11, 9));
    expect(filled.closingLine, -3.5);
    expect(filled.closingDecimal, 1.91);
    expect(filled.closeSource, 'line-history');
    expect(filled.lineClvPoints, closeTo(1.0, 1e-9));
    expect(filled.notes, contains('not typed'));
  });

  test('a game that has not started is left blank', () {
    final filled = autoCloseBet(bet(), history, [
      event,
    ], DateTime.utc(2026, 11, 8, 17));
    expect(filled.closingLine, isNull);
    expect(filled.closeSource, isEmpty);
  });

  test('a typed close is not replaced', () {
    final filled = autoCloseBet(
      bet(closingLine: -1, closeSource: 'typed'),
      history,
      [event],
      DateTime.utc(2026, 11, 9),
    );
    expect(filled.closingLine, -1);
    expect(filled.closeSource, 'typed');
  });

  test(
    'the summary calls a pre-kickoff move movement, not closing-line value',
    () {
      final summary = summarizeLineHistory(
        history: history,
        events: [event],
        now: DateTime.utc(2026, 11, 8, 12),
        example: true,
      );
      expect(summary.closed, isFalse);
      expect(summary.plainEnglish, contains('not closing-line value'));
      expect(summary.plainEnglish, contains('Example prices'));
      expect(summary.plainEnglish, contains('not a pick'));
    },
  );

  test('after kickoff the later pre-kickoff number is the close', () {
    final summary = summarizeLineHistory(
      history: history,
      events: [event],
      now: DateTime.utc(2026, 11, 9),
    );
    expect(summary.closed, isTrue);
    expect(summary.averageSpreadPoints, closeTo(1.0, 1e-9));
    expect(summary.plainEnglish, contains('close in this file'));
    expect(summary.plainEnglish, contains('not a pick'));
  });
}
