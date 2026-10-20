import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/main.dart';

import 'memory_research_store.dart';

void main() {
  testWidgets('Phone navigation, comparison and calculator', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OddsEdgeApp(researchStore: MemoryResearchStore()));
    expect(find.text('DEMO'), findsOneWidget);
    expect(find.textContaining('Snapshot as of'), findsWidgets);
    await tester.tap(find.text('Odds', skipOffstage: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('Best demo price'), findsOneWidget);
    expect(find.text('Research this price'), findsWidgets);
    await tester.tap(find.text('Lab', skipOffstage: false));
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
}
