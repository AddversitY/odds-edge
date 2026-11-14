import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/data/published_snapshot.dart';
import 'package:odds_edge/main.dart';

import 'memory_research_store.dart';
import 'published_snapshot_test.dart' show snapshotJson;

void main() {
  testWidgets(
    'hosted schedule loads, examples are explicit, and refresh failure retains real games',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now().toUtc();
      var fail = false;
      await tester.pumpWidget(
        OddsEdgeApp(
          researchStore: MemoryResearchStore(),
          snapshotLoader: () async {
            if (fail) throw StateError('offline');
            return PublishedSnapshot.parse(snapshotJson(now), now);
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('NFL schedule · prices unavailable'), findsOneWidget);
      expect(find.text('Buffalo Bills at Kansas City Chiefs'), findsOneWidget);
      expect(find.text('EXAMPLE'), findsNothing);
      expect(find.textContaining('1970'), findsNothing);
      await tester.tap(find.byKey(const Key('switch-snapshot-mode')));
      await tester.pumpAndSettle();
      expect(find.text('Invented prices and matchups'), findsOneWidget);
      expect(find.text('EXAMPLE'), findsOneWidget);
      fail = true;
      await tester.tap(find.byKey(const Key('switch-snapshot-mode')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Update failed'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Buffalo Bills at Kansas City Chiefs'),
        150,
      );
      expect(find.text('Buffalo Bills at Kansas City Chiefs'), findsOneWidget);
      expect(find.text('EXAMPLE'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('published schedule and data controls fit enlarged phone text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now().toUtc();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.8),
            disableAnimations: true,
          ),
          child: EdgeWorkspace(
            researchStore: MemoryResearchStore(),
            snapshotLoader: () async =>
                PublishedSnapshot.parse(snapshotJson(now), now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Buffalo Bills at Kansas City Chiefs'),
      200,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'an in-flight snapshot never overwrites an explicit sample-mode switch',
    (tester) async {
      final pending = Completer<PublishedSnapshot>();
      await tester.pumpWidget(
        OddsEdgeApp(
          researchStore: MemoryResearchStore(),
          snapshotLoader: () => pending.future,
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('switch-snapshot-mode')));
      await tester.pumpAndSettle();
      final now = DateTime.now().toUtc();
      pending.complete(PublishedSnapshot.parse(snapshotJson(now), now));
      await tester.pumpAndSettle();
      expect(find.text('Invented prices and matchups'), findsOneWidget);
      expect(find.text('EXAMPLE'), findsOneWidget);
      expect(find.text('Buffalo Bills at Kansas City Chiefs'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
