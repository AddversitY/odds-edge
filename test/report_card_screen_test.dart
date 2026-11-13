import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/report_card_screen.dart';
import 'package:odds_edge/coach/stale_board_screen.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/domain/coach_model.dart';
import 'package:odds_edge/domain/prop_report.dart';
import 'package:odds_edge/theme/edge_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the report card leads with the result and names what was not tested',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.utc(2026, 11, 12);
      final model = (await tester.runAsync(loadBundledCoachModel))!;
      await tester.pumpWidget(
        MaterialApp(
          theme: edgeTheme(),
          home: Scaffold(
            body: ReportCardScreen(
              model: model,
              now: now,
              lineHistory: const {},
              events: const [],
              examplePrices: true,
              propReport: const PropReport(
                method: 'Walk-forward.',
                tested: 'Box scores against a fair 50% line.',
                notTested: 'No historical sportsbook prop price was used. Profit was not tested.',
                usedSportsbookPrices: false,
                marketProxy: 0.5,
                scored: 1200,
                pushes: 40,
                players: 80,
                brier: 0.251,
                logLoss: 0.694,
                baselineBrier: 0.25,
                baselineLogLoss: 0.693,
                calibration: [
                  CalibrationBin(
                    from: 0.6,
                    to: 1,
                    games: 12,
                    predicted: 0.63,
                    actual: 0.50,
                  ),
                ],
                scoredByMetric: {'passing_yards': 1200},
                hasEdge: false,
                plainEnglish: 'Tested 1200 player-games. No historical prop price was available. It is not a pick.',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Game model: no edge yet'), findsOneWidget);
      expect(find.text('No edge'), findsOneWidget);
      expect(find.byKey(const Key('game-version-chart')), findsOneWidget);
      expect(find.text('50.8%'), findsOneWidget);
      expect(find.text('50.5%'), findsOneWidget);
      expect(find.text('-2.9%'), findsOneWidget);
      expect(find.text('-3.6%'), findsOneWidget);
      expect(find.text('2,885 games'), findsOneWidget);
      expect(find.textContaining('no edge against the market'), findsOneWidget);
      expect(find.byKey(const Key('calibration-chart')), findsOneWidget);
      expect(
        find.text('It did not call a 60% chance on this test.'),
        findsOneWidget,
      );
      expect(
        find.text('Not yet tested against sportsbook prices.'),
        findsOneWidget,
      );
      expect(find.text('No closes saved yet.'), findsOneWidget);
      expect(find.text('Comparison, not a pick.'), findsOneWidget);
      expect(find.textContaining('EXAMPLE'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('how-we-tested')),
        400,
      );
      await tester.tap(find.byKey(const Key('how-we-tested')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No historical sportsbook'), findsOneWidget);
      expect(find.textContaining('No line history'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the stale board shows the snapshot time in Eastern', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 11, 12, 18);
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        home: Scaffold(
          body: StaleBoardScreen(
            board: demoBoard(now),
            now: now,
            stamp: (_) => 'saved',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('ET'), findsOneWidget);
    expect(find.textContaining('Not a live board'), findsOneWidget);
    expect(find.textContaining('EXAMPLE'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Comparison, not a pick.'), 400);
    expect(find.text('Comparison, not a pick.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
