import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/player_stats_screen.dart';

Map<String, dynamic> _game(
  String id,
  String name,
  String position,
  int season,
  int week,
  num yards, {
  num? touchdowns = 0,
}) => {
  'playerId': id,
  'name': name,
  'position': position,
  'team': id == 'goff' ? 'DET' : 'GB',
  'opponent': 'CHI',
  'season': season,
  'week': week,
  'date': '$season-09-${(week * 3).toString().padLeft(2, '0')}',
  'seasonType': 'REG',
  'stats': {
    'passing_yards': position == 'QB' ? yards : null,
    'passing_tds': touchdowns,
    'attempts': position == 'QB' ? 20 : null,
    'receiving_yards': position == 'WR' ? yards : null,
    'receptions': position == 'WR' ? 5 : null,
  },
};

Map<String, dynamic> _data() => {
  'metadata': {
    'currentSeason': 2026,
    'cutoff': '2026-10-18',
    'source': 'Test box scores',
    'retrievedAt': '2026-10-19T00:00:00Z',
    'license': 'Test fixture',
  },
  'rows': [
    _game('goff', 'Jared Goff', 'QB', 2026, 1, 100),
    _game('goff', 'Jared Goff', 'QB', 2026, 2, 200),
    _game('goff', 'Jared Goff', 'QB', 2026, 4, 300, touchdowns: null),
    _game('goff', 'Jared Goff', 'QB', 2026, 5, 400),
    _game('goff', 'Jared Goff', 'QB', 2025, 1, 50),
    _game('goff', 'Jared Goff', 'QB', 2024, 1, 60),
    _game('goff', 'Jared Goff', 'QB', 2023, 1, 70),
    _game('reed', 'Jayden Reed', 'WR', 2026, 4, 80),
  ],
};

Future<void> _open(WidgetTester tester, Map<String, dynamic> data) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: PlayerStatsScreen(source: Future.value(data)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'player explorer uses the last three appearances and shows complete seasons without narrow overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _open(tester, _data());

      expect(find.text('Last 3 games'), findsOneWidget);
      expect(find.text('900'), findsOneWidget);
      expect(
        find.text('Recent avg 300.0 · available avg 168.6'),
        findsOneWidget,
      );
      expect(find.text('total · 2/3 games recorded'), findsOneWidget);
      expect(find.text('Week 5 · DET vs CHI'), findsOneWidget);
      expect(find.text('Week 4 · DET vs CHI'), findsOneWidget);
      expect(find.text('Week 2 · DET vs CHI'), findsOneWidget);
      expect(find.text('Week 1 · DET vs CHI'), findsNothing);
      expect(find.text('2025 season'), findsOneWidget);
      expect(find.text('2024 season'), findsOneWidget);
      expect(find.text('2023 season'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byKey(const Key('player-averages')));
      await tester.tap(find.byKey(const Key('player-averages')));
      await tester.pumpAndSettle();
      expect(find.text('300.0'), findsOneWidget);
      expect(find.text('avg · 2/3 games recorded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search selects another player and honestly shows a short sample and absent historical seasons',
    (tester) async {
      await _open(tester, _data());
      await tester.enterText(find.byKey(const Key('player-search')), 'Jayden');
      await tester.pumpAndSettle();
      expect(find.text('1 matching players'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('player-result-reed')),
      );
      await tester.tap(find.byKey(const ValueKey('player-result-reed')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('selected-player-name'))).data,
        'Jayden Reed',
      );
      expect(
        find.text('Latest available · regular season · 1 recorded appearance'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Only 1 recorded game is available; no empty games are added.',
        ),
        findsOneWidget,
      );
      expect(find.text('80'), findsNWidgets(2));
      expect(
        find.text(
          'No recorded appearances. This may predate the player’s career or fall outside source coverage.',
        ),
        findsNWidgets(3),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'latest three games span seasons when only two current-season appearances exist',
    (tester) async {
      final data = _data();
      data['rows'] = [
        _game('goff', 'Jared Goff', 'QB', 2026, 1, 100),
        _game('goff', 'Jared Goff', 'QB', 2026, 2, 200),
        _game('goff', 'Jared Goff', 'QB', 2025, 3, 300),
        _game('goff', 'Jared Goff', 'QB', 2025, 2, 400),
      ];
      await _open(tester, data);
      expect(
        find.text('Latest available · regular season · 3 recorded appearances'),
        findsOneWidget,
      );
      expect(find.text('600'), findsOneWidget);
      expect(find.text('2025-09-09'), findsOneWidget);
      expect(find.text('2025-09-06'), findsNothing);
      expect(find.text('Available game log (4)'), findsOneWidget);

      final picker = find.byKey(const ValueKey('player-season-0'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026 · current').last);
      await tester.pumpAndSettle();
      expect(
        find.text('2026 · regular season · 2 recorded appearances'),
        findsOneWidget,
      );
      expect(find.text('2025-09-09'), findsNothing);
      expect(find.text('Recent avg 150.0 · season avg 150.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
