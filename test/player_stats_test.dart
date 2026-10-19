import 'package:flutter_test/flutter_test.dart';
import 'package:odds_edge/domain/player_stats.dart';

Map<String, dynamic> row({
  String playerId = 'stable-one',
  String name = 'Same Name',
  int season = 2026,
  int week = 1,
  String date = '2026-09-06',
  String team = 'DET',
  String seasonType = 'REG',
  Map<String, num?> stats = const {'receivingYards': 10},
}) => {
  'playerId': playerId,
  'name': name,
  'position': 'WR',
  'team': team,
  'opponent': 'GB',
  'season': season,
  'week': week,
  'date': date,
  'seasonType': seasonType,
  'stats': stats,
};

void main() {
  test(
    'Packed statistics preserve zeros and reject ambiguous metric layouts',
    () {
      final data = PlayerStatsDataset.fromJson({
        'statKeys': ['yards', 'attempts', 'missing'],
        'rows': [
          {
            ...row(),
            'stats': [0, 0, null],
          },
          {
            ...row(week: 2),
            'stats': [21, 2, null],
          },
        ],
      });
      expect(data.rows.first.stats, {
        'yards': 0,
        'attempts': 0,
        'missing': null,
      });
      final window = PlayerStatWindow(data.rows);
      expect(window.average('yards'), 10.5);
      expect(window.observed('yards'), 2);
      expect(window.total('missing'), isNull);
      for (final invalid in [
        {
          'rows': [
            {
              ...row(),
              'stats': [0],
            },
          ],
        },
        {
          'statKeys': ['yards'],
          'rows': [
            {
              ...row(),
              'stats': [0, 1],
            },
          ],
        },
        {
          'statKeys': ['yards', 'yards'],
          'rows': [],
        },
        {
          'statKeys': [''],
          'rows': [],
        },
        {
          'statKeys': ['yards'],
          'rows': [
            {
              ...row(),
              'stats': ['0'],
            },
          ],
        },
        {
          'statKeys': ['yards'],
          'rows': [
            {
              ...row(),
              'stats': [double.nan],
            },
          ],
        },
      ]) {
        expect(
          () => PlayerStatsDataset.fromJson(invalid),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'Most recent games follow recorded appearances, stable IDs and cutoff',
    () {
      final data = PlayerStatsDataset.fromJson({
        'metadata': {'cutoff': '2026-10-18'},
        'rows': [
          row(week: 1),
          row(week: 3, date: '2026-09-20'),
          row(week: 4, date: '2026-09-27', team: 'MIN'),
          row(week: 6, date: '2026-10-11'),
          row(playerId: 'different-person', week: 6, date: '2026-10-11'),
          row(week: 20, date: '2027-01-10', seasonType: 'POST'),
          row(season: 2025, week: 18, date: '2026-01-04'),
        ],
      });
      expect(data.metadata['cutoff'], '2026-10-18');
      expect(
        PlayerStatsDataset.fromJson({
          'cutoff': '2026-10-18',
          'currentSeason': 2026,
          'rows': [],
        }).metadata,
        {'cutoff': '2026-10-18', 'currentSeason': 2026},
      );
      final recent = lastPlayerGames(data.rows, 'stable-one');
      expect(recent.map((game) => game.week), [6, 4, 3]);
      expect(recent.map((game) => game.team), ['DET', 'MIN', 'DET']);
      expect(
        lastPlayerGames(
          data.rows,
          'stable-one',
          through: DateTime(2026, 9, 27, 18),
        ).map((game) => game.week),
        [4, 3, 1],
      );
      expect(playerGames(data.rows, 'stable-one', season: 2025).length, 1);
      expect(
        playerGames(data.rows, 'stable-one', seasonType: 'POST').single.week,
        20,
      );
      expect(lastPlayerGames(data.rows, 'unknown'), isEmpty);
    },
  );

  test(
    'Season summaries preserve zero and use the observed metric denominator',
    () {
      final games = [
        PlayerGame.fromJson(row(stats: {'receivingYards': 0, 'targets': 0})),
        PlayerGame.fromJson(
          row(week: 2, stats: {'receivingYards': 80, 'targets': null}),
        ),
        PlayerGame.fromJson(row(week: 3, stats: {'receivingYards': null})),
      ];
      final window = PlayerStatWindow(games);
      expect(window.gamesCount, 3);
      expect(window.observed('receivingYards'), 2);
      expect(window.total('receivingYards'), 80);
      expect(window.average('receivingYards'), 40);
      expect(window.observed('targets'), 1);
      expect(window.total('targets'), 0);
      expect(window.average('targets'), 0);
      expect(window.observed('unknown'), 0);
      expect(window.total('unknown'), isNull);
      expect(window.average('unknown'), isNull);
      expect(PlayerStatWindow([]).average('receivingYards'), isNull);
      expect(previous3CompletedYears(2026), [2025, 2024, 2023]);
    },
  );

  test('Reject duplicate games, mixed identities and invalid numeric data', () {
    expect(
      () => PlayerStatsDataset.fromJson({
        'rows': [row(), row(team: 'MIN')],
      }),
      throwsFormatException,
    );
    expect(
      () => PlayerStatWindow([
        PlayerGame.fromJson(row()),
        PlayerGame.fromJson(row(playerId: 'different-person')),
      ]),
      throwsArgumentError,
    );
    expect(
      () => PlayerStatWindow([
        PlayerGame.fromJson(row()),
        PlayerGame.fromJson(row()),
      ]),
      throwsArgumentError,
    );
    for (final invalid in [
      row(date: '2026-02-30'),
      row(date: '2026-09-06T12:00:00Z'),
      row(seasonType: 'PRE'),
      row(week: 0),
      row(stats: {'yards': double.nan}),
      row(stats: {'yards': double.infinity}),
      {
        ...row(),
        'stats': {'yards': '12'},
      },
      {...row(), 'playerId': ''},
    ]) {
      expect(() => PlayerGame.fromJson(invalid), throwsFormatException);
    }
    expect(
      () => lastPlayerGames([], 'stable-one', count: 0),
      throwsArgumentError,
    );
  });
}
