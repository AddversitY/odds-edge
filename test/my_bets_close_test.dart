import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/my_bets_screen.dart';
import 'package:odds_edge/domain/bets.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/public_sharp.dart';
import 'package:odds_edge/theme/edge_theme.dart';

import 'memory_research_store.dart';

void main() {
  testWidgets('My Bets fills the close from line history after kickoff', (
    tester,
  ) async {
    final event = SportEvent(
      'game-1',
      'Buffalo Bills',
      'Kansas City Chiefs',
      DateTime.utc(2026, 11, 8, 18),
    );
    final store = MemoryResearchStore();
    await store.saveBet(
      TrackedBet(
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
        eventId: event.id,
      ),
    );
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        home: Scaffold(
          body: MyBetsScreen(
            store: store,
            now: DateTime.utc(2026, 11, 9),
            board: OddsBoard(
              events: [event],
              quotes: const [],
              fetchedAt: DateTime.utc(2026, 11, 8, 17),
            ),
            lineHistory: {
              event.id: [
                LineSnapshot(
                  at: DateTime.utc(2026, 11, 7, 12),
                  eventId: event.id,
                  away: event.away,
                  home: event.home,
                  prices: [
                    LinePrice(
                      bookId: 'fanduel',
                      market: 'spreads',
                      outcome: event.home,
                      decimal: 1.91,
                      point: -2.5,
                    ),
                  ],
                ),
                LineSnapshot(
                  at: DateTime.utc(2026, 11, 8, 17),
                  eventId: event.id,
                  away: event.away,
                  home: event.home,
                  prices: [
                    LinePrice(
                      bookId: 'fanduel',
                      market: 'spreads',
                      outcome: event.home,
                      decimal: 1.87,
                      point: -3.5,
                    ),
                  ],
                ),
              ],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bet log'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1.0 pts'), findsWidgets);
    expect(find.text('Beat the close on 1 of 1 · +1.0 pts.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'The close').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('last saved price'), findsWidgets);
    expect(store.bets.single.closingLine, -3.5);
    expect(store.bets.single.closeSource, 'line-history');
    expect(tester.takeException(), isNull);
  });
}
