import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/home_screen.dart';
import 'package:odds_edge/coach/parlay_slip_view.dart';
import 'package:odds_edge/coach/prop_detail_screen.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/domain/coach_board.dart';
import 'package:odds_edge/domain/hit_rate.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/parlay_slip.dart';
import 'package:odds_edge/domain/player_stats.dart';
import 'package:odds_edge/domain/prop_history.dart';
import 'package:odds_edge/theme/edge_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PlayerGame allen(int week, num yards) => PlayerGame(
    playerId: 'allen',
    name: 'Josh Allen',
    position: 'QB',
    team: 'BUF',
    opponent: 'MIA',
    season: 2026,
    week: week,
    date: DateTime.utc(2026, 9, week),
    seasonType: 'REG',
    stats: {'passing_yards': yards},
  );

  testWidgets('an empty snapshot does not invent prop numbers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 11, 12);
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        home: HomeScreen(
          board: OddsBoard(
            events: const [],
            quotes: const [],
            fetchedAt: now,
            demo: false,
          ),
          now: now,
          stamp: (_) => 'now',
          loadPlayers: () async => PlayerStatsDataset(rows: const []),
          loadMatchup: () async => throw StateError('no matchup'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No player-prop prices'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('EXAMPLE'), findsNothing);
    await tester.tap(find.text('Games'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No games'), findsOneWidget);
  });

  testWidgets('the value feed shows the value check on example props', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 11, 12);
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        home: HomeScreen(
          board: demoBoard(now),
          now: now,
          stamp: (_) => '2026-11-12 00:00:00 UTC',
          loadPlayers: () async => PlayerStatsDataset(
            rows: [for (var week = 1; week <= 8; week++) allen(week, 280)],
          ),
          loadMatchup: () async => throw StateError('no matchup'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('EXAMPLE'), findsOneWidget);
    expect(find.text('Josh Allen'), findsWidgets);
    expect(find.text('Our chance'.toUpperCase()), findsWidgets);
    expect(find.textContaining('NO-VIG'), findsWidgets);
    expect(find.text('Bet'), findsWidgets);
    await tester.tap(find.text('Trending'));
    await tester.pumpAndSettle();
    expect(find.text('Josh Allen'), findsWidgets);
    await tester.scrollUntilVisible(find.textContaining('not a pick'), 400);
    expect(find.textContaining('not a pick'), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Don't"));
    await tester.pumpAndSettle();
    expect(find.textContaining('fee-free consensus'), findsWidgets);
    expect(find.textContaining('not a pick'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prop detail charts hits and adds a leg', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 11, 12);
    final board = demoBoard(now);
    final cards = propCards(board, now);
    final allenCard = cards.firstWhere(
      (card) =>
          card.player == 'Josh Allen' &&
          card.market == 'player_pass_yds' &&
          card.line == 249.5 &&
          card.lineSide == LineSide.over,
    );
    final slip = ParlaySlipController();
    addTearDown(slip.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        home: PropDetailScreen(
          card: allenCard,
          cards: cards,
          board: board,
          now: now,
          directory: PlayerDirectory(
            PlayerStatsDataset(
              rows: [
                for (var week = 1; week <= 6; week++) allen(week, week * 40),
              ],
            ),
          ),
          slip: slip,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('value-check')), findsWidgets);
    expect(find.text('Hit rate'), findsOneWidget);
    expect(find.text('Add to parlay'), findsOneWidget);
    expect(find.textContaining('No recorded stat'), findsNothing);
    await tester.tap(find.text('L5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to parlay'));
    await tester.pump();
    expect(slip.slip.length, 1);
    expect(find.text('Remove from parlay'), findsOneWidget);
    await tester.tap(find.text('Under'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to parlay'));
    await tester.pump();
    expect(slip.slip.length, 1);
    expect(find.textContaining('already on the slip'), findsOneWidget);
    await tester.tap(find.text('H2H'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No recorded stat'), findsOneWidget);
  });

  testWidgets(
    'a same-game slip labels the payout estimated and can drop a leg',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.utc(2026, 11, 12);
      final board = demoBoard(now);
      final cards = propCards(board, now);
      final amon = cards.firstWhere(
        (card) =>
            card.player == 'Amon-Ra St. Brown' &&
            card.lineSide == LineSide.over,
      );
      final gibbs = cards.firstWhere(
        (card) =>
            card.player == 'Jahmyr Gibbs' && card.lineSide == LineSide.over,
      );
      final slip = ParlaySlipController()
        ..add(amon.id)
        ..add(gibbs.id);
      addTearDown(slip.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: edgeTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ParlaySlipView(
                slip: slip,
                board: board,
                now: now,
                directory: PlayerDirectory(
                  PlayerStatsDataset(
                    rows: [
                      for (var week = 1; week <= 6; week++) allen(week, 260),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('EXAMPLE'), findsOneWidget);
      expect(find.textContaining('Estimated payout'), findsWidgets);
      expect(find.textContaining('Same game'), findsWidgets);
      expect(find.text('Our combined chance'.toUpperCase()), findsOneWidget);
      expect(find.byTooltip('Remove leg'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Remove leg').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Add a second leg'), findsOneWidget);
      expect(find.textContaining('Estimated payout'), findsNothing);
    },
  );

  testWidgets('opposite sides of one line are not priced as a parlay', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 11, 12);
    final board = demoBoard(now);
    final cards = propCards(board, now);
    final over = cards.firstWhere(
      (card) =>
          card.player == 'Josh Allen' &&
          card.market == 'player_pass_yds' &&
          card.line == 249.5 &&
          card.lineSide == LineSide.over,
    );
    final under = cards.firstWhere(
      (card) =>
          card.player == 'Josh Allen' &&
          card.market == 'player_pass_yds' &&
          card.line == 249.5 &&
          card.lineSide == LineSide.under,
    );
    expect(oppositeSides(over.side, under.side), isTrue);
    final slip = ParlaySlipController()
      ..add(over.id)
      ..add(under.id);
    addTearDown(slip.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        home: Scaffold(
          body: ParlaySlipView(slip: slip, board: board, now: now),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('over and the under'), findsOneWidget);
    expect(find.text('Our combined chance'.toUpperCase()), findsNothing);
  });
}
