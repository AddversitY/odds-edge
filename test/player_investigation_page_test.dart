import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/player_investigation_page.dart';
import 'package:odds_edge/domain/player_investigation.dart';
import 'package:odds_edge/domain/player_simulation.dart';

import 'memory_research_store.dart';
import 'player_simulation_test.dart' show simulationGames;

void main() {
  testWidgets(
    'Reopening a frozen report restores its scenario and sample, rather than fresh defaults',
    (tester) async {
      final store = MemoryResearchStore();
      final r = PlayerInvestigation(
        savedAt: DateTime.utc(2026, 10, 19),
        playerId: 'p',
        playerName: 'Test Player',
        scenario: const PlayerScenario(
          metric: 'passing_yards',
          line: 125.5,
          price: 2.5,
          workload: .75,
          efficiency: .9,
          seed: 7,
          trials: 1000,
        ),
        games: simulationGames(),
        cutoff: DateTime.utc(2026, 10, 18),
        source: 'Test fixture',
        sourceRetrievedAt: '2026-10-19',
        thesis: 'Original frozen reasoning',
        license: 'Test license',
      );
      store.investigations.add(r);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: PlayerInvestigationPage(
            player: r.games.first,
            games: r.games,
            store: store,
            initialRecord: r,
            initialStep: 1,
            metadata: {
              'cutoff': '2026-10-18',
              'currentSeason': 2026,
              'source': 'Test fixture',
              'retrievedAt': '2026-10-19',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Workload: 75% of sampled game'), findsOneWidget);
      expect(find.textContaining('1000 seeded replays from 8'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('investigation-step-2')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('investigation-thesis')))
            .controller!
            .text,
        'Original frozen reasoning',
      );
      await tester.ensureVisible(find.byKey(const Key('save-investigation')));
      await tester.tap(find.byKey(const Key('save-investigation')));
      await tester.pumpAndSettle();
      expect(store.investigations.last.scenario.toJson(), r.scenario.toJson());
      expect(store.investigations.last.games.length, 8);
      expect(store.investigations.last.simulation.draws, r.simulation.draws);
      expect(store.investigations.last.license, 'Test license');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Evidence to scenario to saved prediction to manual outcome works on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryResearchStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: PlayerInvestigationPage(
              player: simulationGames().last,
              games: simulationGames(),
              store: store,
              metadata: {
                'cutoff': '2026-10-18',
                'currentSeason': 2026,
                'source': 'Test fixture',
                'retrievedAt': '2026-10-19',
                'license': 'Test',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Define the question'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const Key('investigation-line')),
        '100',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('investigation-step-1')),
      );
      await tester.tap(find.byKey(const ValueKey('investigation-step-1')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Conditional replay win rate:'),
        findsOneWidget,
      );
      expect(
        find.textContaining('10000 seeded replays from 8'),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('investigation-workload')),
      );
      await tester.tap(find.byKey(const Key('investigation-workload')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('investigation-step-2')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('investigation-thesis')),
        'Higher usage could persist; efficiency may regress.',
      );
      await tester.ensureVisible(find.byKey(const Key('save-investigation')));
      await tester.tap(find.byKey(const Key('save-investigation')));
      await tester.pumpAndSettle();
      expect(store.investigations.length, 1);
      expect(store.investigations.single.thesis, contains('usage'));
      await tester.ensureVisible(find.text('Record outcome'));
      await tester.tap(find.text('Record outcome'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Final yards'),
        '100',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Result source / reference'),
        'Checked official box score manually',
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Save outcome'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.investigationReviews.length, 1);
      expect(
        store.investigationReviews.values.single.outcome(
          store.investigations.single.scenario,
        ),
        'Push',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
