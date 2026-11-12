import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/data/research_store.dart';
import 'package:odds_edge/domain/research.dart';
import 'package:odds_edge/domain/odds.dart';
import 'package:odds_edge/domain/history.dart';
import 'package:odds_edge/main.dart';
import 'package:odds_edge/research_workspace.dart';
import 'package:odds_edge/historical_evidence.dart';

import 'memory_research_store.dart';

void main() {
  testWidgets(
    'NFL evidence loads real bundle and fits a narrow phone with larger text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: SingleChildScrollView(
                key: const PageStorageKey('history-scroll'),
                child: Builder(
                  builder: (context) {
                    // A restored scroll position must not be read as an expansion bool.
                    PageStorage.of(context).writeState(context, 120.0);
                    return HistoricalEvidence(
                      source: Future.value(
                        Map<String, dynamic>.from(
                          jsonDecode(
                            File('assets/nfl-history.json')
                                .readAsStringSync()
                                .replaceFirst('\uFEFF', ''),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Season story. Recent form.'), findsOneWidget);
      expect(find.text('Season to date'), findsNWidgets(2));
      expect(find.text('Latest NFL week'), findsNWidgets(2));
      await tester.ensureVisible(find.text('Last 4 games'));
      await tester.tap(find.text('Last 4 games'));
      await tester.pumpAndSettle();
      expect(find.text('Last 4 played games'), findsNWidgets(2));
      expect(find.text('Most recent played game'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
  final time = DateTime.utc(2026, 10, 18);
  ResearchContext context(double price) => ResearchContext(
    event: SportEvent('event', 'A', 'B', time, sport: 'tennis', league: 'ATP'),
    quote: OddsQuote(
      selection: const Selection(
        eventId: 'event',
        market: 'h2h',
        outcome: 'A',
        rules: 'tennis_retirement_verified',
      ),
      bookId: 'book',
      book: 'Book',
      provider: 'provider',
      decimal: price,
      sourceAt: time,
      collectedAt: time,
    ),
  );
  SavedResearch record({double price = 2.5}) => SavedResearch(
    savedAt: time,
    name: 'My theory',
    thesis: 'A note',
    assumptions: const ResearchAssumptions(),
    context: context(price),
  );
  test('Captured quote and multi-sport context survive serialization; EV uses captured price', () {
    final r = SavedResearch.fromJson(record().toJson());
    expect(r.context.event!.league, 'ATP');
    expect(r.context.quote!.sourceAt, time);
    expect(r.context.quote!.selection.rules, 'tennis_retirement_verified');
    expect(r.ev, closeTo(.2375, 1e-9));
    expect(r.toJson()['dataOrigin'], 'captured_quote_user_assumptions');
    const p = ResearchAssumptions(
      baseProbability: .99,
      push: .5,
      performance: 10,
    );
    expect(p.probability + p.push, lessThan(1));
    expect(p.evAt(2).isFinite, isTrue);
  });
  test('Storage recovers readable entries, drafts and preferences, with exact backup and duplicate-safe import', () async {
    final dir = await Directory.systemTemp.createTemp('odds-flow');
    addTearDown(() => dir.delete(recursive: true));
    final store = ResearchStore(directory: dir);
    await store.save(record());
    final file = File('${dir.path}/odds_edge/research.jsonl');
    await file.writeAsString('{broken', mode: FileMode.append);
    await store.save(record(price: 3));
    final rows = await store.load();
    expect(rows.length, 2);
    expect(store.warnings, isNotEmpty);
    final backup = await store.backup();
    expect(await File(backup).readAsString(), await file.readAsString());
    await store.saveDraft(record());
    await File('${dir.path}/odds_edge/drafts.jsonl')
        .writeAsString('\n{"schema":999}', mode: FileMode.append);
    expect((await store.loadDraft())!.name, 'My theory');
    await store.saveBooks({'book'});
    expect(await ResearchStore(directory: dir).loadBooks(), {'book'});
    final exported = await store.exportJson();
    expect(await store.importJson(exported), 0);
    final before = await file.readAsString();
    expect(() => store.importJson('{"format":"wrong"}'), throwsFormatException);
    expect(await file.readAsString(), before);
    expect((jsonDecode(exported)['records'] as List).length, 2);
  });
  test('Week windows exclude target/future games and do not replace byes with zeros', () {
    HistoricalGame game(int week, int points, {int year = 2026}) =>
        HistoricalGame(
          season: year,
          week: week,
          date: DateTime.utc(year, 9, week),
          home: 'A',
          away: 'B',
          homeScore: points,
          awayScore: 10,
        );
    final games = [
      game(1, 20),
      game(2, 30),
      game(4, 40),
      game(5, 99),
      game(2, 80, year: 2025),
    ];
    final recent = gamesBeforeWeek(games, 'A', 2026, 5, lastWeeks: 3);
    expect(recent.map((g) => g.week), [2, 4]);
    expect(TeamWindow(recent, 'A').pointsFor, 35);
    expect(gamesBeforeWeek(games, 'A', 2026, 4, lastWeeks: 1), isEmpty);
    expect(
      TeamWindow(
        gamesBeforeWeek(games, 'A', 2026, 4, lastWeeks: 1),
        'A',
      ).margin,
      isNull,
    );
    expect(gamesBeforeWeek(games, 'A', 2026, 1), isEmpty);
    expect(recentGames(games, 'A', 2026, 5, 3).map((g) => g.week), [1, 2, 4]);
    expect(recentGames(games, 'A', 2026, 5, 4).length, 3);
    expect(recentGames(games, 'A', 2026, 4, 1).single.week, 2);
    expect(recentGames(games, 'A', 2026, 1, 4), isEmpty);
    expect(recentGames(games, 'unknown', 2026, 5, 4), isEmpty);
    expect(() => recentGames(games, 'A', 2026, 5, 0), throwsArgumentError);
  });
  test('Holdout probability never uses evaluation-season outcomes', () {
    HistoricalGame g(int year, bool homeWin) => HistoricalGame(
      season: year,
      date: time,
      home: 'A',
      away: 'B',
      homeScore: homeWin ? 20 : 10,
      awayScore: 15,
    );
    final a = HistoricalBenchmark([
      g(2022, true),
      g(2023, false),
      g(2024, true),
      g(2025, true),
    ]);
    final b = HistoricalBenchmark([
      g(2022, true),
      g(2023, false),
      g(2024, true),
      g(2025, false),
    ]);
    expect(a.probability, b.probability);
    expect(a.brier, isNot(b.brier));
  });
  testWidgets(
    'Select price, edit, navigate away, recover, save, search and compare',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryResearchStore();
      await tester.pumpWidget(OddsEdgeApp(researchStore: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Odds comparison'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Investigate in Proof Lab'));
      await tester.tap(find.text('Investigate in Proof Lab'));
      await tester.pumpAndSettle();
      expect(find.byType(ResearchWorkspace), findsOneWidget);
      expect(find.textContaining('Investigate '), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'Research name'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Research name'),
        'Test named research',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Research'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Research name'))
            .controller!
            .text,
        'Test named research',
      );
      await tester.ensureVisible(find.text('Save research snapshot'));
      await tester.tap(find.text('Save research snapshot'));
      await tester.pumpAndSettle();
      expect(store.records.length, 1);
      expect(store.records.first.context.quote, isNotNull);
      await tester.ensureVisible(find.text('Research library (1)'));
      await tester.tap(find.text('Research library (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Test named research'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
