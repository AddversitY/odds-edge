import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/games_screen.dart';
import 'package:odds_edge/coach/sharp_view.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/data/demo_lines.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/public_sharp.dart';
import 'package:odds_edge/main.dart';
import 'package:odds_edge/theme/edge_theme.dart';

import 'memory_research_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the game Sharp row and the public screen fit a phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 11, 12, 18);
    final board = demoBoard(now);
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        home: Scaffold(
          body: GamesScreen(
            board: board,
            now: now,
            lineHistory: demoLineHistory(board),
            sampleHistory: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sharp  Fast move to the Chiefs'), findsOneWidget);
    await tester.tap(find.text('Buffalo Bills'));
    await tester.pumpAndSettle();
    expect(find.text('Sharp'), findsOneWidget);
    expect(find.byType(LineSparkline), findsOneWidget);
    await tester.tap(find.text('Sharp'));
    await tester.pumpAndSettle();
    expect(find.textContaining('inside 20 minutes'), findsOneWidget);
    expect(find.textContaining('DraftKings moved first'), findsOneWidget);
    expect(find.textContaining('not a pick'), findsWidgets);
    expect(find.textContaining('not available'), findsWidgets);
    expect(find.textContaining('Most bets are on'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the public screen lists the clearest signal first', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 11, 12, 18);
    final board = demoBoard(now);
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        home: Scaffold(
          body: PublicSharpScreen(
            board: board,
            now: now,
            lineHistory: demoLineHistory(board),
            sample: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Public vs sharp'), findsOneWidget);
    expect(find.text('Ticket % and money % are not available.'), findsWidgets);
    expect(find.textContaining('Sample line history'), findsOneWidget);
    expect(find.textContaining('signals, not picks'), findsOneWidget);
    expect(find.text('Fast move to the Chiefs'), findsOneWidget);
    expect(find.text('Steelers -1 to -3.5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('More opens Public vs sharp', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(OddsEdgeApp(researchStore: MemoryResearchStore()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More', skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Public vs sharp'));
    await tester.pumpAndSettle();
    expect(find.textContaining('signals, not picks'), findsOneWidget);
    expect(find.text('Fast move to the Chiefs'), findsOneWidget);
    expect(find.text('Ticket % and money % are not available.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fixture with both sides shows the reverse-line sentence', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 11, 12, 18);
    final event = SportEvent(
      'g',
      'Buffalo Bills',
      'Kansas City Chiefs',
      now.add(const Duration(days: 1)),
    );
    final board = OddsBoard(
      events: [event],
      quotes: const [],
      fetchedAt: now,
      demo: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        home: Scaffold(
          body: PublicSharpScreen(
            board: board,
            now: now,
            lineHistory: {
              event.id: [
                LineSnapshot(
                  at: now.subtract(const Duration(hours: 4)),
                  eventId: event.id,
                  away: event.away,
                  home: event.home,
                  prices: [
                    for (final book in const [
                      'fanduel',
                      'draftkings',
                      'betmgm',
                    ])
                      LinePrice(
                        bookId: book,
                        market: 'spreads',
                        outcome: event.home,
                        decimal: 1.91,
                        point: -6,
                      ),
                  ],
                ),
                LineSnapshot(
                  at: now.subtract(const Duration(hours: 1)),
                  eventId: event.id,
                  away: event.away,
                  home: event.home,
                  prices: [
                    for (final book in const [
                      'fanduel',
                      'draftkings',
                      'betmgm',
                    ])
                      LinePrice(
                        bookId: book,
                        market: 'spreads',
                        outcome: event.home,
                        decimal: 1.91,
                        point: -3,
                      ),
                  ],
                ),
              ],
            },
            publicSplits: [
              PublicSplit(
                eventId: event.id,
                market: 'spreads',
                sourceName: 'Example source',
                attribution: 'Shown with permission',
                fetchedAt: now,
                homeLabel: event.home,
                awayLabel: event.away,
                homeTickets: 70,
                awayTickets: 30,
                homeMoney: 38,
                awayMoney: 62,
              ),
            ],
            sample: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Most bets are on the Chiefs, but the line moved toward the Bills. '
        'That usually means bigger bettors like the Bills.',
      ),
      findsNothing,
    );
    await tester.tap(find.text('Sharp'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Most bets are on the Chiefs, but the line moved toward the Bills.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('62% of the money'), findsWidgets);
    expect(find.text('Bets on the Chiefs, line to the Bills'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
