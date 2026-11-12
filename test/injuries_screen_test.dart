import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/coach/injuries_screen.dart';
import 'package:odds_edge/domain/injury_report.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/theme/edge_theme.dart';

void main() {
  testWidgets('changes sit on top and link to the game and the props', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.utc(2026, 11, 12, 18);
    final updated = now.subtract(const Duration(minutes: 4));
    String? openedGame;
    String? openedMarket;
    final entry = InjuryEntry(
      player: 'Star Receiver',
      team: 'BUF',
      position: 'WR',
      status: 'Out',
      injury: 'Ankle',
      sourceId: 'espn',
      sourceLabel: 'ESPN, unofficial',
      official: false,
      fetchedAt: now,
      updatedAt: updated,
      agrees: const ['NFL.com'],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: edgeTheme(),
        home: Scaffold(
          body: InjuriesScreen(
            now: now,
            events: [
              SportEvent(
                'buf-kc',
                'Buffalo Bills',
                'Kansas City Chiefs',
                now.add(const Duration(hours: 3)),
              ),
            ],
            report: InjuryReport(
              fetchedAt: now,
              live: true,
              notice: 'ESPN is unofficial and updates first.',
              entries: [entry],
              changes: [
                InjuryChange(
                  player: entry.player,
                  team: entry.team,
                  position: entry.position,
                  status: entry.status,
                  summary: 'Star Receiver moved from Questionable to Out.',
                  removed: false,
                  previousStatus: 'Questionable',
                  entry: entry,
                ),
              ],
              sources: [
                SourceNote(
                  id: 'espn',
                  label: 'ESPN, unofficial',
                  ok: true,
                  fetchedAt: updated,
                ),
              ],
            ),
            onOpenGame: (id) => openedGame = id,
            onOpenMarket: (market) => openedMarket = market,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Updated 4 min ago'), findsWidgets);
    expect(find.text('JUST CHANGED'), findsOneWidget);
    expect(find.byKey(const Key('injury-change')), findsOneWidget);
    expect(
      find.text('Star Receiver moved from Questionable to Out.'),
      findsOneWidget,
    );
    expect(find.text('WR out: lowers QB passing yards.'), findsWidgets);
    expect(find.textContaining('ESPN, unofficial'), findsWidgets);
    expect(find.textContaining('NFL.com agrees'), findsWidgets);

    await tester.tap(find.text('Buffalo Bills at Kansas City Chiefs').first);
    expect(openedGame, 'buf-kc');
    await tester.tap(find.text('Passing yards').first);
    expect(openedMarket, 'player_pass_yds');
  });
}
