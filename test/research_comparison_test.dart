import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/research.dart';
import 'package:odds_edge/research_comparison.dart';

void main() {
  final original = SavedResearch(
    savedAt: DateTime.utc(2026, 10, 18, 12),
    thesis: 'Original theory',
    assumptions: const ResearchAssumptions(),
  );
  final revised = SavedResearch(
    savedAt: DateTime.utc(2026, 10, 18, 13),
    thesis: 'Reduced performance',
    assumptions: const ResearchAssumptions(performance: -4),
  );

  for (final width in [390.0, 1100.0]) {
    testWidgets('Snapshot comparison and selection at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResearchComparison(records: [revised, original]),
            ),
          ),
        ),
      );
      expect(find.text('Change: −13.5 pp'), findsOneWidget);
      expect(find.text('Change: −6.0 pp'), findsNWidgets(2));
      expect(find.textContaining('The EV conclusion changed:'), findsOneWidget);
      expect(find.text('Original theory'), findsOneWidget);
      await tester.tap(
        find.byType(DropdownButtonFormField<SavedResearch>).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('#2 ·').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('You selected the same snapshot'),
        findsOneWidget,
      );
      expect(find.text('Change: 0.0 pp'), findsNWidgets(7));
      expect(original.assumptions.probability, closeTo(.495, 1e-10));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Comparison explains how to start with fewer than two saves', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ResearchComparison(records: [original])),
    );
    expect(find.textContaining('save two snapshots'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<SavedResearch>), findsNothing);
  });
}
