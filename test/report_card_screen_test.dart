import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/report_card_screen.dart';
import 'package:odds_edge/coach/stale_board_screen.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/domain/coach_model.dart';
import 'package:odds_edge/theme/edge_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the report card leads with the result and keeps the prop comparison',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 3200));
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
            ),
          ),
        ),
      );
      await tester.pump();
      for (var step = 0; step < 40; step++) {
        if (find.byKey(const Key('prop-v2')).evaluate().isNotEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 2)),
        );
        await tester.pump();
      }
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
      expect(find.byKey(const Key('prop-v2')), findsOneWidget);
      expect(find.byKey(const Key('prop-calibration-chart')), findsOneWidget);
      expect(find.text('Record Brier'), findsOneWidget);
      expect(find.text('Usage Brier'), findsOneWidget);
      expect(find.text('Calibrated Brier'), findsOneWidget);
      expect(find.text('0.241'), findsWidgets);
      expect(find.text('0.238'), findsWidgets);
      expect(find.text('0.239'), findsWidgets);
      expect(find.textContaining('17,097 player-games'), findsOneWidget);
      expect(
        find.text('Usage model was not scored in this view.'),
        findsNothing,
      );
      expect(
        find.text('Not yet tested against sportsbook prices.'),
        findsNothing,
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
    timeout: const Timeout(Duration(minutes: 3)),
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
