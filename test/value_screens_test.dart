import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/parlays_screen.dart';
import 'package:odds_edge/coach/props_screen.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/domain/coach_model.dart';
import 'package:odds_edge/domain/matchup.dart';
import 'package:odds_edge/domain/player_stats.dart';
import 'package:odds_edge/theme/edge_theme.dart';

import 'memory_research_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PlayerGame allen(int week, num yards) => PlayerGame(
    playerId: 'allen',
    name: 'Josh Allen',
    position: 'QB',
    team: 'BUF',
    opponent: 'KC',
    season: 2026,
    week: week,
    date: DateTime.utc(2026, 9, week),
    seasonType: 'REG',
    stats: {'passing_yards': yards},
  );

  testWidgets('a prop card leads with a value word and a matchup', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 4200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 11, 12);
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        home: PropsScreen(
          board: demoBoard(now),
          now: now,
          store: MemoryResearchStore(),
          loadPlayers: () async => PlayerStatsDataset(
            rows: [for (var week = 1; week <= 5; week++) allen(week, 260)],
          ),
          loadMatchup: () async => MatchupContext(
            note: MatchupContext.participationNote,
            injuries: const [
              ListedInjury(
                week: 5,
                team: 'BUF',
                player: 'Top Receiver',
                position: 'WR',
                status: 'Out',
                injury: 'Ankle',
              ),
            ],
            snaps: const [
              SnapShare(
                week: 5,
                team: 'BUF',
                opponent: 'KC',
                player: 'Josh Allen',
                position: 'QB',
                offensePct: 0.97,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bet'), findsWidgets);
    expect(find.text('Skip'), findsWidgets);
    expect(find.text('Lean'), findsWidgets);
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Why').first);
    await tester.tap(find.widgetWithText(TextButton, 'Why').first);
    await tester.pumpAndSettle();
    expect(find.text('Hide the reason'), findsWidgets);
    expect(find.textContaining('so this is a'), findsWidgets);
    expect(find.textContaining('participation'), findsWidgets);
    expect(find.textContaining('CC BY 4.0'), findsNothing);
    await tester.tap(find.text('The math').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('CC BY 4.0'), findsWidgets);
  });

  testWidgets(
    'a parlay card leads with the ticket word and labels an estimate',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.utc(2026, 11, 12);
      final model = await loadBundledCoachModel();
      await tester.pumpWidget(
        MaterialApp(
          theme: edgeTheme(),
          home: Scaffold(
            body: ParlaysScreen(
              board: demoBoard(now),
              now: now,
              model: model,
              settings: model.settings,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Skip'), findsWidgets);
      await tester.scrollUntilVisible(find.text('SAME GAME'), 400);
      expect(find.text('SAME GAME'), findsOneWidget);
      expect(find.textContaining('Estimated payout'), findsWidgets);
    },
  );
}
