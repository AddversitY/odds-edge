import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/parlay_slip_view.dart';
import 'package:odds_edge/coach/prop_detail_screen.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/domain/coach_board.dart';
import 'package:odds_edge/domain/history.dart';
import 'package:odds_edge/domain/hit_rate.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/parlay_slip.dart';
import 'package:odds_edge/domain/player_stats.dart';
import 'package:odds_edge/domain/prop_history.dart';
import 'package:odds_edge/theme/edge_theme.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14);
  final board = demoBoard(now), cards = propCards(demoBoard(now), now);
  final directory = PlayerDirectory(
    PlayerStatsDataset.fromJson(
      jsonDecode(File('assets/nfl-player-stats.json').readAsStringSync()),
    ),
  );
  final scores = [
    for (final g in jsonDecode(
      File('assets/nfl-history.json').readAsStringSync(),
    )['games'])
      HistoricalGame.fromJson(g),
  ];
  final mahomes = cards.firstWhere(
    (c) => c.player == 'Patrick Mahomes' && c.lineSide == LineSide.over,
  );
  final gibbs = cards.firstWhere(
    (c) =>
        c.player == 'Jahmyr Gibbs' &&
        c.line == 64.5 &&
        c.lineSide == LineSide.over,
  );
  final amon = cards.firstWhere(
    (c) =>
        c.player == 'Amon-Ra St. Brown' &&
        c.line == 76.5 &&
        c.lineSide == LineSide.over,
  );

  testWidgets(
    'phone simulation, quote correction and changed ticket invalidate results',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final slip = ParlaySlipController()
        ..add(gibbs.id)
        ..add(amon.id);
      addTearDown(slip.dispose);
      var clock = now;
      var activeBoard = board;
      late StateSetter redraw;
      await tester.pumpWidget(
        MaterialApp(
          theme: edgeTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(1.6),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: StatefulBuilder(
            builder: (context, setState) {
              redraw = setState;
              return Scaffold(
                body: SingleChildScrollView(
                  child: ParlaySlipView(
                    slip: slip,
                    board: activeBoard,
                    now: clock,
                    directory: directory,
                    scores: scores,
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Unadjusted leg-price illustration'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Run simulation'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final semantics = tester.ensureSemantics();
      try {
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      } finally {
        semantics.dispose();
      }
      Focus.of(tester.element(find.text('Run simulation'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      for (
        var i = 0;
        i < 12 && find.textContaining('Together ').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await tester.pump();
      }
      expect(find.textContaining('Together '), findsOneWidget);
      expect(find.textContaining('Most common losing pattern'), findsOneWidget);
      expect(find.textContaining('Simulation noise'), findsOneWidget);
      redraw(() {
        clock = clock.add(const Duration(seconds: 15));
        activeBoard = OddsBoard(events: board.events, quotes: board.quotes,
          fetchedAt: clock, demo: board.demo, notices: board.notices);
      });
      await tester.pump();
      expect(find.textContaining('Together '), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(TextField).first,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField).first, '0');
      await tester.pump();
      expect(find.text('Enter decimal odds greater than 1.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '4.20');
      await tester.pump();
      expect(find.text('Enter decimal odds greater than 1.'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('+320'),
        -300,
        maxScrolls: 30,
        scrollable: find.byType(Scrollable).first,
      );
      // The decimal quote renders as American odds, and is no longer estimated.
      redraw(() => clock = clock.add(const Duration(seconds: 15)));
      await tester.pump();
      expect(find.text('+320'), findsOneWidget);
      expect(find.textContaining('Illustrative payout uses'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.textContaining('Try ').hitTestable(),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.textContaining('Try '));
      await tester.pumpAndSettle();
      expect(slip.slip.selectionKeys, isNot([gibbs.id, amon.id]));
      expect(slip.slip.length, 2);
      expect(find.textContaining('Together '), findsNothing);
      expect(find.text('Run simulation'), findsOneWidget);
      slip.remove(slip.slip.selectionKeys.last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Together '), findsNothing);
      expect(find.text('Run again'), findsNothing);
      expect(find.textContaining('Add a second leg'), findsOneWidget);
    },
  );

  testWidgets('price comparison remains usable with large text on a phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(1.8),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: PropDetailScreen(
          card: mahomes,
          cards: cards,
          board: board,
          now: now,
          directory: directory,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Price comparison').hitTestable(),
      200,
    );
    await tester.tap(find.text('Price comparison'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Prices').hitTestable(), 150);
    expect(
      find.textContaining('Same player, stat, side and line'),
      findsOneWidget,
    );
    expect(find.textContaining('to break even'), findsWidgets);
    expect(find.textContaining('Hypothetical \$10 returns'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
