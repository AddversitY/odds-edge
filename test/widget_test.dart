import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/player_stats.dart';
import 'package:odds_edge/main.dart';
import 'package:odds_edge/player_stats_screen.dart';
import 'package:odds_edge/tools_page.dart';

import 'memory_research_store.dart';

void main() {
  testWidgets('Phone navigation, comparison and calculator', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OddsEdgeApp(researchStore: MemoryResearchStore()));
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.textContaining('Snapshot as of'), findsWidgets);
    await tester.tap(find.byKey(const Key('more-menu')));
    await tester.pumpAndSettle();
    expect(find.text('DEMO'), findsOneWidget);
    expect(find.text('Ask Coach'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Odds comparison'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Best demo price'), findsOneWidget);
    expect(find.text('Research this price'), findsWidgets);
    await tester.tap(find.byKey(const Key('more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'More'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-Research')));
    await tester.pump();
    expect(find.widgetWithText(Tab, 'Matchups'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Players'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Players'));
    await tester.pump();
    expect(find.byType(PlayerStatsScreen), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Proof Lab'));
    await tester.pumpAndSettle();
    expect(find.text('Is +125 a good price for Detroit?'), findsOneWidget);
    await tester.ensureVisible(find.byType(Slider).first);
    await tester.tap(find.byType(Slider).first);
    await tester.pump();
    expect(find.textContaining('Assumption-sensitive:'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Desktop comparison and sportsbook filtering', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OddsEdgeApp(researchStore: MemoryResearchStore()));
    expect(find.widgetWithText(ListTile, 'Today'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Research'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'NFL matchups'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Player stats'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Proof Lab'), findsNothing);
    await tester.tap(find.byKey(const Key('more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Odds comparison'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('My accessible books'));
    await tester.tap(find.text('My accessible books'));
    await tester.pumpAndSettle();
    expect(find.text('Books you can access'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tools explain a snapshot price and a Kelly stake', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OddsEdgeApp(researchStore: MemoryResearchStore()));
    await tester.tap(find.byKey(const Key('more-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'More'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-Tools')));
    await tester.pumpAndSettle();
    expect(find.text('Best price'), findsOneWidget);
    expect(find.text('Arbitrage and middles'), findsOneWidget);
    expect(find.text('Line movement'), findsOneWidget);
    expect(find.text('Parlay price'), findsOneWidget);
    expect(find.text('My bets'), findsNothing);
    expect(find.text('Stake size'), findsOneWidget);
    expect(find.text('Prop history'), findsOneWidget);
    expect(find.textContaining('last 20'), findsOneWidget);
    await tester.ensureVisible(find.text('Best price'));
    await tester.tap(find.text('Best price'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not a live stream'), findsWidgets);
    expect(find.textContaining('Sample prices'), findsWidgets);
    await tester.ensureVisible(find.byTooltip('Sportsbook fee').first);
    await tester.tap(find.byTooltip('Sportsbook fee').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('extra probability'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('All tools'));
    await tester.tap(find.text('All tools'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Stake size'));
    await tester.tap(find.text('Stake size'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Full Kelly'), findsOneWidget);
    final stakeLines = tester.widgetList<Text>(
      find.textContaining('% of bankroll'),
    );
    expect(stakeLines, isNotEmpty);
    for (final line in stakeLines) {
      expect(line.data, isNot(contains('+')));
    }
    expect(find.textContaining('1-800-GAMBLER'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Win chance %'),
      '100',
    );
    await tester.pump();
    expect(find.textContaining('less than 100'), findsOneWidget);
    expect(find.textContaining('Full Kelly'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Prop history counts a typed line against recorded games', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rows = [
      for (var week = 1; week <= 5; week++)
        PlayerGame(
          playerId: 'ada',
          name: 'Ada Lovelace',
          position: 'WR',
          team: 'BUF',
          opponent: week == 5 ? 'KC' : 'MIA',
          season: 2026,
          week: week,
          date: DateTime.utc(2026, 9, week),
          seasonType: 'REG',
          stats: {'receiving_yards': week.isEven ? 80 : 10},
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ToolsPage(
              board: OddsBoard(
                events: const [],
                quotes: const [],
                fetchedAt: DateTime.utc(2026, 10, 18),
                demo: true,
              ),
              now: DateTime.utc(2026, 10, 18),
              store: MemoryResearchStore(),
              history: (_) async => <OddsQuote>[],
              stamp: (_) => '2026-10-18 12:00:00 UTC',
              loadPlayers: () async => PlayerStatsDataset(
                rows: rows,
                metadata: const {'currentSeason': 2026},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Prop history'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search player or team abbreviation'),
      'Ada',
    );
    await tester.pump();
    await tester.tap(find.textContaining('Ada Lovelace'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Line, such as 64.5'),
      '64.5',
    );
    await tester.pump();
    expect(find.textContaining('Last 5: 2 of 5 cleared'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Opponent abbreviation, such as KC'),
      'KC',
    );
    await tester.pump();
    expect(find.textContaining('Versus KC: 0 of 1 cleared'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  OddsQuote toolQuote({
    required String outcome,
    required String book,
    required double decimal,
    String market = 'h2h',
    double? point,
    String status = 'unverified',
    String? rules,
  }) {
    final at = DateTime.utc(2026, 10, 18, 12);
    return OddsQuote(
      selection: Selection(
        eventId: 'g',
        market: market,
        outcome: outcome,
        point: point,
        rules: rules ?? 'unverified:$book:$market',
      ),
      bookId: book,
      book: book,
      provider: 'test',
      decimal: decimal,
      sourceAt: at,
      collectedAt: at,
      status: status,
    );
  }

  Widget toolsHarness(OddsBoard board) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ToolsPage(
          board: board,
          now: DateTime.utc(2026, 10, 18, 12),
          store: MemoryResearchStore(),
          history: (_) async => <OddsQuote>[],
          stamp: (_) => '2026-10-18 12:00:00 UTC',
        ),
      ),
    ),
  );

  testWidgets('Unverified snapshot prices show up with the rules note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final at = DateTime.utc(2026, 10, 18, 12);
    await tester.pumpWidget(
      toolsHarness(
        OddsBoard(
          events: [
            SportEvent(
              'g',
              'Buffalo Bills',
              'Kansas City Chiefs',
              at.add(const Duration(days: 1)),
            ),
          ],
          quotes: [
            toolQuote(
              outcome: 'Buffalo Bills',
              book: 'draftkings',
              decimal: 1.91,
            ),
            toolQuote(
              outcome: 'Kansas City Chiefs',
              book: 'fanduel',
              decimal: 1.91,
            ),
            toolQuote(
              outcome: 'Over',
              book: 'draftkings',
              decimal: 1.91,
              market: 'totals',
              point: 47,
            ),
            toolQuote(
              outcome: 'Under',
              book: 'fanduel',
              decimal: 1.91,
              market: 'totals',
              point: 49,
            ),
          ],
          fetchedAt: at,
        ),
      ),
    );
    await tester.tap(find.text('Best price'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('House rules not independently verified'),
      findsWidgets,
    );
    expect(find.textContaining('Suspended lines are left out'), findsNothing);
    await tester.tap(find.text('All tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arbitrage and middles'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('If the window hits, the profit is'),
      findsOneWidget,
    );
    expect(find.textContaining('break even'), findsOneWidget);
    expect(find.textContaining('-\$9.00'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Middle window'));
    await tester.tap(find.byTooltip('Middle window'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('loses one side and wins the other'),
      findsNothing,
    );
    expect(find.textContaining('return the stake'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('An empty tools board names the real reason', (tester) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final at = DateTime.utc(2026, 10, 18, 12);
    await tester.pumpWidget(
      toolsHarness(
        OddsBoard(
          events: [SportEvent('g', 'Buffalo Bills', 'Kansas City Chiefs', at)],
          quotes: [
            toolQuote(
              outcome: 'Buffalo Bills',
              book: 'draftkings',
              decimal: 2.2,
              status: 'open',
              rules: 'includes_overtime_push_on_tie',
            ),
            toolQuote(
              outcome: 'Kansas City Chiefs',
              book: 'fanduel',
              decimal: 2.2,
              status: 'open',
              rules: 'includes_overtime_push_on_tie',
            ),
          ],
          fetchedAt: at,
        ),
      ),
    );
    await tester.tap(find.text('Best price'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already started'), findsOneWidget);
    expect(find.textContaining('Suspended lines are left out'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A spread card names the team and a tiny loss shows as 0.0%', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final at = DateTime.utc(2026, 10, 18, 12);
    await tester.pumpWidget(
      toolsHarness(
        OddsBoard(
          events: [
            SportEvent(
              'g',
              'Buffalo Bills',
              'Kansas City Chiefs',
              at.add(const Duration(days: 1)),
            ),
          ],
          quotes: [
            toolQuote(
              outcome: 'Buffalo Bills',
              book: 'draftkings',
              decimal: 1.9992,
              status: 'open',
              rules: 'includes_overtime_push_on_tie',
            ),
            toolQuote(
              outcome: 'Kansas City Chiefs',
              book: 'draftkings',
              decimal: 1.9992,
              status: 'open',
              rules: 'includes_overtime_push_on_tie',
            ),
            toolQuote(
              outcome: 'Buffalo Bills',
              book: 'draftkings',
              decimal: 1.91,
              market: 'spreads',
              point: 3.5,
              status: 'open',
              rules: 'includes_overtime_push_on_tie',
            ),
            toolQuote(
              outcome: 'Kansas City Chiefs',
              book: 'fanduel',
              decimal: 1.91,
              market: 'spreads',
              point: -3.5,
              status: 'open',
              rules: 'includes_overtime_push_on_tie',
            ),
          ],
          fetchedAt: at,
        ),
      ),
    );
    await tester.tap(find.text('Best price'));
    await tester.pumpAndSettle();
    expect(
      find.text('Buffalo Bills +3.5 · Kansas City Chiefs -3.5'),
      findsOneWidget,
    );
    expect(find.textContaining('Versus that market: 0.0% per'), findsWidgets);
    expect(find.textContaining('-0.0%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Phone coach tabs open without overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OddsEdgeApp(researchStore: MemoryResearchStore()));
    await tester.pump();
    expect(find.text('Value'), findsOneWidget);
    expect(find.textContaining('best prices'), findsOneWidget);
    await tester.tap(find.byKey(const Key('more-menu')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Ask Coach'), findsOneWidget);
    Navigator.of(tester.element(find.text('Ask Coach'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(NavigationDestination, 'Research'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Props', skipOffstage: false));
    await tester.pump();
    expect(find.text('PLAYER PROPS'), findsOneWidget);
    expect(find.text('Josh Allen'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Games', skipOffstage: false));
    await tester.pumpAndSettle();
    expect(find.text('GAMES'), findsOneWidget);
    expect(find.text('Buffalo Bills'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Buffalo Bills').first);
    await tester.pumpAndSettle();
    expect(find.text('FEE-FREE WIN CHANCE'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(NavigationDestination, 'Tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-parlay-builder')));
    await tester.pumpAndSettle();
    expect(find.text('PARLAYS'), findsOneWidget);
    expect(find.textContaining('No legs yet'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('How these tickets are built'),
      300,
    );
    expect(find.text('How these tickets are built'), findsOneWidget);
    expect(tester.takeException(), isNull);

    expect(find.widgetWithText(NavigationDestination, 'Bets'), findsNothing);
    expect(find.text('Bet log'), findsNothing);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(360, 780);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
