import 'dart:async';

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
import 'package:odds_edge/ui/feed_card.dart';
import 'package:odds_edge/coach/prop_pricing.dart';

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

  testWidgets('pending player data is loading, not a board of Skip verdicts', (
    tester,
  ) async {
    final pending = Completer<PlayerStatsDataset>();
    final now = DateTime.utc(2026, 11, 12);
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        home: HomeScreen(
          board: demoBoard(now),
          now: now,
          stamp: (_) => 'now',
          loadPlayers: () => pending.future,
          loadMatchup: () async => throw StateError('no matchup'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Loading saved player stats…'), findsOneWidget);
    expect(find.byType(FeedPropCard), findsNothing);
    pending.completeError(StateError('unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Loading saved player stats…'), findsNothing);
    expect(find.textContaining('Box scores could not be read'), findsOneWidget);
  });

  test(
    'a shared pricing pass preserves every independently priced verdict',
    () {
      final now = DateTime.utc(2026, 11, 12);
      final board = demoBoard(now);
      final cards = propCards(board, now);
      final directory = PlayerDirectory(
        PlayerStatsDataset(
          rows: [for (var week = 1; week <= 8; week++) allen(week, 280)],
        ),
      );
      final shared = showProps(
        cards: cards,
        directory: directory,
        context: null,
        board: board,
        now: now,
      );
      for (var i = 0; i < cards.length; i++) {
        final single = showProp(
          card: cards[i],
          cards: cards,
          directory: directory,
          context: null,
          board: board,
          now: now,
        );
        expect(shared[i].verdict.ourChance, single.verdict.ourChance);
        expect(shared[i].verdict.word, single.verdict.word);
        expect(shared[i].verdict.alternative, single.verdict.alternative);
        expect(shared[i].projection?.mean, single.projection?.mean);
      }
    },
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
    expect(find.text('Review'), findsWidgets);
    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();
    expect(find.text('Josh Allen'), findsWidgets);
    await tester.scrollUntilVisible(find.textContaining('not a pick'), 400);
    expect(find.textContaining('not a pick'), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    scrollable.position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pass'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pts too high'), findsWidgets);
    expect(find.text('FEE-FREE'), findsWidgets);
    expect(find.text('Comparison, not a pick.'), findsOneWidget);
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
    await tester.scrollUntilVisible(find.text('Hit rate'), 250);
    expect(find.text('Hit rate'), findsOneWidget);
    expect(find.text('Add to parlay'), findsOneWidget);
    expect(find.textContaining('No recorded stat'), findsNothing);
    await tester.tap(find.text('L5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to parlay'));
    await tester.pump();
    expect(slip.slip.length, 1);
    expect(find.text('Remove from parlay'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Under'), -250);
    await tester.tap(find.text('Under'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to parlay'));
    await tester.pump();
    expect(slip.slip.length, 1);
    expect(find.textContaining('already on the slip'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('H2H'), 250);
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('H2H'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('No recorded stat'),
      200,
    );
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
      expect(find.text('Combined estimate'.toUpperCase()), findsOneWidget);
      expect(find.text('Run simulation'), findsOneWidget);
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
