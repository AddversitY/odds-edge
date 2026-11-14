import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/games_screen.dart';
import 'package:odds_edge/coach/parlays_screen.dart';
import 'package:odds_edge/coach/props_screen.dart';
import 'package:odds_edge/data/demo.dart';
import 'package:odds_edge/domain/coach_model.dart';
import 'package:odds_edge/domain/injury_report.dart';
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
          injuries: InjuryReport(
            fetchedAt: now,
            live: true,
            notice: 'ESPN is unofficial.',
            entries: [
              InjuryEntry(
                player: 'Top Receiver',
                team: 'BUF',
                position: 'WR',
                status: 'Out',
                injury: 'Ankle',
                sourceId: 'espn',
                sourceLabel: 'ESPN, unofficial',
                official: false,
                fetchedAt: now,
              ),
            ],
            changes: const [],
            sources: [
              SourceNote(
                id: 'espn',
                label: 'ESPN, unofficial',
                ok: true,
                fetchedAt: now,
              ),
            ],
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
    expect(find.text('Review'), findsWidgets);
    expect(find.text('Pass'), findsWidgets);
    expect(find.text('1 out'), findsWidgets);
    await tester.tap(find.text('Josh Allen').first);
    await tester.pumpAndSettle();
    expect(find.text('Evidence at a glance'), findsOneWidget);
    expect(find.text('How we got this'), findsNothing);
    await tester.scrollUntilVisible(find.text('Model and math'), 300);
    await tester.tap(find.text('Model and math'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(TextButton, 'Why').first,
      300,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Why').first);
    await tester.pumpAndSettle();
    expect(find.text('Hide the reason'), findsWidgets);
    expect(find.byKey(const Key('why-brief')), findsWidgets);
    expect(find.textContaining('of last'), findsWidgets);
    expect(find.text('Price'), findsWidgets);
    expect(find.text('Defense'), findsWidgets);
    expect(find.text('Injuries'), findsWidgets);
    expect(find.text('Game script'), findsWidgets);
    expect(find.textContaining('Top Receiver'), findsWidgets);
    expect(find.text('1 out'), findsWidgets);
    expect(find.textContaining('so this is a'), findsNothing);
    expect(find.textContaining('participation'), findsNothing);
    expect(find.textContaining('CC BY 4.0'), findsNothing);
    await tester.tap(find.text('The math').first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining("book's no-vig chance are mixed in"),
      findsWidgets,
    );
    expect(find.textContaining('participation'), findsWidgets);
    expect(find.textContaining('CC BY 4.0'), findsWidgets);
  });

  testWidgets(
    'a parlay card leads with the ticket word and labels an estimate',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.utc(2026, 11, 12);
      final model = (await tester.runAsync(loadBundledCoachModel))!;
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
      expect(find.text('Pass'), findsWidgets);
      await tester.scrollUntilVisible(find.text('SAME GAME'), 400);
      expect(find.text('SAME GAME'), findsOneWidget);
      expect(find.textContaining('Estimated payout'), findsWidgets);
      await tester.scrollUntilVisible(
        find.widgetWithText(TextButton, 'Why').first,
        300,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Why').first);
      await tester.pumpAndSettle();
      expect(find.text('How the legs fit together'), findsWidgets);
    },
  );

  testWidgets('a game side Why is rows, not a paragraph', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 11, 12);
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        home: Scaffold(
          body: GamesScreen(
            board: demoBoard(now),
            now: now,
            injuries: InjuryReport(
              fetchedAt: now,
              live: true,
              notice: 'ESPN is unofficial.',
              entries: [
                InjuryEntry(
                  player: 'Top Receiver',
                  team: 'BUF',
                  position: 'WR',
                  status: 'Out',
                  sourceId: 'espn',
                  sourceLabel: 'ESPN, unofficial',
                  official: false,
                  fetchedAt: now,
                ),
              ],
              changes: const [],
              sources: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 out'), findsWidgets);
    await tester.tap(find.text('Buffalo Bills').first);
    await tester.pumpAndSettle();
    final whys = find.widgetWithText(TextButton, 'Why');
    expect(whys, findsWidgets);
    await tester.ensureVisible(whys.at(1));
    await tester.tap(whys.at(1));
    await tester.pumpAndSettle();
    expect(find.text('Price'), findsWidgets);
    expect(find.text('Injuries'), findsWidgets);
    expect(find.text('Game script'), findsWidgets);
    expect(find.text('Sharp'), findsWidgets);
    expect(find.textContaining('Top Receiver'), findsWidgets);
  });
}
